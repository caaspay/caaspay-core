-- Check transaction tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'transaction'
  AND table_name IN ('transactions', 'audit', 'log');

-- Check transaction triggers
SELECT tgname
FROM pg_trigger
WHERE tgname IN ('audit_transactions', 'update_transactions_timestamp');

-- Check transaction functions
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'transaction'
  AND routine_name IN ('update_timestamp', 'record_audit');

