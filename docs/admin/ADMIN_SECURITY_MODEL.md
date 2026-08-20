# Collect Admin Security Model

Date: 2026-08-15

## Current Guarantees

- Flutter ships no service-role key.
- Flutter ships no OpenAI, WhatsApp, SMS hook, or internal function secrets.
- The customer app has no `/admin` route.
- The admin app defaults to `/admin/login` for unauthenticated users and
  `/admin/denied` for authenticated users without admin permissions.
- Admin pages fetch data through Supabase RPCs and safe views. They do not read
  raw SMS or privileged base tables directly from Flutter.
- Raw SMS reveal is routed through `admin_reveal_raw_sms`, requires a reason,
  and creates an audit/sensitive-access record before returning the message.
- WhatsApp OTP accepts any valid international phone; authorization is decided
  after verification by `admin_current_user` and server-side RBAC, not by a
  phone number compiled into the browser.
- Payment intents and posted transactions use separate list/detail RPCs.
- Admin-role changes and notification retries require manage permissions,
  reasons, audited mutations, and server-side safety checks.
- Notification message bodies and device tokens remain outside admin list and
  detail responses.
- Realtime invalidation carries domain names only and never raw SMS, phone,
  message-body, or device-token data.

## Authorization Boundary

Client-side guards are convenience only. Admin behavior is enforced server-side
through RLS, security-definer RPCs, role/permission tables, and audited
permission checks.

## Data Boundary

- Raw phone numbers, raw SMS bodies, parser payloads, and MOMO evidence must not
  be logged by Flutter or Edge Functions.
- Raw SMS reveal must require permission, reason, and audit.
- Payment allocation, ledger correction, role change, setting change, and
  feature flag change must use backend mutations with audit metadata.
- Security-definer collection helpers permit browser callers to evaluate only
  their own `auth.uid()`; service-role workflows retain explicit cross-user
  evaluation.

## Secret Boundary

Flutter-visible env remains client-safe:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_PUBLIC_URL`
- `ADMIN_APP_URL`
- `enable_sms_reader`
- `enable_android_sms_access`
- `ENABLE_ADMIN_PANEL`
- `ENABLE_ADMIN_DEV_TOOLS`
- `APP_ENVIRONMENT`

Server-only secrets belong in Supabase or CI secret stores.
