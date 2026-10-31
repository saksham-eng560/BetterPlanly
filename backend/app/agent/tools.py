"""Agent tools: thin wrappers over TaskService (actor="agent"), one Change set per call.

Tools return short plain text, because that is what small local models read best.
"""

import asyncio
import functools
import uuid
from collections import Counter
from collections.abc import Callable
from datetime import date, datetime, time, timedelta
from typing import Annotated, Any

from langchain_core.tools import BaseTool, tool
from langgraph.prebuilt import InjectedState
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.agent.scheduler import Slot, replan
from app.config import Settings
from app.models import Task
from app.services.tasks import Moved, NotFound, TaskService, describe_day

MAX_LISTED = 60


def format_task(task: Task) -> str:
    when = describe_day(task.date)
    if task.start_time:
        when += f" {task.start_time.strftime('%H:%M')}"
        if task.duration_min:
            end = datetime.combine(date.min, task.start_time) + timedelta(minutes=task.duration_min)
            when += f"–{end.strftime('%H:%M')}"
    elif task.date:
        when += " anytime"
    if task.duration_min and not task.start_time:
        when += f" ({task.duration_min}m)"
    group = f" · {task.section}" if task.section else ""
    return f"#{task.id} {when} [{task.type}, {task.priority}{group}] {task.title} — {task.status}"


def local_now(state: dict) -> datetime:
    """The browser's wall-clock time for this run (naive)."""
    return datetime.fromisoformat(state["now"]).replace(tzinfo=None)


def _date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"'{value}' is not a date; use YYYY-MM-DD") from exc


def _time(value: str | None) -> time | None:
    if not value:
        return None
    try:
        return time.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"'{value}' is not a time; use HH:MM") from exc


def to_slot(task: Task) -> Slot:
    return Slot(task.id, task.title, task.type, task.priority, task.duration_min, task.start_time, task.position)


