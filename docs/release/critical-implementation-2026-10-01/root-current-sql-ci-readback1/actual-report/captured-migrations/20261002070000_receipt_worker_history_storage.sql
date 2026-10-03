begin;
set local lock_timeout='2s';

do $guard$declare e record;begin
 for e in select * from(values
('public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamp with time zone)','e6215b96adf3cdf504c7c3b3070986407329806a172259518bebaa0a7ac32e4c'),
('public.get_receipt_deferral_exception_scan_v1(uuid)','094cd792fe6ec2c1cd76dd39ec511542fa0f3e4fc94f530199a6981e408049cb'),
('public.execute_receipt_exception_worker_v1(uuid,bigint,timestamp with time zone)','e1f9398c57bac51ecc8b26c5c00aff65db702d28182d33a5e7b3fa1424af43c3'),
('public.get_receipt_exception_worker_request_v1(uuid)','f3639089953f1989e12a1bd021659a148a87d941943a4c57493e1ff52dd35eb8'),
('public.admin_get_receipt_exception_worker_health_v1()','2a919919b8f2644e1d78512cde6a0adfd6a28413e7a9083e4f8d7ddf069e1de0'),
('public.configure_receipt_exception_schedule_v1(bigint,boolean,integer,integer,integer,integer,integer)','867a29c4c4ce51198d24a00878d4598097dd3008a82edc2f89112c60ddc81902'),
('collect_ops.receipt_transport_base_schedule()','b816af7375ce65b587b551f3996d4a7c8521e93517bd8869cdbbe9a44c787929'),
('collect_ops.reconcile_receipt_transport(uuid,integer,timestamp with time zone)','94846abb56c8ed061ac926d5e543ad91fcf5efe27c6ab22bd393cfac4f0e3958'),
('public.get_receipt_worker_transport_request_v1(uuid)','e011463ff9a15030819c66ea89da8812378d0532b2ea01ac55ab0607953be229'),
('public.admin_get_receipt_worker_transport_v1(uuid)','482586254eba200fc1bc6946dba0ed80c00c257c3c289140edcce49619c0a285'),
('collect_ops.run_receipt_exception_schedule()','1448b86c78c49d50eb7f89dd5f9aed186a2d3276345d47449b8db033d5ca7e4a'),
('public.reconcile_receipt_worker_transport_v1(uuid,integer,timestamp with time zone)','e61c7d080f311fdac38c49dc195a88748db99cceaacaf241cd1bf86d434ff00c'),
('collect_ops.receipt_exception_service()','fad7a757a680730e954e4faec8235fd64fa5969f0e13d5d02947935eb57580d3'),
('collect_ops.immutable_evidence()','d162ae74733bf8028e85e508870d84482ae5a70fa24981a9e2c3001557369c7a'),
('collect_ops.protect_receipt_exception_work()','4ce67ee5313a6827916215b5a4707615223dfd85cb6c71396eef897b1c29f3fa'),
('collect_receipt_source_projection.try_retire_source(text,uuid,uuid,uuid)','2c610e28df0d68f7789e5e9c5cc7b14bf0107d6219007316b7079abdaa780c66'),
('public.gateway_receipt_successor_grant_v1(uuid,uuid,text,jsonb)','abde0ee8815ce0c1a5cd585569945ce4b18260c9106c716e75d836fbea9fd23e'),
('public.gateway_receipt_successor_arm_v1(uuid,uuid,text,jsonb)','08b5e431752f65efcac04fc5c9136ec16eb5aa7f7ddc2e12b6c124e034373343'),
('public.gateway_receipt_successor_callback_v1(uuid,uuid,text,jsonb)','746f86efee66a69773271e22f164db8e005ba086f36077fea6e826269d39bbf0'),
('public.gateway_receipt_successor_archive_v1(uuid,uuid,text,jsonb)','66c41a0839b949ef6c8bfaadfbcef1ae03ed645306250aa705cb43e9ef7fbc97'),
('public.admin_revoke_receipt_successor_v1(uuid,uuid,bigint,text)','9e3a5f4590ec3d7120b6622937be9c903b89544363780d8f5ac47c765e029de0'),
('public.admin_approve_receipt_successor_v1(uuid,uuid,text,uuid,bigint,bigint,text,timestamp with time zone,text,text)','dc763a7133ec3cf5686fa4a63071a8f7ace15fd14538981fd79139a2cb98ff46')
 )v(signature,body_sha256)loop
  if to_regprocedure(e.signature)is null or(select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc where oid=to_regprocedure(e.signature))is distinct from e.body_sha256 then
   raise exception 'receipt_worker_history_predecessor_drift:%',e.signature using errcode='55000';end if;
 end loop;
 if exists(select 1 from pg_class x cross join(values('anon'),('authenticated'),('service_role'))r(name)
  where x.oid in('collect_ops.receipt_worker_configuration_history'::regclass,'collect_ops.receipt_worker_receipts'::regclass,'collect_ops.receipt_exception_scans'::regclass,'collect_ops.receipt_transport_requests'::regclass,'collect_ops.receipt_transport_observations'::regclass)
  and(not x.relrowsecurity or has_table_privilege(r.name,x.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')or has_any_column_privilege(r.name,x.oid,'SELECT,INSERT,UPDATE,REFERENCES')))then
  raise exception 'receipt_worker_history_original_acl_drift'using errcode='55000';end if;
 for e in select *from(values
 ('receipt_worker_configuration_history','configuration','jsonb','retain_worker_evidence',array['revision']),
 ('receipt_worker_receipts','result','jsonb','retain_worker_evidence',array['request_id']),
 ('receipt_exception_scans','result','jsonb','retain_receipt_exception_scan',array['request_id']),
 ('receipt_transport_requests','result','jsonb','retain_transport_evidence',array['request_id']),
 ('receipt_transport_observations','response_rows_observed','integer','retain_transport_evidence',array['http_request_id','revision']))v(tab,col,typ,retained,pk)loop
  if not exists(select 1 from pg_attribute a where a.attrelid=('collect_ops.'||e.tab)::regclass and a.attname=e.col and not a.attisdropped and a.attnotnull and a.atttypid=e.typ::regtype)
   or not exists(select 1 from pg_trigger g where g.tgrelid=('collect_ops.'||e.tab)::regclass and g.tgname=e.retained and g.tgtype=27 and g.tgenabled='O'and g.tgfoid='collect_ops.immutable_evidence()'::regprocedure and g.tgnargs=0)
   or not exists(select 1 from pg_constraint c where c.conrelid=('collect_ops.'||e.tab)::regclass and c.contype='p'and c.convalidated and(select array_agg(a.attname::text order by key.ord)from unnest(c.conkey)with ordinality key(num,ord)join pg_attribute a on a.attrelid=c.conrelid and a.attnum=key.num)=e.pk)
  then raise exception 'receipt_worker_history_original_catalog_drift:%',e.tab using errcode='55000';end if;
 end loop;
 for e in select *from(values
 ('receipt_worker_receipts',array['request_id'],'collect_ops.receipt_worker_jobs',false),
 ('receipt_worker_receipts',array['scan_request_id'],'collect_ops.receipt_exception_scans',false),
 ('receipt_transport_observations',array['http_request_id'],'collect_ops.receipt_worker_dispatches',false),
 ('receipt_transport_observations',array['reconciliation_request_id'],'collect_ops.receipt_transport_requests',true))v(tab,cols,parent,deferred)loop
  if not exists(select 1 from pg_constraint c where c.conrelid=('collect_ops.'||e.tab)::regclass and c.contype='f'and c.confrelid=e.parent::regclass and c.convalidated and c.condeferrable=e.deferred and c.condeferred=e.deferred
   and(select array_agg(a.attname::text order by key.ord)from unnest(c.conkey)with ordinality key(num,ord)join pg_attribute a on a.attrelid=c.conrelid and a.attnum=key.num)=e.cols)
  then raise exception 'receipt_worker_history_original_fk_drift:%',e.tab using errcode='55000';end if;
 end loop;
 if not exists(select 1 from pg_constraint c where c.conrelid='collect_receipt_successors.approvals'::regclass and c.contype='f'and c.confrelid='collect_hybrid.sms_notification_outbox'::regclass and c.convalidated)
  or not exists(select 1 from pg_constraint c where c.conrelid='collect_receipt_successors.jobs'::regclass and c.contype='f'and c.confrelid='collect_receipt_successors.approvals'::regclass and c.convalidated)
  or not exists(select 1 from pg_constraint c where c.conrelid='collect_receipt_successors.jobs'::regclass and c.contype='f'and c.confrelid='collect_hybrid.sms_notification_outbox'::regclass and c.convalidated)
 then raise exception 'receipt_worker_history_successor_graph_drift'using errcode='55000';end if;
end$guard$;
create schema collect_receipt_worker_history;
revoke all on schema collect_receipt_worker_history from public,anon,authenticated,service_role;
create table collect_receipt_worker_history.bindings(
 family text not null check(family in('worker_configuration','worker_receipt','scan_receipt','transport_receipt','transport_observation')),
 original_key text not null check(length(original_key)between 1 and 80),codec_version integer not null check(codec_version=1),
 payload_sha256 text not null check(payload_sha256~'^[0-9a-f]{64}$'),payload_bytes bigint not null check(payload_bytes>=0),
 metadata_sha256 text not null check(metadata_sha256~'^[0-9a-f]{64}$'),logical_sha256 text not null check(logical_sha256~'^[0-9a-f]{64}$'),
 recorded_at timestamptz not null check(isfinite(recorded_at)),primary key(family,original_key));
create table collect_receipt_worker_history.objects(
 sha256 text primary key check(sha256~'^[0-9a-f]{64}$'),payload bytea not null,
 check(sha256=encode(extensions.digest(payload,'sha256'),'hex')));
create table collect_receipt_worker_history.requests(
 request_id uuid primary key,request_limit integer not null check(request_limit between 1 and 25),
 expires_at timestamptz not null check(isfinite(expires_at)),recorded_at timestamptz not null check(isfinite(recorded_at)),result jsonb not null,
 check(expires_at>recorded_at));
create table collect_receipt_worker_history.relocations(
 family text not null,original_key text not null,object_sha256 text not null references collect_receipt_worker_history.objects(sha256)on delete restrict,
 request_id uuid not null references collect_receipt_worker_history.requests(request_id)on delete restrict deferrable initially deferred,
 proof jsonb not null,proof_sha256 text not null check(proof_sha256~'^[0-9a-f]{64}$'),
 recorded_at timestamptz not null check(isfinite(recorded_at)),primary key(family,original_key),
 foreign key(family,original_key)references collect_receipt_worker_history.bindings on delete restrict,
 check(proof_sha256=encode(extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex')));
create table collect_receipt_worker_history.progress(
 singleton boolean primary key check(singleton),epoch bigint not null check(epoch between 1 and 1000000000),
 last_family text,last_key text,last_request_id uuid,last_recorded_at timestamptz,
 check((last_family is null)=(last_key is null)));
insert into collect_receipt_worker_history.progress(singleton,epoch)values(true,1);
create table collect_receipt_worker_history.configuration(
 singleton boolean primary key check(singleton),revision bigint not null check(revision between 1 and 1000000000),
 enabled boolean not null default false,batch_limit integer not null check(batch_limit between 1 and 25),
 byte_limit integer not null check(byte_limit between 1 and 4194304),updated_at timestamptz not null check(isfinite(updated_at)));
insert into collect_receipt_worker_history.configuration values(true,1,false,10,4194304,clock_timestamp());
create function collect_receipt_worker_history.immutable()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'receipt_worker_history_evidence_immutable'using errcode='55000';end$$;
do $$declare t text;begin
 foreach t in array array['bindings','objects','requests','relocations','progress','configuration']loop
  execute format('alter table collect_receipt_worker_history.%I enable row level security',t);
  execute format('revoke all on collect_receipt_worker_history.%I from public,anon,authenticated,service_role',t);
  if t not in('progress','configuration')then execute format('create trigger retained_history before update or delete on collect_receipt_worker_history.%I for each row execute function collect_receipt_worker_history.immutable()',t);end if;
  execute format('create trigger retained_history_truncate before truncate on collect_receipt_worker_history.%I for each statement execute function collect_receipt_worker_history.immutable()',t);
 end loop;end$$;
create function collect_receipt_worker_history.sha(p_json jsonb)returns text
language sql immutable set search_path=''as $$select encode(extensions.digest(convert_to(p_json::text,'UTF8'),'sha256'),'hex')$$;
create function collect_receipt_worker_history.fields(p_family text)returns text[]
language plpgsql immutable set search_path=''as $$begin
 case p_family when 'worker_configuration'then return array['configuration'];
 when 'worker_receipt','scan_receipt','transport_receipt'then return array['result'];
 when 'transport_observation'then return array['http_status','worker_error_code','response_rows_observed','response_at'];
 else raise exception 'receipt_worker_history_family_invalid'using errcode='22023';end case;end$$;
create function collect_receipt_worker_history.payload(p_family text,p_row jsonb)returns jsonb
language plpgsql immutable set search_path=''as $$declare keys text[];result jsonb;begin
 keys:=collect_receipt_worker_history.fields(p_family);
 if cardinality(keys)=1 then return p_row->keys[1];end if;
 select jsonb_object_agg(k,p_row->k)into result from unnest(keys)k;return result;end$$;
create function collect_receipt_worker_history.reconstruct(p_family text,p_metadata jsonb,p_payload jsonb)returns jsonb
language plpgsql immutable set search_path=''as $$declare keys text[];begin
 keys:=collect_receipt_worker_history.fields(p_family);
 if cardinality(keys)=1 then return p_metadata||jsonb_build_object(keys[1],p_payload);end if;
 if jsonb_typeof(p_payload)<>'object'or(select array_agg(k order by k)from jsonb_object_keys(p_payload)k)is distinct from(select array_agg(k order by k)from unnest(keys)k)then
  raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 return p_metadata||p_payload;end$$;
create function collect_receipt_worker_history.query(p_family text)returns text
language plpgsql immutable set search_path=''as $$declare tab text;predicate text;present text;begin
 case p_family when 'worker_configuration'then tab:='receipt_worker_configuration_history';predicate:='a.revision=($2)::bigint';present:='a.configuration is not null';
 when 'worker_receipt'then tab:='receipt_worker_receipts';predicate:='a.request_id=($2)::uuid';present:='a.result is not null';
 when 'scan_receipt'then tab:='receipt_exception_scans';predicate:='a.request_id=($2)::uuid';present:='a.result is not null';
 when 'transport_receipt'then tab:='receipt_transport_requests';predicate:='a.request_id=($2)::uuid';present:='a.result is not null';
 when 'transport_observation'then tab:='receipt_transport_observations';predicate:='a.http_request_id=split_part($2,'':'',1)::bigint and a.revision=split_part($2,'':'',2)::bigint';present:='a.response_rows_observed is not null';
 else raise exception 'receipt_worker_history_family_invalid'using errcode='22023';end case;
 return format('select to_jsonb(a)original,%s present,to_jsonb(b)binding,to_jsonb(c)certificate,o.payload bytes from collect_ops.%I a left join collect_receipt_worker_history.bindings b on b.family=$1 and b.original_key=$2 left join collect_receipt_worker_history.relocations c on c.family=b.family and c.original_key=b.original_key left join collect_receipt_worker_history.objects o on o.sha256=c.object_sha256 where %s',present,tab,predicate);
end$$;
create function collect_receipt_worker_history.read_logical(p_family text,p_key text)returns jsonb
language plpgsql volatile security definer set search_path=''set TimeZone='UTC'as $$
declare r record;value jsonb;metadata jsonb;payload jsonb;bytes bytea;begin
 -- One snapshot captures anchor, binding, certificate and object. Decoding uses
 -- those captured immutable values only, so a concurrent commit cannot mix tiers.
 execute collect_receipt_worker_history.query(p_family)into r using p_family,p_key;
 if r.original is null then return null;end if;
 metadata:=r.original-collect_receipt_worker_history.fields(p_family);
 if r.certificate is null then
  if not r.present then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  payload:=collect_receipt_worker_history.payload(p_family,r.original);bytes:=convert_to(payload::text,'UTF8');value:=r.original;
 else
  if r.present or r.binding is null or r.bytes is null or r.certificate->>'object_sha256'is distinct from r.binding->>'payload_sha256'then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  if p_family='transport_observation'then
   if exists(select 1 from jsonb_each(collect_receipt_worker_history.payload(p_family,r.original))x where x.value<>'null'::jsonb)then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  end if;
  bytes:=r.bytes;
  begin payload:=convert_from(bytes,'UTF8')::jsonb;exception when others then raise exception 'receipt_worker_history_integrity'using errcode='55000';end;
  if convert_to(payload::text,'UTF8')<>bytes then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  value:=collect_receipt_worker_history.reconstruct(p_family,metadata,payload);
 end if;
 if r.binding is not null and(r.binding->>'codec_version'<>'1'or(r.binding->>'payload_bytes')::bigint<>octet_length(bytes)
  or r.binding->>'payload_sha256'<>encode(extensions.digest(bytes,'sha256'),'hex')
  or r.binding->>'metadata_sha256'<>collect_receipt_worker_history.sha(metadata)
  or r.binding->>'logical_sha256'<>collect_receipt_worker_history.sha(value))then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 return value;end$$;
create function collect_receipt_worker_history.read_payload(p_family text,p_key text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare r jsonb;begin
 r:=collect_receipt_worker_history.read_logical(p_family,p_key);
 if r is null then raise exception 'receipt_worker_history_original_unavailable'using errcode='55000';end if;
 return collect_receipt_worker_history.payload(p_family,r);end$$;
create function collect_receipt_worker_history.read_transport_observation(p_http bigint,p_revision bigint)
returns setof collect_ops.receipt_transport_observations
language plpgsql volatile security definer set search_path=''as $$declare r jsonb;begin
 if p_http is null or p_revision is null then return;end if;
 r:=collect_receipt_worker_history.read_logical('transport_observation',p_http::text||':'||p_revision::text);
 if r is null then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 return next jsonb_populate_record(null::collect_ops.receipt_transport_observations,r);end$$;
create function collect_receipt_worker_history.bind(p_family text,p_key text,p_row jsonb)returns void
language plpgsql security definer set search_path=''set TimeZone='UTC'as $$
declare p jsonb;b collect_receipt_worker_history.bindings;bytes bytea;begin
 p:=collect_receipt_worker_history.payload(p_family,p_row);bytes:=convert_to(p::text,'UTF8');
 select * into b from collect_receipt_worker_history.bindings where family=p_family and original_key=p_key;
 if b.family is not null then
  if b.payload_sha256<>encode(extensions.digest(bytes,'sha256'),'hex')or b.payload_bytes<>octet_length(bytes)
   or b.metadata_sha256<>collect_receipt_worker_history.sha(p_row-collect_receipt_worker_history.fields(p_family))
   or b.logical_sha256<>collect_receipt_worker_history.sha(p_row)then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;return;end if;
 insert into collect_receipt_worker_history.bindings values(p_family,p_key,1,encode(extensions.digest(bytes,'sha256'),'hex'),octet_length(bytes),
  collect_receipt_worker_history.sha(p_row-collect_receipt_worker_history.fields(p_family)),collect_receipt_worker_history.sha(p_row),clock_timestamp());
end$$;
create function collect_receipt_worker_history.capture()returns trigger
language plpgsql security definer set search_path=''set TimeZone='UTC'as $$declare f text:=tg_argv[0];k text;begin
 case f when 'worker_configuration'then
  if new.configuration is null then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;k:=new.revision::text;
 when 'transport_observation'then
  if new.response_rows_observed is null then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;k:=new.http_request_id::text||':'||new.revision::text;
 else
  if new.result is null then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;k:=new.request_id::text;end case;
 perform collect_receipt_worker_history.bind(f,k,to_jsonb(new));return null;end$$;
create function collect_receipt_worker_history.protect_payload()returns trigger
language plpgsql security definer set search_path=''set TimeZone='UTC'as $$
declare f text:=tg_argv[0];k text;b collect_receipt_worker_history.bindings;c collect_receipt_worker_history.relocations;o collect_receipt_worker_history.objects;
 before_present boolean;after_absent boolean;before_row jsonb;after_row jsonb;begin
 if tg_op<>'UPDATE'then raise exception 'operational_exception_evidence_immutable'using errcode='55000';end if;
 before_row:=to_jsonb(old);after_row:=to_jsonb(new);
 case f when 'worker_configuration'then k:=old.revision::text;before_present:=old.configuration is not null;after_absent:=new.configuration is null;
 when 'transport_observation'then k:=old.http_request_id::text||':'||old.revision::text;before_present:=old.response_rows_observed is not null;
  after_absent:=new.response_rows_observed is null and new.http_status is null and new.worker_error_code is null and new.response_at is null;
 else k:=old.request_id::text;before_present:=old.result is not null;after_absent:=new.result is null;end case;
 select * into b from collect_receipt_worker_history.bindings where family=f and original_key=k;
 select * into c from collect_receipt_worker_history.relocations where family=f and original_key=k;
 select * into o from collect_receipt_worker_history.objects where sha256=c.object_sha256;
 if not before_present or not after_absent or b.family is null or c.family is null or o.sha256 is null
  or before_row-collect_receipt_worker_history.fields(f)is distinct from after_row-collect_receipt_worker_history.fields(f)
  or b.metadata_sha256<>collect_receipt_worker_history.sha(before_row-collect_receipt_worker_history.fields(f))
  or b.logical_sha256<>collect_receipt_worker_history.sha(before_row)
  or b.payload_sha256<>c.object_sha256 or b.payload_bytes<>octet_length(o.payload)
  or o.payload<>convert_to(collect_receipt_worker_history.payload(f,before_row)::text,'UTF8')
  or b.logical_sha256<>collect_receipt_worker_history.sha(collect_receipt_worker_history.reconstruct(f,after_row-collect_receipt_worker_history.fields(f),convert_from(o.payload,'UTF8')::jsonb))
 then raise exception 'operational_exception_evidence_immutable'using errcode='55000';end if;
 return new;end$$;
-- Fast catalog conversion, no full historical row rewrite. Existing originals
-- remain hot; lazy binding is performed under exact anchor NOWAIT locks.
alter table collect_ops.receipt_worker_configuration_history alter column configuration drop not null;
alter table collect_ops.receipt_worker_receipts alter column result drop not null;
alter table collect_ops.receipt_exception_scans alter column result drop not null;
alter table collect_ops.receipt_transport_requests alter column result drop not null;
alter table collect_ops.receipt_transport_observations alter column response_rows_observed drop not null;
do $$declare p record;begin
 for p in select * from(values
 ('worker_configuration','receipt_worker_configuration_history','retain_worker_evidence'),
 ('worker_receipt','receipt_worker_receipts','retain_worker_evidence'),
 ('scan_receipt','receipt_exception_scans','retain_receipt_exception_scan'),
 ('transport_receipt','receipt_transport_requests','retain_transport_evidence'),
 ('transport_observation','receipt_transport_observations','retain_transport_evidence'))v(family,tab,old_trigger)loop
  execute format('drop trigger %I on collect_ops.%I',p.old_trigger,p.tab);
  execute format('create trigger retained_history_payload before update or delete on collect_ops.%I for each row execute function collect_receipt_worker_history.protect_payload(%L)',p.tab,p.family);
  execute format('create trigger retained_history_payload_truncate before truncate on collect_ops.%I for each statement execute function collect_receipt_worker_history.immutable()',p.tab);
  execute format('create trigger captured_history_payload after insert on collect_ops.%I for each row execute function collect_receipt_worker_history.capture(%L)',p.tab,p.family);
 end loop;end$$;
create index receipt_exception_processed_scan on collect_ops.receipt_exception_work(processed_request_id,id)where processed_at is not null;
create index receipt_worker_configuration_jobs on collect_ops.receipt_worker_jobs(configuration_revision,request_id);
create index receipt_history_hot_configuration on collect_ops.receipt_worker_configuration_history((revision::text))where configuration is not null;
create index receipt_history_hot_worker on collect_ops.receipt_worker_receipts((request_id::text))where result is not null;
create index receipt_history_hot_scan on collect_ops.receipt_exception_scans((request_id::text))where result is not null;
create index receipt_history_hot_transport_request on collect_ops.receipt_transport_requests((request_id::text))where result is not null;
create index receipt_history_hot_transport_observation on collect_ops.receipt_transport_observations((http_request_id::text||':'||revision::text))where response_rows_observed is not null;

-- Full metadata key indexes serve both-tier recovery without scanning payloads.
create index receipt_history_all_configuration on collect_ops.receipt_worker_configuration_history((revision::text));
create index receipt_history_all_worker on collect_ops.receipt_worker_receipts((request_id::text));
create index receipt_history_all_scan on collect_ops.receipt_exception_scans((request_id::text));
create index receipt_history_all_transport_request on collect_ops.receipt_transport_requests((request_id::text));
create index receipt_history_all_transport_observation on collect_ops.receipt_transport_observations((http_request_id::text||':'||revision::text));

create function collect_receipt_worker_history.source_proof(p_kind text,p_source uuid,p_scan uuid,p_work uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare e collect_hybrid.receipt_business_events;n collect_hybrid.receipt_business_events;
 h collect_receipt_operations.handled_events;b collect_receipt_operations.backlog_results;
 s collect_hybrid.momo_balance_snapshots;payment public.payments;root collect_hybrid.sms_notification_outbox;
 live collect_receipt_source_projection.live;w collect_ops.receipt_exception_work;
 original_kind text;terminal_code text;receipt uuid;parsed uuid;raw uuid;collection uuid;
 proof_kind text;source_digest text;terminal_digest text;graph_digest text;evidence_digest text;certificate uuid;
 roots uuid[]:='{}';attempts uuid[]:='{}';telemetry uuid[]:='{}';exceptions uuid[]:='{}';
 graph jsonb:='[]';facts jsonb;closures jsonb:='[]';point record;head record;count_value bigint;at timestamptz;
 last_alert uuid;next_alert uuid;seek_count integer;
begin
 if current_setting('transaction_isolation')<>'read committed'then return null;end if;
 -- Private helper is permitted only inside the original, not-yet-published
 -- scan transaction, after its exact original work transition.
 select * into w from collect_ops.receipt_exception_work where id=p_work;
 if w.source_kind is distinct from p_kind or w.source_id is distinct from p_source or w.outcome is distinct from 'refreshed'
  or w.processed_request_id is distinct from p_scan then return null;end if;
 begin
  if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-source-admission:'||p_kind||':'||p_source::text,0))
   or not pg_try_advisory_xact_lock(hashtext('collect-receipt-telemetry-sampler'))then raise exception 'receipt_source_held'using errcode='P0002';end if;
  select * into live from collect_receipt_source_projection.live where source_kind=p_kind and source_id=p_source for update nowait;
  if live.admission_id is not null or exists(select 1 from collect_ops.receipt_exception_work pending where pending.source_kind=p_kind and pending.source_id=p_source and pending.processed_at is null)then raise exception 'receipt_source_held'using errcode='P0002';end if;
  if p_kind='receipt_event'then
   select * into e from collect_hybrid.receipt_business_events where id=p_source;
   select * into h from collect_receipt_operations.handled_events where event_id=p_source;
   if e.id is null or e.collection_id is null then raise exception 'receipt_source_held'using errcode='P0002';end if;
   collection:=e.collection_id;receipt:=h.receipt_id;terminal_code:=h.code;
   if h.event_id is not null then
    if h.source_version is distinct from e.source_version then raise exception 'receipt_source_held'using errcode='P0002';end if;
    proof_kind:='handled_event';terminal_digest:=encode(extensions.digest(to_jsonb(h)::text,'sha256'),'hex');
   else proof_kind:='immutable_supersession';terminal_code:='SOURCE_SUPERSEDED';end if;
   if terminal_code='SOURCE_SUPERSEDED'then
    select * into n from collect_hybrid.receipt_business_events x where x.source_kind=e.source_kind and x.source_id=e.source_id
     and x.source_version>e.source_version and x.collection_id=e.collection_id order by x.source_version,x.id limit 1;
    if n.id is null or not(exists(select 1 from collect_receipt_source_projection.live l where l.source_kind='receipt_event'and l.source_id=n.id)
     or exists(select 1 from collect_ops.receipt_exception_work x where x.source_kind='receipt_event'and x.source_id=n.id and x.processed_at is null)
     or exists(select 1 from collect_receipt_operations.handled_events x where x.event_id=n.id and x.source_version=n.source_version)
     or exists(select 1 from collect_receipt_source_projection.certificates x where x.source_kind='receipt_event'and x.source_id=n.id))then raise exception 'receipt_source_held'using errcode='P0002';end if;
    if proof_kind='immutable_supersession'then terminal_digest:=encode(extensions.digest(to_jsonb(n)::text,'sha256'),'hex');end if;
   end if;
   source_digest:=encode(extensions.digest(to_jsonb(e)::text,'sha256'),'hex');
   if e.source_kind='payment'then select * into payment from public.payments where id=e.source_id for update nowait;
   elsif e.source_kind='receipt'then
    select * into root from collect_hybrid.sms_notification_outbox where id=e.source_id for update nowait;
    select * into payment from public.payments where id=root.payment_id for update nowait;
   else
    select count(*)into count_value from(select p.id from public.payments p where p.parsed_event_id=e.source_id limit 2)bounded;
    if count_value<>1 then raise exception 'receipt_source_held'using errcode='P0002';end if;
    select * into payment from public.payments p where p.parsed_event_id=e.source_id for update nowait;
   end if;
   if e.payment_id is not null and e.payment_id is distinct from payment.id then raise exception 'receipt_source_held'using errcode='P0002';end if;
  elsif p_kind='receipt_backlog'then
   select * into s from collect_hybrid.momo_balance_snapshots where id=p_source and event_type='receipt';
   select * into b from collect_receipt_operations.backlog_results x where x.snapshot_id=p_source and x.business_handled order by x.recorded_at,x.run_id limit 1;
   if s.id is null or b.snapshot_id is null or b.code not in('RECEIPT_ENQUEUED','RECEIPT_EXISTS','PAYMENT_REVERSED','SOURCE_SUPERSEDED')
    or b.code='SOURCE_SUPERSEDED'then raise exception 'receipt_source_held'using errcode='P0002';end if;
   select * into payment from public.payments where id=s.payment_id for update nowait;
   collection:=s.collection_id;receipt:=b.receipt_id;terminal_code:=b.code;proof_kind:='handled_backlog';
   source_digest:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex');terminal_digest:=encode(extensions.digest(to_jsonb(b)::text,'sha256'),'hex');
  else raise exception 'receipt_source_held'using errcode='P0002';end if;
  if payment.id is null or payment.collection_id is distinct from collection or not collect_ops.payment_scope(payment.id)
   or terminal_code not in('RECEIPT_ENQUEUED','RECEIPT_EXISTS','PAYMENT_REVERSED','SOURCE_SUPERSEDED')then raise exception 'receipt_source_held'using errcode='P0002';end if;
  parsed:=payment.parsed_event_id;
  if parsed is not null then
   perform 1 from public.parsed_payment_events where id=parsed for share nowait;
   select raw_sms_id into raw from public.parsed_payment_events where id=parsed;
   if raw is null then raise exception 'receipt_source_held'using errcode='P0002';end if;
   perform 1 from public.raw_payment_sms where id=raw for share nowait;
  end if;
  graph:=jsonb_build_array(jsonb_build_object('kind',p_kind,'id',p_source),jsonb_build_object('kind','payment','id',payment.id));
  if parsed is not null then graph:=graph||jsonb_build_array(jsonb_build_object('kind','allocation','id',parsed),jsonb_build_object('kind','raw_sms','id',raw));end if;
  -- Payment FOR UPDATE also fences FK admission of a new original root.
  -- Each existing root is the exact shared grant/arm/callback/400 fence.
  select count(*)into count_value from(select o.id from collect_hybrid.sms_notification_outbox o where o.payment_id=payment.id limit 9)bounded;
  if count_value>8 then raise exception 'receipt_source_held'using errcode='P0002';end if;
  for root in select * from collect_hybrid.sms_notification_outbox o where o.payment_id=payment.id order by o.id for update nowait loop
   roots:=array_append(roots,root.id);graph:=graph||jsonb_build_array(jsonb_build_object('kind','receipt','id',root.id));
   if exists(select 1 from collect_receipt_successors.approvals a where a.root_outbox_id=root.id)
    or exists(select 1 from collect_receipt_successors.jobs j where j.root_outbox_id=root.id)
    or root.collection_id is distinct from collection or root.state in('awaiting_confirmation','send_started','uncertain')
    or exists(select 1 from collect_security.assisted_sms_session_evidence x where x.outbox_id=root.id)
    or exists(select 1 from collect_hybrid.sms_notification_claim_requests x where x.outbox_id=root.id)
    or exists(select 1 from collect_hybrid.sms_notification_confirmations x where x.outbox_id=root.id)
    or exists(select 1 from collect_hybrid.sms_notification_attempts x where x.outbox_id=root.id)then raise exception 'receipt_source_held'using errcode='P0002';end if;
   for point in select a.* from collect_gateway_dispatch.attempts a where a.outbox_id=root.id loop
    attempts:=array_append(attempts,point.id);graph:=graph||jsonb_build_array(jsonb_build_object('kind','gateway','id',point.device_id));
    if cardinality(attempts)>8 or point.state<>'granted'
     or exists(select 1 from collect_gateway_dispatch.arms x where x.attempt_id=point.id)
     or exists(select 1 from collect_gateway_dispatch.callbacks x where x.attempt_id=point.id)
     or not exists(select 1 from collect_receipt_successors.original_closures x where x.root_outbox_id=root.id
      and x.original_attempt_id=point.id and x.reason_code='definitely_not_invoked')then raise exception 'receipt_source_held'using errcode='P0002';end if;
   end loop;
   closures:=closures||coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'sha256',encode(extensions.digest(to_jsonb(x)::text,'sha256'),'hex'))order by x.id)
    from collect_receipt_successors.original_closures x where x.root_outbox_id=root.id),'[]'::jsonb);
  end loop;
  if terminal_code in('RECEIPT_ENQUEUED','RECEIPT_EXISTS')then
   select * into root from collect_hybrid.sms_notification_outbox where id=receipt;
   select * into s from collect_hybrid.momo_balance_snapshots where id=root.snapshot_id;
   if root.id is null or not root.id=any(roots)or s.id is null or s.event_type<>'receipt'
    or root.payment_id is distinct from payment.id or s.payment_id is distinct from payment.id
    or root.collection_id is distinct from collection or s.collection_id is distinct from collection
    or root.member_record_id is distinct from s.member_record_id or root.amount_rwf is distinct from s.delta_rwf
    or root.member_balance_rwf is distinct from s.member_balance_after_rwf or root.group_balance_rwf is distinct from s.group_balance_after_rwf
    or(p_kind='receipt_backlog'and root.snapshot_id is distinct from p_source)
    or(e.snapshot_id is not null and e.snapshot_id is distinct from root.snapshot_id)
    or not collect_receipt_policy.content_is_valid(root)then raise exception 'receipt_source_held'using errcode='P0002';end if;
  elsif terminal_code='PAYMENT_REVERSED'and not exists(select 1 from collect_hybrid.momo_journal_entries j
   where j.payment_id=payment.id and j.entry_type='reversal')then raise exception 'receipt_source_held'using errcode='P0002';end if;
  -- The sampler lock fences new and moved telemetry heads, including history
  -- still referenced by unfinished workflows and escalation/inbox journals.
  -- At most10 source-local keys, each with at most33 alert-ID index seeks.
  -- Seeking beyond the prior alert_id skips arbitrary numeric-history repeats
  -- without DISTINCT/aggregation over that immutable lifetime journal.
  for point in select 'business_event'kind,p_source id where p_kind='receipt_event'
   union all select 'handled_event',p_source where p_kind='receipt_event'
   union all select 'attempt',a from unnest(attempts)a loop
   for next_alert in select a.id from collect_receipt_telemetry.alert_heads a
    where a.source_kind=point.kind and a.source_id=point.id order by a.id limit 33 loop
    if not next_alert=any(telemetry)then telemetry:=array_append(telemetry,next_alert);end if;
    if cardinality(telemetry)>32 then raise exception 'receipt_source_held'using errcode='P0002';end if;
   end loop;
   last_alert:=null;seek_count:=0;
   loop
    select a.alert_id into next_alert from collect_receipt_telemetry.alert_observations a
     where a.source_kind=point.kind and a.source_id=point.id
      and a.alert_id>=coalesce(last_alert,'00000000-0000-0000-0000-000000000000'::uuid)
      and(last_alert is null or a.alert_id>last_alert)order by a.alert_id limit 1;
    exit when next_alert is null;
    seek_count:=seek_count+1;
    if seek_count>33 then raise exception 'receipt_source_held'using errcode='P0002';end if;
    if not next_alert=any(telemetry)then telemetry:=array_append(telemetry,next_alert);end if;
    if cardinality(telemetry)>32 then raise exception 'receipt_source_held'using errcode='P0002';end if;
    last_alert:=next_alert;
   end loop;
  end loop;
  foreach certificate in array telemetry loop graph:=graph||jsonb_build_array(jsonb_build_object('kind','receipt_telemetry','id',certificate));end loop;
  -- Every observer takes this exact advisory source fence before admission of
  -- a new exception head. Locking existing heads alone would miss phantoms.
  for point in select distinct x->>'kind'kind,(x->>'id')::uuid id from jsonb_array_elements(graph)x order by 1,2 loop
   if not pg_try_advisory_xact_lock(hashtextextended('collect-ops-source:'||point.kind||':'||point.id::text,0))then raise exception 'receipt_source_held'using errcode='P0002';end if;
  end loop;
  for point in select distinct x->>'kind'kind,(x->>'id')::uuid id from jsonb_array_elements(graph)x order by 1,2 loop
   for head in select x.id from collect_ops.exceptions x where x.source_kind=point.kind and x.source_id=point.id order by x.reason_code limit 33 loop
    exceptions:=array_append(exceptions,head.id);
    if cardinality(exceptions)>32 then raise exception 'receipt_source_held'using errcode='P0002';end if;
   end loop;
  end loop;
  if exists(select 1 from collect_ops.exceptions x left join collect_ops.exception_workflows f on f.exception_id=x.id
   where x.id=any(exceptions)and(x.active or(f.exception_id is not null and f.resolved_source_revision is distinct from x.revision)))
   or exists(select 1 from collect_ops.exception_escalations x where x.exception_id=any(exceptions)and x.state in('queued','recipient_unavailable'))
   or exists(select 1 from collect_receipt_source_projection.unread_inbox x where x.exception_id=any(exceptions))
   or exists(select 1 from collect_ops.receipt_exception_work x where x.source_kind=p_kind and x.source_id=p_source and x.processed_at is null)
  then raise exception 'receipt_source_held'using errcode='P0002';end if;
  select coalesce(jsonb_agg(jsonb_build_array(x.id,x.revision,x.active,x.source_sha256)order by x.id),'[]')into facts
   from collect_ops.exceptions x where x.id=any(exceptions);
  graph_digest:=encode(extensions.digest(jsonb_build_object('graph',graph,'heads',facts,'roots',roots,'attempts',attempts,'closures',closures,
   'superseding_event',case when n.id is null then null else to_jsonb(n)end)::text,'sha256'),'hex');
  return jsonb_build_object('source_kind',p_kind,'source_id',p_source,'work_id',p_work,'scan_request_id',p_scan,
   'proof_kind',proof_kind,'terminal_code',terminal_code,'source_sha256',source_digest,'terminal_sha256',terminal_digest,
   'graph_sha256',graph_digest,'heads',facts,'closures',closures,'checked_at',collect_ops.utc(clock_timestamp()),
   'financial_action',false,'send_action',false,'source_scan_complete',false);
 exception when no_data_found or lock_not_available or invalid_parameter_value or insufficient_privilege then return null;end;
end$$;
create or replace function public.process_receipt_deferral_exceptions_v1(p_request_id uuid,p_limit integer,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare prior collect_ops.receipt_exception_scans;p collect_ops.receipt_exception_progress;
 w collect_ops.receipt_exception_work;source uuid;before_heads jsonb;t timestamptz;result jsonb;
 seeded integer:=0;processed integer:=0;refused integer:=0;added integer:=0;activated integer:=0;cleared integer:=0;unchanged integer:=0;
 changed integer;act integer;closed integer;status text;work_outcome text;begin
 perform collect_ops.receipt_exception_service();
 if p_request_id is null or p_limit is null or p_limit not between 1 and 25 or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at>clock_timestamp()+interval '120 seconds'then raise exception 'receipt_exception_scan_invalid'using errcode='22023';end if;
 if p_expires_at<=clock_timestamp()then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-exception-scan:'||p_request_id::text,0));
 select * into prior from collect_ops.receipt_exception_scans where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.request_limit<>p_limit or prior.expires_at<>p_expires_at then raise exception 'receipt_exception_scan_conflict'using errcode='22023';end if;return collect_receipt_worker_history.read_payload('scan_receipt',prior.request_id::text);end if;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-exception-worker'))then status:='busy';
 else
  -- Existing assignment/escalation takes this lock before any source lock.
  perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
  if p_expires_at<=clock_timestamp()then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
  select * into p from collect_ops.receipt_exception_progress where singleton for update;
  -- This is a bounded, repeating source-local UUID sweep, never a commit-order
  -- watermark or a claim that all sources have been observed. New transitions
  -- also append independent work, including UUIDs behind the sweep cursor.
  if p.phase='receipt_event'then
   for source in select l.source_id from collect_receipt_source_projection.live l
    where l.source_kind='receipt_event'and l.source_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or l.source_id>p.last_id)order by l.source_id limit p_limit loop
    insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_event',source,'sweep');seeded:=seeded+1;p.last_id:=source;
   end loop;
   if seeded=0 then p.phase:='receipt_backlog';p.last_id:=null;end if;
  else
   for source in select l.source_id from collect_receipt_source_projection.live l
    where l.source_kind='receipt_backlog'and l.source_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or l.source_id>p.last_id)order by l.source_id limit p_limit loop
    insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_backlog',source,'sweep');seeded:=seeded+1;p.last_id:=source;
   end loop;
   if seeded=0 then
    if p.epoch=1000000000 then raise exception 'receipt_exception_epoch_exhausted'using errcode='55000';end if;
    p.phase:='receipt_event';p.last_id:=null;p.epoch:=p.epoch+1;
   end if;
  end if;
  for w in select * from collect_ops.receipt_exception_work where processed_at is null order by queued_at,id limit p_limit for update skip locked loop
   -- Pending work is independent of the sweep cursor and re-establishes exact
   -- membership after any producer/retirement fast-path race. A contended
   -- publication leaves this original row pending for a later bounded scan.
   if not collect_receipt_source_projection.ensure_work_membership(w.id)then continue;end if;
   work_outcome:='refreshed';begin
    perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||w.source_kind||':'||w.source_id::text,0));
    select coalesce(jsonb_object_agg(e.id::text,e.revision),'{}'::jsonb)into before_heads from collect_ops.exceptions e where e.source_kind=w.source_kind and e.source_id=w.source_id;
    perform collect_ops.refresh_source(w.source_kind,w.source_id);
    select count(*),count(*)filter(where o.active),count(*)filter(where not o.active)into changed,act,closed
     from collect_ops.exception_observations o join collect_ops.exceptions e on e.id=o.exception_id
     where e.source_kind=w.source_kind and e.source_id=w.source_id and o.revision>coalesce((before_heads->>e.id::text)::bigint,0);
    insert into collect_ops.receipt_exception_scan_observations(request_id,exception_id,revision)
     select p_request_id,o.exception_id,o.revision from collect_ops.exception_observations o join collect_ops.exceptions e on e.id=o.exception_id
      where e.source_kind=w.source_kind and e.source_id=w.source_id and o.revision>coalesce((before_heads->>e.id::text)::bigint,0);
    added:=added+changed;activated:=activated+act;cleared:=cleared+closed;if changed=0 then unchanged:=unchanged+1;end if;
   exception when insufficient_privilege then
    -- An unavailable or scope-refused source cannot create/clear evidence.
    -- Retain the failed refresh attempt and count it without starving other
    -- work or interpreting refusal as business/delivery acknowledgement.
    refused:=refused+1;work_outcome:='scope_refused';
   when invalid_parameter_value then refused:=refused+1;work_outcome:='source_unavailable';
   end;
   if p_expires_at<=clock_timestamp()then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
   update collect_ops.receipt_exception_work set processed_at=clock_timestamp(),outcome=work_outcome,processed_request_id=p_request_id where id=w.id;processed:=processed+1;
   if work_outcome='refreshed'then
    perform collect_receipt_source_projection.try_retire_source(w.source_kind,w.source_id,p_request_id,w.id);
   end if;
  end loop;
  update collect_ops.receipt_exception_progress set epoch=p.epoch,phase=p.phase,last_id=p.last_id,last_scan_at=clock_timestamp(),last_request_id=p_request_id where singleton;
  status:='processed';
 end if;
 t:=clock_timestamp();if p_expires_at<=t then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
 select * into p from collect_ops.receipt_exception_progress where singleton;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'expires_at',collect_ops.utc(p_expires_at),
  'status',status,'seeded',seeded,'processed',processed,'refused',refused,'observations_added',added,'activated',activated,'cleared',cleared,'unchanged',unchanged,
  'pending',(select count(*)from collect_ops.receipt_exception_work where processed_at is null),'scan_epoch',p.epoch,'scan_phase',p.phase,
  'source_scan_complete',false,'financial_action',false,'send_action',false);
 insert into collect_ops.receipt_exception_scans values(p_request_id,p_limit,p_expires_at,t,result);return result;end$$;
