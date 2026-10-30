# Planly — Software Requirements Specification

| | |
|---|---|
| Version | 1.0 |
| Date | 2026-10-30 |
| Status | Baseline for v1 implementation |
| Structure | ISO/IEC/IEEE 29148:2018 (SRS content), trimmed for a single-developer project |

---

## 1. Introduction

### 1.1 Purpose
This document specifies what Planly v1 must do. It is the reference for implementation, tests, and review. Terms in **bold** on first use are defined in [`GLOSSARY.md`](../GLOSSARY.md).

### 1.2 Scope
Planly is a self-hosted, single-user web application that:

1. Imports **Tasks** from Notion (API or export) or from a **Plan file** that any AI agent can generate.
2. Shows the day's Tasks in a central timeline, coloured by **Task type**.
3. Offers a checklist below the timeline where the user ticks Tasks, moves them to another day, or opens their **Resources**.
4. Runs a custom **Agent** (LangGraph + a local Ollama model) in a side panel that notices ticks, early finishes and **Missed tasks**, re-plans, finds resources and follows the user's **Preferences**.
5. Stores every change in PostgreSQL so state can be inspected, undone and exported at any time.

Out of scope for v1: multiple users and authentication, mobile native apps, writing changes back to Notion, calendar (CalDAV/Google) sync, notifications/reminders, recurring Tasks.

### 1.3 Definitions
See [`GLOSSARY.md`](../GLOSSARY.md). Additional abbreviations:

| Term | Meaning |
|---|---|
| FR / NFR | Functional / non-functional requirement |
| SSE | Server-Sent Events (streaming HTTP responses) |
| LLM | Large language model |
| HIG | Apple Human Interface Guidelines |

### 1.4 References
- [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) — approved build plan
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md), [`docs/DATA_MODEL.md`](DATA_MODEL.md), [`docs/AGENT.md`](AGENT.md), [`docs/API.md`](API.md), [`docs/PLAN_FORMAT.md`](PLAN_FORMAT.md), [`docs/UI_SPEC.md`](UI_SPEC.md)
- [`docs/adr/`](adr/) — architecture decision records
- Notion API reference — `POST /v1/databases/{id}/query`, version `2022-06-28`

---

## 2. Overall description

### 2.1 Product perspective
Planly is a standalone system of four containers: a browser single-page app, a FastAPI backend, a PostgreSQL database and an Ollama model server, all running on the user's machine (see [ARCHITECTURE](ARCHITECTURE.md)). Its only optional outbound dependencies are the Notion API (when syncing) and a web search provider (when the user enables it).

### 2.2 Product functions (summary)
| Area | Summary |
|---|---|
| Import | Upload Plan files (JSON, YAML, Markdown), Notion CSV/Markdown exports, or sync a Notion database |
| Timeline | Centre view of one day: time-ordered, type-coded Task cards, "Anytime" Tasks, a now-line |
| Checklist | Tick / untick, move to another day, open Resources and Checklist items |
| Agent | Chat; reacts to ticks and moves; reviews Missed tasks; re-plans; finds and saves Resources; remembers Preferences |
| State | Every change is an Event in a Change set; undo; history; export to a Plan file |

### 2.3 User classes
| Class | Description |
|---|---|
| Owner | The single person running Planly locally. Full access. The only user class in v1. |
| Upstream agent | Any external AI agent (ChatGPT, Claude, a script) that produces a Plan file. Never talks to Planly directly; its output is uploaded by the Owner. |

### 2.4 Operating environment
- Backend: Python 3.12+, FastAPI, LangGraph 1.x, SQLAlchemy 2 (async, psycopg 3), PostgreSQL 16.
- LLM: Ollama ≥ 0.4 with a tool-calling model (default `qwen2.5:7b`).
- Frontend: evergreen desktop browsers (Safari 17+, Chrome 120+, Firefox 120+); usable down to 375 px width.
- Deployment: `docker compose up`, or each part run locally.

### 2.5 Design and implementation constraints
- **C-1 Offline-first.** With Notion sync and web search off, Planly makes no outbound network calls.
- **C-2 Local LLM only.** The Agent must run against a local Ollama server; no hosted LLM API keys.
- **C-3 Single writer path.** All mutations of Tasks, Checklist items and Resources go through one backend module (the task service), which records Events. (ADR-0004)
- **C-4 Apple look.** The UI follows the project `apple-design` skill (HIG-based) and the `emil-design-eng` motion guidance.
- **C-5 Tech stack** is fixed: LangGraph, FastAPI, PostgreSQL, React.

