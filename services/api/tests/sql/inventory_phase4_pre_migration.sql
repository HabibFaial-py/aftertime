-- READ ONLY; review before use. Intended ONLY for aftertime-sql-test,
-- project ref wokkxbgbrsmydozvyvkt; confirm the Dashboard independently.
-- This script cannot identify the connected Supabase project. Use a trusted
-- read-only session and do not run on development or production.
-- Catalog expressions have string literals redacted; inspect unusual metadata
-- privately. Counts may reveal information in a small project. Do not share
-- results without reviewing them. No application RPCs are called.

-- 1. Column definitions. Defaults are shown only for known safe expressions;
-- unknown defaults are flagged, never printed. Missing columns appear in 8.
SELECT c.relname AS table_name, a.attnum AS ordinal_position,
       a.attname AS column_name, pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
       NOT a.attnotnull AS nullable,
       CASE WHEN d.oid IS NULL THEN NULL
            WHEN pg_catalog.pg_get_expr(d.adbin, d.adrelid) IN ('now()', 'gen_random_uuid()', 'public.gen_random_uuid()')
              THEN pg_catalog.pg_get_expr(d.adbin, d.adrelid)
            ELSE '[nonstandard default redacted]' END AS default_expression,
       a.attgenerated AS generated_kind, a.attidentity AS identity_kind
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
LEFT JOIN pg_catalog.pg_attrdef AS d ON d.adrelid = c.oid AND d.adnum = a.attnum
WHERE n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')
ORDER BY c.relname, a.attnum;

-- 2. Actual constraint names/types/definitions. String literals are redacted
-- because unexpected CHECK definitions could embed sensitive values. The
-- sanitized definition is not an exact expression comparison.
SELECT c.relname AS table_name, con.conname AS constraint_name,
       con.contype AS constraint_type, con.convalidated AS validated,
       pg_catalog.regexp_replace(pg_catalog.pg_get_constraintdef(con.oid, true),
         $rx$'([^']|'')*'$rx$, $redact$'[literal redacted]'$redact$, 'g') AS definition_literals_redacted
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')
ORDER BY c.relname, con.conname;

-- 3. Indexes and non-internal triggers. Index expressions/predicates can have
-- literals, so they are redacted. Triggers show metadata, not function bodies,
-- trigger arguments, predicates or application-row data.
SELECT tbl.relname AS table_name, idx.relname AS index_name,
       i.indisunique AS is_unique, i.indisprimary AS is_primary,
       i.indisvalid AS is_valid, i.indisready AS is_ready,
       pg_catalog.regexp_replace(pg_catalog.pg_get_indexdef(i.indexrelid),
         $rx$'([^']|'')*'$rx$, $redact$'[literal redacted]'$redact$, 'g') AS definition_literals_redacted
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS tbl ON tbl.oid = i.indrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = tbl.relnamespace
JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
WHERE n.nspname = 'public' AND tbl.relname IN ('capsules', 'recipients')
ORDER BY tbl.relname, idx.relname;

SELECT n.nspname AS table_schema, c.relname AS table_name, t.tgname AS trigger_name, t.tgenabled AS enabled,
       t.tgtype AS event_flags, pn.nspname AS function_schema, p.proname AS function_name,
       t.tgqual IS NOT NULL AS has_condition, t.tgnargs AS argument_count
