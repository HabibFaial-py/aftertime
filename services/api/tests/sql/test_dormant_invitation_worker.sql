-- Disposable loopback cluster only, after migrations 0011 and 0012. Creates
-- committed synthetic fixture objects for independent dblink transactions.
\set ON_ERROR_STOP on
BEGIN;
\ir setup_local_encrypted_outbox.sql
DO $$ DECLARE definition text; BEGIN
  definition := pg_get_functiondef('public.aftertime_invitation_worker_candidates()'::regprocedure);
  definition := replace(definition, 'FUNCTION public.', 'FUNCTION fixture014i4.');
  definition := replace(definition, 'public.invitation_delivery_outbox', 'fixture014i4.invitation_delivery_outbox');
  EXECUTE definition;
  definition := pg_get_functiondef('public.aftertime_invitation_worker_transition(uuid,uuid,text)'::regprocedure);
  definition := replace(definition, 'FUNCTION public.', 'FUNCTION fixture014i4.');
  definition := replace(definition, 'public.direct_capsules', 'fixture014i4.direct_capsules');
  definition := replace(definition, 'public.direct_capsule_invitations', 'fixture014i4.direct_capsule_invitations');
  definition := replace(definition, 'public.invitation_delivery_outbox', 'fixture014i4.invitation_delivery_outbox');
  EXECUTE definition;
END $$;
REVOKE ALL ON FUNCTION fixture014i4.aftertime_invitation_worker_candidates() FROM PUBLIC;
REVOKE ALL ON FUNCTION fixture014i4.aftertime_invitation_worker_transition(uuid,uuid,text) FROM PUBLIC;
GRANT USAGE ON SCHEMA fixture014i4 TO aftertime_invitation_worker;
GRANT EXECUTE ON FUNCTION fixture014i4.aftertime_invitation_worker_candidates() TO aftertime_invitation_worker;
-- This grant applies only to the copied historical implementation, so its
-- behavior can be regression-tested. The public legacy RPC stays revoked.
GRANT EXECUTE ON FUNCTION fixture014i4.aftertime_invitation_worker_transition(uuid,uuid,text) TO aftertime_invitation_worker;
CREATE EXTENSION dblink;
DO $$ DECLARE n int; b text; BEGIN
  FOR n IN 1..9 LOOP
    b := lpad(to_hex(n),2,'0');
    PERFORM fixture014i4.aftertime_create_direct_with_outbox(
      '00000000-0000-4000-8000-000000000141',md5('worker-c'||n)::uuid,md5('worker-i'||n)::uuid,md5('worker-j'||n)::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',
      decode(repeat(b,32),'hex'),'test-key',decode(repeat(b,12),'hex'),decode(repeat(b,32),'hex'),decode(repeat(b,59),'hex'));
  END LOOP;
END $$;
COMMIT;

DO $$ DECLARE
  fn regprocedure := 'public.aftertime_invitation_worker_transition(uuid,uuid,text)'::regprocedure;
  candidates regprocedure := 'public.aftertime_invitation_worker_candidates()'::regprocedure;
  v2 regprocedure := 'public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)'::regprocedure;
BEGIN
  IF has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('authenticated', fn, 'EXECUTE')
     OR has_function_privilege('service_role', fn, 'EXECUTE')
     OR has_function_privilege('aftertime_invitation_worker', fn, 'EXECUTE')
     OR has_function_privilege('anon', candidates, 'EXECUTE') OR has_function_privilege('authenticated', candidates, 'EXECUTE')
     OR has_function_privilege('service_role', candidates, 'EXECUTE')
     OR NOT has_function_privilege('aftertime_invitation_worker', candidates, 'EXECUTE')
     OR has_function_privilege('anon', v2, 'EXECUTE') OR has_function_privilege('authenticated', v2, 'EXECUTE')
     OR has_function_privilege('service_role', v2, 'EXECUTE')
     OR has_function_privilege('aftertime_invitation_worker', v2, 'EXECUTE') IS DISTINCT FROM
        (to_regprocedure('public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)') IS NULL)
     OR has_table_privilege('aftertime_invitation_worker','public.invitation_delivery_outbox','SELECT,INSERT,UPDATE,DELETE')
     OR EXISTS (SELECT FROM pg_roles WHERE rolname='aftertime_invitation_worker' AND (rolcanlogin OR rolinherit)) THEN
    RAISE EXCEPTION 'Unsafe worker privileges';
  END IF;
