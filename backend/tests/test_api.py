import json

import httpx
import pytest
from langchain_core.messages import AIMessage
from sqlalchemy import text

from app.config import Settings
from app.main import create_app
from tests.conftest import REPO_ROOT, TEST_DATABASE_URL
from tests.fakes import ScriptedChatModel, call

SAMPLE = REPO_ROOT / "examples" / "sample-plan.json"
NOW = "2026-10-30T10:05:00+05:30"


@pytest.fixture
async def api(sessionmaker):  # sessionmaker fixture truncates the app tables
    model = ScriptedChatModel(responses=[])
    app = create_app(Settings(database_url=TEST_DATABASE_URL, ollama_base_url="http://127.0.0.1:9"), llm=model)
    async with app.router.lifespan_context(app):
        async with app.state.agent.graph.checkpointer.conn.connection() as conn:
            await conn.execute("TRUNCATE checkpoints, checkpoint_blobs, checkpoint_writes")
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            client.model = model
            yield client


async def upload_sample(api) -> dict:
    response = await api.post("/api/imports/file", files={"file": ("sample-plan.json", SAMPLE.read_bytes())})
    assert response.status_code == 200, response.text
    return response.json()


def parse_sse(body: str) -> list[tuple[str, object]]:
    events = []
    for block in body.strip().split("\n\n"):
        lines = dict(line.split(": ", 1) for line in block.splitlines())
        events.append((lines["event"], json.loads(lines["data"])))
    return events


async def test_upload_lists_and_day_view(api):
    result = await upload_sample(api)
    assert (result["created"], result["plan"]["source"]) == (10, "plan_file")
    day = (await api.get("/api/tasks", params={"start": "2026-10-30", "end": "2026-10-30"})).json()
    assert [t["title"] for t in day][:2] == ["Groceries", "Morning run"]  # Anytime first, then by time
    dsa = next(t for t in day if t["title"].startswith("DSA"))
    assert dsa["start"] == "09:30" and len(dsa["checklist"]) == 3 and len(dsa["resources"]) == 2
    unscheduled = (await api.get("/api/tasks", params={"unscheduled": True})).json()
    assert [t["title"] for t in unscheduled] == ["Brainstorm portfolio project ideas"]
    missed = (await api.get("/api/tasks", params={"missed_before": "2026-10-30"})).json()
    assert [t["title"] for t in missed] == ["Read DDIA chapter 5 — Replication"]


async def test_upload_errors(api):
    bad = await api.post("/api/imports/file", files={"file": ("x.json", b'{"planly": "1", "tasks": [{}]}')})
    assert bad.status_code == 422 and bad.json()["errors"] == ["tasks.0: 'title' is a required property"]
    wrong = await api.post("/api/imports/file", files={"file": ("x.pdf", b"%PDF")})
    assert wrong.status_code == 422 and "Unsupported file type" in wrong.json()["detail"]
    notion = await api.post("/api/imports/notion", json={"database_id": "abc"})
    assert notion.status_code == 400


async def test_tick_move_undo_and_history(api):
    await upload_sample(api)
    tasks = (await api.get("/api/tasks", params={"start": "2026-10-30", "end": "2026-10-30"})).json()
    run = next(t for t in tasks if t["title"] == "Morning run")

    done = (await api.post(f"/api/tasks/{run['id']}/complete")).json()
    assert done["task"]["status"] == "done" and done["change_set"]["summary"].startswith("Completed")

    moved = (await api.post(f"/api/tasks/{run['id']}/reschedule", json={"date": "2026-10-31"})).json()
    assert (moved["task"]["date"], moved["task"]["start"]) == ("2026-10-31", "07:00")

    undo = await api.post(f"/api/history/{moved['change_set']['id']}/undo")
    assert undo.status_code == 200 and undo.json()["undo_of"] == moved["change_set"]["id"]
    assert (await api.get(f"/api/tasks/{run['id']}")).json()["date"] == "2026-10-30"
    again = await api.post(f"/api/history/{moved['change_set']['id']}/undo")
    assert again.status_code == 409

    history = (await api.get("/api/history")).json()
    assert [h["actor"] for h in history][:3] == ["user", "user", "user"] and history[-1]["actor"] == "import"


