-- The RLS policies for these tables intentionally allow authenticated users to
-- read only their own requests. PostgreSQL table privileges must also allow the
-- SELECT statement before those policies can enforce the row boundary.

grant select on table public.mobile_account_deletion_requests to authenticated;
grant select on table public.mobile_support_requests to authenticated;

-- The SMS-first hardening migration intentionally revoked direct SELECT access
-- to collections.public_status. The client-readable payment/ledger policies
-- must therefore not query that protected column as the caller.
create or replace function public.collection_is_public_approved(
  target_collection_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.collections c
    where c.id = target_collection_id
      and c.public_status = 'public_approved'
      and c.archived_at is null
  );
$$;

revoke all on function public.collection_is_public_approved(uuid)
  from public, anon, authenticated;
grant execute on function public.collection_is_public_approved(uuid)
  to anon, authenticated;

drop policy if exists "payments public posted or scoped" on public.payments;
create policy "payments public posted or scoped"
on public.payments
for select
using (
  (
    status = 'posted'
    and public.collection_is_public_approved(collection_id)
  )
  or contributor_user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "ledger public collection credit or scoped"
  on public.ledger_entries;
create policy "ledger public collection credit or scoped"
on public.ledger_entries
for select
using (
  (
    entry_type = 'collection_credit'
    and public.collection_is_public_approved(collection_id)
  )
  or user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);
