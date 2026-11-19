-- Disposable loopback PostgreSQL ONLY. Never run on a hosted/shared database.
-- The real gate remains untouched. Function bodies are copied to independent
-- fixture tables because the real invitation table cannot contain any rows.
\set ON_ERROR_STOP on
DO $$
BEGIN
  IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres'
     OR current_setting('port') <> '55484'
     OR current_setting('data_directory') NOT LIKE '%claim014h4-postgres%' THEN
    RAISE EXCEPTION 'Requires the dedicated local claim test cluster';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.direct_capsule_invitations'::regclass
      AND conname = 'direct_capsule_invitations_disabled' AND convalidated
      AND pg_get_constraintdef(oid) = 'CHECK (false)') THEN RAISE EXCEPTION 'Gate missing'; END IF;
  IF has_function_privilege('anon', 'public.aftertime_claim_direct_capsule(uuid,uuid,bytea)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.aftertime_claim_direct_capsule(uuid,uuid,bytea)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.aftertime_claim_direct_capsule(uuid,uuid,bytea)', 'EXECUTE')
     OR has_table_privilege('service_role', 'public.direct_capsule_invitations', 'SELECT,INSERT,UPDATE,DELETE')
     OR EXISTS (SELECT 1 FROM pg_class WHERE oid IN ('public.direct_capsules'::regclass,
          'public.direct_capsule_invitations'::regclass) AND NOT relrowsecurity) THEN
    RAISE EXCEPTION 'ACL or RLS failure';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.aftertime_claim_direct_capsule(uuid,uuid,bytea)'::regprocedure
      AND prosecdef AND provolatile = 'v' AND proowner = 'postgres'::regrole
      AND proconfig @> ARRAY['search_path=""'])
    OR EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
      WHERE p.oid = 'public.aftertime_claim_direct_capsule(uuid,uuid,bytea)'::regprocedure
        AND a.privilege_type = 'EXECUTE' AND a.grantee NOT IN ('postgres'::regrole::oid, 'service_role'::regrole::oid)) THEN
    RAISE EXCEPTION 'Unsafe function definition or inherited grant';
  END IF;
