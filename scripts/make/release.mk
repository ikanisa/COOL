# Release evidence and manually invoked historical Cloudflare recovery.
.PHONY: uat-evidence-gate uat-evidence-gate-json record-android-sms-uat-evidence record-uat-evidence-signoff
.PHONY: uat-signoff-gate uat-signoff-gate-json release-artifact-manifest release-artifact-manifest-json
.PHONY: release-artifact-manifest-all-platforms release-artifact-manifest-all-platforms-json release-evidence-index release-evidence-index-json
.PHONY: release-approval-packet release-approval-packet-json release-approval-evidence-gate release-approval-evidence-gate-json
.PHONY: record-release-approval release-worktree-review release-worktree-review-json repo-wide-qa-uat
.PHONY: repo-wide-qa-uat-json release-status release-status-json release-secret-scan
.PHONY: cloudflare-platform-test cloudflare-platform-acceptance cloudflare-platform-acceptance-json release-go-preflight

uat-evidence-gate:
	@./scripts/release/uat_evidence_gate.sh

uat-evidence-gate-json:
	@./scripts/release/uat_evidence_gate.sh --json

record-android-sms-uat-evidence:
	@./scripts/release/record_android_sms_uat_evidence.sh $(ARGS)

record-uat-evidence-signoff:
	@./scripts/release/record_uat_evidence_signoff.sh $(ARGS)

uat-signoff-gate:
	@./scripts/release/uat_signoff_gate.sh

uat-signoff-gate-json:
	@./scripts/release/uat_signoff_gate.sh --json

release-artifact-manifest:
	@./scripts/release/release_artifact_manifest.sh

release-artifact-manifest-json:
	@./scripts/release/release_artifact_manifest.sh --json

release-artifact-manifest-all-platforms:
	@./scripts/release/release_artifact_manifest.sh --all-platforms

release-artifact-manifest-all-platforms-json:
	@./scripts/release/release_artifact_manifest.sh --all-platforms --json

release-evidence-index:
	@python3 scripts/qa/release_evidence.py index

release-evidence-index-json:
	@python3 scripts/qa/release_evidence.py index --json

release-approval-packet:
	@python3 scripts/qa/release_evidence.py packet

release-approval-packet-json:
	@python3 scripts/qa/release_evidence.py packet --json

release-approval-evidence-gate:
	@./scripts/release/release_approval_evidence_gate.sh

release-approval-evidence-gate-json:
	@./scripts/release/release_approval_evidence_gate.sh --json

record-release-approval:
	@./scripts/release/record_release_approval.sh $(ARGS)

release-worktree-review:
	@./scripts/release/release_worktree_review_gate.sh

release-worktree-review-json:
	@./scripts/release/release_worktree_review_gate.sh --json

repo-wide-qa-uat:
	@python3 scripts/qa/release_evidence.py run

repo-wide-qa-uat-json:
	@python3 scripts/qa/release_evidence.py run --json

release-status:
	@./scripts/release/release_status.sh

release-status-json:
	@./scripts/release/release_status.sh --json

release-secret-scan:
	@./scripts/release/release_secret_scan.sh


cloudflare-platform-test:
	@cd deploy/platform-api && npm test
	@node scripts/qa/recovery17_ci.mjs
	@node --test scripts/tests/platform_health_probe_test.mjs
	@node --test scripts/tests/public_configuration_apply_test.mjs scripts/tests/policy_configuration_update_test.mjs
	@node --test scripts/tests/atomic_d1_restore_test.mjs
	@node --test scripts/tests/recovery12_test.mjs
	@node --test scripts/tests/recovery13_test.mjs
	@node --test scripts/tests/recovery15_test.mjs
	@node --test scripts/tests/momo_release_candidate_test.mjs
	@node --test scripts/tests/approved_toolchain_test.mjs scripts/tests/approved_toolchain_snapshot_test.mjs

cloudflare-platform-acceptance:
	@python3 scripts/qa/release_evidence.py platform
cloudflare-platform-acceptance-json:
	@python3 scripts/qa/release_evidence.py platform --json
release-go-preflight:
	@./scripts/release/release_go_preflight.sh
