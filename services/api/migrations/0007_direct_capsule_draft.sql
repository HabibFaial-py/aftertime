-- DRAFT ONLY: isolated review/testing. Direct creation remains blocked by 0006.
-- Claim and discovery are intentionally absent until Auth identity is proven.
BEGIN;

-- Separate storage makes existing self RPCs and owner-list queries ineligible.
CREATE TABLE public.direct_capsules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(btrim(title)) > 0),
    body text NOT NULL CHECK (char_length(body) <= 2000),
    unlock_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL,
    cancelled_at timestamptz,
    deleted_at timestamptz,
    CHECK (isfinite(unlock_at) AND isfinite(created_at)),
    CHECK (unlock_at > created_at AND unlock_at <= created_at + interval '90 days'),
    CHECK (cancelled_at IS NULL OR (cancelled_at >= created_at AND cancelled_at < unlock_at)),
    CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    CHECK (cancelled_at IS NULL OR deleted_at IS NULL OR cancelled_at <= deleted_at)
);
ALTER TABLE public.direct_capsules ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.direct_capsules FROM PUBLIC, anon, authenticated, service_role;

-- 0006's CHECK (false) remains in force. Fail if the expected FK drifted.
ALTER TABLE public.direct_capsule_invitations
    DROP CONSTRAINT direct_capsule_invitations_capsule_id_fkey,
    ADD CONSTRAINT direct_capsule_invitations_capsule_id_fkey
    FOREIGN KEY (capsule_id) REFERENCES public.direct_capsules(id) ON DELETE CASCADE;

CREATE FUNCTION public.aftertime_create_direct_capsule(
    p_owner_id uuid, p_recipient_email text, p_title text, p_body text, p_unlock_at timestamptz
)
RETURNS TABLE (id uuid, unlock_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
    v_now timestamptz;
    v_email text := pg_catalog.lower(pg_catalog.btrim(p_recipient_email));
    v_id uuid;
BEGIN
    IF p_title IS NULL OR p_title !~ '[^[:space:]]'
       OR p_body IS NULL OR p_body !~ '[^[:space:]]' OR pg_catalog.char_length(p_body) > 2000
       OR v_email IS NULL OR pg_catalog.char_length(v_email) > 254
       OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+$'
       OR p_unlock_at IS NULL OR NOT pg_catalog.isfinite(p_unlock_at) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid capsule';
    END IF;
    -- Only check the sender; never look up the recipient account.
    PERFORM 1 FROM auth.users AS u JOIN public.profiles AS p ON p.id = u.id
    WHERE u.id = p_owner_id AND u.email_confirmed_at IS NOT NULL
      AND u.email IS NOT NULL AND u.email ~ '[^[:space:]]'
    FOR SHARE OF u, p;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Owner is not eligible';
    END IF;
    v_now := pg_catalog.clock_timestamp();
    IF p_unlock_at <= v_now OR p_unlock_at > v_now + interval '90 days' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid unlock time';
    END IF;
    INSERT INTO public.direct_capsules (owner_id, title, body, unlock_at, created_at)
    VALUES (p_owner_id, p_title, p_body, p_unlock_at, v_now)
    RETURNING direct_capsules.id INTO v_id;
    -- CHECK (false) in 0006 rejects this insert and rolls back the capsule.
    INSERT INTO public.direct_capsule_invitations (capsule_id, intended_email, created_at, expires_at)
    VALUES (v_id, v_email, v_now, v_now + interval '168 hours');
    RETURN QUERY SELECT v_id, p_unlock_at, v_now;
END;
$$;

CREATE FUNCTION public.aftertime_cancel_direct_capsule(p_capsule_id uuid, p_requester_id uuid)
RETURNS TABLE (id uuid, cancelled_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_unlock timestamptz;
    v_created timestamptz;
    v_cancelled timestamptz;
    v_now timestamptz;
BEGIN
    -- Lock capsule, then invitation, matching the existing capsule/recipient order.
    SELECT c.unlock_at, c.created_at, c.cancelled_at INTO v_unlock, v_created, v_cancelled
    FROM public.direct_capsules AS c
    WHERE c.id = p_capsule_id AND c.owner_id = p_requester_id AND c.deleted_at IS NULL
    FOR UPDATE OF c;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.direct_capsule_invitations AS i
    WHERE i.capsule_id = p_capsule_id FOR SHARE OF i;
    IF NOT FOUND THEN RETURN; END IF;
    IF v_cancelled IS NOT NULL THEN
        RETURN QUERY SELECT p_capsule_id, v_cancelled;
        RETURN;
    END IF;
    v_now := pg_catalog.clock_timestamp();
    IF v_now < v_created OR v_now >= v_unlock THEN RETURN; END IF;
    UPDATE public.direct_capsules AS c SET cancelled_at = v_now WHERE c.id = p_capsule_id;
    RETURN QUERY SELECT p_capsule_id, v_now;
END;
$$;

CREATE FUNCTION public.aftertime_reveal_direct_capsule(p_capsule_id uuid, p_requester_id uuid)
RETURNS TABLE (id uuid, body text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_unlock timestamptz;
    v_now timestamptz;
BEGIN
    -- Never read private text until both locks and all checks have succeeded.
    SELECT c.unlock_at INTO v_unlock FROM public.direct_capsules AS c
    WHERE c.id = p_capsule_id AND c.owner_id <> p_requester_id
      AND c.cancelled_at IS NULL AND c.deleted_at IS NULL FOR SHARE OF c;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.direct_capsule_invitations AS i
    WHERE i.capsule_id = p_capsule_id AND i.claimed_user_id = p_requester_id
      AND i.claimed_at IS NOT NULL FOR SHARE OF i;
    IF NOT FOUND THEN RETURN; END IF;
    v_now := pg_catalog.clock_timestamp();
    IF v_now < v_unlock THEN RETURN; END IF;
    RETURN QUERY SELECT c.id, c.body FROM public.direct_capsules AS c
    WHERE c.id = p_capsule_id AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
      AND c.unlock_at <= v_now;
END;
$$;

ALTER FUNCTION public.aftertime_create_direct_capsule(uuid, text, text, text, timestamptz) OWNER TO postgres;
ALTER FUNCTION public.aftertime_cancel_direct_capsule(uuid, uuid) OWNER TO postgres;
ALTER FUNCTION public.aftertime_reveal_direct_capsule(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_create_direct_capsule(uuid, text, text, text, timestamptz),
    public.aftertime_cancel_direct_capsule(uuid, uuid), public.aftertime_reveal_direct_capsule(uuid, uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aftertime_create_direct_capsule(uuid, text, text, text, timestamptz),
    public.aftertime_cancel_direct_capsule(uuid, uuid), public.aftertime_reveal_direct_capsule(uuid, uuid)
TO service_role;

COMMIT;
