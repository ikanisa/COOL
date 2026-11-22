# COOL Documentation Index

This folder keeps current product, architecture, operations, release, and
evidence documentation for Collect. It does not contain design authority. The
installed `revolut-design` skill is the sole design authority. Repository
screenshots, contracts and reports are product evidence only.

## Documentation map

These files describe source and intended controls. Check the exact candidate,
deployed configuration and current evidence before treating a statement as live.

| Topic | Current file |
| --- | --- |
| Product scope and workflow | `docs/PRODUCT.md` |
| Design authority | `revolut-design` skill |
| Visual and interaction review | Owner-selected `revolut-design` skill and current route/state evidence |
| Architecture | `docs/ARCHITECTURE.md` |
| Database | `docs/DATABASE.md` |
| SDK and environment | `docs/ENVIRONMENT.md` |
| Supabase operations | `docs/SUPABASE_OPERATIONS_RUNBOOK.md` |
| Supabase functions | `docs/SUPABASE_FUNCTIONS.md` |
| Android SMS access | `docs/ANDROID_SMS_ACCESS.md` |
| React Admin build | [`admin-web/README.md`](../admin-web/README.md) |
| React Admin architecture | [Browser, server and BuriMunsi access](admin/ADMIN_ARCHITECTURE_PLAN.md) |
| Full-stack audit and refactoring | [Audit findings](assessments/2026-11-18-full-stack-code-audit.md) · [Implementation plan](plans/2026-11-18-collect-cleanup-refactoring.md) |
| Admin security | `docs/admin/ADMIN_SECURITY_MODEL.md` |
| Privacy review | `docs/PRIVACY_AND_COMPLIANCE_NOTES.md` |
| Release commands | [Make targets](../scripts/make/release.mk) · [Release gates and recorders](../scripts/release/) |
| Release status | `docs/release/RELEASE_STATUS.md` |
| Release approvals | `docs/release/RELEASE_APPROVALS.json` |
| UAT evidence manifest | `docs/release/UAT_EVIDENCE_MANIFEST.json` |
| Public deployments | `docs/release/LIVE_DEPLOYMENTS.json` |

## Evidence and historical material

Dated reports, input captures, hashes and proof packets are point-in-time
evidence. Historical receipts can refer to executable inputs removed from this
working tree. Git history retains the tracked inputs.
Use the [current Supabase operations runbook](SUPABASE_OPERATIONS_RUNBOOK.md)
for Collect Cloud configuration and validation.
Local tests, builds and drafts do not establish hosted, device, provider, store or
accountable-release acceptance.