create or replace function public.get_receipt_deferral_exception_scan_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare prior collect_ops.receipt_exception_scans;acquired boolean;t timestamptz;begin
 perform collect_ops.receipt_exception_service();if p_request_id is null then raise exception 'receipt_exception_scan_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-exception-scan:'||p_request_id::text,0));
 select * into prior from collect_ops.receipt_exception_scans where acquired and request_id=p_request_id;
 t:=clock_timestamp();return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),
  'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),'status',case when not acquired then 'in_progress'when prior.request_id is null then 'not_recorded'else 'recorded'end,
  'expires_at',case when prior.request_id is null then null else collect_ops.utc(prior.expires_at)end,'receipt',case when prior.request_id is null then null else collect_receipt_worker_history.read_payload('scan_receipt',prior.request_id::text)end);end$$;
create or replace function public.execute_receipt_exception_worker_v1(p_request_id uuid,p_configuration_revision bigint,p_expires_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;prior collect_ops.receipt_worker_receipts;
 scan jsonb;escalation jsonb;result jsonb;t timestamptz;begin
 perform collect_ops.receipt_exception_service();
 if p_request_id is null or p_configuration_revision is null or p_configuration_revision<1 or p_expires_at is null or not isfinite(p_expires_at)
  then raise exception 'receipt_worker_request_invalid'using errcode='22023';end if;
 -- Lock order is global authority, then original job, then scanner/workflow.
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'))then
  return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','in_progress','receipt',null);end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
 if j.request_id is null then raise exception 'receipt_worker_job_unavailable'using errcode='42501';end if;
 if j.configuration_revision<>p_configuration_revision or j.expires_at<>p_expires_at then
  raise exception 'receipt_worker_original_conflict'using errcode='22023';end if;
 select * into prior from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 if prior.request_id is not null then return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','recorded','receipt',collect_receipt_worker_history.read_payload('worker_receipt',prior.request_id::text));end if;
 select * into c from collect_ops.receipt_worker_configuration where singleton for share;
 if not c.enabled or c.revision<>j.configuration_revision then raise exception 'receipt_worker_authority_lost'using errcode='42501';end if;
 if j.expires_at<=clock_timestamp()or exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)
  then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 -- The escalation pump takes roster before workflow. Acquire both before
 -- the scanner so the combined transaction preserves that same lock order.
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 if j.expires_at<=clock_timestamp()then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 scan:=public.process_receipt_deferral_exceptions_v1(j.request_id,j.scan_limit,j.expires_at);
 if scan->>'status'='processed'then escalation:=public.process_exception_escalations_v1(j.escalation_limit);
 else escalation:=jsonb_build_object('contract_version',1,'channel','admin_inbox','delivered',0,'obsolete',0,'recipient_unavailable',0,'external_send',false);end if;
 t:=clock_timestamp();if j.expires_at<=t then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 -- Scan, source observations, inbox delivery and this receipt commit together.
 result:=jsonb_build_object('contract_version',1,'request_id',j.request_id,'configuration_revision',j.configuration_revision,
  'recorded_at',collect_ops.utc(t),'expires_at',collect_ops.utc(j.expires_at),'status',case when scan->>'status'='busy'then 'busy'else 'completed'end,
  'scan',scan,'escalation',escalation,'financial_action',false,'send_action',false,'external_send',false);
 insert into collect_ops.receipt_worker_receipts values(j.request_id,t,result,j.request_id);
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','recorded','receipt',result);
end$$;
create or replace function public.get_receipt_exception_worker_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare j collect_ops.receipt_worker_jobs;r collect_ops.receipt_worker_receipts;acquired boolean;t timestamptz;begin
 perform collect_ops.receipt_exception_service();if p_request_id is null then raise exception 'receipt_worker_request_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 if acquired then
  select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
  select * into r from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 end if;
 t:=clock_timestamp();return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),
  'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),'status',case when not acquired then 'in_progress'when r.request_id is not null then 'recorded'else 'not_recorded'end,
  'expires_at',case when j.request_id is null then null else collect_ops.utc(j.expires_at)end,'receipt',case when r.request_id is null then null else collect_receipt_worker_history.read_payload('worker_receipt',r.request_id::text)end);
