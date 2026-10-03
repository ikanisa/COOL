# Installed154 member data SQL review

## Result

The actual installed154 schema and API grants were restored into a unique disposable database. The second run completed **55 passing cases and 2 failing cases**. Both failures demonstrate the same server amount-bound defect. This is scoped SQL evidence, not full server acceptance.

Packet: [sql154-attempt2/result.json](sql154-attempt2/result.json), SHA-256 `73f0a3ac32574dab76b9c4e863831686f00200031c78c8445709ff735f7beba7`.

The disposable database was removed. All 153 shared source tables, catalog controls and cron rows matched before and after. The synthetic payment, allocation, balance, journal and delivery fingerprints also matched exactly. No source data was copied; no hosted service or provider was called. No trigger was disabled, and no posted payment, provider confirmation or verified native capability was manufactured.

## Required correction

| Item | Observed behavior | Required change and rationale |
| --- | --- | --- |
| Contribution amount exactness | Authenticated `public.create_contribution_intent(uuid,bigint,text)` accepted `9007199254740992` and `9223372036854775807`, returning pending receipts with numeric JSON amounts. Both probes rolled back. | Reject values outside `1..9007199254740991` before any financial request mutation, or adopt a separately specified exact text wire contract. The current client uses numeric exact integers and rejects these server receipts; native and JavaScript cannot safely share the unrestricted bigint contract. This bound concerns transport precision and is not a payment-provider limit. |

The installed definition is preserved in `sql154-attempt2/installed-api-definitions.json`. Its source definition is `supabase/migrations/20260903201326_geographic_member_profile_gates.sql:260`; the existing check at line294 accepts any positive bigint. Current client dispatch is `lib/shared/repositories/collect_repository_contribution_actions.dart:347`.

The private `create_payment_intent(uuid,bigint,text)` delegates to the same function; its installed API ACL denies authenticated callers. `payment_intents.expected_amount_rwf`, `collections.suggested_amount_rwf` and `collections.target_amount_rwf` have positive/null constraints without the exact JSON upper bound. The related read APIs expose bigint amounts as JSON numbers. Additive SQL correction belongs to the root SQL owner; this agent changed no migration.

## Additive exact amount correction

Root's additive `20260930234000_exact_request_amounts.sql` was applied only to a new disposable154 clone. [sql154-attempt4-candidate234000/result.json](sql154-attempt4-candidate234000/result.json) completed **80 passing cases and no failures**; result SHA-256 `a0b4878c82da8ef9ef037aaadffe9e2c774e01b5970a5c0077134f9144e245d4`.

The reviewed patch SHA-256 is `0ca10f9a069c83f12bc1c1f4529cac2d31579e6132d98382fb57921585b790ba`. It preserves the existing three-argument API signature, application grants and body except its early exact upper-bound guard. Unsafe existing intent, target and suggestion values each abort the migration atomically without changing rows or controls. After legitimate synthetic setup cleanup, all three constraints validate; null/1/maximum controls remain accepted, and nonpositive/unsafe direct values are denied. Unsafe contribution requests return `22023 contribution_amount_not_exact` without mutation.

The clone was removed, all153 shared tables/catalog/cron were preserved, and the shared database still contained154 migrations with latest `20260930230000`. This is verified candidate mechanics, not a claim that234000 is installed in the shared or hosted database. Attempt3's three harness errors for blank SQL-null scalar output remain retained; the final harness uses a JSON object to preserve null explicitly.

## Verified behavior

- Real authenticated contribution calls enforce the requested collection, active membership or readable public group, configured receiver, exact payer hash, positive amount and coherent pending receipt lifetime.
- Identical live requests reuse the same intent. Sixty-one distinct real RPC calls create distinct correctly bound intents. The recent50 window returns a complete pending count of62, deterministic timestamp/ID tie order, an exact old-ID lookup beyond the window, and no foreign-ID leakage. Expired pending rows are reported as expired and excluded from the pending count.
- Readable empty group summaries explicitly return zero balances and zero supporters. Unreadable private groups and forged group IDs remain absent. Actual denied RPCs provide no total; this must stay unavailable in the client.
- All four history sort values accept a genuinely empty result with count0, empty aggregate maps and no cursor. Invalid limits, sort, query and cursor shapes are rejected. A forged anchor is rejected even when its supplied revision equals the current empty revision.
- Equal amount and equal phone suffix do not merge full payer identities. Weak or conflicting payer identifiers, wrong receivers and cross-group parsed targets cannot create a payment candidate. Correct exact payer hashes still require genuine device-attested SMS evidence. Both independently owned intents remain pending.
- Anonymous SQL roles cannot invoke the tested member RPCs. Authenticated callers cannot forge their Collect ID through direct table updates or call the private payment poster.

## Acceptance boundaries

Positive posted-history ordering, tie pagination, filtered matched counts and nonzero full aggregates remain unproved by the baseline and exact-request patch packets. Empty-sort acceptance does not prove the positive sorting algorithm.

Root approved a separate synthetic mechanical fixture using review-only `manual_admin` inputs and the actual `propose_payment_reconciliation_v2`, `approve_payment_reconciliation_v2` and `finalize_approved_reconciliation_v2` APIs. Two distinct approved platform-owner AAL2 sessions supply maker/checker authority; all production confirmation, journal and balance triggers remain active. The evidence digests/references are explicitly synthetic, and this route is not independent provider truth, signed-JWT, device or settlement acceptance. `data_correctness_sql_positive_history_uat.py` exercises this route in a separate disposable154+234000 clone; its results must be bound separately when terminal.

The current recent-intent API has a bounded50 window, a complete count and exact-ID lookup. It has no paging cursor. This packet verifies its actual contract and does not claim a nonexistent pagination workflow.

The native SMS positive candidate path requires a verified capability. This packet exercises genuine allocator denials using explicitly untrusted synthetic parsed input and does not certify native attestation or provider settlement.

## Retained earlier evidence

`sql154-preflight1` retains the original Python compilation failure before SQL execution. `sql154-attempt1` retains the unsafe amount failures plus two harness issues: reconstruction changed raw ACL array order, and an uncast overflow literal selected a nonexistent numeric overload. Attempt2 compares actual role grants and grant options, while retaining raw ACL arrays; it uses an explicit bigint cast for the overflow probe. Neither correction changes application SQL.
