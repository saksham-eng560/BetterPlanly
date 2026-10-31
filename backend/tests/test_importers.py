import json
from datetime import date, time, timedelta

import httpx
import pytest
import respx

from app.importers import PlanParseError, dump_plan, fetch_notion_database, parse_upload, persist_draft
from app.services.tasks import TaskService
from tests.conftest import FIXTURES, REPO_ROOT

SAMPLE_JSON = REPO_ROOT / "examples" / "sample-plan.json"
SAMPLE_MD = REPO_ROOT / "examples" / "sample-plan.md"


def test_plan_file_json_sample():
    draft = parse_upload("sample-plan.json", SAMPLE_JSON.read_bytes())
    assert draft.source == "plan_file" and draft.title == "Late October sprint"
    dsa = next(t for t in draft.tasks if t.external_id == "dsa-graphs")
    assert (dsa.date, dsa.start_time, dsa.duration_min, dsa.priority) == (date(2026, 10, 30), time(9, 30), 90, "high")
    assert [c.title for c in dsa.checklist] == ["BFS on grid", "Dijkstra with heap", "Review mistakes"]
    assert dsa.resources[0].kind == "article"
    assert draft.tasks[-1].date is None


def test_plan_file_yaml_handles_dates_and_sexagesimal_times():
    draft = parse_upload("plan.yaml", (FIXTURES / "plan.yaml").read_bytes())
    run, read = draft.tasks
    assert run.date == date(2026, 10, 30) and run.start_time == time(7, 5)
    assert read.start_time == time(10, 0) and read.external_id == "unscheduled:read"


def test_plan_file_validation_errors_are_reported():
    bad = json.dumps({"planly": "1", "tasks": [{"title": "x", "date": "tomorrow", "priority": "urgent"}]})
    with pytest.raises(PlanParseError) as err:
        parse_upload("bad.json", bad.encode())
    assert any("tasks.0.date" in e for e in err.value.errors)
    assert any("tasks.0.priority" in e for e in err.value.errors)


def test_markdown_sample():
    draft = parse_upload("sample-plan.md", SAMPLE_MD.read_bytes())
    assert draft.title == "Late October sprint"
    titles = [t.title for t in draft.tasks]
    assert titles == [
        "Morning run", "DSA practice — graphs", "Team stand-up", "Groceries",
        "Learn Python asyncio patterns", "Brainstorm portfolio project ideas",
    ]
    dsa = draft.tasks[1]
    assert (dsa.type, dsa.duration_min, dsa.priority, dsa.start_time) == ("study", 90, "high", time(9, 30))
    assert dsa.tags == ["dsa"] and dsa.notes == "Two medium problems minimum."
    assert [c.title for c in dsa.checklist] == ["BFS on grid", "Dijkstra with heap"]
    assert dsa.resources[0].url.startswith("https://cp-algorithms.com")
    asyncio_task = draft.tasks[4]
    assert asyncio_task.duration_min == 60 and asyncio_task.resources[0].url.endswith("asyncio.html")
    assert draft.tasks[5].date is None and draft.tasks[5].priority == "low"


def test_markdown_keeps_unknown_parenthesis_and_done_marks():
    draft = parse_upload("x.md", b"## 2026-10-30\n- [x] Call (mum) #family\n")
    task = draft.tasks[0]
    assert task.title == "Call (mum)" and task.status == "done" and task.tags == ["family"]


def test_markdown_without_tasks_is_an_error():
    with pytest.raises(PlanParseError):
        parse_upload("notes.md", b"# Notes\njust text\n")


def test_notion_csv_export():
    draft = parse_upload("Tasks.csv", (FIXTURES / "notion-export.csv").read_bytes())
    dsa, gym, blog = draft.tasks
    assert (dsa.date, dsa.start_time, dsa.duration_min) == (date(2026, 10, 30), time(9, 30), 90)
    assert (dsa.type, dsa.priority, dsa.tags) == ("study", "high", ["dsa", "graphs"])
    assert dsa.resources[0].url == "https://cp-algorithms.com" and dsa.notes == "Two problems"
    assert (gym.type, gym.status, gym.start_time) == ("fitness", "done", None)
    assert (blog.type, blog.status, blog.date) == ("other", "todo", None)


