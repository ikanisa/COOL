SHELL := /bin/bash
FLUTTER ?= /Volumes/PRO-G40/flutter_3_44/bin/flutter
DART ?= /Volumes/PRO-G40/flutter_3_44/bin/dart

.PHONY: help flutter-clean flutter-pub-get format analyze test admin-web-build verify release-status release-status-json release-secret-scan supabase-go-live-gate supabase-go-live-gate-json supabase-platform-packet supabase-platform-packet-json supabase-platform-exception-gate supabase-post-operator-checklist supabase-post-operator-checklist-json supabase-acceptance-matrix supabase-acceptance-matrix-json supabase-schema-inventory supabase-schema-inventory-json supabase-go-live-evidence supabase-ready supabase-ready-strict supabase-deploy supabase-auth-harden supabase-pitr-enable supabase-operational-report supabase-network-restrict supabase-logical-backup supabase-admin-uat supabase-edge-auth-uat supabase-advisors supabase-advisor-warnings

help:
	@echo "Collect workspace commands"
	@echo "  make flutter-clean     Run flutter clean"
	@echo "  make flutter-pub-get   Run flutter pub get"
	@echo "  make format            Format Dart sources"
	@echo "  make analyze           Run Flutter analyzer"
	@echo "  make test              Run Flutter tests"
	@echo "  make admin-web-build   Build the Collect admin web console"
	@echo "  make verify            Run format check, analyzer, and tests"
	@echo "  make release-status    Summarize strict release status without printing secrets"
	@echo "  make release-status-json Output strict release status as JSON without secrets"
	@echo "  make release-secret-scan Run redacted release secret scan"
	@echo "  make supabase-go-live-gate Final Supabase go-live approval gate"
	@echo "  make supabase-platform-packet Print operator handoff for strict platform blockers"
	@echo "  make supabase-platform-exception-gate Validate signed platform risk exceptions"
	@echo "  make supabase-post-operator-checklist Print redacted post-remediation verification checklist"
	@echo "  make supabase-acceptance-matrix Print evidence-backed Supabase acceptance matrix"
	@echo "  make supabase-schema-inventory Print live public schema contract inventory"
	@echo "  make supabase-go-live-evidence Build redacted Supabase go-live evidence bundle"
	@echo "  make supabase-ready    Check linked Supabase production readiness"
	@echo "  make supabase-deploy   Push migrations, deploy functions, then check readiness"
	@echo "  make supabase-advisors Run linked Supabase security/performance advisor gate"
	@echo "  make supabase-advisor-warnings Check warning-level Supabase advisor inventory"
	@echo "  make supabase-admin-uat Run rollback-only admin/security UAT"
	@echo "  make supabase-edge-auth-uat Run local Edge Function auth contract UAT"
	@echo "  make supabase-auth-harden Apply production Auth hardening"
	@echo "  make supabase-pitr-enable Apply billable PITR add-on after explicit confirmation"
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
	$(FLUTTER) test

admin-web-build:
	$(FLUTTER) build web -t lib/main_admin.dart --release

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

supabase-platform-exception-gate:
	@./scripts/supabase_platform_exception_gate.sh

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
