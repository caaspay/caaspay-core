-- Verify CRUD functions for user_mgmt
SELECT proname
FROM pg_proc
WHERE pronamespace = 'user_mgmt'::regnamespace
  AND proname IN (
    'create_or_update_company',
    'create_or_update_user',
    'create_or_update_group',
    'create_or_update_permission'
  );

-- Verify fallback user ID configuration
SELECT current_setting('user_mgmt.fallback_user_id');

