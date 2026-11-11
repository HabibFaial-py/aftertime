-- Local review draft. Apply only after approval and isolated testing.
-- Requires 0001_initial.sql and a trusted migration session as postgres.
BEGIN;

CREATE FUNCTION public.aftertime_provision_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id)
    VALUES (NEW.id)
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

ALTER FUNCTION public.aftertime_provision_profile() OWNER TO postgres;

-- Remove default PUBLIC and Supabase role grants; this is not a client RPC.
REVOKE ALL ON FUNCTION public.aftertime_provision_profile()
FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER aftertime_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.aftertime_provision_profile();

-- Install the trigger first so subsequent Auth inserts are covered.
-- Safe to repeat this backfill: existing names/timestamps are never updated.
INSERT INTO public.profiles (id)
SELECT users.id
FROM auth.users AS users
WHERE NOT EXISTS (
    SELECT 1 FROM public.profiles AS profiles WHERE profiles.id = users.id
)
ON CONFLICT (id) DO NOTHING;

COMMIT;
