-- migrate:up

DO
$$
    DECLARE
        web_resource_id         INT;
        user_entity_id          INT;
        root_class_id           VARCHAR(21);
        home_class_id           VARCHAR(21);
        default_home_permission SMALLINT := (SELECT BIT_OR(bit)
                                             FROM dbo.permission_enum
                                             WHERE name IN ('read-class', 'read-object'));
    BEGIN
        IF NOT EXISTS(SELECT 1 FROM dbo.entities) THEN
            SELECT dbo.fn_insert_entity('WEB資源', 'WEB Resource', TRUE, 1) INTO web_resource_id;
            SELECT dbo.fn_insert_entity('使用者', 'User', TRUE, 2) INTO user_entity_id;
            PERFORM dbo.fn_insert_entity('檔案', 'File', TRUE, 3);
            PERFORM dbo.fn_insert_entity('公告', 'Announcement', TRUE, 4);
        END IF;

        IF NOT EXISTS(SELECT 1 FROM dbo.classes) THEN
            SELECT id
            FROM dbo.fn_insert_class(
                    _parent_class_id := NULL,
                    _entity_id := web_resource_id,
                    _chinese_name := '/',
                    _chinese_description := NULL,
                    _english_name := 'Root',
                    _english_description := NULL,
                    _owner_id := NULL
                 )
            INTO root_class_id;

            PERFORM dbo.fn_insert_class(
                    _parent_class_id := root_class_id,
                    _entity_id := user_entity_id,
                    _chinese_name := '使用者',
                    _chinese_description := NULL,
                    _english_name := 'User',
                    _english_description := NULL,
                    _owner_id := NULL
                    );

            SELECT id
            FROM dbo.fn_insert_class(
                    _parent_class_id := root_class_id,
                    _entity_id := web_resource_id,
                    _chinese_name := '首頁',
                    _chinese_description := NULL,
                    _english_name := 'Home',
                    _english_description := NULL,
                    _owner_id := NULL
                 )
            INTO home_class_id;


            -- Insert default home permissions for user and guest roles
            INSERT INTO dbo.permissions(class_id, role_type, role_id, permission_bits)
            SELECT home_class_id, FALSE, groups.id, default_home_permission
            FROM auth.groups
            WHERE groups.name IN ('user', 'anon');
        END IF;
    END
$$;

-- migrate:down
