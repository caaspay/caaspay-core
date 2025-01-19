-- Verify schema
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'user_mgmt';

-- Verify tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'user_mgmt'
  AND table_name IN ('user', 'company', 'group', 'permission', 'user_group_relation', 'feature', 'audit', 'log');

-- Verify triggers
SELECT tgname
FROM pg_trigger
WHERE tgname IN (
    'audit_company', 'audit_user', 'audit_group', 'audit_permission', 'audit_feature',
    'update_company_timestamp', 'update_user_timestamp', 'update_group_timestamp',
    'update_permission_timestamp', 'update_feature_timestamp'
);

-- Verify audit functions
SELECT proname
FROM pg_proc
WHERE pronamespace = 'user_mgmt'::regnamespace
  AND proname = 'record_audit';

-- Verify timestamp function
SELECT proname
FROM pg_proc
WHERE pronamespace = 'user_mgmt'::regnamespace
  AND proname = 'update_timestamp';

-- Verify system user exists
SELECT id
FROM user_mgmt.user
WHERE id = '00000000-0000-0000-0000-000000000000';

