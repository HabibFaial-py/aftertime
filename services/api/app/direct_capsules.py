"""Direct-capsule endpoints. Claims remain unavailable until identity is proven."""

import re
from datetime import datetime, timezone
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, StrictStr, ValidationError, field_validator

from app.auth import current_user
from app.capsules import CapsuleCancellation, CapsuleReveal, CreateCapsule
from app.config import DatabaseConfigurationError, get_database_settings
from app.database import DatabaseInputError, DatabaseOwnerError, DatabaseUnavailableError


router = APIRouter(prefix="/v1/direct-capsules")


class CreateDirectCapsule(CreateCapsule):
    body: StrictStr = Field(repr=False)
    recipient_email: StrictStr = Field(repr=False, max_length=254)

    @field_validator("recipient_email")
    @classmethod
    def validate_recipient(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+", value) or "\x00" in value:
            raise ValueError("Invalid recipient")
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise ValueError("Invalid recipient") from None
        return value


class DirectCapsuleCreated(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    unlock_at: datetime
    created_at: datetime

    @field_validator("unlock_at", "created_at", mode="before")
    @classmethod
    def require_timestamp_string(cls, value):
        if not isinstance(value, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})", value
        ):
            raise ValueError("Invalid timestamp")
        return value

    @field_validator("unlock_at", "created_at")
    @classmethod
    def require_aware_time(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Invalid timestamp")
        return value.astimezone(timezone.utc)


class PendingDirectCapsuleMetadata(DirectCapsuleCreated):
    """Proposed minimal projection; no sender-written content or email."""


class ClaimedDirectCapsuleMetadata(DirectCapsuleCreated):
    """Proposed claim result; never a body or title."""


class DirectCapsuleRepository:
    def __init__(self) -> None:
        self._settings = get_database_settings()

    def _rpc(self, function: str, params: dict, *, creating: bool = False) -> list:
        try:
            with httpx.Client(
                base_url=f"{self._settings.supabase_url}/rest/v1/",
                headers={"apikey": self._settings.secret_key, "Content-Profile": "public"},
                timeout=5.0, follow_redirects=False, trust_env=False,
            ) as client:
                response = client.post(f"rpc/{function}", json=params)
                if response.status_code != 200:
                    if creating:
                        try:
                            code = response.json().get("code")
                        except (ValueError, AttributeError):
                            code = None
                        if response.status_code == 400 and code == "22023":
                            raise DatabaseInputError() from None
                        if response.status_code == 403 and code == "42501":
                            raise DatabaseOwnerError() from None
                    raise DatabaseUnavailableError() from None
                rows = response.json()
                if not isinstance(rows, list) or len(rows) > 1:
                    raise DatabaseUnavailableError() from None
                return rows
        except (httpx.HTTPError, ValueError, ValidationError):
            raise DatabaseUnavailableError() from None

    def create(self, user_id: str, capsule: CreateDirectCapsule) -> DirectCapsuleCreated:
        rows = self._rpc("aftertime_create_direct_capsule", {
            "p_owner_id": user_id, "p_recipient_email": capsule.recipient_email,
            "p_title": capsule.title, "p_body": capsule.body,
            "p_unlock_at": capsule.unlock_at.isoformat(),
        }, creating=True)
        if len(rows) != 1:
            raise DatabaseUnavailableError()
        try:
            return DirectCapsuleCreated.model_validate(rows[0])
        except (ValueError, ValidationError):
            raise DatabaseUnavailableError() from None

    def result(self, function: str, capsule_id: UUID, user_id: str, model):
        rows = self._rpc(function, {"p_capsule_id": str(capsule_id), "p_requester_id": user_id})
        if not rows:
            return None
        try:
            result = model.model_validate(rows[0])
            if result.id != capsule_id:
                raise DatabaseUnavailableError()
            return result
        except (ValueError, ValidationError):
            raise DatabaseUnavailableError() from None


async def no_extra_request_data(request: Request) -> None:
    if request.query_params or await request.body():
        raise HTTPException(status_code=422, detail="Invalid capsule request")


@router.post("", status_code=201, response_model=DirectCapsuleCreated)
def create_direct_capsule(capsule: CreateDirectCapsule, request: Request,
                          user_id: str = Depends(current_user)) -> DirectCapsuleCreated:
    if request.query_params:
        raise HTTPException(status_code=422, detail="Invalid capsule request")
    try:
        return DirectCapsuleRepository().create(user_id, capsule)
    except DatabaseInputError:
        raise HTTPException(status_code=422, detail="Invalid capsule request") from None
    except DatabaseOwnerError:
        raise HTTPException(status_code=403, detail="Unable to create capsule") from None
    except (DatabaseConfigurationError, DatabaseUnavailableError):
        raise HTTPException(status_code=503, detail="Capsule service unavailable") from None


@router.get("/invitations", response_model=list[PendingDirectCapsuleMetadata],
            responses={503: {"description": "Pending discovery is unavailable"}})
def list_pending_invitations(_user_id: str = Depends(current_user),
                             _request: None = Depends(no_extra_request_data)) -> list[PendingDirectCapsuleMetadata]:
    # Never query email or metadata until the Auth transaction boundary is proven.
    raise HTTPException(status_code=503, detail="Capsule service unavailable")


@router.post("/{capsule_id}/claim", response_model=ClaimedDirectCapsuleMetadata,
             responses={503: {"description": "Claiming is unavailable"}})
def claim_direct_capsule(capsule_id: UUID, _user_id: str = Depends(current_user),
                         _request: None = Depends(no_extra_request_data)) -> ClaimedDirectCapsuleMetadata:
    # There is intentionally no claim RPC, even when the feature flag is true.
    raise HTTPException(status_code=503, detail="Capsule service unavailable")


@router.post("/{capsule_id}/cancel", response_model=CapsuleCancellation)
def cancel_direct_capsule(capsule_id: UUID, user_id: str = Depends(current_user),
                          _request: None = Depends(no_extra_request_data)) -> CapsuleCancellation:
    try:
        result = DirectCapsuleRepository().result("aftertime_cancel_direct_capsule", capsule_id,
                                                  user_id, CapsuleCancellation)
    except (DatabaseConfigurationError, DatabaseUnavailableError):
        raise HTTPException(status_code=503, detail="Capsule service unavailable") from None
    if result is None:
        raise HTTPException(status_code=404, detail="Capsule unavailable")
    return result


@router.get("/{capsule_id}/reveal", response_model=CapsuleReveal)
def reveal_direct_capsule(capsule_id: UUID, user_id: str = Depends(current_user),
                          _request: None = Depends(no_extra_request_data)) -> CapsuleReveal:
    try:
        result = DirectCapsuleRepository().result("aftertime_reveal_direct_capsule", capsule_id,
                                                  user_id, CapsuleReveal)
    except (DatabaseConfigurationError, DatabaseUnavailableError):
        raise HTTPException(status_code=503, detail="Capsule service unavailable") from None
    if result is None:
        raise HTTPException(status_code=404, detail="Capsule unavailable")
    return result
