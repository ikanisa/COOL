# Hosted metadata readback — 30 September 2026

Read-only Supabase connector inspection confirmed the configured project
`lhbowpbcpwoiparwnwgt` (`COOL`, `us-east-2`, reported `ACTIVE_HEALTHY`). The
migration registry still contains **124 migrations**, ending
`20260906160000_group_cover_bank_and_atomic_creation_media`. This is hosted
registry evidence, not proof every installed definition matches its source.

`metadata.json` retains the actual registry, focused function definition hashes,
API-role execute privileges, private-table RLS/grants, feature flags, cron
metadata and deployed Edge Function version/artifact metadata. Queries read
catalogs and selected configuration only. No user, financial, receipt-body,
destination, password, OTP or credential data was requested. No hosted mutation,
provider call, sign-in request or message send occurred.

Observed limits and release implications:

- `hybrid_sms_notifications` is false. The old hosted receipt-capture trigger
  still has its paused-backlog defect until the compatible new candidate is
  installed and read back.
- The new Overview and manual shadow RPCs are absent. Existing transaction and
  health definitions are older than this candidate. The five MCP tool names
  are client adapters; their actual backend RPC names and Edge Function path
  must be checked and tested through an approved operator session.
- Existing SMS outbox, attempt and confirmation tables have RLS enabled and
  no direct SELECT grant to anon, authenticated or service_role. No private
  schema policies were returned for this focused inventory; RPC authority
  remains essential.
- Five existing cron jobs are active. One is a legacy daily bank-reconciliation
  job, and none establishes the requested unattended Collect receipt runner.
  Command bodies were not exported; their hashes were retained.
- The project reports database build `17.6.1.021`, server version `17.6`.
  The current Supabase changelog was fetched from the official Markdown URL
  and retained for hosting/patch review. Hosting health does not close patch,
  source-access or workflow-security acceptance.
- Security Advisors returned six rule categories, including GraphQL schema
  exposure, callable security-definer functions and disabled leaked-password
  protection. These categories require object-specific review; they are not
  a count of confirmed exploits. Remediation links are retained in the raw
  metadata. Password-protection applicability must be evaluated against the
  actual OTP-based workflow.

`operator-preflight.log` is a separate current local bridge check. It exited 2
with `BLOCKED_STDIO_MCP`, blocked on `collect_notification_health`, and reported
zero queue mutations/provider sends. It does not demonstrate a successful
hosted read, restored session or a live shadow lifecycle. The earlier retained
shadow probe reported `SHADOW_SESSION_REQUIRED`; normal approved local sign-in
is still pending.

Actual operator Auth configuration, hosted positive/negative reads, exact body
parity after deployment, migration compatibility, sender/provider health,
authenticated browser acceptance and live lifecycle reconciliation remain open.
