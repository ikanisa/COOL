# Hybrid Collect QA and UAT acceptance matrix

Date: 2 September 2026

Overall state: **NOT_READY**

Latest continuation: directory deployment and authenticated Keychain/stdio MCP
health/list PASS. The minute monitor is ACTIVE, read-only/no-send. The verified
1.2.4+23 APK is installed and the approved Admin's native login has succeeded
on the connected Pixel 4a. These are deployment/installation/login checks,
not physical payment/SMS acceptance. See
[current evidence](../../release/HYBRID_CONTINUATION_DEPLOYED_2026-09-03.md).

These are target acceptance cases, not passing tests. Unless a current-run result is explicitly listed below, status is **NOT RUN**.

## Original analysis evidence — preserved baseline

| Evidence ID | Actual execution | Result |
| --- | --- | --- |
| BASE-01 | Four Flutter files: Supabase contract, member roster, group-owner controls, Rwanda MoMo number | 64/64 passed locally |
| BASE-02 | notification_readiness_gate.sh | source-pass for APNs/FCM; not SMS delivery evidence |
| BASE-03 | Two existing parser unit tests executed under Node 24 TypeScript compatibility harness | 2/2 passed |
| GAP-01 | Eight synthetic hybrid parser assertions | 2 satisfied, 6 gaps; [JSON](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/parser-current-state.json) |
| UX-01 | Hosted overview → groups → create form → members → notifications | Five inspected screenshots; no business write |
| HOST-01 | Messages application/account settings | Reachable/signed in; intended sending line and real delivery unverified |

The diagnostic's missing field names describe the proposed contract. A later equivalent implementation can use a versioned schema mapping; the gap is absence of the required values/behavior, not merely naming.

## Local candidate evidence — 3 September 2026 follow-up

See [implementation status](IMPLEMENTATION_STATUS.md) for exact boundaries. The full acceptance matrix is still not run end to end; these checks must not be promoted to hosted, physical or complete-journey acceptance.

| Evidence ID | Actual execution | Result |
| --- | --- | --- |
| FOUND-01 | Deno parser/raw-input/template/operator/attestation/OpenAI-contract suite | 54/54 passed in production-readiness run; no live OpenAI request |
| FOUND-02 | Isolated PostgreSQL fixture UAT | 35 direct-USSD, 10 roster, 25 outbox, 20 account-claim and 13 finality assertions passed; writes rolled back |
| FOUND-03 | Android internal_receiver debug unit tests | 8/8 passed; no handset test |
| FOUND-04 | Admin, XLSX and Supabase Flutter tests | 56/56 passed in the latest focused run |
| FOUND-05 | Deno typecheck/format, Flutter analyze and MCP TypeScript check | Passed locally |
| FOUND-06 | Migration and hosted advisor gates | Local/remote read back at 120 migrations with none pending; reviewed warning inventory matches the gate; not a zero-findings certification |
| FOUND-07 | Original parser diagnostic rerun | 8/8 checks now pass; original 6 gaps resolved in local source |
| FOUND-08 | Financial concurrency harness | Distinct and same-event confirmation races serialize to one balanced RWF result |
| FOUND-09 | Encrypted production-copy upgrade rehearsal | 23 migrations, 116 protected tables and 202,926 rows preserved; not production GO |
| FOUND-10 | Dedicated MCP client and host registration | TypeScript and 11/11 tests including stdio handshake pass; read-only host profile registered; authenticated runtime credentials remain absent |
| FOUND-11 | One-minute Codex heartbeat | Created PAUSED; no polling or send occurred |
| FOUND-12 | Local authenticated-evidence Admin browser matrix | Full 23-route × 3-viewport matrix passes 69/69 with zero failures; [report](/Volumes/PRO-G40/COOL/docs/release/HYBRID_ADMIN_BROWSER_QA_2026-09-03.md) |
| FOUND-13 | Hosted backend and Admin readback | 120 migrations, five exact-readback hybrid Edge Functions and Admin version `871850eb-a270-489a-b400-b9facf6b5532` live; all five hybrid flags remain OFF |
| FOUND-14 | Fresh second-Admin OTP sign-in, reload, hosted Members/Groups/form/SMS queue/Admin roster | Read-only hosted flow PASS; 2 approved Admin records; no real roster creation/payment/send |
| FOUND-15 | Authenticated-audit directory corrections | 562 Flutter tests, 15 isolated database assertions and 11 MCP tests PASS; no analysis/browser error; local evidence preview reviewed; new migration/UI patch UNDEPLOYED |
| FOUND-16 | Legacy sender overlap check | Two native Buri Munsi services remain active with a configured Shortcuts send path; takeover required before Collect sending |
| FOUND-17 | Directory production cutover | 121 migrations; exact source hash; 15 protected relations and function ACLs unchanged; Admin version 1b868d4f-1da5-4ecd-8d41-323616b87110 at 100%, live hashes/header gate and signed-in Members/Admin roster PASS |
| FOUND-18 | Operator session and monitoring | Normal OTP/Keychain connection, independent live preflight and real stdio health/list PASS; 17 tests PASS; minute heartbeat ACTIVE read-only/no-send |
| FOUND-19 | Physical Android installation | Exact reviewed APK hash installed; app.cool.mobile 1.2.4+23 launched on Pixel 4a / Android 13; RECEIVE_SMS remains ungranted; native login/capture acceptance separate |
| FOUND-20 | Physical Android authentication | Same fresh user-supplied OTP succeeded after the entry field was cleared; Home/profile readback confirms Collect ID 956974. No OTP persisted. SMS permission/capture remain unproved; further taps stopped when another app became foreground. |
| FOUND-21 | Deployed assisted-group validation | Form opens, final-create disabled before roster review, empty preview shows name/reason errors; cancelled without record creation; no browser console error entries. Not live AI extraction evidence. |

