-- LOCAL DISPOSABLE DATABASE ONLY; never run in Supabase.
-- Apply bootstrap and 0004-0007 first. All changes below roll back.
\set ON_ERROR_STOP on
DO $$
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Requires disposable aftertime_rpc_test as postgres';
    END IF;
END;
$$;
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
    ('00000000-0000-4000-8000-000000000021', 'sender@example.invalid', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000022', 'recipient@example.invalid', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000023', 'other@example.invalid', clock_timestamp());

DO $$
DECLARE
    v_constraint text;
    v_role text;
    v_func regprocedure;
BEGIN
    -- The production draft remains blocked even when the RPC is callable.
    BEGIN
        PERFORM public.aftertime_create_direct_capsule(
            '00000000-0000-4000-8000-000000000021', 'recipient@example.invalid',
            'synthetic', 'synthetic', clock_timestamp() + interval '1 day');
        RAISE EXCEPTION 'Dormant creation unexpectedly succeeded';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint <> 'direct_capsule_invitations_disabled' THEN
            RAISE EXCEPTION 'Unexpected constraint failure';
        END IF;
    END;
    IF EXISTS (SELECT 1 FROM public.direct_capsules) OR EXISTS (SELECT 1 FROM public.direct_capsule_invitations) THEN
        RAISE EXCEPTION 'Blocked creation was not atomic';
    END IF;
    IF to_regprocedure('public.aftertime_claim_direct_capsule(uuid,uuid)') IS NOT NULL
       OR to_regprocedure('public.aftertime_list_direct_invitations(uuid)') IS NOT NULL THEN
        RAISE EXCEPTION 'Unreviewed claim/discovery RPC exists';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class WHERE oid IN ('public.direct_capsules'::regclass,
                                                    'public.direct_capsule_invitations'::regclass)
               AND NOT relrowsecurity)
       OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename IN ('direct_capsules', 'direct_capsule_invitations')) THEN
        RAISE EXCEPTION 'Unexpected RLS configuration';
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF has_table_privilege(v_role, 'public.direct_capsules', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
           OR has_table_privilege(v_role, 'public.direct_capsule_invitations', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
            RAISE EXCEPTION 'Unexpected effective table privilege';
        END IF;
    END LOOP;
    FOREACH v_func IN ARRAY ARRAY[
        'public.aftertime_create_direct_capsule(uuid,text,text,text,timestamptz)'::regprocedure,
        'public.aftertime_cancel_direct_capsule(uuid,uuid)'::regprocedure,
        'public.aftertime_reveal_direct_capsule(uuid,uuid)'::regprocedure
    ] LOOP
        IF has_function_privilege('anon', v_func, 'EXECUTE')
           OR has_function_privilege('authenticated', v_func, 'EXECUTE')
           OR NOT has_function_privilege('service_role', v_func, 'EXECUTE')
           OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = v_func AND p.prosecdef
                          AND p.proowner = 'postgres'::regrole AND p.proconfig @> ARRAY['search_path=""']) THEN
            RAISE EXCEPTION 'Unexpected function privileges or security settings';
        END IF;
    END LOOP;
END;
$$;

-- Test-only override in a rolled-back transaction. This does not implement a
-- claim or establish verified email and must never be copied to a live system.
ALTER TABLE public.direct_capsule_invitations DROP CONSTRAINT direct_capsule_invitations_disabled;

SET LOCAL ROLE service_role;
CREATE TEMP TABLE direct_a AS SELECT * FROM public.aftertime_create_direct_capsule(
    '00000000-0000-4000-8000-000000000021', 'recipient@example.invalid',
    'synthetic title', 'synthetic body', clock_timestamp() + interval '1 day');
CREATE TEMP TABLE direct_b AS SELECT * FROM public.aftertime_create_direct_capsule(
    '00000000-0000-4000-8000-000000000021', 'not-registered@example.invalid',
    'synthetic title', 'synthetic body', clock_timestamp() + interval '1 day');
RESET ROLE;

DO $$
DECLARE
    a uuid := (SELECT id FROM direct_a);
    b uuid := (SELECT id FROM direct_b);
    owner_id uuid := '00000000-0000-4000-8000-000000000021';
    recipient_id uuid := '00000000-0000-4000-8000-000000000022';
    other_id uuid := '00000000-0000-4000-8000-000000000023';
    cancelled_1 timestamptz;
    cancelled_2 timestamptz;
BEGIN
    IF a IS NULL OR b IS NULL OR EXISTS (SELECT 1 FROM public.capsules WHERE id IN (a, b))
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_self_capsule(a, owner_id))
       OR EXISTS (SELECT 1 FROM public.aftertime_cancel_self_capsule(a, owner_id)) THEN
        RAISE EXCEPTION 'Self/direct isolation failed';
    END IF;
    IF EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(a, owner_id))
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(a, recipient_id))
       OR EXISTS (SELECT 1 FROM public.aftertime_cancel_direct_capsule(a, other_id)) THEN
        RAISE EXCEPTION 'Unclaimed or unauthorized operation succeeded';
    END IF;
    -- Synthetic binding only: no verified-email claim exists.
    UPDATE public.direct_capsule_invitations SET claimed_user_id = recipient_id, claimed_at = created_at
    WHERE capsule_id = a;
    IF EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(a, recipient_id)) THEN
        RAISE EXCEPTION 'Locked direct reveal succeeded';
    END IF;
    SELECT cancelled_at INTO cancelled_1 FROM public.aftertime_cancel_direct_capsule(a, owner_id);
    SELECT cancelled_at INTO cancelled_2 FROM public.aftertime_cancel_direct_capsule(a, owner_id);
    IF cancelled_1 IS NULL OR cancelled_1 IS DISTINCT FROM cancelled_2
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(a, recipient_id)) THEN
        RAISE EXCEPTION 'Cancellation or repeat behavior failed';
    END IF;
    UPDATE public.direct_capsule_invitations SET claimed_user_id = recipient_id, claimed_at = created_at
    WHERE capsule_id = b;
    UPDATE public.direct_capsules SET created_at = clock_timestamp() - interval '2 days',
        unlock_at = clock_timestamp() - interval '1 day' WHERE id = b;
    IF (SELECT count(*) FROM public.aftertime_reveal_direct_capsule(b, recipient_id)) <> 1
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(b, owner_id))
       OR EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(b, other_id))
       OR EXISTS (SELECT 1 FROM public.aftertime_cancel_direct_capsule(b, owner_id)) THEN
        RAISE EXCEPTION 'Unlocked direct authorization failed';
    END IF;
    -- Even a fabricated owner binding cannot turn a direct capsule into self reveal.
    UPDATE public.direct_capsule_invitations SET claimed_user_id = owner_id WHERE capsule_id = b;
    IF EXISTS (SELECT 1 FROM public.aftertime_reveal_direct_capsule(b, owner_id)) THEN
        RAISE EXCEPTION 'Sender revealed a direct capsule';
    END IF;
    UPDATE public.direct_capsule_invitations SET claimed_user_id = recipient_id WHERE capsule_id = b;
    -- Invitation expiry governs pending claims, not an already-bound recipient.
    UPDATE public.direct_capsule_invitations SET created_at = now() - interval '8 days',
        expires_at = now() - interval '1 day', claimed_at = now() - interval '8 days'
    WHERE capsule_id = b;
    IF (SELECT count(*) FROM public.aftertime_reveal_direct_capsule(b, recipient_id)) <> 1 THEN
        RAISE EXCEPTION 'Claimed recipient unexpectedly expired';
    END IF;
END;
$$;
ROLLBACK;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.direct_capsule_invitations'::regclass
                   AND conname = 'direct_capsule_invitations_disabled' AND convalidated) THEN
        RAISE EXCEPTION 'Dormant constraint not restored';
    END IF;
END;
$$;
\echo 'Direct draft SQL checks passed; test-only activation rolled back.'
