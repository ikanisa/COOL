\set ON_ERROR_STOP on
begin;
set local statement_timeout='60s';
do $$ begin
 if current_setting('collect.otp_qa_fixture',true) is distinct from 'collect_fin_concurrency_qa_20260929'
   or (select max(version) from supabase_migrations.schema_migrations)<>'20260930130000' then
   raise exception 'Exact task-owned migration145 fixture required';end if;
end $$;
-- Drops are inside this rollback-only transaction and scoped to OTP objects.
-- Source restoration includes private rows, definitions, owners, grants and triggers.
drop function public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text),
 public.reserve_signed_otp_v3(text,text,text),public.begin_signed_otp_v3(text,text,uuid,bigint),
 public.read_signed_otp_v3(text,text,uuid),public.record_signed_otp_v3(text,text,uuid,bigint,text,text,text),
 public.recover_signed_otp_v3(text,text,uuid,bigint,text,text);
drop table collect_security.signed_otp_evidence;
drop table collect_security.signed_otp_requests cascade;
drop table collect_security.otp_policy;
create temp table otp_upgrade_checks(label text primary key);
grant select,insert on otp_upgrade_checks to service_role;
create function pg_temp.otp_upgrade_check(ok boolean,label text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',label;end if;
 insert into pg_temp.otp_upgrade_checks values(label);end $$;

-- Staged: quota policy must be explicitly configured by a privileged operator.

create schema if not exists collect_security;
revoke all on schema collect_security from public,anon,authenticated;
create table collect_security.otp_policy (
 singleton boolean primary key default true check(singleton),
 global_hourly_limit integer not null check(global_hourly_limit between 1 and 100000),
 global_daily_limit integer not null check(global_daily_limit between 1 and 1000000),
 enabled boolean not null default false
);
create table collect_security.signed_otp_requests (
 hook_id text primary key check(length(hook_id) between 1 and 256),
 payload_hash text not null check(payload_hash ~ '^[a-f0-9]{64}$'),
 phone_hash text not null check(phone_hash ~ '^[a-f0-9]{64}$'),
 requested_at timestamptz not null default now(),delivered_at timestamptz,
 status text not null default 'reserved' check(status in ('reserved','sent'))
);
create index signed_otp_requests_window on collect_security.signed_otp_requests(requested_at);
alter table collect_security.otp_policy enable row level security;
alter table collect_security.signed_otp_requests enable row level security;
revoke all on collect_security.otp_policy,collect_security.signed_otp_requests from public,anon,authenticated,service_role;
create function public.reserve_signed_otp_v2(p_hook_id text,p_payload_hash text,p_phone_hash text)
returns text language plpgsql security definer set search_path='' as $$
declare policy collect_security.otp_policy;prior collect_security.signed_otp_requests;t timestamptz;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 if p_hook_id is null or length(p_hook_id) not between 1 and 256 or p_payload_hash is null or p_payload_hash !~ '^[a-f0-9]{64}$'
   or p_phone_hash is null or p_phone_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid reservation'; end if;
 -- The row update serializes decisions and makes stale repeatable-read snapshots
 -- fail rather than admitting extra deliveries under a phantom count.
 update collect_security.otp_policy set enabled=enabled where singleton returning * into policy;
 if policy.singleton is null or not policy.enabled then raise exception 'OTP policy not configured'; end if;
 t:=clock_timestamp();
 select * into prior from collect_security.signed_otp_requests where hook_id=p_hook_id;
 if prior.hook_id is not null then
   if prior.payload_hash<>p_payload_hash or prior.phone_hash<>p_phone_hash then raise exception 'Hook identity conflict'; end if;
   return case when prior.status='sent' then 'already_sent' else 'unresolved' end;
 end if;
 if (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '1 hour')>=policy.global_hourly_limit
  or (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '24 hours')>=policy.global_daily_limit then return 'throttled'; end if;
 if not public.reserve_otp_request(p_phone_hash,null) then return 'throttled'; end if;
 insert into collect_security.signed_otp_requests(hook_id,payload_hash,phone_hash,requested_at) values(p_hook_id,p_payload_hash,p_phone_hash,t);
 return 'reserved';
end; $$;
create function public.complete_signed_otp_v2(p_hook_id text,p_payload_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 update collect_security.signed_otp_requests set status='sent',delivered_at=coalesce(delivered_at,now()) where hook_id=p_hook_id and payload_hash=p_payload_hash;
 return found;
end; $$;
revoke all on function public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) from public,anon,authenticated;
grant execute on function public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) to service_role;


