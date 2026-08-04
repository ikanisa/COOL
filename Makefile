SHELL := /bin/bash
FLUTTER ?= /Users/jeanbosco/Developer/flutter/bin/flutter
DART ?= /Users/jeanbosco/Developer/flutter/bin/dart

.PHONY: help flutter-clean flutter-pub-get format analyze test admin-web-build admin-pwa-gate admin-pwa-hosting-gate admin-pwa-hosting-gate-json admin-pwa-live-gate admin-pwa-live-gate-json admin-pwa-render-smoke mobile-route-render-smoke mobile-route-artifact-gate mobile-route-artifact-gate-json universal-contract-gate universal-contract-gate-json android-device-uat ios-physical-route-uat ios-physical-lifecycle-uat ios-physical-camera-permission-uat ios-simulator-camera-permission-uat ios-simulator-material-state-uat flutter-mobile-release-gate flutter-mobile-release-gate-json android-release-signing-preflight android-release-signing-preflight-json android-kotlin-plugin-compat android-kotlin-plugin-compat-json uat-evidence-gate uat-evidence-gate-json record-android-sms-uat-evidence record-uat-evidence-signoff uat-signoff-gate uat-signoff-gate-json release-artifact-manifest release-artifact-manifest-json release-evidence-index release-evidence-index-json release-approval-packet release-approval-packet-json release-approval-evidence-gate release-approval-evidence-gate-json record-release-approval release-worktree-review release-worktree-review-json collect-product-boundary-scan collect-product-boundary-scan-json revolut-parity-source-hygiene revolut-parity-source-hygiene-json revolut-parity-evidence-consistency revolut-parity-evidence-consistency-json revolut-parity-evidence-consistency-full revolut-parity-evidence-consistency-full-json repo-wide-qa-uat repo-wide-qa-uat-json verify release-status release-status-json release-secret-scan supabase-go-live-gate supabase-go-live-gate-json supabase-platform-packet supabase-platform-packet-json supabase-post-operator-checklist supabase-post-operator-checklist-json supabase-acceptance-matrix supabase-acceptance-matrix-json supabase-schema-inventory supabase-schema-inventory-json supabase-go-live-evidence supabase-ready supabase-ready-strict supabase-deploy supabase-auth-harden supabase-pitr-enable supabase-operational-report supabase-network-restrict supabase-logical-backup supabase-admin-uat supabase-edge-auth-uat supabase-advisors supabase-advisor-warnings

