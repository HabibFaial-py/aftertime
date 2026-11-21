-- Disposable localhost cluster only; committed fixture enables independent workers.
\set ON_ERROR_STOP on
BEGIN;
\ir setup_local_encrypted_outbox.sql
DO $$ DECLARE definition text; BEGIN
  definition := pg_get_functiondef('public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)'::regprocedure);
  definition := replace(definition,'FUNCTION public.','FUNCTION fixture014i4.');
  definition := replace(definition,'public.direct_capsules','fixture014i4.direct_capsules');
  definition := replace(definition,'public.direct_capsule_invitations','fixture014i4.direct_capsule_invitations');
  definition := replace(definition,'public.invitation_delivery_outbox','fixture014i4.invitation_delivery_outbox');
  EXECUTE definition;
  definition := pg_get_functiondef('public.aftertime_claim_direct_capsule(uuid,uuid,bytea)'::regprocedure);
  definition := replace(definition,'FUNCTION public.','FUNCTION fixture014i4.');
  definition := replace(definition,'public.direct_capsules','fixture014i4.direct_capsules');
  definition := replace(definition,'public.direct_capsule_invitations','fixture014i4.direct_capsule_invitations');
  EXECUTE definition;
  definition := pg_get_functiondef('public.aftertime_cancel_direct_capsule(uuid,uuid)'::regprocedure);
  definition := replace(definition,'FUNCTION public.','FUNCTION fixture014i4.');
  definition := replace(definition,'public.direct_capsules','fixture014i4.direct_capsules');
  definition := replace(definition,'public.direct_capsule_invitations','fixture014i4.direct_capsule_invitations');
  EXECUTE definition;
END $$;
REVOKE ALL ON FUNCTION fixture014i4.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fixture014i4.aftertime_claim_direct_capsule(uuid,uuid,bytea) FROM PUBLIC;
REVOKE ALL ON FUNCTION fixture014i4.aftertime_cancel_direct_capsule(uuid,uuid) FROM PUBLIC;
GRANT USAGE ON SCHEMA fixture014i4 TO aftertime_invitation_worker;
GRANT EXECUTE ON FUNCTION fixture014i4.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint) TO aftertime_invitation_worker;
CREATE EXTENSION dblink;
CREATE TABLE fixture014i4.leases (n integer PRIMARY KEY, token uuid, generation bigint);
INSERT INTO auth.users(id,email,email_confirmed_at)
VALUES ('00000000-0000-4000-8000-000000000163','claimant@example.invalid',clock_timestamp());
DO $$ DECLARE n int; b text; BEGIN
  FOR n IN 1..10 LOOP
    b := lpad(to_hex(n),2,'0');
    PERFORM fixture014i4.aftertime_create_direct_with_outbox(
      '00000000-0000-4000-8000-000000000141',md5('reliable-c'||n)::uuid,md5('reliable-i'||n)::uuid,md5('reliable-j'||n)::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',
      decode(repeat(b,32),'hex'),'test-key',decode(repeat(b,12),'hex'),decode(repeat(b,32),'hex'),decode(repeat(b,59),'hex'));
  END LOOP;
END $$;
COMMIT;

DO $$ DECLARE fn regprocedure := 'public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)'::regprocedure; BEGIN
  IF has_function_privilege('anon',fn,'EXECUTE') OR has_function_privilege('authenticated',fn,'EXECUTE')
     OR has_function_privilege('service_role',fn,'EXECUTE')
     OR NOT has_function_privilege('aftertime_invitation_worker',fn,'EXECUTE')
     OR has_function_privilege('aftertime_invitation_worker','public.aftertime_invitation_worker_transition(uuid,uuid,text)','EXECUTE')
     OR has_table_privilege('aftertime_invitation_worker','public.invitation_delivery_outbox','SELECT,UPDATE') THEN
    RAISE EXCEPTION 'Unsafe v2 privileges';
  END IF;
END $$;

-- A returned row in an uncommitted transaction is provisional, and another
-- worker cannot lease it. Rollback removes the transition and acknowledgement.
SELECT dblink_connect('worker_a','host=127.0.0.1 port=55485 dbname=aftertime_rpc_test user=postgres');
SELECT dblink_connect('worker_b','host=127.0.0.1 port=55485 dbname=aftertime_rpc_test user=postgres');
SELECT dblink_exec('worker_a','BEGIN');
SELECT dblink_exec('worker_a','SET LOCAL ROLE aftertime_invitation_worker');
SELECT dblink_exec('worker_b','BEGIN');
SELECT dblink_exec('worker_b','SET LOCAL ROLE aftertime_invitation_worker');
DO $outer$ DECLARE t uuid; g bigint; a text; n bigint; BEGIN
  SELECT x.outcome,x.token,x.generation INTO a,t,g FROM dblink('worker_a',
    $$SELECT outcome,lease_token,lease_generation FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'lease',NULL,NULL)$$)
    AS x(outcome text,token uuid,generation bigint);
  IF a <> 'leased' OR t IS NULL OR substring(t::text,15,1) <> '4' OR g <> 1 THEN RAISE EXCEPTION 'Invalid provisional lease'; END IF;
  SELECT x.n INTO n FROM dblink('worker_b',
    $$SELECT count(*) FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'lease',NULL,NULL)$$) AS x(n bigint);
  IF n <> 0 THEN RAISE EXCEPTION 'Competing worker acquired lock'; END IF;
