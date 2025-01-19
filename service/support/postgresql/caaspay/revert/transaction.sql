BEGIN;
DROP TRIGGER IF EXISTS audit_transactions ON transaction.transactions CASCADE;

DROP TRIGGER IF EXISTS update_transactions_timestamp ON transaction.transactions CASCADE;

DROP FUNCTION IF EXISTS transaction.update_timestamp CASCADE;
DROP FUNCTION IF EXISTS transaction.record_audit CASCADE;

DROP TABLE IF EXISTS transaction.transactions CASCADE;
DROP TABLE IF EXISTS transaction.audit CASCADE;
DROP TABLE IF EXISTS transaction.log CASCADE;

DROP SCHEMA IF EXISTS transaction CASCADE;
COMMIT;

