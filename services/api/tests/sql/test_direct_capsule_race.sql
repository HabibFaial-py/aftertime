-- LOCAL DISPOSABLE DATABASE ONLY. This test commits fixtures and temporarily
-- removes a security constraint. NEVER run it in Supabase or a shared database.
\set ON_ERROR_STOP on
DO $$
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Requires disposable aftertime_rpc_test as postgres';
    END IF;
END;
$$;
CREATE EXTENSION dblink;
ALTER TABLE public.direct_capsule_invitations DROP CONSTRAINT direct_capsule_invitations_disabled;
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
    ('00000000-0000-4000-8000-000000000031', 'sender@example.invalid', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000032', 'recipient@example.invalid', clock_timestamp());
INSERT INTO public.direct_capsules (id, owner_id, title, body, created_at, unlock_at)
VALUES ('00000000-0000-4000-8000-000000000033', '00000000-0000-4000-8000-000000000031',
        'synthetic', 'synthetic', now(), now() + interval '1 day');
INSERT INTO public.direct_capsule_invitations (capsule_id, intended_email, created_at, expires_at, claimed_user_id, claimed_at)
VALUES ('00000000-0000-4000-8000-000000000033', 'recipient@example.invalid', now(),
        now() + interval '168 hours', '00000000-0000-4000-8000-000000000032', now());

-- Connect both independent sessions before starting the short unlock window.
SELECT dblink_connect('race_a', 'host=127.0.0.1 port=' || current_setting('port') || ' dbname=aftertime_rpc_test user=postgres');
SELECT dblink_connect('race_b', 'host=127.0.0.1 port=' || current_setting('port') || ' dbname=aftertime_rpc_test user=postgres');
UPDATE public.direct_capsules SET unlock_at = clock_timestamp() + interval '4 seconds'
WHERE id = '00000000-0000-4000-8000-000000000033';

DO $race$
DECLARE v_count bigint;
BEGIN
    PERFORM dblink_exec('race_a', 'BEGIN');
    SELECT n INTO v_count FROM dblink('race_a',
        $$SELECT count(*) FROM public.aftertime_cancel_direct_capsule(
           '00000000-0000-4000-8000-000000000033', '00000000-0000-4000-8000-000000000031')$$) AS r(n bigint);
    IF v_count <> 1 THEN RAISE EXCEPTION 'Cancellation did not acquire the lock before unlock'; END IF;
    PERFORM dblink_send_query('race_b',
        $$SELECT count(*) FROM public.aftertime_reveal_direct_capsule(
           '00000000-0000-4000-8000-000000000033', '00000000-0000-4000-8000-000000000032')$$);
    PERFORM pg_sleep(0.2);
    IF dblink_is_busy('race_b') <> 1 THEN RAISE EXCEPTION 'Reveal did not wait for cancellation'; END IF;
    -- Cross unlock while the cancellation transaction still owns its lock.
    PERFORM pg_sleep(4.5);
    PERFORM dblink_exec('race_a', 'COMMIT');
    SELECT n INTO v_count FROM dblink_get_result('race_b') AS r(n bigint);
    IF v_count <> 0 THEN RAISE EXCEPTION 'Reveal succeeded after committed cancellation'; END IF;
END;
$race$;
SELECT dblink_disconnect('race_a');
SELECT dblink_disconnect('race_b');
DELETE FROM auth.users WHERE id IN ('00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000032');
ALTER TABLE public.direct_capsule_invitations ADD CONSTRAINT direct_capsule_invitations_disabled CHECK (false);
\echo 'Two-session cancellation/reveal race passed; dormant constraint restored.'
