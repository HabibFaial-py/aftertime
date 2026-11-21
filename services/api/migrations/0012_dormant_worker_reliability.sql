-- DRAFT ONLY: requires 0001-0011. No production worker or delivery.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.direct_capsule_invitations'::regclass
        AND c.conname='direct_capsule_invitations_disabled' AND c.convalidated
        AND pg_catalog.pg_get_constraintdef(c.oid)='CHECK (false)') THEN
    RAISE EXCEPTION 'Dormant invitation gate missing';
  END IF;
END $$;
ALTER TABLE public.invitation_delivery_outbox
  ADD COLUMN lease_generation bigint NOT NULL DEFAULT 0 CHECK (lease_generation >= 0);

-- Results are provisional until the calling transaction commits successfully.
-- An empty result means denied/no change, not an acknowledgement.
CREATE FUNCTION public.aftertime_invitation_worker_transition_v2(
  p_job_id uuid, p_action text, p_token uuid, p_generation bigint
) RETURNS TABLE (outcome text, job_id uuid, lease_token uuid, lease_generation bigint,
  lease_until timestamptz, capsule_id uuid, invitation_id uuid, intended_email text,
  key_id text, nonce bytea, kdf_salt bytea, ciphertext bytea, secret_digest bytea)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' SET timezone = 'UTC' AS $$
DECLARE
  v_capsule_id uuid; v_invitation_id uuid; v_token uuid;
  c public.direct_capsules%ROWTYPE; i public.direct_capsule_invitations%ROWTYPE;
  o public.invitation_delivery_outbox%ROWTYPE; v_now timestamptz; v_status text;
BEGIN
  IF p_job_id IS NULL OR p_action IS NULL OR p_action NOT IN ('lease','prepare','sent','retry','fail')
     OR (p_action='lease' AND (p_token IS NOT NULL OR p_generation IS NOT NULL))
     OR (p_action<>'lease' AND (p_token IS NULL OR p_generation IS NULL OR p_generation <= 0)) THEN RETURN; END IF;
  SELECT x.invitation_id, y.capsule_id INTO v_invitation_id, v_capsule_id
    FROM public.invitation_delivery_outbox x JOIN public.direct_capsule_invitations y ON y.id=x.invitation_id
    WHERE x.id=p_job_id;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO c FROM public.direct_capsules x WHERE x.id=v_capsule_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO i FROM public.direct_capsule_invitations x
    WHERE x.id=v_invitation_id AND x.capsule_id=v_capsule_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO o FROM public.invitation_delivery_outbox x
    WHERE x.id=p_job_id AND x.invitation_id=v_invitation_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND OR o.status <> 'pending' THEN RETURN; END IF;
  v_now := pg_catalog.clock_timestamp();
  IF p_action='lease' THEN
    IF o.next_attempt_at > v_now OR (o.lease_until IS NOT NULL AND o.lease_until > v_now) THEN RETURN; END IF;
  ELSIF o.lease_token IS DISTINCT FROM p_token OR o.lease_generation IS DISTINCT FROM p_generation
        OR o.lease_until IS NULL OR o.lease_until <= v_now THEN RETURN;
  END IF;

  IF c.cancelled_at IS NOT NULL OR c.deleted_at IS NOT NULL OR i.revoked_at IS NOT NULL
     OR i.claimed_at IS NOT NULL OR i.claimed_user_id IS NOT NULL OR i.claim_secret_digest IS NULL
     OR v_now < c.created_at OR v_now < i.created_at THEN v_status := 'cancelled';
  ELSIF v_now >= i.expires_at THEN v_status := 'expired';
  ELSIF p_action='lease' AND o.attempts >= 5 THEN v_status := 'failed';
  ELSIF p_action='sent' THEN v_status := 'sent';
  ELSIF p_action='fail' OR (p_action='retry' AND o.attempts >= 5) THEN v_status := 'failed';
  END IF;
  IF v_status IS NOT NULL THEN
    UPDATE public.invitation_delivery_outbox x SET status=v_status, ciphertext=NULL,
      next_attempt_at=NULL, finished_at=v_now, lease_token=NULL, lease_until=NULL WHERE x.id=p_job_id;
    RETURN QUERY SELECT v_status, p_job_id, NULL::uuid, o.lease_generation, NULL::timestamptz,
      NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::bytea, NULL::bytea, NULL::bytea, NULL::bytea;
    RETURN;
  END IF;
  IF p_action='lease' THEN
    v_token := pg_catalog.gen_random_uuid();
    UPDATE public.invitation_delivery_outbox x SET lease_token=v_token,
      lease_until=v_now + interval '60 seconds', lease_generation=x.lease_generation+1, attempts=x.attempts+1
      WHERE x.id=p_job_id;
    RETURN QUERY SELECT 'leased'::text, p_job_id, v_token, o.lease_generation+1,
      v_now + interval '60 seconds', NULL::uuid, NULL::uuid, NULL::text, NULL::text,
      NULL::bytea, NULL::bytea, NULL::bytea, NULL::bytea;
  ELSIF p_action='prepare' THEN
    RETURN QUERY SELECT 'prepared'::text, o.id, o.lease_token, o.lease_generation, o.lease_until,
      c.id, i.id, i.intended_email, o.key_id, o.nonce, o.kdf_salt, o.ciphertext, i.claim_secret_digest;
  ELSE -- retry clears lease and schedules bounded database-time backoff.
    UPDATE public.invitation_delivery_outbox x SET lease_token=NULL, lease_until=NULL,
      next_attempt_at=v_now + pg_catalog.make_interval(secs => LEAST(300, 30 * (1 << (o.attempts - 1))))
      WHERE x.id=p_job_id;
    RETURN QUERY SELECT 'retry'::text, p_job_id, NULL::uuid, o.lease_generation, NULL::timestamptz,
      NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::bytea, NULL::bytea, NULL::bytea, NULL::bytea;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Invitation worker unavailable';
END $$;
ALTER FUNCTION public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.aftertime_invitation_worker_transition(uuid,uuid,text)
  FROM PUBLIC, anon, authenticated, service_role, aftertime_invitation_worker;
REVOKE ALL ON FUNCTION public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)
  FROM PUBLIC, anon, authenticated, service_role, aftertime_invitation_worker;
GRANT EXECUTE ON FUNCTION public.aftertime_invitation_worker_transition_v2(uuid,text,uuid,bigint)
  TO aftertime_invitation_worker;
COMMIT;