insert into collect_security.otp_policy values(true,1000,10000,true);
insert into collect_security.signed_otp_requests(hook_id,payload_hash,phone_hash,requested_at,delivered_at,status) values
 ('qa_otp_upgrade_sent',repeat('a',64),repeat('8',64),clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute','sent'),
 ('qa_otp_upgrade_unknown',repeat('a',64),repeat('8',64),clock_timestamp()-interval '2 minutes',null,'reserved');
insert into public.otp_rate_limits(phone_hash,requested_at) values
 (repeat('8',64),clock_timestamp()-interval '2 minutes'),(repeat('8',64),clock_timestamp()-interval '2 minutes');


-- Install the signed-hook budget contract in the canonical migration chain.
-- No quota is invented: the owner must configure the private singleton row.
create schema if not exists collect_security;
revoke all on schema collect_security from public, anon, authenticated, service_role;
create table if not exists collect_security.otp_policy (
 singleton boolean primary key default true check (singleton),
 global_hourly_limit integer not null check (global_hourly_limit between 1 and 100000),
 global_daily_limit integer not null check (global_daily_limit between 1 and 1000000),
 enabled boolean not null default false
);
create table if not exists collect_security.signed_otp_requests (
 hook_id text primary key,
 payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
 phone_hash text not null check (phone_hash ~ '^[a-f0-9]{64}$'),
 requested_at timestamptz not null default clock_timestamp(),
 delivered_at timestamptz,
 status text not null default 'reserved'
);
-- PostgreSQL counted regex repetitions stop at255. Keep the documented256
-- ASCII-character contract with an independent length bound. Replace the
-- staged/default constraint as well when upgrading an existing table.
alter table collect_security.signed_otp_requests drop constraint if exists signed_otp_requests_hook_id_check;
alter table collect_security.signed_otp_requests drop constraint if exists signed_otp_hook_v3;
alter table collect_security.signed_otp_requests add constraint signed_otp_hook_v3
 check (char_length(hook_id) between 1 and 256 and hook_id ~ '^[A-Za-z0-9_:.-]+$');
alter table collect_security.signed_otp_requests add column if not exists attempt_id uuid;
alter table collect_security.signed_otp_requests add column if not exists revision bigint not null default 1;
alter table collect_security.signed_otp_requests add column if not exists started_at timestamptz;
alter table collect_security.signed_otp_requests add column if not exists accepted_at timestamptz;
alter table collect_security.signed_otp_requests add column if not exists provider_message_hash text;
alter table collect_security.signed_otp_requests add column if not exists last_evidence_sha256 text;
alter table collect_security.signed_otp_requests add column if not exists contract_version integer not null default 3;

-- A staged-v2 "sent" row proves an HTTP acknowledgement, not delivery.
-- A staged-v2 reservation might already have reached the provider: never retry it.
do $$ declare c record;
begin
 if exists (select 1 from collect_security.signed_otp_requests
   where status not in ('reserved','sent','sending','accepted','delivered','not_sent','failed','ambiguous','expired')) then
   raise exception 'OTP stored state unavailable' using errcode='55000';
 end if;
 for c in select conname from pg_constraint
   where conrelid='collect_security.signed_otp_requests'::regclass and contype='c'
     and pg_get_constraintdef(oid) ~ '\mstatus\M'
 loop execute format('alter table collect_security.signed_otp_requests drop constraint %I',c.conname); end loop;
 update collect_security.signed_otp_requests
 set status=case when status='sent' then 'accepted' else 'ambiguous' end,
     accepted_at=case when status='sent' then delivered_at else null end,
     delivered_at=null, attempt_id=gen_random_uuid(), contract_version=2
 where attempt_id is null;
end $$;
alter table collect_security.signed_otp_requests alter column attempt_id set default gen_random_uuid();
alter table collect_security.signed_otp_requests alter column attempt_id set not null;
alter table collect_security.signed_otp_requests add constraint signed_otp_state_v3
 check (status in ('reserved','sending','accepted','delivered','not_sent','failed','ambiguous','expired'));
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='collect_security.signed_otp_requests'::regclass and conname='signed_otp_revision_v3') then
   alter table collect_security.signed_otp_requests add constraint signed_otp_revision_v3 check (revision between 1 and 1000000);
 end if;
 if not exists(select 1 from pg_constraint where conrelid='collect_security.signed_otp_requests'::regclass and conname='signed_otp_provider_hash_v3') then
   alter table collect_security.signed_otp_requests add constraint signed_otp_provider_hash_v3 check (provider_message_hash is null or provider_message_hash ~ '^[a-f0-9]{64}$');
 end if;
 if not exists(select 1 from pg_constraint where conrelid='collect_security.signed_otp_requests'::regclass and conname='signed_otp_evidence_hash_v3') then
   alter table collect_security.signed_otp_requests add constraint signed_otp_evidence_hash_v3 check (last_evidence_sha256 is null or last_evidence_sha256 ~ '^[a-f0-9]{64}$');
 end if;
end $$;
create index if not exists signed_otp_requests_window on collect_security.signed_otp_requests(requested_at);
create unique index if not exists signed_otp_attempt_v3 on collect_security.signed_otp_requests(attempt_id);
create table if not exists collect_security.signed_otp_evidence (
 id bigint generated always as identity primary key,
 hook_id text not null references collect_security.signed_otp_requests(hook_id),
 attempt_id uuid not null,
 revision bigint not null check (revision between 1 and 1000000),
 evidence_sha256 text not null check (evidence_sha256 ~ '^[a-f0-9]{64}$'),
 evidence_kind text not null check (evidence_kind in ('transport_accepted','transport_ambiguous','expired_unsent',
   'operator_accepted','operator_delivered','operator_not_sent','operator_failed','operator_ambiguous')),
 provider_message_hash text check (provider_message_hash is null or provider_message_hash ~ '^[a-f0-9]{64}$'),
 recorded_at timestamptz not null default clock_timestamp(),
 observed_at timestamptz not null,
 source text not null check (source in ('hook_worker','local_clock','operator_verified_provider_status')),
 unique(hook_id,revision)
);
alter table collect_security.otp_policy enable row level security;
alter table collect_security.signed_otp_requests enable row level security;
alter table collect_security.signed_otp_evidence enable row level security;
revoke all on collect_security.otp_policy,collect_security.signed_otp_requests,collect_security.signed_otp_evidence
 from public,anon,authenticated,service_role;
revoke all on sequence collect_security.signed_otp_evidence_id_seq from public,anon,authenticated,service_role;

create or replace function collect_security.require_otp_service_v3()
returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then
   raise exception 'OTP authorization required' using errcode='42501';
 end if;
end $$;
create or replace function collect_security.otp_receipt_v3(r collect_security.signed_otp_requests)
returns jsonb language plpgsql immutable security definer set search_path='' as $$
begin
 if r.contract_version not in (2,3) or r.revision is null or r.attempt_id is null or
   (r.status='sending' and r.started_at is null) or
   (r.status='accepted' and r.contract_version=3 and (r.accepted_at is null or r.provider_message_hash is null)) or
   (r.status='delivered' and (r.accepted_at is null or r.delivered_at is null or r.provider_message_hash is null)) then
   raise exception 'OTP stored state unavailable' using errcode='55000';
 end if;
 return jsonb_build_object('contract_version',3,'hook_id',r.hook_id,'payload_hash',r.payload_hash,
   'attempt_id',r.attempt_id,'state',r.status,'revision',r.revision,
   'can_send',r.contract_version=3 and r.status='reserved');
