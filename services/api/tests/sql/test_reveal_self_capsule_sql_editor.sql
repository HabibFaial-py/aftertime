-- ONLY an idle, disposable Supabase project with migrations 0001-0004 applied.
-- Use postgres in SQL Editor; run this entire DO block at once, not fragments.
-- Replace BOTH UUIDs with distinct dedicated test users having profiles.
-- No Auth users are inserted or modified. All capsule fixtures are rolled back.
-- Expected: success/no rows; a PASS notice if the UI displays NOTICE messages.
-- Any error means failure or unmet prerequisites. No credentials are required.
DO $test$
DECLARE
    v_owner uuid := '00000000-0000-0000-0000-000000000000';
    v_other uuid := '00000000-0000-0000-0000-000000000000';
    v_open uuid := pg_catalog.gen_random_uuid();
    v_locked uuid := pg_catalog.gen_random_uuid();
    v_cancelled uuid := pg_catalog.gen_random_uuid();
    v_deleted uuid := pg_catalog.gen_random_uuid();
    v_missing_recipient uuid := pg_catalog.gen_random_uuid();
    v_unbound_recipient uuid := pg_catalog.gen_random_uuid();
    v_invited uuid := pg_catalog.gen_random_uuid();
    v_missing uuid := pg_catalog.gen_random_uuid();
    v_function regprocedure;
    v_now timestamptz := pg_catalog.clock_timestamp();
    v_row record;
    v_keys text[];
    v_case record;
    v_count bigint;
    v_role text;
    v_denied boolean;
    v_invalid_uuid boolean := false;
    v_completed boolean := false;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Select postgres in the SQL Editor role selector';
    END IF;
    IF v_owner = '00000000-0000-0000-0000-000000000000'
       OR v_other = '00000000-0000-0000-0000-000000000000'
       OR v_owner = v_other THEN
        RAISE EXCEPTION 'Set two distinct dedicated test user UUIDs';
    END IF;
    v_function := pg_catalog.to_regprocedure('public.aftertime_reveal_self_capsule(uuid,uuid)');
    IF v_function IS NULL THEN
        RAISE EXCEPTION 'Migration 0004 is required';
    END IF;

    -- All inserts/updates and row locks are inside a rollback-only subtransaction.
    -- Use two existing test profiles; never create or modify Auth users.
    BEGIN
        PERFORM pg_catalog.set_config('lock_timeout', '3s', true);
        IF (SELECT count(*) FROM public.profiles p WHERE p.id IN (v_owner, v_other)) <> 2 THEN
            RAISE EXCEPTION 'Dedicated test profiles not found';
        END IF;
        IF EXISTS (SELECT 1 FROM public.capsules c WHERE c.id IN
            (v_open, v_locked, v_cancelled, v_deleted, v_missing_recipient, v_unbound_recipient, v_invited, v_missing)) THEN
            RAISE EXCEPTION 'Random fixture ID collision; rerun';
        END IF;

        INSERT INTO public.capsules (id, owner_id, title, body, created_at, unlock_at, cancelled_at, deleted_at)
        VALUES
            (v_open, v_owner, 'Reveal test', 'synthetic reveal text', v_now - interval '2 hours', v_now - interval '1 hour', NULL, NULL),
            (v_locked, v_owner, 'Locked test', 'synthetic locked text', v_now - interval '2 hours', v_now + interval '1 hour', NULL, NULL),
            (v_cancelled, v_owner, 'Cancelled test', 'synthetic cancelled text', v_now - interval '2 hours', v_now - interval '1 hour', v_now - interval '90 minutes', NULL),
            (v_deleted, v_owner, 'Deleted test', 'synthetic deleted text', v_now - interval '2 hours', v_now - interval '1 hour', NULL, v_now - interval '30 minutes'),
            (v_missing_recipient, v_owner, 'Missing recipient', 'synthetic text', v_now - interval '2 hours', v_now - interval '1 hour', NULL, NULL),
            (v_unbound_recipient, v_owner, 'Unbound recipient', 'synthetic text', v_now - interval '2 hours', v_now - interval '1 hour', NULL, NULL),
            (v_invited, v_owner, 'Invited recipient', 'synthetic text', v_now - interval '2 hours', v_now - interval '1 hour', NULL, NULL);

        INSERT INTO public.recipients (capsule_id, intended_email, user_id, claimed_at)
        SELECT id, 'fixture@example.invalid', v_owner, v_now - interval '2 hours'
        FROM public.capsules WHERE id IN (v_open, v_locked, v_cancelled, v_deleted);
        -- A historical claim without a bound user is not authorization.
        INSERT INTO public.recipients (capsule_id, intended_email, user_id, claimed_at)
        VALUES (v_unbound_recipient, 'fixture@example.invalid', NULL, v_now - interval '2 hours');
        -- Even an invitation claimed by the owner is not a self-recipient row.
        INSERT INTO public.recipients
            (capsule_id, intended_email, user_id, claimed_at, invite_token_hash, invite_expires_at)
        VALUES (v_invited, 'fixture@example.invalid', v_owner, v_now - interval '2 hours',
                pg_catalog.decode(pg_catalog.repeat('ab', 32), 'hex'), v_now + interval '1 day');

        IF pg_catalog.has_function_privilege('anon', v_function, 'EXECUTE')
           OR pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
           OR NOT pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE') THEN
            RAISE EXCEPTION 'Incorrect effective function permissions';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p,
            LATERAL pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
            WHERE p.oid = v_function AND a.privilege_type = 'EXECUTE'
              AND a.grantee NOT IN ('postgres'::regrole::oid, 'service_role'::regrole::oid)) THEN
            RAISE EXCEPTION 'Unexpected explicit function grant';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid = v_function
            AND p.prosecdef AND p.provolatile = 'v' AND p.proowner = 'postgres'::regrole
            AND EXISTS (SELECT 1 FROM pg_catalog.unnest(p.proconfig) s
                        WHERE s IN ('search_path=""', 'search_path='))) THEN
            RAISE EXCEPTION 'Incorrect function security settings';
        END IF;
        IF (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relrowsecurity
              AND c.relname IN ('profiles','capsules','recipients','notifications','blocks','reports')) <> 6 THEN
            RAISE EXCEPTION 'RLS is not enabled on all application tables';
        END IF;

        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT v_row FROM public.aftertime_reveal_self_capsule(v_open, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        SELECT array_agg(k ORDER BY k) INTO v_keys FROM pg_catalog.jsonb_object_keys(pg_catalog.to_jsonb(v_row)) AS keys(k);
        IF v_keys IS DISTINCT FROM ARRAY['body', 'id'] OR v_row.id <> v_open
           OR v_row.body <> 'synthetic reveal text' THEN
            RAISE EXCEPTION 'Unexpected successful reveal projection';
        END IF;

        FOR v_case IN SELECT * FROM (VALUES
            (v_open, v_other), (v_locked, v_owner), (v_cancelled, v_owner),
            (v_deleted, v_owner), (v_missing_recipient, v_owner),
            (v_unbound_recipient, v_owner), (v_invited, v_owner),
            (v_missing, v_owner), (NULL::uuid, v_owner), (v_open, NULL::uuid)
        ) AS cases(capsule_id, requester_id)
        LOOP
            EXECUTE 'SET LOCAL ROLE service_role';
            SELECT count(*) INTO v_count FROM public.aftertime_reveal_self_capsule(v_case.capsule_id, v_case.requester_id);
            EXECUTE 'SET LOCAL ROLE postgres';
            IF v_count <> 0 THEN
                RAISE EXCEPTION 'A denial returned data';
            END IF;
        END LOOP;

        -- Typed PostgreSQL parameters reject malformed UUID strings before the
        -- RPC runs. The eventual HTTP layer must hide the cast/validation detail.
        BEGIN
            PERFORM public.aftertime_reveal_self_capsule('invalid-uuid'::text::uuid, v_owner);
        EXCEPTION WHEN invalid_text_representation THEN
            v_invalid_uuid := true;
        END;
        IF NOT v_invalid_uuid THEN
            RAISE EXCEPTION 'Malformed UUID was unexpectedly accepted';
        END IF;

        -- Set an unlock instant at the database clock, then call immediately.
        -- This tests equality-or-later; exact microsecond equality is not forced.
        UPDATE public.capsules SET unlock_at = pg_catalog.clock_timestamp() WHERE id = v_locked;
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT count(*) INTO v_count FROM public.aftertime_reveal_self_capsule(v_locked, v_owner);
        EXECUTE 'SET LOCAL ROLE postgres';
        IF v_count <> 1 THEN
            RAISE EXCEPTION 'At/after unlock unexpectedly denied';
        END IF;

        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF pg_catalog.has_column_privilege(v_role, 'public.capsules', 'body', 'SELECT') THEN
                RAISE EXCEPTION 'Client role has direct body SELECT privilege';
            END IF;
            EXECUTE pg_catalog.format('SET LOCAL ROLE %I', v_role);
            v_denied := false;
            BEGIN
                PERFORM public.aftertime_reveal_self_capsule(v_open, v_owner);
            EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
            END;
            IF NOT v_denied THEN
                RAISE EXCEPTION 'Client role executed reveal RPC';
            END IF;
            v_denied := false;
            BEGIN
                PERFORM c.body FROM public.capsules c WHERE c.id = v_open;
            EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
            END;
            IF NOT v_denied THEN
                RAISE EXCEPTION 'Client role directly selected body';
            END IF;
            EXECUTE 'SET LOCAL ROLE postgres';
        END LOOP;

        v_completed := true;
        RAISE EXCEPTION USING ERRCODE = 'AT999', MESSAGE = 'Rollback test fixtures';
    EXCEPTION WHEN SQLSTATE 'AT999' THEN
        IF NOT v_completed THEN
            RAISE EXCEPTION 'Unexpected cleanup signal';
        END IF;
        IF EXISTS (SELECT 1 FROM public.capsules c WHERE c.id IN
            (v_open, v_locked, v_cancelled, v_deleted, v_missing_recipient, v_unbound_recipient, v_invited)) THEN
            RAISE EXCEPTION 'Fixture rollback failed';
        END IF;
        RAISE NOTICE 'PASS: self-reveal checks and rollback completed.';
    END;
END;
$test$;
