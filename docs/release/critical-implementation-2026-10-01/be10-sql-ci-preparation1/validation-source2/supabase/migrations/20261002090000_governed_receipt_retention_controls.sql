-- Specific governed controls for lossless700 hot/cold maintenance. No expiry,
-- erasure, sender, run or financial authority. Existing prepare stays unchanged.
begin;
do $$begin
 if not exists(select 1 from pg_proc where oid='collect_receipt_worker_history.prepare(bigint,boolean,integer,integer)'::regprocedure
 and pg_get_userbyid(proowner)='postgres' and prosecdef and proconfig=array['search_path=""','lock_timeout=2s']
 and proacl=array['postgres=X/postgres']::aclitem[]
 and encode(sha256(convert_to(prosrc,'UTF8')),'hex')='3c661e6791647f931d3248c29b517448d3b8647f418107101cfc2f0abbff0122')
 or not exists(select 1 from pg_proc where oid='collect_receipt_worker_history.source_proof(text,uuid,uuid,uuid)'::regprocedure
 and encode(sha256(convert_to(prosrc,'UTF8')),'hex')='ac9c55abcc29e42b5485bbad7eeca81cce30a5aed6204fabdd450f994514861b')
 then raise exception 'receipt_retention_predecessor_changed' using errcode='55000';end if;
end$$;
create schema collect_receipt_retention_controls authorization postgres;
revoke all on schema collect_receipt_retention_controls from public,anon,authenticated,service_role;
create table collect_receipt_retention_controls.adoption(
 singleton boolean primary key default true check(singleton),
 adopted_at timestamptz not null check(isfinite(adopted_at)),
 configuration jsonb not null check(jsonb_typeof(configuration)='object'),
 protocol_sha256 text not null check(protocol_sha256~'^[0-9a-f]{64}$')
);
insert into collect_receipt_retention_controls.adoption
 select true,clock_timestamp(),to_jsonb(c)-'singleton','c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3' from collect_receipt_worker_history.configuration c where singleton;
do $$begin if(select count(*)from collect_receipt_retention_controls.adoption)<>1 then
 raise exception 'receipt_retention_configuration_unavailable'using errcode='55000';end if;end$$;
create table collect_receipt_retention_controls.requests(
 request_id uuid primary key check(request_id<>'00000000-0000-0000-0000-000000000000'),
 actor_id uuid not null references auth.users(id), session_id uuid not null references auth.sessions(id),
 fingerprint_sha256 text not null check(fingerprint_sha256~'^[0-9a-f]{64}$'),
 intent jsonb not null check(jsonb_typeof(intent)='object'),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 before_configuration jsonb not null, after_configuration jsonb not null,
 before_cron jsonb not null, after_cron jsonb not null, result jsonb not null
);
alter table collect_receipt_retention_controls.adoption enable row level security;
alter table collect_receipt_retention_controls.requests enable row level security;
revoke all on all tables in schema collect_receipt_retention_controls from public,anon,authenticated,service_role;
create function collect_receipt_retention_controls.immutable()returns trigger language plpgsql set search_path='' as $$begin
 raise exception 'receipt_retention_record_immutable'using errcode='55000';end$$;
create trigger immutable before update or delete on collect_receipt_retention_controls.adoption for each row execute function collect_receipt_retention_controls.immutable();
create trigger immutable before update or delete on collect_receipt_retention_controls.requests for each row execute function collect_receipt_retention_controls.immutable();
create function collect_receipt_retention_controls.actor(p_manage boolean)returns uuid
language plpgsql security definer set search_path='' as $$declare sid uuid;begin
 sid:=collect_supervisor.owner_actor();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',
 case when p_manage then array['settings.read','settings.manage']else array['settings.read']end);
 return sid;
