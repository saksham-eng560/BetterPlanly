# Planly

A personal day planner. Tasks come in from Notion or from a plan file any AI agent can write; a local LangGraph agent keeps the schedule honest as the day unfolds.

## Planning

**Task**:
One thing to do, optionally on a date and at a start time, with a duration, a type, a priority and a status.
_Avoid_: Todo, item, card (a card is only its visual form)

**Task type**:
The kind of work a Task is (study, work, reading, fitness, meeting, habit, errand, personal, other). Drives colour and glyph; `meeting` is the only fixed type.
_Avoid_: Category, kind, tag

**Fixed task**:
A Task whose time cannot be moved by the Scheduler. Today only `meeting` Tasks are fixed.
_Avoid_: Pinned, locked

**Checklist item**:
A sub-step inside a Task, ticked independently.
_Avoid_: Subtask

**Section**:
The group a Task belongs to inside its source, such as a heading on a Notion page ("AIML / Dev", "LeetCode list"). Each Section is shown as its own widget box.
_Avoid_: Group, category, list

**Resource**:
A link, video, book or note attached to a Task to help complete it.
_Avoid_: Reference, attachment

**Plan**:
The set of Tasks that arrived from one source (one file, one Notion database). Re-importing the same source updates the same Plan.
_Avoid_: Project, list, schedule

**Plan file**:
A document in the Planly plan format (JSON, YAML or Markdown) that any agent can produce and the user can upload.
_Avoid_: Export, template

**Missed task**:
A pending Task whose date is before today.
_Avoid_: Overdue (UI copy may say "Overdue"; the domain term is Missed)

**Day window**:
The hours of a day the Scheduler may place flexible Tasks in (default 08:00–22:00).

## State

**Event**:
One recorded change to a Task, Checklist item or Resource, with who made it (user, agent, import) and the before/after values.
_Avoid_: Log entry, history item

**Change set**:
All Events produced by one action (one tick, one agent tool call, one import). Undo reverses a whole Change set.
_Avoid_: Batch, transaction (in user-facing language)

**Actor**:
Who caused an Event: `user`, `agent` or `import`.

## Agent

**Agent**:
The LangGraph assistant in the side panel, running on a local Ollama model.
_Avoid_: Bot, model (the model is only the LLM inside the Agent)

**Trigger**:
Why an Agent run started: `chat` (the user wrote), `task_event` (the user ticked or moved Tasks) or `day_review` (first open of a day with Missed tasks).

**Thread**:
The persisted conversation and Agent state, stored by the LangGraph Postgres checkpointer.

**Preference**:
A durable instruction from the user the Agent must respect when planning ("workouts before 9am").
_Avoid_: Memory, setting

**Re-plan**:
Moving flexible Tasks into free slots of a day (and overflowing to the next day) using the deterministic Scheduler.
_Avoid_: Reshuffle, optimise
