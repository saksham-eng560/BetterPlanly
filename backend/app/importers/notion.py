"""Notion databases, from a CSV export or live through the Notion API.

Both paths map columns/properties by name (docs/PLAN_FORMAT.md#notion) and
produce the same TaskDraft fields.
"""

import csv
import io
import re
from collections.abc import Callable
from typing import Any

import httpx

from app.importers.draft import PlanDraft, PlanParseError, ResourceDraft, TaskDraft
from app.importers.fields import (
    derived_id,
    normalize_priority,
    normalize_status,
    normalize_type,
    parse_duration,
    parse_iso_when,
    parse_notion_when,
)

NOTION_API = "https://api.notion.com/v1"
NOTION_VERSION = "2022-06-28"

COLUMNS: dict[str, tuple[str, ...]] = {
    "title": ("name", "title", "task"),
    "date": ("date", "due", "due date", "when", "scheduled"),
    "type": ("type", "category", "area", "kind"),
    "status": ("status", "done", "completed", "complete"),
    "priority": ("priority",),
    "duration": ("duration", "estimate", "minutes"),
    "notes": ("notes", "description", "details"),
    "url": ("url", "link", "resource"),
    "tags": ("tags", "labels"),
}


def _column_lookup(names: list[str]) -> Callable[[str], str | None]:
    by_lower = {name.strip().lower(): name for name in names}

    def find(field: str) -> str | None:
        return next((by_lower[c] for c in COLUMNS[field] if c in by_lower), None)

    return find


def _draft(title: str, **values: Any) -> TaskDraft:
    url = values.pop("url", None)
    draft = TaskDraft(
        external_id=values.pop("external_id", None) or derived_id(values.get("date"), title),
        title=title,
        type=normalize_type(values.pop("type", None)) or "other",
        priority=normalize_priority(values.pop("priority", None)) or "medium",
        **values,
    )
    if url:
        draft.resources.append(ResourceDraft(title=url, url=url))
    return draft


# ---------- CSV export ----------

def parse_notion_csv(filename: str, text: str) -> PlanDraft:
    reader = csv.DictReader(io.StringIO(text.lstrip("﻿")))
    if not reader.fieldnames:
        raise PlanParseError(f"{filename} is empty")
    find = _column_lookup(list(reader.fieldnames))
    title_col = find("title") or reader.fieldnames[0]
    tasks, errors = [], []

    for row_number, row in enumerate(reader, start=2):
        def cell(field: str) -> str:
            column = find(field)
            return (row.get(column) or "").strip() if column else ""

        title = (row.get(title_col) or "").strip()
        if not title:
            continue
        try:
            day, start, range_minutes = parse_notion_when(cell("date"))
        except ValueError as exc:
            errors.append(f"row {row_number}: {exc}")
            continue
        tasks.append(
            _draft(
                title,
                date=day,
                start_time=start,
                duration_min=parse_duration(cell("duration")) or range_minutes,
                type=cell("type").split(",")[0],
                priority=cell("priority"),
                status=normalize_status(cell("status")),
                notes=cell("notes"),
                tags=[t.strip() for t in cell("tags").split(",") if t.strip()],
                url=cell("url") or None,
            )
        )
    if errors:
        raise PlanParseError(f"{filename} has rows Planly could not read", errors[:10])
    if not tasks:
        raise PlanParseError(f"{filename} has no rows with a title")
    return PlanDraft(source="notion_csv", source_ref=filename, title=filename.rsplit(".", 1)[0], tasks=tasks)


# ---------- live API ----------

def normalize_database_id(value: str) -> str:
    """Accept a raw id, a dashed UUID or a full notion.so URL."""
    hex_ = "[0-9a-fA-F]"
    dashed = re.search(rf"{hex_}{{8}}-{hex_}{{4}}-{hex_}{{4}}-{hex_}{{4}}-{hex_}{{12}}", value)
    if dashed:
        return dashed.group(0).replace("-", "").lower()
    # in URLs the id follows the page slug ("Life-0123…"), so require a non-hex boundary
    match = re.search(rf"(?<!{hex_}){hex_}{{32}}(?!{hex_})", value)
    if not match:
        raise PlanParseError("That doesn't look like a Notion database id (32 hex characters).")
    return match.group(0).lower()


def _plain(prop: dict) -> Any:
    kind = prop.get("type")
    value = prop.get(kind)
    if kind in ("title", "rich_text"):
        return "".join(part.get("plain_text", "") for part in value or [])
    if kind in ("select", "status"):
        return value.get("name") if value else None
    if kind == "multi_select":
        return [option["name"] for option in value or []]
    if kind == "formula" and value:
        return value.get(value.get("type"))
    return value  # date dict, checkbox, number, url


def _page_to_draft(page: dict) -> TaskDraft | None:
    props = page.get("properties", {})
    find = _column_lookup(list(props))
    title_prop = next((p for p in props.values() if p.get("type") == "title"), None)
    title = _plain(title_prop).strip() if title_prop else ""
    if not title:
        return None

    def value(field: str) -> Any:
        name = find(field)
        return _plain(props[name]) if name else None

    when = value("date") or {}
    day, start = parse_iso_when(when.get("start")) if isinstance(when, dict) else (None, None)
    duration = None
    if isinstance(when, dict) and when.get("end") and start is not None:
        end_day, end = parse_iso_when(when["end"])
        if end is not None and end_day == day and end > start:
            duration = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute)
    raw_duration = value("duration")
    raw_type = value("type")
    tags = value("tags")
    return _draft(
        title,
        external_id=page["id"],
        date=day,
        start_time=start,
        duration_min=parse_duration(raw_duration) or duration,
        type=raw_type[0] if isinstance(raw_type, list) and raw_type else raw_type,
        priority=value("priority"),
        status=normalize_status(value("status")),
        notes=value("notes") or "",
        tags=tags if isinstance(tags, list) else [],
        url=value("url"),
    )


async def fetch_notion_database(
    database_id: str, token: str, client: httpx.AsyncClient | None = None
) -> PlanDraft:
    database_id = normalize_database_id(database_id)
    headers = {"Authorization": f"Bearer {token}", "Notion-Version": NOTION_VERSION}
    own_client = client is None
    client = client or httpx.AsyncClient(timeout=30)
    try:
        meta = await client.get(f"{NOTION_API}/databases/{database_id}", headers=headers)
        if meta.status_code in (401, 403, 404):
            raise PlanParseError(
                "Notion refused access. Check NOTION_TOKEN and share the database with your integration."
            )
        meta.raise_for_status()
        title = "".join(t.get("plain_text", "") for t in meta.json().get("title", [])) or "Notion"

        tasks: list[TaskDraft] = []
        body: dict[str, Any] = {"page_size": 100}
        while True:
            response = await client.post(f"{NOTION_API}/databases/{database_id}/query", headers=headers, json=body)
            response.raise_for_status()
            data = response.json()
            tasks.extend(d for d in map(_page_to_draft, data.get("results", [])) if d is not None)
            if not data.get("has_more"):
                break
            body["start_cursor"] = data["next_cursor"]
    except httpx.HTTPError as exc:
        raise PlanParseError(f"Could not reach Notion: {exc}") from exc
    finally:
        if own_client:
            await client.aclose()
    return PlanDraft(source="notion_api", source_ref=database_id, title=title, tasks=tasks)