async def test_create_patch_checklist_resource_delete(api):
    created = await api.post("/api/tasks", json={
        "title": "Write SRS", "type": "work", "date": "2026-10-30", "start": "15:00",
        "duration_min": 45, "checklist": ["Outline", "Draft"],
    })
    assert created.status_code == 201
    task = created.json()["task"]
    patched = (await api.patch(f"/api/tasks/{task['id']}", json={"priority": "high", "start": None})).json()
    assert patched["task"]["priority"] == "high" and patched["task"]["start"] is None
    ticked = (await api.patch(f"/api/checklist/{task['checklist'][0]['id']}", json={"done": True})).json()
    assert ticked["task"]["checklist"][0]["done"] is True
    res = (await api.post(f"/api/tasks/{task['id']}/resources", json={"title": "IEEE 29148", "kind": "doc"})).json()
    assert res["task"]["resources"][0]["title"] == "IEEE 29148"
    assert (await api.patch(f"/api/tasks/{task['id']}", json={"priority": "urgent"})).status_code == 422
    deleted = (await api.delete(f"/api/tasks/{task['id']}")).json()
    assert (await api.get(f"/api/tasks/{task['id']}")).status_code == 404
    await api.post(f"/api/history/{deleted['change_set']['id']}/undo")
    restored = (await api.get(f"/api/tasks/{task['id']}")).json()
    assert [c["done"] for c in restored["checklist"]] == [True, False] and len(restored["resources"]) == 1


async def test_export_roundtrip(api):
    await upload_sample(api)
    exported = await api.get("/api/export")
    assert "attachment" in exported.headers["content-disposition"]
    doc = exported.json()
    assert doc["planly"] == "1" and len(doc["tasks"]) == 10
    reimport = await api.post("/api/imports/file", files={"file": ("backup.json", json.dumps(doc).encode())})
    assert reimport.json()["created"] == 10


async def test_state_and_preferences(api):
    await upload_sample(api)
    state = (await api.get("/api/state", params={"today": "2026-10-30"})).json()
    assert (state["tasks"], state["done"], state["missed"]) == (10, 0, 1)
    assert state["agent"] == {"model": "qwen2.5:7b", "reachable": False, "busy": False}
    assert state["notion_configured"] is False and state["web_search_enabled"] is False
    assert (await api.get("/api/preferences")).json() == []


async def test_agent_run_streams_sse_and_thread(api):
    await upload_sample(api)
    api.model.responses.extend([
        AIMessage(content="", tool_calls=[call("remember_preference", text="No study after 21:00")]),
        AIMessage(content="Got it — no study after 9pm."),
    ])
    response = await api.post("/api/agent/runs", json={"trigger": "chat", "message": "no study after 9pm", "now": NOW})
    assert response.status_code == 200 and response.headers["content-type"].startswith("text/event-stream")
    events = parse_sse(response.text)
    assert events[0] == ("message", {"role": "user", "content": "no study after 9pm"})
    assert ("tool_call", {"name": "remember_preference", "args": {"text": "No study after 21:00"}}) in events
    assert ("token", {"text": "Got it — no study after 9pm."}) in events
    assert events[-2][0] == "changes" and events[-1] == ("done", {})

    thread = (await api.get("/api/agent/thread")).json()["messages"]
    assert [m["role"] for m in thread] == ["user", "assistant", "tool", "assistant"]
    prefs = (await api.get("/api/preferences")).json()
    assert [p["text"] for p in prefs] == ["No study after 21:00"]


async def test_agent_task_event_and_validation(api):
    await upload_sample(api)
    tasks = (await api.get("/api/tasks", params={"start": "2026-10-30", "end": "2026-10-30"})).json()
    done = (await api.post(f"/api/tasks/{tasks[1]['id']}/complete")).json()
    api.model.responses.append(AIMessage(content="Plan still works."))
    response = await api.post("/api/agent/runs", json={
        "trigger": "task_event", "change_set_ids": [done["change_set"]["id"]], "now": NOW,
    })
    first = parse_sse(response.text)[0]
    assert first[1]["role"] == "event" and first[1]["content"].startswith('[update] Completed #')

    missing = await api.post("/api/agent/runs", json={"trigger": "chat", "now": NOW})
    assert missing.status_code == 422


async def test_health(api, engine):
    assert (await api.get("/api/health")).json() == {"ok": True}
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    from tests.conftest import BACKEND_DIR

    head = ScriptDirectory.from_config(Config(str(BACKEND_DIR / "alembic.ini"))).get_current_head()
    async with engine.connect() as conn:  # the test database is migrated to the latest revision
        assert (await conn.execute(text("select version_num from alembic_version"))).scalar() == head
