#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command psql
require_command python3

DATABASE_URL="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"
if [[ -z "$DATABASE_URL" ]]; then
  echo "Set DATABASE_URL or SUPABASE_DB_URL before running this script." >&2
  exit 1
fi

TRIGGER_MIGRATION_CHECK="${TRIGGER_MIGRATION_CHECK:-0}"

EXPECTED_MIGRATIONS=(
  20260322120000
  20260322143000
  20260322170000
  20260322171000
  20260322172000
  20260322173000
  20260322174000
  20260322175000
  20260322176000
  20260322177000
  20260322178000
  20260322179000
  20260322180000
  20260322181000
  20260322182000
  20260322183000
  20260322184000
)

EXPECTED_METRICS=(
  device_sync
  parsing
  reconciliation
  sender_inventory
  migration_safety
  retention
  sender_drift
  retry_queue
)

echo "==> M-Money SMS Supabase rollout verification"

admin_user_id="$(
  psql "$DATABASE_URL" -X -A -t -v ON_ERROR_STOP=1 <<'SQL'
select id::text
from public.users
where is_admin = true
order by created_at asc
limit 1;
SQL
)"
admin_user_id="$(printf '%s' "$admin_user_id" | tr -d '\r\n')"

if [[ -z "$admin_user_id" ]]; then
  echo "No admin user found in public.users; cannot verify admin-only SMS RPCs." >&2
  exit 1
fi

if [[ "$TRIGGER_MIGRATION_CHECK" == "1" ]]; then
  echo "==> triggering migration safety check"
  psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -v admin_user_id="$admin_user_id" <<'SQL'
with claims as (
  select set_config('request.jwt.claim.sub', :'admin_user_id', false)
)
select public.run_momo_sms_migration_safety_check()
from claims;
SQL
fi

has_cron_schema="$(
  psql "$DATABASE_URL" -X -A -t -v ON_ERROR_STOP=1 <<'SQL'
select exists(
  select 1
  from pg_namespace
  where nspname = 'cron'
);
SQL
)"
has_cron_schema="$(printf '%s' "$has_cron_schema" | tr -d '\r\n')"

if [[ "$has_cron_schema" == "t" ]]; then
  cron_json="$(
    psql "$DATABASE_URL" -X -A -t -v ON_ERROR_STOP=1 <<'SQL'
select jsonb_build_object(
  'has_cron_schema', true,
  'has_redaction_job', exists(
    select 1
    from cron.job
    where jobname = 'redact-momo-sms-artifacts-daily'
      and schedule = '17 2 * * *'
  ),
  'has_migration_safety_job', exists(
    select 1
    from cron.job
    where jobname = 'check-momo-sms-migration-safety-daily'
      and schedule = '29 2 * * *'
  )
);
SQL
  )"
else
  cron_json='{"has_cron_schema": false, "has_redaction_job": false, "has_migration_safety_job": false}'
fi

expected_migrations_csv="$(IFS=,; printf '%s' "${EXPECTED_MIGRATIONS[*]}")"
expected_metrics_csv="$(IFS=,; printf '%s' "${EXPECTED_METRICS[*]}")"

verification_json="$(
  psql "$DATABASE_URL" -X -A -t -v ON_ERROR_STOP=1 \
    -v admin_user_id="$admin_user_id" \
    -v expected_migrations_csv="$expected_migrations_csv" \
    -v expected_metrics_csv="$expected_metrics_csv" \
    -v cron_json="$cron_json" <<'SQL'
with
  claims as (
    select set_config('request.jwt.claim.sub', :'admin_user_id', false)
  ),
  expected_migrations as (
    select regexp_split_to_table(:'expected_migrations_csv', ',') as version
  ),
  expected_metrics as (
    select regexp_split_to_table(:'expected_metrics_csv', ',') as metric_key
  ),
  applied_migrations as (
    select version
    from supabase_migrations.schema_migrations
    where version in (select version from expected_migrations)
  ),
  legacy_counts as (
    select
      count(*) filter (where status = 'completed')::integer as legacy_completed_rows,
      count(distinct status)::integer as distinct_statuses
    from public.group_contributions
  ),
  summary_rows as (
    select summary.*
    from claims
    cross join lateral public.get_momo_sms_operational_summary() summary
  ),
  summary_metrics as (
    select
      jsonb_object_agg(
        metric_key,
        jsonb_build_object(
          'label', label,
          'health_status', health_status,
          'primary_label', primary_label,
          'primary_value', primary_value,
          'secondary_label', secondary_label,
          'secondary_value', secondary_value,
          'tertiary_label', tertiary_label,
          'tertiary_value', tertiary_value,
          'summary', summary,
          'last_signal_at', last_signal_at
        )
      ) as metrics
    from summary_rows
  ),
  release_sms as (
    select to_jsonb(row_data) as row_json
    from (
      select
        service_key,
        health_status,
        ok_count_24h,
        warn_count_24h,
        error_count_24h,
        issue_count,
        last_signal_at,
        summary
      from public.operational_release_dashboard
      where service_key = 'sms_ingest'
      limit 1
    ) row_data
  ),
  latest_migration_event as (
    select to_jsonb(row_data) as row_json
    from (
      select
        status,
        severity,
        issue_code,
        message,
        metadata,
        occurred_at,
        ingest_origin
      from public.operational_health_events
      where service = 'sms_ingest'
        and component = 'momo_sms_migration_safety'
        and ingest_origin = 'system'
      order by occurred_at desc
      limit 1
    ) row_data
  )
