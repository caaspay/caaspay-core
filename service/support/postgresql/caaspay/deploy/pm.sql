BEGIN;

-- Create schema
CREATE SCHEMA IF NOT EXISTS pm;

-- Create audit table
CREATE TABLE pm.audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type VARCHAR(255) NOT NULL,
    resource_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_value JSONB,
    new_value JSONB,
    changed_by UUID DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create log table
CREATE TABLE IF NOT EXISTS pm.log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    log_level VARCHAR(10) NOT NULL, -- INFO, WARN, ERROR
    message TEXT NOT NULL,
    context JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create payment method-related tables
CREATE TABLE pm.payment_method (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('API', 'MANUAL', 'TOKENIZED')),
    api_url VARCHAR(255),
    credentials JSONB NOT NULL,
    encryption_key_id UUID,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_method_status ON pm.payment_method(status);

CREATE TABLE pm.method_properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    method_id UUID REFERENCES pm.payment_method(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    value JSONB NOT NULL, -- Allows structured data
    description TEXT,
    UNIQUE (method_id, key)
);

CREATE INDEX idx_method_properties_method_id ON pm.method_properties(method_id);

CREATE TABLE pm.settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    method_id UUID REFERENCES pm.payment_method(id) ON DELETE CASCADE,
    config JSONB NOT NULL,
    encryption_key_id UUID, -- If settings need to be encrypted externally
    valid_until TIMESTAMP, -- Optional, expiration date
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_settings_method_id ON pm.settings(method_id);
CREATE INDEX idx_settings_valid_until ON pm.settings(valid_until);

CREATE TABLE pm.payment_event_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(100) NOT NULL CHECK (event_type IN ('PAYMENT_INITIATED', 'PAYMENT_SUCCESS', 'PAYMENT_FAILED', 'REFUND_INITIATED', 'REFUND_SUCCESS', 'REFUND_FAILED')),
    payment_method_id UUID REFERENCES pm.payment_method(id) ON DELETE SET NULL,
    reference_id UUID NOT NULL, -- Links to an external transaction
    payload JSONB NOT NULL, -- Full event details
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_event_log_type ON pm.payment_event_log(event_type);
CREATE INDEX idx_payment_event_log_status ON pm.payment_event_log(status);

-- Create trigger function for updated_at
CREATE OR REPLACE FUNCTION pm.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at triggers
CREATE TRIGGER update_method_timestamp
    BEFORE UPDATE ON pm.payment_method
    FOR EACH ROW EXECUTE FUNCTION pm.update_timestamp();

CREATE TRIGGER update_settings_timestamp
    BEFORE UPDATE ON pm.settings
    FOR EACH ROW EXECUTE FUNCTION pm.update_timestamp();

-- Create trigger function for audit logging
CREATE OR REPLACE FUNCTION pm.record_audit()
RETURNS TRIGGER AS $$
DECLARE
    user_id UUID;
BEGIN
    BEGIN
        user_id := current_setting('apm.user_id')::UUID;
    EXCEPTION WHEN others THEN
        user_id := NULL;
    END;

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO pm.audit (resource_type, resource_id, operation, new_value, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(NEW), user_id);
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO pm.audit (resource_type, resource_id, operation, old_value, new_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), user_id);
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO pm.audit (resource_type, resource_id, operation, old_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), user_id);
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Add audit triggers
CREATE TRIGGER audit_method
    AFTER INSERT OR UPDATE OR DELETE ON pm.payment_method
    FOR EACH ROW EXECUTE FUNCTION pm.record_audit();

CREATE TRIGGER audit_settings
    AFTER INSERT OR UPDATE OR DELETE ON pm.settings
    FOR EACH ROW EXECUTE FUNCTION pm.record_audit();

COMMIT;

