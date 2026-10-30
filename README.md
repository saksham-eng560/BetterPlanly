# Planly

A personal day planner with a **local AI agent** beside your schedule.

You bring tasks in from Notion, or from a plan file that any AI assistant can write. Planly lays the day out as a timeline of colour-coded tasks with a checklist underneath. A LangGraph agent running on a local Ollama model watches what you tick. When you finish early, fall behind or miss something, it re-plans the day. Every change, yours or the agent's, is stored in Postgres and can be undone.

| Light | Dark |
|---|---|
| ![Planly, light](docs/screenshots/today-light.png) | ![Planly, dark](docs/screenshots/today-dark.png) |

<p align="center"><img src="docs/screenshots/phone.png" width="260" alt="Planly on a phone"> &nbsp; <img src="docs/screenshots/task-sheet.png" width="520" alt="Task details"></p>

## What it does

- **Import from anywhere.** Planly reads its own JSON/YAML plan format, Markdown checklists, Notion CSV exports, or a live Notion database. Re-importing updates tasks instead of duplicating them, and one Undo reverts an import. [`examples/AGENT_PROMPT.md`](examples/AGENT_PROMPT.md) makes ChatGPT, Claude or any other assistant write a valid plan file.
- **The day at a glance.** The centre timeline shows type-coded cards (study, work, reading, fitness, meeting, habit, errand, personal), a now-line, free time and Anytime tasks.
- **Checklist.** Tick tasks, move them (Today, Tomorrow, Next week, any date) and open their steps and resources.
- **An agent, not just a chat box.** It is a LangGraph graph with ten tools over the same service the UI uses:
  - **Reacts to your ticks.** It knows when you finished 55 minutes early.
  - **Catches up on missed days.** On the first open of a day it re-plans what you missed.
  - **Finds resources**, offline-first, with optional web search.
  - **Remembers preferences** such as "no study after 9pm".
  - **Leaves the arithmetic to code.** Scheduling is done by a deterministic, tested re-planner; the model decides when and why.
- **Everything is stored.**
  - Tasks, history and the agent's conversation all live in PostgreSQL.
  - Each change is a change set with before/after snapshots, and the history panel can undo any of them.
  - Export writes a plan file that imports back losslessly.

## Quick start (Docker)

```bash
docker compose up --build
```

Open <http://localhost:8080>. On first start, the `ollama-pull` container downloads `qwen2.5:7b`, which is about 4.7 GB. Optional settings:

```bash
OLLAMA_MODEL=llama3.1:8b NOTION_TOKEN=secret_… WEB_SEARCH_ENABLED=true docker compose up --build
```

**On a Mac**, Ollama inside Docker can't use the GPU. Install Ollama natively, run `ollama pull qwen2.5:7b`, then start Planly pointing at it:

```bash
OLLAMA_BASE_URL=http://host.docker.internal:11434 docker compose up --build postgres backend frontend
```

## Local development

You need Python 3.12+, Node 22, PostgreSQL 16, and Ollama for real agent replies.

```bash
make setup
```

```bash
make db
```

Then run these in three terminals:

```bash
make backend
```

```bash
make frontend
```

```bash
ollama serve
```

If you don't have a model, run `make fake-ollama` in place of `ollama serve`. It starts a scripted stand-in.

The app runs at <http://localhost:5173>. The API docs are at <http://localhost:8000/docs>.

Configuration lives in `backend/.env` (copy it from [`backend/.env.example`](backend/.env.example)):

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | `postgresql://planly:planly@localhost:5432/planly` | |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | |
| `OLLAMA_MODEL` | `qwen2.5:7b` | Any Ollama model with tool calling |
| `NOTION_TOKEN` | — | Turns on Notion sync ([setup](docs/PLAN_FORMAT.md#live-sync-notion-api)) |
| `WEB_SEARCH_ENABLED` | `false` | Lets the agent search DuckDuckGo for resources |

## Tests

```bash
make test
```

That runs 46 backend tests against Postgres and the frontend unit tests:
- the change-set service and undo
- every importer, with the Notion API mocked
- the scheduler
- the agent graph with a scripted model
- the HTTP API and SSE

```bash
make e2e
```

That's the Playwright smoke test of import → agent day review → tick → move → undo, plus dark mode and phone. It also refreshes [`docs/screenshots/`](docs/screenshots).

## How it fits together

```mermaid
flowchart LR
  ui[React app] -- REST + SSE --> api[FastAPI]
  api --> svc[TaskService<br/>single writer, change sets]
  api --> agent[LangGraph agent]
  agent -- tools --> svc
  agent --> ollama[(Ollama)]
  svc --> db[(PostgreSQL)]
  agent -- checkpointer --> db
```

| Document | |
|---|---|
| [SRS](docs/SRS.md) | Requirements, use cases, traceability to code and tests |
| [Architecture](docs/ARCHITECTURE.md) | Modules, flows, deployment |
| [Agent](docs/AGENT.md) | Graph, tools, scheduler, triggers, streaming |
| [Data model](docs/DATA_MODEL.md) | Tables, change sets, undo rules |
| [API](docs/API.md) | HTTP endpoints |
| [Plan format](docs/PLAN_FORMAT.md) | Plan files, Markdown, Notion |
| [UI spec](docs/UI_SPEC.md) | Layout, tokens, components, motion, accessibility |
| [ADRs](docs/adr) · [Glossary](GLOSSARY.md) · [Roadmap](docs/ROADMAP.md) | |
| [Code graph](docs/graph) | graphify knowledge graph of the codebase |

```
backend/   FastAPI app, LangGraph agent, importers, Alembic migrations, tests
frontend/  React + Vite app, Playwright smoke test
schemas/   JSON Schema for the plan file
examples/  sample plans and the prompt for other agents
scripts/   fake_ollama.py: scripted Ollama stand-in for demos and e2e
docs/      SRS and design docs, screenshots, code graph
.claude/   project skills used to build this (design, motion, architecture)
```
