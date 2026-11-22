# Managed backend contracts and explicitly selected PostgreSQL fixtures.
.PHONY: supabase-inventory supabase-historical-inventory supabase-schema-test supabase-historical-schema-test supabase-data-test
.PHONY: supabase-test supabase-source-test supabase-current-native supabase-current-transfer-test
.PHONY: burimunsi-postgres-test supabase-writer-journal-postgres-test supabase-current16-integration-native supabase-admin-consumers-test

supabase-inventory:
	@node scripts/supabase/current-inventory.mjs .

supabase-historical-inventory:
	@node scripts/supabase/inventory.mjs .

supabase-schema-test:
	@$(MAKE) supabase-current-native

# Historical original-schema qualification requires its reviewed source checkout.
supabase-historical-schema-test:
	@node scripts/supabase/test_schema.mjs

supabase-data-test:
	@node --test scripts/supabase/data_stage.test.mjs

supabase-test:
	@$(MAKE) supabase-source-test
	@$(MAKE) supabase-current-native
	@$(MAKE) supabase-current-transfer-test
	@$(MAKE) supabase-admin-consumers-test

# No database/provider claim: these are current source and transport contracts.
supabase-source-test:
	@python3 supabase/schema-src/generate_baseline.py --check
	@node scripts/supabase/compile-retention-manifest-catalog.mjs --check
	@python3 supabase/templates/build_templates.py --check
	@python3 supabase/templates/validate_templates.py --check
	@python3 -m unittest scripts.supabase.test_cutover_gate scripts.supabase.test_admin_build_config scripts.tests.client_diagnostic_identity_test
	@python3 -m unittest scripts.supabase.test_cloud_migration_preflight
	@python3 -m unittest scripts.supabase.test_aggregate_inventory_reconcile
	@python3 -m unittest scripts.supabase.test_catalogue_reconciliation
	@python3 -m unittest scripts.supabase.test_catalogue_capture
	@node --test scripts/supabase/deployment-profile.test.mjs scripts/supabase/cloud-release/retained-source.test.mjs
	@node --test --test-concurrency=1 scripts/supabase/testing/cloud-binder-fixture.test.mjs
	@python3 -m unittest scripts.supabase.testing.test_qualification_source_manifest
	@node --test deploy/managed-native-ingress/worker.test.mjs
	@node --test deploy/managed-native-ingress/handler-integration/handler-integration.test.mjs
	@node --test --test-concurrency=1 supabase/managed-native-ingress/nonce-ledger.test.mjs
	@node --test --test-concurrency=1 supabase/managed-deployment-identity/bind-managed.test.mjs
	@node --test scripts/supabase/testing/buri-isolated-pg/report.test.mjs
	@cd deploy/managed-sms && python3 test/verify_source_tests_test.py && python3 test/verify_source_tests.py
	@node --test scripts/supabase/atomic_cloud_migration.test.mjs
	@node --test scripts/supabase/cloud-release/writer-journal-plan.test.mjs scripts/supabase/cloud-release/writer-journal-pg.test.mjs
	@node --test scripts/supabase/managed-storage-archive-v2/*.test.mjs
	@node --test scripts/supabase/cloud-data-transfer/compile.test.mjs scripts/supabase/cloud-data-transfer/existing-storage.test.mjs
	@node --test scripts/supabase/data-contracts.test.mjs
	@node scripts/tests/payment_evidence_reveal_test.mjs
	@node --test scripts/supabase/run_edge_node_tests.test.mjs scripts/supabase/testing/curated-platform-fixture.test.mjs scripts/supabase/testing/batch-capacity.test.mjs
	@node --test scripts/supabase/testing/current16-integration.test.mjs
	@node --test scripts/supabase/jobs-config-contracts.test.mjs scripts/supabase/email_jobs_operator.test.mjs
	@cd supabase/functions && "$${COLLECT_DENO:-deno}" test --frozen --lock=deno.lock _shared/tests/email-jobs.test.ts
	@cd supabase/functions && "$${COLLECT_DENO:-deno}" test --frozen --allow-env --lock=deno.lock ../../deploy/collect-sms/test/edge.test.ts
	@node scripts/supabase/run_edge_node_tests.mjs
	@node --test deploy/platform-admin/test/backend-selection.test.mjs deploy/platform-admin/test/supabase-transport.test.mjs deploy/platform-admin/test/supabase-transport-bounded.test.mjs deploy/platform-admin/test/human-parent.test.mjs test/local-challenge-parent.test.mjs
	@output="$$(mktemp "$${TMPDIR:-/tmp}/collect-commission-deno.XXXXXXXX")" || exit 1; trap 'rm -f -- "$$output"' EXIT; "$${COLLECT_DENO:-deno}" --version | grep -Eq '^deno 2[.]9[.]6 ' || exit 1; "$${COLLECT_DENO:-deno}" test --frozen --lock=supabase/functions/deno.lock --reporter=tap scripts/supabase/device-commissioning/edge-smoke.test.ts > "$$output" 2>&1; result=$$?; cat "$$output"; test "$$result" -eq 0 && grep -Fqx 'ok 1 - synthetic Edge request signs and verifies commissioning receipt and acknowledgement' "$$output" && grep -Fqx '1..1' "$$output"
	@cd supabase/functions && "$${COLLECT_DENO:-deno}" task check

# Verify the Cloud bootstrap and SMS helper paths on socket-only PostgreSQL 17.
supabase-current-native:
	@node scripts/supabase/cloud-release/initial-account-bootstrap.test.mjs
	@node --test scripts/supabase/cloud-release/sms-helper-paths.test.mjs scripts/supabase/cloud-release/burimunsi-principal-scope-index.test.mjs

# Synthetic, socket-only PostgreSQL fixtures. The selected PG17 binary path
# must be physical and tests must run as a non-root user. Fixtures require the
# physical /private/tmp (macOS) or /tmp (Linux) and remove only owned clusters.
supabase-current-transfer-test:
	@test "$$(id -u)" -ne 0
	@test -n "$${COLLECT_SYNTHETIC_PG_BIN:-}"
	@test "$$(cd "$$COLLECT_SYNTHETIC_PG_BIN" && pwd -P)" = "$$COLLECT_SYNTHETIC_PG_BIN"
	@command -v openssl >/dev/null
	@output="$$(mktemp "$${TMPDIR:-/tmp}/collect-current-transfer.XXXXXXXX")" || exit 1; trap 'rm -f -- "$$output"' EXIT; node --test --test-concurrency=1 --test-timeout=180000 --test-reporter=tap scripts/supabase/current-pg-transfer/reconcile.test.mjs scripts/supabase/current-pg-transfer/identity-mapping/identity.test.mjs scripts/supabase/managed-cloud-migrations/provider-ca.test.mjs scripts/supabase/managed-cloud-migrations/operator.test.mjs scripts/supabase/managed-cloud-migrations/operator-pg.test.mjs scripts/supabase/managed-cloud-migrations/event-trigger-preimage.test.mjs scripts/supabase/managed-cloud-migrations/migration-postconditions.test.mjs scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs scripts/supabase/current-pg-transfer/test-support/lifecycle.test.mjs scripts/supabase/device-commissioning/fixture.test.mjs scripts/supabase/current-pg-transfer/object-transfer/transfer.test.mjs scripts/supabase/current-pg-transfer/object-transfer/scope-rebind.test.mjs scripts/supabase/current-pg-transfer/object-transfer/supabase-adapter.test.mjs scripts/supabase/current-pg-transfer/business-import/import.test.mjs scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/consistency.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/native-readiness-v3/diagnostic.test.mjs scripts/supabase/current-pg-transfer/financial-import/import.test.mjs scripts/supabase/current-pg-transfer/native-sms-import/import.test.mjs scripts/supabase/retention-convergence/user-id-forward.test.mjs scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs scripts/supabase/retention-convergence/history-plan.test.mjs scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.test.mjs scripts/supabase/retention-convergence/deferred-mfa/history-proposal.test.mjs supabase/functions/_shared/tests/burimunsi/native-sms-ledger.test.mjs supabase/managed-deployment-identity/bind-managed-pg17.test.mjs scripts/supabase/device-commissioning/synthetic-transport.test.mjs supabase/managed-cloud-stopped-recovery/evidence.test.mjs > "$$output" 2>&1; result=$$?; cat "$$output"; test "$$result" -eq 0 && grep -qx '# tests [1-9][0-9]*' "$$output" && grep -qx '# fail 0' "$$output" && grep -qx '# cancelled 0' "$$output" && grep -qx '# skipped 0' "$$output" && grep -qx '# todo 0' "$$output" && for expected in 'isolated PostgreSQL reconciliation' 'managed reconciliation admits only the pinned target, TLS root and verified peer' 'connected clients with startup options are refused' 'owner-approved identity mapping holds both existing principals' 'encrypted quarantine on disposable PostgreSQL 17' 'SIGTERM stops a confirmed server before removing its fixture' 'provider database CA is a valid self-signed root with the pinned DER fingerprint' 'canonical input, exact project and clean environment are required before connecting' 'CLI reports or reconciles commit with closed-stdout' 'commissioning receipt transaction fixture' 'exact immutable ciphertext is copied once with encrypted durable intent and receipt' 'synthetic owner rebind reproduces Storage fingerprints while preserving ciphertext identity' 'actual adapter reads, creates once and verifies synthetic protected bytes' 'HTTPS client rejects a self-signed loopback server' 'mutating an approved plan cannot redirect import or lost-ack reconciliation' 'count-only financial graph inventory on owned PostgreSQL 17' 'financial consistency is aggregate-only and read-only on owned PostgreSQL 17' 'selected native source prerequisites are aggregate-only on owned PostgreSQL 17' 'synthetic posted financial graphs transfer atomically with cloud-primary mapping' 'synthetic accepted native SMS history and posted financial graph' 'forward-only retention user ID correction on owned PostgreSQL 17' 'synthetic full chain refuses divergent originals and runs pinned candidates without writing history' 'history candidate keeps divergent originals unrecorded and uses distinct ordered versions' 'all pinned non-WIP predecessors execute in order while both MFA sources remain absent' 'deferred proposal keeps every non-WIP source action without inventing history' 'a coherently mapped replay with an existing complete financial link performs no second write' 'managed candidate on native PostgreSQL 17 without a postgres superuser' 'a correctly serialized v2-style digest cannot authorize the v3 executor' 'diagnostics rechecks after history insertion' 'notification rechecks after history insertion' 'signed commissioning transport with durable synthetic PostgreSQL receipts' 'managed stopped-work evidence remains non-authorizing with synthetic PG snapshots'; do grep -Eq "^[[:space:]]*ok [0-9]+ - $$expected$$" "$$output" || exit 1; done

burimunsi-postgres-test:
	@node --test --test-concurrency=1 scripts/supabase/cloud-release/burimunsi-member-listing.test.mjs scripts/supabase/cloud-release/burimunsi-payment-sms.test.mjs scripts/supabase/cloud-release/burimunsi-payment-reference.test.mjs scripts/supabase/cloud-release/burimunsi-runtime-grants.test.mjs scripts/supabase/cloud-release/recorded-history.test.mjs scripts/supabase/cloud-release/burimunsi-observation-reconcile.test.mjs
	@$(MAKE) supabase-writer-journal-postgres-test

supabase-writer-journal-postgres-test:
	@node scripts/supabase/cloud-release/chain.test.mjs --managed-lifecycle --text-subjects --writer-journal-release

# Historical original16 only. Requires its reviewed checkout, owned cluster and
# fresh output path documented in scripts/supabase/testing/current16-integration.md.
supabase-current16-integration-native:
	@node scripts/supabase/testing/current16-integration.mjs

# Current frontend-host and CLI consumers; no legacy business backend is run.
supabase-admin-consumers-test:
	@cd deploy/platform-admin && npm ci --ignore-scripts --no-audit --no-fund
	@node --test deploy/platform-admin/test/*.test.mjs
	@cd tools/collect-admin-mcp && npm run check && npm test
	@cd tools/notification-operator && node --test --test-concurrency=1 test/operator.test.mjs test/mcp.test.mjs test/transport.test.mjs test/auth.test.mjs
