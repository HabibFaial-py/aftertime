-- Design draft: review and test on an isolated database before application.
BEGIN;

CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.capsules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(btrim(title)) > 0),
    body text NOT NULL CHECK (char_length(body) <= 2000),
    media_key text,
    unlock_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    cancelled_at timestamptz,
    deleted_at timestamptz,
    CHECK (unlock_at > created_at AND unlock_at <= created_at + interval '90 days'),
    CHECK (cancelled_at IS NULL OR (cancelled_at >= created_at AND cancelled_at < unlock_at)),
    CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    CHECK (cancelled_at IS NULL OR deleted_at IS NULL OR cancelled_at <= deleted_at)
);

CREATE TABLE public.recipients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id uuid NOT NULL UNIQUE REFERENCES public.capsules(id) ON DELETE CASCADE,
    intended_email text NOT NULL CHECK (intended_email = lower(btrim(intended_email)) AND char_length(intended_email) > 0),
    user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    invite_token_hash bytea UNIQUE CHECK (invite_token_hash IS NULL OR octet_length(invite_token_hash) = 32),
    invite_expires_at timestamptz,
    invite_revoked_at timestamptz,
    claimed_at timestamptz,
    opened_at timestamptz,
    CHECK ((invite_token_hash IS NULL AND invite_expires_at IS NULL) OR (invite_token_hash IS NOT NULL AND invite_expires_at IS NOT NULL)),
    CHECK (invite_revoked_at IS NULL OR invite_token_hash IS NOT NULL),
    CHECK (user_id IS NULL OR claimed_at IS NOT NULL),
    -- An unbound claim may remain after ON DELETE SET NULL.
    CHECK (invite_token_hash IS NOT NULL OR claimed_at IS NOT NULL),
    CHECK (opened_at IS NULL OR (claimed_at IS NOT NULL AND opened_at >= claimed_at)),
    CHECK (claimed_at IS NULL OR invite_token_hash IS NULL OR claimed_at < invite_expires_at),
    CHECK (claimed_at IS NULL OR invite_revoked_at IS NULL OR claimed_at < invite_revoked_at),
    UNIQUE (id, capsule_id)
);

CREATE TABLE public.notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id uuid NOT NULL,
    recipient_id uuid NOT NULL,
    kind text NOT NULL CHECK (kind IN ('unlock_email')),
    due_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'leased', 'sent', 'failed', 'cancelled')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at timestamptz NOT NULL,
    lease_until timestamptz,
    sent_at timestamptz,
    provider_message_id text,
    last_error text,
    CHECK ((status = 'leased') = (lease_until IS NOT NULL)),
    CHECK ((status = 'sent') = (sent_at IS NOT NULL)),
    CHECK (status NOT IN ('leased', 'sent', 'failed') OR attempts > 0),
    FOREIGN KEY (recipient_id, capsule_id) REFERENCES public.recipients(id, capsule_id) ON DELETE CASCADE,
    UNIQUE (capsule_id, recipient_id, kind)
);

CREATE TABLE public.blocks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (blocker_id <> blocked_id),
    UNIQUE (blocker_id, blocked_id)
);

CREATE TABLE public.reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    capsule_id uuid NOT NULL REFERENCES public.capsules(id) ON DELETE CASCADE,
    reason text NOT NULL CHECK (char_length(btrim(reason)) > 0),
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'closed')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX capsules_owner_created_idx ON public.capsules (owner_id, created_at DESC);
CREATE INDEX recipients_user_idx ON public.recipients (user_id);
CREATE INDEX notifications_due_idx ON public.notifications (status, next_attempt_at);
CREATE INDEX notifications_lease_idx ON public.notifications (lease_until) WHERE status = 'leased';
CREATE INDEX blocks_blocked_idx ON public.blocks (blocked_id);
CREATE INDEX reports_reporter_idx ON public.reports (reporter_id);
CREATE INDEX reports_capsule_idx ON public.reports (capsule_id);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.capsules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- No client policies: deny by default, including metadata and profiles.
REVOKE ALL ON TABLE public.profiles, public.capsules, public.recipients,
    public.notifications, public.blocks, public.reports FROM PUBLIC, anon, authenticated;

-- Allow trusted server-side operations.
-- Never expose service-role credentials to clients.
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE
    public.profiles,
    public.capsules,
    public.recipients,
    public.notifications,
    public.blocks,
    public.reports
TO service_role;


COMMIT;