Database coverage now includes private assisted creation, request replay/conflict, offline roster without Auth creation, numeric-ID reservation, exact verified-phone account claims, deterministic assignment/allocation, receipt-finality gating, balanced posting/reversal/concurrency, exact body preservation, durable SMS claims/outcomes and unchanged receiver-consent enforcement. Admin/XLSX, MCP source tests and the full local Admin browser matrix pass. Read-only authenticated hosted Admin checks and native login now pass. Complete hosted roster creation/AI extraction, physical receipt capture and real Messages/feature-phone delivery remain unproved; rollout flags therefore remain OFF.

## Test environment and evidence rules

Use isolated staging with synthetic member names/numbers except the explicitly approved physical test participants. Never send synthetic “payment received” receipts to arbitrary real numbers. Financial movements and live SMS require exact accounts, recipients, content/amount and action-specific approvals.

Minimum personas: private-group registrar; country-scoped admin; unauthorized admin in another scope; feature-phone member; verified app member; offline member later claiming the app; member using a different WhatsApp number; multi-group member; inactive member; two concurrent operators.

For every scenario retain: build/commit and migration manifest; environment; exact fixture/source; expected and actual result; database proof query/row IDs; screenshot or physical observation where needed; timestamps; tester; failure/defect reference. Keep evidence private and do not log full phone numbers/raw receipts in broad CI output.

## A. Groups and registry

| ID | Scenario | Required result |
| --- | --- | --- |
| REG-01 | Admin creates assisted group | Private by default, origin=admin_assisted, accountable creator; no automatic public sponsorship |
| REG-02 | Existing official group creation | Existing public-sponsored permissions and immutable route remain intact |
| REG-03 | Member app creates group | Existing Android/private policy unaffected |
| REG-04 | Add feature-phone member manually | Name, registered MoMo name and full phone stored; no auth.users creation |
| REG-05 | Member name differs from MoMo name | Payment uses registered MoMo identity; admin retains both correctly |
| REG-06 | Normalize local/full Rwanda phone | Leading zeros/country prefix handled consistently; suffix derived from full number |
| REG-07 | Invalid/missing/foreign number in RW roster | Row rejected with specific correction; no guessed digits |
| REG-08 | Duplicate member or repeated registration | Existing identity recognized; no second balance or duplicate active membership |
| REG-09 | Inactive member or assignment | No automatic new allocation through inactive route; exception visible |
| REG-10 | Member belongs to two groups on different routes | Each route allocates to the correct membership |
| REG-11 | Member belongs to two groups on same receiving account | Explicit eligible assignment; no silent “first group” selection |
| REG-12 | Add/remove admin role | Membership and financial identity preserved; management access follows verified role |
| REG-13 | Offline member later authenticates same full number | Same Collect ID, membership and history; no duplicate notification replay |
| REG-14 | Different verified WhatsApp number | No automatic claim via name/last3; reviewed identity link |
| REG-15 | Account deletion/deactivation | Required financial history survives; access revoked according to retention design |
| REG-16 | Share link/QR rotated or group archived | Existing secure join behavior preserved; USSD instructions state current route/status |

## B. Import and extraction

