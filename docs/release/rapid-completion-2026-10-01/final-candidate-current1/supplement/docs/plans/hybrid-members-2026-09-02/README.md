# Collect hybrid membership and Mac SMS — architecture and execution plan

Date: 2 September 2026

Decision: **NOT PRODUCTION READY for the new journey**

Scope: Rwanda MoMo/USSD, account-independent members, admin-assisted groups and roster import, receipt allocation, app/SMS routing, Codex operations, QA and UAT.

This started as an architecture analysis, with current-source diagnostics and a limited live admin UX inspection. After the owner accepted send-time confirmation, the backend, Admin, Edge operator, MCP and roster-extraction candidate were implemented and tested; see [implementation status](IMPLEMENTATION_STATUS.md). The production backend and Admin PWA have now been deployed and read back, with every hybrid feature flag still OFF. It is not a completed feature release: no live hybrid payment, OpenAI roster request, Messages receipt, store rollout or physical acceptance has occurred. A one-minute Codex heartbeat was created PAUSED and has never sent. Existing dirty work was preserved. Sections describing the original inspection remain a dated baseline, not the current implementation inventory.

## 1. Recommended product decision

Build one Collect membership and ledger system with two ways to access it:

- App users: authenticated app, group link/QR, history, server-derived balances, existing push notifications.
- Members without an app account: admin records their member name, registered MoMo name and full MoMo number; they pay by USSD and receive the same receipt information by SMS.

A person does not need an Auth account to be a financial member. A group does not need to be public merely because an administrator created it. A payment does not need an app-created intent to be recorded when the permitted receipt and registered membership establish its allocation.

Use Supabase for authoritative membership, payment records, ledger, balances and notification jobs. Codex may inspect and operate a narrow notification queue; it must not become the ledger, infer balances from screenshots, or decide who receives a payment.

The requested no-SMS-API transport is compatible with an **assisted Mac Messages workflow**. The owner accepted this mode on 2 September 2026. The current Computer Use skill requires action-time confirmation before representational messages are sent. This decision is not authorization for any particular SMS. A recurring prompt or MCP wrapper does not waive imminent recipient/content confirmation. Fully unattended sending is not part of the approved implementation.

### End-to-end target

~~~mermaid
flowchart LR
  A[App creation or admin roster] --> M[Account-independent member registry]
  U[Member pays by MoMo USSD] --> R[Permitted receipt SMS retained]
  R --> P[Parse amount, payer, last 3 and wallet balance]
  M --> X[Deterministic route and member allocation]
  P --> X
  X --> T[Atomic payment, balanced journal and balance snapshot]
  T --> Q[Durable notification outbox]
  Q --> N[Authenticated app notification]
  Q --> C[Codex narrow queue review]
  C --> S[Action-time confirmation then Mac Messages]
  S --> E[Observed send evidence or uncertain outcome]
~~~

The provider SMS is the Rwanda product's external transaction evidence. Matching and financial finality remain separate internal steps: after deterministic matching, the same fresh device-attested provider receipt can finalize its candidate automatically. No second bank/provider API or human confirmation is required, but an unattested or arbitrary client-supplied body cannot post money. Diaspora bank-rail rules remain separate and unchanged.

## 2. What exists today — verified evidence

This subsection preserves the original 2 September baseline examined at HEAD `40620f10ffbde3bcbd6a53cc0f493de6e948cc73`. It explains why the update was required; it is superseded for current implementation and deployment status by [implementation status](IMPLEMENTATION_STATUS.md) and [goal execution](GOAL_EXECUTION.md).

