BEGIN;

-- Create schema
CREATE SCHEMA IF NOT EXISTS pp;

-- Create audit table
CREATE TABLE IF NOT EXISTS pp.audit (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    resource_type VARCHAR(255) NOT NULL,
    resource_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    old_value JSONB,
    new_value JSONB,
    changed_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create log table
CREATE TABLE IF NOT EXISTS pp.log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    log_level VARCHAR(10) NOT NULL, -- INFO, WARN, ERROR
    message TEXT NOT NULL,
    context JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create payment processor-related tables
CREATE TABLE pp.payment_processors (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    api_url VARCHAR(255) NOT NULL,
    credentials JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pp.processor_properties (
    id UUID PRIMARY KEY,
    processor_id UUID REFERENCES pp.payment_processors(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    UNIQUE (processor_id, key)
);

CREATE TABLE pp.settings (
    id UUID PRIMARY KEY,
    processor_id UUID REFERENCES pp.payment_processors(id) ON DELETE CASCADE,
    config JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create trigger function for updated_at
CREATE OR REPLACE FUNCTION pp.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at triggers
CREATE TRIGGER update_processors_timestamp
    BEFORE UPDATE ON pp.payment_processors
    FOR EACH ROW EXECUTE FUNCTION pp.update_timestamp();

CREATE TRIGGER update_settings_timestamp
    BEFORE UPDATE ON pp.settings
    FOR EACH ROW EXECUTE FUNCTION pp.update_timestamp();

-- Create trigger function for audit logging
CREATE OR REPLACE FUNCTION pp.record_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO pp.audit (resource_type, resource_id, operation, new_value, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(NEW), current_setting('app.user_id')::UUID);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO pp.audit (resource_type, resource_id, operation, old_value, new_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), current_setting('app.user_id')::UUID);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO pp.audit (resource_type, resource_id, operation, old_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), current_setting('app.user_id')::UUID);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Add audit triggers
CREATE TRIGGER audit_processors
    AFTER INSERT OR UPDATE OR DELETE ON pp.payment_processors
    FOR EACH ROW EXECUTE FUNCTION pp.record_audit();

CREATE TRIGGER audit_settings
    AFTER INSERT OR UPDATE OR DELETE ON pp.settings
    FOR EACH ROW EXECUTE FUNCTION pp.record_audit();

COMMIT;

