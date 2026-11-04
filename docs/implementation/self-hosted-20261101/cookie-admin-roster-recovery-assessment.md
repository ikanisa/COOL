# Cookie Admin roster import and recovery: source assessment

Assessment date: 2026-11-01. Scope: read-only inspection of the intended cookie Admin, retained roster UI and current local Supabase application source. This is a proposed restoration path and a list of requirements to verify. It is not authorization to alter roles or data, a completed implementation, hosted evidence, or release approval.

The inspected checkout was `/Volumes/PRO-G40/Application Data/Codex/Codex-Home/worktrees/collect-consolidation-20261101/COLLECT`, with Git HEAD `14f32d43961cd566e8834dae841ba67e475b21f5`. The checkout was shared and changing. In particular, `supabase/functions/_shared/domain/roster.js` contained another owner's unstaged candidate changes. The hashes below identify selected observed files, not a complete or atomic snapshot of the checkout. Recheck the affected inputs before using this assessment as implementation or test evidence.

## Current entrypoints and reusable pieces

- The intended cookie shell's `lib/admin/cloudflare_admin_app.dart` builds the groups list with `CloudflareCoreListPage`, and its group create/detail with `CloudflareOperatingCreatePage` and `CloudflareOperatingDetailPage`. `lib/admin/core/cloudflare_admin_core_pages.dart` exposes the generic Create group action. These are not the legacy roster dialog.
- The legacy group list action `lib/admin/core/admin_group_runtime.dart` opens `showAdminRosterImport` with `AdminRosterDraft`; the existing-group action is in `lib/admin/core/admin_detail_runtime.dart`. The list-side legacy UI checks `collections.moderate` and `users.read`. The detail action additionally checks the legacy group attributes described below.
- `lib/admin/core/admin_roster_dialog.dart`, `lib/admin/core/admin_roster_import.dart`, `lib/admin/core/admin_roster_models.dart`, `lib/admin/core/admin_roster_upload.dart`, `lib/admin/core/roster_file_parser.dart`, and the `AdminRosterGateway` interface in `lib/admin/core/admin_roster_gateway.dart` contain the existing input, review, acknowledgement, and recovery interaction and can be assessed for reuse. The legacy `CollectAdminRosterGateway` uses bearer-token transport and must not simply be installed in the cookie client.
- `lib/admin/core/cloudflare_admin_repository.dart` does not override `openRosterImport`; `lib/admin/core/admin_repository_base.dart` supplies an unsupported default. `supabase/functions/_shared/domain/admin_bridge.js` has no roster section. Registered bearer-dispatch operations are not, by themselves, proof of a working cookie journey or deployed capability.

## Authority and transaction boundaries to retain

`lib/admin/core/cloudflare_admin_transport_web.dart` creates a credentialed browser client. `lib/admin/core/cloudflare_admin_session.dart` restricts Admin request destinations and methods, supplies the CSRF and Admin request headers for authenticated mutations, captures an `authorityFence` containing a local epoch and account authority key, and reports uncertain mutation outcomes after a timeout or session change. Same-session email-proof renewal is deliberately separate from a change of actor or permissions.

`supabase/functions/_shared/domain/admin_accounts.js` checks the configured origin, resolves the host-only cookie session, checks CSRF on non-read requests, and builds a canonical actor by intersecting the projected Auth session's permissions with current Admin account permissions. `supabase/functions/_shared/domain/admin_accounts_legacy.js` exposes the host-only, HttpOnly, Secure, SameSite=Strict cookie and `accountDatabase`/account guard; the guarded batch includes the current account, session, role/grant, origin and email context. `supabase/functions/_shared/domain/admin_email_policy.js` binds independent verified-email evidence to the resolved account and actor and accepts a maximum age of 300 seconds. This proof is not a claim that the session has MFA or AAL2.

`supabase/functions/_shared/domain/roster.js` requires an Admin actor, the `roster.import` permission, and fresh Admin email. The current-source baseline `supabase/migrations/20261020134444_collect_curated_platform_baseline.sql` contains the owner role capability; effective access also depends on the principal's grant. The later `supabase/migrations/20261023002500_collect_admin_recent_email_source_upgrade.sql` checks the email context and current actor/session for the roster upload and roster guard. The legacy UI's two permissions are not interchangeable with `roster.import`. Any change to role policy requires its own authority and evidence.

A new cookie adapter and narrowly allowlisted BFF must preserve those boundaries, including authorization of reads and replay responses. The inspected `accountDatabase` wrapper applies its account guard to batches. In the inspected roster source, an already-prepared preview can be returned from `extract` before a roster-guard batch, and a review replay can return a stored preview after receipt checks; a new route needs a checked current-account/fresh-email boundary for those read/replay paths as well. Verify the exact atomicity, revocation and response behavior in the final implementation rather than assuming the wrapper guards every standalone read.

## Existing-group provenance and reservation binding

