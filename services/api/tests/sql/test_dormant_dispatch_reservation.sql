-- Run only on verified disposable PostgreSQL with 0013. Read-only checks on the actual schema.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
DO $$ DECLARE
  fn regprocedure := 'public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)'::regprocedure;
  worker name := 'aftertime_invitation_worker';
BEGIN
  IF NOT EXISTS (SELECT FROM pg_constraint
      WHERE conrelid = 'public.direct_capsule_invitations'::regclass
        AND conname = 'direct_capsule_invitations_disabled' AND convalidated
        AND pg_get_constraintdef(oid) = 'CHECK (false)')
     OR NOT EXISTS (SELECT FROM pg_constraint
      WHERE conrelid = 'public.invitation_delivery_outbox'::regclass
        AND conname = 'invitation_delivery_dispatch_shape' AND contype = 'c' AND convalidated)
     OR EXISTS (SELECT FROM public.invitation_delivery_outbox) THEN
    RAISE EXCEPTION 'The dormant gate or dispatch constraint is missing, or the outbox is not empty';
  END IF;
  IF EXISTS (SELECT FROM pg_roles r WHERE r.rolname = worker
             AND (r.rolcanlogin OR r.rolinherit OR EXISTS (SELECT FROM pg_auth_members m WHERE m.roleid = r.oid)))
     OR has_function_privilege(worker, 'public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)', 'EXECUTE')
     OR NOT has_function_privilege(worker, fn, 'EXECUTE')
     OR has_table_privilege(worker, 'public.invitation_delivery_outbox', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('authenticated', fn, 'EXECUTE')
     OR has_function_privilege('service_role', fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'Unsafe dispatch transition privileges';
  END IF;
END $$;
SET LOCAL ROLE aftertime_invitation_worker;
DO $$ BEGIN
  IF EXISTS (SELECT FROM public.aftertime_invitation_worker_transition_v3(
      '00000000-0000-4000-8000-000000000199', 'lease', NULL, NULL, NULL)) THEN
    RAISE EXCEPTION 'Unexpected job in gated outbox';
  END IF;
  BEGIN
    PERFORM public.aftertime_invitation_worker_transition_v2(NULL, 'lease', NULL, NULL);
    RAISE EXCEPTION 'Worker can bypass v3';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
ROLLBACK;
\echo 'Dormant dispatch reservation gate, constraint and effective permissions passed.'
