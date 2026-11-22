-- TEST-ONLY: loaded into a disposable Unix-socket PostgreSQL cluster created by
-- owned-pg17.mjs. This is a deliberately incomplete model, not a migration.
CREATE SCHEMA src; CREATE SCHEMA app; CREATE SCHEMA auth; CREATE SCHEMA private;
CREATE TABLE src.users(id text PRIMARY KEY,phone text UNIQUE,email text UNIQUE,full_name text NOT NULL DEFAULT '',public_id text NOT NULL UNIQUE,country_code text NOT NULL DEFAULT 'RW',currency_code text NOT NULL DEFAULT 'RWF',momo_provider text NOT NULL DEFAULT '',momo_number text NOT NULL DEFAULT '',momo_pay_code text NOT NULL DEFAULT '',access_status text NOT NULL DEFAULT 'active',created_at text NOT NULL,updated_at text NOT NULL,member_type text NOT NULL DEFAULT 'app',revision bigint NOT NULL DEFAULT 1);
CREATE TABLE app.users(LIKE src.users INCLUDING ALL);
CREATE TABLE src.auth_users(id uuid PRIMARY KEY,active boolean NOT NULL);
CREATE TABLE auth.users(LIKE src.auth_users INCLUDING ALL);
CREATE TABLE src.auth_principal_links(auth_user_id uuid PRIMARY KEY REFERENCES src.auth_users(id),user_id text NOT NULL UNIQUE REFERENCES src.users(id),linked_at timestamptz NOT NULL,proof_reference text NOT NULL);
CREATE TABLE private.auth_principal_links(auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),user_id text NOT NULL UNIQUE REFERENCES app.users(id),linked_at timestamptz NOT NULL,proof_reference text NOT NULL);
CREATE FUNCTION private.fixture_link_immutable() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'fixture_immutable' USING ERRCODE='42501';END$$;
CREATE TRIGGER fixture_link_immutable BEFORE UPDATE OR DELETE ON src.auth_principal_links FOR EACH ROW EXECUTE FUNCTION private.fixture_link_immutable();
CREATE TRIGGER fixture_link_immutable BEFORE UPDATE OR DELETE ON private.auth_principal_links FOR EACH ROW EXECUTE FUNCTION private.fixture_link_immutable();
ALTER TABLE src.auth_principal_links ENABLE ALWAYS TRIGGER fixture_link_immutable;
ALTER TABLE private.auth_principal_links ENABLE ALWAYS TRIGGER fixture_link_immutable;
CREATE TABLE src.collections(id text PRIMARY KEY,slug text NOT NULL UNIQUE,creator_user_id text NOT NULL REFERENCES src.users(id),title text NOT NULL,description text NOT NULL DEFAULT '',collection_type text NOT NULL,country_code text NOT NULL DEFAULT 'RW' CHECK(country_code='RW'),currency text NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),status text NOT NULL DEFAULT 'active' CHECK(status IN('active','archived','suspended')),visibility_status text NOT NULL DEFAULT 'private' CHECK(visibility_status IN('private','public_pending','public_approved')),is_platform_sponsored bigint NOT NULL DEFAULT 0 CHECK(is_platform_sponsored IN(0,1)),receiver_momo_number text,receiver_network text,receiver_display_label text,share_code_hash text UNIQUE,share_code_ciphertext text,share_code_version bigint NOT NULL DEFAULT 1,revision bigint NOT NULL DEFAULT 1,data_json text NOT NULL DEFAULT '{}',created_at text NOT NULL,updated_at text NOT NULL);
CREATE TABLE app.collections(LIKE src.collections INCLUDING ALL);
ALTER TABLE app.collections ADD CONSTRAINT fixture_creator_fk FOREIGN KEY(creator_user_id) REFERENCES app.users(id);
CREATE TABLE src.collection_dependencies(collection_id text NOT NULL REFERENCES src.collections(id),kind text NOT NULL);
CREATE TABLE private.fixture_fences(side text PRIMARY KEY CHECK(side IN('source','target')),epoch bigint NOT NULL,mode text NOT NULL);
CREATE TABLE private.fixture_admissions(state text,uncertain_dispatches integer);
CREATE TABLE private.fixture_evidence(id text PRIMARY KEY,source_collection_id text NOT NULL,source_user_id text NOT NULL,target_user_id text NOT NULL,reviewed boolean NOT NULL,complete_object_graph boolean NOT NULL,reference_free boolean NOT NULL,key_aad_verified boolean NOT NULL,identity_aad_independent boolean NOT NULL,source_key_aad text NOT NULL,target_key_aad text NOT NULL);
CREATE TABLE private.fixture_receipts(operation_id uuid PRIMARY KEY,plan_digest text NOT NULL,source_collection_id text NOT NULL UNIQUE,source_user_id text NOT NULL,target_user_id text NOT NULL,target_auth_id uuid NOT NULL,source_hmac text NOT NULL,target_hmac text NOT NULL,evidence_hmac text NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE FUNCTION private.fixture_collection_fence() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 IF current_setting('collect.fixture_operation',true) IS NULL OR current_setting('collect.fixture_operation',true)='' OR
   (SELECT count(*) FROM private.fixture_fences WHERE mode='fenced')<>2 OR
   EXISTS(SELECT 1 FROM private.fixture_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0)
 THEN RAISE EXCEPTION 'fixture_fenced' USING ERRCODE='42501';END IF;RETURN NULL;END$$;
CREATE TRIGGER fixture_collection_fence BEFORE INSERT ON app.collections FOR EACH STATEMENT EXECUTE FUNCTION private.fixture_collection_fence();
ALTER TABLE app.collections ENABLE ALWAYS TRIGGER fixture_collection_fence;
GRANT USAGE ON SCHEMA src,app,auth,private TO fixture_operator;
-- These broad fixture privileges are not suitable for a live migration role.
GRANT SELECT,UPDATE ON ALL TABLES IN SCHEMA src,app,auth,private TO fixture_operator;
GRANT INSERT ON app.collections,private.fixture_receipts TO fixture_operator;
