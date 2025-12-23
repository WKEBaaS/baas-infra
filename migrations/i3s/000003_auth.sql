-- migrate:up

CREATE TABLE auth.users
(
    id             uuid         NOT NULL DEFAULT uuidv7(),
    role           VARCHAR(100)          DEFAULT 'authenticated',
    name           VARCHAR(255) NOT NULL,
    email          VARCHAR(255) NOT NULL,
    email_verified BOOLEAN               DEFAULT FALSE NOT NULL,
    created_at     timestamptz  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     timestamptz  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     timestamptz,
    image          TEXT         NULL,
    CONSTRAINT pk_auth_user PRIMARY KEY (id),
    CONSTRAINT uq_auth_user_email UNIQUE (email)
);
COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';
COMMENT ON COLUMN auth.users.name IS 'User''s chosen display name';
COMMENT ON COLUMN auth.users.image IS 'User''s image url';

CREATE TABLE auth.sessions
(
    id         uuid        NOT NULL DEFAULT uuidv7(),
    user_id    uuid        NOT NULL,
    token      TEXT        NOT NULL,
    expires_at timestamptz NOT NULL,
    ip_address TEXT,
    user_agent TEXT,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_auth_sessions PRIMARY KEY (id),
    CONSTRAINT fk_auth_sessions_user_id FOREIGN KEY (user_id) REFERENCES auth.users ON DELETE CASCADE
);
COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';
COMMENT ON COLUMN auth.sessions.expires_at IS 'The time when the session expires';
CREATE INDEX session_not_after_idx
    ON auth.sessions (expires_at DESC);
CREATE INDEX session_user_id_idx
    ON auth.sessions (user_id);
CREATE INDEX user_id_created_at_idx
    ON auth.sessions (user_id, created_at);

CREATE TABLE auth.accounts
(
    id                       uuid        NOT NULL DEFAULT uuidv7(),
    user_id                  uuid        NOT NULL,
    account_id               TEXT        NOT NULL,
    provider_id              TEXT        NOT NULL,
    access_token             TEXT,
    refresh_token            TEXT,
    access_token_expires_at  timestamptz,
    refresh_token_expires_at timestamptz,
    scope                    TEXT,
    id_token                 TEXT,
    password                 TEXT,
    created_at               timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_auth_accounts PRIMARY KEY (id),
    CONSTRAINT fk_auth_accounts_user_id FOREIGN KEY (user_id) REFERENCES auth.users ON DELETE CASCADE
);
COMMENT ON COLUMN auth.accounts.account_id IS 'The ID of the account as provided by the SSO or equal to userId for credential accounts';
COMMENT ON COLUMN auth.accounts.provider_id IS 'The ID of the provider';

CREATE TABLE auth.verifications
(
    id         uuid        NOT NULL DEFAULT uuidv7(),
    identifier TEXT        NOT NULL,
    value      TEXT        NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_auth_verifications PRIMARY KEY (id)
);
COMMENT ON COLUMN auth.verifications.identifier IS 'The identifier for the verification request';
COMMENT ON COLUMN auth.verifications.value IS 'The value to be verified, e.g., email or phone number';

CREATE TABLE auth.jwks
(
    id          uuid        NOT NULL DEFAULT uuidv7(),
    public_key  TEXT        NOT NULL,
    private_key TEXT        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_auth_jwks PRIMARY KEY (id)
);

CREATE TABLE auth.sso_providers
(
    id              uuid    NOT NULL DEFAULT uuidv7(),
    issuer          VARCHAR NOT NULL,
    domain          VARCHAR NOT NULL,
    oidc_config     TEXT,
    saml_config     TEXT,
    user_id         VARCHAR NOT NULL,
    provider_id     VARCHAR NOT NULL,
    organization_id VARCHAR,
    CONSTRAINT pk_auth_sso_provider PRIMARY KEY (id)
);


CREATE TABLE auth.groups
(
    id           uuid         NOT NULL DEFAULT uuidv7(),
    name         VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    description  TEXT,
    created_at   timestamptz  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   timestamptz  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at   timestamptz,
    is_enabled   BOOLEAN               DEFAULT TRUE,
    CONSTRAINT pk_auth_group PRIMARY KEY (id),
    CONSTRAINT uq_auth_group_name UNIQUE (name)
);

CREATE TABLE auth.user_groups
(
    user_id    uuid NOT NULL,
    group_id   uuid NOT NULL,
    rank       INTEGER,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_auth_user_group PRIMARY KEY (user_id, group_id),
    CONSTRAINT fk_auth_user_group_user_id FOREIGN KEY (user_id) REFERENCES auth.users ON DELETE CASCADE,
    CONSTRAINT fk_auth_user_group_role_id FOREIGN KEY (group_id) REFERENCES auth.groups ON DELETE CASCADE
);

-- Auth tuples
INSERT INTO auth.groups (name, display_name, description)
VALUES ('admin', 'Admin', 'Admin role'),
       ('user', 'User', 'User role'),
       ('anon', 'Anonymous', 'Anonymous role');

CREATE FUNCTION auth.jwt() RETURNS jsonb
    STABLE
    LANGUAGE sql
AS
$$
SELECT COALESCE(
               NULLIF(CURRENT_SETTING('request.jwt.claim', TRUE), ''),
               NULLIF(CURRENT_SETTING('request.jwt.claims', TRUE), '')
       )::jsonb
$$;

-- GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated

-- migrate:down
