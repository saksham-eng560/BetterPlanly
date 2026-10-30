"""Importers: bytes from any supported source → PlanDraft → persist_draft().

    draft = parse_upload("week.json", content)
    result = await persist_draft(TaskService(session, actor="import"), draft)
"""

import io
import zipfile
from datetime import date
from pathlib import Path, PurePosixPath

from app.importers.draft import PlanDraft, PlanParseError
from app.importers.markdown import parse_markdown
from app.importers.notion import fetch_notion_database, parse_notion_csv
from app.importers.persist import ImportResult, persist_draft, persist_drafts
from app.importers.plan_file import dump_plan, parse_plan_file

MAX_UPLOAD_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024  # Notion exports include images; only plan files are read
MAX_ARCHIVE_TEXT_BYTES = 30 * 1024 * 1024
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


def parse_many(
    files: list[tuple[str, bytes]], today: date | None = None, label: str = "the upload"
) -> tuple[list[PlanDraft], list[str]]:
    """Every plan file among `files`: a dropped folder, several selected files, or .zip exports
    (Notion nests zips for big exports). Returns the drafts and the files skipped, with reasons."""
    drafts: list[PlanDraft] = []
    skipped: list[str] = []
    budget = [MAX_ARCHIVE_TEXT_BYTES]

    def take(name: str, data: bytes, depth: int) -> None:
        entry = PurePosixPath(name)
        if entry.name.startswith(".") or "__MACOSX" in entry.parts:
            return
        suffix = entry.suffix.lower()
        if suffix == ".zip":
            if depth >= 3:
                return
            try:
                archive = zipfile.ZipFile(io.BytesIO(data))
            except zipfile.BadZipFile as exc:
                raise PlanParseError(f"{entry.name} is not a valid zip file") from exc
            for info in sorted(archive.infolist(), key=lambda i: i.filename):
                inner = PurePosixPath(info.filename)
                wanted = inner.suffix.lower() in (*SUPPORTED_EXTENSIONS, ".zip")
                if info.is_dir() or not wanted:
                    continue
                if inner.suffix.lower() != ".zip" and (info.file_size > MAX_UPLOAD_BYTES or info.file_size > budget[0]):
                    skipped.append(f"{inner.name} (too large)")
                    continue
                take(info.filename, archive.read(info), depth + 1)
            return
        if suffix not in SUPPORTED_EXTENSIONS:
            return
        if len(data) > MAX_UPLOAD_BYTES or len(data) > budget[0]:
            skipped.append(f"{entry.name} (too large)")
            return
        budget[0] -= len(data)
        try:
            drafts.append(parse_upload(entry.name, data, today))
        except PlanParseError as exc:
            skipped.append(f"{entry.name} ({exc})")

    for name, data in sorted(files, key=lambda f: f[0]):
        take(name, data, 0)
    if not drafts:
        raise PlanParseError(f"No pages with tasks found in {label}", skipped[:10])
    return drafts, skipped


def parse_archive(filename: str, content: bytes, today: date | None = None) -> tuple[list[PlanDraft], list[str]]:
    """Every plan file in one .zip (e.g. a Notion export with subpages)."""
    if len(content) > MAX_ARCHIVE_BYTES:
        raise PlanParseError(f"{filename} is larger than {MAX_ARCHIVE_BYTES // 2**20} MB")
    return parse_many([(filename, content)], today, label=filename)


__all__ = [
    "ImportResult", "PlanDraft", "PlanParseError", "dump_plan", "fetch_notion_database",
    "parse_archive", "parse_many", "parse_upload", "persist_draft", "persist_drafts",
]
