BEGIN;
DROP TRIGGER IF EXISTS audit_client_details ON customer.client_details CASCADE;
DROP TRIGGER IF EXISTS audit_payment_methods ON customer.payment_methods CASCADE;
DROP TRIGGER IF EXISTS audit_stats ON customer.stats CASCADE;

DROP TRIGGER IF EXISTS update_client_details_timestamp ON customer.client_details CASCADE;
DROP TRIGGER IF EXISTS update_payment_methods_timestamp ON customer.payment_methods CASCADE;
DROP TRIGGER IF EXISTS update_stats_timestamp ON customer.stats CASCADE;

DROP FUNCTION IF EXISTS customer.update_timestamp CASCADE;
DROP FUNCTION IF EXISTS customer.record_audit CASCADE;

DROP TABLE IF EXISTS customer.stats CASCADE;
DROP TABLE IF EXISTS customer.history CASCADE;
DROP TABLE IF EXISTS customer.customer_properties CASCADE;
DROP TABLE IF EXISTS customer.payment_methods CASCADE;
DROP TABLE IF EXISTS customer.client_details CASCADE;
DROP TABLE IF EXISTS customer.audit CASCADE;
DROP TABLE IF EXISTS customer.log CASCADE;

DROP SCHEMA IF EXISTS customer CASCADE;
COMMIT;

