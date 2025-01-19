-- Check customer tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'customer'
  AND table_name IN ('client_details', 'payment_methods', 'customer_properties', 'history', 'stats', 'audit', 'log');

-- Check customer triggers
SELECT tgname
FROM pg_trigger
WHERE tgname IN ('audit_client_details', 'audit_payment_methods', 'audit_stats',
                 'update_client_details_timestamp', 'update_payment_methods_timestamp', 'update_stats_timestamp');

-- Check customer functions
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'customer'
  AND routine_name IN ('update_timestamp', 'record_audit');

