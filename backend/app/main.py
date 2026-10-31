import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from langchain_core.language_models import BaseChatModel

from app.agent.runtime import AgentRuntime
from app.api import agent, state, tasks
from app.config import Settings, get_settings
from app.db import make_engine, make_sessionmaker
from app.importers import PlanParseError
from app.services.tasks import Conflict, NotFound


def create_app(settings: Settings | None = None, llm: BaseChatModel | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        engine = make_engine(settings.sqlalchemy_url)
        app.state.settings = settings
        app.state.sessionmaker = make_sessionmaker(engine)
        async with AgentRuntime.open(settings, app.state.sessionmaker, llm=llm) as runtime:
            app.state.agent = runtime
            yield
        await engine.dispose()

    app = FastAPI(title="Planly", version="1.0.0", lifespan=lifespan)

    @app.exception_handler(NotFound)
    async def not_found(_: Request, exc: NotFound):
        return JSONResponse({"detail": str(exc)}, status_code=404)

    @app.exception_handler(Conflict)
    async def conflict(_: Request, exc: Conflict):
        return JSONResponse({"detail": str(exc)}, status_code=409)

    @app.exception_handler(PlanParseError)
    async def parse_error(_: Request, exc: PlanParseError):
        return JSONResponse({"detail": str(exc), "errors": exc.errors}, status_code=422)

    @app.exception_handler(ValueError)
    async def bad_value(_: Request, exc: ValueError):
        return JSONResponse({"detail": str(exc)}, status_code=422)

    @app.get("/api/health", tags=["state"])
    async def health():
        return {"ok": True}

    for module in (tasks, state, agent):
        app.include_router(module.router, prefix="/api")
    return app


app = create_app()