END $$;
SET ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM public.aftertime_invitation_worker_transition(NULL,NULL,'lease');
    RAISE EXCEPTION 'anon RPC allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM public.aftertime_invitation_worker_transition(NULL,NULL,'lease');
    RAISE EXCEPTION 'authenticated RPC allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE aftertime_invitation_worker;
DO $$ BEGIN
  BEGIN PERFORM public.aftertime_invitation_worker_transition(NULL,NULL,'lease');
    RAISE EXCEPTION 'worker legacy RPC allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.aftertime_invitation_worker_candidates();
  IF to_regprocedure('public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)') IS NULL THEN
    PERFORM public.aftertime_invitation_worker_transition_v2(NULL,'lease',NULL,NULL);
  ELSE
    PERFORM public.aftertime_invitation_worker_transition_v3(NULL,'lease',NULL,NULL,NULL);
  END IF;
  BEGIN PERFORM ciphertext FROM public.invitation_delivery_outbox;
    RAISE EXCEPTION 'worker direct table access allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- Two actual connections compete while worker A holds its transaction open.
SELECT dblink_connect('worker_a','host=127.0.0.1 port=55485 dbname=aftertime_rpc_test user=postgres');
SELECT dblink_connect('worker_b','host=127.0.0.1 port=55485 dbname=aftertime_rpc_test user=postgres');
SELECT dblink_exec('worker_a','BEGIN');
SELECT dblink_exec('worker_b','BEGIN');
SELECT dblink_exec('worker_a','SET LOCAL ROLE aftertime_invitation_worker');
SELECT dblink_exec('worker_b','SET LOCAL ROLE aftertime_invitation_worker');
DO $outer$ DECLARE n bigint; BEGIN
  SELECT x.n INTO n FROM dblink('worker_a', $$SELECT count(*) FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-a')::uuid,'lease')$$) AS x(n bigint);
  IF n <> 1 THEN RAISE EXCEPTION 'First worker did not lease'; END IF;
END $outer$;
DO $outer$ DECLARE n bigint; BEGIN
  SELECT x.n INTO n FROM dblink('worker_b', $$SELECT count(*) FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-b')::uuid,'lease')$$) AS x(n bigint);
  IF n <> 0 THEN RAISE EXCEPTION 'Competing worker acquired locked job'; END IF;
END $outer$;
SELECT dblink_exec('worker_a','COMMIT');
DO $outer$ DECLARE n bigint; BEGIN
  SELECT x.n INTO n FROM dblink('worker_b', $$SELECT count(*) FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-b')::uuid,'lease')$$) AS x(n bigint);
  IF n <> 0 THEN RAISE EXCEPTION 'Active lease acquired twice'; END IF;
END $outer$;
SELECT dblink_exec('worker_b','COMMIT');
SELECT dblink_disconnect('worker_a');
SELECT dblink_disconnect('worker_b');

-- Recovery, stale token fencing, eligibility and terminal ciphertext cleanup.
DO $$ DECLARE n bigint; s text; BEGIN
  UPDATE fixture014i4.invitation_delivery_outbox SET lease_until=clock_timestamp()-interval '1 second' WHERE id=md5('worker-j1')::uuid;
  SELECT count(*) INTO n FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-b')::uuid,'lease');
  IF n <> 1 OR (SELECT attempts FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j1')::uuid) <> 2 THEN RAISE EXCEPTION 'Lease recovery failed'; END IF;
  SELECT count(*) INTO n FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-a')::uuid,'prepare');
  IF n <> 0 THEN RAISE EXCEPTION 'Stale token accepted'; END IF;
  SELECT count(*) INTO n FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-b')::uuid,'prepare');
  IF n <> 1 THEN RAISE EXCEPTION 'Current worker could not prepare'; END IF;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j1')::uuid,md5('token-b')::uuid,'retry');
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j1')::uuid AND status='pending'
      AND attempts=2 AND lease_token IS NULL AND next_attempt_at > clock_timestamp()) THEN RAISE EXCEPTION 'Retry backoff failed'; END IF;

  -- Cancellation, claim, expiry and revocation after leasing deny preparation.
  FOR n IN 2..5 LOOP
    PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j'||n)::uuid,md5('token-'||n)::uuid,'lease');
    IF n=2 THEN UPDATE fixture014i4.direct_capsules SET cancelled_at=clock_timestamp() WHERE id=md5('worker-c'||n)::uuid;
    ELSIF n=3 THEN UPDATE fixture014i4.direct_capsule_invitations SET claimed_at=clock_timestamp() WHERE id=md5('worker-i'||n)::uuid;
    ELSIF n=4 THEN UPDATE fixture014i4.direct_capsule_invitations SET expires_at=clock_timestamp()-interval '1 second' WHERE id=md5('worker-i'||n)::uuid;
    ELSE UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=md5('worker-i'||n)::uuid; END IF;
    IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j'||n)::uuid,md5('token-'||n)::uuid,'prepare')) THEN
      RAISE EXCEPTION 'Ineligible invitation prepared'; END IF;
    SELECT status INTO s FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j'||n)::uuid;
    IF s <> (CASE WHEN n=4 THEN 'expired' ELSE 'cancelled' END) OR EXISTS
       (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j'||n)::uuid AND ciphertext IS NOT NULL) THEN
      RAISE EXCEPTION 'Ineligible job not cleaned'; END IF;
  END LOOP;
  UPDATE fixture014i4.invitation_delivery_outbox SET attempts=4 WHERE id=md5('worker-j6')::uuid;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j6')::uuid,md5('token-6')::uuid,'lease');
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j6')::uuid,md5('token-6')::uuid,'retry');
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j6')::uuid AND attempts=5 AND status='failed' AND ciphertext IS NULL) THEN
    RAISE EXCEPTION 'Retry limit failed'; END IF;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j7')::uuid,md5('token-7')::uuid,'lease');
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j7')::uuid,md5('token-7')::uuid,'sent');
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j7')::uuid AND status='sent' AND ciphertext IS NULL) THEN
    RAISE EXCEPTION 'Sent job not cleaned'; END IF;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j8')::uuid,md5('token-8')::uuid,'lease');
  UPDATE fixture014i4.direct_capsules SET deleted_at=clock_timestamp() WHERE id=md5('worker-c8')::uuid;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j8')::uuid,md5('token-8')::uuid,'prepare');
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j8')::uuid AND status='cancelled' AND ciphertext IS NULL) THEN
    RAISE EXCEPTION 'Deleted capsule job not cleaned'; END IF;
  UPDATE fixture014i4.invitation_delivery_outbox SET attempts=4 WHERE id=md5('worker-j9')::uuid;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j9')::uuid,md5('token-9')::uuid,'lease');
  UPDATE fixture014i4.invitation_delivery_outbox SET lease_until=clock_timestamp()-interval '1 second' WHERE id=md5('worker-j9')::uuid;
  PERFORM fixture014i4.aftertime_invitation_worker_transition(md5('worker-j9')::uuid,md5('token-next')::uuid,'lease');
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('worker-j9')::uuid AND status='failed' AND ciphertext IS NULL) THEN
    RAISE EXCEPTION 'Exhausted crashed lease not cleaned'; END IF;
END $$;

BEGIN;
DROP SCHEMA fixture014i4 CASCADE;
DROP ROLE aftertime_fixture_worker_014i4;
DELETE FROM auth.users WHERE id='00000000-0000-4000-8000-000000000141';
DROP EXTENSION dblink;
COMMIT;
\echo 'Dormant worker lease, concurrency, recovery, eligibility and local privilege checks passed.'