| Area | Current evidence | Consequence |
| --- | --- | --- |
| App accounts | profiles.id references auth.users.id | Do not create fake Auth users for feature-phone members. |
| Membership | collection_members.user_id can be null, but the row has only an invited phone hash, role and status | Nullable user_id is not a complete offline member registry. |
| Member reads | Latest group_roster explicitly excludes null user_id and joins profiles | A newly inserted offline membership would be invisible to current member roster reads. |
| Admin groups | Hosted creation form and local admin_group_runtime create only public, Collect-sponsored groups | Add private admin-assisted creation; do not repurpose public creation silently. |
| Sharing | ShareScreen and server share-secret/join-code flows exist | Reuse secure share infrastructure; a QR/link is optional access, not required to pay or exist as a member. |
| Receipt capture | Android receiver joins SMS segments, keeps an encrypted queue and sends envelopes to ingestion | Retain this receive-only design, but update capture eligibility alongside the parser. |
| Capture restriction | isLikelyMomoReceipt requires a transaction/reference hint | A complete easyMO-style receipt without that hint can be discarded before backend parsing. |
| Raw SMS | Immutable raw_payment_sms with receiver/body and receiver/envelope uniqueness | Useful foundation. Source identity and exact-text handling must be aligned with the new contract. |
| Parsing | Current parse-payment-sms uses deterministic parser, writes sender_name=null | There is no current OpenAI receipt parsing call in this function; comments mentioning OpenAI are stale. |
| Allocation | Latest allocator selects pending intents by payer, amount, receiver and time; posting requires an intent and transaction ID | Direct feature-phone payments without an intent cannot use the intended happy path. |
| MoMo ledger | Two positive collection_credit/member_credit projection entries; admin presents these as debit/credit totals | This is not an explicit debit/credit journal. Avoid calling that representation a proven two-sided journal. |
| Push | Existing notification_events, device tokens, delivery claims, attempts and APNs/FCM dispatcher | Reuse for account notifications; existing non-null user_id/device design does not cover offline SMS. |
| Mac bridge | No modelContext/WebMCP match found in inspected web and admin sources | A narrow Collect bridge is proposed, not already installed or operational. |
| Scheduler | Existing “Buri Munsi receipt pipeline” is a paused one-minute heartbeat, still targeting easyMO's Sheet workflow | Leave it paused and unchanged. Do not activate a second overlapping sender. |
| Mac Messages | App and signed-in account settings accessible; a phone start-from identity is configured | Does not prove the intended Rwanda SIM, forwarding availability, carrier path, or handset delivery. |

### Key source locations

- [Baseline accounts/membership/payments](/Volumes/PRO-G40/COOL/supabase/migrations/202605230001_collect_baseline.sql)
- [Current roster contract](/Volumes/PRO-G40/COOL/supabase/migrations/20260902091314_member_group_roster.sql)
- [Admin group creation](/Volumes/PRO-G40/COOL/lib/admin/core/admin_group_runtime.dart)
- [Android receipt capture](/Volumes/PRO-G40/COOL/android/app/src/main/kotlin/app/cool/mobile/receiver_sms/CollectSmsReceiver.kt)
- [Ingestion](/Volumes/PRO-G40/COOL/supabase/functions/ingest-payment-sms/index.ts)
- [Parser](/Volumes/PRO-G40/COOL/supabase/functions/_shared/momo_sms_parser.ts)
- [Parser persistence](/Volumes/PRO-G40/COOL/supabase/functions/parse-payment-sms/index.ts)
- [Latest MoMo posting/allocator definition](/Volumes/PRO-G40/COOL/supabase/migrations/20260820160000_restore_momo_sms_standalone.sql)
- [Admin ledger projection](/Volumes/PRO-G40/COOL/supabase/migrations/20260831095454_collect_admin_operations_model.sql:528)
- [Push dispatcher](/Volumes/PRO-G40/COOL/supabase/functions/dispatch-notifications/index.ts)
- [Current rollout constraints](/Volumes/PRO-G40/COOL/docs/release/CONTROLLED_ROLLOUT_2026-09-02.md)

## 3. Preserve the easyMO contract, not the old infrastructure

Reopened and read the current easyMO AGENTS.md, product doctrine, parser and two template implementations. Its accepted chain is permitted M-Money receipt → exact raw text → amount/wallet balance/payer/time → normalized name plus last three digits → transaction and balanced journal → member/group balances → exact member acknowledgement.

