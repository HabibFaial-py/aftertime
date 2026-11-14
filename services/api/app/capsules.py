from datetime import datetime, timedelta, timezone
import re
from uuid import UUID
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, StrictStr, field_validator


class CreateCapsule(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: StrictStr
    body: StrictStr
    unlock_at: datetime

    @field_validator("title", "body")
    @classmethod
    def validate_text(cls, value: str, info):
        if not value.strip() or "\x00" in value or (info.field_name == "body" and len(value) > 2000):
            raise ValueError("Invalid text")
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise ValueError("Invalid text") from None
        return value

    @field_validator("unlock_at", mode="before")
    @classmethod
    def require_iso_string(cls, value):
        if not isinstance(value, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})", value
        ):
            raise ValueError("Timestamp must include timezone")
        return value

    @field_validator("unlock_at")
    @classmethod
    def validate_time(cls, value: datetime):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Timestamp must include timezone")
        try:
            value = value.astimezone(timezone.utc)
        except (OverflowError, ValueError):
            raise ValueError("Invalid timestamp") from None
        now = datetime.now(timezone.utc)
        if not now < value <= now + timedelta(days=90):
            raise ValueError("Invalid unlock time")
        return value


class CapsuleMetadata(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    title: StrictStr
    unlock_at: datetime
    created_at: datetime

    @field_validator("unlock_at", "created_at")
    @classmethod
    def utc_time(cls, value: datetime):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Invalid timestamp")
        return value.astimezone(timezone.utc)


class CapsuleListItem(CapsuleMetadata):
    status: Literal["locked", "unlocked"]


class CapsuleReveal(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    body: StrictStr = Field(repr=False, max_length=2000)


class CapsuleCancellation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    cancelled_at: datetime

    @field_validator("cancelled_at", mode="before")
    @classmethod
    def require_timestamp_string(cls, value):
        if not isinstance(value, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})", value
        ):
            raise ValueError("Invalid timestamp")
        return value

    @field_validator("cancelled_at")
    @classmethod
    def utc_time(cls, value: datetime):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Invalid timestamp")
        try:
            return value.astimezone(timezone.utc)
        except (OverflowError, ValueError):
            raise ValueError("Invalid timestamp") from None