END $outer$;
SELECT dblink_exec('worker_a','ROLLBACK');
SELECT dblink_exec('worker_b','ROLLBACK');
SELECT dblink_disconnect('worker_a');
SELECT dblink_disconnect('worker_b');
DO $$ BEGIN
  IF EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('reliable-j1')::uuid
      AND (lease_token IS NOT NULL OR attempts<>0 OR lease_generation<>0)) THEN RAISE EXCEPTION 'Rollback persisted lease'; END IF;
END $$;

-- Commit a lease, force a crash/expiry, and verify token plus generation fence.
INSERT INTO fixture014i4.leases SELECT 1,lease_token,lease_generation
  FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'lease',NULL,NULL) WHERE outcome='leased';
DO $$ BEGIN
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'lease',NULL,NULL)) THEN
    RAISE EXCEPTION 'Active lease recovered before expiry'; END IF;
END $$;
UPDATE fixture014i4.invitation_delivery_outbox SET lease_until=clock_timestamp()-interval '1 second' WHERE id=md5('reliable-j1')::uuid;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=1;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'prepare',r.token,r.generation))
     OR EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'sent',r.token,r.generation)) THEN
    RAISE EXCEPTION 'Expired lease accepted'; END IF;
END $$;
INSERT INTO fixture014i4.leases SELECT 11,lease_token,lease_generation
  FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'lease',NULL,NULL) WHERE outcome='leased';
DO $$ DECLARE oldrow record; newrow record; BEGIN
  SELECT * INTO STRICT oldrow FROM fixture014i4.leases WHERE n=1;
  SELECT * INTO STRICT newrow FROM fixture014i4.leases WHERE n=11;
  IF oldrow.token=newrow.token OR oldrow.generation<>1 OR newrow.generation<>2 THEN RAISE EXCEPTION 'Fresh lease fence failed'; END IF;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'sent',oldrow.token,oldrow.generation))
     OR EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'sent',oldrow.token,newrow.generation))
     OR EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'sent',newrow.token,oldrow.generation)) THEN
    RAISE EXCEPTION 'Stale worker updated job'; END IF;
  IF NOT EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j1')::uuid,'retry',newrow.token,newrow.generation) WHERE outcome='retry') THEN
    RAISE EXCEPTION 'Retry acknowledgement missing'; END IF;
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('reliable-j1')::uuid AND status='pending'
      AND attempts=2 AND lease_token IS NULL AND next_attempt_at > clock_timestamp()) THEN RAISE EXCEPTION 'Retry state incorrect'; END IF;
END $$;

-- Lease remaining jobs. Transition rows contain no message body.
INSERT INTO fixture014i4.leases
  SELECT n, r.lease_token, r.lease_generation FROM generate_series(2,10) n
  CROSS JOIN LATERAL fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j'||n)::uuid,'lease',NULL,NULL) r
  WHERE r.outcome='leased';
DO $$ BEGIN IF (SELECT count(*) FROM fixture014i4.leases WHERE n BETWEEN 2 AND 10) <> 9 THEN RAISE EXCEPTION 'Leases missing'; END IF; END $$;

-- Actor holds each mutation uncommitted: worker skips locks; after commit the
-- database-time check denies preparation and terminalizes the job.
SELECT dblink_connect('actor','host=127.0.0.1 port=55485 dbname=aftertime_rpc_test user=postgres');
SELECT dblink_exec('actor','BEGIN');
SELECT * FROM dblink('actor', $$SELECT count(*) FROM fixture014i4.aftertime_cancel_direct_capsule(md5('reliable-c2')::uuid,'00000000-0000-4000-8000-000000000141')$$) AS x(n bigint);
DO $$ DECLARE r record; BEGIN
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=2;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j2')::uuid,'prepare',r.token,r.generation)) THEN RAISE EXCEPTION 'Prepared while cancellation locked'; END IF;
END $$;
SELECT dblink_exec('actor','COMMIT');
SELECT dblink_exec('actor','BEGIN');
SELECT * FROM dblink('actor', $$SELECT count(*) FROM fixture014i4.aftertime_claim_direct_capsule(md5('reliable-c3')::uuid,'00000000-0000-4000-8000-000000000163',decode(repeat('03',32),'hex'))$$) AS x(n bigint);
DO $$ DECLARE r record; BEGIN
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=3;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j3')::uuid,'prepare',r.token,r.generation)) THEN RAISE EXCEPTION 'Prepared while claim locked'; END IF;
END $$;
SELECT dblink_exec('actor','COMMIT');
SELECT dblink_exec('actor','BEGIN');
SELECT dblink_exec('actor', $$UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=md5('reliable-i4')::uuid$$);
DO $$ DECLARE r record; BEGIN
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=4;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j4')::uuid,'prepare',r.token,r.generation)) THEN RAISE EXCEPTION 'Prepared while revocation locked'; END IF;
END $$;
SELECT dblink_exec('actor','COMMIT');
SELECT dblink_disconnect('actor');
DO $$ DECLARE v_idx int; r record; BEGIN
  FOR v_idx IN 2..4 LOOP
    SELECT * INTO STRICT r FROM fixture014i4.leases WHERE leases.n=v_idx;
    IF NOT EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j'||v_idx)::uuid,'prepare',r.token,r.generation)
                   WHERE outcome='cancelled' AND ciphertext IS NULL) THEN RAISE EXCEPTION 'Pre-dispatch invalidation failed'; END IF;
  END LOOP;