def test_unsupported_extension():
    with pytest.raises(PlanParseError):
        parse_upload("plan.docx", b"x")


def _notion_page(page_id, title, start=None, end=None, status=None, kind=None):
    props = {"Task name": {"type": "title", "title": [{"plain_text": title}]}}
    if start:
        props["Due"] = {"type": "date", "date": {"start": start, "end": end}}
    if status:
        props["Status"] = {"type": "status", "status": {"name": status}}
    if kind:
        props["Area"] = {"type": "multi_select", "multi_select": [{"name": kind}]}
    return {"id": page_id, "properties": props}


@respx.mock
async def test_notion_api_paginates_and_maps_properties():
    db = "0123456789abcdef0123456789abcdef"
    respx.get(f"https://api.notion.com/v1/databases/{db}").mock(
        return_value=httpx.Response(200, json={"title": [{"plain_text": "Life OS"}]})
    )
    query = respx.post(f"https://api.notion.com/v1/databases/{db}/query").mock(
        side_effect=[
            httpx.Response(200, json={
                "results": [_notion_page("p1", "Deep work", "2026-10-30T09:00:00.000+05:30",
                                         "2026-10-30T10:30:00.000+05:30", "In progress", "Work")],
                "has_more": True, "next_cursor": "c2",
            }),
            httpx.Response(200, json={
                "results": [_notion_page("p2", "Laundry", "2026-10-31", status="Done"), _notion_page("p3", "")],
                "has_more": False,
            }),
        ]
    )
    draft = await fetch_notion_database(f"https://www.notion.so/me/Life-{db}?v=1", "secret")
    assert draft.title == "Life OS" and draft.source_ref == db
    work, laundry = draft.tasks
    assert (work.external_id, work.start_time, work.duration_min, work.type) == ("p1", time(9), 90, "work")
    assert (laundry.date, laundry.status, laundry.start_time) == (date(2026, 10, 31), "done", None)
    assert json.loads(query.calls[1].request.content)["start_cursor"] == "c2"
    assert query.calls[0].request.headers["Notion-Version"] == "2022-06-28"


@respx.mock
async def test_notion_api_access_denied_is_a_parse_error():
    respx.get(url__regex=r".*/databases/.*").mock(return_value=httpx.Response(404, json={}))
    with pytest.raises(PlanParseError, match="share the database"):
        await fetch_notion_database("0123456789abcdef0123456789abcdef", "bad")


async def test_reimport_updates_in_place_and_respects_done(session):
    svc = TaskService(session, actor="import")
    first = await persist_draft(svc, parse_upload("sample-plan.json", SAMPLE_JSON.read_bytes()))
    assert (first.created, first.updated) == (10, 0) and first.change_set.actor == "import"

    user = TaskService(session)
    run = next(t for t in await user.list_tasks() if t.external_id == "morning-run")
    await user.complete(run.id)

    doc = json.loads(SAMPLE_JSON.read_text())
    for task in doc["tasks"]:
        if task["id"] in ("morning-run", "dsa-graphs"):
            task["title"] += " (edited)"
    second = await persist_draft(svc, parse_upload("sample-plan.json", json.dumps(doc).encode()))
    assert (second.created, second.updated, second.unchanged) == (0, 1, 9)
    titles = {t.external_id: t.title for t in await user.list_tasks()}
    assert titles["dsa-graphs"].endswith("(edited)")
    assert not titles["morning-run"].endswith("(edited)")  # done tasks are left alone

    third = await persist_draft(svc, parse_upload("sample-plan.json", json.dumps(doc).encode()))
    assert third.change_set is None and third.unchanged == 10


