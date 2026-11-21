-- TEST ONLY: run inside a transaction in the dedicated loopback fixture cluster.
-- All synthetic rows, roles, fixture tables and copied functions are rolled back.
DO $$
BEGIN
  IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres'
     OR current_setting('port') <> '55485'
     OR current_setting('listen_addresses') <> '127.0.0.1'
     OR current_setting('data_directory') NOT LIKE '%/build/outbox014i1-postgres-014i4'
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.direct_capsule_invitations'::regclass
       AND conname = 'direct_capsule_invitations_disabled' AND convalidated
       AND pg_get_constraintdef(oid) = 'CHECK (false)') THEN
    RAISE EXCEPTION 'Requires the dedicated local gated cluster';
  END IF;
END $$;
CREATE ROLE aftertime_fixture_worker_014i4 NOLOGIN;
CREATE SCHEMA fixture014i4;
CREATE TABLE fixture014i4.direct_capsules (LIKE public.direct_capsules INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE fixture014i4.direct_capsules ADD PRIMARY KEY (id);
-- The isolated fixture has no CHECK(false); the actual public table is untouched.
CREATE TABLE fixture014i4.direct_capsule_invitations (LIKE public.direct_capsule_invitations INCLUDING DEFAULTS);
ALTER TABLE fixture014i4.direct_capsule_invitations ADD PRIMARY KEY (id), ADD UNIQUE (capsule_id),
  ADD UNIQUE (claim_secret_digest), ADD FOREIGN KEY (capsule_id) REFERENCES fixture014i4.direct_capsules(id);
CREATE TABLE fixture014i4.invitation_outbox_nonces (LIKE public.invitation_outbox_nonces INCLUDING ALL);
CREATE TABLE fixture014i4.invitation_delivery_outbox (LIKE public.invitation_delivery_outbox INCLUDING ALL);
ALTER TABLE fixture014i4.invitation_delivery_outbox
  ADD FOREIGN KEY (invitation_id) REFERENCES fixture014i4.direct_capsule_invitations(id) ON DELETE CASCADE,
  ADD FOREIGN KEY (key_id,nonce,kdf_salt) REFERENCES fixture014i4.invitation_outbox_nonces(key_id,nonce,kdf_salt);
DO $$ DECLARE definition text; BEGIN
  definition := pg_get_functiondef('public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea)'::regprocedure);
  definition := replace(definition, 'FUNCTION public.', 'FUNCTION fixture014i4.');
  definition := replace(definition, 'public.direct_capsules', 'fixture014i4.direct_capsules');
  definition := replace(definition, 'public.direct_capsule_invitations', 'fixture014i4.direct_capsule_invitations');
  definition := replace(definition, 'public.invitation_outbox_nonces', 'fixture014i4.invitation_outbox_nonces');
  definition := replace(definition, 'public.invitation_delivery_outbox', 'fixture014i4.invitation_delivery_outbox');
  EXECUTE definition;
END $$;
REVOKE ALL ON SCHEMA fixture014i4 FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA fixture014i4 FROM PUBLIC, anon, authenticated, service_role, aftertime_fixture_worker_014i4;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA fixture014i4 FROM PUBLIC, anon, authenticated, service_role, aftertime_fixture_worker_014i4;
GRANT USAGE ON SCHEMA fixture014i4 TO service_role, aftertime_fixture_worker_014i4;
GRANT EXECUTE ON FUNCTION fixture014i4.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea) TO service_role;
GRANT SELECT (id, invitation_id, key_id, nonce, kdf_salt, ciphertext) ON fixture014i4.invitation_delivery_outbox TO aftertime_fixture_worker_014i4;
GRANT SELECT (id, capsule_id, intended_email, claim_secret_digest) ON fixture014i4.direct_capsule_invitations TO aftertime_fixture_worker_014i4;
INSERT INTO auth.users(id,email,email_confirmed_at)
VALUES ('00000000-0000-4000-8000-000000000141', 'owner014i4@example.invalid', clock_timestamp());