END;
$$;
SET ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM * FROM public.direct_capsule_invitations; RAISE EXCEPTION 'anon table access allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.aftertime_claim_direct_capsule(NULL,NULL,NULL); RAISE EXCEPTION 'anon RPC access allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM * FROM public.direct_capsules; RAISE EXCEPTION 'authenticated table access allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.aftertime_claim_direct_capsule(NULL,NULL,NULL); RAISE EXCEPTION 'authenticated RPC access allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE service_role;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM public.aftertime_claim_direct_capsule(NULL,NULL,NULL)) THEN RAISE EXCEPTION 'Unexpected result'; END IF; END $$;
RESET ROLE;
CREATE SCHEMA claim_fixture;
CREATE TABLE claim_fixture.direct_capsules (LIKE public.direct_capsules INCLUDING DEFAULTS);
ALTER TABLE claim_fixture.direct_capsules ADD PRIMARY KEY (id);
CREATE TABLE claim_fixture.direct_capsule_invitations (LIKE public.direct_capsule_invitations INCLUDING DEFAULTS);
ALTER TABLE claim_fixture.direct_capsule_invitations ADD PRIMARY KEY (id),
  ADD UNIQUE (capsule_id), ADD UNIQUE (claim_secret_digest),
  ADD CHECK (expires_at = created_at + interval '168 hours'),
  ADD CHECK (claim_secret_digest IS NULL OR octet_length(claim_secret_digest) = 32),
  ADD FOREIGN KEY (capsule_id) REFERENCES claim_fixture.direct_capsules(id) ON DELETE CASCADE,
  ADD FOREIGN KEY (claimed_user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
DO $$
DECLARE definition text; name text;
BEGIN
  FOREACH name IN ARRAY ARRAY['aftertime_claim_direct_capsule(uuid,uuid,bytea)',
    'aftertime_cancel_direct_capsule(uuid,uuid)', 'aftertime_reveal_direct_capsule(uuid,uuid)'] LOOP
    definition := pg_get_functiondef(('public.' || name)::regprocedure);
    definition := replace(definition, 'FUNCTION public.', 'FUNCTION claim_fixture.');
    definition := replace(definition, 'public.direct_capsules', 'claim_fixture.direct_capsules');
    definition := replace(definition, 'public.direct_capsule_invitations', 'claim_fixture.direct_capsule_invitations');
    EXECUTE definition;
  END LOOP;
END;
$$;

INSERT INTO auth.users(id, email_confirmed_at) SELECT md5('user-' || n)::uuid, clock_timestamp() FROM generate_series(1, 8) n;
UPDATE auth.users SET banned_until = clock_timestamp() + interval '1 day' WHERE id = md5('user-4')::uuid;
UPDATE auth.users SET deleted_at = clock_timestamp() WHERE id = md5('user-8')::uuid;
DELETE FROM public.profiles WHERE id = md5('user-7')::uuid;
-- Exercise the actual gate, checking the specific violated constraint.
DO $$
DECLARE rejected boolean := false; constraint_name text;
BEGIN
  BEGIN
    INSERT INTO public.direct_capsules (id,owner_id,title,body,created_at,unlock_at)
      VALUES (md5('gate-probe')::uuid,md5('user-1')::uuid,'fixture','fixture',clock_timestamp(),clock_timestamp() + interval '1 day');
    INSERT INTO public.direct_capsule_invitations (capsule_id,intended_email,created_at,expires_at)
      SELECT md5('gate-probe')::uuid,'fixture.invalid',t,t + interval '168 hours' FROM (SELECT clock_timestamp() AS t) s;
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS constraint_name = CONSTRAINT_NAME;
    rejected := constraint_name = 'direct_capsule_invitations_disabled';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Real invitation gate did not reject insert'; END IF;
END;
$$;
INSERT INTO claim_fixture.direct_capsules(id,owner_id,title,body,created_at,unlock_at)
 SELECT md5('capsule-' || n)::uuid, md5('user-1')::uuid, 'fixture', 'fixture',
 clock_timestamp() - interval '8 days', clock_timestamp() + interval '1 day' FROM generate_series(1, 18) n;
INSERT INTO claim_fixture.direct_capsule_invitations(id,capsule_id,intended_email,created_at,expires_at,claim_secret_digest)
 SELECT md5('invitation-' || n)::uuid, md5('capsule-' || n)::uuid, 'fixture.invalid',
 t.stamp - interval '1 hour', t.stamp + interval '167 hours',
 decode(lpad(to_hex(n),64,'0'),'hex') FROM generate_series(1,18) n CROSS JOIN (SELECT clock_timestamp() AS stamp) t;
UPDATE claim_fixture.direct_capsule_invitations SET created_at = t.stamp - interval '168 hours', expires_at = t.stamp
 FROM (SELECT clock_timestamp() - interval '1 second' AS stamp) t WHERE capsule_id = md5('capsule-3')::uuid;
UPDATE claim_fixture.direct_capsule_invitations SET revoked_at = clock_timestamp() WHERE capsule_id = md5('capsule-4')::uuid;
UPDATE claim_fixture.direct_capsules SET cancelled_at = clock_timestamp() WHERE id = md5('capsule-5')::uuid;
UPDATE claim_fixture.direct_capsules SET deleted_at = clock_timestamp() WHERE id = md5('capsule-6')::uuid;
UPDATE claim_fixture.direct_capsule_invitations SET claimed_at = clock_timestamp() WHERE capsule_id = md5('capsule-9')::uuid;

DO $$
DECLARE n integer; actual bigint;
BEGIN
  FOR n IN 1..9 LOOP
    SELECT count(*) INTO actual FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-' || n)::uuid,
      CASE WHEN n = 7 THEN md5('user-1')::uuid WHEN n = 8 THEN md5('user-4')::uuid ELSE md5('user-2')::uuid END,
      decode(lpad(to_hex(CASE WHEN n = 2 THEN 1 ELSE n END),64,'0'),'hex'));
    IF actual <> (CASE WHEN n = 1 THEN 1 ELSE 0 END) THEN RAISE EXCEPTION 'Claim case % failed', n; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-1')::uuid,md5('user-2')::uuid,decode(lpad('1',64,'0'),'hex')))
     OR EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-1')::uuid,md5('user-3')::uuid,decode(lpad('1',64,'0'),'hex')))
     OR EXISTS (SELECT 1 FROM claim_fixture.aftertime_reveal_direct_capsule(md5('capsule-1')::uuid,md5('user-2')::uuid))
     OR NOT EXISTS (SELECT 1 FROM claim_fixture.direct_capsule_invitations WHERE capsule_id = md5('capsule-1')::uuid
                    AND claimed_user_id = md5('user-2')::uuid AND claimed_at IS NOT NULL AND claim_secret_digest IS NULL)
  THEN RAISE EXCEPTION 'Replay, binding or early reveal failure'; END IF;
  IF EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-10')::uuid,md5('absent')::uuid,decode(lpad('a',64,'0'),'hex')))
     OR EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-10')::uuid,md5('user-7')::uuid,decode(lpad('a',64,'0'),'hex')))
     OR EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-10')::uuid,md5('user-8')::uuid,decode(lpad('a',64,'0'),'hex'))) THEN
    RAISE EXCEPTION 'Missing or deleted account/profile accepted';
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((SELECT to_jsonb(r) FROM
      claim_fixture.aftertime_claim_direct_capsule(md5('capsule-16')::uuid,md5('user-3')::uuid,decode(lpad('10',64,'0'),'hex')) r)) k)
      IS DISTINCT FROM ARRAY['created_at','id','unlock_at'] THEN RAISE EXCEPTION 'Unsafe claim projection'; END IF;
