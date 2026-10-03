begin;

-- Source bodies: docs/release/data-correctness-2026-09-30/sql154-positive-history-precision-review/actual-minimum-functions.json
-- Source SHA-256: 6ec82c3fd45bc71217eab3f1ea7d2cc3da0c1994ea7881d30d5673da6cb7fa9b
-- Preserve numeric JSON wire shapes, authority/finality/replay semantics and
-- all stored values. Existing unsafe posted rows abort this migration; REVIEW
-- observations remain available for an explicit rejection/correction workflow.
create function collect_member_actions.exact_json_amount(p_amount numeric)
returns bigint language plpgsql immutable security invoker set search_path='' as $$
begin
 if p_amount is null or p_amount<0 or p_amount>9007199254740991
   or p_amount<>trunc(p_amount) then
  raise exception 'financial_amount_not_exact' using errcode='22023';
 end if;
 return p_amount::bigint;
end$$;
revoke all on function collect_member_actions.exact_json_amount(numeric)
 from public,anon,authenticated,service_role;

alter table public.payments add constraint payments_posted_amount_exact_json
 check(status<>'posted' or amount_rwf<=9007199254740991) not valid;
alter table public.payments validate constraint payments_posted_amount_exact_json;

CREATE OR REPLACE FUNCTION public.propose_payment_reconciliation_v2(p_payment_id uuid, p_evidence_sha256 text, p_source_reference text, p_occurred_at timestamp with time zone, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare session_id uuid; payment_row public.payments; prior collect_security.reconciliation_reviews;
 result_id uuid; evidence text:=lower(btrim(coalesce(p_evidence_sha256,'')));
 reference_text text:=upper(btrim(coalesce(p_source_reference,''))); reason_text text:=btrim(coalesce(p_reason,''));
 fingerprint text;
begin
 session_id:=collect_security.require_reconciliation_actor();
 if p_payment_id is null or evidence !~ '^[a-f0-9]{64}$'
   or length(reference_text) not between 3 and 128 or length(reason_text) not between 10 and 500
   or p_occurred_at is null or not isfinite(p_occurred_at) or p_occurred_at>clock_timestamp()+interval '5 minutes' then
  raise exception 'reconciliation_invalid_evidence' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:'||p_payment_id::text,0));
 select * into payment_row from public.payments where id=p_payment_id for update;
 if payment_row.id is null or payment_row.status<>'review' or payment_row.currency<>'RWF'
   or payment_row.provider_network not in ('mtn_momo','airtel_money')
   or payment_row.amount_rwf<=0 or payment_row.transaction_id is null
   or length(btrim(payment_row.transaction_id)) not between 3 and 128
   or payment_row.receiver_momo_number_hash is null or payment_row.receiver_momo_number_hash !~ '^[a-f0-9]{64}$' then
  raise exception 'reconciliation_payment_not_reviewable' using errcode='22023'; end if;
 perform collect_member_actions.exact_json_amount(payment_row.amount_rwf);
 fingerprint:=collect_security.reconciliation_fingerprint(payment_row);
 select * into prior from collect_security.reconciliation_reviews where payment_id=p_payment_id
   and proposed_by=auth.uid() and proposed_session_id=session_id and payment_fingerprint=fingerprint
   and evidence_sha256=evidence and source_reference=reference_text and occurred_at=p_occurred_at
   and proposal_reason=reason_text and consumed_at is null
   and proposed_at>=clock_timestamp()-interval '24 hours'
   and (approved_at is null or approved_at>=clock_timestamp()-interval '15 minutes')
   order by proposed_at desc,id limit 1;
 if prior.id is not null and (prior.approved_by is null
   or collect_security.reconciliation_actor_current(prior.approved_by,prior.approved_session_id)) then return prior.id; end if;
 insert into collect_security.reconciliation_reviews(payment_id,payment_fingerprint,evidence_sha256,
   source_reference,occurred_at,proposal_reason,proposed_by,proposed_session_id)
 values(p_payment_id,fingerprint,evidence,reference_text,p_occurred_at,reason_text,auth.uid(),session_id)
 returning id into result_id;
 perform public.create_audit_log('reconciliation.proposed','payment',p_payment_id,
  jsonb_build_object('review_id',result_id,'evidence_sha256',evidence,'source_reference',reference_text,
    'reason',reason_text,'session_id',session_id),auth.uid());
 return result_id;
end $function$;

CREATE OR REPLACE FUNCTION public.confirm_provider_payment(p_payment_id uuid, p_provider_network text, p_transaction_id text, p_provider_confirmation_id text, p_receiver_momo_number_hash text, p_amount_rwf bigint, p_confirmed_at timestamp with time zone, p_evidence_sha256 text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  payment_row public.payments;
  clean_network text := lower(btrim(coalesce(p_provider_network, '')));
  clean_transaction_id text := upper(btrim(coalesce(p_transaction_id, '')));
  clean_confirmation_id text := upper(btrim(coalesce(p_provider_confirmation_id, '')));
  clean_receiver_hash text := lower(btrim(coalesce(p_receiver_momo_number_hash, '')));
  clean_evidence_hash text := lower(btrim(coalesce(p_evidence_sha256, '')));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_payment_id is null
     or char_length(clean_network) not between 2 and 32
     or char_length(clean_transaction_id) not between 3 and 128
     or char_length(clean_confirmation_id) not between 3 and 128
     or clean_receiver_hash !~ '^[0-9a-f]{64}$'
     or p_amount_rwf is null or p_amount_rwf <= 0
     or p_confirmed_at is null or not isfinite(p_confirmed_at) or p_confirmed_at > now() + interval '5 minutes'
     or (clean_evidence_hash <> '' and clean_evidence_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid provider confirmation';
  end if;

  perform collect_member_actions.exact_json_amount(p_amount_rwf);

  perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));

  select payment.* into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if payment_row.status = 'posted' then
    if exists (
      select 1 from public.payment_provider_confirmations confirmation
      where confirmation.payment_id = payment_row.id
        and confirmation.provider_network = clean_network
        and upper(btrim(confirmation.provider_confirmation_id)) = clean_confirmation_id
        and upper(btrim(confirmation.transaction_id)) = clean_transaction_id
        and confirmation.receiver_momo_number_hash = clean_receiver_hash
        and confirmation.amount_rwf = p_amount_rwf
        and confirmation.confirmed_at = p_confirmed_at
        and confirmation.evidence_sha256 is not distinct from nullif(clean_evidence_hash, '')
    ) then return payment_row.id; end if;
    raise exception 'Payment was already finalized by a different confirmation';
  end if;
  if payment_row.status <> 'review' then
    raise exception 'Payment is not awaiting provider confirmation';
  end if;
  if lower(btrim(payment_row.provider_network)) is distinct from clean_network
     or upper(btrim(payment_row.transaction_id)) is distinct from clean_transaction_id
     or payment_row.receiver_momo_number_hash is distinct from clean_receiver_hash
     or payment_row.amount_rwf is distinct from p_amount_rwf then
    raise exception 'Provider confirmation does not match the payment candidate';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(clean_network || ':' || clean_transaction_id, 0));
  insert into public.payment_provider_confirmations(
    payment_id, provider_network, provider_confirmation_id, transaction_id,
    receiver_momo_number_hash, amount_rwf, confirmed_at, evidence_sha256
  ) values (
    payment_row.id, clean_network, clean_confirmation_id, clean_transaction_id,
    clean_receiver_hash, p_amount_rwf, p_confirmed_at, nullif(clean_evidence_hash, '')
  );
  insert into public.ledger_entries(
    payment_id, collection_id, user_id, member_record_id,
    entry_type, amount_rwf, visibility, metadata
  ) values
    (
      payment_row.id, payment_row.collection_id, payment_row.contributor_user_id,
      payment_row.member_record_id, 'collection_credit', payment_row.amount_rwf,
      'public_safe', jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    ),
    (
      payment_row.id, payment_row.collection_id, payment_row.contributor_user_id,
      payment_row.member_record_id, 'member_credit', payment_row.amount_rwf,
      'private', jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    );
  update public.payments
  set status = 'posted', posted_at = p_confirmed_at
  where id = payment_row.id;
  update public.parsed_payment_events
  set allocation_status = 'allocated',
      review_reason = 'Posted after independent provider confirmation'
  where id = payment_row.parsed_event_id;
  perform public.create_audit_log(
    'payment.provider_confirmed', 'payment', payment_row.id,
    jsonb_build_object(
      'provider_network', clean_network,
      'provider_confirmation_id', clean_confirmation_id,
      'confirmed_at', p_confirmed_at,
      'ledger_posted', true
    ),
    null
  );
  return payment_row.id;
