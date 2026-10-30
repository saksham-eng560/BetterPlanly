# Planly — build plan

## Context
`saksham-eng560/BetterPlanly` is empty (branch `claude/loving-tesla-wjhdp4`, no commits). Goal: a personal planner website where tasks come in from Notion or from a plan file that any AI agent can generate. The page has three areas:
- **Centre:** the day's tasks, shown as cards that differ by type.
- **Below it:** a checklist. Each row can be ticked, moved to another day, or opened to see its resources.
- **Side chat:** a custom LangGraph agent running on a local Ollama model. It notices ticks, misses and early finishes, then re-plans, searches and organises.

All state is kept in Postgres and can be exported. You also asked for an SRS and related documents, and a graphify graph of the finished repo.

Your decisions: **Ollama** · **Notion API + export upload** · **resources offline-first, with optional web search** · **skills vendored in `.claude/skills/`**.

## Step 0: gate before implementing
- Check that `/karpathy-guidelines`, `/improve-codebase-architecture`, `/apple-design` and `/emil-design-eng` now appear in the skill list. If any is missing, say so and stop.
- When each skill is loaded:
  - karpathy-guidelines: at the start, to review the prompt and break the project down.
  - improve-codebase-architecture: after the backend skeleton, and again before finishing.
  - apple-design and emil-design-eng: before any frontend work.
- graphify: `pip install graphifyy`, then `graphify install` to register the skill, then run `/graphify` at the end.
- Toolchain is already in the container: Python 3.13, Node 22, Postgres 16 (start the cluster with `pg_ctlcluster 16 main start`), and pip/npm registries.

## Repository layout
```
docs/      SRS.md, ARCHITECTURE.md, DATA_MODEL.md, AGENT.md, API.md, PLAN_FORMAT.md,
           UI_SPEC.md, ROADMAP.md, adr/0001-langgraph-agent.md, 0002-postgres-state.md,
           0003-ollama-local-llm.md, graph/ (graphify output)
schemas/   planly-plan.v1.schema.json
examples/  sample-plan.json, sample-plan.md, AGENT_PROMPT.md (prompt to paste into any agent to produce a plan file)
backend/   pyproject.toml, alembic/, app/, tests/
frontend/  Vite + React + TS
docker-compose.yml (postgres, ollama, backend, frontend) · Makefile · README.md
```

## Backend (FastAPI + SQLAlchemy 2 async + psycopg3 + Alembic)
Use one DB driver, psycopg3, so the LangGraph Postgres checkpointer and SQLAlchemy share it.

- `app/config.py`: pydantic-settings for `DATABASE_URL`, `OLLAMA_BASE_URL`, `OLLAMA_MODEL` (default `qwen2.5:7b`), `NOTION_TOKEN`, `WEB_SEARCH_ENABLED=false`.
- `app/models.py`: `Plan`, `Task` (type, date, start, duration, priority, status, notes, position, source_ref), `ChecklistItem` (subtasks), `Resource` (title, url, kind, added_by), `Event` (an append-only log of changes, with actor `user`, `agent` or `import`, plus kind, task_id, a JSON diff and a timestamp).
- **`app/services/tasks.py` (`TaskService`) is the only code that changes tasks.** It handles create, update, complete, uncomplete, reschedule, reorder, add_resource and undo(event_id). Every call writes an `Event` in the same transaction. This is what makes requirement #4 work: every state change is stored, can be audited and can be undone. The API and the agent's tools both call this service and nothing else.
- `app/importers/`: one entry point, `import_plan(source, payload) -> PlanDraft`, then `persist(draft)`. It picks a format through a small registry:
  - `planly_json.py`: JSON or YAML in the native v1 format, checked against the schema.
  - `markdown.py`: `## YYYY-MM-DD` headings and `- [ ] 09:00 Title (type, 60m)` lines. Also handles Notion Markdown exports.
  - `notion_csv.py`: Notion database CSV export, with column mapping.
  - `notion_api.py`: uses httpx to query a Notion database by ID with `NOTION_TOKEN`, with configurable property mapping (Name/Date/Status/Type). Re-imports are idempotent through `source_ref`.
- `app/api/` routers:
  - `plans` and `imports` (multipart upload, Notion sync)
  - `tasks` (list by date range, PATCH, `/complete`, `/reschedule`, `/resources`)
  - `events` (history, undo)
  - `state` (snapshot, plus export to plan v1 JSON so it can be imported again)
  - `agent` (SSE chat stream, thread history)