END;
$$;
UPDATE auth.users SET email = 'changed.invalid' WHERE id = md5('user-3')::uuid;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM claim_fixture.direct_capsule_invitations WHERE capsule_id = md5('capsule-16')::uuid AND claimed_user_id = md5('user-3')::uuid)
     OR EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-16')::uuid,md5('user-2')::uuid,decode(lpad('10',64,'0'),'hex')))
  THEN RAISE EXCEPTION 'Account email change transferred a claim'; END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS dblink;
SELECT dblink_connect('a', 'host=127.0.0.1 port=55484 dbname=aftertime_rpc_test user=postgres');
SELECT dblink_connect('b', 'host=127.0.0.1 port=55484 dbname=aftertime_rpc_test user=postgres');
-- Concurrent claim: first claim holds locks, second waits and must fail.
SELECT dblink_exec('a', 'BEGIN');
SELECT * FROM dblink('a', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-10')::uuid,md5('user-2')::uuid,decode(lpad('a',64,'0'),'hex'))$$) AS t(n bigint);
SELECT dblink_send_query('b', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-10')::uuid,md5('user-3')::uuid,decode(lpad('a',64,'0'),'hex'))$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Competing claim did not wait'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink_get_result('b') AS x(n bigint); IF n <> 0 THEN RAISE EXCEPTION 'Competing claim succeeded'; END IF; END $$;
SELECT * FROM dblink_get_result('b') AS x(n bigint);
-- Cancellation wins after claim waits for capsule lock.
SELECT dblink_exec('a', 'BEGIN');
SELECT * FROM dblink('a', $$SELECT count(*) FROM claim_fixture.aftertime_cancel_direct_capsule(md5('capsule-11')::uuid,md5('user-1')::uuid)$$) AS t(n bigint);
SELECT dblink_send_query('b', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-11')::uuid,md5('user-2')::uuid,decode(lpad('b',64,'0'),'hex'))$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Claim did not wait for cancellation'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink_get_result('b') AS x(n bigint); IF n <> 0 THEN RAISE EXCEPTION 'Claim after cancellation succeeded'; END IF; END $$;
SELECT * FROM dblink_get_result('b') AS x(n bigint);
-- Claim wins before cancellation; cancellation still prevents reveal.
SELECT dblink_exec('a', 'BEGIN');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink('a', $query$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-13')::uuid,md5('user-2')::uuid,decode(lpad('d',64,'0'),'hex'))$query$) AS x(n bigint); IF n <> 1 THEN RAISE EXCEPTION 'Initial claim failed'; END IF; END $$;
SELECT dblink_send_query('b', $$SELECT count(*) FROM claim_fixture.aftertime_cancel_direct_capsule(md5('capsule-13')::uuid,md5('user-1')::uuid)$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Cancellation did not wait'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink_get_result('b') AS x(n bigint); IF n <> 1 THEN RAISE EXCEPTION 'Cancellation after claim failed'; END IF; END $$;
SELECT * FROM dblink_get_result('b') AS x(n bigint);
DO $$ BEGIN IF EXISTS (SELECT 1 FROM claim_fixture.aftertime_reveal_direct_capsule(md5('capsule-13')::uuid,md5('user-2')::uuid)) THEN RAISE EXCEPTION 'Cancelled claim revealed'; END IF; END $$;
-- Claim wins before deletion, deletion waits and leaves terminal claim history.
SELECT dblink_exec('a', 'BEGIN');
SELECT * FROM dblink('a', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-12')::uuid,md5('user-5')::uuid,decode(lpad('c',64,'0'),'hex'))$$) AS t(n bigint);
SELECT dblink_send_query('b', $$DELETE FROM auth.users WHERE id = md5('user-5')::uuid RETURNING 1$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Deletion did not wait'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
SELECT * FROM dblink_get_result('b') AS x(n integer);
SELECT * FROM dblink_get_result('b') AS x(n integer);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM claim_fixture.direct_capsule_invitations WHERE capsule_id = md5('capsule-12')::uuid AND claimed_at IS NOT NULL AND claimed_user_id IS NULL)
 OR EXISTS (SELECT 1 FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-12')::uuid,md5('user-3')::uuid,decode(lpad('c',64,'0'),'hex')))
 THEN RAISE EXCEPTION 'Deletion or historical claim failure'; END IF;
END $$;
-- Deletion wins while claim is waiting on the Auth row.
SELECT dblink_exec('a', 'BEGIN');
SELECT dblink_exec('a', $$DELETE FROM auth.users WHERE id = md5('user-6')::uuid$$);
SELECT dblink_send_query('b', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-14')::uuid,md5('user-6')::uuid,decode(lpad('e',64,'0'),'hex'))$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Claim did not wait for account deletion'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink_get_result('b') AS x(n bigint); IF n <> 0 THEN RAISE EXCEPTION 'Deleted account claimed'; END IF; END $$;
SELECT * FROM dblink_get_result('b') AS x(n bigint);
-- Time is captured after the capsule lock, not before waiting.
UPDATE claim_fixture.direct_capsule_invitations SET created_at = t.stamp - interval '168 hours', expires_at = t.stamp
 FROM (SELECT clock_timestamp() + interval '1 second' AS stamp) t WHERE capsule_id = md5('capsule-15')::uuid;
SELECT dblink_exec('a', 'BEGIN');
SELECT * FROM dblink('a', $$SELECT count(*) FROM (SELECT 1 FROM claim_fixture.direct_capsules WHERE id = md5('capsule-15')::uuid FOR UPDATE) AS locked$$) AS t(n bigint);
SELECT dblink_send_query('b', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-15')::uuid,md5('user-2')::uuid,decode(lpad('f',64,'0'),'hex'))$$);
SELECT pg_sleep(1.5);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Claim did not wait for capsule'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink_get_result('b') AS x(n bigint); IF n <> 0 THEN RAISE EXCEPTION 'Expired claim succeeded after wait'; END IF; END $$;
SELECT * FROM dblink_get_result('b') AS x(n bigint);
-- Simulated capsule soft deletion and claim in both lock orderings. There is
-- no production direct-capsule deletion RPC in this slice.
SELECT dblink_exec('a', 'BEGIN');
SELECT dblink_exec('a', $$UPDATE claim_fixture.direct_capsules SET deleted_at = clock_timestamp() WHERE id = md5('capsule-17')::uuid$$);
SELECT dblink_send_query('b', $$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-17')::uuid,md5('user-2')::uuid,decode(lpad('11',64,'0'),'hex'))$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Claim did not wait for capsule deletion'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink_get_result('b') AS x(n bigint); IF n <> 0 THEN RAISE EXCEPTION 'Deleted capsule claimed'; END IF; END $$;
SELECT * FROM dblink_get_result('b') AS x(n bigint);
SELECT dblink_exec('a', 'BEGIN');
DO $$ DECLARE n bigint; BEGIN SELECT x.n INTO n FROM dblink('a', $query$SELECT count(*) FROM claim_fixture.aftertime_claim_direct_capsule(md5('capsule-18')::uuid,md5('user-2')::uuid,decode(lpad('12',64,'0'),'hex'))$query$) AS x(n bigint); IF n <> 1 THEN RAISE EXCEPTION 'Claim before deletion failed'; END IF; END $$;
SELECT dblink_send_query('b', $$UPDATE claim_fixture.direct_capsules SET deleted_at = clock_timestamp() WHERE id = md5('capsule-18')::uuid RETURNING 1$$);
SELECT pg_sleep(0.2);
DO $$ BEGIN IF dblink_is_busy('b') <> 1 THEN RAISE EXCEPTION 'Capsule deletion did not wait'; END IF; END $$;
SELECT dblink_exec('a', 'COMMIT');
SELECT * FROM dblink_get_result('b') AS x(n integer);
SELECT * FROM dblink_get_result('b') AS x(n integer);
DO $$ BEGIN IF EXISTS (SELECT 1 FROM claim_fixture.aftertime_reveal_direct_capsule(md5('capsule-18')::uuid,md5('user-2')::uuid)) THEN RAISE EXCEPTION 'Deleted capsule revealed'; END IF; END $$;
SELECT dblink_disconnect('a');
SELECT dblink_disconnect('b');
\echo 'Fixture claim checks passed; actual invitation gate remained intact.'