help:
	@echo "Collect workspace commands"
	@echo "  make flutter-clean     Run flutter clean"
	@echo "  make flutter-pub-get   Run flutter pub get"
	@echo "  make format            Format Dart sources"
	@echo "  make analyze           Run Flutter analyzer"
	@echo "  make test              Run Flutter tests"
	@echo "  make admin-web-build   Build the Collect admin web console"
	@echo "  make admin-pwa-gate    Validate generated Admin PWA metadata and secret hygiene"
	@echo "  make admin-pwa-hosting-gate Validate Admin PWA static hosting headers and robots policy"
	@echo "  make admin-pwa-live-gate Validate deployed Admin PWA URL headers and PWA files"
	@echo "  make admin-pwa-render-smoke Capture rendered desktop/mobile Admin PWA evidence"
	@echo "  make mobile-route-render-smoke Capture representative mobile route screenshots"
	@echo "  make mobile-route-artifact-gate Validate current mobile route evidence against DESIGN.md"
	@echo "  make universal-contract-gate Validate DESIGN.md is the sole contract"
	@echo "  make android-device-uat Run guarded Pixel 4a integration UAT"
	@echo "  make ios-physical-route-uat ARGS='...' Run exact-device, staging-only physical iPhone route UAT"
	@echo "  make ios-physical-lifecycle-uat ARGS='...' Run exact-device physical iPhone lifecycle UAT"
	@echo "  make ios-simulator-material-state-uat ARGS='...' Capture exact-Simulator material state evidence"
	@echo "  make ios-physical-camera-permission-uat ARGS='...' Reset only staging and run owner-assisted physical Camera recovery UAT"
	@echo "  make ios-simulator-camera-permission-uat ARGS='...' Run exact-simulator Camera denial/recovery UAT"
	@echo "  make flutter-mobile-release-gate Validate mobile release metadata, signing review, and iOS scope"
	@echo "  make android-release-signing-preflight Check configured Android signing certificate against Play signing fingerprint"
	@echo "  make android-kotlin-plugin-compat Check Android Flutter plugins for direct Kotlin Gradle Plugin usage"
	@echo "  make uat-evidence-gate Validate sanitized human UAT evidence manifest"
	@echo "  make record-android-sms-uat-evidence ARGS='...' Safely attach sanitized Android SMS UAT scenario evidence"
	@echo "  make record-uat-evidence-signoff ARGS='...' Safely record one UAT persona or release-owner signoff"
	@echo "  make uat-signoff-gate Validate human UAT release-owner signoff"
	@echo "  make release-artifact-manifest Verify release artifacts and write SHA-256 manifest"
	@echo "  make release-evidence-index Validate release evidence bundle auditability"
	@echo "  make release-approval-packet Print current pending approval packet"
	@echo "  make release-approval-evidence-gate Validate signed release approval manifest"
	@echo "  make record-release-approval ARGS='...' Safely record one signed release approval"
	@echo "  make release-worktree-review Validate release branch/worktree review status"
	@echo "  make collect-product-boundary-scan Validate Collect app product-boundary copy"
	@echo "  make revolut-parity-source-hygiene Validate exclusive Inter, official assets, fixture isolation, product boundaries, and secret hygiene"
	@echo "  make revolut-parity-evidence-consistency Validate task/evidence registers and fail-closed audit boundaries"
	@echo "  make revolut-parity-evidence-consistency-full Also verify current coverage and release artifact hashes"
	@echo "  make repo-wide-qa-uat  Run strict repo-wide QA/UAT production-readiness gate"
	@echo "  make verify            Run format check, analyzer, and tests"
	@echo "  make release-status    Summarize strict release status without printing secrets"
	@echo "  make release-status-json Output strict release status as JSON without secrets"
	@echo "  make release-secret-scan Run redacted release secret scan"
	@echo "  make supabase-go-live-gate Final Supabase go-live approval gate"
	@echo "  make supabase-platform-packet Print current SMS-first release blocker handoff"
	@echo "  make supabase-post-operator-checklist Print current SMS-first post-remediation checklist"
	@echo "  make supabase-acceptance-matrix Print evidence-backed Supabase acceptance matrix"
	@echo "  make supabase-schema-inventory Print live public schema contract inventory"
	@echo "  make supabase-go-live-evidence Build redacted Supabase go-live evidence bundle"
	@echo "  make supabase-ready    Check linked Supabase production readiness"
	@echo "  make supabase-deploy   Push migrations, deploy functions, then check readiness"
	@echo "  make supabase-advisors Run linked Supabase security/performance advisor gate"
	@echo "  make supabase-advisor-warnings Check warning-level Supabase advisor inventory"
	@echo "  make supabase-admin-uat Run rollback-only admin/security UAT"
	@echo "  make supabase-edge-auth-uat Run local Edge Function auth contract UAT"
	@echo "  make supabase-auth-harden Apply optional production Auth hardening"
	@echo "  make supabase-pitr-enable Apply optional billable backup add-on after explicit confirmation"
	@echo "  make supabase-operational-report Print read-only DB health and performance stats"
	@echo "  make supabase-logical-backup Create local logical DB dump"

flutter-clean:
	$(FLUTTER) clean

flutter-pub-get:
	$(FLUTTER) pub get

format:
	$(DART) format .

format-check:
	$(DART) format --set-exit-if-changed .

analyze:
	$(FLUTTER) analyze

test:
	@set -euo pipefail; \
	while IFS= read -r test_file; do \
		echo "[flutter-test] $$test_file"; \
		$(FLUTTER) test --no-pub --concurrency=1 "$$test_file"; \
	done < <(find test -name '*_test.dart' -print | sort)

admin-web-build:
	@./scripts/admin_pwa_release_build.sh

admin-pwa-gate:
	@./scripts/admin_pwa_manifest_gate.sh

admin-pwa-hosting-gate:
	@./scripts/admin_pwa_hosting_gate.sh

