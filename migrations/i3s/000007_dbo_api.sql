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

/**
 * 核心權限檢查邏輯 (內部使用)
 * 假設所有 ID 和 bit 都已查證且有效。
 */
CREATE OR REPLACE FUNCTION api.check_permission_core(
    p_class_id TEXT,
    p_owner_id uuid,
    p_user_id uuid, -- 可為 NULL (匿名使用者)
    p_permission_bit SMALLINT
) RETURNS BOOLEAN AS
$$
BEGIN
    -- 1. 立即檢查超級管理員
    IF CURRENT_USER = 'app_admin' THEN
        RETURN TRUE;
    END IF;

    -- 2. 檢查是否為擁有者
    IF p_user_id IS NOT NULL AND p_owner_id = p_user_id THEN
        RETURN TRUE;
    END IF;

    -- 3. 【核心邏輯】
    -- 檢查 'anon'、'user'、'group' 權限
    RETURN EXISTS (
        -- 檢查 'anon' (公開) 權限
        SELECT 1
        FROM dbo.permissions p
                 JOIN auth.groups g ON p.role_id = g.id AND p.role_type = 'GROUP'
        WHERE p.class_id = p_class_id
          AND g.name = 'anon'
          AND g.is_enabled
          AND (p.permission_bits & p_permission_bit) > 0

        UNION ALL

        -- 檢查使用者特定權限 (僅當 v_user_id 存在時)
        SELECT 1
        FROM dbo.permissions p
        WHERE p_user_id IS NOT NULL
          AND p.class_id = p_class_id
          AND p.role_type = 'USER'
          AND p.role_id = p_user_id
          AND (p.permission_bits & p_permission_bit) > 0

        UNION ALL

        -- 檢查使用者的群組權限 (僅當 v_user_id 存在時)
        SELECT 1
        FROM dbo.permissions p
                 JOIN auth.user_groups ur ON ur.user_id = p_user_id
                 JOIN auth.groups g ON g.id = ur.group_id AND p.role_id = g.id
        WHERE p_user_id IS NOT NULL
          AND p.class_id = p_class_id
          AND p.role_type = 'GROUP'
          AND g.is_enabled
          AND (p.permission_bits & p_permission_bit) > 0);
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION api.check_permission_core IS $$核心權限檢查邏輯 (內部使用)
假設所有 ID 和 bit 都已查證且有效。
$$;

CREATE OR REPLACE FUNCTION api.check_class_permission(
    p_class_id TEXT,
    p_permission TEXT
) RETURNS BOOLEAN AS
$$
DECLARE
    v_user_id        uuid;
    v_owner_id       uuid;
    v_permission_bit SMALLINT;
BEGIN
    v_user_id := auth.jwt() ->> 'sub';

    -- 1. 獲取權限對應的 bit
    SELECT bit
    INTO v_permission_bit
    FROM dbo.permission_enum
    WHERE name = p_permission;

    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Permission %s not found', p_permission),
            HINT = 'Check if the permission exists in dbo.permission_enum.';
    END IF;

    -- 2. 獲取 owner_id
    SELECT owner_id
    INTO v_owner_id
    FROM dbo.classes
    WHERE id = p_class_id;

    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Class with id %s not found', p_class_id),
            HINT = 'Check if the class exists in dbo.classes.';
    END IF;

    -- 3. 呼叫核心邏輯
    RETURN api.check_permission_core(
            p_class_id,
            v_owner_id,
            v_user_id,
            v_permission_bit
           );
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION api.check_class_permission_by_name_path(
    p_name_path TEXT,
    p_permission TEXT
)
    RETURNS TABLE
            (
                class_id VARCHAR(21),
                has      BOOLEAN
            )
AS
$$
DECLARE
    v_user_id        uuid;
    v_class_id       VARCHAR(21);
    v_owner_id       uuid;
    v_permission_bit SMALLINT;
    v_has_permission BOOLEAN;
