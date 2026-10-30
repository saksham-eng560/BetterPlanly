"""SQLAlchemy models. Only `services.tasks` writes to these tables (ADR-0004).

Defaults are Python-side so snapshots taken right after a flush are complete
without a round-trip refresh.
"""

import datetime as dt
import uuid

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Time,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

TASK_TYPES = ("study", "work", "reading", "fitness", "meeting", "habit", "errand", "personal", "other")
PRIORITIES = ("high", "medium", "low")
STATUSES = ("todo", "done", "skipped")
RESOURCE_KINDS = ("link", "video", "article", "book", "doc", "note")
ACTORS = ("user", "agent", "import")

JsonType = JSON().with_variant(JSONB(), "postgresql")


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


class Base(DeclarativeBase):
    pass


class Plan(Base):
    __tablename__ = "plans"
    __table_args__ = (UniqueConstraint("source", "source_ref"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    source: Mapped[str] = mapped_column(String(20))
    source_ref: Mapped[str] = mapped_column(String(300))
    imported_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Task(Base):
    __tablename__ = "tasks"
    __table_args__ = (
        UniqueConstraint("plan_id", "external_id"),
        Index("ix_tasks_date", "date"),
        Index("ix_tasks_status_date", "status", "date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    plan_id: Mapped[int | None] = mapped_column(ForeignKey("plans.id", ondelete="SET NULL"))
    external_id: Mapped[str | None] = mapped_column(String(300))
    title: Mapped[str] = mapped_column(String(300))
    type: Mapped[str] = mapped_column(String(20), default="other")
    date: Mapped[dt.date | None] = mapped_column(Date)
    start_time: Mapped[dt.time | None] = mapped_column(Time)
    duration_min: Mapped[int | None] = mapped_column(Integer)
    priority: Mapped[str] = mapped_column(String(10), default="medium")
    status: Mapped[str] = mapped_column(String(10), default="todo")
    completed_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))
    notes: Mapped[str] = mapped_column(Text, default="")
    section: Mapped[str | None] = mapped_column(String(100))
    tags: Mapped[list[str]] = mapped_column(JsonType, default=list)
    position: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    checklist: Mapped[list["ChecklistItem"]] = relationship(
        lazy="selectin", order_by="ChecklistItem.position", passive_deletes=True
    )
    resources: Mapped[list["Resource"]] = relationship(
        lazy="selectin", order_by="Resource.id", passive_deletes=True
    )


class ChecklistItem(Base):
    __tablename__ = "checklist_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    task_id: Mapped[int] = mapped_column(ForeignKey("tasks.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(300))
    done: Mapped[bool] = mapped_column(Boolean, default=False)
    position: Mapped[int] = mapped_column(Integer, default=0)


class Resource(Base):
    __tablename__ = "resources"

    id: Mapped[int] = mapped_column(primary_key=True)
    task_id: Mapped[int] = mapped_column(ForeignKey("tasks.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(300))
    url: Mapped[str | None] = mapped_column(String(2000))
    kind: Mapped[str] = mapped_column(String(10), default="link")
    note: Mapped[str] = mapped_column(Text, default="")
    added_by: Mapped[str] = mapped_column(String(10), default="user")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Preference(Base):
    __tablename__ = "preferences"

    id: Mapped[int] = mapped_column(primary_key=True)
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ChangeSet(Base):
    __tablename__ = "change_sets"
    __table_args__ = (Index("ix_change_sets_created_at", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    actor: Mapped[str] = mapped_column(String(10))
    summary: Mapped[str] = mapped_column(Text, default="")
    agent_run_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    undo_of: Mapped[int | None] = mapped_column(ForeignKey("change_sets.id"))
    undone_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Event(Base):
    __tablename__ = "events"

    id: Mapped[int] = mapped_column(primary_key=True)
    change_set_id: Mapped[int] = mapped_column(
        ForeignKey("change_sets.id", ondelete="CASCADE"), index=True
    )
    entity: Mapped[str] = mapped_column(String(20))
    entity_id: Mapped[int] = mapped_column(Integer)
    op: Mapped[str] = mapped_column(String(10))
    before: Mapped[dict | None] = mapped_column(JsonType)
    after: Mapped[dict | None] = mapped_column(JsonType)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
