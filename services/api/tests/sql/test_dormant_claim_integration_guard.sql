-- Read-only checks on the actual 0009 claim RPC in the verified disposable cluster.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
DO $$ DECLARE
  fn regprocedure := 'public.aftertime_claim_direct_capsule(uuid,uuid,bytea)'::regprocedure;
BEGIN
  IF current_database() <> 'aftertime_rpc_test' OR session_user <> 'postgres'
     OR host(inet_server_addr()) <> '127.0.0.1' OR inet_server_port() <> 55485
     OR NOT EXISTS (SELECT FROM pg_constraint
         WHERE conrelid = 'public.direct_capsule_invitations'::regclass
           AND conname = 'direct_capsule_invitations_disabled' AND convalidated
           AND pg_get_constraintdef(oid) = 'CHECK (false)')
     OR EXISTS (SELECT FROM public.direct_capsule_invitations) THEN
    RAISE EXCEPTION 'Requires the dedicated gated claim cluster';
  END IF;
  IF has_function_privilege('anon', fn, 'EXECUTE')
     OR has_function_privilege('authenticated', fn, 'EXECUTE')
     OR has_function_privilege('aftertime_invitation_worker', fn, 'EXECUTE')
     OR NOT has_function_privilege('service_role', fn, 'EXECUTE')
     OR has_table_privilege('service_role', 'public.direct_capsule_invitations', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'Unsafe claim privileges';
  END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.aftertime_claim_direct_capsule(NULL, NULL, NULL);
    RAISE EXCEPTION 'Authenticated client bypassed the service boundary';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF EXISTS (SELECT FROM public.aftertime_claim_direct_capsule(NULL, NULL, NULL)) THEN
    RAISE EXCEPTION 'Malformed claim returned metadata';
  END IF;
END $$;
ROLLBACK;
\echo 'Dormant claim gate and service-only SQL privileges passed.'
