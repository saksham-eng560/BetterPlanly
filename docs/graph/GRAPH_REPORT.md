# Graph Report - Planly codebase  (2026-10-30)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 707 nodes · 1901 edges · 30 communities (23 shown, 7 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 176 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7bc6e830`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- TaskService, change sets & data model
- HTTP API routers & schemas
- Importers: plan file, Markdown, Notion
- API & importer tests
- Docker Compose deployment
- Frontend build & e2e smoke test
- AgentRuntime & agent tests
- Frontend: timeline & checklist components
- Agent tools & DB sessions
- Deterministic re-planner (scheduler)
- App factory & database engine
- Frontend API client & history
- Toasts & query client
- Task actions & import sheet
- Agent chat store & SSE
- Config & Alembic environment
- App shell & data hooks
- TypeScript config
- Settings & Ollama wiring
- LangGraph graph construction
- Dates & move menu
- Agent context & trigger messages
- Fake Ollama demo server
- YAML plan fixture
- Initial schema migration
- backend project metadata

## God Nodes (most connected - your core abstractions)
1. `TaskService` - 69 edges
2. `ChangeSet` - 27 edges
3. `Task` - 25 edges
4. `build_tools()` - 24 edges
5. `Settings` - 21 edges
6. `create_app()` - 21 edges
7. `App()` - 21 edges
8. `parse_upload()` - 20 edges
9. `replan()` - 20 edges
10. `persist_draft()` - 19 edges

## Surprising Connections (you probably didn't know these)
- `ChangeSetOut` --uses--> `ChangeSet`  [INFERRED]
  backend/app/schemas.py → backend/app/models.py
- `PreferenceOut` --uses--> `Preference`  [INFERRED]
  backend/app/schemas.py → backend/app/models.py
- `format_task()` --uses--> `Task`  [INFERRED]
  backend/app/agent/tools.py → backend/app/models.py
- `to_slot()` --uses--> `Task`  [INFERRED]
  backend/app/agent/tools.py → backend/app/models.py
- `dump_plan()` --uses--> `Task`  [INFERRED]
  backend/app/importers/plan_file.py → backend/app/models.py

## Import Cycles
- None detected.

## Communities (30 total, 7 thin omitted)

### Community 0 - "TaskService, change sets & data model"
Cohesion: 0.07
Nodes (43): render_context(), _dedupe_ids(), ImportResult, persist_draft(), Base, ChangeSet, ChecklistItem, Event (+35 more)

### Community 1 - "HTTP API routers & schemas"
Cohesion: 0.06
Nodes (45): run(), events(), sse(), thread(), get_runtime(), get_service(), get_session(), get_settings_dep() (+37 more)

### Community 2 - "Importers: plan file, Markdown, Notion"
Cohesion: 0.08
Nodes (30): ChecklistDraft, PlanDraft, PlanParseError, ResourceDraft, TaskDraft, derived_id(), normalize_priority(), normalize_status() (+22 more)

### Community 3 - "API & importer tests"
Cohesion: 0.08
Nodes (26): parse_upload(), dump_plan(), ScriptedChatModel, api(), parse_sse(), test_agent_run_streams_sse_and_thread(), test_agent_task_event_and_validation(), test_export_roundtrip() (+18 more)

### Community 4 - "Docker Compose deployment"
Cohesion: 0.05
Nodes (43): build, depends_on, environment, context, dockerfile, postgres, DATABASE_URL, NOTION_TOKEN (+35 more)

### Community 5 - "Frontend build & e2e smoke test"
Cohesion: 0.07
Nodes (32): NOW, ROOT, SHOTS, react-dom@19.3.1, devDependencies, @playwright/test@1.63.0, @types/node@24.19.2, @types/react@19.3.0 (+24 more)

### Community 6 - "AgentRuntime & agent tests"
Cohesion: 0.09
Nodes (4): day_review_message(), trigger_human_message(), AgentBusy, AgentRuntime

### Community 7 - "Frontend: timeline & checklist components"
Cohesion: 0.18
Nodes (22): useTask(), Checkbox(), Sheet(), Checklist(), Group(), Row(), RESOURCE_ICONS, TaskSheet() (+14 more)

### Community 8 - "Agent tools & DB sessions"
Cohesion: 0.23
Nodes (20): summarize(), build_tools(), create_task(), evaluate_progress(), find_resources(), get_task(), guarded(), list_tasks() (+12 more)

