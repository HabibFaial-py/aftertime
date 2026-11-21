-- Disposable loopback cluster only; never a hosted or shared database.
\set ON_ERROR_STOP on
DO $$
DECLARE fn regprocedure := 'public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea)'::regprocedure;
BEGIN
  IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres'
     OR current_setting('port') <> '55485'
     OR current_setting('data_directory') NOT LIKE '%outbox014i1-postgres%' THEN
    RAISE EXCEPTION 'Requires the dedicated local outbox test cluster';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.direct_capsule_invitations'::regclass
      AND conname = 'direct_capsule_invitations_disabled' AND convalidated
      AND pg_get_constraintdef(oid) = 'CHECK (false)') THEN RAISE EXCEPTION 'Gate missing'; END IF;
  IF has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('authenticated', fn, 'EXECUTE')
     OR NOT has_function_privilege('service_role', fn, 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_class WHERE oid IN ('public.invitation_delivery_outbox'::regclass,
         'public.invitation_outbox_nonces'::regclass) AND NOT relrowsecurity)
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) AS role_name,
                        unnest(ARRAY['public.invitation_delivery_outbox','public.invitation_outbox_nonces']) AS table_name
                WHERE has_table_privilege(role_name, table_name, 'SELECT,INSERT,UPDATE,DELETE')) THEN
    RAISE EXCEPTION 'Unsafe privileges or RLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = fn AND prosecdef AND proowner = 'postgres'::regrole
      AND proconfig @> ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Unsafe function'; END IF;