async def test_import_undo_and_export_roundtrip(session):
    svc = TaskService(session, actor="import")
    result = await persist_draft(svc, parse_upload("sample-plan.json", SAMPLE_JSON.read_bytes()))
    exported = dump_plan(await svc.list_tasks())
    reparsed = parse_upload("export.json", json.dumps(exported).encode())
    original = parse_upload("sample-plan.json", SAMPLE_JSON.read_bytes())
    key = lambda t: t.external_id  # noqa: E731
    for a, b in zip(sorted(original.tasks, key=key), sorted(reparsed.tasks, key=key)):
        assert (a.title, a.date, a.start_time, a.duration_min, a.type, a.priority) == (
            b.title, b.date, b.start_time, b.duration_min, b.type, b.priority)
        assert [c.title for c in a.checklist] == [c.title for c in b.checklist]
        assert [r.url for r in a.resources] == [r.url for r in b.resources]

    await TaskService(session).undo(result.change_set.id)
    assert await svc.list_tasks() == []


async def test_duplicate_ids_in_one_file_are_disambiguated(session):
    draft = parse_upload("dup.md", b"## 2026-10-30\n- [ ] Stretch\n- [ ] Stretch\n")
    result = await persist_draft(TaskService(session, actor="import"), draft)
    assert result.created == 2


def test_notion_week_page_export():
    """A Notion study-plan page: dates like 'Fri 30 Oct' in task text and headings, sections, callouts."""
    draft = parse_upload("Week 2 · HTTP 40290067.md", (FIXTURES / "notion-week.md").read_bytes(), today=date(2026, 10, 30))
    assert draft.title == "Week 2 · HTTP, async, Pydantic, Git, Docker, SQL"
    by_section: dict[str, list] = {}
    for task in draft.tasks:
        by_section.setdefault(task.section, []).append(task)
    assert list(by_section) == [
        "Goals for this week", "AIML / Dev", "LeetCode list", "Free days (no LC)", "Explore (side quests)",
    ]

    days = by_section["AIML / Dev"]
    assert [t.date for t in days] == [date(2026, 10, 30) + timedelta(days=i) for i in range(7)]
    assert days[0].title == "Day 8 · HTTP and REST" and days[0].type == "study"
    assert days[0].notes.startswith("📺 Learn: YT: Hussein Nasser")
    assert "🛠️ Do: Call a public API" in days[0].notes

    problems = by_section["LeetCode list"]
    assert len(problems) == 15
    assert sorted({t.date for t in problems}) == [date(2026, 10, 30) + timedelta(days=i) for i in range(5)]
    assert sum(t.status == "done" for t in problems) == 3
    assert problems[1].title == "4 Median of Two Sorted Arrays — Hard · 🆕 New · C++"
    assert all(t.type == "study" and "dsa" in t.tags for t in problems)

    free = by_section["Free days (no LC)"]
    assert [t.date for t in free] == [date(2026, 11, 4), date(2026, 11, 5), None]
    assert free[0].title.startswith("AI/dev deep day")
    assert all(t.date is None for t in by_section["Goals for this week"] + by_section["Explore (side quests)"])
    assert by_section["Explore (side quests)"][0].title == "New tech: Install Ollama and run a small local model"


async def test_notion_week_reimport_and_export_keep_sections(session):
    content = (FIXTURES / "notion-week.md").read_bytes()
    svc = TaskService(session, actor="import")
    first = await persist_draft(svc, parse_upload("week2.md", content, today=date(2026, 10, 30)))
    again = await persist_draft(svc, parse_upload("week2.md", content, today=date(2026, 10, 30)))
    assert first.created == 33 and again.change_set is None
    exported = dump_plan(await svc.list_tasks())
    assert {t.get("section") for t in exported["tasks"]} >= {"AIML / Dev", "LeetCode list"}
    assert parse_upload("export.json", json.dumps(exported).encode()).tasks[0].section is not None
