-- LOCAL DISPOSABLE DATABASE ONLY, after bootstrap and migrations 0004-0008.
-- This tests closed gates, not claim eligibility or actual claim races.
\set ON_ERROR_STOP on
DO $$
DECLARE v_role text;
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Requires disposable aftertime_rpc_test as postgres';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
          AND c.conname = 'direct_capsule_invitations_disabled' AND c.convalidated
          AND pg_get_constraintdef(c.oid) = 'CHECK (false)') THEN
        RAISE EXCEPTION 'Creation gate was changed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'direct_capsule_invitations'
          AND indexname = 'direct_invitation_pending_lookup_idx'
          AND indexdef LIKE '%(intended_email, expires_at, id)%WHERE (claimed_at IS NULL)%') THEN
        RAISE EXCEPTION 'Dormant pending index is missing or incorrect';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN
          ('aftertime_claim_direct_capsule', 'aftertime_list_direct_pending', 'aftertime_list_direct_invitations')) THEN
        RAISE EXCEPTION 'Claim or discovery RPC unexpectedly exists';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class WHERE oid IN ('public.direct_capsules'::regclass,
                 'public.direct_capsule_invitations'::regclass) AND NOT relrowsecurity)
       OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename IN ('direct_capsules', 'direct_capsule_invitations')) THEN
        RAISE EXCEPTION 'Direct table RLS changed';
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF has_table_privilege(v_role, 'public.direct_capsule_invitations',
                               'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
            RAISE EXCEPTION 'Direct invitation privilege unexpectedly granted';
        END IF;
    END LOOP;
END;
$$;

-- Two independent local sessions concurrently attempt the nonexistent claim
-- function. This proves only that calls fail closed, not race-safe claiming.
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT dblink_connect('claim_a', 'host=127.0.0.1 port=' || current_setting('port') || ' dbname=aftertime_rpc_test user=postgres');
SELECT dblink_connect('claim_b', 'host=127.0.0.1 port=' || current_setting('port') || ' dbname=aftertime_rpc_test user=postgres');
DO $test$
DECLARE v_error text;
BEGIN
    PERFORM dblink_send_query('claim_a',
        $$SELECT public.aftertime_claim_direct_capsule('00000000-0000-4000-8000-000000000041'::uuid,
                                                       '00000000-0000-4000-8000-000000000042'::uuid)$$);
    PERFORM dblink_send_query('claim_b',
        $$SELECT public.aftertime_claim_direct_capsule('00000000-0000-4000-8000-000000000041'::uuid,
                                                       '00000000-0000-4000-8000-000000000043'::uuid)$$);
    PERFORM * FROM dblink_get_result('claim_a', false) AS t(value text);
    v_error := dblink_error_message('claim_a');
    IF v_error NOT LIKE '%does not exist%' THEN RAISE EXCEPTION 'First missing claim RPC did not fail closed'; END IF;
    PERFORM * FROM dblink_get_result('claim_b', false) AS t(value text);
    v_error := dblink_error_message('claim_b');
    IF v_error NOT LIKE '%does not exist%' THEN RAISE EXCEPTION 'Second missing claim RPC did not fail closed'; END IF;
END;
$test$;
SELECT dblink_disconnect('claim_a');
SELECT dblink_disconnect('claim_b');
\echo 'Dormant claim preparation checks passed; no claim was performed.'
