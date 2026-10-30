# HTTP API

Base path `/api`. JSON in and out, except uploads (multipart) and agent runs (SSE). FastAPI also serves interactive docs at `/docs`.

Dates are `YYYY-MM-DD`, times `HH:MM`, both in the user's local time.

## Task object

```json
{
  "id": 12,
  "plan_id": 3,
  "title": "DSA practice — graphs",
  "type": "study",
  "date": "2026-10-30",
  "start": "09:30",
  "duration_min": 90,
  "priority": "high",
  "status": "todo",
  "completed_at": null,
  "notes": "Focus on BFS/DFS variants",
  "tags": ["dsa"],
  "checklist": [{"id": 4, "title": "BFS", "done": true, "position": 0}],
  "resources": [{"id": 2, "title": "CP-Algorithms: BFS", "url": "https://…", "kind": "article", "note": "", "added_by": "import"}]
}
```

Every mutation responds with `{"task": {...}, "change_set": {"id": 41, "summary": "Completed #12 …"}}`. The UI uses the Change set id for its Undo toast.

## Tasks

| Method & path | Body / query | Notes |
|---|---|---|
| `GET /tasks` | `start`, `end` (inclusive) | Tasks in a date range |
| `GET /tasks?missed_before=YYYY-MM-DD` | | Pending Tasks dated before the given day |
| `GET /tasks?unscheduled=true` | | Tasks with no date |
| `GET /tasks/{id}` | | |
| `POST /tasks` | Task fields (title required) | Create |
| `PATCH /tasks/{id}` | Any of `title, type, date, start, duration_min, priority, status, notes, tags` | Update |
| `DELETE /tasks/{id}` | | Undoable |
| `POST /tasks/{id}/complete` | | Sets `status=done`, `completed_at=now` |
| `POST /tasks/{id}/uncomplete` | | |
| `POST /tasks/{id}/reschedule` | `{"date": "2026-10-31", "start": "09:00" \| null, "keep_time": true}` | `keep_time` keeps the current start when `start` is omitted |
| `PATCH /checklist/{id}` | `{"done": true}` | |
| `POST /tasks/{id}/resources` | `{"title", "url"?, "kind"?, "note"?}` | |

## History and undo

| Method & path | Notes |
|---|---|
| `GET /history?limit=30` | Recent Change sets: `id, actor, summary, created_at, undone_at, undo_of` |
| `POST /history/{change_set_id}/undo` | Returns the new undo Change set. 409 if already undone or if it is itself an undo |

## Import and export

| Method & path | Body | Response |
|---|---|---|
| `POST /imports/file` | multipart `file` (`.json .yaml .yml .md .csv`, ≤ 2 MB) | `{"plan": {...}, "created": 9, "updated": 0, "unchanged": 0, "change_set": {...}}` |
| `POST /imports/notion` | `{"database_id": "…"}` | Same shape. 400 if `NOTION_TOKEN` is not set |
| `GET /export` | | Planly v1 JSON Plan file containing all Tasks (`Content-Disposition: attachment`) |

Parse and validation errors return 422 `{"detail": "…", "errors": ["tasks[3].date: not a date"]}`.

## State and preferences

| Method & path | Notes |
|---|---|
| `GET /state` | `{"tasks": 42, "done": 10, "missed": 2, "last_change_at": "…", "agent": {"model": "qwen2.5:7b", "reachable": true}, "notion_configured": false, "web_search_enabled": false}` |
| `GET /preferences` | List |
| `DELETE /preferences/{id}` | Undoable |

## Agent

| Method & path | Body | Notes |
|---|---|---|
| `POST /agent/runs` | `{"trigger": "chat", "message": "…", "now": "2026-10-30T10:05"}`<br/>`{"trigger": "task_event", "change_set_ids": [41, 42], "now": "…"}`<br/>`{"trigger": "day_review", "now": "…"}` | `text/event-stream`. Events are listed in [AGENT.md](AGENT.md#streaming-to-the-ui). 409 if a run is already active |
| `GET /agent/thread` | | `{"messages": [{"role": "user" \| "assistant" \| "event" \| "tool", "content": "…", "tool_calls": [...]}]}` |
