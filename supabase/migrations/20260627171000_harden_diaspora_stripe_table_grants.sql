begin;

revoke select on stripe_customers from anon, authenticated;
revoke select on stripe_payment_methods from anon, authenticated;
revoke select on diaspora_contribution_intents from anon, authenticated;
revoke select on stripe_webhook_events from anon, authenticated;

grant all on stripe_customers to service_role;
grant all on stripe_payment_methods to service_role;
grant all on diaspora_contribution_intents to service_role;
grant all on stripe_webhook_events to service_role;

comment on table stripe_customers is
  'Stripe customer mapping is service-role only; browser clients must use scoped RPCs or Edge Functions.';
comment on table stripe_payment_methods is
  'Stripe payment method metadata is service-role only; browser clients must use scoped RPCs or Edge Functions.';
comment on table diaspora_contribution_intents is
  'Diaspora contribution intents are service-role only for direct table reads; browser clients must use scoped RPCs or Edge Functions.';
comment on table stripe_webhook_events is
  'Stripe webhook payloads are service-role only.';

commit;