end$$;
create or replace function public.admin_get_receipt_exception_worker_health_v1()returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;r collect_ops.receipt_worker_receipts;
 t timestamptz;state text;alerts jsonb:='[]'::jsonb;pending bigint;refused integer;transport_ready boolean:=false;
 day_count integer;scan_reserved integer;escalation_reserved integer;begin
 perform collect_ops.actor(false);t:=clock_timestamp();select * into c from collect_ops.receipt_worker_configuration where singleton;
 select * into j from collect_ops.receipt_worker_jobs order by created_at desc,request_id desc limit 1;
 select * into r from collect_ops.receipt_worker_receipts order by recorded_at desc,request_id desc limit 1;
 state:=case when not c.enabled then 'inactive'when j.request_id is null then 'unobserved'
  when exists(select 1 from collect_ops.receipt_worker_receipts where request_id=j.request_id)then 'observed'
  when exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)then 'expired_without_receipt'
  when j.expires_at<=t then 'unknown'else 'pending'end;
 select count(*)into pending from collect_ops.receipt_exception_work where processed_at is null;
 select count(*),coalesce(sum(scan_limit),0),coalesce(sum(escalation_limit),0)into day_count,scan_reserved,escalation_reserved
  from collect_ops.receipt_worker_jobs where reserved_day=(t at time zone 'UTC')::date;
 begin perform collect_ops.receipt_worker_transport();transport_ready:=true;
 exception when object_not_in_prerequisite_state then transport_ready:=false;end;
 if r.request_id is not null then r.result:=collect_receipt_worker_history.read_payload('worker_receipt',r.request_id::text);end if;
 refused:=coalesce((r.result->'scan'->>'refused')::integer,0);
 if c.enabled and(r.recorded_at is null or r.recorded_at<t-interval '180 seconds')then alerts:=alerts||jsonb_build_array('WORKER_STALE');end if;
 if state='unknown'then alerts:=alerts||jsonb_build_array('ORIGINAL_OUTCOME_UNKNOWN');end if;
 if state='expired_without_receipt'then alerts:=alerts||jsonb_build_array('ORIGINAL_EXPIRED_UNHANDLED');end if;
 if pending>c.scan_limit*10 then alerts:=alerts||jsonb_build_array('DEFERRAL_BACKLOG');end if;
 if refused>0 then alerts:=alerts||jsonb_build_array('SOURCE_REFUSALS');end if;
 if c.enabled and not transport_ready then alerts:=alerts||jsonb_build_array('TRANSPORT_UNCONFIGURED');end if;
 if c.enabled and(day_count>=c.day_jobs or scan_reserved+c.scan_limit>c.day_scan_sources or escalation_reserved+c.escalation_limit>c.day_escalations)
  then alerts:=alerts||jsonb_build_array('WORKER_QUOTA_EXHAUSTED');end if;
 return jsonb_build_object('contract_version',1,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'configuration_revision',c.revision,'enabled',c.enabled,'state',state,'last_request_id',j.request_id,'last_created_at',collect_ops.utc(j.created_at),
  'last_expires_at',collect_ops.utc(j.expires_at),'last_recorded_at',collect_ops.utc(r.recorded_at),'last_outcome',r.result->'status',
  'pending_sources',pending,'alerts',alerts,'transport_configured',transport_ready,
  'day_jobs_reserved',day_count,'day_scan_sources_reserved',scan_reserved,'day_escalations_reserved',escalation_reserved,
  'day_jobs_cap',c.day_jobs,'day_scan_sources_cap',c.day_scan_sources,'day_escalations_cap',c.day_escalations,
  'source_scan_complete',false,'financial_action',false,'send_action',false,'external_send',false);
