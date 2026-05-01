# Infra

Infrastructure and operational configuration should live here once it is not
owned by a single app, Supabase function, or release script.

## Target folders

- `ci/` — reusable CI configuration and policy documentation.
- `config/` — environment contracts, config schemas, and deployment mappings.
- `monitoring/` — dashboards, alerts, SLOs, and observability contracts.

## Current source locations

- GitHub Actions workflows: `.github/workflows`.
- Release and validation scripts: `scripts`.
- Supabase local/remote config: `supabase/config.toml`.
- Operational docs: `docs/OPERATIONAL_OBSERVABILITY.md` and
  `docs/qa_release_readiness.md`.

Keep secret values out of this folder. Store only schemas, variable names,
runbooks, and non-sensitive examples.
