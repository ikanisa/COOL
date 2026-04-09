# Hosted Supabase Project Deploy

This repo already contains the full COOL backend contract:

- SQL migrations under [`supabase/migrations`](../supabase/migrations)
- Edge Functions under [`supabase/functions`](../supabase/functions)
- contract smoke checks under [`scripts/supabase_contract_smoke.sh`](../scripts/supabase_contract_smoke.sh)

Use [`scripts/deploy_supabase_hosted.sh`](../scripts/deploy_supabase_hosted.sh) to
bootstrap a fresh hosted Supabase project from this repo.

## What The Script Does

1. Validates the local migration tree.
2. Links the workspace to the target hosted project.
3. Pushes every migration in `supabase/migrations`.
4. Optionally includes `supabase/seed.sql`.
5. Syncs Edge Function secrets from a local ignored `.env` file.
6. Deploys every Edge Function under `supabase/functions/**/index.ts`.
7. Optionally runs the remote contract smoke suite.

## Required Inputs

- `PROJECT_REF`
- `SUPABASE_DB_PASSWORD`

The current Supabase CLI profile, or `SUPABASE_ACCESS_TOKEN` in your shell,
must also have project-level access to `PROJECT_REF`.

For function secret sync, create a local ignored file at:

- `supabase/functions/.env`

Start from:

- [`supabase/functions/.env.example`](../supabase/functions/.env.example)

## Example

```bash
PROJECT_REF=your-project-ref \
SUPABASE_DB_PASSWORD=your-db-password \
FUNCTIONS_ENV_FILE=supabase/functions/.env \
RUN_SMOKE=1 \
bash scripts/deploy_supabase_hosted.sh
```

## Optional Flags

- `INCLUDE_SEED=0` skips `seed.sql`
- `SKIP_SECRETS=1` skips `supabase secrets set`
- `SKIP_FUNCTIONS=1` skips Edge Function deployment
- `SKIP_DB_PUSH=1` skips migration apply
- `RUN_SMOKE=0` skips remote smoke validation
- `PRUNE_FUNCTIONS=1` deletes remote functions that do not exist locally

## App Runtime Reminder

This script deploys the backend. The Flutter app still needs the hosted project
URL and anon key at build time. The release/build scripts now resolve those
from the flavor-specific client env keys:

- `SUPABASE_STAGING_URL`
- `SUPABASE_STAGING_ANON_KEY`
- `SUPABASE_PRODUCTION_URL`
- `SUPABASE_PRODUCTION_ANON_KEY`

At runtime they are still passed to Flutter as `SUPABASE_URL` and
`SUPABASE_ANON_KEY`, and consumed by
[`lib/core/config/env_config.dart`](../lib/core/config/env_config.dart).