admin-pwa-hosting-gate-json:
	@./scripts/admin_pwa_hosting_gate.sh --json

admin-pwa-live-gate:
	@./scripts/admin_pwa_live_gate.sh

admin-pwa-live-gate-json:
	@./scripts/admin_pwa_live_gate.sh --json

admin-pwa-render-smoke:
	@./scripts/admin_pwa_render_smoke.sh

mobile-route-render-smoke:
	@./scripts/mobile_route_render_smoke.sh

mobile-route-artifact-gate:
	@./scripts/mobile_route_artifact_gate.sh

mobile-route-artifact-gate-json:
	@./scripts/mobile_route_artifact_gate.sh --json

universal-contract-gate:
	@./scripts/universal_contract_gate.sh

universal-contract-gate-json:
	@./scripts/universal_contract_gate.sh --json

android-device-uat:
	@./scripts/android_device_uat.sh

ios-physical-route-uat:
	@./scripts/ios_physical_route_uat.sh $(ARGS)

ios-physical-lifecycle-uat:
	@IOS_PHYSICAL_UAT_MODE=lifecycle \
		IOS_PHYSICAL_UAT_TEST_TARGET=integration_test/mobile_ios_lifecycle_device_uat_test.dart \
		IOS_PHYSICAL_UAT_VARIANT_NAME=physical-lifecycle-dark \
		IOS_PHYSICAL_UAT_PREBUILD=true \
		IOS_PHYSICAL_UAT_UNLOCK_WAIT_SECONDS=180 \
		./scripts/ios_physical_route_uat.sh $(ARGS)

ios-physical-camera-permission-uat:
	@IOS_PHYSICAL_UAT_MODE=camera-settings \
		IOS_PHYSICAL_UAT_TEST_TARGET=integration_test/mobile_camera_permission_device_uat_test.dart \
		IOS_PHYSICAL_UAT_VARIANT_NAME=physical-camera-settings-dark \
		IOS_PHYSICAL_UAT_MOBILE_EVIDENCE_MODE=false \
		IOS_PHYSICAL_UAT_CAMERA_PHASE=physical-settings \
		IOS_PHYSICAL_UAT_RESET_STAGING_APP=true \
		IOS_PHYSICAL_UAT_PREBUILD=true \
		IOS_PHYSICAL_UAT_UNLOCK_WAIT_SECONDS=180 \
		./scripts/ios_physical_route_uat.sh $(ARGS)

ios-simulator-camera-permission-uat:
	@./scripts/ios_simulator_camera_permission_uat.sh $(ARGS)

ios-simulator-material-state-uat:
	@IOS_UAT_MODE=state \
		IOS_UAT_TEST_TARGET=integration_test/mobile_material_state_matrix_device_uat_test.dart \
		IOS_UAT_VARIANT_NAME=material-state-dark \
		IOS_UAT_THEME_MODE=dark \
		./scripts/ios_simulator_route_uat.sh $(ARGS)

flutter-mobile-release-gate:
	@./scripts/flutter_mobile_release_gate.sh

flutter-mobile-release-gate-json:
	@./scripts/flutter_mobile_release_gate.sh --json

android-release-signing-preflight:
	@./scripts/android_release_signing_preflight.sh

android-release-signing-preflight-json:
	@./scripts/android_release_signing_preflight.sh --json

android-kotlin-plugin-compat:
	@./scripts/android_kotlin_plugin_compat_gate.sh

android-kotlin-plugin-compat-json:
	@./scripts/android_kotlin_plugin_compat_gate.sh --json

uat-evidence-gate:
	@./scripts/uat_evidence_gate.sh

uat-evidence-gate-json:
	@./scripts/uat_evidence_gate.sh --json

record-android-sms-uat-evidence:
	@./scripts/record_android_sms_uat_evidence.sh $(ARGS)

record-uat-evidence-signoff:
	@./scripts/record_uat_evidence_signoff.sh $(ARGS)

uat-signoff-gate:
	@./scripts/uat_signoff_gate.sh

uat-signoff-gate-json:
	@./scripts/uat_signoff_gate.sh --json

release-artifact-manifest:
	@./scripts/release_artifact_manifest.sh

