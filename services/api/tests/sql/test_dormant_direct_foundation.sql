-- TEST ONLY: after bootstrap.sql and migrations 0004-0006, BEFORE 0007, in an empty,
-- disposable plain PostgreSQL cluster. Never run against Supabase.
\set ON_ERROR_STOP on
DO $$
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Requires disposable aftertime_rpc_test as postgres';
    END IF;
END;
$$;

BEGIN;
SET LOCAL TIME ZONE 'America/New_York';

INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
    ('00000000-0000-4000-8000-000000000011', 'sender@example.invalid', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000012', 'recipient@example.invalid', clock_timestamp());

-- The unchanged self create/reveal/cancel RPCs must still work after 0006.
SET LOCAL ROLE service_role;
CREATE TEMP TABLE self_fixture AS
SELECT id FROM public.aftertime_create_self_capsule(
    '00000000-0000-4000-8000-000000000011', 'Synthetic title', 'synthetic text',
    clock_timestamp() + interval '1 day');
CREATE TEMP TABLE unlocked_fixture AS
SELECT id FROM public.aftertime_create_self_capsule(
    '00000000-0000-4000-8000-000000000011', 'Synthetic title', 'synthetic text',
    clock_timestamp() + interval '1 day');
RESET ROLE;
UPDATE public.capsules SET created_at = clock_timestamp() - interval '2 days',
    unlock_at = clock_timestamp() - interval '1 day'
WHERE id = (SELECT id FROM unlocked_fixture);

DO $$
DECLARE
    v_capsule uuid := (SELECT id FROM self_fixture);
    v_sender uuid := '00000000-0000-4000-8000-000000000011';
    v_other uuid := '00000000-0000-4000-8000-000000000012';
    v_first timestamptz;
    v_second timestamptz;
    v_constraint text;
    v_role text;
BEGIN
    IF v_capsule IS NULL OR (SELECT count(*) FROM self_fixture) <> 1 THEN
        RAISE EXCEPTION 'Self creation did not return one capsule';
    END IF;
    IF EXISTS (SELECT 1 FROM public.aftertime_reveal_self_capsule(v_capsule, v_sender))
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_self_capsule(v_capsule, v_other))
       OR EXISTS (SELECT 1 FROM public.aftertime_cancel_self_capsule(v_capsule, v_other)) THEN
        RAISE EXCEPTION 'Locked self or cross-account operation unexpectedly succeeded';
    END IF;
    IF (SELECT count(*) FROM public.aftertime_reveal_self_capsule(
            (SELECT id FROM unlocked_fixture), v_sender)) <> 1
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_self_capsule(
            (SELECT id FROM unlocked_fixture), v_other)) THEN
        RAISE EXCEPTION 'Unlocked self or cross-account reveal regression';
    END IF;
    SELECT cancelled_at INTO v_first FROM public.aftertime_cancel_self_capsule(v_capsule, v_sender);
    SELECT cancelled_at INTO v_second FROM public.aftertime_cancel_self_capsule(v_capsule, v_sender);
    IF v_first IS NULL OR v_first IS DISTINCT FROM v_second
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_self_capsule(v_capsule, v_sender)) THEN
        RAISE EXCEPTION 'Self cancellation or idempotency regression';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.direct_capsule_invitations'::regclass
          AND conname = 'direct_capsule_invitations_disabled' AND convalidated
    ) OR NOT (SELECT relrowsecurity FROM pg_catalog.pg_class
              WHERE oid = 'public.direct_capsule_invitations'::regclass) THEN
        RAISE EXCEPTION 'Dormant constraint or RLS missing';
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF pg_catalog.has_table_privilege(v_role, 'public.direct_capsule_invitations',
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') THEN
            RAISE EXCEPTION 'Unexpected effective invitation-table privilege';
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies
               WHERE schemaname = 'public' AND tablename = 'direct_capsule_invitations') THEN
        RAISE EXCEPTION 'Unexpected invitation RLS policy';
    END IF;

    -- Even the database owner cannot insert a structurally valid dormant row.
    BEGIN
        INSERT INTO public.direct_capsule_invitations
            (capsule_id, intended_email, created_at, expires_at)
        VALUES (v_capsule, 'recipient@example.invalid', now(),
                now() + interval '168 hours');
        RAISE EXCEPTION 'Dormant invitation unexpectedly accepted';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IS DISTINCT FROM 'direct_capsule_invitations_disabled' THEN
            RAISE EXCEPTION 'A different constraint rejected the probe';
        END IF;
    END;
