BEGIN;

-- Drop all CRUD functions
DROP FUNCTION IF EXISTS user_mgmt.create_or_update_company CASCADE;
DROP FUNCTION IF EXISTS user_mgmt.create_or_update_user CASCADE;
DROP FUNCTION IF EXISTS user_mgmt.create_or_update_group CASCADE;
DROP FUNCTION IF EXISTS user_mgmt.create_or_update_permission CASCADE;

COMMIT;