The retained detail UI offers Add reviewed members only when the legacy record is `creation_origin == 'admin_assisted'`, private, has private public status, is unarchived, uses RWF, and is not diaspora-enabled. The current baseline `collections` table has status, currency and visibility fields but no equivalent `creation_origin` or `diaspora_enabled` columns. The current cookie group projection in `supabase/functions/_shared/domain/admin_records.js` does not establish those missing facts. The inspected roster commit in `roster.js` checks an active group and share-code material, and the current roster guard checks group status and revision; those checks alone do not prove the legacy eligibility conditions.

The inspected commit also checks the reserved `collection_id` only when it is non-null. An upload reserved with a null collection can therefore select `existing` at commit without the same reservation binding. The retained UI choosing a mode is not a server-side guarantee.

Before exposing existing-group import, define and verify a trustworthy current-source provenance/eligibility contract, including how qualifying historical groups are established. Enforce the intended eligibility, mode, exact group binding, and group revision in the same transaction as the commit. A `data_json` hint or a guessed predecessor attribute is not sufficient without a proven authority and integrity contract. Keep groups with unproven eligibility unavailable; do not fabricate their attributes or expand roles.

## Recovery and legacy handoff gaps

The current operation registry in `supabase/functions/_shared/domain/operations.js` registers `admin_review_roster_import`, `admin_commit_roster_import`, `admin_get_roster_import`, `admin_stage_roster_import_intent`, and `admin_execute_roster_import_intent`, plus the four roster function endpoints. The retained draft calls seven additional operations not registered in that current dispatcher:

- `admin_save_roster_import_draft`
- `admin_recover_roster_import`
- `admin_list_interrupted_roster_imports`
- `admin_inspect_interrupted_roster_import`
- `admin_get_interrupted_roster_commit_status`
- `admin_transfer_interrupted_roster_import`
- `admin_get_roster_transfer_status`

Setting `supportsRecovery` to true without those semantics would expose a broken workflow. A complete design needs bounded encrypted server drafts, immutable request/payload hashes, checkpoint/version conflict handling, read-only inspection, explicit human affirmation, a durable transfer receipt and status lookup after an unknown outcome. It must reset prior review/submission approval on a new branch, fence old writers, and preserve genuine upload and revision lineage. The baseline's `roster_source_immutable` trigger forbids changing the original import's actor/session fields; a fresh-session handoff needs an additive, transactionally fenced branch or equivalent reviewed design, not an in-place rebinding.

`lib/admin/core/admin_roster_checkpoint.dart` and `lib/admin/core/admin_roster_checkpoint_web.dart` store an opaque reference and digests in origin-scoped `sessionStorage`; private editor rows are intended to remain in memory or protected server storage. The retained gateway and recovery decoders bind the owner digest to an actor ID and underlying Auth session ID. The cookie session DTO exposes a separate public BFF session ID. They cannot be silently substituted. Define a versioned, non-secret owner binding consistent across the adapter and recovery receipts, while having the server independently authorize the real linked actor and Auth session. Handle a same-authority email renewal without discarding work; fence genuine actor/session or permission changes.

The retained `_readBookmark` clears the stored reference when parsing fails, including a mismatched owner digest, and session invalidation clears the current reference. Any new cookie integration must explicitly decide and test how to preserve a prior owner's opaque recovery evidence without exposing or authorizing that owner's draft to another account. Expired or unavailable proof must fail closed. The old-origin reference is not automatically accessible at a new origin, and neither an opaque reference nor a source redirect can reconstruct edits never saved on the server.

Historical SQL receipt documents and fixtures describe older contracts; they do not prove installation in the current database or establish the actual legacy predecessor's data and actor identity. A real legacy transfer needs verified deployed predecessor/source and storage semantics, a trustworthy old-to-new actor mapping, a reviewed transfer protocol and recovery evidence. The v41 deployed public bytes were not verified in this assessment. Route/fragment preservation is separate from preserving a session or draft.

## Transport and acknowledgement contracts

The generic cookie operations route currently reads at most 2,097,152 bytes (`admin_bridge.js`), while the existing bearer function route admits up to 7,100,000 bytes for the named roster upload/extract functions (`supabase/functions/_shared/domain/index.js`). `admin_roster_upload.dart` admits binary source files up to 5,242,880 bytes and XLSX also carries derived TSV. The combined JSON/base64/derived envelope can exceed 7,100,000 bytes even when the individual components meet their bounds. A new route needs an explicit bounded combined-envelope policy and boundary tests rather than blindly adopting either limit.

The roster UI generates and validates native request UUIDs and exact payload digests; the generic cookie Admin `requestId` helper derives a different UUID from an idempotency key. A new bridge must specify how its header, body IDs, receipts, and stage/execute operations agree; it must not transform the roster identity accidentally or retry an unknown mutation automatically. Explicitly map recent-email-required and other cookie errors without treating every 403 as a reason to erase a recoverable reference.

