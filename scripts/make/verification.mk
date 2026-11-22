# Cross-product source and tooling checks.
.PHONY: collect-product-boundary-scan collect-product-boundary-scan-json revolut-design-authority revolut-design-authority-json
.PHONY: source-integrity source-integrity-json qa-tooling-test cover-catalog-test
.PHONY: public-photography-check

collect-product-boundary-scan:
	@./scripts/collect_product_boundary_scan.sh

collect-product-boundary-scan-json:
	@./scripts/collect_product_boundary_scan.sh --json


revolut-design-authority:
	@python3 scripts/qa/revolut_design_authority.py

revolut-design-authority-json:
	@python3 scripts/qa/revolut_design_authority.py --json

source-integrity:
	@./scripts/source_integrity_gate.sh

source-integrity-json:
	@./scripts/source_integrity_gate.sh --json

qa-tooling-test:
	@python3 scripts/tests/release_evidence_test.py
	@python3 scripts/qa/managed_archive_source_inputs_test.py
	@python3 scripts/hardening/release_gate_test.py
	@python3 scripts/hardening/v2_source_test.py
	@python3 scripts/tests/test_collect_release_candidate.py
	@python3 scripts/tests/test_collect_ci_policy.py
	@python3 scripts/tests/cloudflare_native_build_config_test.py
	@python3 scripts/tests/client_diagnostic_identity_test.py
	@python3 scripts/tests/ios_delivery_contract_test.py
	@python3 scripts/tests/ios_workflow_contract_test.py
	@python3 scripts/tests/candidate_runner_test.py
	@python3 scripts/tests/integrated_candidate_runner_test.py
	@python3 scripts/tests/recovery_list_source_test.py
	@python3 scripts/tests/group_summary_source_test.py
	@python3 scripts/tests/payment_decoding_source_test.py
	@python3 scripts/tests/payment_intent_source_test.py
	@python3 scripts/tests/android_backup_policy_test.py
	@python3 scripts/tests/export_public_configuration_test.py
	@node --test admin-web/tests/pwa/package-pwa.test.mjs
	@node scripts/tests/admin_pwa_worker_cache_test.mjs
	@ruby scripts/tests/public_configuration_payload_test.rb
	@ruby scripts/tests/policy_configuration_payload_test.rb
	@ruby scripts/tests/asset_hygiene_integration_test.rb
	@python3 -m unittest scripts.tests.test_member_preview_fonts
	@ruby scripts/tests/public_static_routes_test.rb
	@ruby scripts/tests/public_website_links_test.rb
	@ruby scripts/tests/public_website_ci_gate_test.rb
	@ruby scripts/tests/public_lighthouse_evidence_test.rb
	@ruby scripts/tests/public_photography_test.rb
	@ruby scripts/tests/lcov_coverage_test.rb
	@ruby scripts/tests/dart_format_test.rb
	@ruby scripts/tests/native_build_provenance_test.rb
	@python3 scripts/tests/native_artifact_metadata_test.py
	@python3 scripts/tests/native_source_export_test.py
	@ruby scripts/tests/mobile_route_artifact_gate_test.rb
	@ruby scripts/tests/release_go_preflight_test.rb
	@ruby scripts/tests/release_status_fail_closed_test.rb
	@ruby scripts/tests/release_worktree_review_gate_test.rb

cover-catalog-test:
	@node --test scripts/tests/group_cover_catalog_source_test.mjs

public-photography-check:
	@NODE_PATH="$${NODE_PATH:-$(CURDIR)/tools/public-photography/node_modules}" node scripts/assets/build_public_photography.mjs --check
