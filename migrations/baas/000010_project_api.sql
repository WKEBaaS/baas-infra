-- migrate:up

GRANT ALL ON TABLE dbo.projects TO authenticated;
GRANT ALL ON TABLE dbo.objects TO authenticated;
GRANT ALL ON TABLE dbo.project_s3_settings TO authenticated;

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

-- migrate:down
