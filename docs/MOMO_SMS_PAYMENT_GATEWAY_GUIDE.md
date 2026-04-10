# M-Money SMS Payment Gateway Guidance

This document defines the target architecture for Cool's M-Money SMS based payment gateway.

Cool does not use MoMo APIs or server-side MoMo webhooks. Payment initiation remains payer-owned USSD. Payment verification comes from Android SMS access, Supabase ingest, parsing, allocation, and ledger posting.

## Purpose

The gateway must do four things reliably:

1. Capture and normalize valid M-Money confirmation SMS.
2. Separate app-linked payments from non-app wallet activity.
3. Allocate app-linked payments to the correct user, group, order, subscription, or managed collection flow.
4. Keep raw SMS, parsed payment events, allocations, ledgers, and domain balances in sync.

## Parties

- `Payer`: the person who sends money through USSD.
- `Payee`: the owner of the receiving MoMo line or receiving MoMo code that gets the payment and receives the SMS.
- `Cool app`: captures SMS, parses payment evidence, matches it to app activity, and updates records.
- `Partner service`: shared-receiver flow with dedicated receiving code(s) for support, orders, or other managed collections.
- `Bank`: custody flow with dedicated receiving code(s) for savings collections and manual allocation.

In user-to-user group examples, the payer is often `User A` and the payee/admin who receives the confirmation SMS is `User B`.

## Core Principle

SMS is payment evidence, not the ledger entry.

The correct model is:

1. `Payment evidence`: raw SMS and parsed payment event.
2. `Payment intent`: an app-side pending payment obligation, such as a group contribution, order, or subscription.
3. `Payment allocation`: a decision that links one parsed payment event either to one app intent or to wallet activity.
4. `Ledger posting`: accounting and balance effects after allocation is confirmed.
5. `Exception handling`: unresolved or ambiguous events routed to manual review.

No user-facing balance or posted ledger should be derived directly from a raw SMS or from a parsed event before allocation is confirmed.

## Receiver-First Routing

The first routing key is always the receiving account, not the payer name.

Every incoming payment event must resolve to one `payment_receiver_account` with:

- `owner_type`: `user`, `partner`, `bank`, `app`
- `owner_id`
- `provider`
- `phone_number` or `merchant_code`
- `purpose`
- `country_code`
- `is_active`

Recommended receiver purposes:

- `personal_wallet_or_user_groups`
- `bank_group_savings`
- `partner_support`
- `partner_order`
- `cool_subscription`

This is the rule that makes the rest of the gateway safe:

- Personal user receiver accounts may fall back to `wallet_transaction`.
- Shared or dedicated receiver accounts must never fall back to wallet. If unmatched, they go to `exception/unallocated`.

## Matching Hierarchy

Auto-match only when the result is unique and defensible.

Recommended order:

1. Exact pending intent match.
2. Unique receiver-account scoped match.
3. Unique member/group match under the receiving admin.
4. Wallet fallback for personal receiver accounts only.
5. Exception queue for all ambiguous or unmatched cases.

Recommended matching signals:

- Receiving account or receiving code
- Amount
- Currency
- Transaction time window
- Registered payer full MoMo number when available
- Registered payer masked suffix
- Normalized payer name and known aliases
- Existing pending intent reference
- Parsed MoMo transaction id

Do not auto-match from payer name alone.

Do not auto-match from the last 3 digits alone.

`name + masked digits` is supporting evidence only. It becomes acceptable for auto-allocation only when combined with receiver account context, amount, time window, and one unique candidate.

## Product Flow Rules

### 1. User Personal Wallet

This is statement recording only.

- If a payment lands on a personal user receiver account and no safe app-linked target exists, classify it as `wallet_transaction`.
- Record it for statements.
- Do not use it to compute an app-maintained wallet balance.
- Do not let it affect group, subscription, or managed-collection ledgers.

### 2. User-Created Groups and Community Groups

Preferred flow:

1. Member starts contribution in the app.
2. App creates a pending contribution intent.
3. Member pays via USSD.
4. Admin/payee receives M-Money SMS.
5. SMS is captured, parsed, matched to the pending contribution, and posted.

Auto-allocation rules:

- If there is one pending contribution intent for that payer, payee receiver account, amount, and recent window, allocate automatically.
- If there is no pending contribution intent, only auto-allocate when the payer identity maps to exactly one eligible member in exactly one group under that payee.
- If the payer belongs to multiple groups under the same admin or multiple pending contributions exist, send to manual review.

### 3. Bank Group Savings

This is a shared receiving code flow.

- Every payment to the bank savings code belongs either to one member contribution or to the bank exception queue.
- Never classify unmatched bank-code payments as wallet.
- Use registered group member payment identities to match payer name, number, amount, and receiving code.
- Post unmatched items to an unallocated bank receipt state and expose them in admin allocation tools.

### 4. Partner Support

If partner support uses a dedicated MoMo code:

- Route by that dedicated receiver account.
- Match to a pending support intent when one exists.
- If support can be paid without a pre-created intent, still keep unmatched receipts under partner-support exceptions, not wallet.

### 5. Partner Orders

This should be intent-driven.

