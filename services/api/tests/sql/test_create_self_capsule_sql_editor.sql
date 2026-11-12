-- SUPABASE SQL EDITOR ONLY: disposable test project, migrations 0001-0003 applied.
-- Select the postgres role. Run this ENTIRE file as one query, not fragments.
-- First create a dedicated confirmed email user through Supabase Auth/Dashboard.
-- Replace BOTH values below with that test user's UUID and exact email.
-- Do not use an actual person's account or an account in concurrent use.
-- No Auth rows are inserted/updated/deleted here. No credentials are needed.
-- All test writes and test-only DDL are rolled back even on success.
-- Expected: Success / no rows returned; PASS notice if the UI shows notices.
-- Any ERROR is a failed or blocked test, never a pass. Do not weaken permissions.

DO $test$
DECLARE
    v_owner uuid := '00000000-0000-0000-0000-000000000000';
    v_expected_email text := 'replace-with-dedicated-test-user-email';
    v_email text;
    v_missing_owner uuid := pg_catalog.gen_random_uuid();
    v_result record;
    v_case record;
    v_keys text[];
    v_state text;
    v_denied boolean;
    v_failed boolean;
    v_completed boolean := false;
    v_capsules bigint;
    v_recipients bigint;
    v_function regprocedure;
    v_helper text := 'aftertime_probe_' || replace(pg_catalog.gen_random_uuid()::text, '-', '');
    v_old_lock_timeout text := current_setting('lock_timeout');
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Select postgres in the SQL Editor role selector';
    END IF;
    IF v_owner = '00000000-0000-0000-0000-000000000000'
       OR v_expected_email = 'replace-with-dedicated-test-user-email' THEN
        RAISE EXCEPTION 'Set the dedicated test user UUID and email first';
    END IF;
    v_function := to_regprocedure('public.aftertime_create_self_capsule(uuid,text,text,timestamptz)');
    IF v_function IS NULL THEN
        RAISE EXCEPTION 'Migration 0003 is required';
    END IF;

    -- This EXCEPTION block is a subtransaction. The deliberate AT999 exception
    -- at its end rolls back successful test writes and DDL before reporting PASS.
    -- Unexpected exceptions propagate and roll back the entire DO statement.
    BEGIN
        PERFORM set_config('lock_timeout', '3s', true);
        SELECT lower(btrim(u.email)) INTO v_email
        FROM auth.users u JOIN public.profiles p ON p.id = u.id
        WHERE u.id = v_owner AND u.email = v_expected_email
          AND u.email_confirmed_at IS NOT NULL
        FOR SHARE OF u, p;
        IF NOT FOUND OR v_email IS NULL OR v_email = '' THEN
            RAISE EXCEPTION 'Dedicated confirmed test user and profile not found';
        END IF;
        IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_missing_owner) THEN
            RAISE EXCEPTION 'Random invalid-owner fixture collided; rerun';
        END IF;

        -- Inspect grants before calls; role switching does not alter any grants.
        IF has_function_privilege('anon', v_function, 'EXECUTE')
           OR has_function_privilege('authenticated', v_function, 'EXECUTE')
           OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
            RAISE EXCEPTION 'Unexpected effective RPC execution privileges';
        END IF;
        IF EXISTS (
            SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
            WHERE p.oid = v_function AND a.privilege_type = 'EXECUTE'
              AND a.grantee NOT IN ('postgres'::regrole::oid, 'service_role'::regrole::oid)
        ) THEN
            RAISE EXCEPTION 'Unexpected explicit RPC execution grant';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p WHERE p.oid = v_function
              AND p.prosecdef AND p.provolatile = 'v' AND p.proowner = 'postgres'::regrole
              AND ARRAY(SELECT lower(s) FROM unnest(p.proconfig) AS settings(s))
                  @> ARRAY['search_path=""', 'timezone=utc']
        ) THEN
            RAISE EXCEPTION 'Unexpected RPC security settings';
        END IF;
        IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relrowsecurity
              AND c.relname IN ('profiles','capsules','recipients','notifications','blocks','reports')) <> 6 THEN
            RAISE EXCEPTION 'Expected all six application tables with RLS enabled';
        END IF;

        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT v_result FROM public.aftertime_create_self_capsule(
            v_owner, 'SQL Editor self-capsule test', repeat('x', 2000),
            clock_timestamp() + interval '89 days');
        EXECUTE 'SET LOCAL ROLE postgres';

        SELECT array_agg(k ORDER BY k) INTO v_keys
        FROM jsonb_object_keys(to_jsonb(v_result)) AS keys(k);
        IF v_keys IS DISTINCT FROM ARRAY['created_at', 'id', 'title', 'unlock_at'] THEN
            RAISE EXCEPTION 'Unsafe metadata projection';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.capsules c JOIN public.recipients r ON r.capsule_id = c.id
            WHERE c.id = v_result.id AND c.owner_id = v_owner AND r.user_id = v_owner
              AND c.title = v_result.title AND c.body = repeat('x', 2000)
              AND c.created_at = v_result.created_at AND c.unlock_at = v_result.unlock_at
              AND c.unlock_at > c.created_at AND c.unlock_at <= c.created_at + interval '90 days'
              AND r.intended_email = v_email AND r.claimed_at = c.created_at
              AND r.invite_token_hash IS NULL AND r.invite_expires_at IS NULL
              AND r.invite_revoked_at IS NULL AND r.opened_at IS NULL
              AND c.media_key IS NULL AND c.cancelled_at IS NULL AND c.deleted_at IS NULL
        ) OR (SELECT count(*) FROM public.recipients WHERE capsule_id = v_result.id) <> 1 THEN
            RAISE EXCEPTION 'Incorrect capsule or self-recipient';
        END IF;
        IF EXISTS (SELECT 1 FROM public.notifications WHERE capsule_id = v_result.id) THEN
            RAISE EXCEPTION 'Unexpected notification for test capsule';
        END IF;

        SELECT count(*) INTO v_capsules FROM public.capsules WHERE owner_id = v_owner;
        SELECT count(*) INTO v_recipients FROM public.recipients WHERE user_id = v_owner;
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
                (v_owner, 'title', 'body', clock_timestamp() + interval '91 days', '22023'),
                (NULL::uuid, 'title', 'body', clock_timestamp() + interval '1 day', '42501'),
                (v_missing_owner, 'title', 'body', clock_timestamp() + interval '1 day', '42501')
            ) AS cases(owner_id, title, body, unlock_at, expected_state)
        LOOP
            v_state := NULL;
            EXECUTE 'SET LOCAL ROLE service_role';
            BEGIN
                PERFORM public.aftertime_create_self_capsule(
                    v_case.owner_id, v_case.title, v_case.body, v_case.unlock_at);
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
            END;
            EXECUTE 'SET LOCAL ROLE postgres';
            IF v_state IS DISTINCT FROM v_case.expected_state THEN
                RAISE EXCEPTION 'Unexpected validation SQLSTATE: expected %, got %', v_case.expected_state, v_state;
            END IF;
        END LOOP;
        IF (SELECT count(*) FROM public.capsules WHERE owner_id = v_owner) <> v_capsules
           OR (SELECT count(*) FROM public.recipients WHERE user_id = v_owner) <> v_recipients THEN
            RAISE EXCEPTION 'Validation failure left test-owner records';
        END IF;

        -- Actual calls under client roles, with valid arguments and a valid owner.
        FOREACH v_state IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            v_denied := false;
            EXECUTE format('SET LOCAL ROLE %I', v_state);
            BEGIN
                PERFORM public.aftertime_create_self_capsule(
                    v_owner, 'Denied call', 'body', clock_timestamp() + interval '1 day');
            EXCEPTION WHEN insufficient_privilege THEN
                v_denied := true;
            END;
            EXECUTE 'SET LOCAL ROLE postgres';
            IF NOT v_denied THEN
                RAISE EXCEPTION 'Client role unexpectedly executed RPC';
            END IF;
        END LOOP;

        -- Unique, uncommitted test helper/trigger. CREATE (not OR REPLACE) cannot
        -- overwrite an existing function. The trigger affects only this owner.
        -- CREATE TRIGGER takes a table lock; use only an idle disposable project.
        EXECUTE format($ddl$
            CREATE FUNCTION public.%I() RETURNS trigger
            LANGUAGE plpgsql SET search_path = '' AS $helper$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM public.capsules c
                    WHERE c.id = NEW.capsule_id AND c.owner_id = NEW.user_id) THEN
                    RAISE EXCEPTION 'Capsule insert did not occur';
                END IF;
                RAISE EXCEPTION USING ERRCODE = 'AT001', MESSAGE = 'Injected recipient failure';
            END;
            $helper$
        $ddl$, v_helper);
        EXECUTE format('REVOKE ALL ON FUNCTION public.%I() FROM PUBLIC, anon, authenticated, service_role', v_helper);
        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT ON public.recipients
            FOR EACH ROW WHEN (NEW.user_id = %L::uuid) EXECUTE FUNCTION public.%I()',
            v_helper, v_owner, v_helper);

        v_failed := false;
        EXECUTE 'SET LOCAL ROLE service_role';
        BEGIN
            PERFORM public.aftertime_create_self_capsule(
                v_owner, 'Rollback probe', 'private test body', clock_timestamp() + interval '1 day');
        EXCEPTION WHEN SQLSTATE 'AT001' THEN
            v_failed := true;
        END;
        EXECUTE 'SET LOCAL ROLE postgres';
        IF NOT v_failed OR (SELECT count(*) FROM public.capsules WHERE owner_id = v_owner) <> v_capsules
           OR (SELECT count(*) FROM public.recipients WHERE user_id = v_owner) <> v_recipients THEN
            RAISE EXCEPTION 'Atomic rollback failed';
        END IF;

        -- Deliberately roll back ALL successful test writes and test-only DDL.
        v_completed := true;
        RAISE EXCEPTION USING ERRCODE = 'AT999', MESSAGE = 'Test cleanup';
    EXCEPTION WHEN SQLSTATE 'AT999' THEN
        IF NOT v_completed THEN
            RAISE EXCEPTION 'Unexpected cleanup SQLSTATE before tests completed';
        END IF;
        -- Rolled-back database changes do not reset PL/pgSQL variable values.
        IF EXISTS (SELECT 1 FROM public.capsules WHERE id = v_result.id)
           OR to_regprocedure(format('public.%I()', v_helper)) IS NOT NULL
           OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = v_helper
                      AND tgrelid = 'public.recipients'::regclass) THEN
            RAISE EXCEPTION 'Test cleanup failed';
        END IF;
        IF current_user <> 'postgres' OR current_setting('lock_timeout') <> v_old_lock_timeout THEN
            RAISE EXCEPTION 'Session settings were not restored';
        END IF;
        RAISE NOTICE 'PASS: creation, safe metadata, validation, privileges, atomic rollback and cleanup. No test writes retained.';
    END;
END;
$test$;