Canonical recovered wording:

> BuriMunsi: Twakiriye ubwizigame bwawe bwa {amount} RWF. Balance yawe: {member_balance} RWF; balance y'itsinda: {group_balance} RWF. Ref: {reference}.

Sources:

- [Production dispatcher template](/Users/jeanbosco/Documents/ChatGPT/easyMo/automation/messages_outbox_dispatch.mjs:367)
- [Apps Script equivalent](/Users/jeanbosco/Documents/ChatGPT/easyMo/automation/apps_script/Code.gs:350)
- [Canonical product doctrine](/Users/jeanbosco/Documents/ChatGPT/easyMo/docs/BURI_MUNSI_SMS_PRODUCT_DOCTRINE.md)

Preserve the literal template for Buri Munsi. For other groups, propose a separately versioned group-label prefix using the same body; do not send “BuriMunsi” for an unrelated group or change the wording silently. Whether “ubwizigame” is appropriate for every non-savings collection also needs template review; initially scope this receipt template to group savings.

Amounts are integer RWF, formatted with comma grouping as easyMO does. Template rendering is deterministic, not rewritten by the model per payment. Store template ID/version, exact rendered body, body hash, immutable amount/balance inputs and reference.

Do not import the Sheet's operational ledger as a parallel live source. If old easyMO members/history move into Collect, use an explicit migration with source-ID mapping, count/amount/readback reconciliation and one cutover boundary. Existing GRP identifiers can be retained as external legacy IDs; preserve Collect UUIDs and current secure share codes rather than replacing every group key.

## 4. Required backend design

### 4.1 Account-independent identities

Proposed additive entities:

| Entity | Required fields and constraints |
| --- | --- |
| member_records | Stable UUID; centrally allocated numeric Collect ID; nullable unique linked_user_id; lifecycle status; source; created/updated audit fields. Account deletion must not cascade-delete financial membership/history. |
| member_momo_identities | member_id; full canonical E.164 number; MoMo registered name; normalized name; last3; private SHA-256 match key; active/effective dates; revision and provenance. Keep personal names/numbers out of general profile/public reads. |
| collection_members extension | member_id linked to registry, with uniqueness preventing duplicate active membership. Keep user_id compatibility during migration. Roles and account access remain distinct from financial membership. |
| member_receiving_assignments | Receiving account/route, member_id, collection_id, validity period; one deterministic active allocation destination in that route context. |
| member_account_links | Verified account-to-member link evidence, actor, timestamp, before/after revision. Linking does not move money or rewrite historical receipts. |
| roster_import_batches/rows | File digest, row/page provenance, extraction version, raw/normalized proposal, validation issues, review status and idempotency key. |
| sms_notification_outbox/attempts | Payment/member/group IDs, destination revision, exact message and ledger snapshot, eligibility reason, claim/fencing token, state, attempts and observed evidence. |

Avoid two independently allocated numeric-ID namespaces. Backfill existing account IDs into the registry and use one authoritative allocator/reservation rule so an offline member keeps the same Collect ID after claiming the app.

The receiving account is its own durable identity. Multiple groups may point to it; code “41258” is Buri Munsi configuration, not a global default. The sender's MoMo number is not the group's receiving MoMo code.

Keep human-readable names in authorized admin/member-identity storage. Do not reopen the recently restricted profile-name endpoints or expose member names in public rosters.

### 4.2 Group creation and member onboarding

Add origin independently of visibility: member_app, admin_assisted, platform_sponsored. Default new admin-assisted groups to private. Keep official public groups on their existing authorized path.

Admin creation is a server-authorized command with group name/type, country RW, RWF, receiving route, administrative owner, and audit reason. Retain creator_user_id as the accountable admin actor where current schema requires it; do not invent a smartphone owner. Delegated app-management access is a separate authorized assignment.

Creating a group can produce a draft before the receiving route and roster are ready. Activation requires a valid configured route; adding a member requires full MoMo number and registered MoMo name. Do not require WhatsApp OTP from a feature-phone member. Record member display name separately when different from the MoMo registered name.

