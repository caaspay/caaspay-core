BEGIN;

-- Check pm tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'pm'
  AND table_name IN ('payment_method', 'method_properties', 'settings', 'audit', 'log');

-- Check pm triggers
SELECT tgname
FROM pg_trigger
WHERE tgname IN ('audit_method', 'audit_settings',
                 'update_method_timestamp', 'update_settings_timestamp');

-- Check pm functions
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'pm'
  AND routine_name IN ('update_timestamp', 'record_audit');

COMMIT;
