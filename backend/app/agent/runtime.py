"""AgentRuntime: the one interface the API uses to run and inspect the agent.

Owns the Ollama model, the compiled graph, the Postgres checkpointer and the
one-run-at-a-time lock for the single Thread.
"""

import asyncio
import logging
import time as clock
import uuid
from collections.abc import AsyncIterator, Sequence
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any, Literal

import httpx
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import AIMessage, AIMessageChunk, HumanMessage, ToolMessage
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langgraph.errors import GraphRecursionError
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.agent.graph import (
    TRIGGER_NAME,
    build_graph,
    day_review_message,
    task_event_message,
    trigger_human_message,
)
from app.config import Settings
from app.services.tasks import TaskService

log = logging.getLogger("planly.agent")

THREAD_ID = "planly-main"
RECURSION_LIMIT = 24
TOOL_RESULT_PREVIEW = 600

Trigger = Literal["chat", "task_event", "day_review"]


class AgentBusy(RuntimeError):
    pass


def make_ollama(settings: Settings) -> BaseChatModel:
    from langchain_ollama import ChatOllama

    return ChatOllama(model=settings.ollama_model, base_url=settings.ollama_base_url, temperature=0.2)


class AgentRuntime:
    def __init__(
        self,
        settings: Settings,
        sessionmaker: async_sessionmaker[AsyncSession],
        checkpointer: Any,
        llm: BaseChatModel | None = None,
    ):
        self.settings = settings
        self.sessionmaker = sessionmaker
        self.graph = build_graph(llm or make_ollama(settings), sessionmaker, settings, checkpointer)
        self._lock = asyncio.Lock()

    @classmethod
    @asynccontextmanager
    async def open(
        cls, settings: Settings, sessionmaker: async_sessionmaker[AsyncSession], llm: BaseChatModel | None = None
    ) -> AsyncIterator["AgentRuntime"]:
        """Runtime with a pooled Postgres checkpointer (tables created on first use)."""
        pool = AsyncConnectionPool(
            settings.database_url,
            open=False,
            max_size=4,
            kwargs={"autocommit": True, "prepare_threshold": 0, "row_factory": dict_row},
        )
        await pool.open()
        try:
            checkpointer = AsyncPostgresSaver(pool)
            await checkpointer.setup()
            yield cls(settings, sessionmaker, checkpointer, llm)
        finally:
            await pool.close()

    @property
    def busy(self) -> bool:
        return self._lock.locked()

    @property
    def config(self) -> dict:
        return {"configurable": {"thread_id": THREAD_ID}, "recursion_limit": RECURSION_LIMIT}

    async def first_message(
        self, trigger: Trigger, now: datetime, message: str | None, change_set_ids: Sequence[int]
    ) -> HumanMessage:
        if trigger == "chat":
            if not message or not message.strip():
                raise ValueError("message is required for a chat run")
            return trigger_human_message(message.strip(), generated=False)
        async with self.sessionmaker() as session:
            svc = TaskService(session)
            if trigger == "task_event":
                text = await task_event_message(svc, list(change_set_ids), now)
            else:
                text = await day_review_message(svc, now.replace(tzinfo=None).date())
        return trigger_human_message(text, generated=True)

    async def stream(
        self,
        trigger: Trigger,
        now: datetime,
        *,
        message: str | None = None,
        change_set_ids: Sequence[int] = (),
    ) -> AsyncIterator[tuple[str, Any]]:
        """Run the agent once, yielding (event, data) pairs: token, tool_call, tool_result,
        changes, error and finally done. Raises AgentBusy if a run is already active."""
        if self._lock.locked():
            raise AgentBusy("the agent is already working")
        async with self._lock:
            started = clock.monotonic()
            run_id = uuid.uuid4()
            first = await self.first_message(trigger, now, message, change_set_ids)
            yield "message", {"role": "event" if first.name == TRIGGER_NAME else "user", "content": first.content}
            state = {"messages": [first], "now": now.isoformat(), "run_id": str(run_id), "context": "", "changes": []}
            tools_used = []
            try:
                async for mode, chunk in self.graph.astream(state, self.config, stream_mode=["messages", "updates"]):
                    if mode == "messages":
                        msg, meta = chunk
                        if meta.get("langgraph_node") == "agent" and isinstance(msg, (AIMessage, AIMessageChunk)) and msg.text:
                            yield "token", {"text": msg.text}
                        continue
                    for node, update in chunk.items():
                        if node == "agent":
                            for call in update["messages"][-1].tool_calls:
                                tools_used.append(call["name"])
                                yield "tool_call", {"name": call["name"], "args": call["args"]}
                        elif node == "tools":
                            for result in update["messages"]:
                                yield "tool_result", {"name": result.name, "content": str(result.content)[:TOOL_RESULT_PREVIEW]}
                        elif node == "summarize":
                            yield "changes", update["changes"]
            except GraphRecursionError:
                yield "error", {"message": "I went around in circles and stopped. Try asking more specifically."}
            except (httpx.ConnectError, ConnectionError) as exc:
                log.warning("ollama unreachable: %s", exc)
                yield "error", {"message": f"Can't reach Ollama at {self.settings.ollama_base_url}. Is it running?"}
            except Exception as exc:  # model errors (e.g. model not pulled) surface to the chat
                log.exception("agent run failed")
                yield "error", {"message": f"The agent failed: {exc}"}
            log.info(
                "agent run %s trigger=%s tools=%s %.1fs", run_id, trigger, tools_used, clock.monotonic() - started
            )
            yield "done", {}

    async def thread(self) -> list[dict]:
        snapshot = await self.graph.aget_state(self.config)
        out = []
        for m in snapshot.values.get("messages", []) if snapshot.values else []:
            if isinstance(m, HumanMessage):
                out.append({"role": "event" if m.name == TRIGGER_NAME else "user", "content": m.content})
            elif isinstance(m, AIMessage):
                out.append({"role": "assistant", "content": m.text, "tool_calls": [c["name"] for c in m.tool_calls]})
            elif isinstance(m, ToolMessage):
                out.append({"role": "tool", "name": m.name, "content": str(m.content)[:TOOL_RESULT_PREVIEW]})
        return out

    async def reachable(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=1.5) as client:
                response = await client.get(f"{self.settings.ollama_base_url}/api/tags")
            return response.status_code == 200
        except httpx.HTTPError:
            return False
