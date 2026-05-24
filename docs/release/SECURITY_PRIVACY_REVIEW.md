# Collect Security And Privacy Review

Audit date: 2026-05-24

Security/privacy status: LOCAL CODE-OWNED CHECKS PASS; production launch
remains NO-GO until trusted Supabase verification is restored, CAPTCHA/bot
protection and HIBP leaked-password protection are resolved, Free-plan/PITR
risks are resolved or validly exceptioned where allowed, and human UAT signoff
is recorded.

| Area | Status | Evidence |
| --- | --- | --- |
| Client secrets | Pass by focused tests | Security hygiene tests scan repository text for obvious API key, token, JWT, and database URL patterns. |
| Local env files | Pass | Tests confirm `.env`, `.env.local`, and `.env.json` remain untracked/ignored. |
| Codex env config | Pass | `.codex/environments/environment.toml` is placeholder-only and tested for empty sensitive values. |
| Secret scan tooling | Pass with local fallback | `make release-secret-scan` prefers `gitleaks detect --redact`; because `gitleaks` is not installed here, it ran the tracked/untracked release-file fallback scan without printing matched values. |
| Android SMS permissions | Pass | Production manifest excludes `READ_SMS` and `RECEIVE_SMS`; restricted permissions are isolated to `internal_receiver` and guarded by tests. |
| Public privacy | Pass by contract/static tests; UAT pending | Public profile and payment-feed tests use safe views and avoid raw SMS/parser JSON exposure. Live public UAT still needs signoff. |
| RLS coverage | Pass in latest inventory | Latest evidence bundle reports RLS `28/28` on public base tables. |
| Linked Supabase readiness | Blocked on latest runner | Earlier linked readiness passed, but latest release refresh reports `database_connectivity`; code-owned readiness must be rerun from trusted linked query mode or an allow-listed database path. |
| Edge Function auth contract | Pass locally | `make supabase-edge-auth-uat` passes and is captured as `edge_auth_contract_uat.txt`; remote endpoint and secret-name probes remain blocked by `database_connectivity`. |
| Strict Supabase readiness | Blocked/NO-GO | Latest gate is blocked by `database_connectivity`; earlier strict evidence also showed CAPTCHA/bot protection disabled, HIBP leaked-password protection disabled, Free-plan organization, and PITR disabled. |
| Raw SMS reveal | UAT pending | Raw SMS is protected by contract tests; live reveal permission/reason/audit behavior still needs role-based UAT evidence. |
| Parser/allocation boundary | Pass | Tests confirm the parser extracts facts while posting/allocation remains deterministic and scoped. |
| Ledger immutability | Pass by contract scan | Ledger protection is covered by Supabase contract tests. |
| Duplicate posting | Pass by contract/static tests; UAT pending | Payment posting, parsed review scoping, and parser fallback tests pass; rollback-safe live edge-case UAT remains pending. |

## Required Before Release

- Restore trusted Supabase DB connectivity and rerun `make supabase-ready-strict`, `make supabase-go-live-gate-json`, and `make supabase-go-live-evidence`.
- Run `make release-secret-scan` in the release environment; install `gitleaks` there for full redacted gitleaks coverage.
- Configure Supabase CAPTCHA/bot protection and rerun `make supabase-ready-strict`.
- Upgrade to a paid Supabase plan, enable HIBP leaked-password protection with `make supabase-auth-harden`, and rerun `make supabase-ready-strict`.
- Upgrade the Supabase organization plan or record an accepted project-pause risk exception.
- Enable PITR or record the signed recovery objective exception.
- Complete live admin/security UAT for raw SMS reveal, duplicate handling, and non-admin denial paths.
