-- DRAFT ONLY. Requires 0001-0012 and the dormant invitation gate.
BEGIN;
LOCK TABLE public.direct_capsule_invitations IN ACCESS SHARE MODE;
LOCK TABLE public.invitation_delivery_outbox IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid = 'public.direct_capsule_invitations'::regclass
        AND c.conname = 'direct_capsule_invitations_disabled' AND c.convalidated
        AND pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK (false)') THEN
    RAISE EXCEPTION 'Dormant invitation gate missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.invitation_delivery_outbox) THEN
    RAISE EXCEPTION 'Dispatch reservation migration requires an empty dormant outbox';
  END IF;
END $$;

ALTER TABLE public.invitation_delivery_outbox
  ADD COLUMN dispatch_generation bigint,
  ADD CONSTRAINT invitation_delivery_dispatch_shape CHECK (
    dispatch_generation IS NULL OR (
      dispatch_generation BETWEEN 1 AND lease_generation AND attempts > 0
      AND (status <> 'pending' OR lease_token IS NOT NULL)));

-- A fresh reservation is the only result that may authorize a provider call,
-- and only once acknowledged by commit. A repeat returns lookup-only metadata.
-- Acceptance and rejection are facts supplied by the trusted worker for the
-- exact dispatch generation. A timeout or missing record supplies neither.
CREATE FUNCTION public.aftertime_invitation_worker_transition_v3(
  p_job_id uuid, p_action text, p_token uuid, p_generation bigint, p_dispatch_generation bigint
) RETURNS TABLE (outcome text, job_id uuid, lease_token uuid, lease_generation bigint,
  lease_until timestamptz, capsule_id uuid, invitation_id uuid, intended_email text,
  key_id text, nonce bytea, kdf_salt bytea, ciphertext bytea, secret_digest bytea, dispatch_generation bigint)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' SET timezone = 'UTC' AS $$
DECLARE
  v_capsule_id uuid;
  v_invitation_id uuid;
  c public.direct_capsules%ROWTYPE;
  i public.direct_capsule_invitations%ROWTYPE;
  o public.invitation_delivery_outbox%ROWTYPE;
  v_now timestamptz;
  v_token uuid;