FROM pg_catalog.pg_trigger AS t
JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_proc AS p ON p.oid = t.tgfoid
JOIN pg_catalog.pg_namespace AS pn ON pn.oid = p.pronamespace
WHERE NOT t.tgisinternal AND (
    (n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')) OR
    (n.nspname = 'auth' AND c.relname = 'users' AND t.tgname = 'aftertime_auth_user_created')
)
ORDER BY n.nspname, c.relname, t.tgname;

-- 4. Application RPCs and profile provisioning trigger function. Only the
-- search_path setting is shown; no function source, arguments' defaults or
-- other potentially sensitive configuration values are output.
SELECT n.nspname AS function_schema, p.proname AS function_name,
       pg_catalog.oidvectortypes(p.proargtypes) AS argument_types,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner_role,
       p.prosecdef AS security_definer, p.provolatile AS volatility,
       ARRAY(SELECT CASE WHEN setting IN ('search_path=""', 'search_path=', 'search_path=public')
                         THEN setting ELSE '[nonstandard search_path redacted]' END
             FROM pg_catalog.unnest(p.proconfig) AS setting
             WHERE setting LIKE 'search_path=%') AS configured_search_path
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND pg_catalog.left(p.proname, 10) = 'aftertime_'
ORDER BY p.proname, pg_catalog.oidvectortypes(p.proargtypes);

-- 5. RLS flags, policies and explicit table ACLs. Policy expressions are not
-- output because unexpected policies can contain sensitive literals. PUBLIC
-- and inherited permissions also need the effective checks below.
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced, pg_catalog.pg_get_userbyid(c.relowner) AS owner_role
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')
ORDER BY c.relname;

SELECT tablename AS table_name, policyname AS policy_name, permissive,
       roles, cmd, qual IS NOT NULL AS has_using_expression,
       with_check IS NOT NULL AS has_check_expression
FROM pg_catalog.pg_policies
WHERE schemaname = 'public' AND tablename IN ('capsules', 'recipients')
ORDER BY tablename, policyname;

SELECT c.relname AS table_name,
       CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END AS grantee,
       pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
       acl.privilege_type, acl.is_grantable
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl, pg_catalog.acldefault('r', c.relowner))) AS acl
WHERE n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')
ORDER BY c.relname, grantee, acl.privilege_type;

-- Effective table and column privileges include inherited membership. A
-- missing role is reported as NULL, not as an apparent denial.
SELECT c.relname AS table_name, requested.role_name, roles.oid IS NOT NULL AS role_exists,
       roles.rolsuper AS is_superuser, roles.rolbypassrls AS bypass_rls,
       pg_catalog.has_table_privilege(roles.oid, c.oid, 'SELECT') AS can_select_table,
       pg_catalog.has_any_column_privilege(roles.oid, c.oid, 'SELECT') AS can_select_any_column,
       pg_catalog.has_table_privilege(roles.oid, c.oid, 'INSERT') AS can_insert,
       pg_catalog.has_any_column_privilege(roles.oid, c.oid, 'INSERT') AS can_insert_any_column,
       pg_catalog.has_table_privilege(roles.oid, c.oid, 'UPDATE') AS can_update,
       pg_catalog.has_any_column_privilege(roles.oid, c.oid, 'UPDATE') AS can_update_any_column,
       pg_catalog.has_table_privilege(roles.oid, c.oid, 'DELETE') AS can_delete
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS requested(role_name)
LEFT JOIN pg_catalog.pg_roles AS roles ON roles.rolname = requested.role_name
WHERE n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')
ORDER BY c.relname, requested.role_name;

SELECT c.relname AS table_name, a.attname AS column_name, requested.role_name,
       roles.oid IS NOT NULL AS role_exists,
       pg_catalog.has_column_privilege(roles.oid, c.oid, a.attnum, 'SELECT') AS can_select,
       pg_catalog.has_column_privilege(roles.oid, c.oid, a.attnum, 'INSERT') AS can_insert,
       pg_catalog.has_column_privilege(roles.oid, c.oid, a.attnum, 'UPDATE') AS can_update
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS requested(role_name)
LEFT JOIN pg_catalog.pg_roles AS roles ON roles.rolname = requested.role_name
WHERE n.nspname = 'public' AND c.relname IN ('capsules', 'recipients')
ORDER BY c.relname, a.attnum, requested.role_name;

-- Each overload is checked separately. These are catalog-based effective
-- privilege checks, not actual calls under the client roles.
SELECT p.proname AS function_name, pg_catalog.oidvectortypes(p.proargtypes) AS argument_types,
       requested.role_name, roles.oid IS NOT NULL AS role_exists,
       pg_catalog.has_function_privilege(roles.oid, p.oid, 'EXECUTE') AS can_execute
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS requested(role_name)
LEFT JOIN pg_catalog.pg_roles AS roles ON roles.rolname = requested.role_name
WHERE n.nspname = 'public' AND pg_catalog.left(p.proname, 10) = 'aftertime_'
ORDER BY p.proname, pg_catalog.oidvectortypes(p.proargtypes), requested.role_name;

