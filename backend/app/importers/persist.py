"""Write a PlanDraft through TaskService as one Change set (re-import = upsert)."""

from dataclasses import dataclass

from sqlalchemy import select

from app.importers.draft import PlanDraft, TaskDraft
from app.models import ChangeSet, ChecklistItem, Plan, Resource, Task, utcnow
from app.services.tasks import TaskService, normalize_task_fields

SOURCE_FIELDS = ("title", "type", "date", "start_time", "duration_min", "priority", "notes", "tags")


@dataclass
class ImportResult:
    plan: Plan
    created: int
    updated: int
    unchanged: int
    change_set: ChangeSet | None


def _dedupe_ids(tasks: list[TaskDraft]) -> None:
    seen: dict[str, int] = {}
    for task in tasks:
        count = seen.get(task.external_id, 0)
        seen[task.external_id] = count + 1
        if count:
            task.external_id = f"{task.external_id}~{count + 1}"


async def persist_draft(svc: TaskService, draft: PlanDraft) -> ImportResult:
    session = svc.session
    _dedupe_ids(draft.tasks)
    plan = (
        await session.execute(select(Plan).where(Plan.source == draft.source, Plan.source_ref == draft.source_ref))
    ).scalar_one_or_none()
    if plan is None:
        plan = Plan(title=draft.title, source=draft.source, source_ref=draft.source_ref)
        session.add(plan)
        await session.flush()
    else:
        plan.title, plan.imported_at = draft.title, utcnow()

    existing = {
        t.external_id: t
        for t in (await session.execute(select(Task).where(Task.plan_id == plan.id))).scalars()
    }
    created = updated = unchanged = 0

    async with svc.change_set() as rec:
        for position, item in enumerate(draft.tasks):
            values = normalize_task_fields({f: getattr(item, f) for f in SOURCE_FIELDS})
            task = existing.get(item.external_id)
            if task is None:
                task = await rec.create(
                    Task(
                        plan_id=plan.id, external_id=item.external_id, position=position, status=item.status,
                        completed_at=utcnow() if item.status == "done" else None, **values,
                    )
                )
                created += 1
                known_checklist, known_resources = set(), set()
            elif task.status == "done":  # never overwrite what the user finished (FR-1.6)
                unchanged += 1
                continue
            else:
                changed = await rec.update(task, position=position, **values)
                if item.status == "done":
                    changed |= await rec.update(task, status="done", completed_at=utcnow())
                known_checklist = {c.title for c in task.checklist}
                known_resources = {r.title for r in task.resources}
                added = False
                for c in item.checklist:
                    added |= c.title not in known_checklist
                for r in item.resources:
                    added |= r.title not in known_resources
                if changed or added:
                    updated += 1
                else:
                    unchanged += 1

            offset = len(known_checklist)
            for c in item.checklist:
                if c.title not in known_checklist:
                    await rec.create(ChecklistItem(task_id=task.id, title=c.title, done=c.done, position=offset))
                    known_checklist.add(c.title)
                    offset += 1
            for r in item.resources:
                if r.title not in known_resources:
                    await rec.create(
                        Resource(task_id=task.id, title=r.title, url=r.url, kind=r.kind, note=r.note, added_by="import")
                    )
                    known_resources.add(r.title)

        rec.change_set.summary = f'Imported "{plan.title}": {created} new, {updated} updated'
    return ImportResult(plan, created, updated, unchanged, rec.change_set)