### 2.6 Assumptions and dependencies
| ID | Assumption |
|---|---|
| A-1 | One user per installation; the backend is reachable only from the user's machine or trusted network. No auth in v1. |
| A-2 | Dates and times are the user's local wall-clock time. The browser sends its current local time with each Agent request; the server stores naive local dates/times. |
| A-3 | A Task with no date is "Unscheduled" and appears in the checklist's Unscheduled group, not on the timeline. |
| A-4 | A Missed task is any pending Task dated before today. Planly never auto-moves it without an Agent run the user can see and undo. |
| A-5 | Agent changes are applied immediately (not proposed) and are always undoable as Change sets. |
| A-6 | Local 7B-class models make mistakes; all time arithmetic (re-planning) is done by deterministic code, not by the LLM. |
| A-7 | Re-importing the same source updates the matching Plan (by file name or Notion database id) instead of creating duplicates. |

---

## 3. Specific requirements

Priority: **M** = must (v1), **S** = should (v1 if time allows), **C** = could (later).

### 3.1 Functional requirements

#### FR-1 Import

| ID | Requirement | P |
|---|---|---|
| FR-1.1 | The system shall accept uploads of `.json`, `.yaml`/`.yml`, `.md` and `.csv` files up to 2 MB. | M |
| FR-1.2 | The system shall parse Plan files in the Planly v1 format (JSON or YAML) and validate them against [`schemas/planly-plan.v1.schema.json`](../schemas/planly-plan.v1.schema.json), reporting the first validation errors to the user. | M |
| FR-1.3 | The system shall parse Markdown plans: `## YYYY-MM-DD` headings, `- [ ]`/`- [x]` task lines with optional `HH:MM` start and `(type, 60m, high)` metadata, nested checklist items, links as Resources and `>` lines as notes. Notion Markdown page exports follow the same rules. | M |
| FR-1.4 | The system shall parse Notion database CSV exports, mapping columns by common names (Name/Title, Date/Due, Type/Category, Status/Done, Priority, Duration, Notes, URL). | M |
| FR-1.5 | Given a Notion integration token (`NOTION_TOKEN`) and a database id, the system shall fetch all pages of the database via the Notion API and import them as Tasks. | M |
| FR-1.6 | Re-importing the same source shall update existing Tasks by their source id instead of duplicating them, and shall not overwrite a Task the user has completed. | M |
| FR-1.7 | Each import shall be recorded as one Change set (actor `import`) and be undoable. | S |
| FR-1.8 | The UI shall offer a copyable prompt (`examples/AGENT_PROMPT.md`) that makes any AI agent output a valid Plan file. | M |

#### FR-2 Timeline (centre view)

| ID | Requirement | P |
|---|---|---|
| FR-2.1 | The centre view shall show the Tasks of one selected day, ordered by start time; Tasks without a start time appear in an "Anytime" group above the timed ones. | M |
| FR-2.2 | Each Task card shall show its type (colour + glyph), title, time range or duration, priority (if high), Checklist progress and Resource count. | M |
| FR-2.3 | A week strip shall let the user pick a day; today is marked; days with Tasks show a dot. | M |
| FR-2.4 | When the selected day is today, a now-line shall mark the current time. | S |
| FR-2.5 | Completed Tasks remain visible, de-emphasised. | M |
| FR-2.6 | Cards shall animate to their new position when Tasks are added, moved or re-planned. | S |

#### FR-3 Checklist

| ID | Requirement | P |
|---|---|---|
| FR-3.1 | Below the timeline, a checklist shall list the selected day's Tasks, plus a "Missed" group (when viewing today) and an "Unscheduled" group. | M |
| FR-3.2 | The user shall tick and untick a Task; ticking records the completion time. | M |
| FR-3.3 | The user shall move a Task to Tomorrow, Next week, or a picked date, optionally keeping its start time. | M |
| FR-3.4 | The user shall open a Task's detail sheet showing notes, Checklist items (tickable) and Resources, with an "Ask the Agent for resources" action. | M |
| FR-3.5 | After each tick or move, the UI shall show a toast with Undo. | M |

