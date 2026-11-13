-- Review and test in an isolated environment before applying elsewhere.
-- Requires 0001-0003 and a trusted migration session as postgres.
BEGIN;

CREATE FUNCTION public.aftertime_reveal_self_capsule(
    p_capsule_id uuid,
    p_requester_id uuid
)
RETURNS TABLE (id uuid, body text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_unlock_at timestamptz;
    v_recipient_id uuid;
    v_now timestamptz;
BEGIN
    -- The caller is trusted backend code and MUST derive p_requester_id from
    -- the verified JWT. A service-role request does not carry the user's JWT.
    -- Lock metadata only: never fetch body before the eligibility checks.
    -- Lock order: capsule first, then its recipient. Future writers must use
    -- the same order to serialize cancellation, deletion and recipient changes.
    SELECT c.unlock_at INTO v_unlock_at
    FROM public.capsules AS c
    WHERE c.id = p_capsule_id AND c.owner_id = p_requester_id
      AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
    FOR SHARE OF c;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT r.id INTO v_recipient_id
    FROM public.recipients AS r
    WHERE r.capsule_id = p_capsule_id AND r.user_id = p_requester_id
      AND r.claimed_at IS NOT NULL AND r.invite_token_hash IS NULL
      AND r.invite_expires_at IS NULL AND r.invite_revoked_at IS NULL
    FOR SHARE OF r;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Capture wall clock after potential lock waits; equality is eligible.
    v_now := pg_catalog.clock_timestamp();
    IF v_unlock_at > v_now THEN
        RETURN;
    END IF;

    -- The locked capsule and recipient cannot change before transaction end.
    -- No media, recipient, email, invitation or internal fields are returned.
    RETURN QUERY SELECT c.id, c.body
    FROM public.capsules AS c
    WHERE c.id = p_capsule_id AND c.owner_id = p_requester_id
      AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
      AND c.unlock_at <= v_now;
END;
$$;

ALTER FUNCTION public.aftertime_reveal_self_capsule(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_reveal_self_capsule(uuid, uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aftertime_reveal_self_capsule(uuid, uuid)
TO service_role;

COMMIT;
