# Collect

Collect is a Flutter and Supabase group-contribution platform with two explicit
geographic rails: Rwanda uses RWF MoMo USSD and consented Android receipt SMS;
the diaspora uses Revolut or SEPA bank transfer. Collect never custodies money
or asks for a MoMo PIN, bank password, card detail, or OTP.

Rwanda receipt SMS is parsed deterministically and can post only after one exact
receiver, payer, amount, time-window, and transaction-ID match. Diaspora bank
evidence remains subject to statement reconciliation. Ledger posting is
idempotent, immutable, and balanced.

The current product source of truth is [docs/PRODUCT.md](docs/PRODUCT.md).

## Product surfaces

- Member Flutter app: `lib/main.dart`
- Admin Flutter web app: `lib/main_admin.dart`
- Member routes: `lib/app/router.dart`
- Admin routes: `lib/admin/admin_router.dart`
- Supabase control plane: `supabase/`
- Full bank lifecycle rollback UAT: `scripts/bank_transfer_rollback_uat.sql`

Member navigation remains Home, Groups, and Settings. WhatsApp onboarding
suggests the profile country and Rwanda MoMo number; members can edit their
country and regional route details. User-created groups are private and can be
created only on Android. Public groups are platform-sponsored.

## Rwanda MoMo lifecycle

1. A Rwanda member signs in with WhatsApp OTP and confirms or edits the suggested
   MTN MoMo/Airtel Money number.
2. An Android member may create a private group after SMS consent and Play
   Integrity verification; the profile MoMo route becomes the receiver.
3. A contributor enters a whole-RWF amount and Collect creates one payer-bound
   pending intent.
4. Collect opens the provider USSD route. The member reviews and enters the PIN
   only in the mobile-network prompt.
5. The receiver Android app queues likely receipt SMS in encrypted local storage,
   then uploads it from the authenticated, consented account.
6. Edge Functions parse the receipt deterministically; Postgres allocates one
   exact match or sends ambiguous/incomplete evidence to admin review.
7. One successful allocation posts the transaction, member/group ledger entries,
   audit event, and notification atomically.

Diaspora members use the separately governed Revolut/SEPA lifecycle, including
unique references, controlled bank evidence, and statement reconciliation.

## Admin control plane

The Admin PWA keeps Groups and Members separate, then presents only four
financial Operations pages: Payees, Transactions, Reconciliations and Ledgers.
Each page normalizes Rwanda MoMo/SMS and diaspora account records without
weakening the different settlement and approval controls underneath them.

Diaspora bank-detail and manual-allocation changes require separate maker and
checker accounts. Rwanda review can complete only a receipt/intent pair that
still passes the strict receiver, payer, amount and timing checks. Raw evidence
reveal requires a dedicated permission, a reason and an audit record.

## Validation

```sh
/Users/jeanbosco/Developer/flutter/bin/flutter analyze
/Users/jeanbosco/Developer/flutter/bin/flutter test
./scripts/migrations/validate_supabase_migrations.sh
COLLECT_SKIP_DOTENV=1 SUPABASE_DB_QUERY_MODE=local ./scripts/collect_linked_uat.sh
./scripts/collect_edge_auth_contract_uat.sh
```

The Android production flavor declares `RECEIVE_SMS` and `CALL_PHONE` for the
Rwanda route, but not `READ_SMS`, `SEND_SMS`, or Call Log access. Google Play
restricted-permission approval and physical-device MoMo UAT remain release
gates; source implementation alone does not establish either.
