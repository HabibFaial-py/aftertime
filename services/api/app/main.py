from datetime import datetime, timezone
from uuid import UUID
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.exception_handlers import request_validation_exception_handler

from app.auth import current_user
from app.capsules import CapsuleListItem, CapsuleMetadata, CapsuleReveal, CreateCapsule
from app.config import DatabaseConfigurationError
from app.database import DatabaseInputError, DatabaseOwnerError, DatabaseRepository, DatabaseUnavailableError

app = FastAPI()


def is_reveal_path(path: str) -> bool:
    return path.startswith("/v1/capsules/") and path.endswith("/reveal")


@app.middleware("http")
async def reveal_cache_protection(request: Request, call_next):
    if not is_reveal_path(request.url.path):
        return await call_next(request)
    try:
        response = await call_next(request)
    except Exception:
        # Do not log/echo provider exceptions or return a traceback for reveal.
        response = JSONResponse(status_code=503, content={"detail": "Capsule service unavailable"})
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    return response


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    if is_reveal_path(request.url.path):
        return JSONResponse(status_code=422, content={"detail": "Invalid capsule ID"})
    if request.url.path == "/v1/capsules":
        return JSONResponse(status_code=422, content={"detail": "Invalid capsule request"})
    return await request_validation_exception_handler(request, exc)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/auth/me")
def me(user_id: str = Depends(current_user)) -> dict[str, str]:
    return {"id": user_id}


@app.post("/v1/capsules", status_code=201, response_model=CapsuleMetadata)
def create_capsule(capsule: CreateCapsule, user_id: str = Depends(current_user)) -> CapsuleMetadata:
    try:
        return DatabaseRepository().create_self_capsule(user_id, capsule)
    except DatabaseInputError:
        raise HTTPException(status_code=422, detail="Invalid capsule request") from None
    except DatabaseOwnerError:
        raise HTTPException(status_code=403, detail="Unable to create capsule") from None
    except (DatabaseConfigurationError, DatabaseUnavailableError):
        raise HTTPException(status_code=503, detail="Capsule service unavailable") from None


@app.get("/v1/capsules", response_model=list[CapsuleListItem])
def list_capsules(
    limit: int = Query(default=50, ge=1, le=50),
    offset: int = Query(default=0, ge=0, le=10000),
    user_id: str = Depends(current_user),
) -> list[CapsuleListItem]:
    try:
        rows = DatabaseRepository().list_owned_capsules(user_id, limit, offset)
    except (DatabaseConfigurationError, DatabaseUnavailableError):
        raise HTTPException(status_code=503, detail="Capsule service unavailable") from None
    now = datetime.now(timezone.utc)
    return [CapsuleListItem(**row.model_dump(), status="unlocked" if row.unlock_at <= now else "locked")
            for row in rows]


@app.get("/v1/capsules/{capsule_id}/reveal", response_model=CapsuleReveal)
def reveal_capsule(capsule_id: UUID, request: Request, user_id: str = Depends(current_user)) -> CapsuleReveal:
    if request.query_params:
        raise HTTPException(status_code=422, detail="Invalid reveal request")
    try:
        result = DatabaseRepository().reveal_self_capsule(capsule_id, user_id)
    except (DatabaseConfigurationError, DatabaseUnavailableError):
        raise HTTPException(status_code=503, detail="Capsule service unavailable") from None
    if result is None:
        raise HTTPException(status_code=404, detail="Capsule unavailable")
    return result
