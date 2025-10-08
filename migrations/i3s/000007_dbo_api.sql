-- migrate:up

GRANT SELECT ON TABLE dbo.permission_enum TO anon, authenticated, app_admin;
GRANT SELECT ON TABLE dbo.permissions TO anon, authenticated, app_admin;
GRANT SELECT ON TABLE auth.groups TO anon, authenticated, app_admin;
GRANT SELECT ON TABLE auth.user_groups TO authenticated, app_admin;

CREATE OR REPLACE FUNCTION api.get_permission_enum()
    RETURNS SETOF dbo.permission_enum AS
$$
BEGIN
    RETURN QUERY SELECT *
                 FROM dbo.permission_enum;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION api.get_permission_enum() IS $$Get permission enums

Returns a set of permission enums from the dbo.permission_enum table. This function is immutable, meaning it always returns the same result for the same input.
$$;

CREATE OR REPLACE FUNCTION api.check_class_permission(
    class_id TEXT,
    permission TEXT
) RETURNS BOOLEAN AS
$$
DECLARE
    v_user_id        uuid    := auth.jwt() ->> 'sub';
    v_permission_bit SMALLINT;
    v_result         BOOLEAN := FALSE;
BEGIN
    SELECT bit
    INTO v_permission_bit
    FROM dbo.permission_enum
    WHERE name = permission;
    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Permission %s not found', permission),
            HINT = 'Check if the permission exists in dbo.permission_enum.';
    END IF;

    IF CURRENT_USER = 'app_admin' THEN
        RETURN TRUE;
    END IF;

    -- Check Public Permissions
    IF CURRENT_USER = 'anon' THEN
        SELECT TRUE
        INTO v_result
        FROM dbo.permissions p,
             auth.groups g
        WHERE p.class_id = check_class_permission.class_id
          AND p.role_type = FALSE
          AND p.role_id = g.id
          AND (p.permission_bits & v_permission_bit) > 0
          AND g.name = 'anon'
          AND g.is_enabled
        LIMIT 1;
        RETURN v_result;
    END IF;

    -- Ref: https://www.postgresql.org/docs/current/plpgsql-control-structures.html
    -- Check user permission first, if not found, check group permission
    SELECT TRUE
    INTO v_result
    FROM dbo.permissions p
    WHERE p.class_id = check_class_permission.class_id
      AND p.role_type = TRUE
      AND p.role_id = v_user_id
      AND (p.permission_bits & v_permission_bit) > 0
    LIMIT 1;
    IF found THEN
        RETURN v_result;
    END IF;

    SELECT TRUE
    INTO v_result
    FROM dbo.permissions p
             JOIN auth.user_groups ur ON ur.user_id = v_user_id
             JOIN auth.groups g ON g.id = ur.group_id
    WHERE p.class_id = check_class_permission.class_id
      AND p.role_type = FALSE
      AND p.role_id = g.id
      AND g.is_enabled
      AND (p.permission_bits & v_permission_bit) > 0
    LIMIT 1;
    RETURN v_result;
END;
$$
    LANGUAGE plpgsql STABLE;

-- migrate:down