end$$;
create or replace function collect_ops.receipt_transport_base_schedule()returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;transport jsonb;t timestamptz;
 prior_count integer;http_id bigint;last_dispatch timestamptz;day_count integer;scan_reserved integer;escalation_reserved integer;state text;begin
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'))then return jsonb_build_object('status','overlap');end if;
 select * into c from collect_ops.receipt_worker_configuration where singleton for share;
 if not c.enabled then return jsonb_build_object('status','inactive');end if;
 transport:=collect_ops.receipt_worker_transport();t:=clock_timestamp();
 select * into j from collect_ops.receipt_worker_jobs order by created_at desc,request_id desc limit 1;
 if j.request_id is not null then
  perform pg_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||j.request_id::text,0));
  if exists(select 1 from collect_ops.receipt_worker_receipts where request_id=j.request_id)then
   perform collect_receipt_worker_history.read_payload('worker_receipt',j.request_id::text);
  else
   if j.expires_at<=t or j.configuration_revision<>c.revision then
    if j.expires_at>t then return jsonb_build_object('status','fenced_pending','request_id',j.request_id);end if;
    -- Fresh exact job lock makes absence conclusive after its immutable deadline.
    insert into collect_ops.receipt_worker_expirations values(j.request_id,t,'expired_without_receipt')on conflict do nothing;
   else
    select count(*),max(dispatched_at)into prior_count,last_dispatch from collect_ops.receipt_worker_dispatches where request_id=j.request_id;
    if prior_count>=3 or last_dispatch>t-interval '30 seconds'then return jsonb_build_object('status','pending','request_id',j.request_id);end if;
    state:='redispatched';
   end if;
  end if;
 end if;
 if state is null then
  if j.created_at>t-interval '60 seconds'then return jsonb_build_object('status','cadence');end if;
  select count(*),coalesce(sum(scan_limit),0),coalesce(sum(escalation_limit),0)into day_count,scan_reserved,escalation_reserved
   from collect_ops.receipt_worker_jobs where reserved_day=(t at time zone 'UTC')::date;
  if day_count>=c.day_jobs or scan_reserved+c.scan_limit>c.day_scan_sources or escalation_reserved+c.escalation_limit>c.day_escalations
   then return jsonb_build_object('status','quota_exhausted');end if;
  insert into collect_ops.receipt_worker_jobs values(gen_random_uuid(),c.revision,c.scan_limit,c.escalation_limit,
   (t at time zone 'UTC')::date,t,t+interval '90 seconds')returning * into j;prior_count:=0;state:='queued';
 end if;
 select net.http_post(url:=transport->>'url',headers:=transport->'headers',body:=jsonb_build_object('contract_version',1,
  'action','execute','request_id',j.request_id,'configuration_revision',j.configuration_revision,'expires_at',collect_ops.utc(j.expires_at)),
  timeout_milliseconds:=15000)into http_id;
 insert into collect_ops.receipt_worker_dispatches values(j.request_id,prior_count+1,http_id,t);
 return jsonb_build_object('status',state,'request_id',j.request_id,'http_request_id',http_id,'attempt',prior_count+1,'expires_at',collect_ops.utc(j.expires_at));
