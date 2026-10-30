from datetime import date, datetime, time, timedelta, timezone
from typing import Any

import pytest
from langchain_core.messages import AIMessage

from app.agent.runtime import AgentBusy, AgentRuntime
from app.config import Settings
from app.services.tasks import TaskService
from tests.conftest import TEST_DATABASE_URL
from tests.fakes import ScriptedChatModel, call

IST = timezone(timedelta(hours=5, minutes=30))
DAY = date(2026, 10, 30)
NOW = datetime(2026, 10, 30, 10, 5, tzinfo=IST)


@pytest.fixture
def settings() -> Settings:
    return Settings(database_url=TEST_DATABASE_URL, web_search_enabled=False)


@pytest.fixture
async def runtime_factory(settings, sessionmaker):
    opened = []

    async def make(*responses: AIMessage):
        model = ScriptedChatModel(responses=list(responses))
        ctx = AgentRuntime.open(settings, sessionmaker, llm=model)
        runtime = await ctx.__aenter__()
        opened.append(ctx)
        if len(opened) == 1:  # fresh Thread per test; later runtimes share it on purpose
            async with runtime.graph.checkpointer.conn.connection() as conn:
                await conn.execute("TRUNCATE checkpoints, checkpoint_blobs, checkpoint_writes")
        return runtime, model

    yield make
    for ctx in reversed(opened):
        await ctx.__aexit__(None, None, None)


async def collect(stream) -> list[tuple[str, Any]]:
    return [event async for event in stream]


async def test_finishing_early_triggers_replan_and_reports_changes(runtime_factory, session):
    svc = TaskService(session)
    dsa, _ = await svc.create_task(title="DSA practice", type="study", date=DAY, start_time=time(9, 30), duration_min=90)
    await svc.create_task(title="Stand-up", type="meeting", date=DAY, start_time=time(12), duration_min=30)
    read, _ = await svc.create_task(title="Read chapter 4", type="reading", date=DAY, start_time=time(14), duration_min=60)
    async with svc.change_set(f'Completed #{dsa.id} "DSA practice"') as rec:  # completed at 10:05 IST
        await rec.update(dsa, status="done", completed_at=NOW.astimezone(timezone.utc))

    runtime, model = await runtime_factory(
        AIMessage(content="", tool_calls=[call("replan_day", date="2026-10-30", pull_earlier=True)]),
        AIMessage(content="Nice, 55 minutes early! I pulled #3 forward to 10:05."),
    )
    events = await collect(runtime.stream("task_event", NOW, change_set_ids=[rec.change_set.id]))
    kinds = [k for k, _ in events]

    first = events[0][1]
    assert first["role"] == "event" and "finished 55 min early" in first["content"]
    assert "planned 09:30–11:00" in first["content"]
    assert ("tool_call", {"name": "replan_day", "args": {"date": "2026-10-30", "pull_earlier": True}}) in events
    tool_result = next(d for k, d in events if k == "tool_result")
    assert '"Read chapter 4" → Fri 30 Oct 10:05' in tool_result["content"]
    assert "token" in kinds and kinds[-1] == "done"
    changes = next(d for k, d in events if k == "changes")
    assert len(changes) == 1 and changes[0]["summary"] == "Re-planned Fri 30 Oct: moved 1 task"

    moved = await svc.get_task(read.id)
    assert moved.start_time == time(10, 5)
    assert (await svc.history(1))[0].actor == "agent"
    # the model saw the plan context with the completed task, and a system prompt
    system = model.seen[0][0].content
    assert "Now: Friday 2026-10-30 10:05" in system and "DSA practice — done" in system


async def test_chat_tools_create_task_and_remember_preference(runtime_factory, session):
    runtime, _ = await runtime_factory(
        AIMessage(content="", tool_calls=[
            call("create_task", "c1", title="Stretch", type="fitness", date="2026-10-30", start="18:00", duration_min=15),
            call("remember_preference", "c2", text="Workouts in the evening"),
        ]),
        AIMessage(content="Added #1 and noted your preference."),
    )
    events = await collect(runtime.stream("chat", NOW, message="add a stretch at 6pm, I like evening workouts"))
    changes = next(d for k, d in events if k == "changes")
    assert [c["summary"] for c in changes] == [
        'Created #1 "Stretch" on Fri 30 Oct', "Remembered: Workouts in the evening",
    ]
    svc = TaskService(session)
    task = await svc.get_task(1)
    assert (task.type, task.start_time, task.duration_min) == ("fitness", time(18), 15)
    assert [p.text for p in await svc.list_preferences()] == ["Workouts in the evening"]


async def test_tool_errors_go_back_to_the_model(runtime_factory):
    runtime, model = await runtime_factory(
        AIMessage(content="", tool_calls=[call("get_task", task_id=999)]),
        AIMessage(content="I can't find that task."),
    )
    events = await collect(runtime.stream("chat", NOW, message="what is #999?"))
    assert next(d for k, d in events if k == "tool_result")["content"] == "Error: task #999 not found"
    assert model.seen[1][-1].content == "Error: task #999 not found"
    assert next(d for k, d in events if k == "changes") == []


