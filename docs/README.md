# COOL Documentation Index

This folder keeps current product, architecture, operations, release, and
evidence documentation for Collect. It does not contain design authority;
root `DESIGN.md` is the only design source for every app surface.

## Current Sources Of Truth

| Topic | Current file |
| --- | --- |
| Product scope and workflow | `docs/PRODUCT.md` |
| Design contract | `DESIGN.md` only |
| Architecture | `docs/ARCHITECTURE.md` |
| Database | `docs/DATABASE.md` |
| SDK and environment | `docs/ENVIRONMENT.md` |
| Supabase operations | `docs/SUPABASE_OPERATIONS_RUNBOOK.md` |
| Supabase functions | `docs/SUPABASE_FUNCTIONS.md` |
| Android SMS access | `docs/ANDROID_SMS_ACCESS.md` |
| Admin security | `docs/admin/ADMIN_SECURITY_MODEL.md` |
| Release status | `docs/release/RELEASE_STATUS.md` |
| Release approvals | `docs/release/RELEASE_APPROVALS.json` |
| UAT evidence manifest | `docs/release/UAT_EVIDENCE_MANIFEST.json` |
| Public deployments | `docs/release/LIVE_DEPLOYMENTS.json` |

## Generated Evidence Rule

Dated goalbooks, implementation reports, manual audits, route evidence, command
logs, screenshots, and generated JSON belong in `.cache/`, `output/`, or an
external evidence pack once their current facts have been merged into the files
above.

Do not use archived docs as the current product, design, or release decision.