BEGIN
    v_user_id := auth.jwt() ->> 'sub';

    -- 1. 獲取權限對應的 bit
    SELECT bit
    INTO v_permission_bit
    FROM dbo.permission_enum
    WHERE name = p_permission;

    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Permission %s not found', p_permission),
            HINT = 'Check if the permission exists in dbo.permission_enum.';
    END IF;

    -- 2. 【優化】一次查詢同時獲取 class_id 和 owner_id
    SELECT id, owner_id
    INTO v_class_id, v_owner_id
    FROM dbo.classes
    WHERE name_path = TRIM(TRAILING '/' FROM p_name_path);

    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Class with name_path %s not found', p_name_path),
            HINT = 'Check if the class exists in dbo.classes.';
    END IF;

    -- 3. 呼叫核心邏輯
    v_has_permission := api.check_permission_core(
            v_class_id,
            v_owner_id,
            v_user_id,
            v_permission_bit
                        );

    -- 4. 返回結果
    RETURN QUERY SELECT v_class_id, v_has_permission;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION api.get_class_permissions(
    p_class_id TEXT -- 重新命名以避免與輸出欄位 'class_id' 衝突
)
    RETURNS TABLE
            (
                permission TEXT,
                has        BOOLEAN
            )
AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    v_user_id              uuid;
    v_owner_id             uuid;
    v_is_super_admin       BOOLEAN  := (CURRENT_USER = 'app_admin');
    v_is_owner             BOOLEAN  := FALSE;
    v_user_permission_bits SMALLINT := 0; -- 用於存儲所有權限的 bitwise OR 總和
BEGIN
    -- 1. 獲取使用者 ID
    v_user_id := auth.jwt() ->> 'sub';

    -- 2. 檢查 class 是否存在，並獲取 owner_id
    SELECT owner_id
    INTO v_owner_id
    FROM dbo.classes
    WHERE id = p_class_id;

    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Class with id %s not found', p_class_id),
            HINT = 'Check if the class exists in dbo.classes.';
        -- 注意：在 RETURNS TABLE 函式中，RAISE 會中止執行。
        -- 如果您希望在找不到時返回空列表，請使用 RETURN;
    END IF;

    -- 3. 檢查是否為擁有者
    IF v_user_id IS NOT NULL AND v_owner_id = v_user_id THEN
        v_is_owner := TRUE;
    END IF;

    -- 4. 【優化】如果是超級管理員或擁有者，他們擁有一切權限
    IF v_is_super_admin OR v_is_owner THEN
        RETURN QUERY
            SELECT p_enum.name, -- 權限名稱
                   TRUE         -- 他們擁有所有權限
            FROM dbo.permission_enum p_enum;

        RETURN; -- 退出函式
    END IF;

    -- 5. 【效能優化】計算 'anon', 'user', 'group' 權限的 bitwise OR 總和
    --    使用 COALESCE(BIT_OR(...), 0) 來計算所有適用權限的組合
    SELECT COALESCE(BIT_OR(permission_bits), 0)
    INTO v_user_permission_bits
    FROM (
             -- 檢查 'anon' (公開) 權限
             SELECT p.permission_bits
             FROM dbo.permissions p
                      JOIN auth.groups g ON p.role_id = g.id AND p.role_type = 'GROUP'
             WHERE p.class_id = p_class_id
               AND g.name = 'anon'
               AND g.is_enabled

             UNION

             -- 檢查使用者特定權限 (僅當 v_user_id 存在時)
             SELECT p.permission_bits
             FROM dbo.permissions p
             WHERE v_user_id IS NOT NULL
               AND p.class_id = p_class_id
               AND p.role_type = 'USER'
               AND p.role_id = v_user_id

             UNION

             -- 檢查使用者的群組權限 (僅當 v_user_id 存在時)
             SELECT p.permission_bits
             FROM dbo.permissions p
                      JOIN auth.user_groups ur ON ur.user_id = v_user_id
                      JOIN auth.groups g ON g.id = ur.group_id AND p.role_id = g.id
             WHERE v_user_id IS NOT NULL
               AND p.class_id = p_class_id
               AND p.role_type = 'GROUP'
               AND g.is_enabled) AS combined_permissions;

    -- 6. 返回所有權限的列表，並檢查 bitwise AND
    --    將計算出的權限總和 (v_user_permission_bits)
    --    與 dbo.permission_enum 中每個單獨的 'bit' 進行比較
    RETURN QUERY
        SELECT p_enum.name,                              -- The permission name
               (v_user_permission_bits & p_enum.bit) > 0 -- 檢查 'has' (true/false)
        FROM dbo.permission_enum p_enum;