For text/CSV the current source uses deterministic extraction. XLSX derived text is labelled `client_derived_tsv`, not verified workbook contents. Optional PDF/image AI processing remains subject to the separate decoder, policy and acceptance gates in `docs/implementation/self-hosted-20261101/roster-native-feasibility.md`; this assessment does not enable or qualify it.

The shared working-tree candidate in `roster.js` now projects a committed status preview as non-submittable and returns the validated initial preview for exact prepare replay. The earlier HEAD source had the two response mismatches documented in `docs/implementation/self-hosted-20261101/roster-status.md`. The candidate's correctness, tests, integration, and deployed status are not established by this read-only assessment.

## Tests needed before claiming restoration

Extend the existing `test/admin_roster_reload_test.dart`, `test/admin_roster_fresh_auth_test.dart`, `test/admin_roster_authority_scope_test.dart`, `test/admin_roster_transport_test.dart`, `test/admin_roster_upload_admission_test.dart`, `test/admin_roster_bookmark_browser_test.dart`, and the current Admin session/BFF and actual-SQL suites as appropriate. Necessary scenarios include:

1. Cookie and origin/CSRF denial; no browser bearer token; current role/grant, session, email-proof expiry and same-session renewal; revocation between request resolution and read/replay/commit; A–B–A authority changes and late responses.
2. Source and combined envelope limits, including near-limit XLSX with derived content; exact request UUID/body/hash replay; changed-payload conflict; no automatic retry after lost upload, review, commit, or transfer acknowledgement.
3. Create versus existing mode, null-to-existing switch, mismatched group ID, unproven assisted provenance, private/archived/status/revision changes, and direct calls that bypass the UI.
4. Same-session reload with and without a saved draft; checkpoint conflict and storage failure; cross-owner isolation; expiry; unknown pending intent and committed status; no extraction, review or commit merely because recovery is inspected.
5. Fresh-sign-in list and inspection with linked actor authority; explicit transfer/affirmation; competing transfers; old-writer fencing; immutable original proof; reset approval; lost transfer response resolved by status without a second write; malformed lineage or wrong-owner rejection.
6. Source-level replay tests for the other owner's status/initial-preview candidate and affected consumers, followed by actual current SQL and isolated browser journey tests on a frozen tuple. Historical SQL142/144/149 fixtures are contract references, not present-chain results.

No test, build, PostgreSQL query, browser journey, deployment, or user-data access was performed for this assessment. No runtime source or existing document was edited.

## Selected source fingerprints

SHA-256 values observed during this assessment:

| Repository path | SHA-256 |
| --- | --- |
| `supabase/functions/_shared/domain/roster.js` (unstaged candidate) | `5f546db696f5a1b068154b906e1d0084ec664eaaf398e09ada53ac82396e8ba9` |
| `supabase/functions/_shared/domain/operations.js` | `1665fb8e39989bf363d6ab991628ecb05bcd08b0757bf43b5e20e5bd302f0707` |
| `supabase/functions/_shared/domain/admin_bridge.js` | `fafa984c9ae0647af068707ffb06e3423281bcaded7a6078830ce9d0ce316df2` |
| `supabase/functions/_shared/domain/admin_accounts.js` | `49d8ec373b3b1f4b4f1fa23efaea2538d701b469f92c99603e4e05a2929fd661` |
| `supabase/functions/_shared/domain/admin_accounts_legacy.js` | `5574f8280e4952c7f41cfb5013c0c613e550c1dc8a2218ec2543f8ae1067ac97` |
| `supabase/functions/_shared/domain/admin_email_policy.js` | `91b91a09297d5d219ed3ea755075752918e9df98731438510a91c17508d7ffc1` |
| `lib/admin/core/admin_roster_import.dart` | `735ea7bee541ec6a0be7796a52c393f7b977f8913a7c8a9794cb8478ee6a910b` |
| `lib/admin/core/admin_roster_gateway.dart` | `37092016b406c3e624a11c27bc94f092f37459e7dd0edb6b1fc240b51a5412d9` |
| `lib/admin/core/admin_roster_models.dart` | `f594e11dcf13b35dd01efb36f756947146b3f34bfada450b49a416111c1129f9` |
| `lib/admin/core/cloudflare_admin_session.dart` | `9751066f637f3d7d9393a80ad929819dfdead50cb44d58573559fd9588466116` |
| `lib/admin/core/admin_group_runtime.dart` | `41269a0e47827ea932c14d5755ea424a9d2e0d8d3520049db9c06c2ed565b70b` |
| `lib/admin/core/admin_detail_runtime.dart` | `8322bda407ce6f9a58cd542efab701347d1bf13f7246c951a59ea4e603e232d5` |
| `supabase/migrations/20261020134444_collect_curated_platform_baseline.sql` | `0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0` |
| `supabase/migrations/20261023002500_collect_admin_recent_email_source_upgrade.sql` | `02c93209f546880032cf38382c61e78a3de0b0073dd2cb88699319afc6f0f185` |