release-artifact-manifest-json:
	@./scripts/release_artifact_manifest.sh --json

release-evidence-index:
	@./scripts/release_evidence_index.sh

release-evidence-index-json:
	@./scripts/release_evidence_index.sh --json

release-approval-packet:
	@./scripts/release_approval_packet.sh

release-approval-packet-json:
	@./scripts/release_approval_packet.sh --json

release-approval-evidence-gate:
	@./scripts/release_approval_evidence_gate.sh

release-approval-evidence-gate-json:
	@./scripts/release_approval_evidence_gate.sh --json

record-release-approval:
	@./scripts/record_release_approval.sh $(ARGS)

release-worktree-review:
	@./scripts/release_worktree_review_gate.sh

release-worktree-review-json:
	@./scripts/release_worktree_review_gate.sh --json

collect-product-boundary-scan:
	@./scripts/collect_product_boundary_scan.sh

collect-product-boundary-scan-json:
	@./scripts/collect_product_boundary_scan.sh --json

revolut-parity-source-hygiene:
	@./scripts/revolut_parity_source_hygiene_gate.sh

revolut-parity-source-hygiene-json:
	@./scripts/revolut_parity_source_hygiene_gate.sh --json

revolut-parity-evidence-consistency:
	@./scripts/revolut_parity_evidence_consistency_gate.sh --source-only

revolut-parity-evidence-consistency-json:
	@./scripts/revolut_parity_evidence_consistency_gate.sh --source-only --json

revolut-parity-evidence-consistency-full:
	@./scripts/revolut_parity_evidence_consistency_gate.sh --full

revolut-parity-evidence-consistency-full-json:
	@./scripts/revolut_parity_evidence_consistency_gate.sh --full --json

repo-wide-qa-uat:
	@./scripts/repo_wide_qa_uat.sh

repo-wide-qa-uat-json:
	@./scripts/repo_wide_qa_uat.sh --json

verify: format-check analyze test

release-status:
	@./scripts/release_status.sh

release-status-json:
	@./scripts/release_status.sh --json

release-secret-scan:
	@./scripts/release_secret_scan.sh

supabase-go-live-gate:
	@./scripts/supabase_go_live_gate.sh

supabase-go-live-gate-json:
	@./scripts/supabase_go_live_gate.sh --json

supabase-platform-packet:
	@./scripts/supabase_platform_go_live_packet.sh

supabase-platform-packet-json:
	@./scripts/supabase_platform_go_live_packet.sh --json

supabase-post-operator-checklist:
	@./scripts/supabase_post_operator_checklist.sh

supabase-post-operator-checklist-json:
	@./scripts/supabase_post_operator_checklist.sh --json

supabase-acceptance-matrix:
	@./scripts/supabase_acceptance_matrix.sh

supabase-acceptance-matrix-json:
	@./scripts/supabase_acceptance_matrix.sh --json

supabase-schema-inventory:
	@./scripts/supabase_schema_inventory.sh

supabase-schema-inventory-json:
	@./scripts/supabase_schema_inventory.sh --json

supabase-go-live-evidence:
	@./scripts/supabase_go_live_evidence_bundle.sh

supabase-ready:
	@./scripts/supabase_production_readiness.sh

supabase-ready-strict:
	@SUPABASE_READY_STRICT_PLATFORM=1 ./scripts/supabase_production_readiness.sh

supabase-deploy:
	@./scripts/supabase_deploy.sh

supabase-advisors:
	@./scripts/supabase_advisors_gate.sh

supabase-advisor-warnings:
	@./scripts/supabase_advisors_warning_inventory.sh

supabase-admin-uat:
	@./scripts/collect_admin_security_uat.sh

supabase-edge-auth-uat:
	@./scripts/collect_edge_auth_contract_uat.sh

supabase-auth-harden:
	@./scripts/supabase_apply_auth_hardening.sh

supabase-pitr-enable:
	@./scripts/supabase_apply_pitr.sh

supabase-operational-report:
	@./scripts/supabase_operational_report.sh

supabase-network-restrict:
	@./scripts/supabase_apply_network_restrictions.sh

supabase-logical-backup:
	@./scripts/supabase_logical_backup.sh
