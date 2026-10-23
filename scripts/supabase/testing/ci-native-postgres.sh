#!/bin/sh
# CI-only synthetic native PostgreSQL for the digest-pinned PostgreSQL job container.
# Source-only proposal: author has NOT run sh/Node/PG/Docker or any test here.
# OS user postgres owns the server; SQL bootstrap user is collect_test.
set -eu
umask 077

fail() { printf '%s\n' "$1" >&2; exit 1; }
[ "$#" -eq 1 ] || fail CI_POSTGRES_START_OR_STOP_REQUIRED
case "$1" in start|stop) action=$1 ;; *) fail CI_POSTGRES_START_OR_STOP_REQUIRED ;; esac
[ "${COLLECT_CI_SYNTHETIC-}" = true ] || fail EXPLICIT_SYNTHETIC_CI_REQUIRED
[ "$(id -u)" -eq 0 ] || fail ROOT_JOB_CONTAINER_REQUIRED
for utility in timeout gosu initdb pg_ctl psql pg_isready postgres realpath stat mktemp chmod chown mkdir rm; do
    command -v "$utility" >/dev/null 2>&1 || fail CI_POSTGRES_PREREQUISITE_MISSING
done
case "$(postgres --version)" in 'postgres (PostgreSQL) 17.10'*) ;; *) fail EXACT_POSTGRES_17_10_REQUIRED ;; esac
[ -n "${RUNNER_TEMP-}" ] && [ -d "$RUNNER_TEMP" ] || fail EXPLICIT_RUNNER_TEMP_REQUIRED
temp_root=$(realpath -- "$RUNNER_TEMP")
case "$temp_root" in /*) ;; *) fail PHYSICAL_RUNNER_TEMP_REQUIRED ;; esac
# pg_ctl forwards its fixed server options through a shell; the runner temp path
# must retain this exact simple grammar, with no spaces or shell metacharacters.
case "$temp_root" in *[!A-Za-z0-9_./-]*) fail SIMPLE_PHYSICAL_RUNNER_TEMP_REQUIRED ;; esac
# The private state file is created exclusively before starting a new server.
# It is never sourced as shell code and cannot select an arbitrary old PGDATA.
state_file="$temp_root/collect-supabase-ci-postgres.state"
cluster_root=

load_state() {
    [ -f "$state_file" ] && [ ! -L "$state_file" ] || fail PRIVATE_CI_POSTGRES_STATE_REQUIRED
    [ "$(stat -c %u -- "$state_file")" -eq 0 ] || fail ROOT_OWNED_CI_POSTGRES_STATE_REQUIRED
    [ "$(stat -c %a -- "$state_file")" = 600 ] || fail PRIVATE_CI_POSTGRES_STATE_REQUIRED
    IFS= read -r cluster_root < "$state_file" || fail CI_POSTGRES_STATE_UNREADABLE
    case "$cluster_root" in "$temp_root"/collect-supabase-pg.*) ;; *) fail OWNED_CI_POSTGRES_PATH_REQUIRED ;; esac
    suffix=${cluster_root#"$temp_root"/collect-supabase-pg.}
    case "$suffix" in ''|*[!A-Za-z0-9]*) fail OWNED_CI_POSTGRES_PATH_REQUIRED ;; esac
    [ -d "$cluster_root" ] && [ ! -L "$cluster_root" ] || fail OWNED_CI_POSTGRES_PATH_REQUIRED
    [ "$(realpath -- "$cluster_root")" = "$cluster_root" ] || fail PHYSICAL_CI_POSTGRES_PATH_REQUIRED
    [ "$(stat -c %u -- "$cluster_root")" = "$(id -u postgres)" ] || fail POSTGRES_OS_OWNED_CI_PATH_REQUIRED
    [ "$(stat -c %a -- "$cluster_root")" = 700 ] || fail PRIVATE_CI_POSTGRES_PATH_REQUIRED
}

stop_owned_server() {
    # No state means startup never dispatched. A malformed state fails closed.
    if [ ! -e "$state_file" ] && [ ! -L "$state_file" ]; then
        printf '%s\n' CI_POSTGRES_WAS_NOT_STARTED
        return 0
    fi
    load_state
    data_dir="$cluster_root/data"
    if [ ! -f "$data_dir/PG_VERSION" ]; then
        rm -f -- "$cluster_root/initdb-password" "$cluster_root/psql-password"
        printf '%s\n' CI_POSTGRES_INITIALIZATION_DID_NOT_COMPLETE
        return 0
    fi
    [ ! -L "$data_dir" ] && [ "$(realpath -- "$data_dir")" = "$data_dir" ] || fail OWNED_CI_PGDATA_REQUIRED
    [ "$(stat -c %u -- "$data_dir")" = "$(id -u postgres)" ] || fail POSTGRES_OS_OWNED_CI_PGDATA_REQUIRED
    if timeout --signal=TERM --kill-after=2s 5s gosu postgres pg_ctl -D "$data_dir" status >/dev/null 2>&1; then
        # First request a clean fast stop. Only a failed stop uses immediate stop;
        # this is bounded process cleanup, never an automatic fixture retry.
        if ! timeout --signal=TERM --kill-after=2s 20s gosu postgres pg_ctl -D "$data_dir" -m fast -w -t 15 stop; then
            timeout --signal=TERM --kill-after=2s 10s gosu postgres pg_ctl -D "$data_dir" -m immediate -w -t 5 stop || return 1
        fi
    else
        status=$?
        [ "$status" -eq 3 ] || return 1
    fi
    # Delete only these newly written synthetic authentication files. Preserve
    # cluster data/logs/state for this job's review until normal runner teardown.
    rm -f -- "$cluster_root/initdb-password" "$cluster_root/psql-password"
    printf '%s\n' "CI_POSTGRES_STOPPED_DATA_AND_LOGS_PRESERVED=$cluster_root"
}

if [ "$action" = stop ]; then
    stop_owned_server
    exit 0
fi

# These are the existing public synthetic CI fixtures, never a secret lookup.
expected_schema_url='postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/collect_schema_test'
expected_admin_url='postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/postgres'
[ "${COLLECT_TEST_PG_URL-}" = "$expected_schema_url" ] || fail EXACT_SYNTHETIC_SCHEMA_URL_REQUIRED
[ "${COLLECT_FENCE_ADMIN_DATABASE_URL-}" = "$expected_admin_url" ] || fail EXACT_SYNTHETIC_FENCE_ADMIN_URL_REQUIRED
[ "${COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL-}" = "$expected_admin_url" ] || fail EXACT_SYNTHETIC_REALTIME_ADMIN_URL_REQUIRED
[ ! -e "$state_file" ] && [ ! -L "$state_file" ] || fail FRESH_CI_POSTGRES_ATTEMPT_REQUIRED

cluster_root=$(mktemp -d "$temp_root/collect-supabase-pg.XXXXXXXXXX")
chmod 700 "$cluster_root"
chown postgres:postgres "$cluster_root"
# Noclobber ensures no prior state, symlink or file can be overwritten.
(set -C; printf '%s\n' "$cluster_root" > "$state_file") || fail FRESH_CI_POSTGRES_ATTEMPT_REQUIRED
chmod 600 "$state_file"
ready=false
finish_start() {
    result=$?
    trap - 0 HUP INT TERM
    # Trap startup failure/cancellation too; the final always() step repeats a
    # bounded stop using this exact state if execution reached server startup.
    if [ "$ready" != true ]; then
        if ! stop_owned_server; then
            printf '%s\n' CI_POSTGRES_FAILED_START_CLEANUP_UNCONFIRMED >&2
            result=1
        fi
    fi
    rm -f -- "$cluster_root/initdb-password" "$cluster_root/psql-password"
    exit "$result"
}
trap finish_start 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$cluster_root/data" "$cluster_root/socket"
chmod 700 "$cluster_root/data" "$cluster_root/socket"
# initdb must run as the OS server owner, not root. A private password file
# selects SQL collect_test as bootstrap SUPERUSER/BYPASSRLS; no SQL postgres
# role is created here. Immutable fixture00 creates its restricted role later.
printf '%s\n' collect_local_fixture_only > "$cluster_root/initdb-password"
printf '%s\n' '127.0.0.1:55439:*:collect_test:collect_local_fixture_only' > "$cluster_root/psql-password"
chmod 600 "$cluster_root/initdb-password" "$cluster_root/psql-password"
chown -R postgres:postgres "$cluster_root"
timeout --signal=TERM --kill-after=5s 90s gosu postgres initdb \
    -D "$cluster_root/data" --username=collect_test --encoding=UTF8 --locale=C \
    --auth-local=trust --auth-host=scram-sha-256 \
    --pwfile="$cluster_root/initdb-password" --no-instructions \
    > "$cluster_root/initdb.log" 2>&1
rm -f -- "$cluster_root/initdb-password"
# There is no Docker service, host-port forwarding, wildcard bind or address
# override. All job steps and this native listener share one container.
timeout --signal=TERM --kill-after=5s 40s gosu postgres pg_ctl \
    -D "$cluster_root/data" -l "$cluster_root/postgres.log" -w -t 30 \
    -o "-h 127.0.0.1 -p 55439 -k $cluster_root/socket -c unix_socket_permissions=0700" start

# A fixed native TCP proof observes exactly the same address/port as the
# existing maintained callers. Password values never enter argv or logs.
PGPASSFILE="$cluster_root/psql-password" PGCONNECT_TIMEOUT=5 timeout --signal=TERM --kill-after=2s 20s gosu postgres psql \
    --no-psqlrc --no-password --set=ON_ERROR_STOP=1 \
    --host=127.0.0.1 --port=55439 --username=collect_test --dbname=postgres <<'SQL'
DO $ci_identity$
DECLARE bootstrap record;
BEGIN
 IF current_database()<>'postgres' OR current_user<>'collect_test' OR session_user<>'collect_test'
 OR coalesce(host(inet_server_addr()),'')<>'127.0.0.1' OR inet_server_port()<>55439
 OR current_setting('server_version_num')::integer<>170010
 OR current_setting('server_encoding')<>'UTF8'
 OR current_setting('default_transaction_isolation')<>'read committed'
 OR pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database()))<>'collect_test' THEN
  RAISE EXCEPTION 'EXACT_CI_NATIVE_POSTGRES_IDENTITY_REQUIRED';
 END IF;
 SELECT rolsuper,rolbypassrls INTO STRICT bootstrap FROM pg_roles WHERE rolname='collect_test';
 IF NOT bootstrap.rolsuper OR NOT bootstrap.rolbypassrls THEN RAISE EXCEPTION 'EXPLICIT_CI_BOOTSTRAP_PROFILE_REQUIRED';END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN RAISE EXCEPTION 'FIXTURE00_MUST_OWN_RESTRICTED_SQL_POSTGRES_CREATION';END IF;
END;$ci_identity$;
CREATE DATABASE collect_schema_test OWNER collect_test TEMPLATE template0 ENCODING 'UTF8';
SQL
PGPASSFILE="$cluster_root/psql-password" PGCONNECT_TIMEOUT=5 timeout --signal=TERM --kill-after=2s 10s gosu postgres psql \
    --no-psqlrc --no-password --set=ON_ERROR_STOP=1 \
    --host=127.0.0.1 --port=55439 --username=collect_test --dbname=collect_schema_test <<'SQL'
DO $ci_database$
BEGIN
 IF current_database()<>'collect_schema_test' OR current_user<>'collect_test' OR session_user<>'collect_test'
 OR coalesce(host(inet_server_addr()),'')<>'127.0.0.1' OR inet_server_port()<>55439
 OR pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database()))<>'collect_test' THEN
  RAISE EXCEPTION 'EXACT_CI_SCHEMA_DATABASE_REQUIRED';
 END IF;
END;$ci_database$;
SQL
rm -f -- "$cluster_root/psql-password"
ready=true
printf '%s\n' "CI_NATIVE_POSTGRES_READY_DATA_AND_LOGS=$cluster_root"
