# Change sets and a single writer

Every mutation of tasks, checklist items, resources and preferences goes through `TaskService`. Each public method opens one change set (actor `user`, `agent` or `import`), writes a full before/after snapshot event for every entity it touches, and commits once. Undo is one generic operation that replays a change set's events backwards. This makes "every state is stored" (requirement 4), the history panel, agent change summaries and undo all fall out of one mechanism instead of four.

## Consequences
- No other module may write these tables directly. Routers and agent tools stay thin.
- Snapshots duplicate data. At personal scale (thousands of events) this is negligible, and it keeps undo trivially correct.
