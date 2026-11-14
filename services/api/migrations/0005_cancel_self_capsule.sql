-- Review and validate in a disposable project before application elsewhere.
-- Requires 0001-0004 and a trusted migration session as postgres.
BEGIN;

CREATE FUNCTION public.aftertime_cancel_self_capsule(
    p_capsule_id uuid,
    p_requester_id uuid
)
RETURNS TABLE (id uuid, cancelled_at timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_unlock_at timestamptz;
    v_created_at timestamptz;
    v_cancelled_at timestamptz;
    v_recipient_id uuid;
    v_now timestamptz;
BEGIN
    -- Backend must derive requester from a verified JWT. The privileged
    -- service-role request does not carry the end user's authorization context.
    -- Match reveal's lock order: capsule first, recipient second. Neither
    -- metadata query selects body, media, recipient email or token bytes.
    SELECT c.unlock_at, c.created_at, c.cancelled_at
    INTO v_unlock_at, v_created_at, v_cancelled_at
    FROM public.capsules AS c
    WHERE c.id = p_capsule_id AND c.owner_id = p_requester_id
      AND c.deleted_at IS NULL
    FOR UPDATE OF c;
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

    -- Idempotent retry: once authorized, preserve the original timestamp,
    -- including if the retry occurs after the scheduled unlock time.
    IF v_cancelled_at IS NOT NULL THEN
        RETURN QUERY SELECT p_capsule_id, v_cancelled_at;
        RETURN;
    END IF;

    -- Recheck the wall clock AFTER acquiring both locks. Equality is too late.
    v_now := pg_catalog.clock_timestamp();
    IF v_now < v_created_at OR v_now >= v_unlock_at THEN
        RETURN;
    END IF;

    UPDATE public.capsules AS c
    SET cancelled_at = v_now
    WHERE c.id = p_capsule_id AND c.owner_id = p_requester_id
      AND c.deleted_at IS NULL AND c.cancelled_at IS NULL
      AND c.unlock_at > v_now;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT p_capsule_id, v_now;
EXCEPTION WHEN OTHERS THEN
    -- Never return PostgreSQL error details, which can include full row values.
    -- Propagating this generic failure still rolls back all function changes.
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Cancellation unavailable';
END;
$$;

ALTER FUNCTION public.aftertime_cancel_self_capsule(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_cancel_self_capsule(uuid, uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aftertime_cancel_self_capsule(uuid, uuid)
TO service_role;

COMMIT;