end $$;
create or replace function collect_security.otp_expire_v3(p_hook_id text)
returns void language plpgsql security definer set search_path='' as $$
declare r collect_security.signed_otp_requests; kind text; h text; t timestamptz:=clock_timestamp();
begin
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.status='reserved' and r.requested_at<t-interval '5 minutes' then
   kind:='expired_unsent';
 elsif r.status='sending' and r.started_at<t-interval '1 minute' then
   kind:='transport_ambiguous';
 else return; end if;
 h:=encode(extensions.digest(convert_to(kind||':'||r.attempt_id::text||':'||r.revision::text,'UTF8'),'sha256'),'hex');
 update collect_security.signed_otp_requests set status=case when kind='expired_unsent' then 'expired' else 'ambiguous' end,
   revision=revision+1,last_evidence_sha256=h where hook_id=r.hook_id returning * into r;
 insert into collect_security.signed_otp_evidence(hook_id,attempt_id,revision,evidence_sha256,evidence_kind,observed_at,source)
 values(r.hook_id,r.attempt_id,r.revision,h,kind,t,'local_clock');
end $$;

create or replace function public.reserve_signed_otp_v3(p_hook_id text,p_payload_hash text,p_phone_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare p collect_security.otp_policy; r collect_security.signed_otp_requests; t timestamptz;
begin
 perform collect_security.require_otp_service_v3();
 if p_hook_id is null or char_length(p_hook_id) not between 1 and 256
   or p_hook_id !~ '^[A-Za-z0-9_:.-]+$' or p_payload_hash is null
   or p_payload_hash !~ '^[a-f0-9]{64}$' or p_phone_hash is null or p_phone_hash !~ '^[a-f0-9]{64}$' then
   raise exception 'OTP identity unavailable' using errcode='22023';
 end if;
 -- Consistent policy->request->phone order fences simultaneous quota decisions.
 update collect_security.otp_policy set enabled=enabled where singleton returning * into p;
 if p.singleton is null then raise exception 'OTP policy unavailable' using errcode='55000'; end if;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is not null then
   if r.payload_hash<>p_payload_hash or r.phone_hash<>p_phone_hash then
     raise exception 'OTP identity conflict' using errcode='22023';
   end if;
   perform collect_security.otp_expire_v3(r.hook_id);
   select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id;
   return collect_security.otp_receipt_v3(r);
 end if;
 if not p.enabled then raise exception 'OTP policy unavailable' using errcode='55000'; end if;
 t:=clock_timestamp();
 if (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '1 hour')>=p.global_hourly_limit
   or (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '24 hours')>=p.global_daily_limit then
   return to_jsonb('throttled'::text);
 end if;
 if not public.reserve_otp_request(p_phone_hash,null) then return to_jsonb('throttled'::text); end if;
 insert into collect_security.signed_otp_requests(hook_id,payload_hash,phone_hash,requested_at)
 values(p_hook_id,p_payload_hash,p_phone_hash,t) returning * into r;
 return collect_security.otp_receipt_v3(r);
end $$;

create or replace function public.begin_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid,p_revision bigint)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare p collect_security.otp_policy; r collect_security.signed_otp_requests;
begin
 perform collect_security.require_otp_service_v3();
 update collect_security.otp_policy set enabled=enabled where singleton returning * into p;
 if p.singleton is null or not p.enabled then raise exception 'OTP policy unavailable' using errcode='55000'; end if;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id then
   raise exception 'OTP identity conflict' using errcode='22023';
 end if;
 perform collect_security.otp_expire_v3(r.hook_id);
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id;
 if r.contract_version<>3 or r.status<>'reserved' or r.revision is distinct from p_revision then
   return collect_security.otp_receipt_v3(r)||jsonb_build_object('started',false);
 end if;
 update collect_security.signed_otp_requests set status='sending',started_at=clock_timestamp(),revision=revision+1
 where hook_id=r.hook_id returning * into r;
 return collect_security.otp_receipt_v3(r)||jsonb_build_object('started',true);
end $$;

create or replace function public.read_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare r collect_security.signed_otp_requests;
begin
 perform collect_security.require_otp_service_v3();
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id then
   raise exception 'OTP identity conflict' using errcode='22023';
 end if;
 perform collect_security.otp_expire_v3(r.hook_id);
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id;
 return collect_security.otp_receipt_v3(r);
end $$;

create or replace function public.record_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid,p_revision bigint,
 p_outcome text,p_provider_message_hash text,p_evidence_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare r collect_security.signed_otp_requests; e collect_security.signed_otp_evidence;
begin
 perform collect_security.require_otp_service_v3();
 if p_outcome is null or p_outcome not in ('accepted','ambiguous') or p_evidence_sha256 is null
   or p_evidence_sha256 !~ '^[a-f0-9]{64}$' or
   (p_outcome='accepted' and (p_provider_message_hash is null or p_provider_message_hash !~ '^[a-f0-9]{64}$')) or
   (p_outcome='ambiguous' and p_provider_message_hash is not null) then
   raise exception 'OTP evidence unavailable' using errcode='22023';
 end if;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id
   or r.contract_version<>3 then raise exception 'OTP identity conflict' using errcode='22023'; end if;
 select * into e from collect_security.signed_otp_evidence where hook_id=r.hook_id
   and revision>=p_revision+1 and evidence_sha256=p_evidence_sha256 and evidence_kind='transport_'||p_outcome;
 if e.id is not null and e.evidence_sha256=p_evidence_sha256 and e.evidence_kind='transport_'||p_outcome
   and e.provider_message_hash is not distinct from p_provider_message_hash then return collect_security.otp_receipt_v3(r); end if;
 -- Late accepted completion is allowed after lease expiry only while unresolved.
 -- It cannot override a contradictory independent provider recovery.
 if r.status not in ('sending','ambiguous') or r.started_at is null or
   (r.revision<>p_revision and not (r.status='ambiguous' and r.revision=p_revision+1 and
     exists(select 1 from collect_security.signed_otp_evidence where hook_id=r.hook_id
       and revision=r.revision and source='local_clock' and evidence_kind='transport_ambiguous'))) then
   raise exception 'OTP completion conflict' using errcode='40001';
 end if;
 update collect_security.signed_otp_requests set status=p_outcome,revision=revision+1,
   accepted_at=case when p_outcome='accepted' then clock_timestamp() else null end,
   provider_message_hash=p_provider_message_hash,last_evidence_sha256=p_evidence_sha256
 where hook_id=r.hook_id returning * into r;
 insert into collect_security.signed_otp_evidence(hook_id,attempt_id,revision,evidence_sha256,evidence_kind,
   provider_message_hash,observed_at,source)
 values(r.hook_id,r.attempt_id,r.revision,p_evidence_sha256,'transport_'||p_outcome,
   p_provider_message_hash,clock_timestamp(),'hook_worker');
 return collect_security.otp_receipt_v3(r);
