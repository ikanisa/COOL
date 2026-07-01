# Supabase Migration 20260627191000 Approval Runbook

## Scope

Linked Supabase production readiness was blocked because the remote project was
missing local migration:

`supabase/migrations/20260627191000_add_admin_feature_flag_toggle_rpc.sql`

This is a production backend mutation. It was applied after the user supplied
explicit approval in this thread on 2026-06-30: `Supabase db push deploy
migrate`.

## Migration Summary

The migration creates or replaces `admin_set_feature_flag(text, boolean, text)`.

Behavior:

- Requires `assert_admin_permission('feature_flags.manage')`.
- Rejects blank feature flag keys.
- Rejects blank change reasons.
- Updates an existing `feature_flags` row.
- Writes an `admin.feature_flag.updated` audit log.
- Revokes execution from `public` and `anon`.
- Grants execution to `authenticated`.

## Current Evidence

| Check | Status | Evidence |
| --- | --- | --- |
| Local migration validation | Pass | `docs/release/supabase_migration_validation_2026-06-30_after_approval.txt` |
| Local backend contract tests | Pass | `docs/release/supabase_contract_test_2026-06-30_after_approval.txt` |
| Edge auth contract UAT | Pass | `scripts/collect_edge_auth_contract_uat.sh` |
| Linked advisors | Pass | `docs/release/supabase_advisors_gate_2026-06-30_after_db_push.txt` |
| Linked migration apply | Pass | `docs/release/supabase_manual_migration_apply_2026-06-30.json`; direct `supabase db push` was blocked by tenant allow-listing before applying changes |
| Edge Function deploy | Pass | `docs/release/supabase_functions_deploy_2026-06-30_after_manual_db_apply_retry.txt`; all ten configured functions deployed |
| Linked migration history | Pass | `docs/release/supabase_migration_history_probe_2026-06-30_after_manual_apply.json`; remote version `20260627191000` is present |
| Linked schema inventory | Pass | `docs/release/supabase_schema_inventory_2026-06-30_after_db_push.json`; expected 183, remote 183, missing 0 |
| Linked readiness | Pass | `docs/release/supabase_production_readiness_2026-06-30_latest.txt`; Stripe secrets deferred for current scope |
| Supabase go-live | Pass | `docs/release/supabase_go_live_gate_2026-06-30_latest.json`; no Supabase blocker keys |

## Approval Checklist

- [x] Release owner approves applying migration `20260627191000`.
- [x] Production backend operator confirms the target project ref.
- [x] Operator confirms a rollback/restore plan appropriate for the linked project.
- [x] Operator runs the approved Supabase migration path.
- [x] Operator deploys the configured Edge Functions.
- [x] Operator reruns:
  - `scripts/supabase_schema_inventory.sh --json`
  - `scripts/supabase_production_readiness.sh`
  - `scripts/supabase_go_live_gate.sh --json`
  - `SUPABASE_EVIDENCE_BUNDLE_DIR=.cache/supabase_go_live_evidence/<timestamp> scripts/supabase_go_live_evidence_bundle.sh`
- [x] Evidence is attached to the final release packet.

## Post-Apply State

After applying the migration and deploying functions, the correct release status
is:

- `scripts/release_status.sh --json`: may report `GO` for local release
  artifacts and approval records.
- `scripts/supabase_go_live_gate.sh --json`: now reports `GO` after setting
  `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON`. Stripe secrets are deferred for the
  current release scope and can be required later with
  `SUPABASE_READY_DEFER_STRIPE=0`.
