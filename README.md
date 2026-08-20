# Collect

Collect is a Flutter and Supabase group-contribution platform. Members create
an exact EUR transfer request in the app, copy the approved beneficiary details,
and open Revolut to complete a SEPA bank transfer. Collect never initiates or
custodies the transfer and has no card, Stripe, direct-debit, or payment-provider
API integration.

An incoming bank SMS or email is candidate evidence only. A contribution becomes
confirmed only after the receipt matches an imported bank statement during the
daily reconciliation. The resulting debit and credit journal is immutable and
balanced.

The current product source of truth is [docs/PRODUCT.md](docs/PRODUCT.md).

## Product surfaces

- Member Flutter app: `lib/main.dart`
- Admin Flutter web app: `lib/main_admin.dart`
- Member routes: `lib/app/router.dart`
- Admin routes: `lib/admin/admin_router.dart`
- Supabase control plane: `supabase/`
- Full bank lifecycle rollback UAT: `scripts/bank_transfer_rollback_uat.sql`

Member navigation remains Home, Groups, and Settings. Bank beneficiary details
are available in Settings and in every transfer request. The beneficiary is
centrally governed and cannot be replaced by a group owner.

## Bank contribution lifecycle

1. A member signs in with WhatsApp OTP and joins or creates a group.
2. The member enters a EUR amount and Collect creates a unique `COL-…` reference.
3. Collect shows the approved beneficiary name, IBAN, BIC, amount, and reference.
4. `Open Revolut` deep-links to the Revolut app. The member selects the saved
   beneficiary, enters the amount/reference, and authorizes the transfer there.
5. Controlled bank SMS/email ingestion records deterministic, deduplicated
   evidence. This moves the request only to `received_unreconciled`.
6. An authorized administrator imports a CSV, JSON, MT940, or CAMT.053 statement.
7. Daily reconciliation matches bank identifiers, reference, amount, currency,
   and date; unresolved items become exceptions.
8. A confirmed receipt posts one bank-cash debit and one group-liability credit,
   creates one member notification, and contributes to the daily close.

## Admin control plane

The Admin PWA manages groups, members, admin users, bank destinations and their
approvals, transfer requests, canonical bank transactions, SMS/email/statement
evidence, reconciliation runs, exceptions, maker-checker allocation requests,
immutable journals, notifications, audit logs, feature flags, settings, and
system health.

Bank-detail and manual-allocation changes require separate maker and checker
accounts. Raw evidence reveal requires a dedicated permission, a reason, and an
audit record.

## Validation

```sh
/Users/jeanbosco/Developer/flutter/bin/flutter analyze
/Users/jeanbosco/Developer/flutter/bin/flutter test
./scripts/migrations/validate_supabase_migrations.sh
COLLECT_SKIP_DOTENV=1 SUPABASE_DB_QUERY_MODE=local ./scripts/collect_linked_uat.sh
./scripts/collect_edge_auth_contract_uat.sh
```

The public production Android flavor has no SMS, inbox, or phone-call
permission. The separately signed `internal_receiver` flavor is controlled
operations infrastructure for new beneficiary-bank notification SMS and posts
to the same production bank-evidence API; it cannot confirm settlement.