end $$;

-- Explicit operator reconciliation. This is not a provider webhook integration:
-- the trusted service caller must independently verify provider evidence first.
-- Hash binding records the evidence; it does not authenticate its truth.
create or replace function public.recover_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid,
 p_revision bigint,p_evidence_text text,p_evidence_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare r collect_security.signed_otp_requests; e jsonb; outcome text; provider_hash text; observed timestamptz;
 h text; prior collect_security.signed_otp_evidence;
begin
 perform collect_security.require_otp_service_v3();
 if p_evidence_text is null or octet_length(p_evidence_text)>4096 or p_evidence_sha256 is null
   or p_evidence_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'OTP evidence unavailable' using errcode='22023'; end if;
 h:=encode(extensions.digest(convert_to(p_evidence_text,'UTF8'),'sha256'),'hex');
 if h<>p_evidence_sha256 then raise exception 'OTP evidence unavailable' using errcode='22023'; end if;
 begin e:=p_evidence_text::jsonb; exception when others then raise exception 'OTP evidence unavailable' using errcode='22023'; end;
 if jsonb_typeof(e)<>'object' or (select count(*) from jsonb_object_keys(e))<>7 or
   not (e ?& array['hook_id','payload_hash','attempt_id','outcome','provider_message_hash','observed_at','source']) or
   jsonb_typeof(e->'hook_id')<>'string' or jsonb_typeof(e->'payload_hash')<>'string' or
   jsonb_typeof(e->'attempt_id')<>'string' or jsonb_typeof(e->'outcome')<>'string' or
   jsonb_typeof(e->'observed_at')<>'string' or jsonb_typeof(e->'source')<>'string' or
   e->>'hook_id' is distinct from p_hook_id or e->>'payload_hash' is distinct from p_payload_hash or
   e->>'attempt_id' is distinct from p_attempt_id::text or e->>'source'<>'operator_verified_provider_status' then
   raise exception 'OTP evidence unavailable' using errcode='22023';
 end if;
 outcome:=e->>'outcome'; provider_hash:=e->>'provider_message_hash';
 if outcome not in ('accepted','delivered','not_sent','failed','ambiguous') or
   (outcome in ('accepted','delivered','failed') and (jsonb_typeof(e->'provider_message_hash')<>'string' or provider_hash is null or provider_hash !~ '^[a-f0-9]{64}$')) or
   (outcome in ('not_sent','ambiguous') and jsonb_typeof(e->'provider_message_hash')<>'null') or
   e->>'observed_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
   raise exception 'OTP evidence unavailable' using errcode='22023';
 end if;
 begin observed:=(e->>'observed_at')::timestamptz; exception when others then raise exception 'OTP evidence unavailable' using errcode='22023'; end;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id then
   raise exception 'OTP identity conflict' using errcode='22023'; end if;
 if observed<r.requested_at-interval '1 minute' or observed>clock_timestamp()+interval '1 minute' then
   raise exception 'OTP evidence unavailable' using errcode='22023'; end if;
 select * into prior from collect_security.signed_otp_evidence where hook_id=r.hook_id
   and evidence_sha256=p_evidence_sha256 and source='operator_verified_provider_status';
 if prior.id is not null then return collect_security.otp_receipt_v3(r); end if;
 if r.revision is distinct from p_revision or r.status in ('delivered','failed','not_sent','expired') or
   (r.status='accepted' and outcome not in ('delivered','failed')) or
   (r.status='reserved' and outcome<>'not_sent') or
   (r.status in ('sending','ambiguous') and outcome='ambiguous' and r.status='ambiguous') or
   (r.provider_message_hash is not null and provider_hash is distinct from r.provider_message_hash) then
   raise exception 'OTP recovery conflict' using errcode='40001';
 end if;
 update collect_security.signed_otp_requests set status=outcome,revision=revision+1,
   accepted_at=case when outcome in ('accepted','delivered') then coalesce(accepted_at,observed) else accepted_at end,
   delivered_at=case when outcome='delivered' then observed else null end,
   provider_message_hash=provider_hash,last_evidence_sha256=p_evidence_sha256
 where hook_id=r.hook_id returning * into r;
 insert into collect_security.signed_otp_evidence(hook_id,attempt_id,revision,evidence_sha256,evidence_kind,
   provider_message_hash,observed_at,source)
 values(r.hook_id,r.attempt_id,r.revision,p_evidence_sha256,'operator_'||outcome,
   provider_hash,observed,'operator_verified_provider_status');
 return collect_security.otp_receipt_v3(r);
end $$;

create or replace function collect_security.guard_otp_evidence_v3()
returns trigger language plpgsql set search_path='' as $$
begin raise exception 'OTP evidence is immutable' using errcode='55000'; end $$;
drop trigger if exists signed_otp_evidence_immutable on collect_security.signed_otp_evidence;
create trigger signed_otp_evidence_immutable before update or delete on collect_security.signed_otp_evidence
 for each row execute function collect_security.guard_otp_evidence_v3();

-- Old callers must not launch new sends or convert an unknown send to success.
create or replace function public.reserve_signed_otp_v2(p_hook_id text,p_payload_hash text,p_phone_hash text)
returns text language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 r:=public.reserve_signed_otp_v3(p_hook_id,p_payload_hash,p_phone_hash);
 if r=to_jsonb('throttled'::text) then return 'throttled'; end if;
 return case when r->>'state' in ('accepted','delivered') then 'already_sent' else 'unresolved' end;
