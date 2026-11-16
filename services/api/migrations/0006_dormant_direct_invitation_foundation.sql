-- DORMANT FOUNDATION ONLY. Review and test in a disposable database before use.
-- Direct capsules, discovery, claims, cancellation and reveal remain disabled.
-- Auth email-change concurrency and self/direct isolation are security blockers.
-- Do not remove the disabled constraint or grant access in this migration.
BEGIN;

CREATE TABLE public.direct_capsule_invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id uuid NOT NULL UNIQUE REFERENCES public.capsules(id) ON DELETE CASCADE,
    intended_email text NOT NULL
        CHECK (intended_email = lower(btrim(intended_email)) AND char_length(intended_email) > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    claimed_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    claimed_at timestamptz,
    CHECK (isfinite(created_at) AND isfinite(expires_at)),
    CHECK (expires_at = created_at + interval '168 hours'),
    CHECK (claimed_user_id IS NULL OR claimed_at IS NOT NULL),
    -- A claimed row can become unbound if its profile is deleted. It must never
    -- be treated as a new invitation merely because claimed_user_id is NULL.
    CHECK (claimed_at IS NULL OR (isfinite(claimed_at)
        AND claimed_at >= created_at AND claimed_at < expires_at)),
    -- Database-level activation gate: even a privileged INSERT must fail.
    CONSTRAINT direct_capsule_invitations_disabled CHECK (false)
);

ALTER TABLE public.direct_capsule_invitations ENABLE ROW LEVEL SECURITY;

-- No policies and no application privileges, including for the service role.
-- Effective inherited privileges must also be checked in the target database.
REVOKE ALL ON TABLE public.direct_capsule_invitations
FROM PUBLIC, anon, authenticated, service_role;

-- No existing table, recipient constraint, self RPC, or function grant changes.
-- A later security-reviewed migration must first enforce self/direct isolation,
-- verified identity, cancellation/reveal ordering and safe metadata projection.
COMMIT;
