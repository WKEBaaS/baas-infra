-----------------------------------------------------------------------
----- Schema & Extensions & Roles is managed by CNPG Database CRD -----
-----------------------------------------------------------------------

-- migrate:up

-- Schemas
-- CREATE SCHEMA IF NOT EXISTS public;
-- CREATE SCHEMA IF NOT EXISTS auth;
-- CREATE SCHEMA IF NOT EXISTS dbo;
-- CREATE SCHEMA IF NOT EXISTS api;
-- CREATE SCHEMA IF NOT EXISTS storage;

-- Extensions
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
-- CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
-- CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;

-- Roles
-- CREATE USER authenticator NOINHERIT;
-- CREATE ROLE anon NOLOGIN NOINHERIT;
-- CREATE ROLE authenticated NOLOGIN NOINHERIT; -- logged-in users
-- CREATE ROLE app_admin NOLOGIN NOINHERIT BYPASSRLS;

-- PostgREST Authentication
-- set default privileges for public schema
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, app_admin;

-- set default privileges for schemas
GRANT USAGE ON SCHEMA api TO postgres, anon, authenticated, app_admin;
GRANT USAGE ON SCHEMA auth TO postgres, anon, authenticated, app_admin;
GRANT USAGE ON SCHEMA dbo TO postgres, anon, authenticated, app_admin;
GRANT USAGE ON SCHEMA storage TO postgres, anon, authenticated, app_admin;

-- expose functions for PostgREST
ALTER DEFAULT PRIVILEGES IN SCHEMA api GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, app_admin;

-- watch CREATE and ALTER
CREATE OR REPLACE FUNCTION public.pgrst_ddl_watch() RETURNS EVENT_TRIGGER AS
$$
DECLARE
    cmd RECORD;
BEGIN
    FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
        LOOP
            IF cmd.command_tag IN (
                                   'CREATE SCHEMA', 'ALTER SCHEMA', 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO',
                                   'ALTER TABLE', 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE', 'CREATE VIEW',
                                   'ALTER VIEW', 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW',
                                   'CREATE FUNCTION', 'ALTER FUNCTION', 'CREATE TRIGGER', 'CREATE TYPE', 'ALTER TYPE',
                                   'CREATE RULE', 'COMMENT'
                )
                -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
                AND cmd.schema_name IS DISTINCT FROM 'pg_temp'
            THEN
                NOTIFY pgrst, 'reload schema';
            END IF;
        END LOOP;
END;
$$ LANGUAGE plpgsql;

-- watch DROP
CREATE OR REPLACE FUNCTION public.pgrst_drop_watch() RETURNS EVENT_TRIGGER AS
$$
DECLARE
    obj RECORD;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
        LOOP
            IF obj.object_type IN (
                                   'schema', 'table', 'foreign table', 'view', 'materialized view', 'function',
                                   'trigger', 'type', 'rule'
                )
                AND obj.is_temporary IS FALSE -- no pg_temp objects
            THEN
                NOTIFY pgrst, 'reload schema';
            END IF;
        END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER pgrst_ddl_watch
    ON ddl_command_end
EXECUTE PROCEDURE public.pgrst_ddl_watch();

CREATE EVENT TRIGGER pgrst_drop_watch
    ON sql_drop
EXECUTE PROCEDURE public.pgrst_drop_watch();

-- migrate:down