end $$;
create or replace function public.complete_signed_otp_v2(p_hook_id text,p_payload_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
begin perform collect_security.require_otp_service_v3(); return false; end $$;

revoke all on function collect_security.require_otp_service_v3(),
 collect_security.otp_receipt_v3(collect_security.signed_otp_requests),collect_security.otp_expire_v3(text),
 collect_security.guard_otp_evidence_v3() from public,anon,authenticated,service_role;
revoke all on function public.reserve_signed_otp_v3(text,text,text),public.begin_signed_otp_v3(text,text,uuid,bigint),
 public.read_signed_otp_v3(text,text,uuid),public.record_signed_otp_v3(text,text,uuid,bigint,text,text,text),
 public.recover_signed_otp_v3(text,text,uuid,bigint,text,text),
 public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) from public,anon,authenticated,service_role;
grant execute on function public.reserve_signed_otp_v3(text,text,text),public.begin_signed_otp_v3(text,text,uuid,bigint),
 public.read_signed_otp_v3(text,text,uuid),public.record_signed_otp_v3(text,text,uuid,bigint,text,text,text),
 public.recover_signed_otp_v3(text,text,uuid,bigint,text,text),
 public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) to service_role;

comment on function public.recover_signed_otp_v3(text,text,uuid,bigint,text,text) is
 'Trusted service-only explicit evidence reconciliation; never resends or refunds quota. SHA binding is integrity, not provider authenticity.';


select pg_temp.otp_upgrade_check((select status='accepted' and accepted_at is not null and delivered_at is null and contract_version=2
 from collect_security.signed_otp_requests where hook_id='qa_otp_upgrade_sent'),'legacy sent becomes acceptance only');
select pg_temp.otp_upgrade_check((select status='ambiguous' and started_at is null and delivered_at is null and contract_version=2
 from collect_security.signed_otp_requests where hook_id='qa_otp_upgrade_unknown'),'legacy reserved remains unknown without resend');
select pg_temp.otp_upgrade_check((select enabled and global_hourly_limit=1000 and global_daily_limit=10000 from collect_security.otp_policy),'legacy policy preserved');
select pg_temp.otp_upgrade_check((select count(*)=2 from public.otp_rate_limits where phone_hash=repeat('8',64)),'legacy quota charges retained');
create temp table otp_before_reapply as select hook_id,to_jsonb(r) row_body from collect_security.signed_otp_requests r;


-- Install the signed-hook budget contract in the canonical migration chain.
-- No quota is invented: the owner must configure the private singleton row.
create schema if not exists collect_security;
revoke all on schema collect_security from public, anon, authenticated, service_role;
create table if not exists collect_security.otp_policy (
 singleton boolean primary key default true check (singleton),
 global_hourly_limit integer not null check (global_hourly_limit between 1 and 100000),
 global_daily_limit integer not null check (global_daily_limit between 1 and 1000000),
 enabled boolean not null default false
);
create table if not exists collect_security.signed_otp_requests (
 hook_id text primary key,
 payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
 phone_hash text not null check (phone_hash ~ '^[a-f0-9]{64}$'),
 requested_at timestamptz not null default clock_timestamp(),
 delivered_at timestamptz,
 status text not null default 'reserved'
);
-- PostgreSQL counted regex repetitions stop at255. Keep the documented256
-- ASCII-character contract with an independent length bound. Replace the
-- staged/default constraint as well when upgrading an existing table.
alter table collect_security.signed_otp_requests drop constraint if exists signed_otp_requests_hook_id_check;
alter table collect_security.signed_otp_requests drop constraint if exists signed_otp_hook_v3;
alter table collect_security.signed_otp_requests add constraint signed_otp_hook_v3
 check (char_length(hook_id) between 1 and 256 and hook_id ~ '^[A-Za-z0-9_:.-]+$');
alter table collect_security.signed_otp_requests add column if not exists attempt_id uuid;
alter table collect_security.signed_otp_requests add column if not exists revision bigint not null default 1;
alter table collect_security.signed_otp_requests add column if not exists started_at timestamptz;
alter table collect_security.signed_otp_requests add column if not exists accepted_at timestamptz;
alter table collect_security.signed_otp_requests add column if not exists provider_message_hash text;
alter table collect_security.signed_otp_requests add column if not exists last_evidence_sha256 text;
alter table collect_security.signed_otp_requests add column if not exists contract_version integer not null default 3;

-- A staged-v2 "sent" row proves an HTTP acknowledgement, not delivery.
-- A staged-v2 reservation might already have reached the provider: never retry it.
do $$ declare c record;
begin
 if exists (select 1 from collect_security.signed_otp_requests
   where status not in ('reserved','sent','sending','accepted','delivered','not_sent','failed','ambiguous','expired')) then
   raise exception 'OTP stored state unavailable' using errcode='55000';
 end if;
 for c in select conname from pg_constraint
   where conrelid='collect_security.signed_otp_requests'::regclass and contype='c'
     and pg_get_constraintdef(oid) ~ '\mstatus\M'
 loop execute format('alter table collect_security.signed_otp_requests drop constraint %I',c.conname); end loop;
 update collect_security.signed_otp_requests
 set status=case when status='sent' then 'accepted' else 'ambiguous' end,
     accepted_at=case when status='sent' then delivered_at else null end,
     delivered_at=null, attempt_id=gen_random_uuid(), contract_version=2
 where attempt_id is null;
end $$;
alter table collect_security.signed_otp_requests alter column attempt_id set default gen_random_uuid();
alter table collect_security.signed_otp_requests alter column attempt_id set not null;
alter table collect_security.signed_otp_requests add constraint signed_otp_state_v3
 check (status in ('reserved','sending','accepted','delivered','not_sent','failed','ambiguous','expired'));
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='collect_security.signed_otp_requests'::regclass and conname='signed_otp_revision_v3') then
   alter table collect_security.signed_otp_requests add constraint signed_otp_revision_v3 check (revision between 1 and 1000000);
 end if;
 if not exists(select 1 from pg_constraint where conrelid='collect_security.signed_otp_requests'::regclass and conname='signed_otp_provider_hash_v3') then
   alter table collect_security.signed_otp_requests add constraint signed_otp_provider_hash_v3 check (provider_message_hash is null or provider_message_hash ~ '^[a-f0-9]{64}$');
 end if;
 if not exists(select 1 from pg_constraint where conrelid='collect_security.signed_otp_requests'::regclass and conname='signed_otp_evidence_hash_v3') then
   alter table collect_security.signed_otp_requests add constraint signed_otp_evidence_hash_v3 check (last_evidence_sha256 is null or last_evidence_sha256 ~ '^[a-f0-9]{64}$');
 end if;