BEGIN
  IF p_job_id IS NULL OR p_action IS NULL OR p_action NOT IN ('lease','prepare','reserve','accept','reject','fail')
     OR (p_action = 'lease' AND (p_token IS NOT NULL OR p_generation IS NOT NULL))
     OR (p_action <> 'lease' AND (p_token IS NULL OR p_generation IS NULL OR p_generation <= 0))
     OR (p_action IN ('accept','reject') AND (p_dispatch_generation IS NULL OR p_dispatch_generation <= 0
                                             OR p_dispatch_generation > p_generation))
     OR (p_action NOT IN ('accept','reject') AND p_dispatch_generation IS NOT NULL) THEN RETURN; END IF;

  SELECT x.invitation_id, y.capsule_id INTO v_invitation_id, v_capsule_id
  FROM public.invitation_delivery_outbox x JOIN public.direct_capsule_invitations y ON y.id = x.invitation_id
  WHERE x.id = p_job_id;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO c FROM public.direct_capsules x WHERE x.id = v_capsule_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO i FROM public.direct_capsule_invitations x
  WHERE x.id = v_invitation_id AND x.capsule_id = v_capsule_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO o FROM public.invitation_delivery_outbox x
  WHERE x.id = p_job_id AND x.invitation_id = v_invitation_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND OR o.status <> 'pending' THEN RETURN; END IF;

  v_now := pg_catalog.clock_timestamp();
  IF p_action = 'lease' THEN
    IF o.next_attempt_at > v_now OR (o.lease_until IS NOT NULL AND o.lease_until > v_now) THEN RETURN; END IF;
  ELSIF o.lease_token IS DISTINCT FROM p_token OR o.lease_generation IS DISTINCT FROM p_generation
        OR o.lease_until IS NULL OR o.lease_until <= v_now THEN RETURN;
  END IF;
  IF (p_action IN ('accept','reject') AND o.dispatch_generation IS DISTINCT FROM p_dispatch_generation)
     OR (p_action = 'fail' AND o.dispatch_generation IS NOT NULL) THEN RETURN; END IF;

  job_id := o.id;
  lease_generation := o.lease_generation;
  IF c.cancelled_at IS NOT NULL OR c.deleted_at IS NOT NULL OR i.revoked_at IS NOT NULL
     OR i.claimed_at IS NOT NULL OR i.claimed_user_id IS NOT NULL OR i.claim_secret_digest IS NULL
     OR v_now < c.created_at OR v_now < i.created_at THEN outcome := 'cancelled';
  ELSIF v_now >= i.expires_at THEN outcome := 'expired';
  ELSIF p_action = 'lease' AND o.dispatch_generation IS NULL AND o.attempts >= 5 THEN outcome := 'failed';
  ELSIF p_action = 'accept' THEN outcome := 'sent'; dispatch_generation := o.dispatch_generation;
  ELSIF p_action = 'reject' AND o.attempts >= 5 THEN outcome := 'failed'; dispatch_generation := o.dispatch_generation;
  ELSIF p_action = 'fail' THEN outcome := 'failed';
  END IF;
  IF outcome IS NOT NULL THEN
    UPDATE public.invitation_delivery_outbox x SET status = outcome, ciphertext = NULL,
      next_attempt_at = NULL, finished_at = v_now, lease_token = NULL, lease_until = NULL WHERE x.id = p_job_id;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_action = 'lease' THEN
    outcome := 'leased';
    v_token := pg_catalog.gen_random_uuid();
    lease_token := v_token;
    lease_until := v_now + interval '60 seconds';
    lease_generation := o.lease_generation + 1;
    UPDATE public.invitation_delivery_outbox x SET lease_token = v_token,
      lease_until = v_now + interval '60 seconds', lease_generation = x.lease_generation + 1,
      attempts = x.attempts + CASE WHEN x.dispatch_generation IS NULL THEN 1 ELSE 0 END
    WHERE x.id = p_job_id;
  ELSIF p_action IN ('prepare','reserve') THEN
    lease_token := o.lease_token;
    lease_until := o.lease_until;
    IF o.dispatch_generation IS NOT NULL THEN
      outcome := 'reconcile';
      dispatch_generation := o.dispatch_generation;
    ELSIF p_action = 'prepare' THEN
      outcome := 'prepared';
      capsule_id := c.id;
      invitation_id := i.id;
      intended_email := i.intended_email;
      key_id := o.key_id;
      nonce := o.nonce;
      kdf_salt := o.kdf_salt;
      ciphertext := o.ciphertext;
      secret_digest := i.claim_secret_digest;
    ELSE
      PERFORM pg_catalog.set_config('synchronous_commit', 'on', true);
      UPDATE public.invitation_delivery_outbox x SET dispatch_generation = p_generation WHERE x.id = p_job_id;
      outcome := 'reserved';
      dispatch_generation := p_generation;
    END IF;
  ELSE -- Confirmed rejection with attempts remaining.
    UPDATE public.invitation_delivery_outbox x SET lease_token = NULL, lease_until = NULL,
      dispatch_generation = NULL, next_attempt_at = v_now + pg_catalog.make_interval(secs => 30 * (1 << (o.attempts - 1)))
      WHERE x.id = p_job_id;
    outcome := 'retry';
    dispatch_generation := o.dispatch_generation;
  END IF;
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invitation worker unavailable';
END $$;

ALTER FUNCTION public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)
  FROM PUBLIC, anon, authenticated, service_role, aftertime_invitation_worker;
REVOKE ALL ON FUNCTION public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)
  FROM PUBLIC, anon, authenticated, service_role, aftertime_invitation_worker;
GRANT EXECUTE ON FUNCTION public.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)
  TO aftertime_invitation_worker;
COMMIT;
