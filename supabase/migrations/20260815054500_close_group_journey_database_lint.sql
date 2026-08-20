-- Close the two warning-level PL/pgSQL findings retained by the group-journey
-- audit without weakening the public RPC contracts.

create or replace function public.admin_list_sms_metadata(
  p_search text default null,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  search_term text := nullif(btrim(p_search), '');
begin
  perform public.assert_admin_permission('sms.metadata.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(
      public._admin_row(
        sms.id,
        coalesce(public.mask_phone(sms.raw_sender), 'SMS'),
        sms.body_hash,
        sms.parse_status,
        '',
        sms.ingested_at
      )
      order by sms.ingested_at desc
    )
    from public.raw_payment_sms sms
    where (p_status is null or sms.parse_status = p_status)
      and (
        search_term is null
        or coalesce(public.mask_phone(sms.raw_sender), 'SMS')
          ilike '%' || search_term || '%'
        or sms.body_hash ilike '%' || search_term || '%'
        or sms.parse_status::text ilike '%' || search_term || '%'
      )
  ), '[]'::jsonb));
end;
$$;

revoke all on function public.admin_list_sms_metadata(text, text)
  from public, anon;
grant execute on function public.admin_list_sms_metadata(text, text)
  to authenticated, service_role;

-- Retain the legacy RPC signature for older installed clients, but delegate to
-- the current membership-gated, idempotent contribution-intent implementation.
-- This also ensures the supplied sender hash is validated and stored instead
-- of being silently ignored.
create or replace function public.create_payment_intent(
  collection uuid,
  expected_amount_rwf bigint default null,
  sender_phone_hash text default null
)
returns public.payment_intents
language plpgsql
security definer
set search_path = public
as $$
declare
  created_intent_id uuid;
  intent_row public.payment_intents;
begin
  select created.id
    into created_intent_id
  from public.create_contribution_intent(
    collection,
    expected_amount_rwf,
    sender_phone_hash
  ) created
  limit 1;

  select intent.*
    into strict intent_row
  from public.payment_intents intent
  where intent.id = created_intent_id
    and intent.contributor_user_id = auth.uid();

  return intent_row;
end;
$$;

revoke all on function public.create_payment_intent(uuid, bigint, text)
  from public, anon;
grant execute on function public.create_payment_intent(uuid, bigint, text)
  to authenticated;

comment on function public.create_payment_intent(uuid, bigint, text) is
  'Compatibility wrapper; new clients use create_contribution_intent.';