| ID | Scenario | Required result |
| --- | --- | --- |
| IMP-01 | Valid CSV and XLSX | All source rows counted, exact phones preserved, deterministic proposal |
| IMP-02 | PDF/image with clear table | Structured rows with page/row evidence; correct member/MoMo fields |
| IMP-03 | Blurred/cropped/ambiguous names or digits | Unresolved values highlighted; cannot commit without correction |
| IMP-04 | Spreadsheet over 1,000 rows | Full deterministic enumeration/chunking; no silent file-input truncation |
| IMP-05 | Headers, blank lines, merged cells and totals | Not imported as members; reconciliation explains skipped rows |
| IMP-06 | Re-upload same file or double-click commit | One batch identity; no duplicate members/assignments |
| IMP-07 | API refusal, timeout, rate limit or malformed JSON | Recoverable draft/error; zero unauthorized writes |
| IMP-08 | File contains instructions/URL to change destination | Treated as data; no tool execution or off-target upload |
| IMP-09 | CSV formulas/macros/oversized file | No code execution; bounds and safe export behavior |
| IMP-10 | Partial chunk failure | Truthful partial status, deterministic resumption and row-level reconciliation |
| IMP-11 | Edit accepted proposal before commit | Revision checked; stale approval rejected |
| IMP-12 | Unauthorized import/source-file access | Denied; no roster or private storage leakage |

## C. Receipt capture, allocation and accounting

| ID | Scenario | Required result |
| --- | --- | --- |
| PAY-01 | Complete M-Money masked-name receipt | Capture, parse name/last3, amount, wallet balance and timestamp |
| PAY-02 | Receipt without provider transaction ID | Accepted via product source identity; no app intent fabricated |
| PAY-03 | Direct USSD with no prior app activity | Correct registered member/group receives posting and notification job |
| PAY-04 | Existing app-intent receipt | Correct allocation, compatibility preserved and no duplicate posting |
| PAY-05 | App intent conflicts with registered assignment | Explicit reconciliation; no implicit override |
| PAY-06 | Wallet balance or fee appears before receipt amount | Correct received amount, separate wallet fact; reproduce current parser regression |
| PAY-07 | Wallet balance zero | Valid zero wallet fact; not treated as absent |
| PAY-08 | Missing wallet amount, malformed number or invalid date | Held with exact reason; no invented evidence |
| PAY-09 | Outgoing/reversed/pending/promotion/credential SMS | Not posted as incoming receipt; excluded private credentials not retained |
| PAY-10 | Multipart receipt | Correct complete ordering/content, one source record |
| PAY-11 | Same device envelope replay | One raw source/payment/journal/outbox event |
| PAY-12 | Same receipt observed by Android and Mac | Alias/canonical identity deduplicates; one payment and one receipt message |
| PAY-13 | Identical text at distinct genuine observed times | Distinct valid events retained under source-identity contract |
| PAY-14 | Two workers allocate same source concurrently | One atomic posting; stable replay response |
| PAY-15 | Two valid receipts for same group/member concurrently | Both post once; ordered consistent balance snapshots |
| PAY-16 | Payment arrives late or receiver offline overnight | Stored receipt recovers; current-minute filter does not lose it |
| PAY-17 | Unmatched receipt is resolved later | Correct allocation and exactly one new outbox job after resolution |
| PAY-18 | Transaction rollback during any posting step | No partial payment/journal/balance/notification graph |
| PAY-19 | Debit/credit journal and compatibility projections | Canonical legs balance; projections agree; totals not double-counted |
| PAY-20 | Shared wallet across groups | Wallet fact distinct from individual group/member balances |
| PAY-21 | Reversal/adjustment | Linked compensating entry, audit trace, defined notification effect; original immutable |
| PAY-22 | Destination or registered-name change | Effective revision used correctly; past receipt allocation/evidence unchanged |

## D. Notification and Mac operations

