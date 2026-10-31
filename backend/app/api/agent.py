import json
from datetime import datetime

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from app.agent.runtime import AgentBusy
from app.api.deps import Runtime
from app.schemas import AgentRunIn

router = APIRouter(tags=["agent"])


def sse(event: str, data) -> str:
    return f"event: {event}\ndata: {json.dumps(data, default=str)}\n\n"


@router.post("/agent/runs")
async def run(body: AgentRunIn, runtime: Runtime):
    """Start an agent run and stream it as Server-Sent Events (docs/AGENT.md#streaming-to-the-ui)."""
    now = body.now or datetime.now().astimezone()
    stream = runtime.stream(body.trigger, now, message=body.message, change_set_ids=body.change_set_ids)
    try:
        first = await anext(stream)  # surfaces busy / bad input as a status code, not a broken stream
    except AgentBusy as exc:
        raise HTTPException(409, str(exc)) from exc

    async def events():
        yield sse(*first)
        async for event in stream:
            yield sse(*event)

    return StreamingResponse(
        events(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )


@router.get("/agent/thread")
async def thread(runtime: Runtime):
    return {"messages": await runtime.thread()}
