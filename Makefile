SHELL := /bin/bash

.PHONY: help admin-lint admin-build website-build web-build pwa-check migrations-check migrations-apply flutter-analyze docs-tests structure-check verify-structure

help:
	@echo "Cool workspace commands"
	@echo "  make admin-lint        Type-check the admin web app"
	@echo "  make admin-build       Build the admin web app"
	@echo "  make website-build     Build the public website"
	@echo "  make web-build         Build all web surfaces"
	@echo "  make pwa-check         Verify the retired PWA stub exists"
	@echo "  make migrations-check  Validate Supabase migrations"
	@echo "  make migrations-apply  Dry-run/apply Supabase migrations with DATABASE_URL"
	@echo "  make flutter-analyze   Run Flutter analyzer"
	@echo "  make docs-tests        Run structure/security doc tests"
	@echo "  make verify-structure  Run the safe structure verification set"

admin-lint:
	npm --prefix apps/admin run lint

admin-build:
	npm --prefix apps/admin run build

website-build:
	npm --prefix apps/website run build

web-build: admin-build website-build

pwa-check:
	test -f apps/pwa/wrangler.toml
	@echo "apps/pwa is a retired Cloudflare Pages stub, not a deployable Node app."

migrations-check:
	bash scripts/migrations/validate_supabase_migrations.sh

migrations-apply:
	bash scripts/migrations/apply_supabase_migrations.sh

flutter-analyze:
	cd apps/mobile && ../../scripts/dev/flutterw analyze

docs-tests:
	cd apps/mobile && ../../scripts/dev/flutterw test test/docs/admin_placeholder_actions_test.dart test/docs/static_headers_security_test.dart

structure-check:
	rg -n "coming soon|Coming soon|toast\\.info|TODO: wire|future: wire|Placeholder" apps/admin/src; test $$? -eq 1

verify-structure: structure-check admin-lint web-build docs-tests migrations-check flutter-analyze
