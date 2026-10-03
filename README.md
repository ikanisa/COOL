# Collect

Collect is a Rwanda-only Flutter and Supabase group-contribution platform. Contributions use whole Rwandan francs through MTN MoMo or Airtel Money USSD. Collect never holds member funds or asks for a MoMo PIN or payment provider OTP. A WhatsApp sign-in code is used only to sign in to Collect.

The member app, Admin PWA, public website, and Supabase contribution APIs share the Rwanda MoMo scope. The current product contract is [docs/PRODUCT.md](docs/PRODUCT.md).

## Product surfaces

- Member Flutter app: `lib/main.dart`
- Admin Flutter web app: `lib/main_admin.dart`
- Member routes: `lib/app/router.dart`
- Admin routes: `lib/admin/admin_router.dart`
- Supabase control plane: `supabase/`
- Read-only Rwanda MoMo linked readiness check: `scripts/rwanda_momo_readiness_uat.sql`

Members sign in with a Rwanda WhatsApp number and complete a Rwanda MoMo profile. User-created groups are private and can be created only on Android. Public groups are platform sponsored.

## MoMo USSD contribution lifecycle

1. A member signs in with WhatsApp OTP and confirms an MTN MoMo or Airtel Money number.
2. An eligible Android member creates a private group after explicit SMS consent and Play Integrity verification.
3. A contributor enters a whole-RWF amount. Collect creates a pending intent bound to the payer and group receiver.
4. Collect opens the provider USSD route. The member reviews and enters the PIN only in the mobile-network prompt.
5. The consented receiver Android app queues likely receipt SMS in encrypted local storage and uploads it from the authenticated account.
6. Edge Functions parse the receipt deterministically. Postgres checks receiver, payer, amount, time window, and transaction ID or sends ambiguity to Admin review. The SMS is candidate evidence, not independent proof of settlement.
7. A production-confirmed contribution needs governed independent reconciliation or an explicitly approved constrained finality policy. The current exact-match allocation and balanced journal must be validated against that policy before release; retries must remain idempotent.

## Admin control plane

The Admin PWA manages Rwanda Groups and Members. Its financial Operations pages cover Payees, Transactions, Reconciliations, and Ledgers. Raw receipt evidence reveal requires a dedicated permission, a reason, and an audit record.

## Validation

All member app, Admin and public website design follows the owner-selected
[`revolut-design` skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>).
It is the sole design authority. Shared Flutter tokens/components and public
CSS implement its platform-specific patterns while keeping Collect's name,
logo, terminology and workflows. Competing design references must be deleted.
Run `make revolut-design-authority` to check reference hygiene; route/state
comparisons and the skill's acceptance evidence are still required for a
100% fidelity claim.

```sh
flutter analyze --no-pub
flutter test --no-pub
./scripts/migrations/validate_supabase_migrations.sh
COLLECT_SKIP_DOTENV=1 SUPABASE_DB_QUERY_MODE=local ./scripts/collect_linked_uat.sh
```

The Android production flavor declares `RECEIVE_SMS` and `CALL_PHONE`, but not `READ_SMS`, `SEND_SMS`, or Call Log access. Google Play permission approval, physical-device MoMo UAT, and owner-reviewed visual, interaction, and accessibility evidence under the sole `revolut-design` skill remain separate release requirements.
