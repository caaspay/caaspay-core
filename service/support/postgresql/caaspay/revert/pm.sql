BEGIN;

DROP TRIGGER IF EXISTS audit_method ON pm.payment_method CASCADE;
DROP TRIGGER IF EXISTS audit_settings ON pm.settings CASCADE;

DROP TRIGGER IF EXISTS update_method_timestamp ON pm.payment_method CASCADE;
DROP TRIGGER IF EXISTS update_settings_timestamp ON pm.settings CASCADE;

DROP FUNCTION IF EXISTS pm.update_timestamp CASCADE;
DROP FUNCTION IF EXISTS pm.record_audit CASCADE;

DROP TABLE IF EXISTS pm.method_properties CASCADE;
DROP TABLE IF EXISTS pm.settings CASCADE;
DROP TABLE IF EXISTS pm.payment_method CASCADE;
DROP TABLE IF EXISTS pm.audit CASCADE;
DROP TABLE IF EXISTS pm.log CASCADE;

DROP SCHEMA IF EXISTS pm CASCADE;

COMMIT;