end $$;
create index if not exists signed_otp_requests_window on collect_security.signed_otp_requests(requested_at);
create unique index if not exists signed_otp_attempt_v3 on collect_security.signed_otp_requests(attempt_id);
create table if not exists collect_security.signed_otp_evidence (
 id bigint generated always as identity primary key,
 hook_id text not null references collect_security.signed_otp_requests(hook_id),
 attempt_id uuid not null,
 revision bigint not null check (revision between 1 and 1000000),
 evidence_sha256 text not null check (evidence_sha256 ~ '^[a-f0-9]{64}$'),
 evidence_kind text not null check (evidence_kind in ('transport_accepted','transport_ambiguous','expired_unsent',
   'operator_accepted','operator_delivered','operator_not_sent','operator_failed','operator_ambiguous')),
 provider_message_hash text check (provider_message_hash is null or provider_message_hash ~ '^[a-f0-9]{64}$'),
 recorded_at timestamptz not null default clock_timestamp(),
 observed_at timestamptz not null,
 source text not null check (source in ('hook_worker','local_clock','operator_verified_provider_status')),
 unique(hook_id,revision)
);
alter table collect_security.otp_policy enable row level security;
alter table collect_security.signed_otp_requests enable row level security;
alter table collect_security.signed_otp_evidence enable row level security;
revoke all on collect_security.otp_policy,collect_security.signed_otp_requests,collect_security.signed_otp_evidence
 from public,anon,authenticated,service_role;
revoke all on sequence collect_security.signed_otp_evidence_id_seq from public,anon,authenticated,service_role;

create or replace function collect_security.require_otp_service_v3()
returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then
   raise exception 'OTP authorization required' using errcode='42501';
 end if;
end $$;
create or replace function collect_security.otp_receipt_v3(r collect_security.signed_otp_requests)
returns jsonb language plpgsql immutable security definer set search_path='' as $$
begin
 if r.contract_version not in (2,3) or r.revision is null or r.attempt_id is null or
   (r.status='sending' and r.started_at is null) or
   (r.status='accepted' and r.contract_version=3 and (r.accepted_at is null or r.provider_message_hash is null)) or
   (r.status='delivered' and (r.accepted_at is null or r.delivered_at is null or r.provider_message_hash is null)) then
   raise exception 'OTP stored state unavailable' using errcode='55000';
 end if;
 return jsonb_build_object('contract_version',3,'hook_id',r.hook_id,'payload_hash',r.payload_hash,
   'attempt_id',r.attempt_id,'state',r.status,'revision',r.revision,
   'can_send',r.contract_version=3 and r.status='reserved');
end $$;
create or replace function collect_security.otp_expire_v3(p_hook_id text)
returns void language plpgsql security definer set search_path='' as $$
declare r collect_security.signed_otp_requests; kind text; h text; t timestamptz:=clock_timestamp();
begin
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.status='reserved' and r.requested_at<t-interval '5 minutes' then
   kind:='expired_unsent';
 elsif r.status='sending' and r.started_at<t-interval '1 minute' then
   kind:='transport_ambiguous';
 else return; end if;
 h:=encode(extensions.digest(convert_to(kind||':'||r.attempt_id::text||':'||r.revision::text,'UTF8'),'sha256'),'hex');
 update collect_security.signed_otp_requests set status=case when kind='expired_unsent' then 'expired' else 'ambiguous' end,
   revision=revision+1,last_evidence_sha256=h where hook_id=r.hook_id returning * into r;
 insert into collect_security.signed_otp_evidence(hook_id,attempt_id,revision,evidence_sha256,evidence_kind,observed_at,source)
 values(r.hook_id,r.attempt_id,r.revision,h,kind,t,'local_clock');
end $$;

create or replace function public.reserve_signed_otp_v3(p_hook_id text,p_payload_hash text,p_phone_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare p collect_security.otp_policy; r collect_security.signed_otp_requests; t timestamptz;
begin
 perform collect_security.require_otp_service_v3();
 if p_hook_id is null or char_length(p_hook_id) not between 1 and 256
   or p_hook_id !~ '^[A-Za-z0-9_:.-]+$' or p_payload_hash is null
   or p_payload_hash !~ '^[a-f0-9]{64}$' or p_phone_hash is null or p_phone_hash !~ '^[a-f0-9]{64}$' then
   raise exception 'OTP identity unavailable' using errcode='22023';
 end if;
 -- Consistent policy->request->phone order fences simultaneous quota decisions.
 update collect_security.otp_policy set enabled=enabled where singleton returning * into p;
 if p.singleton is null then raise exception 'OTP policy unavailable' using errcode='55000'; end if;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is not null then
   if r.payload_hash<>p_payload_hash or r.phone_hash<>p_phone_hash then
     raise exception 'OTP identity conflict' using errcode='22023';
   end if;
   perform collect_security.otp_expire_v3(r.hook_id);
   select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id;
   return collect_security.otp_receipt_v3(r);
 end if;
 if not p.enabled then raise exception 'OTP policy unavailable' using errcode='55000'; end if;
 t:=clock_timestamp();
 if (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '1 hour')>=p.global_hourly_limit
   or (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '24 hours')>=p.global_daily_limit then
   return to_jsonb('throttled'::text);
 end if;
 if not public.reserve_otp_request(p_phone_hash,null) then return to_jsonb('throttled'::text); end if;
 insert into collect_security.signed_otp_requests(hook_id,payload_hash,phone_hash,requested_at)
 values(p_hook_id,p_payload_hash,p_phone_hash,t) returning * into r;
 return collect_security.otp_receipt_v3(r);
end $$;

create or replace function public.begin_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid,p_revision bigint)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare p collect_security.otp_policy; r collect_security.signed_otp_requests;
begin
 perform collect_security.require_otp_service_v3();
 update collect_security.otp_policy set enabled=enabled where singleton returning * into p;
 if p.singleton is null or not p.enabled then raise exception 'OTP policy unavailable' using errcode='55000'; end if;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id then
   raise exception 'OTP identity conflict' using errcode='22023';
 end if;
 perform collect_security.otp_expire_v3(r.hook_id);
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id;
 if r.contract_version<>3 or r.status<>'reserved' or r.revision is distinct from p_revision then
   return collect_security.otp_receipt_v3(r)||jsonb_build_object('started',false);
 end if;
 update collect_security.signed_otp_requests set status='sending',started_at=clock_timestamp(),revision=revision+1
 where hook_id=r.hook_id returning * into r;
 return collect_security.otp_receipt_v3(r)||jsonb_build_object('started',true);
