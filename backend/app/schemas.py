"""HTTP request/response shapes (docs/API.md)."""

import datetime as dt
from typing import Literal

from pydantic import BaseModel, Field

from app.models import ChangeSet, Preference, Task

TaskType = Literal["study", "work", "reading", "fitness", "meeting", "habit", "errand", "personal", "other"]
Priority = Literal["high", "medium", "low"]
Status = Literal["todo", "done", "skipped"]
ResourceKind = Literal["link", "video", "article", "book", "doc", "note"]


class ChecklistOut(BaseModel):
    id: int
    title: str
    done: bool
    position: int


class ResourceOut(BaseModel):
    id: int
    title: str
    url: str | None
    kind: str
    note: str
    added_by: str


class TaskOut(BaseModel):
    id: int
    plan_id: int | None
    title: str
    type: str
    date: dt.date | None
    start: str | None
    duration_min: int | None
    priority: str
    status: str
    completed_at: dt.datetime | None
    notes: str
    tags: list[str]
    checklist: list[ChecklistOut]
    resources: list[ResourceOut]

    @classmethod
    def of(cls, task: Task) -> "TaskOut":
        return cls(
            id=task.id, plan_id=task.plan_id, title=task.title, type=task.type, date=task.date,
            start=task.start_time.strftime("%H:%M") if task.start_time else None,
            duration_min=task.duration_min, priority=task.priority, status=task.status,
            completed_at=task.completed_at, notes=task.notes, tags=task.tags or [],
            checklist=[ChecklistOut.model_validate(c, from_attributes=True) for c in task.checklist],
            resources=[ResourceOut.model_validate(r, from_attributes=True) for r in task.resources],
        )


class ChangeSetOut(BaseModel):
    id: int
    actor: str
    summary: str
    created_at: dt.datetime
    undone_at: dt.datetime | None
    undo_of: int | None

    @classmethod
    def of(cls, cs: ChangeSet | None) -> "ChangeSetOut | None":
        return cls.model_validate(cs, from_attributes=True) if cs else None


class TaskChange(BaseModel):
    task: TaskOut | None
    change_set: ChangeSetOut | None


class TaskCreateIn(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    type: TaskType = "other"
    date: dt.date | None = None
    start: dt.time | None = None
    duration_min: int | None = Field(default=None, gt=0, le=1440)
    priority: Priority = "medium"
    notes: str = ""
    tags: list[str] = []
    checklist: list[str] = []


class TaskPatchIn(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=300)
    type: TaskType | None = None
    date: dt.date | None = None
    start: dt.time | None = None
    duration_min: int | None = Field(default=None, gt=0, le=1440)
    priority: Priority | None = None
    status: Status | None = None
    notes: str | None = None
    tags: list[str] | None = None

    def fields(self) -> dict:
        """Only the fields the client sent, with `start` renamed to the column name."""
        data = self.model_dump(exclude_unset=True)
        if "start" in data:
            data["start_time"] = data.pop("start")
        return data


class RescheduleIn(BaseModel):
    date: dt.date | None
    start: dt.time | None = None
    keep_time: bool = True


class ChecklistPatchIn(BaseModel):
    done: bool


class ResourceIn(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    url: str | None = None
    kind: ResourceKind = "link"
    note: str = ""


class PlanOut(BaseModel):
    id: int
    title: str
    source: str
    source_ref: str


class ImportOut(BaseModel):
    plan: PlanOut
    created: int
    updated: int
    unchanged: int
    change_set: ChangeSetOut | None


class NotionImportIn(BaseModel):
    database_id: str = Field(min_length=1)


class PreferenceOut(BaseModel):
    id: int
    text: str
    created_at: dt.datetime

    @classmethod
    def of(cls, pref: Preference) -> "PreferenceOut":
        return cls.model_validate(pref, from_attributes=True)


class AgentStatus(BaseModel):
    model: str
    reachable: bool
    busy: bool


class StateOut(BaseModel):
    tasks: int
    done: int
    missed: int
    last_change_at: dt.datetime | None
    agent: AgentStatus
    notion_configured: bool
    web_search_enabled: bool


class AgentRunIn(BaseModel):
    trigger: Literal["chat", "task_event", "day_review"]
    message: str | None = Field(default=None, max_length=4000)
    change_set_ids: list[int] = []
    now: dt.datetime | None = Field(default=None, description="Browser local time with UTC offset")
