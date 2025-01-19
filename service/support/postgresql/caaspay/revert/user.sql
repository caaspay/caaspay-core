BEGIN;
-- Drop all triggers
DROP TRIGGER IF EXISTS audit_company ON user_mgmt.company CASCADE;
DROP TRIGGER IF EXISTS audit_user ON user_mgmt.user CASCADE;
DROP TRIGGER IF EXISTS audit_group ON user_mgmt.group CASCADE;
DROP TRIGGER IF EXISTS audit_permission ON user_mgmt.permission CASCADE;
DROP TRIGGER IF EXISTS audit_feature ON user_mgmt.feature CASCADE;

DROP TRIGGER IF EXISTS update_company_timestamp ON user_mgmt.company CASCADE;
DROP TRIGGER IF EXISTS update_user_timestamp ON user_mgmt.user CASCADE;
DROP TRIGGER IF EXISTS update_group_timestamp ON user_mgmt.group CASCADE;
DROP TRIGGER IF EXISTS update_permission_timestamp ON user_mgmt.permission CASCADE;
DROP TRIGGER IF EXISTS update_feature_timestamp ON user_mgmt.feature CASCADE;

-- Drop functions
DROP FUNCTION IF EXISTS user_mgmt.record_audit CASCADE;
DROP FUNCTION IF EXISTS user_mgmt.update_timestamp CASCADE;

-- Drop tables
DROP TABLE IF EXISTS user_mgmt.feature CASCADE;
DROP TABLE IF EXISTS user_mgmt.user_group_relation CASCADE;
DROP TABLE IF EXISTS user_mgmt.permission CASCADE;
DROP TABLE IF EXISTS user_mgmt.group CASCADE;
DROP TABLE IF EXISTS user_mgmt.user CASCADE;
DROP TABLE IF EXISTS user_mgmt.company CASCADE;
DROP TABLE IF EXISTS user_mgmt.audit CASCADE;
DROP TABLE IF EXISTS user_mgmt.log CASCADE;

-- Drop schema
DROP SCHEMA IF EXISTS user_mgmt CASCADE;

COMMIT;

