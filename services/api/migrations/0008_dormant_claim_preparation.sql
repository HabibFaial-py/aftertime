-- DRAFT ONLY: safe preparation; this does not implement or enable claims.
-- The managed Auth email-change transaction boundary remains unverified.
-- Requires 0006 and 0007. Do not apply to a hosted project without review.
BEGIN;

DO $$
BEGIN
    -- Abort on drift: this migration must never weaken the independent gate.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_disabled'
          AND c.convalidated AND pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK (false)'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_capsule_id_fkey'
          AND c.contype = 'f' AND c.confrelid = 'public.direct_capsules'::regclass
          AND c.convalidated
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN
          ('aftertime_claim_direct_capsule', 'aftertime_list_direct_pending', 'aftertime_list_direct_invitations')
    ) THEN
        RAISE EXCEPTION 'Dormant direct-capsule prerequisites not satisfied';
    END IF;
END;
$$;

-- Preparation only; an index does not authorize lookup or enforce expiry.
-- Historical rows with claimed_at set are excluded even after claimant deletion.
CREATE INDEX direct_invitation_pending_lookup_idx
    ON public.direct_capsule_invitations (intended_email, expires_at, id)
    WHERE claimed_at IS NULL;

-- No claim/discovery RPC, policy, privilege, table data, or gate change.
COMMIT;
