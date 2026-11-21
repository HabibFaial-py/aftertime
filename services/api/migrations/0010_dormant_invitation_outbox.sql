-- DRAFT ONLY. Requires 0001-0009, including the 0007 direct-capsule FK and
-- 0009 digest/claim foundation. No worker, key, delivery or activation.
-- The 0006 gate remains. Do not apply to a hosted database without review.
BEGIN;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_disabled' AND c.convalidated
          AND pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK (false)')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_capsule_id_fkey'
          AND c.contype = 'f' AND c.confrelid = 'public.direct_capsules'::regclass
          AND c.convalidated)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'public.direct_capsule_invitations'::regclass
          AND a.attname = 'claim_secret_digest' AND a.atttypid = 'bytea'::regtype
          AND NOT a.attisdropped)
       OR pg_catalog.to_regprocedure('public.aftertime_claim_direct_capsule(uuid,uuid,bytea)') IS NULL THEN
        RAISE EXCEPTION 'Dormant invitation prerequisites missing';
    END IF;
END;
$$;

-- Collision records survive deletion, but cannot cover rolled-back attempts,
-- independent databases or restores. CSPRNG independence remains essential.
CREATE TABLE public.invitation_outbox_nonces (
    key_id text NOT NULL CHECK (key_id ~ '^[A-Za-z0-9_-]{1,64}$'),
    nonce bytea NOT NULL CHECK (pg_catalog.octet_length(nonce) = 12),
    kdf_salt bytea NOT NULL CHECK (pg_catalog.octet_length(kdf_salt) = 32),
    PRIMARY KEY (key_id, nonce),
    UNIQUE (key_id, kdf_salt),
    UNIQUE (key_id, nonce, kdf_salt)
);
CREATE TABLE public.invitation_delivery_outbox (
    id uuid PRIMARY KEY,
    invitation_id uuid NOT NULL UNIQUE REFERENCES public.direct_capsule_invitations(id) ON DELETE CASCADE,
    key_id text NOT NULL,
    nonce bytea NOT NULL,
    kdf_salt bytea NOT NULL,
    ciphertext bytea,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'cancelled', 'expired')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    next_attempt_at timestamptz,
    finished_at timestamptz,
    FOREIGN KEY (key_id, nonce, kdf_salt) REFERENCES public.invitation_outbox_nonces(key_id, nonce, kdf_salt),
    UNIQUE (key_id, nonce),
    CHECK ((status = 'pending' AND ciphertext IS NOT NULL AND pg_catalog.octet_length(ciphertext) = 59
            AND next_attempt_at IS NOT NULL AND pg_catalog.isfinite(next_attempt_at) AND finished_at IS NULL)
        OR (status <> 'pending' AND ciphertext IS NULL AND next_attempt_at IS NULL
            AND finished_at IS NOT NULL AND pg_catalog.isfinite(finished_at)))
);
ALTER TABLE public.invitation_outbox_nonces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitation_delivery_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.invitation_outbox_nonces, public.invitation_delivery_outbox
FROM PUBLIC, anon, authenticated, service_role;

-- Caller is trusted to derive owner from a verified JWT and encrypt the same
-- generated secret whose digest it submits. No raw secret or key is accepted.
CREATE FUNCTION public.aftertime_create_direct_with_outbox(
    p_owner_id uuid, p_capsule_id uuid, p_invitation_id uuid, p_job_id uuid,
    p_recipient_email text, p_title text, p_body text, p_unlock_at timestamptz,
    p_digest bytea, p_key_id text, p_nonce bytea, p_kdf_salt bytea, p_ciphertext bytea
)
RETURNS TABLE (id uuid, unlock_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' SET timezone = 'UTC'
AS $$
DECLARE
    v_now timestamptz;
BEGIN
    IF p_owner_id IS NULL OR p_capsule_id IS NULL OR p_invitation_id IS NULL OR p_job_id IS NULL
       OR p_title IS NULL OR p_title !~ '[^[:space:]]'
       OR p_body IS NULL OR p_body !~ '[^[:space:]]' OR pg_catalog.char_length(p_body) > 2000
       OR p_recipient_email IS NULL OR p_recipient_email <> pg_catalog.lower(pg_catalog.btrim(p_recipient_email))
       OR pg_catalog.char_length(p_recipient_email) > 254
       OR p_recipient_email !~ '^[^[:space:]@]+@[^[:space:]@]+$'
       OR p_unlock_at IS NULL OR NOT pg_catalog.isfinite(p_unlock_at)
       OR p_digest IS NULL OR pg_catalog.octet_length(p_digest) <> 32
       OR p_key_id IS NULL OR p_key_id !~ '^[A-Za-z0-9_-]{1,64}$'
       OR p_nonce IS NULL OR pg_catalog.octet_length(p_nonce) <> 12
       OR p_kdf_salt IS NULL OR pg_catalog.octet_length(p_kdf_salt) <> 32
       OR p_ciphertext IS NULL OR pg_catalog.octet_length(p_ciphertext) <> 59 THEN
        RAISE EXCEPTION 'Invalid request';
    END IF;
    PERFORM 1 FROM auth.users AS u JOIN public.profiles AS p ON p.id = u.id
    WHERE u.id = p_owner_id AND u.email_confirmed_at IS NOT NULL
      AND u.email IS NOT NULL AND u.email ~ '[^[:space:]]'
      AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.clock_timestamp())
    FOR SHARE OF u, p;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid request'; END IF;
    v_now := pg_catalog.clock_timestamp();
    IF p_unlock_at <= v_now OR p_unlock_at > v_now + interval '90 days' THEN
        RAISE EXCEPTION 'Invalid request';
    END IF;
    INSERT INTO public.direct_capsules (id, owner_id, title, body, unlock_at, created_at)
    VALUES (p_capsule_id, p_owner_id, p_title, p_body, p_unlock_at, v_now);
    INSERT INTO public.direct_capsule_invitations
        (id, capsule_id, intended_email, created_at, expires_at, claim_secret_digest)
    VALUES (p_invitation_id, p_capsule_id, p_recipient_email, v_now, v_now + interval '168 hours', p_digest);
    INSERT INTO public.invitation_outbox_nonces (key_id, nonce, kdf_salt) VALUES (p_key_id, p_nonce, p_kdf_salt);
    INSERT INTO public.invitation_delivery_outbox (id, invitation_id, key_id, nonce, kdf_salt, ciphertext, next_attempt_at)
    VALUES (p_job_id, p_invitation_id, p_key_id, p_nonce, p_kdf_salt, p_ciphertext, v_now);
    RETURN QUERY SELECT p_capsule_id, p_unlock_at, v_now;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Unable to create invitation';
END;
$$;
ALTER FUNCTION public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea)
TO service_role;
COMMIT;
