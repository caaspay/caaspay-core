BEGIN;

-- Create schema
CREATE SCHEMA IF NOT EXISTS user_mgmt;

-- Set fallback system user ID
DO $$
BEGIN
    -- Set fallback user UUID for the system
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_settings
        WHERE name = 'user_mgmt.fallback_user_id'
    ) THEN
        PERFORM set_config('user_mgmt.fallback_user_id', '00000000-0000-0000-0000-000000000000', false);
    END IF;
END $$;

-- Create audit table
CREATE TABLE IF NOT EXISTS user_mgmt.audit (
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
CREATE TABLE IF NOT EXISTS user_mgmt.log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    log_level VARCHAR(10) NOT NULL, -- INFO, WARN, ERROR
    message TEXT NOT NULL,
    context JSONB,
    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create company table
CREATE TABLE user_mgmt.company (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    website VARCHAR(255),
    telephone VARCHAR(20),
    address TEXT,
    created_by UUID,
    updated_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create user table
CREATE TABLE user_mgmt.user (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES user_mgmt.company(id) ON DELETE CASCADE,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_by UUID,
    updated_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert system user if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM user_mgmt.user
        WHERE id = '00000000-0000-0000-0000-000000000000'
    ) THEN
        INSERT INTO user_mgmt.user (
            id, username, email, password_hash, status, created_at, updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            'system',
            'system@localhost',
            'system', -- Placeholder password, as this user won't log in
            'active',
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        );
    END IF;
END $$;

-- Create group table
CREATE TABLE user_mgmt.group (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES user_mgmt.company(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    created_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create permission table
CREATE TABLE user_mgmt.permission (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES user_mgmt.company(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    created_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create user_group_relation table
CREATE TABLE user_mgmt.user_group_relation (
    user_id UUID REFERENCES user_mgmt.user(id) ON DELETE CASCADE,
    group_id UUID REFERENCES user_mgmt.group(id) ON DELETE CASCADE,
    created_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, group_id)
);

-- Create feature table
CREATE TABLE user_mgmt.feature (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES user_mgmt.company(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    created_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES user_mgmt.user(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create trigger function for updated_at
CREATE OR REPLACE FUNCTION user_mgmt.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at triggers
CREATE TRIGGER update_company_timestamp
    BEFORE UPDATE ON user_mgmt.company
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.update_timestamp();

CREATE TRIGGER update_user_timestamp
    BEFORE UPDATE ON user_mgmt.user
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.update_timestamp();

CREATE TRIGGER update_group_timestamp
    BEFORE UPDATE ON user_mgmt.group
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.update_timestamp();

CREATE TRIGGER update_permission_timestamp
    BEFORE UPDATE ON user_mgmt.permission
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.update_timestamp();

CREATE TRIGGER update_feature_timestamp
    BEFORE UPDATE ON user_mgmt.feature
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.update_timestamp();

-- Create trigger function for audit logging
CREATE OR REPLACE FUNCTION user_mgmt.record_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO user_mgmt.audit (resource_type, resource_id, operation, new_value, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(NEW), current_setting('app.user_id')::UUID);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO user_mgmt.audit (resource_type, resource_id, operation, old_value, new_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), current_setting('app.user_id')::UUID);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO user_mgmt.audit (resource_type, resource_id, operation, old_value, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD), current_setting('app.user_id')::UUID);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Add audit triggers
CREATE TRIGGER audit_company
    AFTER INSERT OR UPDATE OR DELETE ON user_mgmt.company
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.record_audit();

CREATE TRIGGER audit_user
    AFTER INSERT OR UPDATE OR DELETE ON user_mgmt.user
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.record_audit();

CREATE TRIGGER audit_group
    AFTER INSERT OR UPDATE OR DELETE ON user_mgmt.group
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.record_audit();

CREATE TRIGGER audit_permission
    AFTER INSERT OR UPDATE OR DELETE ON user_mgmt.permission
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.record_audit();

CREATE TRIGGER audit_feature
    AFTER INSERT OR UPDATE OR DELETE ON user_mgmt.feature
    FOR EACH ROW EXECUTE FUNCTION user_mgmt.record_audit();

COMMIT;

