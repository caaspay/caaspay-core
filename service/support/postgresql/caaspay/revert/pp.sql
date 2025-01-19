BEGIN;
DROP TRIGGER IF EXISTS audit_processors ON pp.payment_processors CASCADE;
DROP TRIGGER IF EXISTS audit_settings ON pp.settings CASCADE;

DROP TRIGGER IF EXISTS update_processors_timestamp ON pp.payment_processors CASCADE;
DROP TRIGGER IF EXISTS update_settings_timestamp ON pp.settings CASCADE;

DROP FUNCTION IF EXISTS pp.update_timestamp CASCADE;
DROP FUNCTION IF EXISTS pp.record_audit CASCADE;

DROP TABLE IF EXISTS pp.processor_properties CASCADE;
DROP TABLE IF EXISTS pp.settings CASCADE;
DROP TABLE IF EXISTS pp.payment_processors CASCADE;
DROP TABLE IF EXISTS pp.audit CASCADE;
DROP TABLE IF EXISTS pp.log CASCADE;

DROP SCHEMA IF EXISTS pp CASCADE;
COMMIT;

