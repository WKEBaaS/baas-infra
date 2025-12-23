-- migrate:up

CREATE OR REPLACE FUNCTION dbo.fn_gen_name_path(
    p_parent_class_id TEXT,
    p_chinese_name TEXT
)
    RETURNS TEXT
AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    result TEXT;
BEGIN
    IF p_parent_class_id IS NULL THEN
        RETURN p_chinese_name;
    END IF;

    SELECT CASE
               WHEN c.name_path = '/' THEN '/' || p_chinese_name
               ELSE c.name_path || '/' || p_chinese_name
               END
    INTO result
    FROM dbo.classes c
    WHERE c.id = p_parent_class_id;

    RETURN result;
END;
$$
    LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dbo.fn_gen_id_path(p_parent_class_id VARCHAR(21), p_class_id VARCHAR(21) DEFAULT NULL)
    RETURNS TEXT
AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    result TEXT;
BEGIN
    IF p_parent_class_id IS NULL THEN
        RETURN p_class_id;
    END IF;

    -- We must still qualify 'class_id' with the function name
    -- to resolve the ambiguity with the 'c.class_id' column,
    -- overriding the 'USE_COLUMN' directive for this specific variable.
    SELECT c.id_path || '/' || p_class_id
    INTO result
    FROM dbo.classes c
    WHERE c.id = p_parent_class_id; -- 'c.id' is column, 'parent_class_id' is param

    RETURN result;
END;
$$
    LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dbo.fn_insert_class(
    p_parent_class_id VARCHAR(21),
    p_entity_id INT,
    p_chinese_name VARCHAR(256),
    p_chinese_description VARCHAR(4000),
    p_english_name VARCHAR(256),
    p_english_description VARCHAR(4000),
    p_owner_id uuid DEFAULT NULL)
    RETURNS SETOF dbo.classes
AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    v_parent_name_path    TEXT;
    v_new_class_id        VARCHAR(21) := nanoid();
    v_new_name_path       TEXT        := dbo.fn_gen_name_path(p_parent_class_id, p_chinese_name);
    v_new_id_path         TEXT        := dbo.fn_gen_id_path(p_parent_class_id, v_new_class_id);
    v_new_hierarchy_level INT;
    v_inserted_class      dbo.classes%ROWTYPE; -- Variable to hold the successfully inserted row
BEGIN
    RAISE NOTICE 'New Name Path: %, New ID Path: %', v_new_name_path, v_new_id_path;
    -- Determine hierarchy level and check for parent existence
    IF p_parent_class_id IS NULL THEN
        v_new_hierarchy_level := 0;
    ELSE
        -- In this query, 'id' and 'hierarchy_level' are resolved as columns
        -- due to the USE_COLUMN directive and query context.
        SELECT name_path, hierarchy_level + 1
        INTO v_parent_name_path, v_new_hierarchy_level
        FROM dbo.classes
        WHERE id = p_parent_class_id; -- 'parent_class_id' is unambiguously a parameter

        IF NOT found THEN
            RAISE EXCEPTION 'Error: parent_class_id % 不存在，無法建立 class。', p_parent_class_id USING ERRCODE = '22000';
        END IF;
    END IF;

    -- Insert the new class, handling potential name_path conflicts
    INSERT INTO dbo.classes (id, entity_id, chinese_name, chinese_description, english_name,
                             english_description,
                             owner_id,
                             id_path,
                             name_path,
                             hierarchy_level)
    VALUES (v_new_class_id,
            p_entity_id,
            p_chinese_name,
            p_chinese_description,
            p_english_name,
            p_english_description,
            p_owner_id,
            v_new_id_path,
            v_new_name_path,
            v_new_hierarchy_level)
    RETURNING * INTO v_inserted_class;

    -- Only proceed if the insert was successful
    RAISE NOTICE 'class_inserted: %', v_inserted_class;
    IF v_inserted_class.id IS NOT NULL THEN
        INSERT INTO dbo.inheritances(pcid, ccid) VALUES (p_parent_class_id, v_inserted_class.id);

        -- Inherit permissions from parent class
        INSERT INTO dbo.permissions
        SELECT v_inserted_class.id, role_type, role_id, permission_bits
        FROM dbo.permissions
        WHERE class_id = p_parent_class_id;
        -- 'class_id' is column, 'parent_class_id' is param

        -- Return the newly inserted class
        RETURN NEXT v_inserted_class;
    END IF;

    RETURN;
