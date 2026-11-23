from uuid import UUID

import pytest
from pydantic import SecretStr

from app.invitation_claim import (
    ClaimOutcome, InvalidInvitation, build_invitation_link, claim_invitation, parse_invitation_link,
)


CAPSULE = UUID("eb0c61a6-6aa1-4ab9-9170-03916980370f")
SECRET = "A" * 43  # Canonical synthetic value.


def test_link_has_only_capsule_id_in_path_and_masks_secret():
    link = build_invitation_link(CAPSULE, SecretStr(SECRET))
    assert link.get_secret_value() == f"https://aftertime.example.invalid/invite/{CAPSULE}#{SECRET}"
    parsed = parse_invitation_link(link)
    assert parsed.capsule_id == CAPSULE
    assert parsed.claim.secret.get_secret_value() == SECRET
    assert all(SECRET not in value for value in (str(link), repr(link), repr(parsed), repr(parsed.claim)))


@pytest.mark.parametrize("tamper", [
    lambda text: text.replace("https:", "http:"),
    lambda text: text.replace("aftertime.example.invalid", "other.example.invalid"),
    lambda text: text.replace("https://", "https://user@"),
    lambda text: text.replace("/invite/", "/invite//"),
    lambda text: text.replace("/invite/", "/old/"),
    lambda text: text.replace(str(CAPSULE), str(CAPSULE).upper()),
    lambda text: text.replace("#", "?secret="),
    lambda text: text.replace("#", "?x=1#"),
    lambda text: text.replace("#", "/"),
    lambda text: text.replace("#", "%23"),
    lambda text: text.replace("#", "##"),
    lambda text: text.replace("#", "#secret="),
    lambda text: text[:-1] + "B",  # Noncanonical pad bits for the same decoded bytes.
    lambda text: text[:-1] + "\n",
    lambda text: text + "=",
    lambda text: text + "A" * 10000,
])
def test_parser_rejects_tampered_and_noncanonical_links(tamper):
    link = build_invitation_link(CAPSULE, SECRET).get_secret_value()
    with pytest.raises(InvalidInvitation, match="^Invalid invitation$") as exc:
        parse_invitation_link(tamper(link))
    assert SECRET not in repr(exc.value) and link not in repr(exc.value)


@pytest.mark.parametrize("bad", [SECRET[:-1], SECRET[:-1] + "B", SECRET + "=", "x" * 10000, "!" * 43])
def test_builder_rejects_invalid_secrets_without_echoing_them(bad):
    with pytest.raises(InvalidInvitation, match="^Invalid invitation$") as exc:
        build_invitation_link(CAPSULE, bad)
    assert bad not in str(exc.value)


@pytest.mark.parametrize("confirmation", [False, None, 1])
def test_claim_requires_explicit_boolean_confirmation(confirmation):
    def unexpected_connection():
        pytest.fail("Opened link must not start a claim transaction")

    link = build_invitation_link(CAPSULE, SECRET)
    result = claim_invitation(link, None, confirmed=confirmation, connection_factory=unexpected_connection)
    assert result.outcome is ClaimOutcome.CONFIRMATION_REQUIRED
    assert result.capsule is None
