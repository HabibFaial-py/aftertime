-- ONLY an idle, disposable Supabase project with migrations 0001-0005 applied.
-- Select postgres in SQL Editor. Replace BOTH UUIDs with distinct dedicated
-- test users having profiles. Run this entire DO block, not a selection.
-- No Auth users are modified. All synthetic fixture changes are rolled back.
-- Expected: success/no rows; a PASS notice if the UI displays notices.
DO $test$
DECLARE
    v_owner uuid := '00000000-0000-0000-0000-000000000000';
    v_other uuid := '00000000-0000-0000-0000-000000000000';
    v_locked uuid := pg_catalog.gen_random_uuid();
    v_cross uuid := pg_catalog.gen_random_uuid();
    v_open uuid := pg_catalog.gen_random_uuid();
    v_deleted uuid := pg_catalog.gen_random_uuid();
    v_no_recipient uuid := pg_catalog.gen_random_uuid();
    v_unbound uuid := pg_catalog.gen_random_uuid();
    v_other_recipient uuid := pg_catalog.gen_random_uuid();
    v_invited uuid := pg_catalog.gen_random_uuid();
    v_boundary uuid := pg_catalog.gen_random_uuid();
    v_error_fixture uuid := pg_catalog.gen_random_uuid();
    v_missing uuid := pg_catalog.gen_random_uuid();
    v_function regprocedure;
    v_now timestamptz := pg_catalog.clock_timestamp();
    v_original timestamptz;
    v_row record;
    v_case record;
    v_keys text[];
    v_count bigint;
    v_role text;
    v_denied boolean;
    v_completed boolean := false;
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_helper text := 'aftertime_cancel_probe_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Select postgres in the SQL Editor role selector';
    END IF;
    IF v_owner = '00000000-0000-0000-0000-000000000000'
       OR v_other = '00000000-0000-0000-0000-000000000000'
       OR v_owner = v_other THEN
        RAISE EXCEPTION 'Set two distinct dedicated test user UUIDs';
    END IF;
    v_function := pg_catalog.to_regprocedure('public.aftertime_cancel_self_capsule(uuid,uuid)');
    IF v_function IS NULL OR pg_catalog.to_regprocedure('public.aftertime_reveal_self_capsule(uuid,uuid)') IS NULL THEN
        RAISE EXCEPTION 'Migrations 0004 and 0005 are required';
    END IF;

    -- Catching AT999 rolls back all fixtures even after successful assertions.
    BEGIN
        PERFORM pg_catalog.set_config('lock_timeout', '3s', true);
        IF (SELECT count(*) FROM public.profiles p WHERE p.id IN (v_owner, v_other)) <> 2 THEN
            RAISE EXCEPTION 'Dedicated test profiles not found';
        END IF;
        IF EXISTS (SELECT 1 FROM public.capsules c WHERE c.id IN
            (v_locked, v_cross, v_open, v_deleted, v_no_recipient, v_unbound, v_other_recipient, v_invited, v_boundary, v_error_fixture, v_missing)) THEN
            RAISE EXCEPTION 'Random fixture collision; rerun';
        END IF;

        INSERT INTO public.capsules (id, owner_id, title, body, created_at, unlock_at, deleted_at)
        VALUES
            (v_locked, v_owner, 'Cancel test', 'synthetic locked text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_cross, v_owner, 'Cross-user test', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_open, v_owner, 'Unlocked test', 'synthetic private text', v_now - interval '2 hours', v_now - interval '1 hour', NULL),
            (v_deleted, v_owner, 'Deleted test', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', v_now - interval '30 minutes'),
            (v_no_recipient, v_owner, 'No recipient', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_unbound, v_owner, 'Unbound recipient', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_other_recipient, v_owner, 'Other recipient', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_invited, v_owner, 'Invitation recipient', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_boundary, v_owner, 'Boundary test', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL),
            (v_error_fixture, v_owner, 'Error test', 'synthetic private text', v_now - interval '2 hours', v_now + interval '1 hour', NULL);

        INSERT INTO public.recipients (capsule_id, intended_email, user_id, claimed_at)
        SELECT c.id, 'fixture@example.invalid', v_owner, v_now - interval '2 hours'
        FROM public.capsules c WHERE c.id IN (v_locked, v_cross, v_open, v_deleted, v_boundary, v_error_fixture);
        INSERT INTO public.recipients (capsule_id, intended_email, user_id, claimed_at)
        VALUES (v_unbound, 'fixture@example.invalid', NULL, v_now - interval '2 hours'),
               (v_other_recipient, 'fixture@example.invalid', v_other, v_now - interval '2 hours');
        INSERT INTO public.recipients (capsule_id, intended_email, user_id, claimed_at, invite_token_hash, invite_expires_at)
        VALUES (v_invited, 'fixture@example.invalid', v_owner, v_now - interval '2 hours',
                pg_catalog.decode(pg_catalog.repeat('ab', 32), 'hex'), v_now + interval '1 day');

        IF pg_catalog.has_function_privilege('anon', v_function, 'EXECUTE')
           OR pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
           OR NOT pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE') THEN
            RAISE EXCEPTION 'Incorrect effective RPC permissions';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p,
            LATERAL pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
            WHERE p.oid = v_function AND a.privilege_type = 'EXECUTE'
              AND a.grantee NOT IN ('postgres'::regrole::oid, 'service_role'::regrole::oid)) THEN
            RAISE EXCEPTION 'Unexpected explicit RPC grant';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid = v_function
            AND p.prosecdef AND p.provolatile = 'v' AND p.proowner = 'postgres'::regrole
            AND EXISTS (SELECT 1 FROM pg_catalog.unnest(p.proconfig) s
                        WHERE s IN ('search_path=""', 'search_path='))) THEN
            RAISE EXCEPTION 'Incorrect RPC security settings';
        END IF;
        IF (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relrowsecurity
              AND c.relname IN ('profiles','capsules','recipients','notifications','blocks','reports')) <> 6 THEN
            RAISE EXCEPTION 'RLS is not enabled on all application tables';
        END IF;

        -- Compare the actual return shape without displaying its values.
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT v_row FROM public.aftertime_cancel_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        SELECT array_agg(k ORDER BY k) INTO v_keys FROM pg_catalog.jsonb_object_keys(pg_catalog.to_jsonb(v_row)) AS keys(k);
        IF v_keys IS DISTINCT FROM ARRAY['cancelled_at', 'id'] OR v_row.id <> v_locked
           OR v_row.cancelled_at IS NULL THEN
            RAISE EXCEPTION 'Unexpected successful cancellation projection';
        END IF;
        v_original := v_row.cancelled_at;
        IF NOT EXISTS (SELECT 1 FROM public.capsules c WHERE c.id = v_locked
            AND c.cancelled_at = v_original AND c.cancelled_at >= c.created_at AND c.cancelled_at < c.unlock_at) THEN
            RAISE EXCEPTION 'Incorrect cancellation timestamp';
        END IF;

        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT count(*) INTO v_count FROM public.aftertime_reveal_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_count <> 0 THEN RAISE EXCEPTION 'Cancelled capsule unexpectedly revealed'; END IF;

        -- Repeat is idempotent; it returns the original timestamp unchanged.
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT v_row FROM public.aftertime_cancel_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_row.cancelled_at IS DISTINCT FROM v_original THEN
            RAISE EXCEPTION 'Repeated cancellation changed timestamp';
        END IF;
        -- Simulate a retry after the original cancellation's unlock time.
        -- The update touches only this rolled-back fixture and keeps CHECKs valid.
        UPDATE public.capsules SET unlock_at = v_original + interval '1 microsecond' WHERE id = v_locked;
        PERFORM pg_catalog.pg_sleep(0.01);
        IF pg_catalog.clock_timestamp() <= v_original + interval '1 microsecond' THEN
            RAISE EXCEPTION 'Clock did not advance past fixture unlock';
        END IF;
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT v_row FROM public.aftertime_cancel_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_row.cancelled_at IS DISTINCT FROM v_original THEN
            RAISE EXCEPTION 'Post-unlock retry changed timestamp';
        END IF;

        -- A historical claim without the original self binding must not make
        -- an otherwise idempotent retry succeed.
        UPDATE public.recipients SET user_id = NULL WHERE capsule_id = v_locked;
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT count(*) INTO v_count FROM public.aftertime_cancel_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_count <> 0 THEN RAISE EXCEPTION 'Unbound repeat unexpectedly succeeded'; END IF;
        UPDATE public.recipients SET user_id = v_owner WHERE capsule_id = v_locked;

        FOR v_case IN SELECT * FROM (VALUES
            (v_cross, v_other), (v_open, v_owner), (v_deleted, v_owner),
            (v_no_recipient, v_owner), (v_unbound, v_owner),
            (v_other_recipient, v_owner), (v_invited, v_owner),
            (v_missing, v_owner), (NULL::uuid, v_owner), (v_cross, NULL::uuid)
        ) AS cases(capsule_id, requester_id)
        LOOP
            EXECUTE 'SET LOCAL ROLE service_role';
            SELECT count(*) INTO v_count FROM public.aftertime_cancel_self_capsule(v_case.capsule_id, v_case.requester_id);
            EXECUTE 'SET LOCAL ROLE postgres';
            IF v_count <> 0 THEN RAISE EXCEPTION 'A denial returned data'; END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM public.capsules c WHERE c.id IN
            (v_cross, v_open, v_deleted, v_no_recipient, v_unbound, v_other_recipient, v_invited)
            AND c.cancelled_at IS NOT NULL) THEN
            RAISE EXCEPTION 'A denial modified a capsule';
        END IF;

        -- Setting unlock to database time and then calling tests equality-or-
        -- later denial, but does not force exact microsecond equality.
        UPDATE public.capsules SET unlock_at = pg_catalog.clock_timestamp() WHERE id = v_boundary;
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT count(*) INTO v_count FROM public.aftertime_cancel_self_capsule(v_boundary, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_count <> 0 OR EXISTS (SELECT 1 FROM public.capsules WHERE id = v_boundary AND cancelled_at IS NOT NULL) THEN
            RAISE EXCEPTION 'At/after-unlock cancellation unexpectedly succeeded';
        END IF;

        -- Test-only, uncommitted DDL on an idle disposable project. A unique
        -- helper/trigger targets only this fixture and is rolled back below.
        EXECUTE pg_catalog.format($ddl$
            CREATE FUNCTION public.%I() RETURNS trigger
            LANGUAGE plpgsql SET search_path = '' AS $helper$
            BEGIN
                RAISE EXCEPTION USING ERRCODE = 'AT001', MESSAGE = 'synthetic private error',
                    DETAIL = 'synthetic private row';
            END;
            $helper$
        $ddl$, v_helper);
        EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.%I() FROM PUBLIC, anon, authenticated, service_role', v_helper);
        EXECUTE pg_catalog.format('CREATE TRIGGER %I BEFORE UPDATE ON public.capsules
            FOR EACH ROW WHEN (NEW.id = %L::uuid) EXECUTE FUNCTION public.%I()',
            v_helper, v_error_fixture, v_helper);
        EXECUTE 'SET LOCAL ROLE service_role';
        BEGIN
            PERFORM public.aftertime_cancel_self_capsule(v_error_fixture, v_owner);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_state = RETURNED_SQLSTATE,
                v_error_message = MESSAGE_TEXT, v_error_detail = PG_EXCEPTION_DETAIL;
        END;
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_error_state IS DISTINCT FROM 'P0001'
           OR v_error_message IS DISTINCT FROM 'Cancellation unavailable'
           OR COALESCE(v_error_detail, '') <> ''
           OR EXISTS (SELECT 1 FROM public.capsules WHERE id = v_error_fixture AND cancelled_at IS NOT NULL) THEN
            RAISE EXCEPTION 'Failure was not sanitized or rolled back';
        END IF;

        -- Deleted state overrides even a previously cancelled self-capsule.
        UPDATE public.capsules SET deleted_at = pg_catalog.clock_timestamp() WHERE id = v_locked;
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT count(*) INTO v_count FROM public.aftertime_cancel_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_count <> 0 THEN RAISE EXCEPTION 'Deleted repeat unexpectedly succeeded'; END IF;

        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF pg_catalog.has_column_privilege(v_role, 'public.capsules', 'cancelled_at', 'UPDATE') THEN
                RAISE EXCEPTION 'Client role has direct cancellation UPDATE privilege';
            END IF;
            EXECUTE pg_catalog.format('SET LOCAL ROLE %I', v_role);
            v_denied := false;
            BEGIN
                PERFORM public.aftertime_cancel_self_capsule(v_cross, v_owner);
            EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
            END;
            IF NOT v_denied THEN RAISE EXCEPTION 'Client role executed cancellation RPC'; END IF;
            v_denied := false;
            BEGIN
                UPDATE public.capsules SET cancelled_at = pg_catalog.clock_timestamp() WHERE id = v_cross;
            EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
            END;
            IF NOT v_denied THEN RAISE EXCEPTION 'Client role directly updated capsule'; END IF;
            EXECUTE 'SET LOCAL ROLE postgres';
        END LOOP;

        v_completed := true;
        RAISE EXCEPTION USING ERRCODE = 'AT999', MESSAGE = 'Rollback test fixtures';
    EXCEPTION WHEN SQLSTATE 'AT999' THEN
        IF NOT v_completed THEN RAISE EXCEPTION 'Unexpected cleanup signal'; END IF;
        IF EXISTS (SELECT 1 FROM public.capsules c WHERE c.id IN
            (v_locked, v_cross, v_open, v_deleted, v_no_recipient, v_unbound, v_other_recipient, v_invited, v_boundary, v_error_fixture)) THEN
            RAISE EXCEPTION 'Fixture rollback failed';
        END IF;
        IF pg_catalog.to_regprocedure(pg_catalog.format('public.%I()', v_helper)) IS NOT NULL
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgname = v_helper
                      AND tgrelid = 'public.capsules'::regclass) THEN
            RAISE EXCEPTION 'Test-only DDL rollback failed';
        END IF;
        RAISE NOTICE 'PASS: self-cancellation checks and rollback completed.';
    END;
END;
$test$;
