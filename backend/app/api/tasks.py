from datetime import date

from fastapi import APIRouter, Query

from app.api.deps import Service
from app.schemas import (
    ChangeSetOut,
    ChecklistPatchIn,
    RescheduleIn,
    ResourceIn,
    TaskChange,
    TaskCreateIn,
    TaskOut,
    TaskPatchIn,
)

router = APIRouter(tags=["tasks"])


def changed(task, change_set) -> TaskChange:
    return TaskChange(task=TaskOut.of(task) if task else None, change_set=ChangeSetOut.of(change_set))


@router.get("/tasks", response_model=list[TaskOut])
async def list_tasks(
    svc: Service,
    start: date | None = None,
    end: date | None = None,
    missed_before: date | None = None,
    unscheduled: bool = Query(False),
):
    tasks = await svc.list_tasks(start, end, missed_before=missed_before, unscheduled=unscheduled)
    return [TaskOut.of(t) for t in tasks]


@router.get("/tasks/{task_id}", response_model=TaskOut)
async def get_task(task_id: int, svc: Service):
    return TaskOut.of(await svc.get_task(task_id))


@router.post("/tasks", response_model=TaskChange, status_code=201)
async def create_task(body: TaskCreateIn, svc: Service):
    data = body.model_dump()
    checklist = data.pop("checklist")
    data["start_time"] = data.pop("start")
    return changed(*await svc.create_task(checklist=checklist, **data))


@router.patch("/tasks/{task_id}", response_model=TaskChange)
async def update_task(task_id: int, body: TaskPatchIn, svc: Service):
    return changed(*await svc.update_task(task_id, **body.fields()))


@router.delete("/tasks/{task_id}", response_model=TaskChange)
async def delete_task(task_id: int, svc: Service):
    return changed(None, await svc.delete_task(task_id))


@router.post("/tasks/{task_id}/complete", response_model=TaskChange)
async def complete(task_id: int, svc: Service):
    return changed(*await svc.complete(task_id))


@router.post("/tasks/{task_id}/uncomplete", response_model=TaskChange)
async def uncomplete(task_id: int, svc: Service):
    return changed(*await svc.uncomplete(task_id))


@router.post("/tasks/{task_id}/reschedule", response_model=TaskChange)
async def reschedule(task_id: int, body: RescheduleIn, svc: Service):
    return changed(*await svc.reschedule(task_id, body.date, body.start, keep_time=body.keep_time))


@router.patch("/checklist/{item_id}", response_model=TaskChange)
async def set_checklist_item(item_id: int, body: ChecklistPatchIn, svc: Service):
    return changed(*await svc.set_checklist_item(item_id, body.done))


@router.post("/tasks/{task_id}/resources", response_model=TaskChange, status_code=201)
async def add_resource(task_id: int, body: ResourceIn, svc: Service):
    return changed(*await svc.add_resource(task_id, body.title, body.url, body.kind, body.note))