end $$;

create or replace function public.read_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare r collect_security.signed_otp_requests;
begin
 perform collect_security.require_otp_service_v3();
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id then
   raise exception 'OTP identity conflict' using errcode='22023';
 end if;
 perform collect_security.otp_expire_v3(r.hook_id);
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id;
 return collect_security.otp_receipt_v3(r);
end $$;

create or replace function public.record_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid,p_revision bigint,
 p_outcome text,p_provider_message_hash text,p_evidence_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare r collect_security.signed_otp_requests; e collect_security.signed_otp_evidence;
begin
 perform collect_security.require_otp_service_v3();
 if p_outcome is null or p_outcome not in ('accepted','ambiguous') or p_evidence_sha256 is null
   or p_evidence_sha256 !~ '^[a-f0-9]{64}$' or
   (p_outcome='accepted' and (p_provider_message_hash is null or p_provider_message_hash !~ '^[a-f0-9]{64}$')) or
   (p_outcome='ambiguous' and p_provider_message_hash is not null) then
   raise exception 'OTP evidence unavailable' using errcode='22023';
 end if;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id
   or r.contract_version<>3 then raise exception 'OTP identity conflict' using errcode='22023'; end if;
 select * into e from collect_security.signed_otp_evidence where hook_id=r.hook_id
   and revision>=p_revision+1 and evidence_sha256=p_evidence_sha256 and evidence_kind='transport_'||p_outcome;
 if e.id is not null and e.evidence_sha256=p_evidence_sha256 and e.evidence_kind='transport_'||p_outcome
   and e.provider_message_hash is not distinct from p_provider_message_hash then return collect_security.otp_receipt_v3(r); end if;
 -- Late accepted completion is allowed after lease expiry only while unresolved.
 -- It cannot override a contradictory independent provider recovery.
 if r.status not in ('sending','ambiguous') or r.started_at is null or
   (r.revision<>p_revision and not (r.status='ambiguous' and r.revision=p_revision+1 and
     exists(select 1 from collect_security.signed_otp_evidence where hook_id=r.hook_id
       and revision=r.revision and source='local_clock' and evidence_kind='transport_ambiguous'))) then
   raise exception 'OTP completion conflict' using errcode='40001';
 end if;
 update collect_security.signed_otp_requests set status=p_outcome,revision=revision+1,
   accepted_at=case when p_outcome='accepted' then clock_timestamp() else null end,
   provider_message_hash=p_provider_message_hash,last_evidence_sha256=p_evidence_sha256
 where hook_id=r.hook_id returning * into r;
 insert into collect_security.signed_otp_evidence(hook_id,attempt_id,revision,evidence_sha256,evidence_kind,
   provider_message_hash,observed_at,source)
 values(r.hook_id,r.attempt_id,r.revision,p_evidence_sha256,'transport_'||p_outcome,
   p_provider_message_hash,clock_timestamp(),'hook_worker');
 return collect_security.otp_receipt_v3(r);
end $$;

