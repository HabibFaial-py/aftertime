-- Run only after bootstrap.sql in its disposable plain PostgreSQL cluster.
\set ON_ERROR_STOP on
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Requires disposable aftertime_rpc_test as postgres';
    END IF;
END;
$$;

INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
    ('00000000-0000-4000-8000-000000000001', ' Self@Example.invalid ', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000002', 'unconfirmed@example.invalid', NULL),
    ('00000000-0000-4000-8000-000000000003', NULL, clock_timestamp()),
    ('00000000-0000-4000-8000-000000000004', 'missing-profile@example.invalid', clock_timestamp());
DELETE FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000004';

-- Real SQL-role invocation: neither a JWT nor a secret is needed.
SET LOCAL ROLE service_role;
CREATE TEMP TABLE creation_result AS
SELECT * FROM public.aftertime_create_self_capsule(
    '00000000-0000-4000-8000-000000000001', 'Test title', repeat('x', 2000),
    clock_timestamp() + interval '90 days'
);
RESET ROLE;

DO $$
DECLARE
    v_result record;
    v_keys text[];
BEGIN
    IF (SELECT count(*) FROM creation_result) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one result';
    END IF;
    SELECT * INTO STRICT v_result FROM creation_result;
    SELECT array_agg(k ORDER BY k) INTO v_keys
    FROM jsonb_object_keys(to_jsonb(v_result)) AS keys(k);
    IF v_keys <> ARRAY['created_at', 'id', 'title', 'unlock_at'] THEN
        RAISE EXCEPTION 'Unsafe metadata projection';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.capsules c JOIN public.recipients r ON r.capsule_id = c.id
        WHERE c.id = v_result.id
          AND c.owner_id = '00000000-0000-4000-8000-000000000001'
          AND r.user_id = c.owner_id AND r.intended_email = 'self@example.invalid'
          AND c.title = v_result.title AND c.body = repeat('x', 2000)
          AND c.created_at = v_result.created_at AND c.unlock_at = v_result.unlock_at
          AND c.unlock_at > c.created_at
          AND c.unlock_at <= c.created_at + interval '90 days'
          AND r.claimed_at = c.created_at AND r.opened_at IS NULL
          AND r.invite_token_hash IS NULL AND r.invite_expires_at IS NULL
          AND r.invite_revoked_at IS NULL AND c.media_key IS NULL
          AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Incorrect capsule or self-recipient';
    END IF;
    IF EXISTS (SELECT 1 FROM public.notifications) THEN
        RAISE EXCEPTION 'Unexpected notification';
    END IF;
END;
$$;

-- Validation failures must have the expected SQLSTATE and leave no extra rows.
DO $$
DECLARE
    v_case record;
    v_state text;
    v_capsules bigint := (SELECT count(*) FROM public.capsules);
    v_recipients bigint := (SELECT count(*) FROM public.recipients);
    v_owner uuid := '00000000-0000-4000-8000-000000000001';
BEGIN
    FOR v_case IN
        SELECT * FROM (VALUES
            (v_owner, NULL::text, 'body', clock_timestamp() + interval '1 day', '22023'),
            (v_owner, '', 'body', clock_timestamp() + interval '1 day', '22023'),
            (v_owner, E' \t\n', 'body', clock_timestamp() + interval '1 day', '22023'),
            (v_owner, 'title', NULL, clock_timestamp() + interval '1 day', '22023'),
            (v_owner, 'title', '', clock_timestamp() + interval '1 day', '22023'),
            (v_owner, 'title', E' \t\n', clock_timestamp() + interval '1 day', '22023'),
            (v_owner, 'title', repeat('x', 2001), clock_timestamp() + interval '1 day', '22023'),
            (v_owner, 'title', 'body', NULL, '22023'),
            (v_owner, 'title', 'body', '-infinity'::timestamptz, '22023'),
            (v_owner, 'title', 'body', 'infinity'::timestamptz, '22023'),
            (v_owner, 'title', 'body', clock_timestamp() - interval '1 day', '22023'),
            (v_owner, 'title', 'body', clock_timestamp(), '22023'),
            (v_owner, 'title', 'body', clock_timestamp() + interval '90 days 1 hour', '22023'),
            (NULL::uuid, 'title', 'body', clock_timestamp() + interval '1 day', '42501'),
            ('00000000-0000-4000-8000-000000000099'::uuid, 'title', 'body', clock_timestamp() + interval '1 day', '42501'),
            ('00000000-0000-4000-8000-000000000002'::uuid, 'title', 'body', clock_timestamp() + interval '1 day', '42501'),
            ('00000000-0000-4000-8000-000000000003'::uuid, 'title', 'body', clock_timestamp() + interval '1 day', '42501'),
            ('00000000-0000-4000-8000-000000000004'::uuid, 'title', 'body', clock_timestamp() + interval '1 day', '42501')
        ) AS cases(owner_id, title, body, unlock_at, expected_state)
    LOOP
        v_state := NULL;
        BEGIN
            PERFORM public.aftertime_create_self_capsule(
                v_case.owner_id, v_case.title, v_case.body, v_case.unlock_at);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
        END;
        IF v_state IS DISTINCT FROM v_case.expected_state THEN
            RAISE EXCEPTION 'Unexpected validation outcome: expected %, got %', v_case.expected_state, v_state;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.capsules) <> v_capsules
       OR (SELECT count(*) FROM public.recipients) <> v_recipients THEN
        RAISE EXCEPTION 'Validation failure left rows';
    END IF;