END $$;
SET ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM * FROM public.invitation_delivery_outbox; RAISE EXCEPTION 'anon table access allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.aftertime_create_direct_with_outbox(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
    RAISE EXCEPTION 'anon RPC allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM * FROM public.invitation_outbox_nonces; RAISE EXCEPTION 'authenticated table access allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.aftertime_create_direct_with_outbox(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
    RAISE EXCEPTION 'authenticated RPC allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- All synthetic fixture writes roll back. Copies preserve the real gate.
BEGIN;
CREATE SCHEMA outbox_fixture;
CREATE TABLE outbox_fixture.direct_capsules (LIKE public.direct_capsules INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE outbox_fixture.direct_capsules ADD PRIMARY KEY (id);
CREATE TABLE outbox_fixture.direct_capsule_invitations (LIKE public.direct_capsule_invitations INCLUDING DEFAULTS);
ALTER TABLE outbox_fixture.direct_capsule_invitations ADD PRIMARY KEY (id), ADD UNIQUE (capsule_id),
  ADD UNIQUE (claim_secret_digest), ADD FOREIGN KEY (capsule_id) REFERENCES outbox_fixture.direct_capsules(id);
CREATE TABLE outbox_fixture.invitation_outbox_nonces (LIKE public.invitation_outbox_nonces INCLUDING ALL);
CREATE TABLE outbox_fixture.invitation_delivery_outbox (LIKE public.invitation_delivery_outbox INCLUDING ALL);
ALTER TABLE outbox_fixture.invitation_delivery_outbox
  ADD FOREIGN KEY (invitation_id) REFERENCES outbox_fixture.direct_capsule_invitations(id) ON DELETE CASCADE,
  ADD FOREIGN KEY (key_id,nonce,kdf_salt) REFERENCES outbox_fixture.invitation_outbox_nonces(key_id,nonce,kdf_salt);
DO $$ DECLARE definition text; BEGIN
  definition := pg_get_functiondef('public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea)'::regprocedure);
  definition := replace(definition, 'FUNCTION public.', 'FUNCTION outbox_fixture.');
  definition := replace(definition, 'public.direct_capsules', 'outbox_fixture.direct_capsules');
  definition := replace(definition, 'public.direct_capsule_invitations', 'outbox_fixture.direct_capsule_invitations');
  definition := replace(definition, 'public.invitation_outbox_nonces', 'outbox_fixture.invitation_outbox_nonces');
  definition := replace(definition, 'public.invitation_delivery_outbox', 'outbox_fixture.invitation_delivery_outbox');
  EXECUTE definition;
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES (md5('outbox-owner')::uuid,'owner@example.invalid',clock_timestamp());
DO $$
DECLARE v_owner uuid := md5('outbox-owner')::uuid; n integer; err text;
BEGIN
  -- The actual function must fail behind the real gate and roll back all rows.
  BEGIN
    PERFORM public.aftertime_create_direct_with_outbox(v_owner,md5('real-c')::uuid,md5('real-i')::uuid,md5('real-j')::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',decode(repeat('11',32),'hex'),'test-key',decode(repeat('22',12),'hex'),decode(repeat('44',32),'hex'),decode(repeat('33',59),'hex'));
    RAISE EXCEPTION 'Actual gated call succeeded';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
    IF err <> 'Unable to create invitation' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.direct_capsules WHERE id=md5('real-c')::uuid)
    OR EXISTS (SELECT 1 FROM public.invitation_outbox_nonces WHERE key_id='test-key') THEN
    RAISE EXCEPTION 'Real gate did not roll back'; END IF;

  SELECT count(*) INTO n FROM outbox_fixture.aftertime_create_direct_with_outbox(v_owner,md5('c1')::uuid,md5('i1')::uuid,md5('j1')::uuid,
    'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',decode(repeat('11',32),'hex'),'test-key',decode(repeat('22',12),'hex'),decode(repeat('44',32),'hex'),decode(repeat('33',59),'hex'));
  IF n <> 1 OR NOT EXISTS (SELECT 1 FROM outbox_fixture.direct_capsule_invitations i
      JOIN outbox_fixture.invitation_delivery_outbox o ON o.invitation_id=i.id
      JOIN outbox_fixture.invitation_outbox_nonces r ON r.key_id=o.key_id AND r.nonce=o.nonce AND r.kdf_salt=o.kdf_salt
      WHERE i.id=md5('i1')::uuid AND i.capsule_id=md5('c1')::uuid AND i.claim_secret_digest=decode(repeat('11',32),'hex')
        AND o.id=md5('j1')::uuid AND o.status='pending' AND o.attempts=0 AND o.kdf_salt=decode(repeat('44',32),'hex') AND o.ciphertext=decode(repeat('33',59),'hex')) THEN
    RAISE EXCEPTION 'Atomic fixture creation failed'; END IF;

  -- A lost-response retry and duplicate nonce must not create a second job.
  FOR n IN 1..2 LOOP
    BEGIN
      PERFORM outbox_fixture.aftertime_create_direct_with_outbox(v_owner,
        CASE WHEN n=1 THEN md5('c1')::uuid ELSE md5('c2')::uuid END,
        CASE WHEN n=1 THEN md5('i1')::uuid ELSE md5('i2')::uuid END,
        CASE WHEN n=1 THEN md5('j1')::uuid ELSE md5('j2')::uuid END,
        'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',
        decode(repeat(CASE WHEN n=1 THEN '11' ELSE '44' END,32),'hex'),'test-key',decode(repeat('22',12),'hex'),decode(repeat('44',32),'hex'),decode(repeat('33',59),'hex'));
      RAISE EXCEPTION 'Duplicate allowed';
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
      IF err <> 'Unable to create invitation' THEN RAISE; END IF;
    END;
  END LOOP;
  IF EXISTS (SELECT 1 FROM outbox_fixture.direct_capsules WHERE id=md5('c2')::uuid)
     OR (SELECT count(*) FROM outbox_fixture.invitation_delivery_outbox) <> 1 THEN RAISE EXCEPTION 'Duplicate left partial state'; END IF;

  -- Even with a different nonce, a committed salt collision is rejected.
  BEGIN
    PERFORM outbox_fixture.aftertime_create_direct_with_outbox(v_owner,md5('salt-c')::uuid,md5('salt-i')::uuid,md5('salt-j')::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',decode(repeat('aa',32),'hex'),'test-key',decode(repeat('ab',12),'hex'),decode(repeat('44',32),'hex'),decode(repeat('33',59),'hex'));
    RAISE EXCEPTION 'Duplicate salt allowed';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
    IF err <> 'Unable to create invitation' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM outbox_fixture.direct_capsules WHERE id=md5('salt-c')::uuid)
     OR EXISTS (SELECT 1 FROM outbox_fixture.direct_capsule_invitations WHERE id=md5('salt-i')::uuid)
     OR EXISTS (SELECT 1 FROM outbox_fixture.invitation_delivery_outbox WHERE id=md5('salt-j')::uuid)
     OR EXISTS (SELECT 1 FROM outbox_fixture.invitation_outbox_nonces WHERE nonce=decode(repeat('ab',12),'hex')) THEN
    RAISE EXCEPTION 'Salt collision left partial state'; END IF;

  -- A duplicate job ID fails after nonce reservation: transaction must undo all writes.
  BEGIN
    PERFORM outbox_fixture.aftertime_create_direct_with_outbox(v_owner,md5('c3')::uuid,md5('i3')::uuid,md5('j1')::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',decode(repeat('55',32),'hex'),'test-key',decode(repeat('66',12),'hex'),decode(repeat('66',32),'hex'),decode(repeat('33',59),'hex'));
    RAISE EXCEPTION 'Duplicate job allowed';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
    IF err <> 'Unable to create invitation' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM outbox_fixture.direct_capsules WHERE id=md5('c3')::uuid)
    OR EXISTS (SELECT 1 FROM outbox_fixture.direct_capsule_invitations WHERE id=md5('i3')::uuid)
    OR EXISTS (SELECT 1 FROM outbox_fixture.invitation_outbox_nonces WHERE nonce=decode(repeat('66',12),'hex')) THEN
    RAISE EXCEPTION 'Outbox failure left partial state'; END IF;

  -- A duplicate digest must roll back capsule, invitation, nonce and job.
  BEGIN
    PERFORM outbox_fixture.aftertime_create_direct_with_outbox(v_owner,md5('c4')::uuid,md5('i4')::uuid,md5('j4')::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()+interval '1 day',decode(repeat('11',32),'hex'),'test-key',decode(repeat('77',12),'hex'),decode(repeat('77',32),'hex'),decode(repeat('88',59),'hex'));
    RAISE EXCEPTION 'Duplicate digest allowed';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
    IF err <> 'Unable to create invitation' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM outbox_fixture.direct_capsules WHERE id=md5('c4')::uuid)
    OR EXISTS (SELECT 1 FROM outbox_fixture.direct_capsule_invitations WHERE id=md5('i4')::uuid)
    OR EXISTS (SELECT 1 FROM outbox_fixture.invitation_outbox_nonces WHERE nonce=decode(repeat('77',12),'hex'))
    OR EXISTS (SELECT 1 FROM outbox_fixture.invitation_delivery_outbox WHERE id=md5('j4')::uuid) THEN
    RAISE EXCEPTION 'Digest failure left partial state'; END IF;

  -- Database time remains authoritative even if an application prevalidates.
  BEGIN
    PERFORM outbox_fixture.aftertime_create_direct_with_outbox(v_owner,md5('c5')::uuid,md5('i5')::uuid,md5('j5')::uuid,
      'recipient@example.invalid','fixture','fixture',clock_timestamp()-interval '1 second',decode(repeat('99',32),'hex'),'test-key',decode(repeat('aa',12),'hex'),decode(repeat('aa',32),'hex'),decode(repeat('bb',59),'hex'));
    RAISE EXCEPTION 'Past unlock allowed';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
    IF err <> 'Unable to create invitation' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM outbox_fixture.direct_capsules WHERE id=md5('c5')::uuid) THEN
    RAISE EXCEPTION 'Invalid time left partial state'; END IF;

  BEGIN
    UPDATE outbox_fixture.invitation_delivery_outbox SET status='sent',next_attempt_at=NULL,finished_at=clock_timestamp() WHERE id=md5('j1')::uuid;
    RAISE EXCEPTION 'Terminal ciphertext retained';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE outbox_fixture.invitation_delivery_outbox SET status='sent',ciphertext=NULL,next_attempt_at=NULL,finished_at=clock_timestamp() WHERE id=md5('j1')::uuid;
  DELETE FROM outbox_fixture.direct_capsule_invitations WHERE id=md5('i1')::uuid;
  IF NOT EXISTS (SELECT 1 FROM outbox_fixture.invitation_outbox_nonces WHERE key_id='test-key' AND nonce=decode(repeat('22',12),'hex')) THEN
    RAISE EXCEPTION 'Nonce reservation lost after deletion'; END IF;
END $$;
ROLLBACK;
\echo 'Dormant outbox fixture, rollback, gate and local privilege checks passed.'
