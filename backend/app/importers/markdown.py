"""Markdown plans and Notion page exports. Rules: docs/PLAN_FORMAT.md#markdown."""

import re
from datetime import date, time
from pathlib import Path

from app.importers.draft import ChecklistDraft, PlanDraft, PlanParseError, ResourceDraft, TaskDraft
from app.importers.fields import derived_id, find_date, normalize_priority, normalize_type, parse_duration

_HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
_MARKUP = re.compile(r"\*\*|__|</?b>|</?strong>")
_LEADING_SYMBOLS = re.compile(r"^[^\w(\[]+")
_SEPARATORS = re.compile(r"^[\s·:,—-]+|[\s·:,—-]+$")
_BOLD_LINE = re.compile(r"^\s*\*\*(.+?)\*\*\s*$")
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


def _clean(text: str) -> str:
    """Drop Notion's bold markup and leading emoji."""
    return _LEADING_SYMBOLS.sub("", _MARKUP.sub("", text)).strip()


def _section_type(section: str | None) -> tuple[str | None, list[str]]:
    """Infer a type (and tags) from the section a task sits in, e.g. Notion study plans."""
    name = (section or "").lower()
    if "leetcode" in name or "problem" in name:
        return "study", ["dsa"]
    if "aiml" in name or "study" in name or "learn" in name or re.search(r"\bdev\b", name):
        return "study", []
    return None, []


def _parse_task_line(text: str, day: date | None, done: bool, section: str | None, today: date) -> TaskDraft:
    text = _MARKUP.sub("", text).strip()
    if found := find_date(text, today):  # "Day 8 · Fri 30 Oct: HTTP and REST" → Fri 30 Oct
        day = found[0]
        before, after = _SEPARATORS.sub("", text[: found[1]]), _SEPARATORS.sub("", text[found[2]:])
        text = " · ".join(part for part in (before, after) if part)
    start = None
    if match := _LEADING_TIME.match(text):
        hour, minute = int(match.group(1)), int(match.group(2))
        if hour < 24 and minute < 60:
            start = time(hour, minute)
            text = text[match.end():]
    tags = _TAG.findall(text)
    text = _TAG.sub("", text).strip()
    title, meta = _split_meta(text)
    kind, section_tags = _section_type(section)
    if kind and "type" not in meta:
        meta["type"] = kind
    return TaskDraft(
        external_id=derived_id(day, title),
        title=title,
        date=day,
        start_time=start,
        status="done" if done else "todo",
        tags=tags + [t for t in section_tags if t not in tags],
        section=section,
        **meta,
    )


def parse_markdown(filename: str, text: str, today: date | None = None) -> PlanDraft:
    today = today or date.today()
    title = Path(filename).stem
    seen_title = False
    day: date | None = None
    section: str | None = None
    saved: tuple[date | None, str | None] | None = None  # context to restore after a callout
    in_aside = aside_named = False
    tasks: list[TaskDraft] = []
    current: TaskDraft | None = None
    notes: list[str] = []

    def finish() -> None:
        if current is not None and notes:
            current.notes = "\n".join(notes).strip()

    for line in text.splitlines():
        if not line.strip():
            continue
        stripped = line.strip()
        if stripped.startswith("<aside"):  # Notion exports callouts as <aside>…</aside>
            finish()
            current, notes, in_aside, aside_named, saved = None, [], True, False, (day, section)
            continue
        if stripped.startswith("</aside"):
            finish()
            current, notes, in_aside = None, [], False
            day, section = saved or (day, section)
            continue
        if in_aside and not aside_named and (bold := _BOLD_LINE.match(line)):
            aside_named = True
            if not find_date(bold.group(1), today):  # a callout's bold first line names its section
                section, day = _clean(bold.group(1)), None
            continue
        if heading := _HEADING.match(line):
            level, content = len(heading.group(1)), heading.group(2)
            if level == 1 and not seen_title and not tasks:
                title, seen_title = _clean(content), True
                continue
            finish()
            current, notes = None, []
            found = find_date(content, today)
            if found:
                day = found[0]  # "LC day 1 · Fri 30 Oct": a date for the tasks below; section unchanged
            else:
                day, section = None, _clean(content) or section
            continue
        if box := _CHECKBOX.match(line):
            indent, mark, content = box.groups()
            if len(indent.expandtabs(4)) < 2:
                aside_named = True
                finish()
                current, notes = _parse_task_line(content.strip(), day, mark != " ", section, today), []
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
                notes.append(_MARKUP.sub("", content))
    finish()

    if not tasks:
        raise PlanParseError(f"{filename} has no tasks — expected '- [ ] …' lines (see docs/PLAN_FORMAT.md)")
    return PlanDraft(source="markdown", source_ref=filename, title=title, tasks=tasks)
