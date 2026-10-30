"""Markdown plans and Notion page exports. Rules: docs/PLAN_FORMAT.md#markdown."""

import re
from datetime import date, time
from pathlib import Path

from app.importers.draft import ChecklistDraft, PlanDraft, PlanParseError, ResourceDraft, TaskDraft
from app.importers.fields import derived_id, normalize_priority, normalize_type, parse_duration

_HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
_DATE = re.compile(r"\b(\d{4}-\d{2}-\d{2})\b")
_CHECKBOX = re.compile(r"^(\s*)[-*+]\s+\[([ xX])\]\s+(.+)$")
_BULLET = re.compile(r"^(\s+)[-*+]\s+(.+)$")
_QUOTE = re.compile(r"^\s*>\s?(.*)$")
_LINK = re.compile(r"^\[([^\]]+)\]\((https?://[^)\s]+)\)\s*(.*)$")
_URL = re.compile(r"^(https?://\S+)\s*(.*)$")
_LEADING_TIME = re.compile(r"^(\d{1,2}):(\d{2})\s+")
_TAG = re.compile(r"(?:^|\s)#([\w-]+)")
_META = re.compile(r"\(([^()]*)\)\s*$")


def _split_meta(text: str) -> tuple[str, dict]:
    """'DSA (study, 90m, high)' → ('DSA', {...}). Leaves the parens if any token is unknown."""
    match = _META.search(text)
    if not match:
        return text, {}
    meta: dict = {}
    for token in (t.strip() for t in match.group(1).split(",") if t.strip()):
        if (minutes := parse_duration(token)) is not None and not token.isdigit():
            meta["duration_min"] = minutes
        elif priority := normalize_priority(token):
            meta["priority"] = priority
        elif kind := normalize_type(token):
            meta["type"] = kind
        else:
            return text, {}
    return text[: match.start()].rstrip(), meta


def _parse_task_line(text: str, day: date | None, done: bool) -> TaskDraft:
    start = None
    if match := _LEADING_TIME.match(text):
        hour, minute = int(match.group(1)), int(match.group(2))
        if hour < 24 and minute < 60:
            start = time(hour, minute)
            text = text[match.end():]
    tags = _TAG.findall(text)
    text = _TAG.sub("", text).strip()
    title, meta = _split_meta(text)
    return TaskDraft(
        external_id=derived_id(day, title),
        title=title,
        date=day,
        start_time=start,
        status="done" if done else "todo",
        tags=tags,
        **meta,
    )


def parse_markdown(filename: str, text: str) -> PlanDraft:
    title = Path(filename).stem
    seen_title = False
    day: date | None = None
    tasks: list[TaskDraft] = []
    current: TaskDraft | None = None
    notes: list[str] = []

    def finish() -> None:
        if current is not None and notes:
            current.notes = "\n".join(notes).strip()

    for line in text.splitlines():
        if not line.strip():
            continue
        if heading := _HEADING.match(line):
            level, content = len(heading.group(1)), heading.group(2)
            if level == 1 and not seen_title and not tasks:
                title, seen_title = content, True
                continue
            finish()
            current, notes = None, []
            found = _DATE.search(content)
            day = date.fromisoformat(found.group(1)) if found else None
            continue
        if box := _CHECKBOX.match(line):
            indent, mark, content = box.groups()
            if len(indent.expandtabs(4)) < 2:
                finish()
                current, notes = _parse_task_line(content.strip(), day, mark != " "), []
                tasks.append(current)
            elif current is not None:
                current.checklist.append(ChecklistDraft(content.strip(), mark != " "))
            continue
        if current is None:
            continue
        if quote := _QUOTE.match(line):
            notes.append(quote.group(1))
        elif bullet := _BULLET.match(line):
            content = bullet.group(2).strip()
            if link := _LINK.match(content):
                current.resources.append(ResourceDraft(link.group(1), link.group(2), note=link.group(3)))
            elif url := _URL.match(content):
                current.resources.append(ResourceDraft(url.group(2) or url.group(1), url.group(1)))
            else:
                notes.append(content)
    finish()

    if not tasks:
        raise PlanParseError(f"{filename} has no tasks — expected '- [ ] …' lines (see docs/PLAN_FORMAT.md)")
    return PlanDraft(source="markdown", source_ref=filename, title=title, tasks=tasks)
