# Apps

## Inventory

| App | Path | Runtime | Status | Primary commands |
| --- | --- | --- | --- | --- |
| Mobile | Root app with marker docs in `apps/mobile` | Flutter, Android, iOS, web-capable Flutter target | Active | `scripts/dev/flutterw analyze --fatal-infos`, `scripts/dev/flutterw test`, `scripts/build_play_release.sh` |
| Admin | `apps/admin` | React, Vite, Supabase JS | Active | `npm --prefix apps/admin run lint`, `npm --prefix apps/admin run build:ci`, `npm --prefix apps/admin run smoke:admin-browser`, `npm --prefix apps/admin run smoke:admin-search` |
| Website | `apps/website` | Vite static site | Active | `npm --prefix apps/website run build`, `npm --prefix apps/website run preview` |
| PWA | `apps/pwa` | Cloudflare Pages stub | Retired/fail-closed | `make pwa-check` |
| Future venue dashboard | Not present | Not applicable | Not active | Must meet product registry criteria before creation. |
| Future agent console | Not present | Not applicable | Not active | Must meet agent permission and audit criteria before creation. |

## Build from clean checkout

1. Install Node dependencies for web apps according to the root lockfile/workspace state.
2. Install Flutter through the repository wrapper or local toolchain expected by `scripts/dev/flutterw`.
3. Configure local environment variables from `.env.example` files without committing values.
4. Run the verification set:

```bash
make verify-structure
npm --prefix apps/admin run build:ci
npm --prefix apps/website run build
scripts/dev/flutterw analyze --fatal-infos
scripts/dev/flutterw test --concurrency=4 test/integration_smoke
```

## Environment variables by app

Document names only in source control. Store values in CI secrets, operator shells, Supabase secrets, or platform-specific secure config.

| App | Required names |
| --- | --- |
| Admin | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` |
| Website | Public build-time values only. No service keys. |
| Flutter mobile | Supabase URL/anon key, Firebase/App Check config, release signing config, optional feature flags, platform notification config. Keep platform secret files out of git. |
| Release scripts | `DATABASE_URL` for direct migrations, Supabase project identifiers, signing credentials, production-only flag when applicable. |

## App quality gates

- No dead buttons, placeholder production flows, fake metrics, or hardcoded users/venues/payments.
- Every sensitive UI action must be backed by RLS/RPC/Edge Function permission checks.
- Every data screen should have loading, empty, error, success, disabled, and permission-denied behavior where relevant.
- Admin tables should use the shared table controller for search, filter, sort, pagination, and export-state consistency.
- Mobile screens should use shared design tokens and typed repositories rather than direct ad hoc backend calls in widgets.

## Mobile relocation note

The mobile app still builds from the repository root. Do not move it under `apps/mobile` as part of incidental cleanup. A safe relocation must update:

- Flutter package paths and generated localization paths.
- Android/iOS asset, signing, and Firebase references.
- CI workflows and release scripts.
- Test paths and docs tests.
- Any shell scripts that assume root `pubspec.yaml`.
