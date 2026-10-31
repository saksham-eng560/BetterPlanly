"""History/undo, imports/export, preferences and the diagnostic state snapshot."""

from datetime import date

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from app.api.deps import AppSettings, Runtime, Service, Session
from app.importers import (
    MAX_ARCHIVE_BYTES,
    MAX_UPLOAD_BYTES,
    dump_plan,
    fetch_notion_database,
    parse_many,
    parse_upload,
    persist_drafts,
)
from app.schemas import ChangeSetOut, ImportOut, NotionImportIn, PlanOut, PreferenceOut, StateOut
from app.services.tasks import TaskService

router = APIRouter()


# ---------- history ----------

@router.get("/history", response_model=list[ChangeSetOut], tags=["history"])
async def history(svc: Service, limit: int = 30):
    return [ChangeSetOut.of(cs) for cs in await svc.history(min(limit, 200))]


@router.post("/history/{change_set_id}/undo", response_model=ChangeSetOut, tags=["history"])
async def undo(change_set_id: int, svc: Service):
    return ChangeSetOut.of(await svc.undo(change_set_id))


# ---------- import / export ----------

async def _persist(session, drafts, skipped: list[str] | None = None) -> ImportOut:
    result = await persist_drafts(TaskService(session, actor="import"), drafts)
    return ImportOut(
        plan=PlanOut.model_validate(result.plan, from_attributes=True),
        plans=[PlanOut.model_validate(p, from_attributes=True) for p in result.plans],
        skipped=skipped or [],
        created=result.created, updated=result.updated, unchanged=result.unchanged,
        change_set=ChangeSetOut.of(result.change_set),
    )


@router.post("/imports/file", response_model=ImportOut, tags=["import"])
async def import_file(
    session: Session,
    file: UploadFile | None = None,
    files: list[UploadFile] = File(default=[]),
):
    """One plan file, a .zip export, or many files at once (a dropped folder) — always one Change set."""
    uploads = [u for u in [file, *files] if u is not None]
    if not uploads:
        raise HTTPException(422, "Attach a file.")
    if len(uploads) == 1 and not (uploads[0].filename or "").lower().endswith(".zip"):
        upload = uploads[0]
        return await _persist(session, [parse_upload(upload.filename or "upload", await upload.read(MAX_UPLOAD_BYTES + 1))])
    contents, total = [], 0
    for upload in uploads:
        data = await upload.read(MAX_ARCHIVE_BYTES + 1)
        total += len(data)
        if total > MAX_ARCHIVE_BYTES:
            raise HTTPException(413, f"The upload is larger than {MAX_ARCHIVE_BYTES // 2**20} MB")
        contents.append((upload.filename or "upload", data))
    label = uploads[0].filename if len(uploads) == 1 else f"the {len(uploads)} files"
    drafts, skipped = parse_many(contents, label=label or "the upload")
    return await _persist(session, drafts, skipped)


@router.post("/imports/notion", response_model=ImportOut, tags=["import"])
async def import_notion(body: NotionImportIn, session: Session, settings: AppSettings):
    if not settings.notion_token:
        raise HTTPException(400, "Notion is not connected. Set NOTION_TOKEN in the backend environment.")
    draft = await fetch_notion_database(body.database_id, settings.notion_token)
    return await _persist(session, [draft])


@router.get("/export", tags=["import"])
async def export(svc: Service):
    tasks = await svc.list_tasks()
    filename = f"planly-export-{date.today().isoformat()}.json"
    return JSONResponse(dump_plan(tasks), headers={"Content-Disposition": f'attachment; filename="{filename}"'})


# ---------- preferences ----------

@router.get("/preferences", response_model=list[PreferenceOut], tags=["preferences"])
async def preferences(svc: Service):
    return [PreferenceOut.of(p) for p in await svc.list_preferences()]


@router.delete("/preferences/{pref_id}", response_model=ChangeSetOut, tags=["preferences"])
async def delete_preference(pref_id: int, svc: Service):
    return ChangeSetOut.of(await svc.delete_preference(pref_id))


# ---------- state ----------

@router.get("/state", response_model=StateOut, tags=["state"])
async def state(svc: Service, runtime: Runtime, settings: AppSettings, today: date | None = None):
    counts = await svc.counts(today or date.today())
    return StateOut(
        **counts,
        last_change_at=await svc.last_change_at(),
        agent={"model": settings.ollama_model, "reachable": await runtime.reachable(), "busy": runtime.busy},
        notion_configured=bool(settings.notion_token),
        web_search_enabled=settings.web_search_enabled,
    )
