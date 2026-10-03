begin;

-- Additive reviewed-intent receipts. Existing v1 mutation and evidence remain
-- unchanged: v2 delegates their locks, revisions, eligibility and audit write.
create function collect_ops.followup_v2_actor(p_mutation boolean) returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare sid uuid;
begin
 sid:=collect_ops.actor(p_mutation);
 -- A transition-mode WhatsApp owner remains valid for v1, never for v2.
 if collect_admin_access.email_identity(auth.uid()) is distinct from true
  or not exists(select 1 from collect_admin_access.email_approvals a
   where a.user_id=auth.uid() and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>clock_timestamp())) then
  raise exception 'exception_followup_email_owner_required' using errcode='42501';
 end if;
 return sid;
end $$;

create function collect_ops.followup_v2_fingerprint(p_request_id uuid,p_exception_id uuid,
 p_expected_source_revision bigint,p_expected_workflow_revision bigint,p_action text,
 p_assignee_id uuid,p_due_at timestamptz,p_reason_code text,p_expires_at timestamptz)
returns text language plpgsql immutable security definer set search_path='' as $$
begin
 if p_request_id is null or p_exception_id is null or p_expected_source_revision is null
  or p_expected_source_revision not between 1 and 1000000000
  or p_expected_workflow_revision is null or p_expected_workflow_revision not between 0 and 999999999
  or p_action is null or p_action not in('assign','escalate','resolve')
  or p_reason_code is null or p_reason_code not in('review_started','owner_review_required',
   'uncertain_send_review','contact_review','source_rechecked')
  or (p_action='assign' and (p_assignee_id is null or p_due_at is null))
  or (p_action<>'assign' and (p_assignee_id is not null or p_due_at is not null))
  or (p_action='resolve' and p_reason_code<>'source_rechecked')
  or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at<'0001-01-01T00:00:00Z'::timestamptz
  or p_expires_at>='10000-01-01T00:00:00Z'::timestamptz
  or (p_due_at is not null and (not isfinite(p_due_at)
   or p_due_at<'0001-01-01T00:00:00Z'::timestamptz
   or p_due_at>='10000-01-01T00:00:00Z'::timestamptz)) then
  raise exception 'exception_followup_input_invalid' using errcode='22023';
 end if;
 -- Closed enums, canonical UUID/decimal/UTC6 fields, exactly one LF between
 -- fields, and no final LF make this grammar unambiguous across clients.
 return encode(extensions.digest(convert_to(concat_ws(E'\n',
  'collect-exception-workflow-v2',p_request_id::text,p_exception_id::text,
  p_expected_source_revision::text,p_expected_workflow_revision::text,p_action,
  coalesce(p_assignee_id::text,'-'),coalesce(collect_ops.utc(p_due_at),'-'),
  p_reason_code,collect_ops.utc(p_expires_at)),'UTF8'),'sha256'),'hex');
end $$;

