# Architecture Overview

Cool is a production-only, Supabase-backed platform with Flutter mobile, React admin, public website, Supabase Edge Functions, database migrations, and documented boundaries for future agents and integrations.

## Source-of-truth surfaces

| Surface | Source of truth | Production status |
| --- | --- | --- |
| Flutter mobile app | Root `pubspec.yaml`, `lib/`, `android/`, `ios/`, `web/`, `test/` plus `apps/mobile` ownership docs | Active. Root layout remains intentional until a dedicated move updates every script and workflow. |
| Admin web app | `apps/admin` | Active React/Vite admin surface. UI permissions are convenience checks; Supabase RLS/RPCs enforce access. |
| Public website | `apps/website` | Active static Vite site for landing, legal, and account deletion pages. |
| PWA | `apps/pwa` | Retired Cloudflare Pages stub. Fail-closed and not an active product surface. |
| Supabase backend | `supabase/migrations`, `supabase/functions`, `supabase/tests`, `supabase/policies`, `supabase/docs` | Active schema, RLS, RPC, Edge Function, and database contract layer. |
| Agents | `agents` | Contracts only. No production runtime is present. |
| Integrations | `integrations`, `supabase/functions`, `lib/core/services`, `lib/features/momo/services` | Active adapters live close to their runtime until they become shared. |
| Shared packages | `packages` | Boundary packages exist; only move logic into them when it is genuinely reusable and tested. |
| Operations and release | `scripts`, `infra`, `.github/workflows`, `docs` | Active CI, QA, deploy, migration, and release helpers. |

## Repository map

```text
apps/          Independent web app surfaces and mobile ownership marker.
packages/      Shared contracts, utilities, domain, auth, payment, UI, analytics packages.
supabase/      Database migrations, Edge Functions, policies, seeds, tests, backend docs.
agents/        Future agent operating assets. Currently fail-closed contracts only.
integrations/  Future shared channel/payment adapters and setup docs.
docs/          Architecture, security, release, operations, testing, and integration runbooks.
scripts/       Dev, QA, deploy, migration, release, and verification commands.
infra/         CI, configuration, deployment, and monitoring ownership notes.
lib/           Current Flutter app implementation until mobile relocation is completed.
test/          Flutter unit, widget, docs, and integration smoke tests.
```

## Boundary rules

- App code owns presentation, local state, routing, and user interaction.
- Supabase owns authorization, tenant isolation, sensitive writes, payment status transitions, and audit trails.
- Shared packages must contain reusable contracts only. Do not move single-app code into shared packages for tidiness alone.
- Edge Functions must authenticate, authorize, validate input, rate limit where relevant, avoid leaking secrets, and log safely.
- Payment instructions are never payment confirmations. Status transitions require verified evidence or authorized manual action.
- Agent tools, when added, must call backend-enforced permissions and emit audit events for sensitive actions.

## Production-only operating model

There is no staging project at the time of this pass. Production-only mode is explicit:

```bash
COOL_PRODUCTION_ONLY_RELEASE=1
```

That mode only skips staging/project separation checks. It does not relax authorization, RLS, audit, migration review, backup, test evidence, or operator approval requirements.

## Core verification set

```bash
make verify-structure
npm --prefix apps/admin run build:ci
npm --prefix apps/website run build
bash scripts/migrations/validate_supabase_migrations.sh
deno check $(find supabase/functions -type f -name '*.ts' | sort)
scripts/dev/flutterw analyze --fatal-infos
```
