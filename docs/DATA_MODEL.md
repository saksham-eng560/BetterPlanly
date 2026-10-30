# Data model

PostgreSQL 16. App tables are managed by Alembic (`backend/alembic/`); LangGraph's checkpoint tables (`checkpoints`, `checkpoint_blobs`, `checkpoint_writes`, `checkpoint_migrations`) are created by `AsyncPostgresSaver.setup()`.

```mermaid
erDiagram
  plans ||--o{ tasks : "imported into"
  tasks ||--o{ checklist_items : has
  tasks ||--o{ resources : has
  change_sets ||--o{ events : groups
  change_sets |o--o| change_sets : "undo_of"

  plans {
    int id PK
    text title
    text source "plan_file | markdown | notion_csv | notion_api"
    text source_ref "file name or Notion database id"
    timestamptz imported_at
  }
  tasks {
    int id PK
    int plan_id FK "nullable, set null on plan delete"
    text external_id "id in the source, nullable"
    text title
    text type "study|work|reading|fitness|meeting|habit|errand|personal|other"
    date date "nullable = Unscheduled"
    time start_time "nullable = Anytime"
    int duration_min "nullable"
    text priority "high|medium|low"
    text status "todo|done|skipped"
    timestamptz completed_at
    text notes
    jsonb tags
    int position
    timestamptz created_at
    timestamptz updated_at
  }
  checklist_items {
    int id PK
    int task_id FK "cascade"
    text title
    bool done
    int position
  }
  resources {
    int id PK
    int task_id FK "cascade"
    text title
    text url "nullable"
    text kind "link|video|article|book|doc|note"
    text note
    text added_by "user|agent|import"
    timestamptz created_at
  }
  preferences {
    int id PK
    text text
    timestamptz created_at
  }
  change_sets {
    int id PK
    text actor "user|agent|import"
    text summary "human readable"
    uuid agent_run_id "nullable"
    int undo_of FK "nullable"
    timestamptz undone_at "nullable"
    timestamptz created_at
  }
  events {
    int id PK
    int change_set_id FK
    text entity "task|checklist_item|resource|preference"
    int entity_id
    text op "create|update|delete"
    jsonb before "null for create"
    jsonb after "null for delete"
    timestamptz created_at
  }
```

## Rules

- **Uniqueness.** `plans (source, source_ref)` and `tasks (plan_id, external_id)` are unique, which makes re-import an upsert.
- **Events are append-only.** The only later write to the event tables is setting `change_sets.undone_at` when a Change set is undone.
- **Snapshots.** `before`/`after` hold the full column values of the row (dates as ISO strings). For a deleted Task, the snapshot also contains its checklist items and resources, so undo can re-create everything.
- **Undo.** For each Event of a Change set, in reverse order: `create` → delete the entity; `delete` → re-insert from `before` (same id); `update` → write `before` back. The undo is itself a new Change set with `undo_of` set. Undoing an already-undone Change set is rejected (409).
- **Missed** is derived, not stored: `status = 'todo' AND date < :today`.
- **Ordering.** Within a day: `start_time NULLS FIRST, position, id`.
- **Indexes.** `tasks (date)`, `tasks (status, date)`, `events (change_set_id)`, `change_sets (created_at DESC)`, `change_sets (agent_run_id)`.
