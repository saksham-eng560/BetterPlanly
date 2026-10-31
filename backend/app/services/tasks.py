"""TaskService: the single writer for tasks, checklist items, resources and preferences.

Every public mutation opens one Change set, records a before/after Event per
entity it touches and commits once (ADR-0004). Undo replays a Change set's
Events backwards. Nothing else in the app writes these tables.
"""

import uuid
from collections.abc import AsyncIterator, Iterable
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import date, datetime, time
from typing import Any

from sqlalchemy import Date, DateTime, Time, and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    PRIORITIES,
    RESOURCE_KINDS,
    STATUSES,
    TASK_TYPES,
    Base,
    ChangeSet,
    ChecklistItem,
    Event,
    Preference,
    Resource,
    Task,
    utcnow,
)

ENTITY_MODELS: dict[str, type[Base]] = {
    "task": Task,
    "checklist_item": ChecklistItem,
    "resource": Resource,
    "preference": Preference,
}
ENTITY_NAMES = {model: name for name, model in ENTITY_MODELS.items()}

EDITABLE_TASK_FIELDS = {
    "title", "type", "date", "start_time", "duration_min", "priority", "status", "notes", "section", "tags",
}


class NotFound(LookupError):
    pass


class Conflict(RuntimeError):
    pass


def snapshot(obj: Base) -> dict[str, Any]:
    """All column values of a row, JSON-safe."""
    out = {}
    for col in obj.__table__.columns:
        value = getattr(obj, col.key)
        if isinstance(value, (date, time, datetime)):
            value = value.isoformat()
        elif isinstance(value, uuid.UUID):
            value = str(value)
        out[col.key] = value
    return out


def _from_snapshot(model: type[Base], snap: dict[str, Any]) -> dict[str, Any]:
    values = {}
    for col in model.__table__.columns:
        if col.key not in snap:
            continue
        value = snap[col.key]
        if value is not None:
            if isinstance(col.type, DateTime):
                value = datetime.fromisoformat(value)
            elif isinstance(col.type, Date):
                value = date.fromisoformat(value)
            elif isinstance(col.type, Time):
                value = time.fromisoformat(value)
        values[col.key] = value
    return values


def normalize_task_fields(fields: dict[str, Any]) -> dict[str, Any]:
    """Coerce loosely-typed values (from LLM tools, imports) into valid column values."""
    out = dict(fields)
    if "type" in out:
        out["type"] = out["type"] if out["type"] in TASK_TYPES else "other"
    if "priority" in out and out["priority"] not in PRIORITIES:
        raise ValueError(f"priority must be one of {PRIORITIES}")
    if "status" in out and out["status"] not in STATUSES:
        raise ValueError(f"status must be one of {STATUSES}")
    if "title" in out:
        out["title"] = (out["title"] or "").strip()
        if not out["title"]:
            raise ValueError("title must not be empty")
    if out.get("duration_min") is not None and out["duration_min"] <= 0:
        raise ValueError("duration_min must be positive")
    return out


def describe_day(d: date | None) -> str:
    return d.strftime("%a %-d %b") if d else "Unscheduled"


def describe_task(task: Task) -> str:
    return f'#{task.id} "{task.title}"'


class Recorder:
    """Writes entities and their Events inside one open Change set."""

    def __init__(self, session: AsyncSession, change_set: ChangeSet):
        self.session = session
        self.change_set = change_set
        self.events = 0

    def _event(self, obj: Base, op: str, before: dict | None, after: dict | None) -> None:
        self.session.add(
            Event(
                change_set_id=self.change_set.id,
                entity=ENTITY_NAMES[type(obj)],
                entity_id=obj.id,
                op=op,
                before=before,
                after=after,
            )
        )
        self.events += 1

    async def create(self, obj: Base) -> Base:
        self.session.add(obj)
        await self.session.flush()
        self._event(obj, "create", None, snapshot(obj))
        return obj

    async def update(self, obj: Base, **fields: Any) -> bool:
        before = snapshot(obj)
        for key, value in fields.items():
            setattr(obj, key, value)
        if snapshot(obj) == before:
            return False
        if hasattr(obj, "updated_at") and "updated_at" not in fields:
            obj.updated_at = utcnow()
        await self.session.flush()
        self._event(obj, "update", before, snapshot(obj))
        return True

    async def delete(self, obj: Base) -> None:
        if isinstance(obj, Task):  # children first, so undo re-creates the parent before them
            for model in (ChecklistItem, Resource):
                rows = await self.session.execute(select(model).where(model.task_id == obj.id))
                for child in rows.scalars():
                    await self.delete(child)
        before = snapshot(obj)
        await self.session.delete(obj)
        await self.session.flush()
        self._event(obj, "delete", before, None)


@dataclass
class Moved:
    task_id: int
    date: date | None
    start: time | None


