insert into feature_flags (key, enabled, description)
values
  ('ENABLE_ANDROID_SMS_ACCESS', false, 'Android-only SMS app access for consented MoMo SMS ingestion'),
  ('ENABLE_SMS_READER', false, 'Restricted SMS reader integration for approved internal builds'),
  ('ADMIN_PANEL_ENABLED', true, 'Platform admin panel access through Supabase Auth and admin roles')
on conflict (key) do update set description = excluded.description;

insert into system_settings (key, value, description, is_sensitive)
values
  ('payments.mode', '{"provider":"payment_intent_momo_ussd","country":"RW","currency":"RWF"}'::jsonb, 'Collect payment mode: payment intent, MoMo USSD launch, and automated SMS allocation', false),
  ('sms.parser.schema_version', '"collect.sms_parser.v1"'::jsonb, 'Active SMS parser structured output schema version', false)
on conflict (key) do update
set value = excluded.value,
    description = excluded.description,
    is_sensitive = excluded.is_sensitive,
    updated_at = now();
