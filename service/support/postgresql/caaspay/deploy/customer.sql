BEGIN;

-- Create schema
CREATE SCHEMA IF NOT EXISTS customer;

-- Create audit table
CREATE TABLE IF NOT EXISTS customer.audit (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    resource_type VARCHAR(255) NOT NULL,
    resource_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_value JSONB,
    new_value JSONB,
    changed_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create log table
CREATE TABLE IF NOT EXISTS customer.log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    log_level VARCHAR(10) NOT NULL CHECK (log_level IN ('INFO', 'WARN', 'ERROR')),
    message TEXT NOT NULL,
    context JSONB,
    user_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create customer-related tables
CREATE TABLE customer.client_details (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(15),
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer.payment_methods (
    id UUID PRIMARY KEY,
    client_id UUID REFERENCES customer.client_details(id) ON DELETE CASCADE,
    method_type VARCHAR(50) NOT NULL CHECK (method_type IN ('card', 'bank_transfer', 'wallet', 'crypto')),
    details JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer.customer_properties (
    id UUID PRIMARY KEY,
    client_id UUID REFERENCES customer.client_details(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    UNIQUE (client_id, key)
);

CREATE TABLE customer.history (
    id UUID PRIMARY KEY,
    client_id UUID REFERENCES customer.client_details(id) ON DELETE CASCADE,
    event VARCHAR(255) NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (created_at);

CREATE TABLE customer.stats (
    id UUID PRIMARY KEY,
    client_id UUID REFERENCES customer.client_details(id) ON DELETE CASCADE,
    total_transactions BIGINT DEFAULT 0,
    total_spent DECIMAL(10, 2) DEFAULT 0.00,
    last_transaction TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_stats_client_id ON customer.stats(client_id);

-- Create trigger function for updated_at
CREATE OR REPLACE FUNCTION customer.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at triggers
CREATE TRIGGER update_client_details_timestamp
    BEFORE UPDATE ON customer.client_details
    FOR EACH ROW EXECUTE FUNCTION customer.update_timestamp();

CREATE TRIGGER update_payment_methods_timestamp
    BEFORE UPDATE ON customer.payment_methods
    FOR EACH ROW EXECUTE FUNCTION customer.update_timestamp();

CREATE TRIGGER update_stats_timestamp
    BEFORE UPDATE ON customer.stats
    FOR EACH ROW EXECUTE FUNCTION customer.update_timestamp();

-- Create trigger function for audit logging
CREATE OR REPLACE FUNCTION customer.record_audit()
RETURNS TRIGGER AS $$
BEGIN
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            INSERT INTO customer.audit (resource_type, resource_id, operation, new_value, changed_by, transaction_id)
            VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(NEW), current_setting('app.user_id')::UUID, txid_current()::UUID);
        ELSIF (TG_OP = 'UPDATE') THEN
            INSERT INTO customer.audit (resource_type, resource_id, operation, old_value, new_value, changed_by, transaction_id)
            VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), current_setting('app.user_id')::UUID, txid_current()::UUID);
        ELSIF (TG_OP = 'DELETE') THEN
            INSERT INTO customer.audit (resource_type, resource_id, operation, old_value, changed_by, transaction_id)
            VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), current_setting('app.user_id')::UUID, txid_current()::UUID);
        END IF;
        RETURN NEW;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Audit logging failed: %', SQLERRM;
        RETURN NEW;
    END;
END;
$$ LANGUAGE plpgsql;

-- Add audit triggers
CREATE TRIGGER audit_client_details
    AFTER INSERT OR UPDATE OR DELETE ON customer.client_details
    FOR EACH ROW EXECUTE FUNCTION customer.record_audit();

CREATE TRIGGER audit_payment_methods
    AFTER INSERT OR UPDATE OR DELETE ON customer.payment_methods
    FOR EACH ROW EXECUTE FUNCTION customer.record_audit();

CREATE TRIGGER audit_stats
    AFTER INSERT OR UPDATE OR DELETE ON customer.stats
    FOR EACH ROW EXECUTE FUNCTION customer.record_audit();

COMMIT;