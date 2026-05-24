alter table raw_payment_sms
  add column if not exists collection_id uuid references collections(id) on delete set null;

alter table parsed_payment_events
  add column if not exists collection_id uuid references collections(id) on delete set null;

create index if not exists raw_sms_collection_idx
  on raw_payment_sms (collection_id, ingested_at desc);

create index if not exists parsed_events_collection_review_idx
  on parsed_payment_events (collection_id, allocation_status, created_at desc);

create or replace view member_collection_summary_view
as
select
  c.id as collection_id,
  c.title,
  c.category,
  c.visibility,
  c.public_status,
  c.creator_user_id,
  (
    select coalesce(sum(le.amount_rwf) filter (where le.entry_type = 'collection_credit'), 0)::bigint
    from ledger_entries le
    where le.collection_id = c.id
  ) as amount_raised_rwf,
  (
    select count(distinct coalesce(p.contributor_user_id::text, p.transaction_id, p.id::text))::bigint
    from payments p
    where p.collection_id = c.id
  ) as supporter_count,
  (
    select count(pi.id)::bigint
    from payment_intents pi
    where pi.collection_id = c.id
      and pi.status = 'pending'
  ) as pending_intent_count,
  (
    select count(distinct ppe.id)::bigint
    from collection_receivers cr
    join parsed_payment_events ppe
      on ppe.receiver_user_id = cr.receiver_user_id
     and (
       ppe.collection_id = c.id
       or (
         ppe.collection_id is null
         and ppe.receiver_phone_hash = cr.momo_number_hash
       )
     )
    where cr.collection_id = c.id
      and ppe.allocation_status in ('needs_review', 'ambiguous')
  ) as review_event_count
from collections c
where public.user_can_read_collection(c.id, auth.uid());

create or replace view parsed_payment_events_review_view
as
select distinct on (ppe.id, coalesce(ppe.collection_id, cr.collection_id))
  ppe.id,
  coalesce(ppe.collection_id, cr.collection_id) as collection_id,
  ppe.raw_sms_id,
  ppe.receiver_user_id,
  ppe.is_mobile_money_payment,
  ppe.network,
  ppe.direction,
  ppe.amount_rwf,
  ppe.currency,
  ppe.transaction_id,
  ppe.sender_name,
  ppe.transaction_time,
  ppe.detected_collection_code,
  ppe.detected_user_public_id,
  ppe.confidence,
  ppe.parser_model,
  ppe.parser_schema_version,
  ppe.allocation_status,
  ppe.review_reason,
  ppe.created_at
from parsed_payment_events ppe
left join collection_receivers cr
  on cr.receiver_user_id = ppe.receiver_user_id
 and cr.is_active
 and ppe.collection_id is null
 and ppe.receiver_phone_hash = cr.momo_number_hash
where (
  ppe.collection_id is not null
  and public.user_can_read_collection(ppe.collection_id, auth.uid())
)
or (
  ppe.collection_id is null
  and cr.collection_id is not null
  and public.user_can_read_collection(cr.collection_id, auth.uid())
);

grant select on member_collection_summary_view, parsed_payment_events_review_view to authenticated;
