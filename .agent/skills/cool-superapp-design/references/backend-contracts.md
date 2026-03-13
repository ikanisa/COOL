# Backend Contracts

Use this file when the task touches Supabase schema, RPCs, edge functions, secrets, or frontend-to-backend integration.

## Source Of Truth

Backend work in this repo spans:

- `supabase/migrations/`
- `supabase/functions/`
- repository calls in `lib/features/**/repositories/`
- services that depend on Supabase or edge functions

Do not assume local files equal deployed reality. Validate remote state when the task depends on current deployment.

## Verify Remote State

Use these before claiming a backend feature is live:

```sh
supabase migration list --linked
supabase functions list --project-ref <project-ref>
set -a && source .env && set +a && psql "$DATABASE_URL" -Atc \
  "select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','v','m') order by relname;"
set -a && source .env && set +a && psql "$DATABASE_URL" -Atc \
  "select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by proname;"
```

## Public Relations Used By The App

The app currently depends on these public relations:

### Core app and config

- `users`
- `app_config`
- `quick_actions`
- `partners`
- `partner_services`
- `vehicle_types`
- `supported_countries`
- `supported_country_momo_reference`
- `user_fcm_tokens`

### Groups and community finance

- `groups`
- `group_members`
- `group_contributions`

### MoMo and payment verification

- `pending_transactions`
- `momo_sms_raw`
- `momo_parse_attempts`
- `momo_sms_parsed`
- `momo_reconciliations`
- `momo_ledger_entries`
- `momo_validation_issues` view

### Mobility

- `driver_profiles`
- `driver_subscriptions`
- `mobility_trips`

### Credit

- `credit_scores`
- `credit_score_runs`
- `partner_credit_applications`

### Engagement and discovery

- `cool_status`
- `cool_events`
- `cool_invite_attributions`
- `cool_missions`
- `cool_mission_progress`
- `cool_seasons`

### Rayon and partners

- `rs_fan_memberships`
- `rs_fan_clubs`
- `rs_fan_club_members`
- `rs_achievements`
- `rs_matches`
- `rs_tickets`
- `rs_shop_products`
- `rs_shop_orders`
- `rs_initiatives`
- `rs_initiative_contributions`
- `wallet_passes`
- `wallet_pass_events`

## RPCs Used By The App

Current app-facing RPC usage includes:

- `create_group_atomic`
- `get_group_invite_preview`
- `join_group_via_invite`
- `get_group_savings_statement_entries`
- `get_nearby_drivers`
- `get_scheduled_trips`
- `get_rayon_member_registry`
- `get_momo_validation_issues`
- `repair_momo_validation_issue`
- `refresh_my_credit_score`
- `create_partner_credit_application`
- `create_referral_invite`
- `mark_referral_invite_opened`
- `activate_referral_invite`
- `activate_referral_invite_for_user`
- `apply_cool_event`
- `purge_mock_batch`
- `rs_apply_membership_points`

Design implication:

- if a flow depends on one of these RPCs, the UI should handle missing-function or degraded-backend states gracefully
- admin and validation flows should surface backend unavailability plainly rather than failing with generic copy

## Edge Functions In The Repo

Local edge-function code exists for:

- `send-otp`
- `verify-otp`
- `delete-account`
- `parse-momo-sms`
- `maps-gateway`
- `expire-trips`
- `rs-scan-ticket`
- `wallet-issuer`

## Edge Functions Called By The App

The Flutter app currently invokes:

- `send-otp`
- `verify-otp`
- `delete-account`
- `parse-momo-sms`
- `maps-gateway`
- `rs-scan-ticket`
- `wallet-issuer`

If one of these is not deployed or not configured, the UX must not pretend the feature is healthy.

## Fullstack Domain Contracts

### Auth

Frontend depends on:

- `send-otp`
- `verify-otp`
- `delete-account`
- `users`
- `otp_codes`

The UX should assume:

- WhatsApp OTP, not SMS OTP and not MoMo auth
- profile completion is optional after verification

### Groups

Frontend depends on:

- `groups`
- `group_members`
- `group_contributions`
- `create_group_atomic`
- `get_group_invite_preview`
- `join_group_via_invite`

### MoMo

Frontend depends on:

- country-configured USSD route data
- Android SMS ingestion on device
- `momo_sms_raw`
- `momo_sms_parsed`
- `momo_reconciliations`
- `momo_ledger_entries`
- `parse-momo-sms`

Design rule:

- pending, draft, parsed, and posted all matter and should be reflected honestly in UI or admin diagnostics

### Mobility

Frontend depends on:

- `driver_profiles`
- `driver_subscriptions`
- `mobility_trips`
- `get_nearby_drivers`
- `get_scheduled_trips`
- `maps-gateway`
- `expire-trips`

### Rayon and partner transactions

Frontend depends on:

- `rs_*` commerce and membership tables
- `rs-scan-ticket`
- `wallet-issuer`
- `rs_apply_membership_points`

Design rule:

- ticket or order status must stay pending until payment confirmation truly completes

### Credit

Frontend depends on:

- `credit_scores`
- `credit_score_runs`
- `partner_credit_applications`
- `refresh_my_credit_score`
- `create_partner_credit_application`

## Secrets And Configuration

Important remote secrets include:

- Supabase URL and keys
- WhatsApp credentials
- OTP secrets
- AI parse provider keys
- Google Maps server key
- Google Wallet issuer and service-account secrets

Use `supabase secrets list --project-ref <project-ref>` to confirm presence.

## Operational Truthfulness Rules

- Never claim a backend feature is complete because a local file exists.
- Never assume deployed edge functions have all required secrets.
- If remote deployment is missing, surface it as an operational gap, not as a frontend polish task.
- When a screen depends on remote configuration, state that explicitly in the implementation plan.

## Example Audit Pattern

When investigating a broken feature:

1. identify the repository call or service call
2. identify the table, RPC, or edge function it depends on
3. verify local code exists
4. verify remote object exists
5. verify secrets or rollout config if an edge function is involved
6. only then decide whether the bug is UI, state, backend, or deployment

## Current Deployment Note

Remote deployment state is temporal and must be rechecked. A March 13, 2026 audit on the app's configured project found:

- migrations aligned through the latest local migration
- database relations and RPCs used by the app present
- `wallet-issuer` code present locally but not deployed remotely
- `maps-gateway` deployed, but remote secret hygiene still needed for the preferred Google Maps server key path

Do not hardcode this note into user-facing claims without re-verifying.
