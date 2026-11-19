-- Draft only: the 0006 CHECK (false) gate remains in force.
-- The service must derive p_claimant_id from a verified session and pass only
-- SHA-256 of a uniformly random 32-byte secret, never the secret itself.
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_disabled'
          AND c.convalidated AND pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK (false)') THEN
        RAISE EXCEPTION 'Dormant invitation gate missing';
    END IF;
END;
$$;

ALTER TABLE public.direct_capsule_invitations
    ADD COLUMN claim_secret_digest bytea UNIQUE
        CHECK (claim_secret_digest IS NULL OR pg_catalog.octet_length(claim_secret_digest) = 32),
    ADD COLUMN revoked_at timestamptz
        CHECK (revoked_at IS NULL OR pg_catalog.isfinite(revoked_at));

CREATE FUNCTION public.aftertime_claim_direct_capsule(
    p_capsule_id uuid, p_claimant_id uuid, p_secret_digest bytea
)
RETURNS TABLE (id uuid, created_at timestamptz, unlock_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_created timestamptz;
    v_unlock timestamptz;
    v_expires timestamptz;
    v_invitation_created timestamptz;
    v_now timestamptz;
BEGIN
    IF p_capsule_id IS NULL OR p_claimant_id IS NULL OR p_secret_digest IS NULL
       OR pg_catalog.octet_length(p_secret_digest) <> 32 THEN RETURN; END IF;

    -- Lock Auth then profile, followed by capsule then invitation. Actual
    -- managed account deletion and session revocation remain unverified.
    PERFORM 1 FROM auth.users AS u
    WHERE u.id = p_claimant_id AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.clock_timestamp())
    FOR SHARE OF u;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.profiles AS p WHERE p.id = p_claimant_id FOR SHARE OF p;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT c.created_at, c.unlock_at INTO v_created, v_unlock
    FROM public.direct_capsules AS c
    WHERE c.id = p_capsule_id AND c.owner_id <> p_claimant_id
      AND c.cancelled_at IS NULL AND c.deleted_at IS NULL FOR UPDATE OF c;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT i.created_at, i.expires_at INTO v_invitation_created, v_expires FROM public.direct_capsule_invitations AS i
    WHERE i.capsule_id = p_capsule_id AND i.claimed_at IS NULL
      AND i.claimed_user_id IS NULL AND i.revoked_at IS NULL
      AND i.claim_secret_digest = p_secret_digest FOR UPDATE OF i;
    IF NOT FOUND THEN RETURN; END IF;
    v_now := pg_catalog.clock_timestamp();
    IF v_now < v_created OR v_now < v_invitation_created OR v_now >= v_expires THEN RETURN; END IF;
    UPDATE public.direct_capsule_invitations AS i
    SET claimed_user_id = p_claimant_id, claimed_at = v_now, claim_secret_digest = NULL
    WHERE i.capsule_id = p_capsule_id;
    RETURN QUERY SELECT p_capsule_id, v_created, v_unlock;
END;
$$;

ALTER FUNCTION public.aftertime_claim_direct_capsule(uuid, uuid, bytea) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_claim_direct_capsule(uuid, uuid, bytea)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.aftertime_claim_direct_capsule(uuid, uuid, bytea) TO service_role;
COMMIT;
