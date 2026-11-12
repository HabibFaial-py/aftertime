-- TEST ONLY: empty, disposable plain PostgreSQL cluster, never Supabase.
\set ON_ERROR_STOP on
DO $$
BEGIN
    IF current_database() <> 'aftertime_rpc_test' OR current_user <> 'postgres'
       OR to_regnamespace('auth') IS NOT NULL
       OR to_regclass('public.profiles') IS NOT NULL THEN
        RAISE EXCEPTION 'Requires an empty aftertime_rpc_test database as postgres';
    END IF;
END;
$$;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
-- Only the managed Auth columns referenced by our migrations are simulated.
CREATE TABLE auth.users (
    id uuid PRIMARY KEY,
    email text,
    email_confirmed_at timestamptz
);
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
\ir ../../migrations/0001_initial.sql
\ir ../../migrations/0002_profile_provisioning.sql
\ir ../../migrations/0003_create_self_capsule.sql
