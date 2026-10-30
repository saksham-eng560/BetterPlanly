"""Deterministic day re-planner. Pure: no I/O, no LLM (ADR-0001).

Fixed tasks (meetings) never move. By default, flexible tasks still ahead of
`now` keep their time; only tasks whose time has passed, missed tasks from
earlier days and clashing tasks are placed into the first free gap. With
`compact=True` (e.g. the user finished early) every timed flexible task is
re-packed from `now`, pulling the day earlier. Whatever doesn't fit before the
end of the day window moves to the next day as an Anytime task.
"""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

PRIORITY_RANK = {"high": 0, "medium": 1, "low": 2}
FIXED_TYPES = {"meeting"}
DEFAULT_DURATION = 30
STEP_MIN = 5


@dataclass(frozen=True)
class Slot:
    task_id: int
    title: str
    type: str
    priority: str
    duration_min: int | None
    start: time | None
    position: int = 0

    @property
    def length(self) -> int:
        return self.duration_min or DEFAULT_DURATION


@dataclass(frozen=True)
class Placement:
    task_id: int
    title: str
    date: date
    start: time | None
    moved_from: tuple[date | None, time | None]


def _minutes(t: time) -> int:
    return t.hour * 60 + t.minute


def _time(minutes: int) -> time:
    return time(minutes // 60, minutes % 60)


def _overlaps(start: int, length: int, busy: list[tuple[int, int]]) -> bool:
    return any(start < end and start + length > begin for begin, end in busy)


def replan(
    day: date,
    tasks: list[Slot],
    *,
    missed: list[tuple[Slot, date]] = (),
    now: datetime | None = None,
    window: tuple[time, time] = (time(8, 0), time(22, 0)),
    compact: bool = False,
) -> list[Placement]:
    """Return a Placement for every task whose date or start changes.

    `tasks`: todo tasks dated `day` (Anytime tasks are left alone).
    `missed`: (task, original_date) pairs from earlier days to bring into `day`.
    """
    window_start, window_end = _minutes(window[0]), _minutes(window[1])
    cursor = window_start
    if now is not None and now.date() == day:
        current = now.hour * 60 + now.minute
        cursor = max(cursor, -(-current // STEP_MIN) * STEP_MIN)  # round up to 5 min
    elif now is not None and now.date() > day:
        cursor = window_end  # the day is over: nothing fits any more

    timed = [t for t in tasks if t.start is not None]
    fixed = [t for t in timed if t.type in FIXED_TYPES]
    flexible = sorted((t for t in timed if t.type not in FIXED_TYPES), key=lambda t: (t.start, t.position))
    busy = [(_minutes(t.start), _minutes(t.start) + t.length) for t in fixed]

    to_place: list[Slot] = []
    for task in flexible:
        start = _minutes(task.start)
        if not compact and start >= cursor and not _overlaps(start, task.length, busy):
            busy.append((start, start + task.length))  # still ahead and free: keep it
        else:
            to_place.append(task)
    to_place.sort(key=lambda t: (PRIORITY_RANK.get(t.priority, 1), _minutes(t.start), t.position))
    to_place += sorted((t for t, _ in missed), key=lambda t: (PRIORITY_RANK.get(t.priority, 1), t.position))

    originals = {t.task_id: (day, t.start) for t in tasks}
    originals.update({t.task_id: (d, t.start) for t, d in missed})

    missed_ids = {t.task_id for t, _ in missed}
    placements = []
    for task in to_place:
        # a clash pushes a task later, never earlier; passed/missed/compact tasks start at `cursor`
        start = cursor if compact or task.task_id in missed_ids else max(cursor, _minutes(task.start))
        for begin, end in sorted(busy):  # slide past every interval we would overlap
            if start < end and start + task.length > begin:
                start = end
        if start + task.length <= window_end:
            busy.append((start, start + task.length))
            target = (day, _time(start))
        else:
            target = (day + timedelta(days=1), None)
        if target != originals[task.task_id]:
            placements.append(Placement(task.task_id, task.title, *target, originals[task.task_id]))
    return placements