def build_tools(sessionmaker: async_sessionmaker[AsyncSession], settings: Settings) -> list[BaseTool]:
    def service(session: AsyncSession, state: dict) -> TaskService:
        return TaskService(session, actor="agent", agent_run_id=uuid.UUID(state["run_id"]))

    def guarded(fn: Callable) -> Callable:
        """Turn expected errors into messages the model can read and recover from."""
        @functools.wraps(fn)
        async def wrapper(*args: Any, **kwargs: Any) -> str:
            try:
                return await fn(*args, **kwargs)
            except (NotFound, ValueError) as exc:
                return f"Error: {exc}"
        return wrapper

    @tool
    @guarded
    async def list_tasks(
        start_date: str, end_date: str, status: str | None = None, *, state: Annotated[dict, InjectedState]
    ) -> str:
        """List tasks dated between start_date and end_date (inclusive, YYYY-MM-DD). Optional status: todo, done or skipped."""
        async with sessionmaker() as session:
            tasks = await service(session, state).list_tasks(_date(start_date), _date(end_date), status=status)
        if not tasks:
            return "No tasks in that range."
        lines = [format_task(t) for t in tasks[:MAX_LISTED]]
        if len(tasks) > MAX_LISTED:
            lines.append(f"…and {len(tasks) - MAX_LISTED} more")
        return "\n".join(lines)

    @tool
    @guarded
    async def get_task(task_id: int, *, state: Annotated[dict, InjectedState]) -> str:
        """Get one task with its notes, checklist and resources."""
        async with sessionmaker() as session:
            task = await service(session, state).get_task(task_id)
        lines = [format_task(task)]
        if task.notes:
            lines.append(f"Notes: {task.notes}")
        lines += [f"  [{'x' if c.done else ' '}] {c.title}" for c in task.checklist]
        lines += [f"  resource: {r.title}{' — ' + r.url if r.url else ''} ({r.kind})" for r in task.resources]
        return "\n".join(lines)

    @tool
    @guarded
    async def create_task(
        title: str,
        type: str = "other",
        date: str | None = None,
        start: str | None = None,
        duration_min: int | None = None,
        priority: str = "medium",
        notes: str = "",
        *,
        state: Annotated[dict, InjectedState],
    ) -> str:
        """Create a task. type: study, work, reading, fitness, meeting, habit, errand, personal or other.
        date YYYY-MM-DD (omit for unscheduled), start HH:MM (omit for anytime), priority high/medium/low."""
        async with sessionmaker() as session:
            task, _ = await service(session, state).create_task(
                title=title, type=type, date=_date(date) if date else None, start_time=_time(start),
                duration_min=duration_min, priority=priority, notes=notes,
            )
        return f"Created {format_task(task)}"

    @tool
    @guarded
    async def update_task(
        task_id: int,
        title: str | None = None,
        type: str | None = None,
        duration_min: int | None = None,
        priority: str | None = None,
        notes: str | None = None,
        status: str | None = None,
        *,
        state: Annotated[dict, InjectedState],
    ) -> str:
        """Change a task's fields. Only pass what should change. status: todo, done or skipped.
        Use reschedule_task to change its date or time."""
        fields = {
            k: v for k, v in dict(
                title=title, type=type, duration_min=duration_min, priority=priority, notes=notes, status=status
            ).items() if v is not None
        }
        if not fields:
            return "Nothing to change."
        async with sessionmaker() as session:
            task, cs = await service(session, state).update_task(task_id, **fields)
        return f"Updated {format_task(task)}" if cs else f"No change: {format_task(task)}"

    @tool
    @guarded
    async def reschedule_task(
        task_id: int, date: str, start: str | None = None, *, state: Annotated[dict, InjectedState]
    ) -> str:
        """Move a task to another date (YYYY-MM-DD). Pass start (HH:MM) to set a time; omit it to keep the current time."""
        async with sessionmaker() as session:
            task, _ = await service(session, state).reschedule(task_id, _date(date), _time(start))
        return f"Moved {format_task(task)}"

    @tool
    @guarded
    async def replan_day(date: str, pull_earlier: bool = False, *, state: Annotated[dict, InjectedState]) -> str:
        """Re-plan a day with the scheduler: missed tasks (when date is today), tasks whose time has passed and
        clashing tasks are moved to free slots; what doesn't fit moves to the next day. Meetings never move.
        Set pull_earlier=true when the user finished early and wants the rest of the day pulled forward."""
        day, now = _date(date), local_now(state)
        async with sessionmaker() as session:
            svc = service(session, state)
            tasks = await svc.list_tasks(day, day, status="todo")
            missed = await svc.list_tasks(missed_before=day) if day == now.date() else []
            placements = replan(
                day, [to_slot(t) for t in tasks], missed=[(to_slot(t), t.date) for t in missed],
                now=now, window=(settings.day_start, settings.day_end), compact=pull_earlier,
            )
            if not placements:
                return f"{describe_day(day)} already works; nothing moved."
            await svc.apply_moves(
                [Moved(p.task_id, p.date, p.start) for p in placements],
                f"Re-planned {describe_day(day)}: moved {len(placements)} task{'s' * (len(placements) != 1)}",
            )
        return "Moved:\n" + "\n".join(
            f'#{p.task_id} "{p.title}" → {describe_day(p.date)}{" " + p.start.strftime("%H:%M") if p.start else " anytime"}'
            for p in placements
        )

    @tool
    @guarded
    async def find_resources(task_id: int, query: str | None = None, *, state: Annotated[dict, InjectedState]) -> str:
        """Find resources for a task: its saved resources, plus web results if web search is enabled.
        Save the useful ones with save_resource."""
        async with sessionmaker() as session:
            task = await service(session, state).get_task(task_id)
        lines = [f"Saved for #{task.id}:"] + (
            [f"- {r.title}{' — ' + r.url if r.url else ''}" for r in task.resources] or ["- (none)"]
        )
        if not settings.web_search_enabled:
            lines.append("Web search is off. Suggest well-known resources from your own knowledge instead.")
            return "\n".join(lines)
        results = await asyncio.to_thread(web_search, query or task.title)
        lines.append("Web results:")
        lines += [f"- {r['title']} — {r['href']}" for r in results] or ["- (no results)"]
        return "\n".join(lines)

    @tool
    @guarded
    async def save_resource(
        task_id: int, title: str, url: str | None = None, kind: str = "link", note: str = "",
        *, state: Annotated[dict, InjectedState],
    ) -> str:
        """Attach a resource to a task. kind: link, video, article, book, doc or note."""
        async with sessionmaker() as session:
            task, _ = await service(session, state).add_resource(task_id, title, url, kind, note)
        return f'Saved "{title}" to #{task.id}'

    @tool
    @guarded
    async def evaluate_progress(start_date: str, end_date: str, *, state: Annotated[dict, InjectedState]) -> str:
        """Completion stats between two dates (inclusive): done, todo, skipped and missed, overall and by type."""
        today = local_now(state).date()
        async with sessionmaker() as session:
            tasks = await service(session, state).list_tasks(_date(start_date), _date(end_date))
        if not tasks:
            return "No tasks in that range."
        status = Counter("missed" if t.status == "todo" and t.date < today else t.status for t in tasks)
        by_type = Counter((t.type, t.status) for t in tasks)
        rate = round(100 * status["done"] / len(tasks))
        types = sorted({t.type for t in tasks})
        per_type = ", ".join(f"{k}: {by_type[(k, 'done')]}/{sum(by_type[(k, s)] for s in ('done', 'todo', 'skipped'))}" for k in types)
        return (
            f"{len(tasks)} tasks — done {status['done']}, todo {status['todo']}, missed {status['missed']}, "
            f"skipped {status['skipped']}; completion {rate}%.\nDone by type: {per_type}"
        )

    @tool
    @guarded
    async def remember_preference(text: str, *, state: Annotated[dict, InjectedState]) -> str:
        """Store a lasting preference the user stated (e.g. 'No study after 21:00'). It is shown to you in every later conversation."""
        async with sessionmaker() as session:
            await service(session, state).add_preference(text)
        return f"Remembered: {text}"

    return [
        list_tasks, get_task, create_task, update_task, reschedule_task, replan_day,
        find_resources, save_resource, evaluate_progress, remember_preference,
    ]


def web_search(query: str, max_results: int = 5) -> list[dict]:
    from ddgs import DDGS

    try:
        return list(DDGS().text(query, max_results=max_results))
    except Exception:  # network errors, rate limits: the agent just gets no results
        return []
