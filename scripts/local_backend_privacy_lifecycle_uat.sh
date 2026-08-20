#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONTAINER="${COLLECT_LOCAL_SUPABASE_DB_CONTAINER:-supabase_db_collect}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${COLLECT_LOCAL_BACKEND_EVIDENCE_DIR:-$ROOT_DIR/.cache/local_backend_privacy_lifecycle/$timestamp}"
SQL_FILE="$ROOT_DIR/scripts/local_backend_privacy_lifecycle_uat.sql"
LOG_FILE="$EVIDENCE_DIR/psql.log"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  printf '[local-backend-uat][FAIL] Local Supabase database container %s is unavailable.\n' "$CONTAINER" >&2
  exit 1
fi

mkdir -p "$EVIDENCE_DIR"
set +e
docker exec -i "$CONTAINER" psql \
  -X \
  -v ON_ERROR_STOP=1 \
  -U postgres \
  -d postgres <"$SQL_FILE" >"$LOG_FILE" 2>&1
rc=$?
set -e

UAT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
UAT_RC="$rc" \
UAT_LOG="$LOG_FILE" \
UAT_SQL="$SQL_FILE" \
UAT_SUMMARY="$SUMMARY_FILE" \
ruby <<'RUBY'
require "digest"
require "json"
require "time"

log_path = ENV.fetch("UAT_LOG")
sql_path = ENV.fetch("UAT_SQL")
log = File.read(log_path)
exit_code = Integer(ENV.fetch("UAT_RC"))
marker = log.include?("LOCAL_BACKEND_PRIVACY_LIFECYCLE_PASS")
provider_gateway_marker = log.include?("PROVIDER_FINALITY_GATEWAY_PASS")
summary = {
  "generated_at" => ENV.fetch("UAT_GENERATED_AT"),
  "status" => exit_code.zero? && marker && provider_gateway_marker ? "pass" : "fail",
  "scope" => "isolated local Supabase transaction; synthetic identities and payment events; automatic rollback; no production mutation, provider request, real SMS, or customer data",
  "exit_code" => exit_code,
  "completion_marker" => marker,
  "provider_finality_gateway_marker" => provider_gateway_marker,
  "lifecycle_states" => %w[pending confirmed expired duplicate failed recovery],
  "privacy_boundaries" => %w[
    receiver_detail
    ledger_authorization
    account_deletion_request
    support_request
    collection_audit_scope
  ],
  "checks" => {
    "transaction_rolled_back" => log.include?("ROLLBACK"),
    "payment_allocation_idempotent" => exit_code.zero? && marker,
    "provider_request_replay_idempotent" => exit_code.zero? && provider_gateway_marker,
    "provider_rejection_posts_no_ledger" => exit_code.zero? && provider_gateway_marker,
    "ledger_immutable" => exit_code.zero? && marker,
    "receiver_details_scoped" => exit_code.zero? && marker,
    "deletion_and_support_requests_scoped" => exit_code.zero? && marker,
    "collection_audit_scoped" => exit_code.zero? && marker
  },
  "limitations" => [
    "This is a local database/RLS/RPC lifecycle run, not a production Supabase change.",
    "It does not place a MoMo transaction, read an SMS body from a device, or prove provider delivery.",
    "Native network-loss/restoration and production monitoring remain separate evidence."
  ],
  "artifacts" => {
    "sql" => sql_path.delete_prefix("#{Dir.pwd}/"),
    "sql_sha256" => Digest::SHA256.file(sql_path).hexdigest,
    "log" => log_path.delete_prefix("#{Dir.pwd}/"),
    "log_sha256" => Digest::SHA256.file(log_path).hexdigest
  }
}
File.write(ENV.fetch("UAT_SUMMARY"), JSON.pretty_generate(summary) + "\n")
exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY

cat "$SUMMARY_FILE"
