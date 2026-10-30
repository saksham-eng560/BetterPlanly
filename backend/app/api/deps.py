from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.agent.runtime import AgentRuntime
from app.config import Settings
from app.services.tasks import TaskService


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    async with request.app.state.sessionmaker() as session:
        yield session


Session = Annotated[AsyncSession, Depends(get_session)]


def get_service(session: Session) -> TaskService:
    return TaskService(session, actor="user")


def get_runtime(request: Request) -> AgentRuntime:
    return request.app.state.agent


def get_settings_dep(request: Request) -> Settings:
    return request.app.state.settings


Service = Annotated[TaskService, Depends(get_service)]
Runtime = Annotated[AgentRuntime, Depends(get_runtime)]
AppSettings = Annotated[Settings, Depends(get_settings_dep)]