select jsonb_build_object(
  'expected_migrations', (
    select jsonb_agg(version order by version)
    from expected_migrations
  ),
  'applied_migrations', (
    select jsonb_agg(version order by version)
    from applied_migrations
  ),
  'expected_metrics', (
    select jsonb_agg(metric_key order by metric_key)
    from expected_metrics
  ),
  'cron', :'cron_json'::jsonb,
  'legacy', jsonb_build_object(
    'legacy_completed_rows', (select legacy_completed_rows from legacy_counts),
    'distinct_statuses', (select distinct_statuses from legacy_counts)
  ),
  'summary_metrics', coalesce(
    (select metrics from summary_metrics),
    '{}'::jsonb
  ),
  'release_sms', coalesce(
    (select row_json from release_sms),
    'null'::jsonb
  ),
  'latest_migration_event', coalesce(
    (select row_json from latest_migration_event),
    'null'::jsonb
  )
);
SQL
)"

python3 - "$verification_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
expected_migrations = data["expected_migrations"] or []
applied_migrations = set(data["applied_migrations"] or [])
expected_metrics = data["expected_metrics"] or []
summary_metrics = data["summary_metrics"] or {}
cron = data["cron"] or {}
legacy = data["legacy"] or {}
release_sms = data["release_sms"]
latest_event = data["latest_migration_event"]

failures = []

missing_migrations = [v for v in expected_migrations if v not in applied_migrations]
if missing_migrations:
    failures.append(
        "Missing expected M-Money SMS migrations: " + ", ".join(missing_migrations)
    )

if not cron.get("has_cron_schema"):
    failures.append("pg_cron schema is missing.")
if not cron.get("has_redaction_job"):
    failures.append("Missing cron job: redact-momo-sms-artifacts-daily @ 17 2 * * *")
if not cron.get("has_migration_safety_job"):
    failures.append(
        "Missing cron job: check-momo-sms-migration-safety-daily @ 29 2 * * *"
    )

legacy_completed_rows = int(legacy.get("legacy_completed_rows") or 0)
if legacy_completed_rows != 0:
    failures.append(
        f"Legacy group_contributions.status='completed' rows remain: {legacy_completed_rows}"
    )

missing_metrics = [key for key in expected_metrics if key not in summary_metrics]
if missing_metrics:
    failures.append(
        "Missing expected M-Money SMS summary metrics: " + ", ".join(missing_metrics)
    )

migration_safety = summary_metrics.get("migration_safety")
if migration_safety is None:
    failures.append("M-Money SMS summary is missing migration_safety.")
else:
    if migration_safety.get("health_status") != "healthy":
        failures.append(
            "migration_safety metric is not healthy: "
            + str(migration_safety.get("health_status"))
        )
    if int(migration_safety.get("primary_value") or 0) != 0:
        failures.append(
            "migration_safety primary_value is not zero legacy rows: "
            + str(migration_safety.get("primary_value"))
        )

if release_sms is None:
    failures.append("operational_release_dashboard is missing SMS Ingest.")
else:
    if release_sms.get("service_key") != "sms_ingest":
      failures.append("operational_release_dashboard returned the wrong SMS row.")
    if release_sms.get("health_status") == "failing":
      failures.append("SMS Ingest release health is failing.")

if latest_event is None:
    failures.append("No trusted momo_sms_migration_safety operational event found.")
else:
    if latest_event.get("ingest_origin") != "system":
        failures.append("Latest migration safety event is not system-origin.")
    if latest_event.get("issue_code") not in (
        "migration_safety_verified",
        "legacy_completed_contribution_rows",
    ):
        failures.append(
            "Unexpected migration safety event issue_code: "
            + str(latest_event.get("issue_code"))
        )

print("==> rollout snapshot")
print(
    f"migrations: {len(applied_migrations)}/{len(expected_migrations)} expected applied"
)
print(
    "cron: "
    f"redaction={cron.get('has_redaction_job')} "
    f"migration_safety={cron.get('has_migration_safety_job')}"
)
print(
    "legacy rows: "
    f"{legacy_completed_rows} "
    f"(distinct statuses={legacy.get('distinct_statuses')})"
)
if migration_safety is not None:
    print(
        "migration_safety: "
        f"{migration_safety.get('health_status')} "
        f"primary={migration_safety.get('primary_value')} "
        f"secondary={migration_safety.get('secondary_value')} "
        f"tertiary={migration_safety.get('tertiary_value')}"
    )
if release_sms is not None:
    print(
        "release_sms: "
        f"{release_sms.get('health_status')} "
        f"issues={release_sms.get('issue_count')} "
        f"summary={release_sms.get('summary')}"
    )
if latest_event is not None:
    print(
        "latest_event: "
        f"{latest_event.get('issue_code')} "
        f"status={latest_event.get('status')} "
        f"at={latest_event.get('occurred_at')}"
    )

if failures:
    print("==> verification failed", file=sys.stderr)
    for failure in failures:
        print(f" - {failure}", file=sys.stderr)
    sys.exit(1)

print("==> verification passed")
PY
