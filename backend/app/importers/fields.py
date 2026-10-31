"""Lenient value parsing shared by the Markdown and Notion importers."""

import re
import unicodedata
from datetime import date, datetime, time

from dateutil import parser as dateparser

from app.models import TASK_TYPES

TYPE_SYNONYMS = {
    "gym": "fitness", "exercise": "fitness", "workout": "fitness", "sport": "fitness", "health": "fitness",
    "learning": "study", "learn": "study", "course": "study", "school": "study",
    "read": "reading", "book": "reading", "books": "reading",
    "call": "meeting", "meetings": "meeting", "event": "meeting",
    "habits": "habit", "routine": "habit",
    "chore": "errand", "chores": "errand", "shopping": "errand", "errands": "errand",
    "job": "work", "project": "work", "career": "work",
    "life": "personal", "family": "personal", "home": "personal",
}
PRIORITY_SYNONYMS = {
    "high": "high", "urgent": "high", "p0": "high", "p1": "high", "important": "high",
    "medium": "medium", "normal": "medium", "p2": "medium", "med": "medium",
    "low": "low", "p3": "low", "p4": "low", "someday": "low",
}
DONE_VALUES = {"done", "complete", "completed", "yes", "true", "finished", "✅"}
SKIPPED_VALUES = {"skipped", "cancelled", "canceled", "won't do", "wont do"}

_DURATION = re.compile(r"^(\d+(?:\.\d+)?)\s*(m|min|mins|minutes?|h|hr|hrs|hours?)?$", re.I)
_HAS_TIME = re.compile(r"\d{1,2}:\d{2}|\d\s*(am|pm)\b", re.I)


def normalize_type(value: str | None) -> str | None:
    """Known type or synonym → type; anything else → None (caller decides)."""
    if not value:
        return None
    key = value.strip().lower()
    if key in TASK_TYPES:
        return key
    return TYPE_SYNONYMS.get(key)


def normalize_priority(value: str | None) -> str | None:
    if not value:
        return None
    return PRIORITY_SYNONYMS.get(value.strip().lower())


def normalize_status(value: str | bool | None) -> str:
    if isinstance(value, bool):
        return "done" if value else "todo"
    key = (value or "").strip().lower()
    if key in DONE_VALUES:
        return "done"
    if key in SKIPPED_VALUES:
        return "skipped"
    return "todo"


def parse_duration(value: str | int | float | None) -> int | None:
    """'45m', '1.5h', '90', 90 → minutes. Bare numbers are minutes."""
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return int(value) if value > 0 else None
    match = _DURATION.match(value.strip())
    if not match:
        return None
    amount = float(match.group(1))
    unit = (match.group(2) or "m").lower()
    minutes = amount * 60 if unit.startswith("h") else amount
    return int(round(minutes)) or None


def parse_notion_when(value: str | None) -> tuple[date | None, time | None, int | None]:
    """Parse Notion's exported dates: 'October 30, 2026', 'October 30, 2026 9:30 AM (GMT+5:30)',
    'October 30, 2026 9:30 AM → 11:00 AM', '2026/10/30'. Returns (date, start, duration_min)."""
    if not value or not value.strip():
        return None, None, None
    text = re.sub(r"\(GMT[^)]*\)|\bGMT[+-]\S+", "", value).strip()
    left, _, right = (part.strip() for part in text.partition("→"))
    try:
        start = dateparser.parse(left)
    except (ValueError, OverflowError) as exc:
        raise ValueError(f"unrecognised date {value!r}") from exc
    start_time = start.time().replace(second=0, microsecond=0) if _HAS_TIME.search(left) else None
    duration = None
    if right and start_time is not None:
        try:
            end = dateparser.parse(right, default=start)
        except (ValueError, OverflowError):
            end = None
        if end is not None and end > start:
            duration = int((end - start).total_seconds() // 60)
    return start.date(), start_time, duration


def parse_iso_when(value: str | None) -> tuple[date | None, time | None]:
    """Notion API date strings: '2026-10-30' or '2026-10-30T09:30:00.000+05:30' (wall-clock kept)."""
    if not value:
        return None, None
    if "T" not in value:
        return date.fromisoformat(value), None
    moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return moment.date(), moment.time().replace(second=0, microsecond=0, tzinfo=None)


_MONTHS = ("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
_WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
_MONTH = r"(?P<month>jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"
_WEEKDAY = r"(?:(?P<weekday>mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?,?\s+)?"
_LOOSE_DATE = re.compile(
    rf"\b(?:{_WEEKDAY}(?P<day>\d{{1,2}})(?:st|nd|rd|th)?\s+{_MONTH}"
    rf"|{_WEEKDAY.replace('weekday', 'weekday2')}{_MONTH.replace('month', 'month2')}\s+(?P<day2>\d{{1,2}})(?:st|nd|rd|th)?)\b",
    re.I,
)
_ISO_DATE = re.compile(r"\b(\d{4}-\d{2}-\d{2})\b")


def find_date(text: str, today: date) -> tuple[date, int, int] | None:
    """First date in free text: ISO ('2026-10-30') or without a year ('Fri 30 Oct', 'Oct 30').
    A missing year is inferred from the weekday when there is one, else the year nearest today.
    Returns (date, match start, match end)."""
    if iso := _ISO_DATE.search(text):
        try:
            return date.fromisoformat(iso.group(1)), iso.start(), iso.end()
        except ValueError:
            pass
    for match in _LOOSE_DATE.finditer(text):
        groups = match.groupdict()
        month = _MONTHS.index((groups["month"] or groups["month2"])[:3].lower()) + 1
        day = int(groups["day"] or groups["day2"])
        weekday = groups["weekday"] or groups["weekday2"]
        candidates = []
        for year in (today.year - 1, today.year, today.year + 1):
            try:
                candidates.append(date(year, month, day))
            except ValueError:
                continue
        if weekday:
            matching = [d for d in candidates if d.weekday() == _WEEKDAYS.index(weekday[:3].lower())]
            candidates = matching or candidates
        if candidates:
            return min(candidates, key=lambda d: abs((d - today).days)), match.start(), match.end()
    return None


def slug(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:80] or "task"


def derived_id(day: date | None, title: str) -> str:
    return f"{day.isoformat() if day else 'unscheduled'}:{slug(title)}"
