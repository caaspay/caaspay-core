-- CRUD Function: Create or Update Company
CREATE OR REPLACE FUNCTION user_mgmt.create_or_update_company(
    p_id UUID DEFAULT NULL, -- Existing ID for update, NULL for create
    p_name VARCHAR DEFAULT NULL,
    p_website VARCHAR DEFAULT NULL,
    p_telephone VARCHAR DEFAULT NULL,
    p_address TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    fallback_user_id UUID := COALESCE(
        current_setting('user_mgmt.fallback_user_id', true)::UUID,
        '00000000-0000-0000-0000-000000000000' -- Hardcoded fallback
    );
BEGIN
    -- Set the current user context or fallback to system
    PERFORM set_config('app.user_id', COALESCE(p_user_id, fallback_user_id)::TEXT, false);

    -- Check if this is an update or create operation
    IF p_id IS NOT NULL THEN
        -- Validate that the ID exists
        IF NOT EXISTS (SELECT 1 FROM user_mgmt.company WHERE id = p_id) THEN
            RAISE EXCEPTION 'Company with ID % does not exist', p_id;
        END IF;

        -- Perform update
        UPDATE user_mgmt.company
        SET name = p_name,
            website = p_website,
            telephone = p_telephone,
            address = p_address,
            updated_by = COALESCE(p_user_id, fallback_user_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_id;

    ELSE
        -- Perform create
        p_id := gen_random_uuid();
        INSERT INTO user_mgmt.company (id, name, website, telephone, address, created_by)
        VALUES (p_id, p_name, p_website, p_telephone, p_address, COALESCE(p_user_id, fallback_user_id));
    END IF;

    -- Reset the user context
    PERFORM set_config('app.user_id', NULL, false);

    RETURN p_id;
END;
$$ LANGUAGE plpgsql;

-- CRUD Function: Create or Update User
CREATE OR REPLACE FUNCTION user_mgmt.create_or_update_user(
    p_id UUID DEFAULT NULL, -- Existing ID for update, NULL for create
    p_company_id UUID DEFAULT NULL,
    p_username VARCHAR DEFAULT NULL,
    p_email VARCHAR DEFAULT NULL,
    p_password_hash TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    fallback_user_id UUID := COALESCE(
        current_setting('user_mgmt.fallback_user_id', true)::UUID,
        '00000000-0000-0000-0000-000000000000' -- Hardcoded fallback
    );
BEGIN
    -- Set the current user context or fallback to system
    PERFORM set_config('app.user_id', COALESCE(p_user_id, fallback_user_id)::TEXT, false);

    -- Check if this is an update or create operation
    IF p_id IS NOT NULL THEN
        -- Validate that the ID exists
        IF NOT EXISTS (SELECT 1 FROM user_mgmt.user WHERE id = p_id) THEN
            RAISE EXCEPTION 'User with ID % does not exist', p_id;
        END IF;

        -- Perform update
        UPDATE user_mgmt.user
        SET company_id = p_company_id,
            username = p_username,
            email = p_email,
            password_hash = p_password_hash,
            updated_by = COALESCE(p_user_id, fallback_user_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_id;

    ELSE
        -- Perform create
        p_id := gen_random_uuid();
        INSERT INTO user_mgmt.user (id, company_id, username, email, password_hash, created_at, updated_at)
        VALUES (p_id, p_company_id, p_username, p_email, p_password_hash, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
    END IF;

    -- Reset the user context
    PERFORM set_config('app.user_id', NULL, false);

    RETURN p_id;
END;
$$ LANGUAGE plpgsql;

-- CRUD Function: Create or Update Group
CREATE OR REPLACE FUNCTION user_mgmt.create_or_update_group(
    p_id UUID DEFAULT NULL, -- Existing ID for update, NULL for create
    p_company_id UUID DEFAULT NULL,
    p_name VARCHAR DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    fallback_user_id UUID := COALESCE(
        current_setting('user_mgmt.fallback_user_id', true)::UUID,
        '00000000-0000-0000-0000-000000000000' -- Hardcoded fallback
    );
BEGIN
    -- Set the current user context or fallback to system
    PERFORM set_config('app.user_id', COALESCE(p_user_id, fallback_user_id)::TEXT, false);

    -- Check if this is an update or create operation
    IF p_id IS NOT NULL THEN
        -- Validate that the ID exists
        IF NOT EXISTS (SELECT 1 FROM user_mgmt.group WHERE id = p_id) THEN
            RAISE EXCEPTION 'Group with ID % does not exist', p_id;
        END IF;

        -- Perform update
        UPDATE user_mgmt.group
        SET company_id = p_company_id,
            name = p_name,
            description = p_description,
            updated_by = COALESCE(p_user_id, fallback_user_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_id;

    ELSE
        -- Perform create
        p_id := gen_random_uuid();
        INSERT INTO user_mgmt.group (id, company_id, name, description, created_by, created_at, updated_at)
        VALUES (p_id, p_company_id, p_name, p_description, COALESCE(p_user_id, fallback_user_id), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
    END IF;

    -- Reset the user context
    PERFORM set_config('app.user_id', NULL, false);

    RETURN p_id;
END;
$$ LANGUAGE plpgsql;

-- CRUD Function: Create or Update Permission
CREATE OR REPLACE FUNCTION user_mgmt.create_or_update_permission(
    p_id UUID DEFAULT NULL, -- Existing ID for update, NULL for create
    p_company_id UUID DEFAULT NULL,
    p_name VARCHAR DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    fallback_user_id UUID := COALESCE(
        current_setting('user_mgmt.fallback_user_id', true)::UUID,
        '00000000-0000-0000-0000-000000000000' -- Hardcoded fallback
    );
BEGIN
    -- Set the current user context or fallback to system
    PERFORM set_config('app.user_id', COALESCE(p_user_id, fallback_user_id)::TEXT, false);

    -- Check if this is an update or create operation
    IF p_id IS NOT NULL THEN
        -- Validate that the ID exists
        IF NOT EXISTS (SELECT 1 FROM user_mgmt.permission WHERE id = p_id) THEN
            RAISE EXCEPTION 'Permission with ID % does not exist', p_id;
        END IF;

        -- Perform update
        UPDATE user_mgmt.permission
        SET company_id = p_company_id,
            name = p_name,
            description = p_description,
            updated_by = COALESCE(p_user_id, fallback_user_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_id;

    ELSE
        -- Perform create
        p_id := gen_random_uuid();
        INSERT INTO user_mgmt.permission (id, company_id, name, description, created_by, created_at, updated_at)
        VALUES (p_id, p_company_id, p_name, p_description, COALESCE(p_user_id, fallback_user_id), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
    END IF;

    -- Reset the user context
    PERFORM set_config('app.user_id', NULL, false);

    RETURN p_id;
END;
$$ LANGUAGE plpgsql;