## Agent (LangGraph, in `app/agent/`)
- **State:** `messages`, `plan_id`, `today`, `trigger` (chat, task_event or day_review) and `changes` (event IDs the agent created).
- **Graph:** `START → load_context → agent ⇄ tools → summarize_changes → END`.
  - `load_context` is plain code, no LLM. It gathers today's and tomorrow's tasks, overdue items, recent events and the user's stated preferences, and builds a compact system message from them.
  - `agent` is `ChatOllama` with tools bound; `tools` is a ToolNode.
  - `summarize_changes` returns structured `changes` so the UI can show what changed with an Undo button.
- **Tools** (thin wrappers over `TaskService`, recorded with `actor=agent`): `list_tasks`, `get_task`, `create_task`, `update_task`, `reschedule_task`, `split_task`, `complete_task`, `replan_day(date)`, `find_resources(task_id)`, `save_resource` and `evaluate_progress`.
  - `replan_day` uses a deterministic scheduler that fills free time slots, so the LLM picks the intent and the code does the time calculations.
  - `find_resources` checks stored resources and model knowledge first, and uses DuckDuckGo search only if `WEB_SEARCH_ENABLED`.
  - There is no delete tool. Agent changes are applied directly and can be undone through the event log.
- **Triggers:**
  - A tick or reschedule in the UI fires a background run with a `task_event` message (for example "completed X 2h early").
  - The first load of a day fires a `day_review` run for missed tasks.
  - Chat messages use the same graph.
- **Persistence:** `AsyncPostgresSaver` (from `langgraph-checkpoint-postgres`), with one thread per plan for chat. Restarting keeps the conversation and the agent's state.
- **Streaming:** `graph.astream(stream_mode=["messages","updates"])` is sent to the browser as SSE.

## Frontend (React 18 + Vite + TS, `motion`, TanStack Query)
The apple-design skill sets the final look; this is the structure.
- `src/design/tokens.css`: system font stack (SF Pro first), Apple system colours, translucent blurred "material" surfaces, 8pt spacing, continuous corner radii, and light/dark themes.
- Layout: a top bar with a week strip; the **centre timeline** of type-coded task cards; the **checklist section** you reach by scrolling; and a **side chat sheet** you can collapse.
- Features live in `features/timeline`, `features/checklist`, `features/chat`, `features/import` (drag-and-drop file or Notion sync sheet) and `features/history` (undo).
- Checklist rows have tick, "Move to…" (date popover) and "Resources" (a sheet with stored links and an "Ask agent" button). When the agent changes something, cards animate to their new place and a toast offers Undo.
- Motion follows the emil-design-eng skill: spring and ease-out timing, interruptible, respects `prefers-reduced-motion`, and uses layout animations for reordering.

## Documents (written first, pushed early)
- **SRS.md** (ISO/IEC/IEEE 29148 structure): purpose and scope, definitions, overall description, user classes, constraints (offline-first, single user), functional requirements FR-1…FR-n (import, timeline, checklist, agent, persistence, export), non-functional requirements (privacy, latency, accessibility), external interfaces, data requirements, use cases, and a traceability table linking each FR to code and tests.
- The other documents (ARCHITECTURE with Mermaid C4 context/container, DATA_MODEL ERD, AGENT graph diagram, API, PLAN_FORMAT with JSON Schema, UI_SPEC with tokens and motion spec, ADRs, ROADMAP) are filled in as each part is built.

## Commit sequence (push each to `claude/loving-tesla-wjhdp4`)
1. Docs, schema and examples.
2. Backend core: models, migration, TaskService and importers, with tests.
3. Agent graph, tools and checkpointer, with tests.
4. API routers and SSE.
5. Frontend.
6. docker-compose, Makefile and README.
7. graphify output in `docs/graph/`, plus a final architecture review pass.

## Verification
- `pytest` against the local Postgres 16:
  - TaskService writes events and undo restores the previous state.
  - Each importer turns its fixture into the expected draft, and Notion API calls are mocked with `respx`.
  - Agent tests use a scripted fake chat model that makes tool calls. They check that a tick event leads to a reschedule, that changes are logged as `actor=agent`, and that the checkpointer still has the thread after a new graph instance is created.
  - API tests use `httpx.AsyncClient`.
- `npm run build` and `vitest` for the frontend. Then a Playwright smoke test with the backend running: import `examples/sample-plan.json`, see the cards, tick an item, move one to tomorrow, and take light and dark screenshots to send you.
- Ollama is not installed in the container, so live LLM chat can't be tested here. It is covered by the fake model in tests, and the README explains how to run `ollama pull qwen2.5:7b` locally.
