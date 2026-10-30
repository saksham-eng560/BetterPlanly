# LangGraph tool-calling agent with a deterministic scheduler

The side-panel assistant is a LangGraph `StateGraph` (load_context → agent ⇄ tools → summarize) whose tools call the same `TaskService` the UI uses, rather than a prompt-only chatbot or a fixed rules engine. Local 7B models are unreliable at time arithmetic, so the one thing they must not do is compute schedules: `replan_day` delegates to a pure, tested scheduler and the model only decides *when* to re-plan and *how to explain it*.

## Considered options
- **Plain LLM chat that returns a new plan as JSON** — rejected: a small model rewriting the whole day loses tasks and hallucinates times; no partial undo.
- **Rules only, no LLM** — rejected: the user explicitly wants a custom agent that can search, evaluate and follow free-form preferences.