Allow single-row entry, paste-table entry, CSV/XLSX import, and reviewed PDF/image extraction. A duplicate import should show an existing member/update proposal, not create a second balance.

### 4.3 Deterministic matching and posting

1. Retain the exact accepted permitted receipt, sender, observed device time, source/envelope ID, receiver binding and ingestion timestamp.
2. Parse received amount, resulting wallet balance, payer name, last3, currency, timestamp and optional transaction reference. The captured wallet balance is the receiving wallet balance, not the member or group balance.
3. Use the easyMO normalization contract: trim, collapse whitespace, uppercase; hash normalized_name + "|" + last3. Version any normalization change and use matching goldens across implementations.
4. Resolve the permitted receiving account and its active assignments. Match the registered identity within that context; do not infer a full phone number from a suffix.
5. For direct-USSD payments, resolve the single eligible member/group assignment without an app intent. Retain the app-intent path for explicit app payments. If both paths identify the same target, post once; if they disagree, create a reconciliation exception rather than choose one silently.
6. Zero eligible assignments creates a held allocation exception. Multiple active group destinations for one member in the same receiving account require the configured assignment or an admin resolution. This tests faithful routing; it does not replace the accepted name/last3 identity design.
7. In one transaction, lock the source and the affected member/group balance sequence; create payment, allocation, actual debit/credit journal, reconciliation record and immutable receipt balance snapshot. Enqueue the appropriate notification with a unique payment/member/purpose key.
8. The app and admin read the same authoritative balances. Codex only reads the prepared receipt.

No amount/time-only guess, fabricated pending intent, dependency on app login, second provider API or human confirmation belongs in the direct-USSD path. The finality record is produced automatically from the same accepted device-attested provider receipt after matching and remains independently auditable.

### 4.4 Raw evidence and idempotency details

Current Android capture and ingest-payment-sms trim the body. For the “exact raw SMS” requirement, keep an untouched accepted raw body and a separate normalized parsing value. New retention should exclude credential/unrelated messages at capture, not merely hide them later.

Current receiver/body uniqueness omits observed time. Use the product source identity based on full accepted SMS plus original observed timestamp/stable identity and receiving-account scope. A replay from another supported capture path must resolve to the same source; distinct genuine receipts must not collapse solely because their text matches. Preserve original IDs during retries and record aliases when Android and Mac transport IDs differ.

Provider transaction references, when present, remain useful extra evidence. They must not be mandatory for complete masked-name receipts. Update Android's transaction-hint filter, TypeScript parsing, parsed-event schema, SQL posting preconditions, admin exceptions and fixtures together.

The reproduced balance-first error shows why extraction must be tied to the “received” clause, not the first currency-looking amount. Test zero wallet balance, fees, spacing, grouping, malformed numbers, source locale and receipt timestamp validation. Do not infer a missing wallet balance or silently backfill old records from current totals.

### 4.5 Ledger and balance semantics

Existing Rwanda ledger_entries are two positive projections, not separate signed journal legs. Add canonical MoMo journal headers/lines with balanced debit/credit enforcement and unique payment linkage. Retain old projection rows only as transactionally derived compatibility reads during migration; never sum canonical and projection stores together.

Existing bank journal_entries are EUR-constrained and bank-entry-type constrained. Do not repurpose them for RWF without an explicit cross-rail redesign. This plan prefers a scoped additive MoMo journal to avoid changing the diaspora contract.

For each posted receipt, snapshot contribution amount, member's balance in that group, group's balance, ledger sequence and timestamp. Serializing on a group/account balance key prevents concurrent receipts from producing contradictory snapshots. A delayed acknowledgement should retain its captured “after this receipt” balance, not drift to a later live balance.

Keep contribution totals, savings balances and available-to-withdraw balances distinct. Reversals/adjustments use linked compensating records, not edits to receipt evidence. A shared receiving wallet's total is not a group's total. Reconciliation records the source amount/wallet fact and verifies internal posting; it must not require that the entire wallet equals one group's ledger.