#### FR-4 Agent

| ID | Requirement | P |
|---|---|---|
| FR-4.1 | A side panel shall host a chat with the Agent; replies stream token by token. | M |
| FR-4.2 | The Agent shall be a LangGraph graph with tools, not a bare LLM call; its tools shall be: list tasks, get task, create task, update task, reschedule task, re-plan day, find resources, save resource, evaluate progress, remember preference. | M |
| FR-4.3 | After the user ticks or moves Tasks, the UI shall (if "Agent reacts to changes" is on) start a `task_event` run describing what changed — including whether a Task finished early or late — so the Agent can adjust the rest of the day. Rapid changes within 4 s are combined into one run. | M |
| FR-4.4 | On the first open of a day with Missed tasks, the UI shall start a `day_review` run so the Agent can re-plan them. | M |
| FR-4.5 | Re-planning shall use a deterministic scheduler: fixed Tasks stay put; flexible Tasks still ahead keep their time unless they clash; passed, clashing and Missed tasks go into the first free slot of the Day window (by priority); with "pull earlier" the remaining day is re-packed from now; overflow moves to the next day. | M |
| FR-4.6 | `find resources` shall return the Task's stored Resources; when `WEB_SEARCH_ENABLED=true` it shall also return web search results. The Agent may save useful results as Resources. | M |
| FR-4.7 | The Agent shall store Preferences the user states and include them in every run's context. | M |
| FR-4.8 | Every change made by the Agent shall be recorded with actor `agent`, and each run shall end with a summary of its Change sets that the UI shows with Undo. | M |
| FR-4.9 | The Agent shall not delete Tasks. | M |
| FR-4.10 | Conversation and Agent state shall persist across server restarts (LangGraph Postgres checkpointer). | M |
| FR-4.11 | If Ollama is unreachable, the chat shall show a clear error and the rest of the app shall keep working. | M |

#### FR-5 State and persistence

| ID | Requirement | P |
|---|---|---|
| FR-5.1 | All Tasks, Checklist items, Resources, Preferences and Events shall be stored in PostgreSQL. | M |
| FR-5.2 | Every mutation shall write an Event with actor, entity, before and after values, grouped into a Change set. | M |
| FR-5.3 | The user shall undo any Change set; undo restores the before values, deletes created entities and re-creates deleted ones, and is itself recorded. | M |
| FR-5.4 | A history panel shall list recent Change sets with actor, description and Undo. | S |
| FR-5.5 | The user shall export all Tasks as a Planly v1 JSON Plan file that re-imports losslessly. | M |
| FR-5.6 | A `GET /api/state` snapshot shall return counts, last Event time and Agent availability for diagnostics. | S |

### 3.2 Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-1 | Privacy | No data leaves the machine unless Notion sync or web search is explicitly used. No telemetry. |
| NFR-2 | Performance | Non-Agent API calls respond in < 150 ms p95 with 5 000 Tasks on a laptop. First Agent token appears in < 3 s with a warm 7B model on Apple Silicon / a modern GPU. |
| NFR-3 | Reliability | A failed Agent run leaves no partial Change set: each tool call commits atomically. |
| NFR-4 | Accessibility | WCAG 2.1 AA contrast; full keyboard operation; visible focus; respects reduced motion, reduced transparency, increased contrast and dark mode; 44 px hit targets. |
| NFR-5 | Usability | Importing a Plan file and seeing it on the timeline takes ≤ 3 interactions. |
| NFR-6 | Maintainability | Backend tests cover the task service, importers, scheduler, Agent graph (with a scripted fake model) and API. The frontend builds without type errors. |
| NFR-7 | Portability | One `docker compose up` starts the whole system. |
| NFR-8 | Observability | Backend logs each request and each Agent run (trigger, tool calls, duration). |

### 3.3 External interfaces

| Interface | Description |
|---|---|
| UI | Single-page web app, see [UI_SPEC](UI_SPEC.md). |
| REST + SSE API | `/api/*`, see [API](API.md). |
| Ollama | HTTP at `OLLAMA_BASE_URL` (default `http://localhost:11434`), via `langchain-ollama`. |
| Notion | HTTPS `api.notion.com`, bearer `NOTION_TOKEN`, `Notion-Version: 2022-06-28`. |
| Web search | DuckDuckGo via the `ddgs` package, only when `WEB_SEARCH_ENABLED=true`. |
| PostgreSQL | `DATABASE_URL`; app tables (Alembic) and LangGraph checkpoint tables. |