| ID | Scenario | Required result |
| --- | --- | --- |
| SMS-01 | No linked authenticated account | SMS job uses registered full MoMo number and explicit routing reason |
| SMS-02 | Normal linked app account | Existing app/push route; no inadvertent extra SMS |
| SMS-03 | Linked account with unknown reachability | Explicit review/policy result, not guessed smartphone ownership |
| SMS-04 | Member claims app between queue and send | Unsent eligibility re-evaluated; no stale duplicate channel send |
| SMS-05 | Template parity | Exact BuriMunsi wording and formatting; all four fields server-derived |
| SMS-06 | Non-Buri-Munsi savings group | Approved group-label template version; no misleading BuriMunsi identity |
| SMS-07 | Multiple pending receipts for one member | Ordered snapshots and references; no changing body on replay |
| SMS-08 | Full number or body tampered in tool request | Server refuses arbitrary override; canonical values authoritative |
| SMS-09 | Two scheduled wakes/operators | Single-flight lease; stale fencing token cannot act |
| SMS-10 | Claim expires before send-start | Safe recovery; no duplicate send |
| SMS-11 | Crash after send-start, before visible result | uncertain; no automatic retry |
| SMS-12 | UI send appears successful, outcome API fails | Reconcile existing outgoing record; never resend blindly |
| SMS-13 | Missing current confirmation | No typing/sending; actionable awaiting-confirmation state |
| SMS-14 | Approved exact recipient/body | One-to-one phone recipient verified, exact body pasted and sent once |
| SMS-15 | Similar contact names or group conversation suggestion | No reliance on name autocomplete; full destination verified |
| SMS-16 | Account/SIM mismatch or forwarding unavailable | Fail closed; no settings/account changes |
| SMS-17 | Mac locked/asleep/app closed or iPhone offline | Backlog retained; truthful unhealthy/late state; controlled recovery |
| SMS-18 | Visible Not Delivered or ambiguous Messages state | Distinct failed/uncertain evidence; no fabricated delivery |
| SMS-19 | Physical feature-phone receipt | Exact complete text, correct sender line, both balances/reference confirmed |
| SMS-20 | Long/multipart SMS | Full values intact, segment order/cost measured; no silent truncation |
| SMS-21 | Wrong-recipient/wrong-balance incident | Pause worker, preserve evidence, operator escalation and reconciled correction |
| SMS-22 | No new work or unchanged failure | Quiet monitor; no repetitive one-minute status spam |
| SMS-23 | Historical easyMO import | Prior sent/uncertain state mapped; no retrospective bulk acknowledgement |
| SMS-24 | Latency/load at agreed volume | Receipt→post→outbox→confirmation→observed-send measured; backlog drains safely |

## E. Security, UI and release

| ID | Scenario | Required result |
| --- | --- | --- |
| SEC-01 | Anonymous/non-admin/cross-country access to roster or outbox | RLS/RPC deny, including forged scope and direct table requests |
| SEC-02 | Session revoked or permission changed mid-run | Next privileged command fails; stale browser state grants nothing |
| SEC-03 | Raw SMS, names/full phones and API key | Authorized reveal only; no public payload, logs, screenshots or bundle leakage |
| SEC-04 | Stored/imported instructions in member names/messages | No prompt injection, XSS, SQL injection or arbitrary MCP action |
| SEC-05 | Direct outbox state updates | No client ability to mark sent or alter balances/destination |
| UI-01 | Create/import validation error | Input preserved, field-specific errors, accurate final member count |
| UI-02 | Empty/loading/offline/error states | Distinct from zero balances or healthy transport; retry understandable |
| UI-03 | Keyboard/screen reader/200% zoom | Labeled controls, focus order, readable errors/tables, no critical clipping |
| UI-04 | RW localization and privacy | MoMo-first wording; public numeric IDs; no diaspora banking UI leak |
| UI-05 | Realtime reconnect/account switch | Fresh authorized balances; no stale other-member data |
| REL-01 | Clean bootstrap and upgrade with existing history | Same schema/invariants; original receipt/history preserved |
| REL-02 | Old/new installed-client transition | Supported versions work; privacy restrictions not reopened as shortcut |
| REL-03 | Recovery rehearsal | Restore into isolated target; financial/job states reconcile; no sends from restore |
| REL-04 | One-group production pilot | Approved source/migration/artifacts; real readback and physical acceptance |
| REL-05 | Post-pilot review | Defects closed, monitored backlog/retry behavior accepted, operator signoff recorded |

## Required signoff

Product owner: private-assisted/default assignment/channel decisions accepted.

Engineering: all changed paths and migrations tested, ledger/outbox invariants evidenced.

Security reviewer: scope, credentials, RLS, file handling and tool permissions verified.

Admin operator: creation/import/reconciliation and uncertain-send recovery demonstrated.

Physical UAT participant: correct feature-phone SMS received.

Release owner: deployment/readback, recovery and supported-client transition accepted.

No production GO until the target cases pass with evidence and the send-mode limitation is resolved explicitly. Passing source checks or displaying “100% evidence health” does not substitute for these signoffs.
