begin;
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
    keyset_predicate := '($4::uuid is null or payment.posted_at <= $5) and '
      || '($4::uuid is null or payment.posted_at < $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))';
    source_order := 'payment.posted_at desc, payment.id';
    window_order := 'posted_at desc, id';
  elsif p_sort = 'oldest' then
    keyset_predicate := '($4::uuid is null or payment.posted_at >= $5) and '
      || '($4::uuid is null or payment.posted_at > $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))';
    source_order := 'payment.posted_at, payment.id';
    window_order := 'posted_at, id';
  elsif p_sort = 'highest' then
    keyset_predicate := '($4::uuid is null or payment.amount_rwf <= $6) and '
      || '($4::uuid is null or payment.amount_rwf < $6 or '
      || '(payment.amount_rwf = $6 and (payment.posted_at < $5 or '
      || '(payment.posted_at = $5 and payment.id > $4))))';
    source_order := 'payment.amount_rwf desc, payment.posted_at desc, payment.id';
    window_order := 'amount_rwf desc, posted_at desc, id';
  else
    keyset_predicate := '($4::uuid is null or payment.amount_rwf >= $6) and '
      || '($4::uuid is null or payment.amount_rwf > $6 or '
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
            and exists (select 1 from public.collections collection
              where collection.id = payment.collection_id
                and strpos(lower(collection.title), $3) > 0)))
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
commit;
