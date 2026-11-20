#!/bin/bash
set -euo pipefail
BIN="${COLLECT_SMS_TEST_PG_BIN:-/Volumes/PRO-G40/Development/Supabase/Qwen-Validation/cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin}"
DENO_BIN="${COLLECT_SMS_TEST_DENO_BIN:-$(command -v deno)}"
"$BIN/initdb" --version | grep -Eq '^initdb \(PostgreSQL\) 17\.'
TASK_TMP="$(mktemp -d /tmp/collect-managed-sms-XXXXXXXX)"
TASK_TMP="$(cd "$TASK_TMP" && pwd -P)"
case "$TASK_TMP" in /private/tmp/collect-managed-sms-*|/tmp/collect-managed-sms-*) ;; *) exit 1;; esac
SERVER_PID=''
SERVER_LAUNCH_ATTEMPTED=false
TASK_CHILD=''
cleanup() {
  # Stop only the exact server started from this fresh, physical data folder.
  if [ "$SERVER_LAUNCH_ATTEMPTED" = true ] && [ -z "$SERVER_PID" ]; then
    printf 'synthetic postgres startup unconfirmed; retained %s\n' "$TASK_TMP" >&2; return 1
  fi
  if [ -f "$TASK_TMP/data/postmaster.pid" ]; then
    if [ -z "$SERVER_PID" ] || [ -L "$TASK_TMP/data" ] ||
       [ "$(cd "$TASK_TMP/data" && pwd -P)" != "$TASK_TMP/data" ] ||
       [ "$(sed -n '1p' "$TASK_TMP/data/postmaster.pid")" != "$SERVER_PID" ] ||
       [ "$(sed -n '2p' "$TASK_TMP/data/postmaster.pid")" != "$TASK_TMP/data" ]; then
      printf 'synthetic postgres identity unconfirmed; retained %s\n' "$TASK_TMP" >&2; return 1
    fi
    if ! "$BIN/pg_ctl" -D "$TASK_TMP/data" -m fast -w -t 10 stop >/dev/null 2>&1; then
      printf 'synthetic postgres stop unconfirmed; retained %s\n' "$TASK_TMP" >&2; return 1
    fi
  fi
  if [ -f "$TASK_TMP/data/postmaster.pid" ] || { [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; }; then
    printf 'synthetic postgres still present; retained %s\n' "$TASK_TMP" >&2; return 1
  fi
  rm -rf -- "$TASK_TMP"
}
trap 'status=$?; trap - EXIT; if ! cleanup; then exit 1; fi; exit "$status"' EXIT
# Interruptions terminate the exact tracked fixture child before verified server
# cleanup. A signal during startup can leave identity unconfirmed: retain it.
interrupt() {
  local code="$1" i
  trap '' TERM INT
  if [ -n "$TASK_CHILD" ]; then
    kill -TERM "$TASK_CHILD" 2>/dev/null || :
    for i in {1..50}; do if ! kill -0 "$TASK_CHILD" 2>/dev/null; then break; fi; sleep 0.1; done
    if kill -0 "$TASK_CHILD" 2>/dev/null; then kill -KILL "$TASK_CHILD" 2>/dev/null || :; fi
    wait "$TASK_CHILD" 2>/dev/null || :
    TASK_CHILD=''
  fi
  exit "$code"
}
trap 'interrupt 143' TERM
trap 'interrupt 130' INT
owned_command() {
  local status
  "$@" <&0 & TASK_CHILD=$!
  if wait "$TASK_CHILD"; then status=0; else status=$?; fi
  TASK_CHILD=''
  return "$status"
}
TASK_PORT="$(/usr/bin/python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
chmod 700 "$TASK_TMP"
mkdir -m 700 "$TASK_TMP/socket"
owned_command "$BIN/initdb" -D "$TASK_TMP/data" -U postgres --auth=trust --no-sync >/dev/null
SERVER_LAUNCH_ATTEMPTED=true
owned_command "$BIN/pg_ctl" -D "$TASK_TMP/data" -l "$TASK_TMP/postgres.log" -o "-k $TASK_TMP/socket -p $TASK_PORT -c listen_addresses=127.0.0.1" -w start >/dev/null
SERVER_PID="$(sed -n '1p' "$TASK_TMP/data/postmaster.pid")"
case "$SERVER_PID" in ''|*[!0-9]*) printf 'synthetic postgres PID invalid\n' >&2; exit 1;; esac
owned_command "$BIN/psql" -h "$TASK_TMP/socket" -p "$TASK_PORT" -U postgres -d postgres -X -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE ROLE collect_sms_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE collect_sms_edge LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
GRANT collect_sms_runtime TO collect_sms_edge;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON DATABASE postgres FROM PUBLIC;
CREATE SCHEMA private; CREATE SCHEMA app; CREATE SCHEMA collect_sms;
REVOKE ALL ON SCHEMA private,app FROM PUBLIC;
GRANT USAGE ON SCHEMA collect_sms TO collect_sms_runtime;
-- Synthetic contract doubles; these are not the production fence migrations.
CREATE TABLE private.fixture_admissions(id uuid PRIMARY KEY, epoch bigint NOT NULL, source text NOT NULL, kind text NOT NULL, state text NOT NULL, reason text, external integer, uncertain integer);
CREATE TABLE collect_sms.applications(application_id text PRIMARY KEY,token_hash text UNIQUE NOT NULL,allowed_kinds text NOT NULL,scopes text NOT NULL,revoked_at text);
INSERT INTO collect_sms.applications VALUES('alpha',repeat('c',64),'["receipt"]','["messages:read","messages:write"]',NULL);
CREATE TABLE collect_sms.messages(message_id text PRIMARY KEY,application_id text NOT NULL REFERENCES collect_sms.applications,kind text NOT NULL,text text NOT NULL);
GRANT SELECT,UPDATE ON collect_sms.applications TO collect_sms_runtime;
GRANT SELECT,INSERT,UPDATE ON collect_sms.messages TO collect_sms_runtime;
CREATE FUNCTION collect_sms.fixture_require() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN IF current_setting('role',true)<>'collect_sms_runtime' OR current_setting('collect.sms_verified',true)<>'true' THEN RAISE EXCEPTION 'fixture_role_refused'; END IF; END$$;
CREATE FUNCTION collect_sms.work_register(p_id uuid,p_source text,p_kind text,p_profile text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN PERFORM collect_sms.fixture_require(); IF p_source<>repeat('a',64) OR p_profile<>repeat('b',64) THEN RAISE EXCEPTION 'fixture_binding_refused'; END IF;
 IF (SELECT count(*) FROM private.fixture_admissions WHERE state IN ('active','unresolved'))>=8 THEN RAISE EXCEPTION 'fixture_work_capacity'; END IF;
 INSERT INTO private.fixture_admissions VALUES(p_id,1,p_source,p_kind,'active',NULL,NULL,NULL);
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',1,'sourceSha256',p_source,'kind',p_kind,'state','active','mode','open'); END$$;
CREATE FUNCTION collect_sms.work_assert(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE k text;BEGIN PERFORM collect_sms.fixture_require();IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_locks WHERE locktype='advisory' AND pid=pg_backend_pid() AND classid=7346371 AND objid=1 AND mode='ShareLock' AND granted) THEN RAISE EXCEPTION 'fixture_lease_missing'; END IF;
 SELECT kind INTO k FROM private.fixture_admissions WHERE id=p_id AND epoch=p_epoch AND source=p_source AND state='active';IF k IS NULL THEN RAISE EXCEPTION 'fixture_admission_missing'; END IF;
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',p_epoch,'sourceSha256',p_source,'kind',k,'state','active','mode','open'); END$$;
CREATE FUNCTION collect_sms.work_assert_write(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN PERFORM collect_sms.fixture_require();IF NOT EXISTS(SELECT 1 FROM private.fixture_admissions WHERE id=p_id AND epoch=p_epoch AND source=p_source AND state='active') THEN RAISE EXCEPTION 'fixture_admission_missing'; END IF;
 PERFORM pg_advisory_xact_lock_shared(7346371,2);RETURN jsonb_build_object('contractVersion',1,'epoch',p_epoch,'mode','open'); END$$;
CREATE FUNCTION collect_sms.fixture_write_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN PERFORM collect_sms.work_assert_write(nullif(current_setting('collect.fence_admission_id',true),'')::uuid,nullif(current_setting('collect.fence_epoch',true),'')::bigint,nullif(current_setting('collect.fence_source_sha256',true),''));RETURN NULL;END$$;
CREATE TRIGGER fixture_write BEFORE INSERT OR UPDATE OR DELETE ON collect_sms.messages FOR EACH STATEMENT EXECUTE FUNCTION collect_sms.fixture_write_guard();
CREATE FUNCTION collect_sms.work_close(p_id uuid,p_epoch bigint,p_source text,p_outcome text,p_reason text,p_external integer,p_uncertain integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE k text;BEGIN PERFORM collect_sms.fixture_require();UPDATE private.fixture_admissions SET state=p_outcome,reason=p_reason,external=p_external,uncertain=p_uncertain WHERE id=p_id AND epoch=p_epoch AND source=p_source RETURNING kind INTO k;
 IF k IS NULL THEN RAISE EXCEPTION 'fixture_admission_missing';END IF;RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',p_epoch,'sourceSha256',p_source,'state',p_outcome,'reason',p_reason,'externalDispatches',p_external,'uncertainDispatches',p_uncertain);END$$;
CREATE FUNCTION collect_sms.work_status(p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE a private.fixture_admissions%ROWTYPE;BEGIN PERFORM collect_sms.fixture_require();SELECT * INTO a FROM private.fixture_admissions WHERE id=p_id;IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion',1,'found',false,'admissionId',p_id);END IF;
 RETURN jsonb_build_object('contractVersion',1,'found',true,'admissionId',p_id,'epoch',a.epoch,'sourceSha256',a.source,'state',a.state,'reason',a.reason,'externalDispatches',a.external,'uncertainDispatches',a.uncertain);END$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_sms FROM PUBLIC;
GRANT EXECUTE ON FUNCTION collect_sms.work_register(uuid,text,text,text),collect_sms.work_assert(uuid,bigint,text),collect_sms.work_assert_write(uuid,bigint,text),collect_sms.work_close(uuid,bigint,text,text,text,integer,integer),collect_sms.work_status(uuid) TO collect_sms_runtime;
SQL
DENO_ENV=(PATH=/usr/bin:/bin "MANAGED_SMS_FIXTURE_SOCKET=$TASK_TMP/socket" "MANAGED_SMS_FIXTURE_PORT=$TASK_PORT")
if [ -n "${COLLECT_SMS_TEST_DENO_DIR:-}" ]; then
  case "$COLLECT_SMS_TEST_DENO_DIR" in /*) ;; *) printf 'Deno cache must be absolute\n' >&2; exit 1;; esac
  [ -d "$COLLECT_SMS_TEST_DENO_DIR" ] || { printf 'Deno cache is unavailable\n' >&2; exit 1; }
  DENO_ENV+=("DENO_DIR=$COLLECT_SMS_TEST_DENO_DIR")
fi
owned_command env -i "${DENO_ENV[@]}" "$DENO_BIN" run --cached-only --frozen-lockfile --lock=deno.lock --node-modules-dir=none --allow-env --allow-net="127.0.0.1:$TASK_PORT" test/local-postgres-fixture.ts