### 4.6 App-versus-SMS routing

“Never authenticated in Collect” is measurable. “Does not own a smartphone” cannot be inferred from login absence. A WhatsApp OTP proves account authentication, not a permanently reachable installed app.

Use explicit channel policy plus server-derived account state:

| State | Proposed routing |
| --- | --- |
| No linked authenticated account | Queue SMS to the registered full MoMo number. |
| Linked, verified account with normal app access | Existing in-app receipt and push according to preferences. |
| Explicit SMS-only operational choice | SMS, with reason/audit trail. |
| Linked account but app/push reachability unknown | Show “delivery preference needs review”; do not silently classify as no smartphone. |
| Duplicate/deactivated record or unresolved destination | Do not send; resolve the underlying registry issue. |

Before a send begins, revalidate current identity/assignment and channel policy against the queued revision. If the member claimed the app or the destination changed, supersede/hold the unsent job explicitly. Once a send may have occurred, reconcile that attempt before creating a replacement.

Claiming an offline record requires the authenticated full verified number to match the registered MoMo identity, or a reviewed link process where those numbers differ. Name and last3 are payment matching inputs, not credentials for account takeover. Preserve the existing payments and Collect ID after linking; do not replay historical SMS.

## 5. OpenAI-assisted member-list import

Use OpenAI to propose structured rows, not to create accounts, approve members, choose payment allocations or compute balances.

1. Private authenticated upload; type/size/page/row limits, restricted storage, file digest, no executable macro evaluation. Protect CSV exports against formula injection.
2. Parse CSV/XLSX deterministically first. Use the API only for unclear column mapping and PDF/image/table transcription.
3. Send the minimum relevant roster material through a backend-only API call using strict Structured Outputs and store:false; no tools or arbitrary URLs supplied by the document. Treat all file instructions as untrusted data.
4. Proposed schema: source page/row, member name, MoMo registered name, raw phone, normalized phone proposal, extraction uncertainty and validation issues. Blank/uncertain values remain blank; never invent missing digits or names.
5. Validate full Rwanda mobile numbers server-side; preserve leading zeros, country normalization and registered spelling. AI confidence alone never authorizes import.
6. Present all rows for review, highlighting missing fields, existing identities, conflicting assignments and changes. Counts must reconcile accepted + rejected + unresolved to source rows.
7. Commit only reviewed rows under batch idempotency and server permissions. Small batches can commit atomically; large imports use explicit chunk checkpoints and truthful partial status. Re-running the batch creates zero duplicate members.
8. Keep source provenance and review evidence with bounded retention; no API key or member roster in prompts, task logs or general analytics.

The OpenAI file-input guide says spreadsheet augmentation processes up to the first 1,000 rows per sheet. Therefore, never use a raw spreadsheet model upload as proof that an entire larger roster was extracted. Read/chunk all rows locally/backend-side and reconcile counts. Strict JSON schema constrains structure, not factual accuracy. store:false is not a claim of zero retention across all service logs; review actual account data controls.

