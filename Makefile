SHELL := /bin/bash
FLUTTER ?= flutter
DART ?= dart
# Keep command-line/environment overrides available to the script entry points.
export FLUTTER DART

.DEFAULT_GOAL := help
.PHONY: help

help:
	@echo "Collect workspace commands"
	@echo "  make cloudflare-platform-test Manually test retained legacy Worker/D1/R2 history"
	@echo "  make flutter-clean     Run flutter clean"
	@echo "  make flutter-pub-get   Run flutter pub get"
	@echo "  make format            Format Dart sources"
	@echo "  make analyze           Run Flutter analyzer"
	@echo "  make test              Run unit/widget tests (SQL receipts require their explicit integration target)"
	@echo "  make test-history-retained Verify the recorded SQL decoder windows on VM and Chrome"
	@echo "  make test-history-current14 DEFINES='...' Run historical current14 SQL receipt consumer"
	@echo "  make admin-web-build   Build the Collect admin web console"
	@echo "  make admin-pwa-gate    Validate generated Admin PWA metadata and secret hygiene"
	@echo "  make admin-pwa-hosting-gate Validate Admin PWA static hosting headers and robots policy"
	@echo "  make admin-pwa-live-gate Validate deployed Admin PWA URL headers and PWA files"
	@echo "  make admin-pwa-smoke   Test the compiled React Admin PWA on loopback"
	@echo "  make mobile-route-render-smoke Capture representative mobile route screenshots"
	@echo "  make mobile-route-artifact-gate MOBILE_ROUTE_RENDER_EVIDENCE_DIR='...' Validate a completed mobile route capture"
	@echo "  make android-device-uat Run guarded Pixel 4a integration UAT"
	@echo "  make ios-physical-route-uat ARGS='...' Run exact-device, staging-only physical iPhone route UAT"
	@echo "  make ios-physical-lifecycle-uat ARGS='...' Run exact-device physical iPhone lifecycle UAT"
	@echo "  make ios-simulator-material-state-uat ARGS='...' Capture exact-Simulator material state evidence"
	@echo "  make ios-physical-camera-permission-uat ARGS='...' Reset only staging and run owner-assisted physical Camera recovery UAT"
	@echo "  make ios-simulator-camera-permission-uat ARGS='...' Run exact-simulator Camera denial/recovery UAT"
	@echo "  make ios-app-store-readiness-gate Validate iOS metadata, artwork, privacy, and build contracts"
	@echo "  make flutter-mobile-release-gate Validate mobile release metadata, signing review, and iOS scope"
	@echo "  make android-release-signing-preflight Check configured Android signing certificate against Play signing fingerprint"
	@echo "  make android-kotlin-plugin-compat Check Android Flutter plugins for direct Kotlin Gradle Plugin usage"
	@echo "  make uat-evidence-gate Validate sanitized human UAT evidence manifest"
	@echo "  make record-android-sms-uat-evidence ARGS='...' Safely attach sanitized Android SMS UAT scenario evidence"
	@echo "  make record-uat-evidence-signoff ARGS='...' Safely record one UAT persona or release-owner signoff"
	@echo "  make uat-signoff-gate Validate human UAT release-owner signoff"
	@echo "  make release-artifact-manifest Verify release artifacts and write SHA-256 manifest"
	@echo "  make release-artifact-manifest-all-platforms IOS_RELEASE_ARCHIVE_PATH='...' Verify Android, Admin, public, and unsigned iOS artifacts"
	@echo "  make release-evidence-index Validate release evidence bundle auditability"
	@echo "  make release-approval-packet Print current pending approval packet"
	@echo "  make release-approval-evidence-gate Validate signed release approval manifest"
	@echo "  make record-release-approval ARGS='...' Safely record one signed release approval"
	@echo "  make release-worktree-review Validate release branch/worktree review status"
	@echo "  make collect-product-boundary-scan Validate Collect app product-boundary copy"
	@echo "  make source-integrity Check asset hashes, fixture isolation, secrets and product boundaries"
	@echo "  make repo-wide-qa-uat  Run strict repo-wide QA/UAT production-readiness gate"
	@echo "  make verify            Run format check, analyzer, and tests"
	@echo "  make release-status    Summarize strict release status without printing secrets"
	@echo "  make release-status-json Output strict release status as JSON without secrets"
	@echo "  make release-secret-scan Run redacted release secret scan"

include scripts/make/member.mk
include scripts/make/admin.mk
include scripts/make/verification.mk
include scripts/make/release.mk
include scripts/make/supabase.mk
