-- Tighten admin RBAC so each seeded role only carries the permissions needed
-- for its operational lane. The original seed gave several non-owner roles the
-- same broad permission set and left compliance_admin without permissions.

update admin_roles
set description = case name
  when 'platform_owner' then 'Full platform administration'
  when 'compliance_admin' then 'Audit, privacy, sensitive access, and compliance review'
  when 'operations_admin' then 'Collection and operational queue management'
  when 'payments_admin' then 'Payment event, allocation, payment, and ledger operations'
  when 'moderation_admin' then 'Public approval and moderation operations'
  when 'support_admin' then 'Read support-oriented users, collections, receivers, and events'
  when 'read_only_admin' then 'Read-only operational visibility'
  else description
end
where name in (
  'platform_owner',
  'compliance_admin',
  'operations_admin',
  'payments_admin',
  'moderation_admin',
  'support_admin',
  'read_only_admin'
);

delete from admin_role_permissions arp
using admin_roles ar
where arp.role_id = ar.id
  and ar.name <> 'platform_owner'
  and ar.name in (
    'compliance_admin',
    'operations_admin',
    'payments_admin',
    'moderation_admin',
    'support_admin',
    'read_only_admin'
  );

with desired(role_name, permission_name) as (
  values
    ('compliance_admin', 'overview.read'),
    ('compliance_admin', 'users.read'),
    ('compliance_admin', 'sms.metadata.read'),
    ('compliance_admin', 'sms.raw.reveal'),
    ('compliance_admin', 'payment_events.read'),
    ('compliance_admin', 'payments.read'),
    ('compliance_admin', 'ledger.read'),
    ('compliance_admin', 'audit.read'),
    ('compliance_admin', 'system_health.read'),

    ('operations_admin', 'overview.read'),
    ('operations_admin', 'public_requests.read'),
    ('operations_admin', 'collections.read'),
    ('operations_admin', 'collections.moderate'),
    ('operations_admin', 'users.read'),
    ('operations_admin', 'receivers.read'),
    ('operations_admin', 'sms.metadata.read'),
    ('operations_admin', 'payment_events.read'),
    ('operations_admin', 'payments.read'),
    ('operations_admin', 'ledger.read'),
    ('operations_admin', 'audit.read'),
    ('operations_admin', 'system_health.read'),

    ('payments_admin', 'overview.read'),
    ('payments_admin', 'collections.read'),
    ('payments_admin', 'receivers.read'),
    ('payments_admin', 'sms.metadata.read'),
    ('payments_admin', 'payment_events.read'),
    ('payments_admin', 'payment_events.reparse'),
    ('payments_admin', 'payments.read'),
    ('payments_admin', 'payments.allocate'),
    ('payments_admin', 'ledger.read'),
    ('payments_admin', 'audit.read'),
    ('payments_admin', 'system_health.read'),

    ('moderation_admin', 'overview.read'),
    ('moderation_admin', 'public_requests.read'),
    ('moderation_admin', 'public_requests.review'),
    ('moderation_admin', 'collections.read'),
    ('moderation_admin', 'collections.moderate'),
    ('moderation_admin', 'users.read'),
    ('moderation_admin', 'audit.read'),
    ('moderation_admin', 'system_health.read'),

    ('support_admin', 'overview.read'),
    ('support_admin', 'public_requests.read'),
    ('support_admin', 'collections.read'),
    ('support_admin', 'users.read'),
    ('support_admin', 'receivers.read'),
    ('support_admin', 'sms.metadata.read'),
    ('support_admin', 'payment_events.read'),
    ('support_admin', 'payments.read'),
    ('support_admin', 'audit.read'),
    ('support_admin', 'system_health.read'),

    ('read_only_admin', 'overview.read'),
    ('read_only_admin', 'public_requests.read'),
    ('read_only_admin', 'collections.read'),
    ('read_only_admin', 'users.read'),
    ('read_only_admin', 'receivers.read'),
    ('read_only_admin', 'sms.metadata.read'),
    ('read_only_admin', 'payment_events.read'),
    ('read_only_admin', 'payments.read'),
    ('read_only_admin', 'ledger.read'),
    ('read_only_admin', 'audit.read'),
    ('read_only_admin', 'feature_flags.read'),
    ('read_only_admin', 'settings.read'),
    ('read_only_admin', 'system_health.read'),
    ('read_only_admin', 'admin_users.read')
)
insert into admin_role_permissions (role_id, permission_name)
select ar.id, ap.name
from desired d
join admin_roles ar on ar.name = d.role_name
join admin_permissions ap on ap.name = d.permission_name
on conflict do nothing;

create or replace function public.current_user_is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin(auth.uid());
$$;

create or replace function review_public_collection(
  request_id uuid,
  approved boolean,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public_collection_requests;
begin
  if not (
    public.current_user_is_platform_admin()
    or public.has_admin_permission('public_requests.review', auth.uid())
  ) then
    raise exception 'Admin permission public_requests.review required';
  end if;

  select * into request_row
  from public_collection_requests
  where id = request_id
  for update;

  if not found then
    raise exception 'Public collection request not found';
  end if;

  update public_collection_requests
    set status = case when approved then 'approved' else 'rejected' end,
        admin_user_id = auth.uid(),
        admin_note = p_admin_note,
        reviewed_at = now()
    where id = request_id;

  update collections
    set public_status = case when approved then 'public_approved'::collection_visibility else 'public_rejected'::collection_visibility end,
        visibility = case when approved then 'public_approved'::collection_visibility else 'private'::collection_visibility end
    where id = request_row.collection_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    case when approved then 'collection.public_approved' else 'collection.public_rejected' end,
    'collection',
    request_row.collection_id,
    jsonb_build_object('request_id', request_id, 'admin_note', p_admin_note)
  );
end;
$$;

create or replace function manual_allocate_parsed_payment_event(
  event_id uuid,
  target_collection_id uuid,
  target_payment_intent_id uuid default null,
  reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if coalesce(trim(reason), '') = '' then
    raise exception 'Manual allocation reason is required';
  end if;
  if not (
    public.user_is_collection_admin(target_collection_id, auth.uid())
    or public.has_admin_permission('payments.allocate', auth.uid())
  ) then
    raise exception 'Admin permission payments.allocate required';
  end if;
  return post_payment_from_event(event_id, target_payment_intent_id, target_collection_id, 'manual', reason, auth.uid());
end;
$$;