Sources: [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [File inputs](https://developers.openai.com/api/docs/guides/file-inputs).

## 6. Admin and member frontend changes

Preserve Collect's current visual system and country-aware navigation. The [live UX audit](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/UX_AUDIT.md) contains five freshly captured states.

| Surface | Required update |
| --- | --- |
| Groups | Distinguish origin, visibility and status. “Create group” starts a private assisted flow; public sponsorship remains a separate privilege. |
| Creation flow | Group details → receiving account → member entry/import → review → create/activate; save drafts, retain entered rows after validation errors, show exact final counts. |
| Group detail | Members, Transactions, Balances, Share, Settings; receipt route and intake health visible to authorized operators. Printable USSD instructions coexist with link/QR. |
| Members | Registry of all members, not only Auth users. Filters: no app account, linked account, SMS routing, missing details, group and status. |
| Member detail | Private MoMo identity, Collect ID, group memberships, account-link state, per-group balances and receipt history; authorized actions only. |
| Import review | Side-by-side source preview and editable proposed rows; row provenance, warnings, accepted/rejected totals and explicit commit result. |
| Transactions | Raw-source link, parsed received amount, wallet balance, private payer/match details, receiving account, member/group allocation and receipt-notification state. |
| Reconciliations | Specific reasons for missing registry match, inactive assignment, incomplete receipt or conflicting route; repair with audit/readback, then enqueue once. |
| Notifications | App and SMS separated. States: waiting, awaiting confirmation, in progress, observed sent, uncertain, failed, suppressed. Add oldest pending age and worker heartbeat. |
| System health | Last intake/parse/post/queue/worker activity; backlog; retry/uncertain counts; expected vs actual cadence. Never substitute “no rows” for healthy transport. |
| Member app | Claimed offline history appears under the same Collect ID; account linking does not create a new balance. Numeric public identity/privacy remains unchanged. |

Use accessible labels/tooltips for icon controls and meaningful table semantics. The live browser inspection exposed only an “Enable accessibility” button despite rendered admin content. This is a concrete automation/assistive-access concern in the inspected surface, not a full WCAG verdict. Test keyboard, focus, screen reader and 200% zoom separately.

## 7. Codex, MCP and Mac Messages

See the [proposed operator contract](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/CODEX_OPERATOR_CONTRACT.md).

Use the existing native heartbeat mechanism, not a shell cron workaround. A minute-based schedule is supported, but polling cadence is not an end-to-end delivery guarantee. Official scheduling documentation requires the computer and desktop app to remain running for local work. [Scheduled tasks](https://learn.chatgpt.com/docs/automations?surface=app).

Mac SMS depends on the sending iPhone, its network/SMS capability, the same Apple Account and Messages in iCloud or Text Message Forwarding. A Mac account showing a number does not prove those conditions. The outgoing SMS originates from the sending line, not the group's merchant USSD code. Confirm the intended line and test an actual non-smartphone recipient. [Apple forwarding requirements](https://support.apple.com/en-ie/102545).

Poll all pending eligible jobs with durable state, not payments created in the preceding minute. A delayed parse or outage must not strand an old payment. Realtime can refresh admin or wake a supported consumer, but is only a hint; a due-job query recovers missed events.

Single-flight claims, attempt fencing and a durable pre-send marker are necessary. There is no atomic transaction spanning Postgres and Apple Messages. If the UI sends and the agent crashes before recording success, the outcome is uncertain, not safely retryable. Re-read exact recipient/body/time evidence; hold for review if it cannot be resolved. Do not claim exactly-once physical SMS delivery.

## 8. Execution work packages and release gates

These are proposed packages, not completed implementations.

| Phase | Work and primary ownership area | Exit evidence |
| --- | --- | --- |
| 0 — decisions/baseline | Set assisted send mode, group privacy default, receiving-account assignments, template scope and supported client transition | Accepted decisions; source manifest; isolated environment; zero overlapping dispatchers |
| 1 — registry | Additive SQL registry, identity/assignment tables, RLS and account linking; backfill mappings without new Auth users | Upgrade/bootstrap tests; full/partial/duplicate imports; profile privacy and account-link denial tests |
| 2 — payment engine | Android eligibility and exact capture, deterministic parser, source identity, direct-USSD allocator, actual journal and snapshots | Receipt fixture corpus; concurrent/replay tests; per-payment balanced journals and exact totals |
| 3 — admin/import | Existing Flutter admin components, backend import extraction, reviewed commit, sharing/print instructions | Current browser captures; functional import tests; keyboard/reader/zoom and responsive QA |
| 4 — notification bridge | Outbox, policy routing, narrow MCP/optional WebMCP, leases, attempts, health and assisted prompt | No-send contract tests; two-worker contention; crash boundary/uncertain-state tests; unauthorized calls denied |
| 5 — staging UAT | App and no-app personas; real receiving device; approved test sending line/feature phone; old/new clients | Timestamped receipt-to-post-to-observed-send chain, physical receipt acknowledgement and operator acceptance |
| 6 — controlled release | Reviewed migration/artifact manifest, compatible deployment order, one-group pilot, recovery rehearsal | Hosted readback + physical UAT + operator signoff; pause sender on uncertain outcomes; no blind replay |

Existing source tests hard-code public-only admin creation. Replace those expectations deliberately with separate public-sponsored/private-assisted contracts; passing the old assertions is not the new acceptance criterion.

Do not treat the current dirty candidate as a frozen release. Its existing rollout document already records profile/history compatibility gates. Re-read remote migration state before deployment; no current remote-schema verification was performed in this analysis. Do not run a broad deployment script merely to ship one new migration.

Suggested rollout order: additive backend and safe compatibility reads → registry backfill/readback → parser/allocator behind a pilot route flag → admin/import → outbox in no-send mode → confirmed physical test → one-group assisted pilot. Keep auto-send disabled. Do not retroactively notify imported history by default.

Rollback means pause new notification claims, preserve accepted raw receipts, freeze affected allocation if incorrect, reconcile any in-flight send, and use a reviewed forward repair. Do not delete payments, restore over production, or blindly requeue uncertain sends.

## 9. Original analysis baseline — before implementation

| Check | Result | Boundary |
| --- | --- | --- |
| Four focused Flutter test files | 64 tests passed | Local source/unit/contract tests, not live new-feature UAT |
| Existing notification readiness script | source-pass, APNs/FCM | Static readiness only; no push or SMS delivered |
| Existing TypeScript parser tests via Node 24 compatibility harness | 2 passed | Parser functions only; not Deno Edge deployment |
| New hybrid receipt characterization | 2 of 8 checks satisfied; 6 gaps | Synthetic fixtures; deliberate exit code 2 = NOT_READY |
| Hosted admin UI | Five states captured and inspected | Authenticated read-only navigation; no group/member created |
| Messages setup | Signed-in UI reachable, phone start-from configured | No intended-SIM/forwarding/send/delivery proof |
| Schedule inventory | Existing Buri Munsi heartbeat remains PAUSED | No new schedule and no activation |
| Production implementation/deployment/UAT | Not executed | New workflow must not be described as released or production-ready |

The six reproduced gaps are M-Money network detection, missing payer name, missing last3, missing wallet balance, rejection-level confidence for a complete masked receipt without a provider reference, and first-currency-amount extraction when wallet balance appears first.

Reproduce safely:

~~~sh
/Users/jeanbosco/.nvm/versions/node/v24.18.0/bin/node scripts/audits/hybrid_sms_current_state.mjs
flutter test test/supabase_contract_test.dart test/shared/member_roster_test.dart test/shared/group_owner_controls_test.dart test/core/rwanda_momo_number_test.dart --reporter expanded
bash scripts/notification_readiness_gate.sh
~~~

The diagnostic is intentionally not wired into CI as a passing production gate. Its [saved JSON](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/parser-current-state.json) is an observed baseline. The [QA/UAT matrix](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/UAT_QA_MATRIX.md) defines the remaining acceptance work.

### Decisions and activation gates

1. Resolved: the owner accepted action-confirmed Mac sending. Each imminent send still requires recipient/content confirmation.
2. Exact sending iPhone/SIM and one authorized feature-phone test recipient.
3. Any exception to private-by-default admin-assisted groups, and explicit per-receiving-account allocation where members belong to multiple groups.
4. Exact branding/template scope for non-Buri-Munsi groups and treatment of linked accounts with uncertain app reachability.

Next stage: the backend and Admin deployment/readback are complete with every hybrid flag OFF. Continue with fresh authenticated Admin UAT, one consented live roster extraction, the governed MCP health/list dry run, duplicate easyMO-dispatcher reconciliation and approved physical Android/feature-phone acceptance. Keep all feature flags and the paused heartbeat inactive until those gates pass, then start with one bounded group under explicit rollout and release-owner approval.
