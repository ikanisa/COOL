-- Supabase security advisor 0010: public views should run with the querying
-- user's privileges/RLS context instead of the view owner's privileges.

grant select (
  id,
  public_id,
  display_name,
  avatar_url,
  anonymity_default,
  created_at
) on public.profiles to anon, authenticated;

grant select (
  id,
  slug,
  creator_user_id,
  title,
  description,
  category,
  cover_image_url,
  currency,
  target_amount_rwf,
  deadline_at,
  visibility,
  public_status,
  is_recurring,
  recurring_rule,
  allow_anonymous,
  contribution_visibility,
  receiver_display_label,
  created_at,
  updated_at,
  archived_at
) on public.collections to anon, authenticated;

grant select (
  id,
  parsed_event_id,
  payment_intent_id,
  collection_id,
  contributor_user_id,
  contributor_public_id,
  amount_rwf,
  currency,
  transaction_id,
  source,
  status,
  anonymity_choice,
  posted_at,
  created_at
) on public.payments to anon, authenticated;

grant select (
  id,
  payment_id,
  collection_id,
  user_id,
  entry_type,
  amount_rwf,
  currency,
  visibility,
  created_at
) on public.ledger_entries to anon, authenticated;

drop policy if exists "payments public posted or scoped" on public.payments;
drop policy if exists "payments read scoped" on public.payments;
create policy "payments public posted or scoped" on public.payments
for select
using (
  (
    status = 'posted'
    and exists (
      select 1
      from public.collections c
      where c.id = payments.collection_id
        and c.public_status = 'public_approved'
        and c.archived_at is null
    )
  )
  or contributor_user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "ledger public collection credit or scoped" on public.ledger_entries;
drop policy if exists "ledger read scoped" on public.ledger_entries;
create policy "ledger public collection credit or scoped" on public.ledger_entries
for select
using (
  (
    entry_type = 'collection_credit'
    and exists (
      select 1
      from public.collections c
      where c.id = ledger_entries.collection_id
        and c.public_status = 'public_approved'
        and c.archived_at is null
    )
  )
  or user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

alter view public.public_profiles_view set (security_invoker = true);
alter view public.collection_summary_view set (security_invoker = true);
alter view public.public_collections_view set (security_invoker = true);
alter view public.public_contributions_view set (security_invoker = true);
alter view public.member_collection_summary_view set (security_invoker = true);
alter view public.parsed_payment_events_review_view set (security_invoker = true);
alter view public.member_collections_view set (security_invoker = true);
alter view public.member_contributions_view set (security_invoker = true);
alter view public.member_public_collection_requests_view set (security_invoker = true);