end$$;
create or replace function collect_ops.reconcile_receipt_transport(p_request_id uuid,p_limit integer,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare prior collect_ops.receipt_transport_requests;c collect_ops.receipt_transport_configuration;p collect_ops.receipt_transport_progress;
 d collect_ops.receipt_worker_dispatches;old collect_ops.receipt_transport_observations;sample jsonb;signature text;rev bigint;
 t timestamptz;result jsonb;state text;inspected integer:=0;added integer:=0;terminal integer:=0;unobserved integer:=0;units integer;begin
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_transport_snapshot_retry'using errcode='40001';end if;
 if p_request_id is null or p_limit is null or p_limit not between 1 and 25 or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at>clock_timestamp()+interval '120 seconds'then raise exception 'receipt_transport_request_invalid'using errcode='22023';end if;
 if p_expires_at<=clock_timestamp()then raise exception 'receipt_transport_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-transport-request:'||p_request_id::text,0));
 select * into prior from collect_ops.receipt_transport_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.request_limit<>p_limit or prior.expires_at<>p_expires_at then raise exception 'receipt_transport_original_conflict'using errcode='22023';end if;return collect_receipt_worker_history.read_payload('transport_receipt',prior.request_id::text);end if;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-transport-reconcile'))then state:='busy';
 else
  select * into c from collect_ops.receipt_transport_configuration where singleton for share;
  select * into p from collect_ops.receipt_transport_progress where singleton for update;
  if not collect_ops.receipt_transport_schema_valid()then state:='runtime_unavailable';
  else
   t:=clock_timestamp();select count(*)into units from collect_ops.receipt_transport_inspections where quota_day=(t at time zone 'UTC')::date;
   if units>=c.day_inspections then state:='quota_exhausted';
   else
    for d in select x.* from collect_ops.receipt_worker_dispatches x
     left join collect_ops.receipt_transport_heads h on h.http_request_id=x.http_request_id
     left join collect_ops.receipt_transport_observations o on o.http_request_id=h.http_request_id and o.revision=h.revision
     where o.transport_terminal is distinct from true and(p.last_dispatched_at is null or(x.dispatched_at,x.http_request_id)>(p.last_dispatched_at,p.last_http_request_id))
     order by x.dispatched_at,x.http_request_id limit least(p_limit,c.batch_limit,c.day_inspections-units)loop
     if p_expires_at<=clock_timestamp()then raise exception 'receipt_transport_expired'using errcode='55000';end if;
     sample:=collect_ops.receipt_transport_sample(d.http_request_id,d.request_id);
     signature:=encode(extensions.digest(convert_to(jsonb_build_object('http_request_id',d.http_request_id::text,
      'request_id',d.request_id,'attempt',d.attempt,'dispatched_at',collect_ops.utc(d.dispatched_at),'metadata',sample)::text,'UTF8'),'sha256'),'hex');
     select o.* into old from collect_ops.receipt_transport_heads h join collect_ops.receipt_transport_observations o
      on o.http_request_id=h.http_request_id and o.revision=h.revision where h.http_request_id=d.http_request_id;
     if old.http_request_id is null or old.evidence_sha256<>signature then
      rev:=coalesce(old.revision,0)+1;if rev>1000000000 then raise exception 'receipt_transport_revision_exhausted'using errcode='55000';end if;
      insert into collect_ops.receipt_transport_observations values(d.http_request_id,rev,sample->>'outcome',(sample->>'transport_terminal')::boolean,
       (sample->>'http_status')::integer,sample->>'worker_error_code',(sample->>'response_rows_observed')::integer,
       (sample->>'response_at')::timestamptz,clock_timestamp(),signature,p_request_id);
      insert into collect_ops.receipt_transport_heads values(d.http_request_id,rev)on conflict(http_request_id)do update set revision=excluded.revision;
      insert into collect_ops.receipt_transport_request_observations values(p_request_id,d.http_request_id,rev);added:=added+1;
     end if;
     insert into collect_ops.receipt_transport_inspections values(p_request_id,d.http_request_id,clock_timestamp(),(t at time zone 'UTC')::date);
     inspected:=inspected+1;if(sample->>'transport_terminal')::boolean then terminal:=terminal+1;else unobserved:=unobserved+1;end if;
     p.last_dispatched_at:=d.dispatched_at;p.last_http_request_id:=d.http_request_id;
    end loop;
    if inspected=0 then
     if p.epoch=1000000000 then raise exception 'receipt_transport_epoch_exhausted'using errcode='55000';end if;
     p.last_dispatched_at:=null;p.last_http_request_id:=null;p.epoch:=p.epoch+1;
    end if;
    state:='processed';
   end if;
  end if;
 end if;
 t:=clock_timestamp();if p_expires_at<=t then raise exception 'receipt_transport_expired'using errcode='55000';end if;
 if p.singleton is not null then update collect_ops.receipt_transport_progress set epoch=p.epoch,last_dispatched_at=p.last_dispatched_at,
  last_http_request_id=p.last_http_request_id,last_request_id=p_request_id,last_recorded_at=t where singleton;end if;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'expires_at',collect_ops.utc(p_expires_at),
  'status',state,'inspected',inspected,'observations_added',added,'terminal_observed',terminal,'unobserved',unobserved,
  'source_scan_complete',false,'financial_action',false,'send_action',false,'resend_action',false);
 insert into collect_ops.receipt_transport_requests values(p_request_id,p_limit,p_expires_at,t,result);return result;
