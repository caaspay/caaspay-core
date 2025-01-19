-- Check pp tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'pp'
  AND table_name IN ('payment_processors', 'processor_properties', 'settings', 'audit', 'log');

-- Check pp triggers
SELECT tgname
FROM pg_trigger
WHERE tgname IN ('audit_processors', 'audit_settings',
                 'update_processors_timestamp', 'update_settings_timestamp');

-- Check pp functions
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'pp'
  AND routine_name IN ('update_timestamp', 'record_audit');

