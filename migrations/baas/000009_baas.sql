-- migrate:up

INSERT INTO dbo.entities (chinese_name, english_name)
VALUES ('專案', 'Project');

CREATE TABLE dbo.projects
(
    id                  uuid        NOT NULL DEFAULT uuidv7(),
    reference           VARCHAR(20) NOT NULL UNIQUE,
    password_expired_at timestamptz NULL     DEFAULT CURRENT_TIMESTAMP,
    initialized_at      timestamptz NULL,
    CONSTRAINT pk_dbo_projects PRIMARY KEY (id),
    CONSTRAINT fk_dbo_projects_id FOREIGN KEY (id) REFERENCES dbo.objects
);

CREATE TABLE dbo.project_settings
(
    id              uuid        NOT NULL DEFAULT uuidv7(),
    project_id      uuid        NOT NULL,
    secret          TEXT        NOT NULL DEFAULT ENCODE(gen_random_bytes(32), 'base64'),
    trusted_origins TEXT[]      NOT NULL DEFAULT ARRAY []::TEXT[],
    created_at      timestamptz NOT NULL DEFAULT NOW(),
    updated_at      timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_dbo_project_auth_settings PRIMARY KEY (id),
    CONSTRAINT fk_dbo_project_auth_settings_id FOREIGN KEY (project_id) REFERENCES dbo.projects ON DELETE CASCADE
);
COMMENT ON COLUMN dbo.project_settings.secret IS 'better-auth required secret';

CREATE TABLE dbo.project_auth_providers
(
    id            uuid        NOT NULL DEFAULT uuidv7(),
    enabled       BOOLEAN     NOT NULL DEFAULT FALSE,
    name          VARCHAR(50) NOT NULL,
    project_id    uuid        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    client_id     TEXT,
    client_secret TEXT,
    extra_config  jsonb       NULL,
    CONSTRAINT pk_dbo_project_idps PRIMARY KEY (id),
    CONSTRAINT fk_dbo_project_idps_project_id FOREIGN KEY (project_id) REFERENCES dbo.projects (id) ON DELETE CASCADE,
    CONSTRAINT uq_dbo_project_oauth_providers_name_project_id UNIQUE (name, project_id)
);
COMMENT ON TABLE dbo.project_auth_providers IS 'project identity providers';
COMMENT ON COLUMN dbo.project_auth_providers.name IS 'identity provider name';

CREATE OR REPLACE VIEW dbo.vd_projects AS
(
SELECT o.id,
       o.chinese_name        name,
       o.chinese_description description,
       o.owner_id,
       o.entity_id,
       p.reference,
       o.created_at,
       o.updated_at,
       p.initialized_at,
       p.password_expired_at
FROM dbo.objects o,
     dbo.projects p
WHERE o.id = p.id
    );

-- migrate:down
