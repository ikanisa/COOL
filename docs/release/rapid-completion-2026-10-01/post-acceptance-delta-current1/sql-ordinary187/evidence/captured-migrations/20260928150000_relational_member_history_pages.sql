begin;

-- The member client is Rwanda MoMo only after 20260925190000. A posted row
-- without a posting instant cannot be ordered or decoded as history. Adding
-- the constraint before validation closes the concurrent-write gap; validation
-- stops the upgrade for reconciliation rather than dropping such a row.
alter table public.payments
  add constraint payments_posted_rwf_has_posted_at
  check (status <> 'posted' or currency <> 'RWF' or posted_at is not null)
  not valid;
alter table public.payments validate constraint payments_posted_rwf_has_posted_at;

-- The two scoped paths (own payments and readable collections) need the same
-- deterministic tie breaker for all four client sorts. These partial indexes
-- omit unposted and retired-currency records from member history reads.
create index payments_history_collection_newest_idx
  on public.payments (collection_id, posted_at desc, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_collection_oldest_idx
  on public.payments (collection_id, posted_at, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_collection_highest_idx
  on public.payments (collection_id, amount_rwf desc, posted_at desc, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_collection_lowest_idx
  on public.payments (collection_id, amount_rwf, posted_at desc, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_own_newest_idx
  on public.payments (contributor_user_id, posted_at desc, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_own_oldest_idx
  on public.payments (contributor_user_id, posted_at, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_own_highest_idx
  on public.payments (contributor_user_id, amount_rwf desc, posted_at desc, id)
  where status = 'posted' and currency = 'RWF';
create index payments_history_own_lowest_idx
  on public.payments (contributor_user_id, amount_rwf, posted_at desc, id)
  where status = 'posted' and currency = 'RWF';

create index payment_intents_member_recent_idx
  on public.payment_intents (contributor_user_id, created_at desc, id);
create index payment_intents_member_pending_idx
  on public.payment_intents (contributor_user_id, expires_at)
  where status = 'pending';
create index collection_receivers_history_lookup_idx
  on public.collection_receivers
  (collection_id, momo_number_hash, created_at desc, id);

-- Keep the existing public wrapper, JSON response, and {revision,after}
-- cursor. Only a bounded keyset window is converted to JSON. Complete totals
-- and a row-content revision still scan all matching relational rows;
-- they never materialize or rank the legacy payment_history() JSON array.
create or replace function collect_member_actions.history_page(
  p_collection_id uuid, p_query text, p_sort text, p_cursor jsonb, p_limit integer
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
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
  select count(*)::bigint,
    coalesce(sum(amount_rwf), 0)::bigint,
    coalesce(sum(amount_rwf) filter (where own), 0)::bigint,
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
$$;
revoke all on function collect_member_actions.history_page(uuid,text,text,jsonb,integer)
  from public, anon, authenticated;
grant execute on function collect_member_actions.history_page(uuid,text,text,jsonb,integer)
  to authenticated;

-- Select the newest 50 rows, or one actor-owned historical ID, before joining
-- receiver details and aggregating JSON. pending_count remains an exact count
-- over active pending requests; the dedicated partial index supports it.
create or replace function collect_member_actions.recent_intents(p_intent_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  items jsonb;
  pending_count bigint;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select count(*)::bigint into pending_count
  from public.payment_intents intent
  where intent.contributor_user_id = actor
    and intent.status = 'pending' and intent.expires_at > now();

  if p_intent_id is null then
    with selected as materialized (
      select intent.id, intent.collection_id, intent.expected_amount_rwf,
        intent.receiver_momo_number_hash, intent.status, intent.created_at,
        intent.expires_at
      from public.payment_intents intent
      where intent.contributor_user_id = actor
      order by intent.created_at desc, intent.id
      limit 50
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', intent.id,
      'collection_id', intent.collection_id,
      'rail', 'rwanda_momo',
      'amount_minor', intent.expected_amount_rwf,
      'currency', 'RWF',
      'receiver_momo_number', receiver.momo_number,
      'receiver_label', receiver.label,
      'network', receiver.network,
      'status', case when intent.status = 'pending' and intent.expires_at <= now()
        then 'expired' else intent.status::text end,
      'created_at', intent.created_at,
      'expires_at', intent.expires_at
    ) order by intent.created_at desc, intent.id), '[]'::jsonb)
    into items
    from selected intent
    left join lateral (
      select route.momo_number, route.label, route.network
      from public.collection_receivers route
      where route.collection_id = intent.collection_id
        and route.momo_number_hash = intent.receiver_momo_number_hash
      order by route.created_at desc, route.id limit 1
    ) receiver on true;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', intent.id,
      'collection_id', intent.collection_id,
      'rail', 'rwanda_momo',
      'amount_minor', intent.expected_amount_rwf,
      'currency', 'RWF',
      'receiver_momo_number', receiver.momo_number,
      'receiver_label', receiver.label,
      'network', receiver.network,
      'status', case when intent.status = 'pending' and intent.expires_at <= now()
        then 'expired' else intent.status::text end,
      'created_at', intent.created_at,
      'expires_at', intent.expires_at
    )), '[]'::jsonb)
    into items
    from public.payment_intents intent
    left join lateral (
      select route.momo_number, route.label, route.network
      from public.collection_receivers route
      where route.collection_id = intent.collection_id
        and route.momo_number_hash = intent.receiver_momo_number_hash
      order by route.created_at desc, route.id limit 1
    ) receiver on true
    where intent.id = p_intent_id and intent.contributor_user_id = actor;
  end if;

  return jsonb_build_object('items', items, 'pending_count', pending_count);
end;
$$;
revoke all on function collect_member_actions.recent_intents(uuid)
  from public, anon, authenticated;
grant execute on function collect_member_actions.recent_intents(uuid)
  to authenticated;

commit;