END;
$$;

-- Check real role calls as well as effective ACL metadata above.
SET LOCAL ROLE anon;
DO $$
BEGIN
    BEGIN
        PERFORM 1 FROM public.direct_capsule_invitations;
        RAISE EXCEPTION 'anon unexpectedly read invitations';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END;
$$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
    BEGIN
        PERFORM 1 FROM public.direct_capsule_invitations;
        RAISE EXCEPTION 'authenticated unexpectedly read invitations';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END;
$$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
BEGIN
    BEGIN
        PERFORM 1 FROM public.direct_capsule_invitations;
        RAISE EXCEPTION 'service role unexpectedly read invitations';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END;
$$;
RESET ROLE;

-- Test the independent structural constraints only after temporarily removing
-- the activation gate INSIDE this rolled-back, disposable test transaction.
-- This does not implement or authorize a claim and must never run in Supabase.
ALTER TABLE public.direct_capsule_invitations
    DROP CONSTRAINT direct_capsule_invitations_disabled;

DO $$
DECLARE
    v_capsule uuid := (SELECT id FROM self_fixture);
    v_created timestamptz := '2025-03-08 12:00:00-05'::timestamptz;
    v_claimant uuid := '00000000-0000-4000-8000-000000000012';
    v_case record;
    v_rejected boolean;
BEGIN
    FOR v_case IN SELECT * FROM (VALUES
        (' Unnormalized@example.invalid ', v_created + interval '168 hours', NULL::uuid, NULL::timestamptz),
        ('', v_created + interval '168 hours', NULL::uuid, NULL::timestamptz),
        ('recipient@example.invalid', v_created + interval '167 hours', NULL::uuid, NULL::timestamptz),
        ('recipient@example.invalid', v_created + interval '168 hours', v_claimant, NULL::timestamptz),
        ('recipient@example.invalid', v_created + interval '168 hours', v_claimant, v_created + interval '168 hours')
    ) AS cases(email, expires, claimant, claimed)
    LOOP
        v_rejected := false;
        BEGIN
            INSERT INTO public.direct_capsule_invitations
                (capsule_id, intended_email, created_at, expires_at, claimed_user_id, claimed_at)
            VALUES (v_capsule, v_case.email, v_created, v_case.expires, v_case.claimant, v_case.claimed);
        EXCEPTION WHEN check_violation THEN
            v_rejected := true;
        END;
        IF NOT v_rejected THEN
            RAISE EXCEPTION 'Invalid invitation shape unexpectedly accepted';
        END IF;
    END LOOP;

    -- Across a DST transition this is 168 elapsed hours, not seven local days.
    INSERT INTO public.direct_capsule_invitations
        (capsule_id, intended_email, created_at, expires_at)
    VALUES (v_capsule, 'recipient@example.invalid', v_created, v_created + interval '168 hours');
    v_rejected := false;
    BEGIN
        INSERT INTO public.direct_capsule_invitations
            (capsule_id, intended_email, created_at, expires_at)
        VALUES (v_capsule, 'recipient@example.invalid', v_created, v_created + interval '168 hours');
    EXCEPTION WHEN unique_violation THEN
        v_rejected := true;
    END;
    IF NOT v_rejected THEN
        RAISE EXCEPTION 'Duplicate invitation unexpectedly accepted';
    END IF;
    UPDATE public.direct_capsule_invitations
    SET claimed_user_id = v_claimant, claimed_at = v_created + interval '1 hour'
    WHERE capsule_id = v_capsule;
    IF NOT EXISTS (SELECT 1 FROM public.direct_capsule_invitations
                   WHERE capsule_id = v_capsule AND claimed_user_id = v_claimant AND claimed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Structural binding failed';
    END IF;
    DELETE FROM public.profiles WHERE id = v_claimant;
    IF NOT EXISTS (SELECT 1 FROM public.direct_capsule_invitations
                   WHERE capsule_id = v_capsule AND claimed_user_id IS NULL AND claimed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Deleted claimant history was not preserved';
    END IF;
END;
$$;

ROLLBACK;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
                   WHERE conrelid = 'public.direct_capsule_invitations'::regclass
                     AND conname = 'direct_capsule_invitations_disabled' AND convalidated)
       OR EXISTS (SELECT 1 FROM public.direct_capsule_invitations) THEN
        RAISE EXCEPTION 'Rollback did not restore the dormant foundation';
    END IF;
END;
$$;
\echo 'Dormant foundation SQL checks passed; all test changes rolled back.'
