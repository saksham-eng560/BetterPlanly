"""Planly v1 plan files (JSON / YAML): parse, validate, and dump (for export)."""

import json
from datetime import date, time
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, FormatChecker

from app.config import get_settings
from app.importers.draft import ChecklistDraft, PlanDraft, PlanParseError, ResourceDraft, TaskDraft
from app.importers.fields import derived_id
from app.models import Task


@lru_cache
def _validator() -> Draft202012Validator:
    schema_path: Path = get_settings().schema_dir / "planly-plan.v1.schema.json"
    return Draft202012Validator(json.loads(schema_path.read_text()), format_checker=FormatChecker())


def _yaml_scalars_to_strings(doc: Any) -> Any:
    """YAML turns 2026-10-30 into a date and 9:30 into 570 (base 60). Undo both for the schema."""
    if not isinstance(doc, dict) or not isinstance(doc.get("tasks"), list):
        return doc
    if isinstance(doc.get("planly"), int):
        doc["planly"] = str(doc["planly"])
    for task in doc["tasks"]:
        if not isinstance(task, dict):
            continue
        if isinstance(task.get("date"), date):
            task["date"] = task["date"].isoformat()
        if isinstance(task.get("start"), int):
            task["start"] = f"{task['start'] // 60:02d}:{task['start'] % 60:02d}"
    return doc


def parse_plan_file(filename: str, text: str, *, is_yaml: bool) -> PlanDraft:
    try:
        doc = _yaml_scalars_to_strings(yaml.safe_load(text)) if is_yaml else json.loads(text)
    except (yaml.YAMLError, json.JSONDecodeError) as exc:
        raise PlanParseError(f"{filename} is not valid {'YAML' if is_yaml else 'JSON'}: {exc}") from exc

    errors = sorted(_validator().iter_errors(doc), key=lambda e: list(e.absolute_path))
    if errors:
        messages = [
            f"{'.'.join(str(p) for p in e.absolute_path) or '(root)'}: {e.message}" for e in errors[:10]
        ]
        raise PlanParseError(f"{filename} is not a valid Planly plan", messages)

    tasks = []
    for raw in doc["tasks"]:
        day = date.fromisoformat(raw["date"]) if raw.get("date") else None
        tasks.append(
            TaskDraft(
                external_id=raw.get("id") or derived_id(day, raw["title"]),
                title=raw["title"].strip(),
                type=raw.get("type", "other"),
                date=day,
                start_time=time.fromisoformat(raw["start"]) if raw.get("start") else None,
                duration_min=raw.get("duration"),
                priority=raw.get("priority", "medium"),
                status=raw.get("status", "todo"),
                notes=raw.get("notes", ""),
                tags=raw.get("tags", []),
                checklist=[
                    ChecklistDraft(item) if isinstance(item, str) else ChecklistDraft(item["title"], item.get("done", False))
                    for item in raw.get("checklist", [])
                ],
                resources=[ResourceDraft(**res) for res in raw.get("resources", [])],
            )
        )
    return PlanDraft(
        source="plan_file", source_ref=filename, title=doc.get("title") or Path(filename).stem, tasks=tasks
    )


def dump_plan(tasks: list[Task], title: str = "Planly export") -> dict[str, Any]:
    """All tasks as a Planly v1 document. Round-trips through parse_plan_file."""
    out = []
    seen: set[str] = set()
    for task in tasks:
        # external ids are only unique per plan; fall back to the Planly id on collision
        task_id = task.external_id if task.external_id and task.external_id not in seen else f"planly-{task.id}"
        seen.add(task_id)
        item: dict[str, Any] = {"id": task_id, "title": task.title, "type": task.type}
        if task.date:
            item["date"] = task.date.isoformat()
        if task.start_time:
            item["start"] = task.start_time.strftime("%H:%M")
        if task.duration_min:
            item["duration"] = task.duration_min
        item["priority"] = task.priority
        item["status"] = task.status
        if task.notes:
            item["notes"] = task.notes
        if task.tags:
            item["tags"] = task.tags
        if task.checklist:
            item["checklist"] = [{"title": c.title, "done": c.done} for c in task.checklist]
        if task.resources:
            item["resources"] = [
                {k: v for k, v in {"title": r.title, "url": r.url, "kind": r.kind, "note": r.note}.items() if v}
                for r in task.resources
            ]
        out.append(item)
    return {"planly": "1", "title": title, "tasks": out}
