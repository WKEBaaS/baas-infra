-- migrate:up

GRANT ALL ON TABLE dbo.projects TO authenticated;
GRANT ALL ON TABLE dbo.objects TO authenticated;
GRANT ALL ON TABLE dbo.project_s3_settings TO authenticated;
GRANT ALL ON TABLE dbo.project_auth_settings TO authenticated;
GRANT ALL ON TABLE dbo.project_auth_providers TO authenticated;

CREATE TABLE api.create_project_output
(
    id                   uuid        NOT NULL,
    ref                  VARCHAR(20) NOT NULL,
    auth_secret          TEXT        NOT NULL,
    s3_bucket            TEXT        NOT NULL,
    s3_access_key_id     TEXT        NOT NULL,
    s3_secret_access_key TEXT        NOT NULL
);

CREATE OR REPLACE FUNCTION api.create_project(
    name TEXT,
    description TEXT
) RETURNS SETOF api.create_project_output AS
$$
DECLARE
    v_user_id           uuid := auth.jwt() ->> 'sub';
    v_project_entity_id INT  := 100;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to create a project.';
    END IF;

    RETURN QUERY
        WITH new_object AS (
            INSERT INTO dbo.objects (chinese_name, chinese_description, owner_id, entity_id)
                VALUES (create_project.name, create_project.description, v_user_id, v_project_entity_id)
                RETURNING id, chinese_name AS name, chinese_description AS description, owner_id, entity_id, created_at, updated_at),
             new_project AS (
                 INSERT INTO dbo.projects (id, reference)
                     SELECT id, nanoid(20, 'abcdefghijklmnopqrstuvwxyz')
                     FROM new_object
                     RETURNING id, reference, initialized_at, password_expired_at),
             auth_settings AS (
                 INSERT INTO dbo.project_auth_settings (project_id)
                     SELECT id FROM new_object
                     RETURNING project_id, secret),
             auth_providers AS (
                 INSERT INTO dbo.project_auth_providers (project_id, name, enabled)
                     SELECT id, 'email', TRUE
                     FROM new_object),
             s3_settings AS (
                 INSERT INTO dbo.project_s3_settings (project_id, bucket, access_key_id, secret_access_key)
                     SELECT id,
                            CONCAT('baas-', reference),
                            reference,
                            nanoid(32)
                     FROM new_project
                     RETURNING project_id, bucket, access_key_id, secret_access_key)
        SELECT o.id
             , p.reference
             , a.secret
             , s.bucket
             , s.access_key_id
             , s.secret_access_key
        FROM new_object o
                 JOIN new_project p ON o.id = p.id
                 JOIN auth_settings a ON o.id = a.project_id
                 JOIN s3_settings s ON o.id = s.project_id;
END;
$$
    LANGUAGE plpgsql
    SECURITY DEFINER;

COMMENT ON FUNCTION api.create_project IS $$Create a new project
Creates a new project with default settings and returns the project details.
$$;


CREATE TABLE api.delete_project_output
(
    ref              VARCHAR(20) NOT NULL,
    s3_bucket        TEXT        NOT NULL,
    s3_access_key_id TEXT        NOT NULL
);

CREATE OR REPLACE FUNCTION api.delete_project(project_id uuid)
    RETURNS SETOF api.delete_project_output AS
$$
DECLARE
    v_user_id uuid := auth.jwt() ->> 'sub';
BEGIN
    IF v_user_id IS NULL THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to delete a project.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.projects WHERE id = project_id) THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = 'Not Found',
            HINT = 'Project not found.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.objects WHERE id = project_id AND owner_id = v_user_id) THEN
        RAISE SQLSTATE 'PT403' USING
            MESSAGE = 'Forbidden',
            HINT = 'User does not have permission to delete this project.';
    END IF;

    RETURN QUERY
        WITH s3_settings AS (
            DELETE FROM dbo.project_s3_settings
                WHERE project_s3_settings.project_id = delete_project.project_id
                RETURNING bucket, access_key_id),
             project AS (
                 DELETE FROM dbo.projects WHERE id = project_id RETURNING reference),
             object AS (
                 DELETE FROM dbo.objects WHERE id = project_id)
        SELECT p.reference, s.bucket, s.access_key_id
        FROM project p,
             s3_settings s;
END;
$$ LANGUAGE plpgsql VOLATILE;


CREATE TABLE api.update_project_output
(
    ref VARCHAR(20) NOT NULL
);