end;
$function$;

CREATE OR REPLACE FUNCTION collect_member_actions.history_page(p_collection_id uuid, p_query text, p_sort text, p_cursor jsonb, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  query_text text := lower(btrim(coalesce(p_query, '')));
  anchor_id uuid;
  anchor_at timestamptz;
  anchor_amount bigint;
  total_count bigint;
  total_amount bigint;
  own_amount bigint;
  own_collection_ids jsonb;
  revision text;
  page_items jsonb;
  has_more boolean;
  last_id text;
  keyset_predicate text;
  source_order text;
  window_order text;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or length(query_text) > 80
     or p_sort is null or p_sort not in ('newest', 'oldest', 'highest', 'lowest') then
    raise exception 'Invalid history query' using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
       or coalesce(p_cursor->>'revision', '') !~ '^[a-f0-9]{32}$'
       or coalesce(p_cursor->>'after', '') !~
         '^momo:[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' then
      raise exception 'Invalid history cursor' using errcode = '22023';
    end if;
    anchor_id := substring(p_cursor->>'after' from 6)::uuid;
  end if;

  with readable as materialized (
    select collection.id from public.collections collection
    where public.user_can_read_collection(collection.id, actor)
  ), scoped as (
    select payment.id, payment.collection_id, payment.amount_rwf,
      payment.posted_at,
      coalesce(payment.contributor_user_id = actor, false) as own,
      case when payment.contributor_user_id = actor
        then payment.transaction_id end as transaction_id,
      case when payment.contributor_user_id = actor then 'You'
        when payment.anonymity_choice = 'public_id'
          and payment.contributor_public_id is not null
          then 'Collect ID ' || payment.contributor_public_id
        else 'Anonymous supporter' end as supporter_label,
      collection.title,
      payment.collection_id in (select id from readable) as can_read_collection
    from public.payments payment
    join public.collections collection on collection.id = payment.collection_id
    where payment.status = 'posted' and payment.currency = 'RWF'
      and (p_collection_id is null or payment.collection_id = p_collection_id)
      and (payment.contributor_user_id = actor
        or payment.collection_id in (select id from readable))
  ), matched as (
    select * from scoped
    where query_text = ''
      or strpos(lower(supporter_label), query_text) > 0
      or strpos(lower(coalesce(transaction_id, '')), query_text) > 0
      or (can_read_collection and strpos(lower(title), query_text) > 0)
  )
  select collect_member_actions.exact_json_amount(count(*)),
    collect_member_actions.exact_json_amount(coalesce(sum(amount_rwf), 0)),
    collect_member_actions.exact_json_amount(coalesce(sum(amount_rwf) filter (where own), 0)),
    coalesce(to_jsonb(array_agg(distinct collection_id::text
      order by collection_id::text) filter (where own)), '[]'::jsonb),
    -- A 256-bit XOR of per-row SHA-256 digests has constant aggregate space.
    -- Row identity is included, so a changed/missing row changes the revision
    -- with overwhelming probability; count also distinguishes cardinality.
    md5(row(actor, p_collection_id, query_text, p_sort, count(*),
      coalesce(bit_xor(('x' || encode(extensions.digest(
        row(id, collection_id, amount_rwf, posted_at, own,
          transaction_id, supporter_label)::text, 'sha256'), 'hex'))::bit(256)),
        repeat('0', 256)::bit(256)))::text)
  into total_count, total_amount, own_amount, own_collection_ids, revision
  from matched;

  if p_cursor is not null and revision <> p_cursor->>'revision' then
    raise exception 'History changed. Refresh before loading more.'
      using errcode = 'P0001';
  end if;
  if anchor_id is not null then
    with readable as materialized (
      select collection.id from public.collections collection
      where public.user_can_read_collection(collection.id, actor)
    )
    select payment.posted_at, payment.amount_rwf
    into anchor_at, anchor_amount
    from public.payments payment
    join public.collections collection on collection.id = payment.collection_id
    where payment.id = anchor_id
      and payment.status = 'posted' and payment.currency = 'RWF'
      and (p_collection_id is null or payment.collection_id = p_collection_id)
      and (payment.contributor_user_id = actor
        or payment.collection_id in (select id from readable))
      and (query_text = ''
        or strpos(lower(case when payment.contributor_user_id = actor then 'You'
          when payment.anonymity_choice = 'public_id'
            and payment.contributor_public_id is not null
            then 'Collect ID ' || payment.contributor_public_id
          else 'Anonymous supporter' end), query_text) > 0
        or (payment.contributor_user_id = actor
          and strpos(lower(coalesce(payment.transaction_id, '')), query_text) > 0)
        or (payment.collection_id in (select id from readable)
          and strpos(lower(collection.title), query_text) > 0));
    if not found then
      raise exception 'History changed. Refresh before loading more.'
        using errcode = 'P0001';
    end if;
  end if;

  -- These fragments are selected solely from the four validated enum values.
  -- All user data remains in EXECUTE USING parameters, never in SQL text.
  if p_sort = 'newest' then
    keyset_predicate := '($4::uuid is null or payment.posted_at < $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))';
    source_order := 'payment.posted_at desc, payment.id';
    window_order := 'posted_at desc, id';
  elsif p_sort = 'oldest' then
    keyset_predicate := '($4::uuid is null or payment.posted_at > $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))';
    source_order := 'payment.posted_at, payment.id';
    window_order := 'posted_at, id';
  elsif p_sort = 'highest' then
    keyset_predicate := '($4::uuid is null or payment.amount_rwf < $6 or '
      || '(payment.amount_rwf = $6 and (payment.posted_at < $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))))';
    source_order := 'payment.amount_rwf desc, payment.posted_at desc, payment.id';
    window_order := 'amount_rwf desc, posted_at desc, id';
  else
    keyset_predicate := '($4::uuid is null or payment.amount_rwf > $6 or '
      || '(payment.amount_rwf = $6 and (payment.posted_at < $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))))';
    source_order := 'payment.amount_rwf, payment.posted_at desc, payment.id';
    window_order := 'amount_rwf, posted_at desc, id';
  end if;

  execute format($page$
    with readable as materialized (
      select collection.id from public.collections collection
      where public.user_can_read_collection(collection.id, $1)
    ), candidate as (
      select payment.id, payment.collection_id, payment.amount_rwf,
        payment.posted_at, payment.contributor_user_id, payment.transaction_id,
        payment.anonymity_choice, payment.contributor_public_id
      from public.payments payment
      join public.collections collection on collection.id = payment.collection_id
      where payment.status = 'posted' and payment.currency = 'RWF'
        and ($2::uuid is null or payment.collection_id = $2)
        and (payment.contributor_user_id = $1
          or payment.collection_id in (select id from readable))
        and ($3 = ''
          or strpos(lower(case when payment.contributor_user_id = $1 then 'You'
            when payment.anonymity_choice = 'public_id'
              and payment.contributor_public_id is not null
              then 'Collect ID ' || payment.contributor_public_id
            else 'Anonymous supporter' end), $3) > 0
          or (payment.contributor_user_id = $1
            and strpos(lower(coalesce(payment.transaction_id, '')), $3) > 0)
          or (payment.collection_id in (select id from readable)
            and strpos(lower(collection.title), $3) > 0))
        and %s
      order by %s
      limit $7 + 1
    ), numbered as (
      select candidate.*, row_number() over (order by %s) as position
      from candidate
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'payment_id', 'momo:' || id,
      'collection_id', collection_id,
      'amount_minor', amount_rwf,
      'currency', 'RWF',
      'rail', 'rwanda_momo',
      'posted_at', posted_at,
      'transaction_id', case when contributor_user_id = $1 then transaction_id end,
      'is_current_user_contribution', coalesce(contributor_user_id = $1, false),
      'supporter_label', case when contributor_user_id = $1 then 'You'
        when anonymity_choice = 'public_id' and contributor_public_id is not null
          then 'Collect ID ' || contributor_public_id
        else 'Anonymous supporter' end
    ) order by position) filter (where position <= $7), '[]'::jsonb),
    count(*) > $7,
    max(case when position = $7 then 'momo:' || id end)
    from numbered
  $page$, keyset_predicate, source_order, window_order)
  into page_items, has_more, last_id
  using actor, p_collection_id, query_text, anchor_id, anchor_at,
    anchor_amount, p_limit;

  return jsonb_build_object(
    'items', page_items,
    'total_count', total_count,
    'totals', case when total_count = 0 then '{}'::jsonb
      else jsonb_build_object('RWF', total_amount) end,
    'own_totals', case when total_count = 0 then '{}'::jsonb
      else jsonb_build_object('RWF', own_amount) end,
    'own_collection_ids', own_collection_ids,
    'revision', revision,
    'next_cursor', case when has_more then
      jsonb_build_object('revision', revision, 'after', last_id) end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_current_member_collection_balances()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with visible as (
    select collection.id from public.collections collection
    where public.user_can_read_collection(collection.id, auth.uid())
      and collection.currency = 'RWF' and not collection.diaspora_enabled
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'collection_id', visible.id,
    'balances', jsonb_build_array(jsonb_build_object(
      'currency', 'RWF',
      'amount_raised_minor', collect_member_actions.exact_json_amount(coalesce(balance.confirmed_rwf, 0)),
      'current_user_balance_minor', collect_member_actions.exact_json_amount(coalesce((
        select sum(member_balance.confirmed_rwf)
        from collect_hybrid.member_balances member_balance
        where member_balance.collection_id = visible.id
          and collect_hybrid.member_record_belongs_to_user(
            member_balance.member_record_id, auth.uid()
          )
      ), 0))
    )),
    'supporter_count', (
      select case when count(*) filter (where payment.contributor_user_id is null) > 0
        then null else count(distinct payment.contributor_user_id) end
      from public.payments payment
      where payment.collection_id = visible.id and payment.status = 'posted'
        and payment.currency = 'RWF'
    )
  ) order by visible.id), '[]'::jsonb)
  into result
  from visible
  left join collect_hybrid.collection_balances balance on balance.collection_id = visible.id;
  return result;
end;
$function$;

notify pgrst,'reload schema';
commit;