class TaskService:
    def __init__(
        self,
        session: AsyncSession,
        actor: str = "user",
        agent_run_id: uuid.UUID | None = None,
    ):
        self.session = session
        self.actor = actor
        self.agent_run_id = agent_run_id

    # ---------- change sets ----------

    @asynccontextmanager
    async def change_set(self, summary: str = "", undo_of: int | None = None) -> AsyncIterator[Recorder]:
        """Open a Change set; commit it (or drop it if nothing changed) on exit."""
        cs = ChangeSet(
            actor=self.actor, summary=summary, agent_run_id=self.agent_run_id, undo_of=undo_of
        )
        self.session.add(cs)
        await self.session.flush()
        rec = Recorder(self.session, cs)
        try:
            yield rec
        except BaseException:
            await self.session.rollback()
            raise
        if rec.events == 0 and undo_of is None:
            await self.session.delete(cs)
            rec.change_set = None  # type: ignore[assignment]
        await self.session.commit()

    # ---------- reads ----------

    async def get_task(self, task_id: int) -> Task:
        task = (
            await self.session.execute(
                select(Task).where(Task.id == task_id).execution_options(populate_existing=True)
            )
        ).scalar_one_or_none()
        if task is None:
            raise NotFound(f"task #{task_id} not found")
        return task

    async def list_tasks(
        self,
        start: date | None = None,
        end: date | None = None,
        *,
        missed_before: date | None = None,
        unscheduled: bool = False,
        status: str | None = None,
    ) -> list[Task]:
        query = select(Task).execution_options(populate_existing=True)
        if unscheduled:
            query = query.where(Task.date.is_(None))
        elif missed_before is not None:
            query = query.where(and_(Task.date < missed_before, Task.status == "todo"))
        else:
            if start is not None:
                query = query.where(Task.date >= start)
            if end is not None:
                query = query.where(Task.date <= end)
        if status is not None:
            query = query.where(Task.status == status)
        query = query.order_by(
            Task.date.nulls_last(), Task.start_time.nulls_first(), Task.position, Task.id
        )
        return list((await self.session.execute(query)).scalars())

    async def list_preferences(self) -> list[Preference]:
        return list((await self.session.execute(select(Preference).order_by(Preference.id))).scalars())

    async def history(self, limit: int = 30) -> list[ChangeSet]:
        query = select(ChangeSet).order_by(ChangeSet.id.desc()).limit(limit)
        return list((await self.session.execute(query)).scalars())

    async def change_sets_for_run(self, agent_run_id: uuid.UUID) -> list[ChangeSet]:
        query = select(ChangeSet).where(ChangeSet.agent_run_id == agent_run_id).order_by(ChangeSet.id)
        return list((await self.session.execute(query)).scalars())

    async def get_change_sets(self, ids: Iterable[int]) -> list[ChangeSet]:
        query = select(ChangeSet).where(ChangeSet.id.in_(list(ids))).order_by(ChangeSet.id)
        return list((await self.session.execute(query)).scalars())

    async def events_for(self, change_set_id: int) -> list[Event]:
        query = select(Event).where(Event.change_set_id == change_set_id).order_by(Event.id)
        return list((await self.session.execute(query)).scalars())

    async def last_change_at(self) -> datetime | None:
        return (await self.session.execute(select(func.max(ChangeSet.created_at)))).scalar()

    async def counts(self, today: date) -> dict[str, int]:
        row = (
            await self.session.execute(
                select(
                    func.count(Task.id),
                    func.count(Task.id).filter(Task.status == "done"),
                    func.count(Task.id).filter(and_(Task.status == "todo", Task.date < today)),
                )
            )
        ).one()
        return {"tasks": row[0], "done": row[1], "missed": row[2]}

    # ---------- task mutations ----------

    async def create_task(
        self,
        *,
        checklist: Iterable[str] = (),
        resources: Iterable[dict[str, Any]] = (),
        **fields: Any,
    ) -> tuple[Task, ChangeSet]:
        fields = normalize_task_fields(fields)
        async with self.change_set() as rec:
            task = await rec.create(Task(**fields))
            for i, title in enumerate(checklist):
                await rec.create(ChecklistItem(task_id=task.id, title=title, position=i))
            for res in resources:
                await rec.create(Resource(task_id=task.id, added_by=self.actor, **res))
            rec.change_set.summary = f"Created {describe_task(task)} on {describe_day(task.date)}"
        return await self.get_task(task.id), rec.change_set

    async def update_task(self, task_id: int, **fields: Any) -> tuple[Task, ChangeSet | None]:
        unknown = set(fields) - EDITABLE_TASK_FIELDS
        if unknown:
            raise ValueError(f"cannot update {sorted(unknown)}")
        fields = normalize_task_fields(fields)
        task = await self.get_task(task_id)
        if "status" in fields:
            if fields["status"] == "done" and task.status != "done":
                fields["completed_at"] = utcnow()
            elif fields["status"] != "done":
                fields["completed_at"] = None
        async with self.change_set() as rec:
            await rec.update(task, **fields)
            names = ", ".join(sorted(k for k in fields if k != "completed_at"))
            rec.change_set.summary = f"Updated {describe_task(task)} ({names})"
        return await self.get_task(task_id), rec.change_set

    async def complete(self, task_id: int) -> tuple[Task, ChangeSet | None]:
        task = await self.get_task(task_id)
        async with self.change_set(f"Completed {describe_task(task)}") as rec:
            await rec.update(task, status="done", completed_at=utcnow())
        return await self.get_task(task_id), rec.change_set

    async def uncomplete(self, task_id: int) -> tuple[Task, ChangeSet | None]:
        task = await self.get_task(task_id)
        async with self.change_set(f"Reopened {describe_task(task)}") as rec:
            await rec.update(task, status="todo", completed_at=None)
        return await self.get_task(task_id), rec.change_set

    async def reschedule(
        self,
        task_id: int,
        new_date: date | None,
        start: time | None = None,
        *,
        keep_time: bool = True,
    ) -> tuple[Task, ChangeSet | None]:
        task = await self.get_task(task_id)
        new_start = start if start is not None or not keep_time else task.start_time
        when = describe_day(new_date) + (f" {new_start.strftime('%H:%M')}" if new_start else "")
        async with self.change_set(f"Moved {describe_task(task)} to {when}") as rec:
            await rec.update(task, date=new_date, start_time=new_start)
        return await self.get_task(task_id), rec.change_set

    async def apply_moves(self, moves: Iterable[Moved], summary: str) -> ChangeSet | None:
        """Move many tasks as one Change set (used by the re-planner)."""
        async with self.change_set(summary) as rec:
            for move in moves:
                task = await self.get_task(move.task_id)
                await rec.update(task, date=move.date, start_time=move.start)
        return rec.change_set

    async def delete_task(self, task_id: int) -> ChangeSet:
        task = await self.get_task(task_id)
        async with self.change_set(f"Deleted {describe_task(task)}") as rec:
            await rec.delete(task)
        return rec.change_set

    async def set_checklist_item(self, item_id: int, done: bool) -> tuple[Task, ChangeSet | None]:
        item = await self.session.get(ChecklistItem, item_id)
        if item is None:
            raise NotFound(f"checklist item {item_id} not found")
        verb = "Ticked" if done else "Unticked"
        async with self.change_set(f'{verb} "{item.title}" in #{item.task_id}') as rec:
            await rec.update(item, done=done)
        return await self.get_task(item.task_id), rec.change_set

    async def add_resource(
        self, task_id: int, title: str, url: str | None = None, kind: str = "link", note: str = ""
    ) -> tuple[Task, ChangeSet]:
        task = await self.get_task(task_id)
        kind = kind if kind in RESOURCE_KINDS else "link"
        async with self.change_set(f'Added resource "{title}" to {describe_task(task)}') as rec:
            await rec.create(
                Resource(task_id=task_id, title=title, url=url, kind=kind, note=note, added_by=self.actor)
            )
        return await self.get_task(task_id), rec.change_set

    # ---------- preferences ----------

    async def add_preference(self, text: str) -> tuple[Preference, ChangeSet]:
        async with self.change_set(f"Remembered: {text}") as rec:
            pref = await rec.create(Preference(text=text.strip()))
        return pref, rec.change_set

    async def delete_preference(self, pref_id: int) -> ChangeSet:
        pref = await self.session.get(Preference, pref_id)
        if pref is None:
            raise NotFound(f"preference {pref_id} not found")
        async with self.change_set(f"Forgot: {pref.text}") as rec:
            await rec.delete(pref)
        return rec.change_set

    # ---------- undo ----------

    async def undo(self, change_set_id: int) -> ChangeSet:
        target = await self.session.get(ChangeSet, change_set_id)
        if target is None:
            raise NotFound(f"change set {change_set_id} not found")
        if target.undone_at is not None:
            raise Conflict("already undone")
        if target.undo_of is not None:
            raise Conflict("an undo cannot be undone; make the change again instead")
        events = await self.events_for(change_set_id)
        async with self.change_set(f"Undid: {target.summary}", undo_of=target.id) as rec:
            for ev in reversed(events):
                model = ENTITY_MODELS[ev.entity]
                current = await self.session.get(model, ev.entity_id)
                if ev.op == "create":
                    if current is not None:
                        await rec.delete(current)
                elif ev.op == "delete":
                    if current is None:
                        await rec.create(model(**_from_snapshot(model, ev.before)))
                elif current is not None:
                    await rec.update(current, **_from_snapshot(model, ev.before))
            target.undone_at = utcnow()
        return rec.change_set