CREATE OR REPLACE FUNCTION api.update_project(
    id uuid,
    name TEXT,
    description TEXT,
    trusted_origins TEXT[],
    proxy_url TEXT
) RETURNS SETOF api.update_project_output AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    v_user_id uuid := auth.jwt() ->> 'sub';
BEGIN
    IF v_user_id IS NULL THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to delete a project.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.projects WHERE id = update_project.id) THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = 'Not Found',
            HINT = 'Project not found.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.objects WHERE id = update_project.id AND owner_id = v_user_id) THEN
        RAISE SQLSTATE 'PT403' USING
            MESSAGE = 'Forbidden',
            HINT = 'User does not have permission to delete this project.';
    END IF;

    UPDATE dbo.objects
    SET chinese_name        = COALESCE(update_project.name, chinese_name),
        chinese_description = COALESCE(update_project.description, chinese_description),
        updated_at          = NOW()
    WHERE id = update_project.id;

    UPDATE dbo.project_auth_settings
    SET trusted_origins = COALESCE(update_project.trusted_origins, trusted_origins),
        proxy_url       = COALESCE(update_project.proxy_url, proxy_url),
        updated_at      = NOW()
    WHERE project_id = update_project.id;

    RETURN QUERY SELECT reference AS ref
                 FROM dbo.projects
                 WHERE id = update_project.id;
END;
$$ LANGUAGE plpgsql VOLATILE;


CREATE OR REPLACE FUNCTION api.create_or_update_auth_providers(payload jsonb)
    RETURNS VOID AS
$$
DECLARE
    v_user_id    uuid := auth.jwt() ->> 'sub';
    v_project_id uuid := (payload ->> 'project_id')::uuid;
BEGIN
    -- 身份驗證與權限檢查 (與原版相同)
    IF v_user_id IS NULL THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to perform this action.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.projects WHERE id = v_project_id) THEN
        RAISE SQLSTATE 'PT404' USING
            MESSAGE = 'Not Found',
            HINT = 'Project not found.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.objects WHERE id = v_project_id AND owner_id = v_user_id) THEN
        RAISE SQLSTATE 'PT403' USING
            MESSAGE = 'Forbidden',
            HINT = 'User does not have permission to modify this project.';
    END IF;

    -- 使用 jsonb_each 來處理 JSON 物件
    INSERT INTO dbo.project_auth_providers(project_id, name, enabled, client_id, client_secret, updated_at)
    SELECT v_project_id,
           provider.name,                            -- 鍵 (key) 直接作為 name
           (provider.config ->> 'enabled')::BOOLEAN, -- 從值 (value) 中提取 enabled
           provider.config ->> 'client_id',          -- 從值 (value) 中提取 client_id
           provider.config ->> 'client_secret',      -- 從值 (value) 中提取 client_secret
           NOW()
    FROM JSONB_EACH(payload -> 'providers') AS provider(name, config) -- 將物件展開為 name 和 config
    ON CONFLICT (project_id, name) DO UPDATE SET enabled       = excluded.enabled,
                                                 client_id     = excluded.client_id,
                                                 client_secret = excluded.client_secret,
                                                 updated_at    = excluded.updated_at;
END;
$$
    LANGUAGE plpgsql
    VOLATILE;

-- 建議同時更新函式註解，以反映正確的 payload 結構
COMMENT ON FUNCTION api.create_or_update_auth_providers IS $$Create or update authentication providers for a project.
@param payload A JSONB object containing the project ID and an object of authentication providers.
The payload should look like:
```json
{
  "project_id": "UUID",
  "providers": {
    "provider_name_1": { "enabled": true, "client_id": "...", "client_secret": "..." },
    "provider_name_2": { "enabled": false, "client_id": "...", "client_secret": "..." }
  }
}
```
$$;

CREATE OR REPLACE FUNCTION api.get_project_s3_settings(p_project_id uuid)
    RETURNS SETOF dbo.project_s3_settings AS
$$
    # VARIABLE_CONFLICT USE_COLUMN
DECLARE
    -- Extract the user ID from the JWT token.
    v_user_id uuid := auth.jwt() ->> 'sub';
BEGIN
    -- Check if the user is authenticated. If not, raise an unauthorized error.
    IF v_user_id IS NULL THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to view project settings.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM dbo.objects WHERE id = p_project_id AND owner_id = v_user_id) THEN
        RAISE SQLSTATE 'PT403' USING
            MESSAGE = 'Forbidden',
            HINT = 'User does not have permission to access this project''s settings.';
    END IF;

    RETURN QUERY
        SELECT s.*
        FROM dbo.project_s3_settings AS s
        WHERE s.project_id = p_project_id;
END;
$$
    LANGUAGE plpgsql
    -- Execute the function with the privileges of the user who defines it, not the user who calls it.
    -- This is crucial for checking permissions on tables the 'authenticated' role may not have direct access to.
    SECURITY DEFINER;
COMMENT ON FUNCTION api.get_project_s3_settings(uuid) IS
    $$Get the S3 settings for a specific project.
Only the project owner can access these settings.
$$;

CREATE OR REPLACE FUNCTION api.check_project_permission(
    p_project_id uuid
)
    RETURNS TABLE
            (
                has BOOLEAN
            )
    LANGUAGE plpgsql
    STABLE SECURITY DEFINER
AS
$$
DECLARE
    v_user_id uuid    := auth.jwt() ->> 'sub';
    v_has     BOOLEAN := FALSE;
