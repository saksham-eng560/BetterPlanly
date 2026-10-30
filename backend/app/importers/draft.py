"""The format-independent shape every importer produces."""

from dataclasses import dataclass, field
import datetime as dt


class PlanParseError(ValueError):
    def __init__(self, message: str, errors: list[str] | None = None):
        super().__init__(message)
        self.errors = errors or []


@dataclass
class ResourceDraft:
    title: str
    url: str | None = None
    kind: str = "link"
    note: str = ""


@dataclass
class ChecklistDraft:
    title: str
    done: bool = False


@dataclass
class TaskDraft:
    external_id: str
    title: str
    type: str = "other"
    date: dt.date | None = None
    start_time: dt.time | None = None
    duration_min: int | None = None
    priority: str = "medium"
    status: str = "todo"
    notes: str = ""
    section: str | None = None
    tags: list[str] = field(default_factory=list)
    checklist: list[ChecklistDraft] = field(default_factory=list)
    resources: list[ResourceDraft] = field(default_factory=list)


@dataclass
class PlanDraft:
    source: str  # plan_file | markdown | notion_csv | notion_api
    source_ref: str  # file name or Notion database id
    title: str
    tasks: list[TaskDraft] = field(default_factory=list)
