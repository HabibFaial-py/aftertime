"""Test-only ASGI boundary. The normal API never imports or mounts it."""

import os
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials

from app.auth import bearer
from app.capsules import CapsuleReveal
from app.recipient_capsules import (
    RecipientInboxItem, RecipientReadUnavailable, list_received_capsules, reveal_received_capsule,
)


INBOX_PATH = "/__local/recipient/capsules"
REVEAL_PATH = INBOX_PATH + "/{capsule_id}/reveal"


def _enabled():
    return (os.environ.get("AFTERTIME_LOCAL_DELIVERY_TEST") == "1"
            and os.environ.get("AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST") == "1")


async def _validate_request(request: Request):
    query = request.query_params
    allowed = {"limit", "offset"} if request.method == "GET" else set()
    if set(query) - allowed or len(query.multi_items()) != len(query) or await request.body():
        raise HTTPException(status_code=422, detail="Invalid recipient request")


def create_local_recipient_app(fixture_marker: UUID) -> FastAPI:
    """Create an in-process test app for the active disposable fixture."""
    if not _enabled():
        raise RuntimeError("Local recipient HTTP tests are disabled")

    # Load the optional driver only for opt-in tests. Each connection checks
    # the fixed cluster path, loopback identity and the real invitation gate.
    from local_delivery_adapter import InboxConnection, RevealConnection, connect_local

    try:
        with connect_local() as connection:
            markers = connection.execute("SELECT id FROM fixture014i4.test_marker").fetchall()
        if markers != [(fixture_marker,)]:
            raise ValueError("Fixture marker mismatch")
    except Exception:
        raise RuntimeError("Local recipient HTTP fixture unavailable") from None

    app = FastAPI(openapi_url=None, docs_url=None, redoc_url=None, redirect_slashes=False)

    @app.middleware("http")
    async def protect_local_response(request: Request, call_next):
        if not _enabled() or request.client is None or request.client.host != "127.0.0.1":
            response = JSONResponse(status_code=404, content={"detail": "Not found"})
        else:
            try:
                response = await call_next(request)
            except Exception:
                response = JSONResponse(status_code=503, content={"detail": "Capsule service unavailable"})
        response.headers["Cache-Control"] = "no-store"
        response.headers["Pragma"] = "no-cache"
        return response

    @app.exception_handler(RequestValidationError)
    async def invalid_request(_request: Request, _error: RequestValidationError):
        return JSONResponse(status_code=422, content={"detail": "Invalid recipient request"})

    @app.exception_handler(RecipientReadUnavailable)
    async def unavailable(_request: Request, _error: RecipientReadUnavailable):
        return JSONResponse(status_code=503, content={"detail": "Capsule service unavailable"})

    @app.get(INBOX_PATH, dependencies=[Depends(_validate_request)], response_model=list[RecipientInboxItem])
    def inbox(credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
              limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0, le=10000)):
        return list_received_capsules(credentials, connection_factory=InboxConnection, limit=limit, offset=offset)

    @app.post(REVEAL_PATH, dependencies=[Depends(_validate_request)], response_model=CapsuleReveal)
    def reveal(capsule_id: UUID, credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        result = reveal_received_capsule(capsule_id, credentials, connection_factory=RevealConnection)
        if result is None:
            raise HTTPException(status_code=404, detail="Capsule unavailable")
        return result

    return app