EXCEPTION
    WHEN UNIQUE_VIOLATION THEN
        RAISE SQLSTATE 'PT409' USING
            MESSAGE = FORMAT('Class %s is already exist in %s', p_chinese_name, COALESCE(v_parent_name_path, '/')),
            HINT = 'Choose a different chinese_name.';
END;
$$
    LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dbo.fn_insert_entity(
    p_chinese_name TEXT DEFAULT NULL,
    p_english_name TEXT DEFAULT NULL,
    p_is_relational BOOLEAN DEFAULT NULL::BOOLEAN,
    p_custom_id INTEGER DEFAULT NULL::INTEGER) RETURNS INT
    LANGUAGE plpgsql
AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    entity_id INT;
BEGIN
    -- 檢查參數是否為空
    IF (p_chinese_name IS NULL OR p_english_name IS NULL OR p_is_relational IS NULL) THEN
        RAISE EXCEPTION 'Error: 所有參數 (chinese_name, english_name, is_relational) 都必須提供' USING ERRCODE = '22000';
    END IF;

    -- 檢查 chinese_name 或 english_name 是否已存在
    -- We must qualify the parameters to distinguish from columns
    IF EXISTS(SELECT 1
              FROM dbo.entities
              WHERE chinese_name = p_chinese_name
                 OR english_name = p_english_name) THEN
        RAISE EXCEPTION 'Error: chinese_name 或 english_name 已經存在，無法建立 entity' USING ERRCODE = '22000';
    END IF;

    -- 如果有提供 custom_id 則使用它來覆蓋系統默認值
    IF p_custom_id IS NOT NULL THEN
        INSERT INTO dbo.entities(id,
                                 chinese_name,
                                 english_name,
                                 is_relational)
            OVERRIDING SYSTEM VALUE
        VALUES (p_custom_id,
                p_chinese_name,
                p_english_name,
                p_is_relational)
        RETURNING id INTO entity_id;
    ELSE
        INSERT INTO dbo.entities(chinese_name,
                                 english_name,
                                 is_relational)
        VALUES (p_chinese_name,
                p_english_name,
                p_is_relational)
        RETURNING id INTO entity_id;
    END IF;

    -- 返回新插入的 entity_id
    RETURN entity_id;
END;
$$;

CREATE OR REPLACE FUNCTION dbo.fn_delete_class(
    p_class_id VARCHAR(21),
    p_recursive BOOLEAN DEFAULT FALSE
) RETURNS SETOF dbo.classes
    LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
    IF NOT p_recursive THEN
        RETURN QUERY DELETE FROM dbo.classes WHERE id = p_class_id RETURNING *;
        IF NOT found THEN
            RAISE EXCEPTION 'Error: class_id % 不存在，無法刪除class。', id USING ERRCODE = '22000';
        END IF;
        RETURN;
    END IF;

    -- Delete class and all its descendant classes recursively
    RETURN QUERY
        WITH RECURSIVE class_tree AS (SELECT p_class_id AS id
                                      UNION
                                      SELECT i.ccid
                                      FROM dbo.inheritances i,
                                           class_tree ct
                                      WHERE i.pcid = ct.id)
            DELETE FROM dbo.classes c
                USING class_tree ct
                WHERE c.id = ct.id
                RETURNING c.*;
END
$$;

COMMENT ON FUNCTION dbo.fn_delete_class IS $$Delete Class and referenced records in cascade.
- Permissions
- Inheritances
- CO records
$$;

-- migrate:down