BEGIN
    IF CURRENT_USER = 'anon' THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to check project permissions.';
    END IF;


    SELECT INTO v_has CASE
                          WHEN EXISTS(SELECT 1
                                      FROM dbo.objects o
                                      WHERE o.id = p_project_id
                                        AND o.owner_id = v_user_id) THEN TRUE
                          ELSE FALSE
                          END AS has;

    IF NOT v_has THEN
        RAISE SQLSTATE 'PT403' USING
            MESSAGE = 'Forbidden',
            HINT = 'User does not have permission for this project.';
    END IF;

    RETURN QUERY SELECT v_has AS has;
END;
$$;

CREATE OR REPLACE FUNCTION api.check_project_permission_by_ref(
    p_project_ref VARCHAR(20)
)
    RETURNS TABLE
            (
                has BOOLEAN
            )
    LANGUAGE plpgsql
    STABLE SECURITY DEFINER
AS
$$
DECLARE
    v_user_id uuid    := auth.jwt() ->> 'sub';
    v_has     BOOLEAN := FALSE;
BEGIN
    IF CURRENT_USER = 'anon' THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to check project permissions.';
    END IF;

    SELECT INTO v_has CASE
                          WHEN EXISTS(SELECT 1
                                      FROM dbo.objects o
                                               JOIN dbo.projects p ON o.id = p.id
                                      WHERE p.reference = p_project_ref
                                        AND o.owner_id = v_user_id) THEN TRUE
                          ELSE FALSE
                          END AS has;
    IF NOT v_has THEN
        RAISE SQLSTATE 'PT403' USING
            MESSAGE = 'Forbidden',
            HINT = 'User does not have permission for this project.';
    END IF;
    RETURN QUERY SELECT v_has AS has;
END;
$$;

CREATE OR REPLACE FUNCTION api.new_create_class_function(
    p_project_id uuid,
    p_name TEXT,
    p_version SMALLINT,
    p_description TEXT,
    p_authenticated BOOLEAN,
    p_root_node jsonb,
    p_nodes jsonb
) RETURNS SETOF dbo.create_class_functions
    LANGUAGE plpgsql
    VOLATILE SECURITY DEFINER
AS
$$
DECLARE
BEGIN
    PERFORM api.check_project_permission(p_project_id);

    RETURN QUERY
        INSERT INTO dbo.create_class_functions (project_id, name, version, description, authenticated, root_node, node)
            VALUES (p_project_id,
                    p_name,
                    p_version,
                    p_description,
                    p_authenticated,
                    p_root_node,
                    p_nodes)
            ON CONFLICT (project_id, name, version)
                DO UPDATE SET description = excluded.description,
                    authenticated = excluded.authenticated,
                    root_node = excluded.root_node,
                    node = excluded.node,
                    updated_at = NOW()
            RETURNING *;
END;
$$;

CREATE OR REPLACE FUNCTION api.get_create_class_functions(p_project_id uuid)
    RETURNS TABLE
            (
                id          uuid,
                name        TEXT,
                version     SMALLINT,
                description TEXT
            )
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
AS
$$
BEGIN
    IF CURRENT_USER = 'anon' THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to get create class functions.';
    END IF;
    PERFORM api.check_project_permission(p_project_id);
    RETURN QUERY
        SELECT DISTINCT ON (name) id, name, version, description
        FROM dbo.create_class_functions
        WHERE project_id = p_project_id
        ORDER BY name, version DESC;
END;
$$;

CREATE OR REPLACE FUNCTION api.get_create_class_function(
    p_project_id uuid,
    p_name TEXT,
    p_version SMALLINT
)
    RETURNS dbo.create_class_functions
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
AS
$$
DECLARE
    v_function dbo.create_class_functions%ROWTYPE;
BEGIN
    IF CURRENT_USER = 'anon' THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to get create class function.';
    END IF;

    PERFORM api.check_project_permission(p_project_id);

    SELECT *
    INTO v_function
    FROM dbo.create_class_functions
    WHERE project_id = p_project_id
      AND name = p_name
      AND version = p_version;
    RETURN v_function;
END;
$$;

CREATE OR REPLACE FUNCTION api.get_create_class_function_versions(
    p_project_id uuid,
    p_name TEXT
)
    RETURNS INT[]
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
AS
$$
DECLARE
    v_result INT[];
BEGIN
    -- Auth Checks
    IF CURRENT_USER = 'anon' THEN
        RAISE SQLSTATE 'PT401' USING
            MESSAGE = 'Unauthorized',
            HINT = 'User must be authenticated to get create class function versions.';
    END IF;

    PERFORM api.check_project_permission(p_project_id);

    -- Query Logic
    SELECT ARRAY_AGG(version ORDER BY version)
    INTO v_result
    FROM dbo.create_class_functions
    WHERE project_id = p_project_id
      AND name = p_name;

    -- Return the single array, defaulting to an empty array if no rows found
    RETURN COALESCE(v_result, '{}');
END;
$$;

-- migrate:down