### 3.4 Data requirements
See [DATA_MODEL](DATA_MODEL.md). Key rules: Task ids are small integers (LLM-friendly); Events are append-only; undo never edits past Events except to mark them undone.

---

## 4. Use cases

**UC-1 Import an agent-generated plan.** Owner pastes the Agent prompt into any AI, saves the reply as `week.json`, drags it onto Planly. Planly validates, imports, and shows today's Tasks. (FR-1.1, 1.2, 1.8, 2.1)

**UC-2 Sync from Notion.** Owner enters a Notion database id in the import sheet; Planly pulls all rows; a second sync updates changed rows without duplicates. (FR-1.5, 1.6)

**UC-3 Finish early.** Owner ticks "DSA practice" at 10:05 although it was planned 09:30–11:00. A `task_event` run tells the Agent it finished 55 min early; the Agent re-plans the day, pulling "Read chapter 4" earlier, and summarises the change with Undo. (FR-3.2, 4.3, 4.5, 4.8)

**UC-4 Missed yesterday.** Owner opens Planly in the morning; two Tasks from yesterday are pending. A `day_review` run moves them into today's free slots, overflowing one to tomorrow, and explains. (FR-4.4, 4.5)

**UC-5 Move a Task.** Owner chooses "Move to → Tomorrow" on a checklist row; the Task moves with an Undo toast; the Agent comments if the day becomes overloaded. (FR-3.3, 3.5, 4.3)

**UC-6 Get resources.** Owner opens a Task's sheet and taps "Ask the Agent for resources". The Agent lists stored Resources, searches the web if enabled, saves the best ones to the Task. (FR-3.4, 4.6)

**UC-7 Teach a preference.** Owner writes "never schedule study after 9pm". The Agent stores the Preference and respects it in later re-plans. (FR-4.7)

**UC-8 Undo the Agent.** Owner disagrees with a re-plan and taps Undo on the Agent's summary; all Tasks return to their previous times. (FR-4.8, 5.3)

**UC-9 Back up.** Owner exports all Tasks to `planly-export.json` and can re-import it into a fresh install. (FR-5.5)

---

## 5. Verification and traceability

Each FR is verified by the tests listed. Paths are relative to `backend/tests/` unless stated.

| Requirement | Implemented in | Verified by |
|---|---|---|
| FR-1.1–1.4 | `app/importers/` | `test_importers.py`, `test_api.py::test_upload_*` |
| FR-1.5 | `app/importers/notion.py` | `test_importers.py::test_notion_api_*` (HTTP mocked with respx) |
| FR-1.6–1.7 | `app/importers/persist.py` | `test_importers.py::test_reimport_*` |
| FR-1.8 | `examples/AGENT_PROMPT.md` | Manual: prompt output validates against schema |
| FR-2.x | `frontend/src/features/timeline/` | `frontend/e2e/smoke.spec.ts` |
| FR-3.x | `frontend/src/features/checklist/`, `app/api/tasks.py` | `test_api.py`, `frontend/e2e/smoke.spec.ts` |
| FR-4.1–4.2 | `app/agent/` | `test_agent.py` |
| FR-4.3–4.4 | `app/agent/graph.py` (trigger messages), `frontend/src/features/chat/` | `test_agent.py::test_finishing_early_*`, `test_agent.py::test_day_review_*` |
| FR-4.5 | `app/agent/scheduler.py` | `test_scheduler.py` |
| FR-4.6–4.9 | `app/agent/tools.py` | `test_agent.py` |
| FR-4.10 | `app/agent/runtime.py` | `test_agent.py::test_thread_survives_a_new_runtime` |
| FR-4.11 | `app/agent/runtime.py`, `app/api/agent.py` | `test_agent.py::test_unreachable_ollama_is_reported` |
| FR-5.1–5.3 | `app/services/tasks.py` | `test_task_service.py` |
| FR-5.4–5.6 | `app/api/events.py`, `app/api/state.py` | `test_api.py::test_history_*`, `test_api.py::test_export_roundtrip` |

## 6. Change history
| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-10-30 | Initial baseline |
