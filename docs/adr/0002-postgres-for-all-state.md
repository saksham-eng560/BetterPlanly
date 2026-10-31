# PostgreSQL for app state and agent checkpoints

All state — tasks, history (change sets and events), preferences and the LangGraph thread (via `AsyncPostgresSaver`) — lives in one PostgreSQL database, so a single backup captures everything and the agent's memory can never drift from the data it talks about. Both SQLAlchemy and the checkpointer use psycopg 3, so there is one driver to install and configure.
