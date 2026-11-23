-- DRAFT ONLY. Requires 0001-0013 and the validated dormant invitation gate.
BEGIN;
LOCK TABLE public.direct_capsule_invitations IN ACCESS SHARE MODE;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_disabled' AND c.convalidated
          AND pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK (false)')
       OR pg_catalog.to_regprocedure('public.aftertime_claim_direct_capsule(uuid,uuid,bytea)') IS NULL
       OR pg_catalog.to_regprocedure('public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)') IS NULL THEN
        RAISE EXCEPTION 'Dormant recipient prerequisites missing';
    END IF;
END $$;

CREATE INDEX direct_invitation_claimed_inbox_idx
    ON public.direct_capsule_invitations (claimed_user_id, capsule_id)
    WHERE claimed_at IS NOT NULL AND revoked_at IS NULL AND claim_secret_digest IS NULL;

-- Trusted callers derive p_requester_id from a verified JWT. This snapshot
-- exposes only bound-recipient metadata and never authorizes reveal.
CREATE FUNCTION public.aftertime_list_received_direct_capsules(
    p_requester_id uuid, p_limit integer, p_offset integer
)
RETURNS TABLE (id uuid, sender_id uuid, created_at timestamptz, unlock_at timestamptz, status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_now timestamptz := pg_catalog.statement_timestamp();
BEGIN
    IF p_requester_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
       OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 10000 THEN RETURN; END IF;

    RETURN QUERY
    SELECT c.id, c.owner_id, c.created_at, c.unlock_at,
           CASE WHEN c.unlock_at <= v_now THEN 'unlocked' ELSE 'locked' END
    FROM public.direct_capsule_invitations i
    JOIN public.direct_capsules c ON c.id = i.capsule_id
    WHERE i.claimed_user_id = p_requester_id AND i.claimed_at IS NOT NULL AND i.claimed_at <= v_now
      AND i.revoked_at IS NULL AND i.claim_secret_digest IS NULL
      AND c.owner_id <> p_requester_id AND c.created_at <= v_now
      AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
      AND EXISTS (SELECT 1 FROM auth.users u JOIN public.profiles p ON p.id = u.id
                  WHERE u.id = p_requester_id AND u.deleted_at IS NULL
                    AND (u.banned_until IS NULL OR u.banned_until <= v_now))
    ORDER BY c.created_at DESC, c.id DESC LIMIT p_limit OFFSET p_offset;
END $$;

-- Harden the existing service RPC so callers cannot bypass account checks via
-- the earlier draft. Use the claim lock order and read the body only at the end.
CREATE OR REPLACE FUNCTION public.aftertime_reveal_direct_capsule(p_capsule_id uuid, p_requester_id uuid)
RETURNS TABLE (id uuid, body text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_banned_until timestamptz;
    v_created_at timestamptz;
    v_unlock_at timestamptz;
    v_claimed_at timestamptz;
    v_now timestamptz;
BEGIN
    IF p_capsule_id IS NULL OR p_requester_id IS NULL THEN RETURN; END IF;

    SELECT u.banned_until INTO v_banned_until FROM auth.users u
    WHERE u.id = p_requester_id AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.clock_timestamp())
    FOR SHARE OF u;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.profiles p WHERE p.id = p_requester_id FOR SHARE OF p;
    IF NOT FOUND THEN RETURN; END IF;

    -- The binding prefilter avoids locking someone else's capsule. The locked
    -- invitation read below repeats the authorization checks.
    SELECT c.created_at, c.unlock_at INTO v_created_at, v_unlock_at
    FROM public.direct_capsules c
    WHERE c.id = p_capsule_id AND c.owner_id <> p_requester_id
      AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
      AND EXISTS (SELECT FROM public.direct_capsule_invitations i
                  WHERE i.capsule_id = c.id AND i.claimed_user_id = p_requester_id
                    AND i.claimed_at IS NOT NULL)
    FOR SHARE OF c;
    IF NOT FOUND THEN RETURN; END IF;

    SELECT i.claimed_at INTO v_claimed_at FROM public.direct_capsule_invitations i
    WHERE i.capsule_id = p_capsule_id AND i.claimed_user_id = p_requester_id
      AND i.claimed_at IS NOT NULL AND i.revoked_at IS NULL AND i.claim_secret_digest IS NULL
    FOR SHARE OF i;
    IF NOT FOUND THEN RETURN; END IF;

    -- Expiry limits the original claim. The established binding survives it.
    v_now := pg_catalog.clock_timestamp();
    IF v_created_at > v_now OR v_claimed_at > v_now OR v_unlock_at > v_now
       OR (v_banned_until IS NOT NULL AND v_banned_until > v_now) THEN RETURN; END IF;

    RETURN QUERY SELECT c.id, c.body FROM public.direct_capsules c WHERE c.id = p_capsule_id;
END $$;

ALTER FUNCTION public.aftertime_list_received_direct_capsules(uuid, integer, integer) OWNER TO postgres;
ALTER FUNCTION public.aftertime_reveal_direct_capsule(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_list_received_direct_capsules(uuid, integer, integer),
    public.aftertime_reveal_direct_capsule(uuid, uuid)
FROM PUBLIC, anon, authenticated, service_role, aftertime_invitation_worker;
GRANT EXECUTE ON FUNCTION public.aftertime_list_received_direct_capsules(uuid, integer, integer),
    public.aftertime_reveal_direct_capsule(uuid, uuid) TO service_role;
COMMIT;
