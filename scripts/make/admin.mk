# React Admin build, local smoke, and artifact/hosting checks.
.PHONY: admin-web-build admin-pwa-gate admin-pwa-hosting-gate admin-pwa-hosting-gate-json
.PHONY: admin-pwa-live-gate admin-pwa-live-gate-json admin-pwa-smoke

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

admin-pwa-smoke:
	@node admin-web/tests/browser/smoke.mjs