end$$;
create or replace function public.get_receipt_worker_transport_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_ops.receipt_transport_requests;t timestamptz;acquired boolean;begin
 perform collect_ops.receipt_exception_service();if p_request_id is null then raise exception 'receipt_transport_request_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-transport-request:'||p_request_id::text,0));
 select * into r from collect_ops.receipt_transport_requests where acquired and request_id=p_request_id;t:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'status',case when not acquired then 'in_progress'when r.request_id is null then 'not_recorded'else 'recorded'end,
  'expires_at',case when r.request_id is null then null else collect_ops.utc(r.expires_at)end,'receipt',case when r.request_id is null then null else collect_receipt_worker_history.read_payload('transport_receipt',r.request_id::text)end);end$$;
create or replace function public.admin_get_receipt_worker_transport_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare j collect_ops.receipt_worker_jobs;r collect_ops.receipt_worker_receipts;c collect_ops.receipt_transport_configuration;
 p collect_ops.receipt_transport_progress;t timestamptz;state text;rows jsonb;alerts jsonb:='[]'::jsonb;last_outcome text;units bigint;acquired boolean;begin
 perform collect_ops.actor(false);if p_request_id is null then raise exception 'receipt_transport_request_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
 if j.request_id is null then raise exception 'receipt_transport_job_unavailable'using errcode='22023';end if;
 select * into r from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 if r.request_id is not null then r.result:=collect_receipt_worker_history.read_payload('worker_receipt',r.request_id::text);end if;
 select * into c from collect_ops.receipt_transport_configuration where singleton;select * into p from collect_ops.receipt_transport_progress where singleton;
 t:=clock_timestamp();state:=case when r.request_id is not null then 'recorded'
  when exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)then 'expired_without_receipt'
  when not acquired then 'in_progress'
  when j.expires_at<=t then 'unknown'else 'pending'end;
 select coalesce(jsonb_agg(jsonb_build_object('attempt',d.attempt,'http_request_id',d.http_request_id::text,'dispatched_at',collect_ops.utc(d.dispatched_at),
  'evidence_revision',o.revision,'outcome',coalesce(o.outcome,'NOT_COLLECTED'),'transport_terminal',coalesce(o.transport_terminal,false),
  'http_status',o.http_status,'worker_error_code',o.worker_error_code,'response_rows_observed',o.response_rows_observed,
  'response_at',collect_ops.utc(o.response_at),'observed_at',collect_ops.utc(o.observed_at),'evidence_sha256',o.evidence_sha256)order by d.attempt),'[]'::jsonb)into rows
 from collect_ops.receipt_worker_dispatches d left join collect_ops.receipt_transport_heads h on h.http_request_id=d.http_request_id
 left join lateral collect_receipt_worker_history.read_transport_observation(h.http_request_id,h.revision)o on true where d.request_id=p_request_id;
 -- Derive the alert from the exact same row projection. A concurrent capture
 -- cannot produce an alert for a newer revision absent from the displayed rows.
 last_outcome:=rows->(jsonb_array_length(rows)-1)->>'outcome';
 if last_outcome not in('HTTP_ACCEPTED','HTTP_PENDING')then alerts:=alerts||jsonb_build_array(last_outcome);end if;
 select count(*)into units from collect_ops.receipt_transport_inspections where quota_day=(t at time zone 'UTC')::date;
 if p.last_recorded_at is null then alerts:=alerts||jsonb_build_array('COLLECTOR_UNOBSERVED');
 elsif p.last_recorded_at<t-interval '180 seconds'then alerts:=alerts||jsonb_build_array('COLLECTOR_STALE');end if;
 if units>=c.day_inspections then alerts:=alerts||jsonb_build_array('COLLECTOR_QUOTA_EXHAUSTED');end if;
 if not collect_ops.receipt_transport_schema_valid()then alerts:=alerts||jsonb_build_array('SOURCE_SCHEMA_UNAVAILABLE');end if;
 perform collect_ops.actor(false);
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'original_status',state,'original_expires_at',collect_ops.utc(j.expires_at),'original_receipt_status',r.result->'status','scan_request_id',r.scan_request_id,
  'rows',rows,'alerts',alerts,'collector',jsonb_build_object('configuration_revision',c.revision,'last_request_id',p.last_request_id,
   'last_recorded_at',collect_ops.utc(p.last_recorded_at),'day_inspections',units,'day_cap',c.day_inspections,'quota_exhausted',units>=c.day_inspections,
   'source_schema_valid',collect_ops.receipt_transport_schema_valid()),'source_scan_complete',false,'financial_action',false,'send_action',false,'resend_action',false);
end$$;
create function collect_receipt_worker_history.fences(p_jobs uuid[],p_scans uuid[],p_transport uuid[])returns void
language plpgsql volatile security definer set search_path=''as $$declare id uuid;begin
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 for id in select distinct x from unnest(p_jobs)x order by x loop
  if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||id::text,0))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;end loop;
 if not pg_try_advisory_xact_lock(hashtext('collect_admin_combined_roster'))or not pg_try_advisory_xact_lock(hashtext('collect-ops-workflow'))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 for id in select distinct x from unnest(p_scans)x order by x loop
  if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-exception-scan:'||id::text,0))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;end loop;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-exception-worker'))or not pg_try_advisory_xact_lock(hashtext('collect-receipt-transport-reconcile'))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 for id in select distinct x from unnest(p_transport)x order by x loop
  if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-transport-request:'||id::text,0))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;end loop;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-telemetry-sampler'))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