1. User places order in the app.
2. App creates a pending order payment intent.
3. User pays to the partner-order receiver code.
4. Parsed payment event is matched to exactly one pending order.
5. Order becomes paid and ready for dispatch.

If multiple orders are possible for the same payer and amount, send to manual review.

### 6. Cool Subscriptions

This should also be intent-driven.

- Create a pending subscription payment intent before the user pays.
- Match incoming payment on the subscription receiver code to that intent.
- After posting, activate or renew the subscription in the same transaction scope.

## Recommended Data Model

Use the current MoMo pipeline as the base and tighten the role of each table.

### Existing Foundation

- `momo_sms_raw`: raw evidence
- `momo_sms_parsed`: normalized payment event
- `momo_reconciliations`: allocation decision
- `momo_ledger_entries`: posted accounting result

### Recommended Additions

- `payment_receiver_accounts`
- `payment_identities`
- `payment_intents`
- `payment_exceptions`
- `ledger_transactions`
- `ledger_postings`

### Suggested Responsibilities

`payment_receiver_accounts`

- defines every valid receiving line or code
- tells the matcher which flows are legal for that receiver

`payment_identities`

- stores registered payer identity for users and members
- stores normalized full name
- stores aliases
- stores full number when known
- stores masked suffix used in SMS matching

`payment_intents`

- one row per app-initiated payable item
- example types: `group_contribution`, `bank_group_saving`, `partner_support`, `partner_order`, `subscription`
- holds expected amount, currency, receiver account, payer, domain record, and lifecycle status

`payment_exceptions`

- one row per unresolved parsed payment event
- holds reason code, candidate target ids, assigned reviewer, and resolution audit

`ledger_transactions` and `ledger_postings`

- store the accounting effect only after allocation is confirmed
- support suspense or unallocated receipt accounting for shared receiver codes

## State Model

Recommended event lifecycle:

1. `captured`
2. `parsed`
3. `classified`
4. `matched`
5. `posted`

Recommended exception lifecycle:

1. `needs_review`
2. `allocated_manually`
3. `rejected`
4. `refunded`

Recommended intent lifecycle:

1. `pending`
2. `matched`
3. `posted`
4. `cancelled`
5. `expired`

## Reconciliation Invariants

These must hold at all times:

1. One raw SMS must end in exactly one parse outcome: `parsed`, `ignored`, or `failed`.
2. One parsed incoming payment event must have exactly one active allocation state: `wallet`, `matched`, `exception`, or `rejected`.
3. One matched allocation must point to exactly one target domain record.
4. One matched allocation must create exactly one posted ledger transaction.
5. Shared receiver accounts must never leave money orphaned outside either `posted` or `exception`.
6. Wallet statement rows must never be used as authoritative stored-value balances.
7. Manual allocations and rejections must always record actor, time, reason, and previous state.

## UI and UX Rules

### Permission UX

- SMS access must be explicit and reversible.
- The app must deep link users to Android app settings when permission is denied or needs manual management.
- The app access surface must clearly explain what SMS is used for and what is not uploaded.

### Sync UX

Show:

- permission status
- last sync status
- last successful parse
- exception count
- manual review count for admins or partners

### Wallet UX

- show recorded transactions only
- do not show wallet balances
- do not label wallet history as authoritative cash balance

### Admin and Partner UX

Every shared receiver flow needs:

- exception queue
- candidate suggestions
- approve or allocate action
- reject action
- full audit trail

## Current Repository Direction

Current anchors in this repository:

- ingest function: `supabase/functions/sms-ingest/index.ts`
- parser and matcher: `supabase/functions/parse-momo-sms/index.ts`
- bank manual allocation flow: `supabase/migrations/20260315124500_bank_admin_manual_allocation_actions.sql`
- generic review queue: `supabase/migrations/20260322173000_momo_sms_manual_review_admin_queue.sql`

This is an evolution, not a rewrite.

The current pipeline already has raw capture, parsing, reconciliation, and manual review foundations. The main missing structure is a stricter separation between:

- payment evidence
- payment intent
- payment allocation
- posted ledger
- exception handling

## Immediate Implementation Priorities

1. Add `payment_receiver_accounts` and route matching off the receiving account first.
2. Add a unified `payment_intents` layer for group contributions, bank savings, partner orders, partner support, and subscriptions.
3. Restrict user-visible ledger or statement summaries to posted results, and keep wallet as statement-only.
4. Generalize bank manual allocation into a generic positive allocation workflow for all shared receiver accounts.
5. Tighten auto-match rules so `name + masked digits` is never the sole auto-allocation key.
6. Add operational reports for orphaned events, duplicate allocations, unmatched shared-code payments, and ledger-domain drift.

## Decision Summary

The gateway should be implemented as:

- SMS evidence capture
- parsed payment event normalization
- receiver-first routing
- intent-aware matching
- explicit allocation
- posted ledger update
- exception queue for ambiguous or unmatched shared-code receipts

That model is the safest way to support:

- user wallet statements
- user-created group contributions
- community group collections
- bank custody savings allocations
- partner support
- partner orders
- Cool subscriptions

without introducing MoMo APIs or server-side payment webhooks.
