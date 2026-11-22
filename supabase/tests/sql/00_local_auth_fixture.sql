-- Synthetic local PostgreSQL fixture ONLY. Supabase owns these schemas in a
-- real project. This file is not a migration and must never run there.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY,email text,phone text,phone_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
CREATE TABLE IF NOT EXISTS auth.sessions(id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES auth.users(id),aal text NOT NULL DEFAULT 'aal1',factor_id uuid,not_after timestamptz);
CREATE TABLE IF NOT EXISTS auth.mfa_factors(id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES auth.users(id),status text NOT NULL);
CREATE TABLE IF NOT EXISTS auth.mfa_amr_claims(session_id uuid NOT NULL REFERENCES auth.sessions(id),authentication_method text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(session_id,authentication_method));
DO $$BEGIN
 -- Hosted Supabase postgres is not a superuser. This local-only identity
 -- prevents SUPERUSER test sessions from hiding runtime SET ROLE failures.
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres NOLOGIN NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END$$;