END;
$$;

-- Force the SECOND insert to fail after proving the first insert occurred.
CREATE FUNCTION public.aftertime_test_fail_recipient() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.capsules c WHERE c.id = NEW.capsule_id) THEN
        RAISE EXCEPTION 'Capsule insert did not occur';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'AT001', MESSAGE = 'Injected recipient failure';
END;
$$;
CREATE TRIGGER aftertime_test_fail_recipient BEFORE INSERT ON public.recipients
FOR EACH ROW EXECUTE FUNCTION public.aftertime_test_fail_recipient();

DO $$
DECLARE
    v_capsules bigint := (SELECT count(*) FROM public.capsules);
    v_recipients bigint := (SELECT count(*) FROM public.recipients);
    v_failed boolean := false;
BEGIN
    BEGIN
        PERFORM public.aftertime_create_self_capsule(
            '00000000-0000-4000-8000-000000000001', 'Rollback probe', 'Private test text',
            clock_timestamp() + interval '1 day');
    EXCEPTION WHEN SQLSTATE 'AT001' THEN
        v_failed := true;
    END;
    IF NOT v_failed OR (SELECT count(*) FROM public.capsules) <> v_capsules
       OR (SELECT count(*) FROM public.recipients) <> v_recipients THEN
        RAISE EXCEPTION 'Atomic rollback failed';
    END IF;
END;
$$;
DROP TRIGGER aftertime_test_fail_recipient ON public.recipients;
DROP FUNCTION public.aftertime_test_fail_recipient();

DO $$
DECLARE
    v_function regprocedure := 'public.aftertime_create_self_capsule(uuid,text,text,timestamptz)'::regprocedure;
BEGIN
    IF has_function_privilege('anon', v_function, 'EXECUTE')
       OR has_function_privilege('authenticated', v_function, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
        RAISE EXCEPTION 'Incorrect effective execution privileges';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
        WHERE p.oid = v_function AND a.privilege_type = 'EXECUTE'
          AND a.grantee NOT IN ('postgres'::regrole::oid, 'service_role'::regrole::oid)
    ) THEN
        RAISE EXCEPTION 'Unexpected execution grant (including PUBLIC)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = v_function
        AND p.prosecdef AND p.provolatile = 'v' AND p.proowner = 'postgres'::regrole
        AND ARRAY(SELECT lower(setting) FROM unnest(p.proconfig) AS settings(setting))
            @> ARRAY['search_path=""', 'timezone=utc']) THEN
        RAISE EXCEPTION 'Incorrect function security settings';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN ('profiles','capsules','recipients','notifications','blocks','reports')
          AND NOT c.relrowsecurity) THEN
        RAISE EXCEPTION 'RLS disabled';
    END IF;
END;
$$;

-- Verify actual denied calls, not only ACL metadata.
SET LOCAL ROLE anon;
DO $$
BEGIN
    BEGIN
        PERFORM public.aftertime_create_self_capsule(
            '00000000-0000-4000-8000-000000000001', 'Denied', 'body', clock_timestamp() + interval '1 day');
        RAISE EXCEPTION 'anon unexpectedly executed RPC';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END;
$$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
    BEGIN
        PERFORM public.aftertime_create_self_capsule(
            '00000000-0000-4000-8000-000000000001', 'Denied', 'body', clock_timestamp() + interval '1 day');
        RAISE EXCEPTION 'authenticated unexpectedly executed RPC';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END;
$$;
RESET ROLE;
ROLLBACK;
\echo 'Self-capsule SQL checks passed; test rows and failure trigger rolled back.'