-- 6. Aggregate data inventory. Categories overlap and some can legitimately
-- be nonzero, particularly historical unbound claims. Counts alone do not
-- identify a row, but small counts can disclose facts about a small project.
SELECT (SELECT pg_catalog.count(*) FROM public.capsules) AS capsules_total,
       (SELECT pg_catalog.count(*) FROM public.recipients) AS recipient_rows,
       (SELECT pg_catalog.count(*) FROM public.recipients WHERE invite_token_hash IS NOT NULL) AS token_backed,
       (SELECT pg_catalog.count(*) FROM public.recipients WHERE invite_token_hash IS NULL AND claimed_at IS NOT NULL) AS tokenless_claimed,
       (SELECT pg_catalog.count(*) FROM public.recipients WHERE claimed_at IS NOT NULL AND user_id IS NULL) AS historical_unbound_claims,
       (SELECT pg_catalog.count(*) FROM public.capsules AS c WHERE NOT EXISTS
         (SELECT 1 FROM public.recipients AS r WHERE r.capsule_id = c.id)) AS capsules_without_recipient,
       (SELECT pg_catalog.count(*) FROM public.recipients AS r JOIN public.capsules AS c ON c.id = r.capsule_id
         WHERE r.user_id IS NOT NULL AND r.user_id <> c.owner_id) AS bound_to_non_owner,
       (SELECT pg_catalog.count(*) FROM public.recipients AS r LEFT JOIN public.capsules AS c ON c.id = r.capsule_id
         WHERE c.id IS NULL) AS recipients_without_capsule,
       (SELECT pg_catalog.count(*) FROM public.recipients WHERE
         (invite_token_hash IS NULL) <> (invite_expires_at IS NULL)
         OR (invite_revoked_at IS NOT NULL AND invite_token_hash IS NULL)
         OR (user_id IS NOT NULL AND claimed_at IS NULL)
         OR (invite_token_hash IS NULL AND claimed_at IS NULL)
         OR (opened_at IS NOT NULL AND (claimed_at IS NULL OR opened_at < claimed_at))
         OR (claimed_at IS NOT NULL AND invite_token_hash IS NOT NULL AND claimed_at >= invite_expires_at)
         OR (claimed_at IS NOT NULL AND invite_revoked_at IS NOT NULL AND claimed_at >= invite_revoked_at)
       ) AS recipient_state_anomalies;

-- 7. Catalog-based self-RPC signature drift. Missing or differently typed
-- functions are flagged; extra overloads are visible in sections 4 and 5.
SELECT expected.signature,
       pg_catalog.to_regprocedure(expected.signature) IS NOT NULL AS signature_present
FROM (VALUES
  ('public.aftertime_create_self_capsule(uuid,text,text,timestamp with time zone)'),
  ('public.aftertime_reveal_self_capsule(uuid,uuid)'),
  ('public.aftertime_cancel_self_capsule(uuid,uuid)'),
  ('public.aftertime_provision_profile()')
) AS expected(signature)
ORDER BY expected.signature;

-- 8. Expected column type/nullability drift relative to migration 0001. This
-- is not a complete schema equivalence check; review constraints, defaults,
-- privileges, functions, indexes, triggers and unexpected columns above.
SELECT expected.table_name, expected.column_name, expected.data_type AS expected_type,
       expected.nullable AS expected_nullable,
       actual.column_name IS NOT NULL AS column_present,
       CASE WHEN actual.column_name IS NULL THEN NULL
            ELSE actual.data_type = expected.data_type AND (actual.is_nullable = 'YES') = expected.nullable END AS matches_type_and_nullability
FROM (VALUES
  ('capsules','id','uuid',false), ('capsules','owner_id','uuid',false),
  ('capsules','title','text',false), ('capsules','body','text',false),
  ('capsules','media_key','text',true), ('capsules','unlock_at','timestamp with time zone',false),
  ('capsules','created_at','timestamp with time zone',false), ('capsules','cancelled_at','timestamp with time zone',true),
  ('capsules','deleted_at','timestamp with time zone',true),
  ('recipients','id','uuid',false), ('recipients','capsule_id','uuid',false),
  ('recipients','intended_email','text',false), ('recipients','user_id','uuid',true),
  ('recipients','invite_token_hash','bytea',true), ('recipients','invite_expires_at','timestamp with time zone',true),
  ('recipients','invite_revoked_at','timestamp with time zone',true), ('recipients','claimed_at','timestamp with time zone',true),
  ('recipients','opened_at','timestamp with time zone',true)
) AS expected(table_name, column_name, data_type, nullable)
LEFT JOIN information_schema.columns AS actual
  ON actual.table_schema = 'public' AND actual.table_name = expected.table_name AND actual.column_name = expected.column_name
ORDER BY expected.table_name, expected.column_name;
