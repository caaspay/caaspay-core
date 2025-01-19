BEGIN;

-- Create schema
CREATE SCHEMA IF NOT EXISTS transaction;

-- Create audit table
CREATE TABLE IF NOT EXISTS transaction.audit (
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
CREATE TABLE IF NOT EXISTS transaction.log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    log_level VARCHAR(10) NOT NULL, -- INFO, WARN, ERROR
    message TEXT NOT NULL,
    context JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create transaction-related tables
CREATE TABLE transaction.transactions (
    id UUID PRIMARY KEY,
    client_id UUID REFERENCES customer.client_details(id) ON DELETE CASCADE,
    processor_id UUID REFERENCES pp.payment_processors(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    currency CHAR(3) NOT NULL, -- ISO 4217 (e.g., USD)
    type VARCHAR(50) NOT NULL, -- ewallet, credit_card, crypto
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, completed, failed
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create trigger function for updated_at
CREATE OR REPLACE FUNCTION transaction.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at triggers
CREATE TRIGGER update_transactions_timestamp
    BEFORE UPDATE ON transaction.transactions
    FOR EACH ROW EXECUTE FUNCTION transaction.update_timestamp();

-- Create trigger function for audit logging
CREATE OR REPLACE FUNCTION transaction.record_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO transaction.audit (resource_type, resource_id, operation, new_value, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(NEW), current_setting('app.user_id')::UUID);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO transaction.audit (resource_type, resource_id, operation, old_value, new_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), current_setting('app.user_id')::UUID);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO transaction.audit (resource_type, resource_id, operation, old_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), current_setting('app.user_id')::UUID);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Add audit triggers
CREATE TRIGGER audit_transactions
    AFTER INSERT OR UPDATE OR DELETE ON transaction.transactions
    FOR EACH ROW EXECUTE FUNCTION transaction.record_audit();

COMMIT;

