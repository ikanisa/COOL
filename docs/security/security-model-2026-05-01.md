# Security Model - 2026-05-01

## Authorization

- Frontend permission checks are usability hints only. Supabase RLS, security-definer RPCs, and Edge Function auth are the enforcement boundary.
- Platform admin checks use `public.is_admin_user()` and role-assignment RPCs. Admin UI restrictions must map to backend checks.
- Agent folders are documentation-only today. Future agent tools must authenticate callers, use explicit tool permissions, produce structured outputs, and emit audit events for privileged actions.

## Tenant And User Isolation

- User-owned rows are scoped by `auth.uid()`.
- Group and savings data is scoped through membership helpers such as `public.is_group_member()`.
- Bank custody access is handled by bank/group helper RPCs, not by frontend filters.
- Public reads are reserved for catalog/reference data. Runtime app config is exposed only through `public.get_public_app_config()`.

## Payments

- Payment instructions and USSD guidance are not payment confirmation.
- Generic `payment_intents` can be created by users as pending instructions, but status changes are reserved for verified backend evidence, service-role flows, or platform admins.
- Manual allocations must record actor/source metadata and write admin audit logs.

## Outbound Messaging

- User-targeted push sends must respect `notification_preferences`.
- Topic broadcasts require a matching approved `notification_campaign_approvals` row. Approval changes are audit logged.
- Durable notification logs store send status and approval linkage; FCM provider errors are sanitized before storage.

## Files And OCR

- Member-list OCR is admin-only and validates MIME type, base64 shape, and size before sending content to external AI.
- Raw third-party AI error bodies are not logged.

## Secrets And Logs

- Secrets must live in Supabase/GitHub secret stores, never committed files.
- Previously exposed Supabase credentials must be rotated before linked linting, deployment, or migration apply.
- Logs should contain operational issue codes and sanitized provider status, not raw tokens, SMS bodies, uploaded document content, or private keys.
