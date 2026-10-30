from datetime import date, time

import pytest

from app.services.tasks import Conflict, Moved, TaskService

D = date(2026, 10, 30)


async def test_create_records_one_change_set_with_events(session):
    svc = TaskService(session)
    task, cs = await svc.create_task(
        title="DSA practice", type="study", date=D, start_time=time(9, 30), duration_min=90,
        checklist=["BFS", "DFS"], resources=[{"title": "CP-Algorithms", "url": "https://cp-algorithms.com"}],
    )
    assert task.id == 1 and [c.title for c in task.checklist] == ["BFS", "DFS"]
    assert task.resources[0].added_by == "user"
    events = await svc.events_for(cs.id)
    assert [(e.entity, e.op) for e in events] == [
        ("task", "create"), ("checklist_item", "create"), ("checklist_item", "create"), ("resource", "create"),
    ]
    assert cs.actor == "user" and cs.summary == 'Created #1 "DSA practice" on Fri 30 Oct'


async def test_unknown_type_becomes_other_and_bad_priority_rejected(session):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="Mystery", type="spaceflight")
    assert task.type == "other"
    with pytest.raises(ValueError):
        await svc.create_task(title="x", priority="urgent")


async def test_complete_then_undo_restores_previous_state(session):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="Run", date=D)
    done, cs = await svc.complete(task.id)
    assert done.status == "done" and done.completed_at is not None
    await svc.undo(cs.id)
    reopened = await svc.get_task(task.id)
    assert reopened.status == "todo" and reopened.completed_at is None
    with pytest.raises(Conflict):
        await svc.undo(cs.id)


async def test_noop_update_creates_no_change_set(session):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="Read", priority="low")
    _, cs = await svc.update_task(task.id, priority="low")
    assert cs is None
    assert len(await svc.history()) == 1


async def test_reschedule_keeps_time_unless_told_otherwise(session):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="Gym", date=D, start_time=time(7, 0))
    moved, cs = await svc.reschedule(task.id, date(2026, 10, 31))
    assert moved.date == date(2026, 10, 31) and moved.start_time == time(7, 0)
    assert cs.summary == 'Moved #1 "Gym" to Sat 31 Oct 07:00'
    moved, _ = await svc.reschedule(task.id, date(2026, 11, 2), keep_time=False)
    assert moved.start_time is None


async def test_delete_and_undo_recreates_task_with_children(session):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="Ship", checklist=["a", "b"], resources=[{"title": "doc"}])
    cs = await svc.delete_task(task.id)
    await svc.undo(cs.id)
    back = await svc.get_task(task.id)
    assert back.title == "Ship"
    assert [c.title for c in back.checklist] == ["a", "b"]
    assert [r.title for r in back.resources] == ["doc"]


async def test_undo_of_create_removes_task_and_children(session):
    svc = TaskService(session)
    task, cs = await svc.create_task(title="Temp", checklist=["x"])
    await svc.undo(cs.id)
    assert await svc.list_tasks() == []


async def test_agent_change_sets_are_tagged_with_run(session):
    import uuid

    run = uuid.uuid4()
    user = TaskService(session)
    t1, _ = await user.create_task(title="A", date=D, start_time=time(9))
    t2, _ = await user.create_task(title="B", date=D, start_time=time(10))
    agent = TaskService(session, actor="agent", agent_run_id=run)
    cs = await agent.apply_moves(
        [Moved(t1.id, D, time(11)), Moved(t2.id, date(2026, 10, 31), None)], "Re-planned Fri 30 Oct"
    )
    assert [c.id for c in await user.change_sets_for_run(run)] == [cs.id]
    assert cs.actor == "agent"
    await user.undo(cs.id)
    assert (await user.get_task(t1.id)).start_time == time(9)
    assert (await user.get_task(t2.id)).date == D


async def test_list_views(session):
    svc = TaskService(session)
    await svc.create_task(title="old", date=date(2026, 10, 28))
    old_done, _ = await svc.create_task(title="old done", date=date(2026, 10, 28))
    await svc.complete(old_done.id)
    await svc.create_task(title="today b", date=D, start_time=time(10))
    await svc.create_task(title="today anytime", date=D)
    await svc.create_task(title="today a", date=D, start_time=time(9))
    await svc.create_task(title="someday")
    assert [t.title for t in await svc.list_tasks(D, D)] == ["today anytime", "today a", "today b"]
    assert [t.title for t in await svc.list_tasks(missed_before=D)] == ["old"]
    assert [t.title for t in await svc.list_tasks(unscheduled=True)] == ["someday"]


async def test_checklist_and_preferences(session):
    svc = TaskService(session)
    task, _ = await svc.create_task(title="T", checklist=["step"])
    updated, cs = await svc.set_checklist_item(task.checklist[0].id, True)
    assert updated.checklist[0].done and cs.summary == 'Ticked "step" in #1'
    pref, _ = await svc.add_preference("  No study after 9pm ")
    assert pref.text == "No study after 9pm"
    cs = await svc.delete_preference(pref.id)
    assert await svc.list_preferences() == []
    await svc.undo(cs.id)
    assert [p.text for p in await svc.list_preferences()] == ["No study after 9pm"]