end$$;
create function collect_receipt_retention_controls.utc(p_at timestamptz)returns text
language sql immutable strict set search_path='' as $$select to_char(p_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;
create function collect_receipt_retention_controls.configuration(c jsonb)returns jsonb
language sql immutable strict set search_path=''as $$select c||jsonb_build_object('updated_at',collect_receipt_retention_controls.utc((c->>'updated_at')::timestamptz))$$;
create function collect_receipt_retention_controls.cron()returns jsonb
language plpgsql security definer set search_path='' as $$declare rows jsonb; r jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(j)),'[]'::jsonb)into rows from
 (select jobid,schedule,command,active,username,database from cron.job
 where jobname='collect-receipt-history-maintenance'order by jobid limit 2)j;
 if jsonb_array_length(rows)>1 then raise exception 'receipt_retention_cron_ambiguous'using errcode='55000';end if;
 if jsonb_array_length(rows)=0 then return jsonb_build_object('state','absent','job_id',null,'schedule',null,'command_sha256',null);end if;
 r:=rows->0;
 if r->>'username'<>current_user or r->>'database'<>current_database()
 or r->>'command'<>'select collect_receipt_worker_history.run_schedule();'or r->>'schedule'<>'* * * * *' then
 raise exception 'receipt_retention_cron_binding_changed'using errcode='55000';end if;
 return jsonb_build_object('state',case when(r->>'active')::boolean then 'active'else 'inactive'end,
 'job_id',(r->>'jobid')::bigint,'schedule',r->>'schedule','command_sha256',encode(sha256(convert_to(r->>'command','UTF8')),'hex'));
exception when insufficient_privilege then
 return jsonb_build_object('state','unavailable','job_id',null,'schedule',null,'command_sha256',null);
end$$;
create function public.admin_get_receipt_retention_controls_v1()returns jsonb
language plpgsql volatile security definer set search_path='' set statement_timeout='15s' as $$
declare sid uuid; c collect_receipt_worker_history.configuration; t timestamptz; j jsonb; manage boolean:=true;begin
 sid:=collect_receipt_retention_controls.actor(false);
 select * into c from collect_receipt_worker_history.configuration where singleton for share;
 if not found then raise exception 'receipt_retention_configuration_unavailable'using errcode='55000';end if;
 j:=collect_receipt_retention_controls.cron();
 if collect_receipt_retention_controls.actor(false)<>sid then raise exception 'receipt_retention_session_changed'using errcode='42501';end if;
 begin perform collect_receipt_retention_controls.actor(true);exception when insufficient_privilege then manage:=false;end;
 t:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_retention_controls','actor_id',auth.uid(),'session_id',sid,
 'checked_at',collect_receipt_retention_controls.utc(t),'sample_valid_until',collect_receipt_retention_controls.utc(t+interval '60 seconds'),
 'configuration',collect_receipt_retention_controls.configuration(to_jsonb(c)-'singleton'),'cron',j,
 'retention',jsonb_build_object('cold_expiry_allowed',false,'raw_financial_expiry_allowed',false,
 'unknown_outcome_hold_required',true,'late_callback_bindings_retained',true,'protocol_sha256','c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3'),
 'platform_policies',jsonb_build_object('scheduler',jsonb_build_object('specification_sha256','559819220b3503ddb0ad13af669cf878bb00107b0c88accae0b86a3fb042c5b6','verification_state','release_declared','observed_at',null),
 'android',jsonb_build_object('specification_sha256','e72be359be948dd74ec1d84ce83aa8238e13a93d9abe5a7e9d639d157722ab1c','verification_state','release_declared','observed_at',null)), 'mutation_allowed',manage);
end$$;
create function collect_receipt_retention_controls.intent(p_request_id uuid,p_actor uuid,p_session uuid,p_expected_revision bigint,
 p_enabled boolean,p_batch_limit integer,p_byte_limit integer,p_reason text,p_expires_at timestamptz)returns jsonb
language sql immutable set search_path='' as $$select jsonb_build_object('request_id',p_request_id,'actor_id',p_actor,'session_id',p_session,
 'expected_revision',p_expected_revision,'enabled',p_enabled,'batch_limit',p_batch_limit,'byte_limit',p_byte_limit,
 'reason',p_reason,'expires_at',collect_receipt_retention_controls.utc(p_expires_at),'protocol_sha256','c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3')$$;