end$$;
create function collect_receipt_worker_history.scan_proof(p_scan uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set TimeZone='UTC'as $$
declare r jsonb;w collect_ops.receipt_exception_work;p jsonb;proofs jsonb:='[]';n integer:=0;h record;job uuid;begin
 select request_id into job from collect_ops.receipt_worker_receipts where scan_request_id=p_scan;
 perform collect_receipt_worker_history.fences(case when job is null then array[]::uuid[]else array[job]end,array[p_scan],array[]::uuid[]);
 r:=collect_receipt_worker_history.read_logical('scan_receipt',p_scan::text);
 if r is null or r->'result'->>'status'is distinct from 'processed'then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 for w in select * from collect_ops.receipt_exception_work where processed_request_id=p_scan and processed_at is not null order by id limit 33 loop
  n:=n+1;if n>32 or w.outcome<>'refreshed'then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
  p:=collect_receipt_worker_history.source_proof(w.source_kind,w.source_id,p_scan,w.id);
  if p is null then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
  proofs:=proofs||jsonb_build_array(p-'checked_at');
 end loop;
 if n is distinct from(r->'result'->>'processed')::integer then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 n:=0;
 for h in select o.exception_id,o.revision,x.active,x.revision current_revision,f.resolved_source_revision
  from collect_ops.receipt_exception_scan_observations o join collect_ops.exceptions x on x.id=o.exception_id
  left join collect_ops.exception_workflows f on f.exception_id=x.id where o.request_id=p_scan order by o.exception_id,o.revision limit 33 loop
  n:=n+1;if n>32 or h.active or(h.resolved_source_revision is not null and h.resolved_source_revision<>h.current_revision)
   or exists(select 1 from collect_ops.exception_workflows f where f.exception_id=h.exception_id and f.resolved_source_revision is distinct from h.current_revision)
   or exists(select 1 from collect_ops.exception_escalations e where e.exception_id=h.exception_id and e.state in('queued','recipient_unavailable'))
   or exists(select 1 from collect_receipt_source_projection.unread_inbox i where i.exception_id=h.exception_id)then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 end loop;
 return jsonb_build_object('kind','scan_receipt','scan',p_scan,'logical_sha256',collect_receipt_worker_history.sha(r),'sources',proofs,
  'observations',n,'financial_action',false,'send_action',false,'source_scan_complete',false);
end$$;
create function collect_receipt_worker_history.worker_proof(p_job uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set TimeZone='UTC'as $$
declare r jsonb;s uuid;j collect_ops.receipt_worker_jobs;p jsonb;begin
 select * into j from collect_ops.receipt_worker_jobs where request_id=p_job;
 select scan_request_id into s from collect_ops.receipt_worker_receipts where request_id=p_job;
 if j.request_id is null or s is null then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 perform collect_receipt_worker_history.fences(array[p_job],array[s],array[]::uuid[]);
 r:=collect_receipt_worker_history.read_logical('worker_receipt',p_job::text);
 if r is null or r->'result'->>'status'is distinct from 'completed'or(r->'result'->>'request_id')::uuid is distinct from p_job
  or(r->'result'->>'configuration_revision')::bigint is distinct from j.configuration_revision
  or(r->'result'->>'expires_at')::timestamptz is distinct from j.expires_at then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 p:=collect_receipt_worker_history.scan_proof(s);
 if r->'result'->'scan'is distinct from collect_receipt_worker_history.read_payload('scan_receipt',s::text)then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 return jsonb_build_object('kind','worker_receipt','job',p_job,'logical_sha256',collect_receipt_worker_history.sha(r),'scan',p);
end$$;
create function collect_receipt_worker_history.prove(p_family text,p_key text)returns jsonb
language plpgsql volatile security definer set search_path=''set TimeZone='UTC'as $$
declare p jsonb;points jsonb:='[]';x record;n integer:=0;job uuid;requests uuid[]:='{}';jobs uuid[]:='{}';scans uuid[]:='{}';r jsonb;begin
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_worker_history_snapshot_retry'using errcode='40001';end if;
 if p_family='worker_receipt'then return collect_receipt_worker_history.worker_proof(p_key::uuid);end if;
 if p_family='scan_receipt'then
  select request_id into job from collect_ops.receipt_worker_receipts where scan_request_id=p_key::uuid;
  if job is not null then return collect_receipt_worker_history.worker_proof(job);end if;
  return collect_receipt_worker_history.scan_proof(p_key::uuid);
 end if;
 if p_family='worker_configuration'then
  perform collect_receipt_worker_history.fences(array[]::uuid[],array[]::uuid[],array[]::uuid[]);
  if exists(select 1 from collect_ops.receipt_worker_configuration where revision=p_key::bigint)then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
  for x in select request_id from collect_ops.receipt_worker_jobs where configuration_revision=p_key::bigint order by request_id limit 33 loop
   n:=n+1;if n>32 then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
   points:=points||jsonb_build_array(collect_receipt_worker_history.worker_proof(x.request_id));end loop;
  r:=collect_receipt_worker_history.read_logical(p_family,p_key);
  if r is null then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
  return jsonb_build_object('kind',p_family,'key',p_key,'logical_sha256',collect_receipt_worker_history.sha(r),'jobs',points);
 end if;
 if p_family='transport_observation'then
  select d.request_id,o.reconciliation_request_id,o.transport_terminal into x
   from collect_ops.receipt_transport_observations o join collect_ops.receipt_worker_dispatches d using(http_request_id)
   where o.http_request_id=split_part(p_key,':',1)::bigint and o.revision=split_part(p_key,':',2)::bigint;
  if x.request_id is null or not x.transport_terminal then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
  perform collect_receipt_worker_history.fences(array[x.request_id],array[]::uuid[],array[x.reconciliation_request_id]);
  p:=collect_receipt_worker_history.worker_proof(x.request_id);
  r:=collect_receipt_worker_history.read_logical(p_family,p_key);
  return jsonb_build_object('kind',p_family,'key',p_key,'logical_sha256',collect_receipt_worker_history.sha(r),'job',p);
 end if;
 if p_family='transport_receipt'then
  for x in select d.request_id,r.scan_request_id,i.http_request_id
   from collect_ops.receipt_transport_inspections i join collect_ops.receipt_worker_dispatches d using(http_request_id)
   left join collect_ops.receipt_worker_receipts r on r.request_id=d.request_id where i.request_id=p_key::uuid order by i.http_request_id limit 33 loop
   n:=n+1;if n>32 or x.scan_request_id is null then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
   jobs:=array_append(jobs,x.request_id);scans:=array_append(scans,x.scan_request_id);
  end loop;
  perform collect_receipt_worker_history.fences(jobs,scans,array[p_key::uuid]);
  for job in select distinct a from unnest(jobs)a order by a loop points:=points||jsonb_build_array(collect_receipt_worker_history.worker_proof(job));end loop;
  r:=collect_receipt_worker_history.read_logical(p_family,p_key);
  if r is null or r->'result'->>'status'is distinct from 'processed'then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
  return jsonb_build_object('kind',p_family,'key',p_key,'logical_sha256',collect_receipt_worker_history.sha(r),'jobs',points,'inspections',n);
 end if;
 raise exception 'receipt_worker_history_family_invalid'using errcode='22023';end$$;
create function collect_receipt_worker_history.admit_relocation()returns trigger
language plpgsql volatile security definer set search_path=''as $$declare b collect_receipt_worker_history.bindings;o collect_receipt_worker_history.objects;p jsonb;begin
 select * into b from collect_receipt_worker_history.bindings where family=new.family and original_key=new.original_key;
 select * into o from collect_receipt_worker_history.objects where sha256=new.object_sha256;
 if b.family is null or o.sha256 is null or b.payload_sha256<>o.sha256 or b.payload_bytes<>octet_length(o.payload)then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 p:=collect_receipt_worker_history.prove(new.family,new.original_key);
 if p is distinct from new.proof then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 return new;end$$;
create trigger admitted_relocation before insert on collect_receipt_worker_history.relocations
 for each row execute function collect_receipt_worker_history.admit_relocation();
create function collect_receipt_worker_history.store_object(p_sha text,p_bytes bytea)returns void
language plpgsql security definer set search_path=''as $$declare prior bytea;begin
 if p_sha is null or p_bytes is null or encode(extensions.digest(p_bytes,'sha256'),'hex')<>p_sha then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 select payload into prior from collect_receipt_worker_history.objects where sha256=p_sha;
 if prior is not null then
  if prior<>p_bytes then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;return;end if;
 insert into collect_receipt_worker_history.objects values(p_sha,p_bytes);end$$;
create function collect_receipt_worker_history.detach(p_family text,p_key text,p_request uuid,p_proof jsonb)returns bigint
language plpgsql volatile security definer set search_path=''set TimeZone='UTC'as $$
declare r record;value jsonb;b collect_receipt_worker_history.bindings;bytes bytea;tab text;predicate text;clear text;check_value jsonb;begin
 execute collect_receipt_worker_history.query(p_family)||' for update of a nowait'into r using p_family,p_key;
 if r.original is null then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 value:=collect_receipt_worker_history.read_logical(p_family,p_key);
 if r.certificate is not null then return 0;end if;
 perform collect_receipt_worker_history.bind(p_family,p_key,value);
 select * into b from collect_receipt_worker_history.bindings where family=p_family and original_key=p_key;
 bytes:=convert_to(collect_receipt_worker_history.payload(p_family,value)::text,'UTF8');
 if octet_length(bytes)>1048576 then raise exception 'receipt_worker_history_byte_limit'using errcode='P0002';end if;
 perform collect_receipt_worker_history.store_object(b.payload_sha256,bytes);
 insert into collect_receipt_worker_history.relocations values(p_family,p_key,b.payload_sha256,p_request,p_proof,collect_receipt_worker_history.sha(p_proof),clock_timestamp());
 case p_family when 'worker_configuration'then tab:='receipt_worker_configuration_history';predicate:='revision=$1::bigint';clear:='configuration=null';
 when 'worker_receipt'then tab:='receipt_worker_receipts';predicate:='request_id=$1::uuid';clear:='result=null';
 when 'scan_receipt'then tab:='receipt_exception_scans';predicate:='request_id=$1::uuid';clear:='result=null';
 when 'transport_receipt'then tab:='receipt_transport_requests';predicate:='request_id=$1::uuid';clear:='result=null';
 when 'transport_observation'then tab:='receipt_transport_observations';predicate:='http_request_id=split_part($1,'':'',1)::bigint and revision=split_part($1,'':'',2)::bigint';clear:='http_status=null,worker_error_code=null,response_rows_observed=null,response_at=null';
 end case;
 execute format('update collect_ops.%I set %s where %s',tab,clear,predicate)using p_key;
 check_value:=collect_receipt_worker_history.read_logical(p_family,p_key);
 if check_value is distinct from value then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
 return octet_length(bytes);end$$;
create function collect_receipt_worker_history.archive_candidate(p_family text,p_key text,p_request uuid,p_budget bigint)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare proof jsonb;scan uuid;worker uuid;other jsonb;bytes bigint:=0;total bigint;originals jsonb:='[]';r jsonb;begin
 begin
  proof:=collect_receipt_worker_history.prove(p_family,p_key);
  if p_family='worker_receipt'then select scan_request_id into scan from collect_ops.receipt_worker_receipts where request_id=p_key::uuid;worker:=p_key::uuid;
  elsif p_family='scan_receipt'then scan:=p_key::uuid;select request_id into worker from collect_ops.receipt_worker_receipts where scan_request_id=scan;end if;
  -- Count exact unarchived byte lengths before either member can be detached.
  total:=0;
  if worker is not null then r:=collect_receipt_worker_history.read_logical('worker_receipt',worker::text);
   if not exists(select 1 from collect_receipt_worker_history.relocations where family='worker_receipt'and original_key=worker::text)then total:=total+octet_length(convert_to((r->'result')::text,'UTF8'));end if;end if;
  if scan is not null then r:=collect_receipt_worker_history.read_logical('scan_receipt',scan::text);
   if not exists(select 1 from collect_receipt_worker_history.relocations where family='scan_receipt'and original_key=scan::text)then total:=total+octet_length(convert_to((r->'result')::text,'UTF8'));end if;end if;
  if scan is null and worker is null then total:=octet_length(convert_to(collect_receipt_worker_history.read_payload(p_family,p_key)::text,'UTF8'));end if;
  if total>p_budget then raise exception 'receipt_worker_history_byte_limit'using errcode='P0002';end if;
  if worker is not null then other:=collect_receipt_worker_history.prove('worker_receipt',worker::text);
   bytes:=bytes+collect_receipt_worker_history.detach('worker_receipt',worker::text,p_request,other);originals:=originals||jsonb_build_array(jsonb_build_object('family','worker_receipt','key',worker));end if;
  if scan is not null then other:=collect_receipt_worker_history.prove('scan_receipt',scan::text);
   bytes:=bytes+collect_receipt_worker_history.detach('scan_receipt',scan::text,p_request,other);originals:=originals||jsonb_build_array(jsonb_build_object('family','scan_receipt','key',scan));end if;
  if scan is null and worker is null then bytes:=collect_receipt_worker_history.detach(p_family,p_key,p_request,proof);originals:=jsonb_build_array(jsonb_build_object('family',p_family,'key',p_key));end if;
  return jsonb_build_object('status','archived','bytes',bytes,'originals',originals,'proof_sha256',collect_receipt_worker_history.sha(proof));
 exception when no_data_found then return jsonb_build_object('status','held','code',case when sqlerrm='receipt_worker_history_byte_limit'then 'BYTE_LIMIT'else 'HELD'end,'bytes',0);
 when lock_not_available then return jsonb_build_object('status','held','code','SOURCE_BUSY','bytes',0);
 when object_not_in_prerequisite_state then
  if sqlerrm like 'receipt_worker_history_integrity%'then return jsonb_build_object('status','unavailable','code','INTEGRITY_REQUIRED','bytes',0);end if;raise;
 end;
end$$;
create function collect_receipt_worker_history.key_page(p_family text,p_key text,p_limit integer,p_hot boolean)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare f text;tab text;k text;hot text;after_key text;x record;rows jsonb:='[]';result jsonb;begin
 if p_limit is null or p_limit not between 1 and 25 or(p_family is null)<>(p_key is null)or(p_family is not null and(p_family not in('scan_receipt','transport_observation','transport_receipt','worker_configuration','worker_receipt')or length(p_key)not between 1 and 80))then raise exception 'receipt_worker_history_request_invalid'using errcode='22023';end if;
 foreach f in array array['scan_receipt','transport_observation','transport_receipt','worker_configuration','worker_receipt']loop
  if p_family is not null and f<p_family then continue;end if;
  after_key:=case when f=p_family then p_key else ''end;
  case f when 'worker_configuration'then tab:='receipt_worker_configuration_history';k:='revision::text';hot:='configuration is not null';
  when 'worker_receipt'then tab:='receipt_worker_receipts';k:='request_id::text';hot:='result is not null';
  when 'scan_receipt'then tab:='receipt_exception_scans';k:='request_id::text';hot:='result is not null';
  when 'transport_receipt'then tab:='receipt_transport_requests';k:='request_id::text';hot:='result is not null';
  when 'transport_observation'then tab:='receipt_transport_observations';k:='http_request_id::text||'':''||revision::text';hot:='response_rows_observed is not null';
  end case;
  if not p_hot then hot:='true';end if;
  for x in execute format('select %s original_key from collect_ops.%I where %s and(%s)>$1 order by(%s)limit $2',k,tab,hot,k,k)using after_key,p_limit loop
   rows:=rows||jsonb_build_array(jsonb_build_object('family',f,'original_key',x.original_key));end loop;
 end loop;
 if not p_hot then
  -- A dangling binding must enter the recovery inventory and fail reconstruction.
  for x in select family,original_key from collect_receipt_worker_history.bindings
   where p_family is null or(family,original_key)>(p_family,p_key)order by family,original_key limit p_limit loop
   if not rows@>jsonb_build_array(jsonb_build_object('family',x.family,'original_key',x.original_key))then
    rows:=rows||jsonb_build_array(jsonb_build_object('family',x.family,'original_key',x.original_key));end if;
  end loop;
 end if;
 select coalesce(jsonb_agg(value order by value->>'family',value->>'original_key'),'[]'::jsonb)into result
  from(select value from jsonb_array_elements(rows)order by value->>'family',value->>'original_key'limit p_limit)page;
 return result;end$$;
create function collect_receipt_worker_history.candidate_page(p_family text,p_key text,p_limit integer)returns jsonb
language sql volatile security definer set search_path=''as $$select collect_receipt_worker_history.key_page(p_family,p_key,p_limit,true)$$;
create function collect_receipt_worker_history.verify_recorded(p_receipt jsonb)returns void
language plpgsql volatile security definer set search_path=''as $$declare row jsonb;original jsonb;n integer:=0;begin
 for row in select value from jsonb_array_elements(p_receipt->'rows')loop
  for original in select value from jsonb_array_elements(coalesce(row->'result'->'originals','[]'::jsonb))loop
   n:=n+1;if n>50 then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
   if collect_receipt_worker_history.read_logical(original->>'family',original->>'key')is null then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  end loop;
 end loop;end$$;
create function collect_receipt_worker_history.maintain(p_request uuid,p_limit integer,p_expires timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare prior collect_receipt_worker_history.requests;p collect_receipt_worker_history.progress;c collect_receipt_worker_history.configuration;
 x record;at timestamptz;value jsonb;rows jsonb:='[]';n integer:=0;moved bigint:=0;status text;result jsonb;begin
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_worker_history_snapshot_retry'using errcode='40001';end if;
 if p_request is null or p_limit is null or p_limit not between 1 and 25 or p_expires is null or not isfinite(p_expires)or p_expires>clock_timestamp()+interval '120 seconds'then raise exception 'receipt_worker_history_request_invalid'using errcode='22023';end if;
 if p_expires<=clock_timestamp()then raise exception 'receipt_worker_history_expired'using errcode='55000';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-history-request:'||p_request::text,0))then return jsonb_build_object('status','in_progress','request_id',p_request);end if;
 select * into prior from collect_receipt_worker_history.requests where request_id=p_request;
 if prior.request_id is not null then
  if prior.request_limit<>p_limit or prior.expires_at<>p_expires then raise exception 'receipt_worker_history_original_conflict'using errcode='22023';end if;
  perform collect_receipt_worker_history.verify_recorded(prior.result);return prior.result;end if;
 select * into c from collect_receipt_worker_history.configuration where singleton;
 if not c.enabled then return jsonb_build_object('status','inactive');end if;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-history-maintenance'))then status:='overlap';
 else
  select * into p from collect_receipt_worker_history.progress where singleton for update nowait;
  for x in select * from jsonb_to_recordset(collect_receipt_worker_history.candidate_page(p.last_family,p.last_key,least(p_limit,c.batch_limit)))as page(family text,original_key text)loop
   if p_expires<=clock_timestamp()then raise exception 'receipt_worker_history_expired'using errcode='55000';end if;
   value:=collect_receipt_worker_history.archive_candidate(x.family,x.original_key,p_request,c.byte_limit-moved);
   n:=n+1;moved:=moved+(value->>'bytes')::bigint;rows:=rows||jsonb_build_array(jsonb_build_object('family',x.family,'key',x.original_key,'result',value));
   p.last_family:=x.family;p.last_key:=x.original_key;
  end loop;
  if n=0 then
   if p.epoch=1000000000 then raise exception 'receipt_worker_history_epoch_exhausted'using errcode='55000';end if;
   p.epoch:=p.epoch+1;p.last_family:=null;p.last_key:=null;end if;
  status:='processed';
 end if;
 at:=clock_timestamp();if p_expires<=at then raise exception 'receipt_worker_history_expired'using errcode='55000';end if;
 if p.singleton is not null then update collect_receipt_worker_history.progress set epoch=p.epoch,last_family=p.last_family,last_key=p.last_key,last_request_id=p_request,last_recorded_at=at where singleton;end if;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request,'checked_at',collect_ops.utc(at),'expires_at',collect_ops.utc(p_expires),
  'status',status,'candidates',n,'moved_bytes',moved,'rows',rows,'epoch',p.epoch,'source_scan_complete',false,'financial_action',false,'send_action',false);
 insert into collect_receipt_worker_history.requests values(p_request,p_limit,p_expires,at,result);return result;end$$;
create function collect_receipt_worker_history.run_schedule()returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare c collect_receipt_worker_history.configuration;begin
 select * into c from collect_receipt_worker_history.configuration where singleton;
 if not c.enabled then return jsonb_build_object('status','inactive');end if;
 return collect_receipt_worker_history.maintain(gen_random_uuid(),c.batch_limit,clock_timestamp()+interval '60 seconds');end$$;
create function collect_receipt_worker_history.prepare(p_expected bigint,p_enabled boolean,p_limit integer,p_bytes integer)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='2s'as $$
declare c collect_receipt_worker_history.configuration;job bigint;begin
 if p_expected is null or p_enabled is null or p_limit is null or p_limit not between 1 and 25 or p_bytes is null or p_bytes not between 1 and 4194304 then raise exception 'receipt_worker_history_configuration_invalid'using errcode='22023';end if;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-history-maintenance'))then raise exception 'receipt_worker_history_held'using errcode='P0002';end if;
 select * into c from collect_receipt_worker_history.configuration where singleton for update nowait;
 if c.revision<>p_expected or c.revision=1000000000 then raise exception 'receipt_worker_history_configuration_changed'using errcode='55000';end if;
 update collect_receipt_worker_history.configuration set revision=revision+1,enabled=p_enabled,batch_limit=p_limit,byte_limit=p_bytes,updated_at=clock_timestamp()where singleton returning * into c;
 for job in select jobid from cron.job where jobname='collect-receipt-history-maintenance'loop perform cron.unschedule(job);end loop;
 job:=cron.schedule('collect-receipt-history-maintenance','* * * * *','select collect_receipt_worker_history.run_schedule();');
 perform cron.alter_job(job,active:=p_enabled);
 return to_jsonb(c)-'singleton';end$$;
create function collect_receipt_worker_history.inventory_page(p_after_family text,p_after_key text,p_limit integer)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare x record;r jsonb;rows jsonb:='[]';bytes bigint:=0;item jsonb;last_family text;last_key text;b jsonb;begin
 for x in select *from jsonb_to_recordset(collect_receipt_worker_history.key_page(p_after_family,p_after_key,p_limit,false))as page(family text,original_key text)loop
  r:=collect_receipt_worker_history.read_logical(x.family,x.original_key);
  if r is null then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  select to_jsonb(binding)into b from collect_receipt_worker_history.bindings binding where family=x.family and original_key=x.original_key;
  item:=jsonb_build_object('family',x.family,'key',x.original_key,'logical_sha256',collect_receipt_worker_history.sha(r),'binding',b,
   'tier',case when exists(select 1 from collect_receipt_worker_history.relocations where family=x.family and original_key=x.original_key)then 'cold'else 'hot'end);
  bytes:=bytes+octet_length(convert_to(item::text,'UTF8'));if bytes>4194304 then raise exception 'receipt_worker_history_byte_limit'using errcode='55000';end if;rows:=rows||jsonb_build_array(item);
  last_family:=x.family;last_key:=x.original_key;
 end loop;return jsonb_build_object('contract_version',1,'rows',rows,'checked',jsonb_array_length(rows),'last_family',last_family,'last_key',last_key,
  'financial_action',false,'send_action',false,'source_scan_complete',false);end$$;
create function collect_receipt_worker_history.verify_page(p_page jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare x jsonb;r jsonb;n integer:=0;begin
 if jsonb_typeof(p_page->'rows')is distinct from 'array'or jsonb_array_length(p_page->'rows')>25 then raise exception 'receipt_worker_history_request_invalid'using errcode='22023';end if;
 for x in select value from jsonb_array_elements(p_page->'rows')loop
  r:=collect_receipt_worker_history.read_logical(x->>'family',x->>'key');
  if r is null or collect_receipt_worker_history.sha(r)is distinct from x->>'logical_sha256'then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;n:=n+1;
 end loop;return jsonb_build_object('contract_version',1,'verified',n,'financial_action',false,'send_action',false);end$$;
create function collect_receipt_worker_history.object_inventory_page(p_after_sha text,p_limit integer)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare o collect_receipt_worker_history.objects;rows jsonb:='[]';last_sha text;begin
 if p_limit is null or p_limit not between 1 and 25 or(p_after_sha is not null and p_after_sha!~'^[0-9a-f]{64}$')then raise exception 'receipt_worker_history_request_invalid'using errcode='22023';end if;
 for o in select *from collect_receipt_worker_history.objects where p_after_sha is null or sha256>p_after_sha order by sha256 limit p_limit loop
  if o.sha256 is distinct from encode(extensions.digest(o.payload,'sha256'),'hex')then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('sha256',o.sha256,'bytes',octet_length(o.payload)));last_sha:=o.sha256;
 end loop;return jsonb_build_object('contract_version',1,'rows',rows,'checked',jsonb_array_length(rows),'last_sha256',last_sha,'financial_action',false,'send_action',false);end$$;
create function collect_receipt_worker_history.verify_object_page(p_page jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare x jsonb;o collect_receipt_worker_history.objects;n integer:=0;begin
 if jsonb_typeof(p_page->'rows')is distinct from 'array'or jsonb_array_length(p_page->'rows')>25 then raise exception 'receipt_worker_history_request_invalid'using errcode='22023';end if;
 for x in select value from jsonb_array_elements(p_page->'rows')loop
  select *into o from collect_receipt_worker_history.objects where sha256=x->>'sha256';
  if o.sha256 is null or o.sha256 is distinct from encode(extensions.digest(o.payload,'sha256'),'hex')or octet_length(o.payload)::text is distinct from x->>'bytes'then raise exception 'receipt_worker_history_integrity'using errcode='55000';end if;n:=n+1;
 end loop;return jsonb_build_object('contract_version',1,'verified',n,'financial_action',false,'send_action',false);end$$;

revoke all on all functions in schema collect_receipt_worker_history from public,anon,authenticated,service_role;
commit;
