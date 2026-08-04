# Collect Product Language Contract

Date: 2026-07-30  
Status: active implementation contract; product-owner acceptance pending

## Purpose

Keep Collect's member, contribution, ledger, receiver, and support language
stable across mobile, public, and Admin surfaces. Revolut may inform hierarchy
and interaction grammar, but not Collect's product or regulatory meaning.

## Canonical user-facing terms

| Meaning | Use | Avoid |
| --- | --- | --- |
| A person belonging to a group | `member` / `members` | `supporter`, `people` |
| The user's group action | `contribute` / `contribution` | generic `pay` / `payment` |
| Confirmed accumulated group value | `total collected` or `confirmed contributions` | `balance`, `available funds`, `account balance` |
| The confirmed history | `ledger` or `activity` | `bank statement`, `account transactions` |
| The mobile-money handoff | `Continue with MoMo` or `Contribute with MoMo` | `send from Collect`, `Collect transfer` |
| A pending contribution request | `contribution pending` | `money held`, `funds available` |
| Group administrator | `owner` / `admin` | `bank administrator`, `account holder` |
| Support channel | `WhatsApp support` | exposing a private receiver or transaction in prefilled text |

## Allowed technical exceptions

- Internal data models and backend contracts may retain established fields such
  as `supporterLabel`, `payment_intent`, or `payment_event` where renaming would
  break an API or migration contract.
- `MoMo Pay code` is a receiver-mode proper term, not a generic Collect action.
- Admin audit and operational surfaces may use backend contract names when the
  technical distinction is necessary and clearly scoped.

Technical exceptions must not leak into ordinary member-facing action labels.

## Count and grammar rules

- `0 supported groups`
- `1 supported group`
- `2 supported groups`
- `1 member`
- `2 members`
- Avoid manual plural strings when the count is dynamic.

## Regulated-language boundary

Collect records and verifies group contributions. Unless separately authorized
and implemented through a regulated provider, it must not claim or imply:

- deposit accounts;
- custody or stored balances;
- cards or cash withdrawal;
- investments, crypto, or exchange;
- credit or payment origination;
- protected deposits;
- internal person-to-person transfers.

## Privacy boundary

- Full receiver details appear only in the explicit contribution review
  context.
- Public, group-discovery, recovery, Help, and comparison evidence must not
  expose receiver numbers, raw SMS, OTPs, or private transaction content.
- External support links must not prefill secrets or private financial data.

## Validation

1. Widget tests cover zero, singular, and plural labels.
2. Source-contract tests reject retired member-facing `Pay` and `People`
   actions in the group-detail surface.
3. Product Design comparisons verify that monetary heroes are labelled as
   confirmed ledger totals.
4. Product review dispositions any remaining `supporter` or `payment` label as
   internal-contract, Admin-specific, or a defect.
