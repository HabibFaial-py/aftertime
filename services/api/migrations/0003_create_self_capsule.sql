-- Apply only after isolated validation and separate deployment authorization.
-- Requires 0001/0002 and a trusted migration session as postgres.
BEGIN;

CREATE FUNCTION public.aftertime_create_self_capsule(
    p_owner_id uuid,
    p_title text,
    p_body text,
    p_unlock_at timestamptz
)
RETURNS TABLE (id uuid, title text, unlock_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
    v_email text;
    v_now timestamptz;
    v_capsule_id uuid;
BEGIN
    -- No title maximum exists in 0001. Preserve text, rejecting whitespace-only
    -- inputs; body length counts characters, not encoded bytes.
    IF p_title IS NULL OR p_title !~ '[^[:space:]]' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid title';
    END IF;
    IF p_body IS NULL OR p_body !~ '[^[:space:]]'
       OR pg_catalog.char_length(p_body) > 2000 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid body';
    END IF;
    IF p_unlock_at IS NULL OR NOT pg_catalog.isfinite(p_unlock_at) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid unlock time';
    END IF;

    -- p_owner_id is a trusted backend assertion from a verified JWT, NOT public
    -- request data. The service-role session cannot supply the user's auth.uid().
    -- Lock both rows until transaction end, including against email changes.
    SELECT pg_catalog.lower(pg_catalog.btrim(u.email))
    INTO v_email
    FROM auth.users AS u
    JOIN public.profiles AS p ON p.id = u.id
    WHERE u.id = p_owner_id AND u.email_confirmed_at IS NOT NULL
    FOR SHARE OF u, p;

    IF NOT FOUND OR v_email IS NULL OR v_email !~ '[^[:space:]]' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Owner is not eligible';
    END IF;

    -- Capture after any row-lock wait. UTC makes 90 days independent of DST.
    v_now := pg_catalog.clock_timestamp();
    IF p_unlock_at <= v_now OR p_unlock_at > v_now + interval '90 days' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid unlock time';
    END IF;

    INSERT INTO public.capsules AS c
        (owner_id, title, body, unlock_at, created_at,
         media_key, cancelled_at, deleted_at)
    VALUES
        (p_owner_id, p_title, p_body, p_unlock_at, v_now, NULL, NULL, NULL)
    RETURNING c.id INTO v_capsule_id;

    INSERT INTO public.recipients
        (capsule_id, intended_email, user_id, claimed_at,
         invite_token_hash, invite_expires_at, invite_revoked_at, opened_at)
    VALUES
        (v_capsule_id, v_email, p_owner_id, v_now, NULL, NULL, NULL, NULL);

    -- No exception swallowing or intermediate commits: either insert failing
    -- aborts this call. Never return a full capsule or recipient record.
    RETURN QUERY SELECT v_capsule_id, p_title, p_unlock_at, v_now;
END;
$$;

ALTER FUNCTION public.aftertime_create_self_capsule(uuid, text, text, timestamptz)
OWNER TO postgres;

REVOKE ALL ON FUNCTION public.aftertime_create_self_capsule(uuid, text, text, timestamptz)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aftertime_create_self_capsule(uuid, text, text, timestamptz)
TO service_role;

COMMIT;
