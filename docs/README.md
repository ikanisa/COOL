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
| Admin security | `docs/admin/ADMIN_SECURITY_MODEL.md` |
| Privacy review | `docs/PRIVACY_AND_COMPLIANCE_NOTES.md` |
| Release status | `docs/release/RELEASE_STATUS.md` |
| Release approvals | `docs/release/RELEASE_APPROVALS.json` |
| UAT evidence manifest | `docs/release/UAT_EVIDENCE_MANIFEST.json` |
| Public deployments | `docs/release/LIVE_DEPLOYMENTS.json` |

## Evidence and historical material

Dated reports, input captures, hashes and proof packets are point-in-time
evidence. Preserve their original bytes and referenced paths when consolidating;
identical content at two paths may support different evidence chains. Do not
present a historical snapshot as the current product, design or release decision.
Local tests, builds and drafts do not establish hosted, device, provider, store or
accountable-release acceptance.