async def test_thread_survives_a_new_runtime(runtime_factory):
    first, _ = await runtime_factory(AIMessage(content="Hello! Your day looks fine."))
    await collect(first.stream("chat", NOW, message="hi"))

    second, model = await runtime_factory(AIMessage(content="You said hi earlier."))
    history = await second.thread()
    assert [m["role"] for m in history] == ["user", "assistant"]
    await collect(second.stream("chat", NOW, message="what did I say?"))
    shown = [m.content for m in model.seen[0][1:]]
    assert shown == ["hi", "Hello! Your day looks fine.", "what did I say?"]


async def test_day_review_lists_missed_tasks(runtime_factory, session):
    svc = TaskService(session)
    await svc.create_task(title="Read DDIA", date=date(2026, 10, 29), start_time=time(20), duration_min=45)
    runtime, _ = await runtime_factory(AIMessage(content="Nothing to do."))
    events = await collect(runtime.stream("day_review", NOW))
    assert events[0][1]["content"].startswith('[day review] 1 missed task: #1 "Read DDIA" (Thu 29 Oct)')


async def test_one_run_at_a_time(runtime_factory):
    runtime, _ = await runtime_factory(AIMessage(content="first"))
    stream = runtime.stream("chat", NOW, message="one")
    await stream.__anext__()
    assert runtime.busy
    with pytest.raises(AgentBusy):
        await runtime.stream("chat", NOW, message="two").__anext__()
    async for _ in stream:
        pass
    assert not runtime.busy


async def test_unreachable_ollama_is_reported(settings, sessionmaker):
    from app.agent.runtime import make_ollama

    settings = settings.model_copy(update={"ollama_base_url": "http://127.0.0.1:9"})
    async with AgentRuntime.open(settings, sessionmaker, llm=make_ollama(settings)) as runtime:
        events = await collect(runtime.stream("chat", NOW, message="hello"))
        assert not await runtime.reachable()
    error = next(d for k, d in events if k == "error")
    assert "Can't reach Ollama at http://127.0.0.1:9" in error["message"]
    assert events[-1][0] == "done"


async def test_resource_and_progress_tools(runtime_factory, session, monkeypatch):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="Learn asyncio", type="study", date=DAY, start_time=time(9), duration_min=60)
    done, _ = await svc.create_task(title="Run", type="fitness", date=DAY)
    await svc.complete(done.id)
    await svc.create_task(title="Old", type="study", date=date(2026, 10, 29))

    runtime, _ = await runtime_factory(
        AIMessage(content="", tool_calls=[
            call("find_resources", "c1", task_id=task.id),
            call("save_resource", "c2", task_id=task.id, title="asyncio docs",
                 url="https://docs.python.org/3/library/asyncio.html", kind="doc"),
            call("evaluate_progress", "c3", start_date="2026-10-29", end_date="2026-10-30"),
        ]),
        AIMessage(content="Saved the docs."),
    )
    events = await collect(runtime.stream("chat", NOW, message="resources for asyncio?"))
    results = {d["name"]: d["content"] for k, d in events if k == "tool_result"}
    assert "Web search is off" in results["find_resources"]
    assert results["save_resource"] == f'Saved "asyncio docs" to #{task.id}'
    assert results["evaluate_progress"].startswith("3 tasks — done 1, todo 1, missed 1, skipped 0; completion 33%")
    saved = (await svc.get_task(task.id)).resources
    assert [(r.title, r.kind, r.added_by) for r in saved] == [("asyncio docs", "doc", "agent")]

    # with web search on, results are appended (the search itself is stubbed)
    import app.agent.tools as tools

    monkeypatch.setattr(tools, "web_search", lambda q, max_results=5: [{"title": f"About {q}", "href": "https://example.org"}])
    runtime.settings.web_search_enabled = True
    find = next(t for t in tools.build_tools(runtime.sessionmaker, runtime.settings) if t.name == "find_resources")
    web = await find.ainvoke(
        {"type": "tool_call", "id": "x", "name": "find_resources",
         "args": {"task_id": task.id, "state": {"run_id": "00000000-0000-0000-0000-000000000000", "now": NOW.isoformat()}}}
    )
    assert "About Learn asyncio — https://example.org" in web.content


async def test_migrations_leave_checkpoint_tables_alone(runtime_factory):
    """Alembic must never manage (or drop) LangGraph's checkpoint tables."""
    from alembic import command
    from alembic.config import Config

    from tests.conftest import BACKEND_DIR, SQLALCHEMY_URL

    await runtime_factory(AIMessage(content="ok"))  # creates the checkpoint tables
    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    cfg.attributes["sqlalchemy_url"] = SQLALCHEMY_URL
    command.check(cfg)  # raises if autogenerate would emit any operation
