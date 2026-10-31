from datetime import time
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://planly:planly@localhost:5432/planly"
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "qwen2.5:14b"
    ollama_num_ctx: int = 8192  # Ollama's 4096 default truncates the agent prompt once history builds up
    notion_token: str | None = None
    web_search_enabled: bool = False
    day_start: time = time(8, 0)
    day_end: time = time(22, 0)
    schema_dir: Path = REPO_ROOT / "schemas"

    @property
    def sqlalchemy_url(self) -> str:
        return self.database_url.replace("postgresql://", "postgresql+psycopg://", 1)


@lru_cache
def get_settings() -> Settings:
    return Settings()