create function public.admin_list_exception_followup_operators_v2(p_limit integer default 25,
 p_before_created_at timestamptz default null,p_before_operator_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' set lock_timeout='100ms' as $$
declare at timestamptz;rows jsonb;cursor_value jsonb;
begin
 perform collect_ops.followup_v2_actor(false);
 if p_limit is null or p_limit not between 1 and 25
  or (p_before_created_at is null)<>(p_before_operator_id is null)
  or (p_before_created_at is not null and (not isfinite(p_before_created_at)
   or p_before_created_at<'0001-01-01T00:00:00Z'::timestamptz
   or p_before_created_at>='10000-01-01T00:00:00Z'::timestamptz)) then
  raise exception 'exception_followup_directory_input_invalid' using errcode='22023';
 end if;
 at:=clock_timestamp();
 with candidates as materialized (
  select p.id,p.public_id,p.created_at from public.profiles p
  where isfinite(p.created_at) and p.created_at>='0001-01-01T00:00:00Z'::timestamptz
   and p.created_at<=at and collect_ops.recipient_available(p.id)
   and exists(select 1 from collect_admin_access.email_approvals a where a.user_id=p.id
    and a.revoked_at is null and (a.expires_at is null or a.expires_at>at))
   and (p_before_created_at is null or (p.created_at,p.id)<(p_before_created_at,p_before_operator_id))
  order by p.created_at desc,p.id desc limit p_limit+1
 ), numbered as (select *,row_number()over(order by created_at desc,id desc) n from candidates)
 select coalesce(jsonb_agg(jsonb_build_object('operator_id',id,
   'display_label','Collect ID '||public_id,'created_at',collect_ops.utc(created_at))
   order by created_at desc,id desc)filter(where n<=p_limit),'[]'::jsonb),
  case when max(n)>p_limit then (select jsonb_build_object('created_at',collect_ops.utc(x.created_at),
   'operator_id',x.id) from numbered x where x.n=p_limit) else null end
 into rows,cursor_value from numbered;
 perform collect_ops.followup_v2_actor(false);
 return jsonb_build_object('contract_version',2,'scope','platform_global','checked_at',collect_ops.utc(at),
  'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),'limit',p_limit,
  'rows',rows,'next_cursor',cursor_value);
exception when lock_not_available then
 raise exception 'exception_followup_authority_busy' using errcode='55P03';
end $$;

create function public.admin_act_exception_workflow_v2(p_request_id uuid,p_exception_id uuid,
 p_expected_source_revision bigint,p_expected_workflow_revision bigint,p_action text,
 p_assignee_id uuid,p_due_at timestamptz,p_reason_code text,p_expires_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare fingerprint text;receipt jsonb;
begin
 perform collect_ops.followup_v2_actor(true);
 fingerprint:=collect_ops.followup_v2_fingerprint(p_request_id,p_exception_id,
  p_expected_source_revision,p_expected_workflow_revision,p_action,p_assignee_id,p_due_at,p_reason_code,p_expires_at);
 receipt:=public.admin_act_exception_workflow_v1(p_request_id,p_exception_id,
  p_expected_source_revision,p_expected_workflow_revision,p_action,p_assignee_id,p_due_at,p_reason_code,p_expires_at);
 perform collect_ops.followup_v2_actor(true);
 return receipt||jsonb_build_object('contract_version',2,'request_fingerprint',fingerprint);
end $$;

create function public.admin_get_exception_workflow_request_v2(p_request_id uuid,
 p_request_fingerprint text,p_expires_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path='' set lock_timeout='100ms' as $$
declare prior collect_ops.exception_workflow_requests;acquired boolean;at timestamptz;
 fingerprint text;receipt jsonb;
begin
 perform collect_ops.followup_v2_actor(false);
 if p_request_id is null or p_request_fingerprint is null or p_request_fingerprint!~'^[0-9a-f]{64}$'
  or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at<'0001-01-01T00:00:00Z'::timestamptz
  or p_expires_at>='10000-01-01T00:00:00Z'::timestamptz then
  raise exception 'exception_followup_lookup_input_invalid' using errcode='22023';
 end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-ops-workflow-request:'||p_request_id::text,0));
 select * into prior from collect_ops.exception_workflow_requests
  where acquired and request_id=p_request_id and actor_id=auth.uid();
 if prior.request_id is not null then
  fingerprint:=collect_ops.followup_v2_fingerprint(prior.request_id,prior.exception_id,
   prior.expected_source_revision,prior.expected_workflow_revision,prior.action,
   prior.assignee_id,prior.due_at,prior.reason_code,prior.expires_at);
  if fingerprint is distinct from p_request_fingerprint or prior.expires_at is distinct from p_expires_at then
   raise exception 'exception_followup_request_conflict' using errcode='22023';
  end if;
  receipt:=prior.result||jsonb_build_object('contract_version',2,'request_fingerprint',fingerprint);
 end if;
 perform collect_ops.followup_v2_actor(false);
 at:=clock_timestamp();
 return jsonb_build_object('contract_version',2,'request_id',p_request_id,
  'request_fingerprint',p_request_fingerprint,'expires_at',collect_ops.utc(p_expires_at),
  'checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),
  'status',case when not acquired then 'in_progress' when prior.request_id is null then 'not_recorded' else 'recorded' end,
  'receipt',receipt);
exception when lock_not_available then
 raise exception 'exception_followup_authority_busy' using errcode='55P03';
end $$;

revoke all on function collect_ops.followup_v2_actor(boolean),
 collect_ops.followup_v2_fingerprint(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text,timestamptz)
 from public,anon,authenticated,service_role;
revoke all on function public.admin_list_exception_followup_operators_v2(integer,timestamptz,uuid),
 public.admin_act_exception_workflow_v2(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text,timestamptz),
 public.admin_get_exception_workflow_request_v2(uuid,text,timestamptz)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_list_exception_followup_operators_v2(integer,timestamptz,uuid),
 public.admin_act_exception_workflow_v2(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text,timestamptz),
 public.admin_get_exception_workflow_request_v2(uuid,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