END $$;

-- Prepare each job in a completed statement/transaction before any actor
-- mutation; a future network call would occur with no database locks held.
DO $$ DECLARE v_idx int; r record; BEGIN
  FOR v_idx IN 5..7 LOOP
    SELECT * INTO STRICT r FROM fixture014i4.leases WHERE leases.n=v_idx;
    IF NOT EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j'||v_idx)::uuid,'prepare',r.token,r.generation)
                   WHERE outcome='prepared' AND ciphertext IS NOT NULL) THEN RAISE EXCEPTION 'Eligible prepare failed'; END IF;
  END LOOP;
END $$;
-- This statement begins only after the above transaction commits.
DO $$ DECLARE v_idx int; digest bytea; BEGIN
  FOR v_idx IN 5..7 LOOP
    SELECT claim_secret_digest INTO digest FROM fixture014i4.direct_capsule_invitations WHERE id=md5('reliable-i'||v_idx)::uuid;
    IF v_idx=5 THEN PERFORM fixture014i4.aftertime_cancel_direct_capsule(md5('reliable-c'||v_idx)::uuid,'00000000-0000-4000-8000-000000000141');
    ELSIF v_idx=6 THEN
      IF NOT EXISTS (SELECT FROM fixture014i4.aftertime_claim_direct_capsule(md5('reliable-c'||v_idx)::uuid,'00000000-0000-4000-8000-000000000163',digest)) THEN
        RAISE EXCEPTION 'First claim failed'; END IF;
    ELSE UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=md5('reliable-i'||v_idx)::uuid; END IF;
    IF EXISTS (SELECT FROM fixture014i4.aftertime_claim_direct_capsule(md5('reliable-c'||v_idx)::uuid,'00000000-0000-4000-8000-000000000163',digest)) THEN
      RAISE EXCEPTION 'Late or duplicate claim succeeded'; END IF;
  END LOOP;
END $$;
DO $$ DECLARE r record; digest bytea; BEGIN
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=8;
  SELECT claim_secret_digest INTO digest FROM fixture014i4.direct_capsule_invitations WHERE id=md5('reliable-i8')::uuid;
  UPDATE fixture014i4.direct_capsule_invitations SET expires_at=clock_timestamp()-interval '1 second' WHERE id=md5('reliable-i8')::uuid;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_claim_direct_capsule(md5('reliable-c8')::uuid,'00000000-0000-4000-8000-000000000163',digest))
     OR NOT EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j8')::uuid,'prepare',r.token,r.generation) WHERE outcome='expired') THEN
    RAISE EXCEPTION 'Expired invitation accepted'; END IF;
END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=9;
  UPDATE fixture014i4.invitation_delivery_outbox SET attempts=5 WHERE id=md5('reliable-j9')::uuid;
  IF NOT EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j9')::uuid,'retry',r.token,r.generation) WHERE outcome='failed') THEN
    RAISE EXCEPTION 'Exhausted retry not acknowledged'; END IF;
  IF NOT EXISTS (SELECT FROM fixture014i4.invitation_delivery_outbox WHERE id=md5('reliable-j9')::uuid AND status='failed' AND ciphertext IS NULL) THEN
    RAISE EXCEPTION 'Exhausted retry not cleaned'; END IF;
  SELECT * INTO STRICT r FROM fixture014i4.leases WHERE n=10;
  IF NOT EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j10')::uuid,'sent',r.token,r.generation) WHERE outcome='sent') THEN
    RAISE EXCEPTION 'Sent acknowledgement failed'; END IF;
  IF EXISTS (SELECT FROM fixture014i4.aftertime_invitation_worker_transition_v2(md5('reliable-j10')::uuid,'sent',r.token,r.generation)) THEN
    RAISE EXCEPTION 'Sent no-op acknowledgement failed'; END IF;
END $$;

BEGIN;
DROP SCHEMA fixture014i4 CASCADE;
DROP ROLE aftertime_fixture_worker_014i4;
DELETE FROM auth.users WHERE id IN ('00000000-0000-4000-8000-000000000141','00000000-0000-4000-8000-000000000163');
DROP EXTENSION dblink;
COMMIT;
\echo 'Dormant worker v2 acknowledgements, fencing, ordering and claim checks passed.'