create function collect_receipt_retention_controls.fingerprint(i jsonb)returns text
language sql immutable strict set search_path=''as $$select encode(sha256(convert_to(
 'receipt-retention-v1'||chr(10)||concat_ws(chr(10),i->>'request_id',i->>'actor_id',i->>'session_id',i->>'expected_revision',i->>'enabled',
 i->>'batch_limit',i->>'byte_limit',encode(sha256(convert_to(i->>'reason','UTF8')),'hex'),i->>'expires_at',i->>'protocol_sha256'),'UTF8')),'hex')$$;
create function public.admin_configure_receipt_retention_controls_v1(p_request_id uuid,p_expected_revision bigint,p_enabled boolean,
 p_batch_limit integer,p_byte_limit integer,p_reason text,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path='' set statement_timeout='15s' as $$
declare sid uuid; i jsonb; fp text; old collect_receipt_retention_controls.requests; before_c jsonb;after_c jsonb; before_j jsonb;after_j jsonb;t timestamptz;r jsonb;begin
 sid:=collect_receipt_retention_controls.actor(true);
 if p_request_id is null or p_request_id='00000000-0000-0000-0000-000000000000' or p_expected_revision is null or p_expected_revision<1 or p_expected_revision>=1000000000
 or p_enabled is null or p_batch_limit is null or p_batch_limit not between 1 and 25 or p_byte_limit is null or p_byte_limit not between 1 and 4194304
 or p_reason is null or length(p_reason)not between 10 and 500 or p_reason<>btrim(p_reason)or p_reason~'[[:cntrl:]]'
 or p_expires_at is null or not isfinite(p_expires_at) then raise exception 'receipt_retention_intent_invalid'using errcode='22023';end if;
 i:=collect_receipt_retention_controls.intent(p_request_id,auth.uid(),sid,p_expected_revision,p_enabled,p_batch_limit,p_byte_limit,p_reason,p_expires_at);
 fp:=collect_receipt_retention_controls.fingerprint(i);
 perform pg_advisory_xact_lock(hashtext('collect-receipt-retention-request:'||p_request_id::text));
 if collect_receipt_retention_controls.actor(true)<>sid then raise exception 'receipt_retention_session_changed'using errcode='42501';end if;
 select *into old from collect_receipt_retention_controls.requests where request_id=p_request_id;
 if found then
 if old.actor_id<>auth.uid()or old.session_id<>sid or old.intent is distinct from i or old.fingerprint_sha256<>fp
 then raise exception 'receipt_retention_request_conflict'using errcode='55000';end if;
 return old.result;
 end if;
 t:=clock_timestamp();
 if p_expires_at<=t or p_expires_at>t+interval '120 seconds'then raise exception 'receipt_retention_request_expired'using errcode='22023';end if;
 -- Same actual700 publication/maintenance lock, before config; nonblocking.
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-history-maintenance'))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 select collect_receipt_retention_controls.configuration(to_jsonb(c)-'singleton')into before_c from collect_receipt_worker_history.configuration c where singleton for update nowait;
 if before_c is null then raise exception 'receipt_retention_configuration_unavailable'using errcode='55000';end if;
 before_j:=collect_receipt_retention_controls.cron();
 after_c:=collect_receipt_retention_controls.configuration(collect_receipt_worker_history.prepare(p_expected_revision,p_enabled,p_batch_limit,p_byte_limit));
 after_j:=collect_receipt_retention_controls.cron();
 if after_j->>'state'<>(case when p_enabled then 'active'else 'inactive'end)then raise exception 'receipt_retention_cron_unavailable'using errcode='55000';end if;
 if collect_receipt_retention_controls.actor(true)<>sid then raise exception 'receipt_retention_session_changed'using errcode='42501';end if;
 t:=clock_timestamp();if p_expires_at<=t then raise exception 'receipt_retention_request_expired'using errcode='22023';end if;
 r:=jsonb_build_object('contract_version',1,'scope','rw_receipt_retention_control_request','status','recorded','request_id',p_request_id,
 'actor_id',auth.uid(),'session_id',sid,'fingerprint_sha256',fp,'intent',i,'recorded_at',collect_receipt_retention_controls.utc(t),
 'before_configuration',before_c,'after_configuration',after_c,'before_cron',before_j,'after_cron',after_j);
 insert into collect_receipt_retention_controls.requests values(p_request_id,auth.uid(),sid,fp,i,t,before_c,after_c,before_j,after_j,r);
 return r;
end$$;
create function public.admin_get_receipt_retention_control_request_v1(p_request_id uuid,p_fingerprint_sha256 text,p_intent jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''set statement_timeout='15s'as $$
declare sid uuid;old collect_receipt_retention_controls.requests;i jsonb;begin
 sid:=collect_receipt_retention_controls.actor(false);
 if p_request_id is null or p_request_id='00000000-0000-0000-0000-000000000000'or p_fingerprint_sha256 is null or p_fingerprint_sha256!~'^[0-9a-f]{64}$'
 then raise exception 'receipt_retention_intent_invalid'using errcode='22023';end if;
 if p_intent is null or jsonb_typeof(p_intent)<>'object' then raise exception 'receipt_retention_intent_invalid'using errcode='22023';end if;
 i:=collect_receipt_retention_controls.intent(p_request_id,auth.uid(),sid,(p_intent->>'expected_revision')::bigint,
 (p_intent->>'enabled')::boolean,(p_intent->>'batch_limit')::integer,(p_intent->>'byte_limit')::integer,p_intent->>'reason',(p_intent->>'expires_at')::timestamptz);
 if p_intent is distinct from i or collect_receipt_retention_controls.fingerprint(i)is distinct from p_fingerprint_sha256
 or not coalesce((i->>'expected_revision')::bigint between 1 and 999999999,false)
 or not coalesce((i->>'batch_limit')::integer between 1 and 25,false)
 or not coalesce((i->>'byte_limit')::integer between 1 and 4194304,false)
 or i->>'enabled'is null or i->>'expires_at'is null or not isfinite((i->>'expires_at')::timestamptz)
 or not coalesce(length(i->>'reason')between 10 and 500,false)or i->>'reason'<>btrim(i->>'reason')or i->>'reason'~'[[:cntrl:]]'
 then raise exception 'receipt_retention_request_conflict'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtext('collect-receipt-retention-request:'||p_request_id::text));
 if collect_receipt_retention_controls.actor(false)<>sid then raise exception 'receipt_retention_session_changed'using errcode='42501';end if;
 select *into old from collect_receipt_retention_controls.requests where request_id=p_request_id;
 if not found then return jsonb_build_object('contract_version',1,'scope','rw_receipt_retention_control_request','status','not_recorded',
 'request_id',p_request_id,'actor_id',auth.uid(),'session_id',sid,'fingerprint_sha256',p_fingerprint_sha256,'intent',null,
 'checked_at',collect_receipt_retention_controls.utc(clock_timestamp()),'recorded_at',null,'before_configuration',null,'after_configuration',null,'before_cron',null,'after_cron',null);end if;
 if old.actor_id<>auth.uid()or old.session_id<>sid or old.fingerprint_sha256<>p_fingerprint_sha256
 then raise exception 'receipt_retention_request_conflict'using errcode='55000';end if;
 return old.result;
end$$;
revoke all on all functions in schema collect_receipt_retention_controls from public,anon,authenticated,service_role;
revoke all on function public.admin_get_receipt_retention_controls_v1(),
 public.admin_configure_receipt_retention_controls_v1(uuid,bigint,boolean,integer,integer,text,timestamptz),
 public.admin_get_receipt_retention_control_request_v1(uuid,text,jsonb)from public,anon,service_role;
grant execute on function public.admin_get_receipt_retention_controls_v1(),
 public.admin_configure_receipt_retention_controls_v1(uuid,bigint,boolean,integer,integer,text,timestamptz),
 public.admin_get_receipt_retention_control_request_v1(uuid,text,jsonb)to authenticated;
commit;
