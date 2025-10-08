-- migrate:up

CREATE OR REPLACE FUNCTION dbo.fn_gen_name_path(
    _parent_class_id VARCHAR(21),
    _chinese_name VARCHAR(255)
)
    RETURNS TEXT
AS
$$
DECLARE
    result TEXT;
BEGIN
    IF _parent_class_id IS NULL THEN
        RETURN _chinese_name;
    END IF;

    SELECT CASE
               WHEN c.name_path = '/' THEN '/' || _chinese_name
               ELSE c.name_path || '/' || _chinese_name
               END
    INTO result
    FROM dbo.classes c
    WHERE c.id = _parent_class_id;

    RETURN result;
END;
$$
    LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dbo.fn_gen_id_path(_parent_class_id VARCHAR(21), _class_id VARCHAR(21) DEFAULT NULL)
    RETURNS TEXT
AS
$$
DECLARE
    result TEXT;
BEGIN
    IF _parent_class_id IS NULL THEN
        RETURN _class_id;
    END IF;

    SELECT c.id_path || '/' || fn_gen_id_path._class_id
    INTO result
    FROM dbo.classes c
    WHERE c.id = _parent_class_id;

    RETURN result;
END;
$$
    LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dbo.fn_insert_class(
    _parent_class_id VARCHAR(21),
    _entity_id INT,
    _chinese_name VARCHAR(256),
    _chinese_description VARCHAR(4000),
    _english_name VARCHAR(256),
    _english_description VARCHAR(4000),
    _owner_id uuid DEFAULT NULL)
    RETURNS SETOF dbo.classes
AS
$$
DECLARE
    new_class_id        VARCHAR(21) := nanoid();
    new_name_path       TEXT        := dbo.fn_gen_name_path(_parent_class_id, fn_insert_class._chinese_name);
    new_id_path         TEXT        := dbo.fn_gen_id_path(_parent_class_id, new_class_id);
    new_hierarchy_level INT;
BEGIN
    -- 檢查NamePath是否重複
    IF EXISTS(SELECT 1
              FROM dbo.classes
              WHERE name_path = new_name_path) THEN
        RAISE EXCEPTION 'Error: name_path 已經存在，無法建立 class。NamePath: %', new_name_path USING ERRCODE = '22000';
    END IF;

    IF _parent_class_id IS NULL THEN
        new_hierarchy_level := 0;
    ELSE
        SELECT hierarchy_level + 1
        INTO new_hierarchy_level
        FROM dbo.classes
        WHERE id = _parent_class_id;

        IF NOT found THEN
            RAISE EXCEPTION 'Error: parent_class_id % 不存在，無法建立 class。', _parent_class_id USING ERRCODE = '22000';
        END IF;
    END IF;

    RETURN QUERY INSERT INTO dbo.classes (id, entity_id, chinese_name, chinese_description, english_name,
                                          english_description,
                                          owner_id,
                                          id_path,
                                          name_path,
                                          hierarchy_level)
        VALUES (new_class_id,
                _entity_id,
                _chinese_name,
                _chinese_description,
                _english_name,
                _english_description,
                _owner_id,
                new_id_path,
                new_name_path,
                new_hierarchy_level)
        RETURNING *;

    -- Inherit permissions from parent class
    INSERT INTO dbo.permissions
    SELECT new_class_id, role_type, role_id, permission_bits
    FROM dbo.permissions
    WHERE class_id = _parent_class_id;

    RETURN;
END;
$$
    LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dbo.fn_insert_entity(
    _chinese_name CHARACTER VARYING DEFAULT NULL::CHARACTER VARYING,
    _english_name CHARACTER VARYING DEFAULT NULL::CHARACTER VARYING,
    _is_relational BOOLEAN DEFAULT NULL::BOOLEAN,
    _custom_id INTEGER DEFAULT NULL::INTEGER) RETURNS INT
    LANGUAGE plpgsql
AS
$$
DECLARE
    entity_id INT;
BEGIN
    -- 檢查參數是否為空
    IF (_chinese_name IS NULL OR _english_name IS NULL OR _is_relational IS NULL) THEN
        RAISE EXCEPTION 'Error: 所有參數 (chinese_name, english_name, is_relational) 都必須提供' USING ERRCODE = '22000';
    END IF;

    -- 檢查 chinese_name 或 english_name 是否已存在
    IF EXISTS(SELECT 1
              FROM dbo.entities
              WHERE dbo.entities.chinese_name = _chinese_name
                 OR dbo.entities.english_name = _english_name) THEN
        RAISE EXCEPTION 'Error: chinese_name 或 english_name 已經存在，無法建立 entity' USING ERRCODE = '22000';
    END IF;

    -- 如果有提供 custom_id 則使用它來覆蓋系統默認值
    IF _custom_id IS NOT NULL THEN
        INSERT INTO dbo.entities(id,
                                 chinese_name,
                                 english_name,
                                 is_relational)
            OVERRIDING SYSTEM VALUE
        VALUES (_custom_id,
                _chinese_name,
                _english_name,
                _is_relational)
        RETURNING id INTO entity_id;
    ELSE
        INSERT INTO dbo.entities(chinese_name,
                                 english_name,
                                 is_relational)
        VALUES (_chinese_name,
                _english_name,
                _is_relational)
        RETURNING id INTO entity_id;
    END IF;

    -- 返回新插入的 entity_id
    RETURN entity_id;
END;
$$;

CREATE OR REPLACE FUNCTION dbo.fn_delete_class(
    class_id VARCHAR(21)
) RETURNS SETOF dbo.classes
    LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
    RETURN QUERY DELETE FROM dbo.classes WHERE id = class_id RETURNING *;
    IF NOT found THEN
        RAISE EXCEPTION 'Error: class_id % 不存在，無法刪除class。', id USING ERRCODE = '22000';
    END IF;
END;
$$;

-- migrate:down
