# Roadmap

## v1 (this build)
Everything in the [SRS](SRS.md) marked **M**, plus the **S** items where time allows.

## Next
- **Write back to Notion.** Push ticks and moves back to the source database (two-way sync, with conflict rules).
- **Recurring tasks.** For example, "Gym Mon/Wed/Fri", expanded by the importer and the scheduler.
- **Calendar import.** Read ICS/CalDAV so meetings become fixed tasks automatically.
- **Reminders.** Browser notifications shortly before a timed task.
- **Agent evaluations.** A small set of recorded scenarios (finished early, missed day, overloaded day) scored against several Ollama models, to choose a better default.
- **OpenAI-compatible provider.** A second LLM factory for LM Studio, llama.cpp or vLLM (see ADR-0003).
- **Mobile layout polish.** Make the chat a bottom sheet on phones.
- **Multi-user.** Authentication and per-user data. This would require revisiting ADR-0005, since integer ids would then be shared across users.