END;
$$
    LANGUAGE plpgsql STABLE;

CREATE FUNCTION api.get_class_permissions_by_name_path(p_name_path TEXT)
    RETURNS TABLE
            (
                class_id   CHARACTER VARYING,
                permission TEXT,
                has        BOOLEAN
            )
    STABLE
    LANGUAGE plpgsql
AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    v_class_id VARCHAR(21);
BEGIN
    SELECT id
    INTO v_class_id
    FROM dbo.classes
    WHERE name_path = TRIM(TRAILING '/' FROM p_name_path); -- Normalize input by removing trailing slash
    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Class with name_path %s not found', p_name_path),
            HINT = 'Check if the class exists in dbo.classes.';
    END IF;
    RETURN QUERY SELECT v_class_id,
                        permission,
                        has
                 FROM api.get_class_permissions(v_class_id);
END;
$$;

CREATE OR REPLACE FUNCTION api.get_permission_bits(p_class_id VARCHAR(21))
    RETURNS SMALLINT
    STABLE
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_user_id         uuid     := auth.jwt() ->> 'sub';
    v_owner_id        uuid;
    v_permission_bits SMALLINT := 0;
BEGIN
    SELECT owner_id
    INTO v_owner_id
    FROM dbo.classes
    WHERE id = p_class_id;

    IF NOT found THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = FORMAT('Class with id %s not found', p_class_id),
            HINT = 'Check if the class exists in dbo.classes.';
    END IF;

    -- 1. 超級管理員擁有所有權限
    IF CURRENT_USER = 'app_admin' THEN
        RETURN 127; -- 所有 7 個權限位元都設置為 1
    END IF;

    -- 2. 擁有者擁有所有權限
    IF v_user_id IS NOT NULL AND v_owner_id = v_user_id THEN
        RETURN 127; -- 所有 7 個權限位元都設置為 1
    END IF;

    -- 3. 計算 'anon'、'user'、'group' 權限的 bitwise OR 總和
    SELECT COALESCE(BIT_OR(permission_bits), 0)
    INTO v_permission_bits
    FROM (
             -- 檢查 'anon' (公開) 權限
             SELECT p.permission_bits
             FROM dbo.permissions p
                      JOIN auth.groups g ON p.role_id = g.id AND p.role_type = 'GROUP'
             WHERE p.class_id = p_class_id
               AND g.name = 'anon'
               AND g.is_enabled
             UNION
             -- 檢查使用者特定權限 (僅當 v_user_id 存在時)
             SELECT p.permission_bits
             FROM dbo.permissions p
             WHERE v_user_id IS NOT NULL
               AND p.class_id = p_class_id
               AND p.role_type = 'USER'
               AND p.role_id = v_user_id
             UNION
             -- 檢查使用者的群組權限 (僅當 v_user
             SELECT p.permission_bits
             FROM dbo.permissions p
                      JOIN auth.user_groups ur ON ur.user_id = v_user_id
                      JOIN auth.groups g ON g.id = ur.group_id AND p.role_id = g.id
             WHERE v_user_id IS NOT NULL
               AND p.class_id = p_class_id
               AND p.role_type = 'GROUP'
               AND g.is_enabled) AS combined_permissions;
    RETURN v_permission_bits;
END
$$;


-- migrate:down
