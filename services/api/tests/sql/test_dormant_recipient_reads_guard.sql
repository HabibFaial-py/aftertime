-- Disposable local PostgreSQL with 0014. The actual direct gate remains in place.
\set ON_ERROR_STOP on
BEGIN;
DO $$ DECLARE
    fn regprocedure;
    role_name name;
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR session_user <> 'postgres'
       OR host(inet_server_addr()) <> '127.0.0.1' OR inet_server_port() <> 55485
       OR current_setting('listen_addresses') <> '127.0.0.1'
       OR current_setting('data_directory') NOT LIKE '%/build/outbox014i1-postgres-014i4'
       OR NOT EXISTS (SELECT FROM pg_constraint
           WHERE conrelid = 'public.direct_capsule_invitations'::regclass
             AND conname = 'direct_capsule_invitations_disabled' AND convalidated
             AND pg_get_constraintdef(oid) = 'CHECK (false)')
       OR to_regclass('public.direct_invitation_claimed_inbox_idx') IS NULL
       OR EXISTS (SELECT FROM pg_class WHERE oid IN ('public.direct_capsules'::regclass,
                    'public.direct_capsule_invitations'::regclass) AND NOT relrowsecurity) THEN
        RAISE EXCEPTION 'Unsafe or unverified dormant recipient database';
    END IF;
    FOREACH fn IN ARRAY ARRAY['public.aftertime_list_received_direct_capsules(uuid,integer,integer)'::regprocedure,
                              'public.aftertime_reveal_direct_capsule(uuid,uuid)'::regprocedure] LOOP
        IF NOT has_function_privilege('service_role', fn, 'EXECUTE')
           OR NOT EXISTS (SELECT FROM pg_proc p WHERE p.oid = fn AND p.prosecdef
                           AND p.proowner = 'postgres'::regrole AND p.proconfig @> ARRAY['search_path=""']) THEN
            RAISE EXCEPTION 'Recipient service function missing its security contract';
        END IF;
        FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'aftertime_invitation_worker'] LOOP
            IF has_function_privilege(role_name, fn, 'EXECUTE') THEN
                RAISE EXCEPTION 'Recipient RPC accessible outside service role';
            END IF;
        END LOOP;
    END LOOP;
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role', 'aftertime_invitation_worker'] LOOP
        IF has_table_privilege(role_name, 'public.direct_capsules', 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege(role_name, 'public.direct_capsule_invitations', 'SELECT,INSERT,UPDATE,DELETE') THEN
            RAISE EXCEPTION 'Recipient tables directly accessible';
        END IF;
    END LOOP;
END $$;

SET LOCAL ROLE authenticated;
DO $$ BEGIN
    BEGIN
        PERFORM public.aftertime_list_received_direct_capsules(NULL, 1, 0);
        RAISE EXCEPTION 'Client could call inbox RPC';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        PERFORM public.aftertime_reveal_direct_capsule(NULL, NULL);
        RAISE EXCEPTION 'Client could call reveal RPC';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- Exercise the actual self RPCs with rollback-only synthetic data. The self
-- capsule must remain invisible to the direct-recipient RPCs at both times.
INSERT INTO auth.users (id, email, email_confirmed_at)
VALUES ('00000000-0000-4000-8000-000000000239', 'self014j3@example.invalid', clock_timestamp());
SET LOCAL ROLE service_role;
CREATE TEMP TABLE self_recipient_probe AS
SELECT * FROM public.aftertime_create_self_capsule('00000000-0000-4000-8000-000000000239',
    'synthetic', 'local self reveal', clock_timestamp() + interval '1 day');
DO $$ DECLARE subject uuid := '00000000-0000-4000-8000-000000000239';
BEGIN
    IF EXISTS (SELECT FROM public.aftertime_reveal_self_capsule((SELECT id FROM self_recipient_probe), subject))
       OR EXISTS (SELECT FROM public.aftertime_list_received_direct_capsules(subject, 50, 0))
       OR EXISTS (SELECT FROM public.aftertime_reveal_direct_capsule((SELECT id FROM self_recipient_probe), subject)) THEN
        RAISE EXCEPTION 'Locked self capsule visible through reveal or recipient inbox';
    END IF;
END $$;
RESET ROLE;
UPDATE public.capsules SET created_at = statement_timestamp() - interval '2 days',
    unlock_at = statement_timestamp() - interval '1 hour' WHERE id = (SELECT id FROM self_recipient_probe);
SET LOCAL ROLE service_role;
DO $$ DECLARE subject uuid := '00000000-0000-4000-8000-000000000239';
BEGIN
    IF NOT EXISTS (SELECT FROM public.aftertime_reveal_self_capsule((SELECT id FROM self_recipient_probe), subject)
        WHERE body = 'local self reveal')
       OR EXISTS (SELECT FROM public.aftertime_list_received_direct_capsules(subject, 50, 0))
       OR EXISTS (SELECT FROM public.aftertime_reveal_direct_capsule((SELECT id FROM self_recipient_probe), subject)) THEN
        RAISE EXCEPTION 'Unlocked self reveal or self/direct isolation failed';
    END IF;
END $$;
ROLLBACK;
\echo 'Dormant recipient permissions, self/direct isolation, and self reveal passed.'