### Community 9 - "Deterministic re-planner (scheduler)"
Cohesion: 0.20
Nodes (15): _minutes(), _overlaps(), Placement, replan(), Slot, _time(), moves(), slot() (+7 more)

### Community 10 - "App factory & database engine"
Cohesion: 0.12
Nodes (5): make_engine(), make_sessionmaker(), create_app(), engine(), migrated()

### Community 11 - "Frontend API client & history"
Cohesion: 0.14
Nodes (16): useHistory(), Popover(), ACTOR_ICON, Entries(), HistoryPopover(), ApiError, ChangeSet, ChecklistItem (+8 more)

### Community 12 - "Toasts & query client"
Cohesion: 0.15
Nodes (14): dependencies, lucide-react@1.65.0, motion@14.8.0, react@19.3.1, @tanstack/react-query@5.105.0, zustand@5.0.16, queryClient, Toaster() (+6 more)

### Community 13 - "Task actions & import sheet"
Cohesion: 0.27
Nodes (15): refreshPlan(), fail(), moveTask(), patchCachedTask(), toggleChecklistItem(), toggleDone(), undo(), undoAction() (+7 more)

### Community 14 - "Agent chat store & SSE"
Cohesion: 0.14
Nodes (15): AgentStore, Change, ChatItem, describeTool(), pending, queue, readReact(), RunRequest (+7 more)

### Community 15 - "Config & Alembic environment"
Cohesion: 0.15
Nodes (6): database_url(), run_migrations_offline(), run_migrations_online(), to_slot(), web_search(), get_settings()

### Community 16 - "App shell & data hooks"
Cohesion: 0.30
Nodes (13): App(), useDayReview(), useAppState(), useMissed(), useUnscheduled(), useWeekTasks(), useAgent, ChatPanel() (+5 more)

### Community 17 - "TypeScript config"
Cohesion: 0.12
Nodes (15): compilerOptions, isolatedModules, jsx, lib, module, moduleResolution, noEmit, noFallthroughCasesInSwitch (+7 more)

### Community 18 - "Settings & Ollama wiring"
Cohesion: 0.20
Nodes (5): make_ollama(), Settings, lifespan(), make(), settings()

### Community 19 - "LangGraph graph construction"
Cohesion: 0.15
Nodes (5): build_graph(), agent(), load_context(), _sendable(), local_now()

### Community 20 - "Dates & move menu"
Cohesion: 0.45
Nodes (10): MoveMenu(), addDays(), isoDate(), localNowIso(), nextMonday(), pad(), relativeDay(), shortDay() (+2 more)

### Community 21 - "Agent context & trigger messages"
Cohesion: 0.23
Nodes (4): AgentState, _minutes_between(), _span(), task_event_message()

### Community 23 - "YAML plan fixture"
Cohesion: 0.22
Nodes (8): planly, tasks, duration, id, start, title, type, title

## Knowledge Gaps
- **1 isolated node(s):** `planly-backend`
  These have ≤1 connection - possible missing edges. (Counts symbols only; 210 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `TaskService` connect `TaskService, change sets & data model` to `HTTP API routers & schemas`, `Importers: plan file, Markdown, Notion`, `API & importer tests`, `AgentRuntime & agent tests`, `Agent tools & DB sessions`, `Config & Alembic environment`, `LangGraph graph construction`, `Agent context & trigger messages`?**
  _High betweenness centrality (0.083) - this node is a cross-community bridge._
- **Are the 11 inferred relationships involving `TaskService` (e.g. with `day_review_message()` and `render_context()`) actually correct?**
  _`TaskService` has 11 INFERRED edges - model-reasoned connections that need verification._
- **What connects `planly-backend` to the rest of the system?**
  _1 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `TaskService, change sets & data model` be split into smaller, more focused modules?**
  _Cohesion score 0.07301231802911534 - nodes in this community are weakly interconnected._
- **Why does `date` connect `Importers: plan file, Markdown, Notion` to `TaskService, change sets & data model`, `HTTP API routers & schemas`, `AgentRuntime & agent tests`, `Agent tools & DB sessions`, `Deterministic re-planner (scheduler)`, `YAML plan fixture`?**
  _High betweenness centrality (0.028) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `ChangeSet` (e.g. with `ImportResult` and `ChangeSetOut`) actually correct?**
  _`ChangeSet` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `HTTP API routers & schemas` be split into smaller, more focused modules?**
  _Cohesion score 0.05789009697325889 - nodes in this community are weakly interconnected._