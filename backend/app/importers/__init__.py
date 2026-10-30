"""Importers: bytes from any supported source → PlanDraft → persist_draft().

    draft = parse_upload("week.json", content)
    result = await persist_draft(TaskService(session, actor="import"), draft)
"""

from datetime import date
from pathlib import Path

from app.importers.draft import PlanDraft, PlanParseError
from app.importers.markdown import parse_markdown
from app.importers.notion import fetch_notion_database, parse_notion_csv
from app.importers.persist import ImportResult, persist_draft
from app.importers.plan_file import dump_plan, parse_plan_file

MAX_UPLOAD_BYTES = 2 * 1024 * 1024
SUPPORTED_EXTENSIONS = (".json", ".yaml", ".yml", ".md", ".markdown", ".csv")


def parse_upload(filename: str, content: bytes, today: date | None = None) -> PlanDraft:
    if len(content) > MAX_UPLOAD_BYTES:
        raise PlanParseError(f"{filename} is larger than 2 MB")
    extension = Path(filename).suffix.lower()
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise PlanParseError(f"{filename} is not UTF-8 text") from exc
    if extension == ".json":
        return parse_plan_file(filename, text, is_yaml=False)
    if extension in (".yaml", ".yml"):
        return parse_plan_file(filename, text, is_yaml=True)
    if extension in (".md", ".markdown"):
        return parse_markdown(filename, text, today)
    if extension == ".csv":
        return parse_notion_csv(filename, text)
    raise PlanParseError(f"Unsupported file type {extension or '(none)'}; use {', '.join(SUPPORTED_EXTENSIONS)}")


__all__ = [
    "ImportResult", "PlanDraft", "PlanParseError", "dump_plan", "fetch_notion_database",
    "parse_upload", "persist_draft",
]