-- Explicit operator reconciliation. This is not a provider webhook integration:
-- the trusted service caller must independently verify provider evidence first.
-- Hash binding records the evidence; it does not authenticate its truth.
create or replace function public.recover_signed_otp_v3(p_hook_id text,p_payload_hash text,p_attempt_id uuid,
 p_revision bigint,p_evidence_text text,p_evidence_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare r collect_security.signed_otp_requests; e jsonb; outcome text; provider_hash text; observed timestamptz;
 h text; prior collect_security.signed_otp_evidence;
begin
 perform collect_security.require_otp_service_v3();
 if p_evidence_text is null or octet_length(p_evidence_text)>4096 or p_evidence_sha256 is null
   or p_evidence_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'OTP evidence unavailable' using errcode='22023'; end if;
 h:=encode(extensions.digest(convert_to(p_evidence_text,'UTF8'),'sha256'),'hex');
 if h<>p_evidence_sha256 then raise exception 'OTP evidence unavailable' using errcode='22023'; end if;
 begin e:=p_evidence_text::jsonb; exception when others then raise exception 'OTP evidence unavailable' using errcode='22023'; end;
 if jsonb_typeof(e)<>'object' or (select count(*) from jsonb_object_keys(e))<>7 or
   not (e ?& array['hook_id','payload_hash','attempt_id','outcome','provider_message_hash','observed_at','source']) or
   jsonb_typeof(e->'hook_id')<>'string' or jsonb_typeof(e->'payload_hash')<>'string' or
   jsonb_typeof(e->'attempt_id')<>'string' or jsonb_typeof(e->'outcome')<>'string' or
   jsonb_typeof(e->'observed_at')<>'string' or jsonb_typeof(e->'source')<>'string' or
   e->>'hook_id' is distinct from p_hook_id or e->>'payload_hash' is distinct from p_payload_hash or
   e->>'attempt_id' is distinct from p_attempt_id::text or e->>'source'<>'operator_verified_provider_status' then
   raise exception 'OTP evidence unavailable' using errcode='22023';
 end if;
 outcome:=e->>'outcome'; provider_hash:=e->>'provider_message_hash';
 if outcome not in ('accepted','delivered','not_sent','failed','ambiguous') or
   (outcome in ('accepted','delivered','failed') and (jsonb_typeof(e->'provider_message_hash')<>'string' or provider_hash is null or provider_hash !~ '^[a-f0-9]{64}$')) or
   (outcome in ('not_sent','ambiguous') and jsonb_typeof(e->'provider_message_hash')<>'null') or
   e->>'observed_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
   raise exception 'OTP evidence unavailable' using errcode='22023';
 end if;
 begin observed:=(e->>'observed_at')::timestamptz; exception when others then raise exception 'OTP evidence unavailable' using errcode='22023'; end;
 select * into r from collect_security.signed_otp_requests where hook_id=p_hook_id for update;
 if r.hook_id is null or r.payload_hash is distinct from p_payload_hash or r.attempt_id is distinct from p_attempt_id then
   raise exception 'OTP identity conflict' using errcode='22023'; end if;
 if observed<r.requested_at-interval '1 minute' or observed>clock_timestamp()+interval '1 minute' then
   raise exception 'OTP evidence unavailable' using errcode='22023'; end if;
 select * into prior from collect_security.signed_otp_evidence where hook_id=r.hook_id
   and evidence_sha256=p_evidence_sha256 and source='operator_verified_provider_status';
 if prior.id is not null then return collect_security.otp_receipt_v3(r); end if;
 if r.revision is distinct from p_revision or r.status in ('delivered','failed','not_sent','expired') or
   (r.status='accepted' and outcome not in ('delivered','failed')) or
   (r.status='reserved' and outcome<>'not_sent') or
   (r.status in ('sending','ambiguous') and outcome='ambiguous' and r.status='ambiguous') or
   (r.provider_message_hash is not null and provider_hash is distinct from r.provider_message_hash) then
   raise exception 'OTP recovery conflict' using errcode='40001';
 end if;
 update collect_security.signed_otp_requests set status=outcome,revision=revision+1,
   accepted_at=case when outcome in ('accepted','delivered') then coalesce(accepted_at,observed) else accepted_at end,
   delivered_at=case when outcome='delivered' then observed else null end,
   provider_message_hash=provider_hash,last_evidence_sha256=p_evidence_sha256
 where hook_id=r.hook_id returning * into r;
 insert into collect_security.signed_otp_evidence(hook_id,attempt_id,revision,evidence_sha256,evidence_kind,
   provider_message_hash,observed_at,source)
 values(r.hook_id,r.attempt_id,r.revision,p_evidence_sha256,'operator_'||outcome,
   provider_hash,observed,'operator_verified_provider_status');
 return collect_security.otp_receipt_v3(r);
end $$;

create or replace function collect_security.guard_otp_evidence_v3()
returns trigger language plpgsql set search_path='' as $$
begin raise exception 'OTP evidence is immutable' using errcode='55000'; end $$;
drop trigger if exists signed_otp_evidence_immutable on collect_security.signed_otp_evidence;
create trigger signed_otp_evidence_immutable before update or delete on collect_security.signed_otp_evidence
 for each row execute function collect_security.guard_otp_evidence_v3();

-- Old callers must not launch new sends or convert an unknown send to success.
create or replace function public.reserve_signed_otp_v2(p_hook_id text,p_payload_hash text,p_phone_hash text)
returns text language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 r:=public.reserve_signed_otp_v3(p_hook_id,p_payload_hash,p_phone_hash);
 if r=to_jsonb('throttled'::text) then return 'throttled'; end if;
 return case when r->>'state' in ('accepted','delivered') then 'already_sent' else 'unresolved' end;
end $$;
create or replace function public.complete_signed_otp_v2(p_hook_id text,p_payload_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
begin perform collect_security.require_otp_service_v3(); return false; end $$;

revoke all on function collect_security.require_otp_service_v3(),
 collect_security.otp_receipt_v3(collect_security.signed_otp_requests),collect_security.otp_expire_v3(text),
 collect_security.guard_otp_evidence_v3() from public,anon,authenticated,service_role;
revoke all on function public.reserve_signed_otp_v3(text,text,text),public.begin_signed_otp_v3(text,text,uuid,bigint),
 public.read_signed_otp_v3(text,text,uuid),public.record_signed_otp_v3(text,text,uuid,bigint,text,text,text),
 public.recover_signed_otp_v3(text,text,uuid,bigint,text,text),
 public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) from public,anon,authenticated,service_role;
grant execute on function public.reserve_signed_otp_v3(text,text,text),public.begin_signed_otp_v3(text,text,uuid,bigint),
 public.read_signed_otp_v3(text,text,uuid),public.record_signed_otp_v3(text,text,uuid,bigint,text,text,text),
 public.recover_signed_otp_v3(text,text,uuid,bigint,text,text),
 public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) to service_role;

comment on function public.recover_signed_otp_v3(text,text,uuid,bigint,text,text) is
 'Trusted service-only explicit evidence reconciliation; never resends or refunds quota. SHA binding is integrity, not provider authenticity.';


select pg_temp.otp_upgrade_check(not exists(select 1 from otp_before_reapply b full join collect_security.signed_otp_requests r using(hook_id)
 where b.row_body is distinct from to_jsonb(r)),'reapply preserves every attempt and stored outcome');
select pg_temp.otp_upgrade_check((select count(*)=0 from collect_security.signed_otp_evidence),'reapply invents no historical provider evidence');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select pg_temp.otp_upgrade_check(public.reserve_signed_otp_v2('qa_otp_upgrade_sent',repeat('a',64),repeat('8',64))='already_sent','legacy accepted hook acknowledgement preserved');
select pg_temp.otp_upgrade_check(public.reserve_signed_otp_v2('qa_otp_upgrade_unknown',repeat('a',64),repeat('8',64))='unresolved','legacy unresolved cannot authorize send');
select pg_temp.otp_upgrade_check(not public.complete_signed_otp_v2('qa_otp_upgrade_unknown',repeat('a',64)),'legacy completion cannot fabricate success');
reset role;
select label from otp_upgrade_checks order by label;
select 'SIGNED_OTP_UPGRADE_UAT_PASS: '||count(*)||' checks' from otp_upgrade_checks;
rollback;

