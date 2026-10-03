"""Affected connected cases; all fixtures stay inside one isolated SQL target."""
import concurrent.futures,datetime,json,time,uuid
ident=lambda:str(uuid.uuid4())
def run(t,m,call,case,scan,drain,live,certs,post,operation,principal,run_id,normal,receipt,device,save,report):
 q=m.quoted;version=500000;zero='00000000-0000-0000-0000-000000000000'
 def event(payment=None,handled=True,code='RECEIPT_EXISTS',target=None,source_version=None,h_version=None):
  nonlocal version
  version+=1;v=source_version or version;eid=ident();payment=payment or normal['payment'];target=target or receipt
  t.sql('begin;insert into collect_hybrid.receipt_business_events(id,source_kind,source_id,source_version,event_kind,collection_id,payment_id,member_record_id,source_state)values('+','.join([q(eid),"'payment'",q(payment),str(v),"'payment_posted'",q(m.GROUP),q(payment),q(m.MEMBER),"'posted'"])+');'+('insert into collect_receipt_operations.handled_events values('+','.join([q(eid),q(run_id),q(principal),str(h_version or v),q(code),q(target)if code in('RECEIPT_EXISTS','RECEIPT_ENQUEUED')else'null','clock_timestamp()'])+');'if handled else'')+'commit;',label='explicit original immutable event/handling fixture '+eid)
  return eid
 def queue(kind,source):
  return t.scalar('insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('+q(kind)+','+q(source)+",'sweep')returning id;")
 def deferral(eid,code='SOURCE_BUSY'):
  t.sql('insert into collect_receipt_operations.event_deferrals values('+q(eid)+',clock_timestamp(),'+q(code)+')on conflict(event_id)do update set code=excluded.code;')
 def await_state(app):
  for _ in range(150):
   if t.scalar("select exists(select 1 from pg_stat_activity where application_name="+q(app)+"and wait_event='PgSleep');")=='t':return True
   time.sleep(.01)
  return False
 def exact():
  return t.scalar("select not exists(select 1 from collect_receipt_source_projection.admissions a left join collect_receipt_source_projection.live l on l.admission_id=a.id left join collect_receipt_source_projection.certificates c on c.admission_id=a.id where(l.admission_id is null)=(c.admission_id is null))and not exists(select 1 from collect_receipt_source_projection.certificates c join collect_ops.receipt_exception_work w on w.id=c.work_id left join collect_ops.receipt_exception_scans s on s.request_id=c.scan_request_id where s.request_id is null or w.processed_request_id is distinct from c.scan_request_id or w.source_kind<>c.source_kind or w.source_id<>c.source_id or w.outcome<>'refreshed');")=='t'
 # The public result and original request identity stay closed and exact.
 first=scan();same=scan(25,first['request_id'],first['expires_at'])
 case('exact original scan UUID replay returns byte-equivalent receipt and flags remain false',same==first and not first['source_scan_complete']and not first['financial_action']and not first['send_action'])
 old_count=t.scalar('select count(*)from collect_receipt_source_projection.certificates;')
 found=call('public.get_receipt_deferral_exception_scan_v1('+q(first['request_id'])+')',True)
 case('lost original response lookup recovers exact unchanged scan without another certificate',found['status']=='recorded'and found['receipt']==first and t.scalar('select count(*)from collect_receipt_source_projection.certificates;')==old_count)
 conflict=t.sql("begin;set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.process_receipt_deferral_exceptions_v1("+q(first['request_id'])+',1,'+q(first['expires_at'])+');rollback;',check=False)
 case('same original UUID cannot change its limit',conflict.returncode!=0 and 'receipt_exception_scan_conflict'in conflict.stderr)
 # A malformed boolean is not a terminal code. Matching original FK identity,
 # source version and content proof remain mandatory even when1400 sayshandled.
 newer=post('backlog');other=post('other')
 t.sql('insert into collect_receipt_operations.backlog_results values('+q(run_id)+','+q(newer['snapshot'])+",'DRY_RUN_ELIGIBLE',true,null,clock_timestamp());")
 drain();case('true backlog boolean with DRY_RUN_ELIGIBLE cannot retire live membership',live('receipt_backlog',newer['snapshot'])and certs('receipt_backlog',newer['snapshot'])==0)
 wrong_version=event(h_version=1);drain();case('immutable handled event with mismatched exact source_version remains live',live('receipt_event',wrong_version)and certs('receipt_event',wrong_version)==0)
 wrong_receipt=event(payment=other['payment']);drain();case('handled receipt from another actual payment/snapshot cannot retire source',live('receipt_event',wrong_receipt)and certs('receipt_event',wrong_receipt)==0)
 t.sql('insert into collect_receipt_operations.backlog_results values('+q(run_id)+','+q(other['snapshot'])+",'RECEIPT_EXISTS',true,"+q(receipt)+',clock_timestamp());')
 drain();case('handled backlog with mismatched original receipt snapshot remains live',live('receipt_backlog',other['snapshot'])and certs('receipt_backlog',other['snapshot'])==0)
 # A correct immutable backlog acknowledgement is independently terminal.
 backlog_run=run_id;t.sql('insert into collect_receipt_operations.backlog_results values('+q(backlog_run)+','+q(normal['snapshot'])+",'RECEIPT_EXISTS',true,"+q(receipt)+',clock_timestamp());')
 drain();case('exact immutable handled backlog binds original run snapshot and receipt',not live('receipt_backlog',normal['snapshot'])and certs('receipt_backlog',normal['snapshot'])==1)
 # Higher immutable source evidence must remain separately discoverable.
 superseded=event(handled=False);replacement=event();deferral(superseded);drain()
 case('strict immutable supersession retires old source with independent replacement proof',not live('receipt_event',superseded)and certs('receipt_event',superseded)==1 and t.scalar('select proof_kind=\'immutable_supersession\'and superseding_event_id='+q(replacement)+'from collect_receipt_source_projection.certificates where source_id='+q(superseded)+';')=='t')
 missing=post('missing-replacement');old=event(payment=missing['payment'],handled=False);event(payment=missing['payment'],handled=False);deferral(old);drain()
 case('unrepresented immutable replacement does not remove old pending source',live('receipt_event',old)and certs('receipt_event',old)==0)
 mutable=post('mutable-only');t.sql('update collect_hybrid.receipt_business_event_heads set version=version+1 where source_kind=\'payment\'and source_id='+q(mutable['payment'])+';');deferral(mutable['event']['id']);drain()
 case('mutable head alone is not immutable supersession proof',live('receipt_event',mutable['event']['id'])and certs('receipt_event',mutable['event']['id'])==0)
 busy=post('source-busy');deferral(busy['event']['id']);drain()
 case('SOURCE_BUSY and current dry-run/clear observations do not manufacture terminal ACK',live('receipt_event',busy['event']['id'])and certs('receipt_event',busy['event']['id'])==0 and t.scalar('select not exists(select 1 from collect_receipt_operations.handled_events where event_id='+q(busy['event']['id'])+');')=='t')
 unavailable=ident();queue('receipt_event',unavailable);drain()
 case('source-unavailable original work is retained and cannot acquire a certificate',live('receipt_event',unavailable)and certs('receipt_event',unavailable)==0 and t.scalar('select exists(select 1 from collect_ops.receipt_exception_work where source_id='+q(unavailable)+"and outcome='source_unavailable');")=='t')
 # Actual Admin assignment, deadline sweep, source clear, resolution and read
 # are separate causes. Maintenance never creates those source acknowledgements.
 t.sql("update public.parsed_payment_events set allocation_status='needs_review'where id="+q(normal['parsed'])+';')
 held=event();drain();case('active exact allocation exception holds immutable handled source',live('receipt_event',held))
 exception=t.scalar("select id from collect_ops.exceptions where source_kind='allocation'and source_id="+q(normal['parsed'])+"and reason_code='ALLOCATION_REVIEW';")
 workflow=call('public.admin_get_exception_workflow_v1('+q(exception)+')');due=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=1)).isoformat()
 call('public.admin_act_exception_workflow_v2('+','.join([q(ident()),q(exception),str(workflow['source_revision']),str(workflow['workflow_revision']),"'assign'",q(m.UID),q(due),"'review_started'","clock_timestamp()+interval '100 seconds'"])+')')
 time.sleep(1.15);pumped=call('public.process_exception_escalations_v1(20)',True)
 t.sql("update public.parsed_payment_events set allocation_status='allocated'where id="+q(normal['parsed'])+';');drain()
 case('inactive head with unfinished actual workflow retains live source',live('receipt_event',held)and pumped['delivered']>=1)
 workflow=call('public.admin_get_exception_workflow_v1('+q(exception)+')')
 call('public.admin_act_exception_workflow_v2('+','.join([q(ident()),q(exception),str(workflow['source_revision']),str(workflow['workflow_revision']),"'resolve'",'null','null',"'source_rechecked'","clock_timestamp()+interval '100 seconds'"])+')');drain()
 case('resolved workflow does not discard delivered unread original inbox evidence',live('receipt_event',held))
 deliveries=t.json('select jsonb_agg(d.escalation_id)from collect_ops.exception_inbox_deliveries d join collect_ops.exception_escalations e on e.id=d.escalation_id where e.exception_id='+q(exception)+';')
 for delivery in deliveries:call('public.admin_read_exception_escalation_v1('+q(delivery)+')')
 drain();case('actual source resolution and inbox read permit exact terminal certificate',not live('receipt_event',held)and certs('receipt_event',held)==1 and t.scalar('select exists(select 1 from collect_receipt_source_projection.certificate_observations o join collect_receipt_source_projection.certificates c on c.id=o.certificate_id where c.source_id='+q(held)+'and o.exception_id='+q(exception)+');')=='t')
 # Explicit private escalation states cannot be treated as completed delivery.
 escalation=ident();t.sql('insert into collect_ops.exception_escalations(id,exception_id,source_revision,recipient_id,reason_code,state)select '+q(escalation)+',id,revision,'+q(m.OTHER)+",'operator_escalation','recipient_unavailable'from collect_ops.exceptions where id="+q(exception)+';')
 escalated=event();drain();case('recipient-unavailable escalation holds the exact inactive source graph',live('receipt_event',escalated))
 t.sql("update collect_ops.exception_escalations set state='obsolete',completed_at=clock_timestamp()where id="+q(escalation)+';');drain()
 case('original escalation producer terminal state permits later conservative retirement',not live('receipt_event',escalated))
 #300 actual historical heads are joined, even when their current source moved.
 alert=ident();linked=event();rule='HANDLING_LATENCY_HIGH';scope='9'*64
 t.sql('begin;insert into collect_receipt_telemetry.alert_heads(id,scope_sha256,policy_revision,collection_ids,rule_code,status,episode,revision,evidence_sha256,source_kind,source_id,response_code,observed_at)values('+','.join([q(alert),q(scope),'2','array['+q(m.GROUP)+']::uuid[]',q(rule),"'active'",'1','1',"repeat('b',64)","'handled_event'",q(linked),"'investigate_handling'",'clock_timestamp()'])+');select collect_ops.observe(\'receipt_telemetry\','+q(alert)+",array['TELEMETRY_HANDLING_LATENCY_HIGH'],'{\"episode\":1,\"status\":\"active\"}');update collect_receipt_telemetry.alert_heads set exception_id=(select id from collect_ops.exceptions where source_kind='receipt_telemetry'and source_id="+q(alert)+")where id="+q(alert)+';insert into collect_receipt_telemetry.alert_observations values('+q(alert)+",1,'active',1,'{}','handled_event',"+q(linked)+',clock_timestamp());commit;')
 drain();case('actual300 linked active telemetry exception holds handled source',live('receipt_event',linked))
 t.sql('begin;update collect_receipt_telemetry.alert_heads set source_id='+q(ident())+',revision=revision+1 where id='+q(alert)+';commit;');drain()
 case('moved telemetry head remains linked through immutable original observations',live('receipt_event',linked))
 t.sql('begin;update collect_receipt_telemetry.alert_heads set status=\'clear\',revision=revision+1 where id='+q(alert)+';select collect_ops.observe(\'receipt_telemetry\','+q(alert)+",'{}','{\"episode\":1,\"status\":\"clear\"}');commit;")
 #5000 historical numeric rows for one alert must not cause a lifetime DISTINCT.
 t.sql('insert into collect_receipt_telemetry.alert_observations select '+q(alert)+",100+g,'clear',1,jsonb_build_object('synthetic_history',g),'handled_event',"+q(linked)+',clock_timestamp()from generate_series(1,5000)g;analyze collect_receipt_telemetry.alert_observations;')
 plan=json.loads(t.sql('explain(analyze,buffers,format json)select a.alert_id from collect_receipt_telemetry.alert_observations a where a.source_kind=\'handled_event\'and a.source_id='+q(linked)+"and a.alert_id>="+q(alert)+"and a.alert_id>"+q(alert)+'order by a.alert_id limit 1;').stdout)
 save(report/'deep-telemetry-alert-seek-explain.json',plan)
 def nodes(x):
  if isinstance(x,dict):
   yield x
   for v in x.values():yield from nodes(v)
  elif isinstance(x,list):
   for v in x:yield from nodes(v)
 case('actual historical alert-ID seek uses source index and skips5000 duplicate numeric rows',any(n.get('Index Name')=='receipt_telemetry_observation_source'for n in nodes(plan))and all(n.get('Actual Rows',0)<5000 for n in nodes(plan)))
 drain();case('cleared linked telemetry with deep unchanged history permits exact certificate',not live('receipt_event',linked)and certs('receipt_event',linked)==1)
 # Expiry rolls processed work, certificate, live removal and original scan
 # publication back together; no partial durable completion can escape.
 expiring=event();adm=t.scalar('select admission_id from collect_receipt_source_projection.live where source_id='+q(expiring)+';')
 t.sql("create function public.projection_fixture_pause_cert()returns trigger language plpgsql set search_path=''as $$begin if current_setting('application_name')='projection-expiry'then perform pg_sleep(.3);end if;return new;end$$;create trigger zz_fixture_pause_certificate before insert on collect_receipt_source_projection.certificates for each row execute function public.projection_fixture_pause_cert();")
 expiry_request=ident();r=t.sql("begin;set local application_name='projection-expiry';set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.process_receipt_deferral_exceptions_v1("+q(expiry_request)+",25,clock_timestamp()+interval '.15 seconds');commit;",check=False)
 case('actual expiry rolls certificate and live removal back with original scan',r.returncode!=0 and 'receipt_exception_scan_expired'in r.stderr and live('receipt_event',expiring)and certs('receipt_event',expiring)==0 and t.scalar('select admission_id='+q(adm)+'from collect_receipt_source_projection.live where source_id='+q(expiring)+';')=='t'and call('public.get_receipt_deferral_exception_scan_v1('+q(expiry_request)+')',True)['status']=='not_recorded')
 t.sql('drop trigger zz_fixture_pause_certificate on collect_receipt_source_projection.certificates;drop function public.projection_fixture_pause_cert();');drain();case('later valid original scan recovers expired pending work without financial retry',not live('receipt_event',expiring))
 # Deterministic race: pause after final pending check, before live DELETE.
 raced=event();old_admission=t.scalar('select admission_id from collect_receipt_source_projection.live where source_id='+q(raced)+';')
 t.sql("create function public.projection_fixture_pause_delete()returns trigger language plpgsql set search_path=''as $$begin if old.source_id="+q(raced)+"::uuid and current_setting('application_name')='projection-delete-race'then perform pg_sleep(1.5);end if;return old;end$$;create trigger zz_fixture_pause_delete before delete on collect_receipt_source_projection.live for each row execute function public.projection_fixture_pause_delete();")
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
  request=ident();scanner=pool.submit(t.sql,"begin;set local application_name='projection-delete-race';set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.process_receipt_deferral_exceptions_v1("+q(request)+",25,clock_timestamp()+interval '100 seconds');commit;")
  assert await_state('projection-delete-race');producer=pool.submit(t.sql,'begin;insert into collect_receipt_operations.event_deferrals values('+q(raced)+",clock_timestamp(),'SOURCE_BUSY');commit;")
  producer.result(timeout=3);case('producer commits original pending work between last check and deletion without financial blocking',await_state('projection-delete-race'))
  # Actual shipping producers use the same workflow gate before source/head
  # publication. Their denied bounded calls cannot append a phantom hold.
  for name,expr in [('workflow','public.process_exception_escalations_v1(20)'),('telemetry','public.process_receipt_operational_telemetry_v1('+q(ident())+",clock_timestamp()+interval '100 seconds')")]:
   blocked=t.sql("begin;set local lock_timeout='100ms';set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select "+expr+';commit;',check=False,label='actual '+name+' producer refuses shared publication gate during scan certificate/delete')
   case('actual '+name+' publication gate cannot admit a phantom hold while scanner owns it',blocked.returncode!=0 and '55P03'in blocked.stderr and await_state('projection-delete-race'))
  scanner.result(timeout=10)
  # Once the same shipping gate is released, original service consumers remain
  # usable; telemetry stays inactive and reports its unavailable status.
  recovered_pump=call('public.process_exception_escalations_v1(20)',True)
  recovered_sample=call('public.process_receipt_operational_telemetry_v1('+q(ident())+",clock_timestamp()+interval '100 seconds')",True)
  save(report/'actual-publication-gate-recovery.json',dict(workflow=recovered_pump,telemetry=recovered_sample))
  case('same original workflow and inactive sampler recover after certificate publication gate releases',isinstance(recovered_pump,dict)and isinstance(recovered_sample,dict))
 case('racing producer original pending row survives retired old membership and certificate',not live('receipt_event',raced)and certs('receipt_event',raced)==1 and t.scalar('select exists(select 1 from collect_ops.receipt_exception_work where source_id='+q(raced)+"and processed_at is null);")=='t')
 late_work=t.scalar('select id from collect_ops.receipt_exception_work where source_id='+q(raced)+'and processed_at is null order by queued_at,id limit 1;')
 t.sql('drop trigger zz_fixture_pause_delete on collect_receipt_source_projection.live;drop function public.projection_fixture_pause_delete();update collect_ops.receipt_exception_progress set phase=\'receipt_event\',last_id=\'ffffffff-ffff-ffff-ffff-ffffffffffff\'where singleton;')
 before_replay=t.scalar('select count(*)from collect_receipt_source_projection.certificates;');original=call('public.get_receipt_deferral_exception_scan_v1('+q(request)+')',True)['receipt'];case('raced original UUID lookup remains exact immutable receipt',scan(25,request,original['expires_at'])==original and t.scalar('select count(*)from collect_receipt_source_projection.certificates;')==before_replay)
 drain();case('behind-cursor exact pending work re-admits and retires with a new immutable admission',not live('receipt_event',raced)and certs('receipt_event',raced)==2 and t.scalar('select exists(select 1 from collect_receipt_source_projection.certificates c join collect_receipt_source_projection.admissions a on a.id=c.admission_id where c.source_id='+q(raced)+'and a.work_id='+q(late_work)+'and a.id<>'+q(old_admission)+');')=='t')
 # NOWAIT refuses busy financial/root evidence while unrelated producers run.
 contended=event()
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
  holder=pool.submit(t.sql,"begin;set local application_name='projection-source-lock';select id from public.payments where id="+q(normal['payment'])+'for update;select pg_sleep(3);commit;')
  assert await_state('projection-source-lock');scan();case('actual busy source fences retain membership without certificate',live('receipt_event',contended)and certs('receipt_event',contended)==0)
  independent=pool.submit(post,'independent').result(timeout=3)
  case('independent actual financial posting commits while another source remains locked',await_state('projection-source-lock')and t.scalar('select status=\'posted\'from public.payments where id='+q(independent['payment'])+';')=='t')
  ack=pool.submit(t.sql,'insert into collect_receipt_operations.event_deferrals values('+q(independent['event']['id'])+",clock_timestamp(),'SOURCE_BUSY');")
  ack.result(timeout=3);case('independent exact work producer progresses while another financial source stays locked',await_state('projection-source-lock'));holder.result(timeout=5)
 drain();case('released source contention recovers on later bounded sweep',not live('receipt_event',contended))
 # Original real worker/160 consumers still join the same UUIDs and scan FK.
 # Exact retained synthetic transport credentials; no Vault crypto, hosted
 # credential, HTTP availability or external worker authentication is attested.
 t.sql("alter view vault.decrypted_secrets rename to isolated_original_decrypted_secrets;create table vault.transport_fixture_credentials(name text primary key,decrypted_secret text);create view vault.decrypted_secrets as select name,decrypted_secret from vault.transport_fixture_credentials;grant select on vault.decrypted_secrets to postgres;insert into vault.transport_fixture_credentials values('collect_receipt_exception_project_url','https://lhbowpbcpwoiparwnwgt.supabase.co'),('collect_receipt_exception_api_key','SYNTHETIC-PUBLISHABLE-KEY-ONLY'),('collect_receipt_exception_worker_secret','SYNTHETIC-WORKER-CREDENTIAL-NEVER-A-REAL-SECRET');",user='supabase_admin',label='exact declared isolated Vault view fixture; never real credentials or encryption proof')
 save(report/'synthetic-vault-boundary.json',dict(synthetic_vault_view=True,vault_crypto_verified=False,hosted_credentials_used=False,external_worker_authentication_verified=False))
 worker_event=event();call('public.configure_receipt_exception_schedule_v1(1,true,25,20,1440,36000,28800)')
 worker=ident();t.sql('with stamp as materialized(select clock_timestamp()at)insert into collect_ops.receipt_worker_jobs select '+q(worker)+",2,25,20,(at at time zone 'UTC')::date,at,at+interval '90 seconds'from stamp;")
 job=t.json('select to_jsonb(j)from collect_ops.receipt_worker_jobs j where request_id='+q(worker)+';');http=t.scalar("select net.http_post(url:='https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-exception-worker',body:='{}'::jsonb,headers:='{}'::jsonb,timeout_milliseconds:=15000);")
 t.sql('insert into collect_ops.receipt_worker_dispatches values('+q(worker)+',1,'+http+',clock_timestamp());')
 processed=call('public.execute_receipt_exception_worker_v1('+','.join([q(worker),'2',q(job['expires_at'])])+')',True)
 looked=call('public.get_receipt_exception_worker_request_v1('+q(worker)+')',True);detail=call('public.admin_get_receipt_worker_transport_v1('+q(worker)+')')
 save(report/'actual-worker-original-lookup.json',looked);save(report/'actual-worker-transport-detail.json',detail)
 case('real original worker execute lookup and160 read retain original UUID and scan FK',processed['status']=='recorded'and looked['status']=='recorded'and looked['receipt']==processed['receipt']and detail['scan_request_id']==worker and detail['original_status']=='recorded'and not detail['send_action'])
 case('worker certificate commits with the exact original worker scan receipt',not live('receipt_event',worker_event)and t.scalar('select exists(select 1 from collect_receipt_source_projection.certificates c join collect_ops.receipt_worker_receipts r on r.scan_request_id=c.scan_request_id where c.source_id='+q(worker_event)+'and r.request_id='+q(worker)+');')=='t')
 # Future transport has its own synchronous exception/new immutable event.
 # Certificate at an earlier scan never represents permanent transport absence.
 fixture_send_flag=t.scalar("select enabled from public.feature_flags where key='hybrid_sms_notifications';")
 t.sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';",label='explicit isolated future-transport SQL fixture enable; no network/device/SMS authority')
 fresh=operation('begin_run')
 hp=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z'))
 call('public.gateway_heartbeat_v1('+q(device)+','+q(ident())+','+q('f'*64)+','+q(json.dumps(hp))+'::jsonb)',True)
 def gateway(action,payload):return call('public.'+action+'('+','.join([q(device),q(ident()),q('e'*64),q(json.dumps(payload))+'::jsonb'])+')',True)
 grant=gateway('gateway_dispatch_grant_v2',{});case('ordinary grant can follow old source certificate through its separate original route',grant['code']=='DISPATCH_GRANTED'and grant['receipt_id']==receipt and not live('receipt_event',normal['event']['id']))
 plan=[dict(segment_index=i,sent_callback_id=ident(),delivery_callback_id=ident())for i in range(grant['segment_count'])]
 armed=gateway('gateway_arm_dispatch_v2',dict(attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],callbacks=plan,reservation_sha256='e'*64))
 def callback(code):return gateway('gateway_callback_v2',dict(callback_id=plan[0]['sent_callback_id'],attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],segment_index=0,segment_count=grant['segment_count'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],callback_kind='sent',result_code=code,tp_status=None,occurred_at=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')))
 callback(-1);callback(1)
 case('later authenticated uncertain callback synchronously creates own exception and NEW immutable event',armed['code']=='DISPATCH_ARMED'and t.scalar('select exists(select 1 from collect_ops.exceptions where source_kind=\'receipt\'and source_id='+q(receipt)+"and active and reason_code='SEND_UNCERTAIN')and exists(select 1 from collect_hybrid.receipt_business_events where source_kind='receipt'and source_id="+q(receipt)+"and event_kind='receipt_uncertain');")=='t')
 unknown=event();drain();case('actual grant arm and uncertain callback hold new handled source membership',live('receipt_event',unknown)and certs('receipt_event',unknown)==0)
 t.sql("update public.feature_flags set enabled="+('true'if fixture_send_flag=='t'else'false')+" where key='hybrid_sms_notifications';",label='restore exact isolated send-flag fixture state; shipping defaults stay unchanged')
 #400 owner closure keeps its active suppressed exception. Its immutable
 # never-armed evidence cannot silently manufacture source resolution.
 closed=post('closed-original');closed_root=t.scalar('select id from collect_hybrid.sms_notification_outbox where payment_id='+q(closed['payment'])+';')
 inspection=call('public.admin_inspect_unarmed_receipt_closure_v1('+q(closed_root)+')')
 assert inspection['can_close'],inspection
 closure=call('public.admin_close_unarmed_receipt_v1('+','.join([q(ident()),q(closed_root),str(inspection['root_revision']),str(inspection['lineage_revision']),"'definitely_not_invoked'","'Synthetic original route never invoked'"])+')')
 closed_event=event(payment=closed['payment'],target=closed_root);drain()
 case('actual400 immutable unarmed closure retains active RECEIPT_SUPPRESSED hold',closure['proof_class']=='never_armed_closed'and live('receipt_event',closed_event)and certs('receipt_event',closed_event)==0 and t.scalar('select exists(select 1 from collect_ops.exceptions where source_kind=\'receipt\'and source_id='+q(closed_root)+"and active and reason_code='RECEIPT_SUPPRESSED');")=='t')
 # Even declared malformed owner-only evidence cannot remove another recipient
 # hold: the public API already denied the wrong-recipient action above.
 unread_only=post('unread-only');unread_root=t.scalar('select id from collect_hybrid.sms_notification_outbox where payment_id='+q(unread_only['payment'])+';')
 t.sql("update public.parsed_payment_events set allocation_status='needs_review'where id="+q(unread_only['parsed'])+";update public.parsed_payment_events set allocation_status='allocated'where id="+q(unread_only['parsed'])+';')
 unread_exception=t.scalar("select id from collect_ops.exceptions where source_kind='allocation'and source_id="+q(unread_only['parsed'])+"and reason_code='ALLOCATION_REVIEW'and not active;")
 assert unread_exception
 before_wrong=event(payment=unread_only['payment'],target=unread_root);drain()
 case('isolated inactive source graph retires before any unread hold is admitted',not live('receipt_event',before_wrong)and certs('receipt_event',before_wrong)==1)
 wrong_delivery=ident();t.sql('begin;insert into collect_ops.exception_escalations(id,exception_id,source_revision,recipient_id,reason_code,state,completed_at)select '+q(wrong_delivery)+',id,revision,'+q(m.UID)+",'operator_escalation','delivered',clock_timestamp()from collect_ops.exceptions where id="+q(unread_exception)+';insert into collect_ops.exception_inbox_deliveries values('+q(wrong_delivery)+','+q(m.UID)+',clock_timestamp());insert into collect_ops.exception_inbox_reads values('+q(wrong_delivery)+','+q(m.OTHER)+',clock_timestamp());commit;',label='explicit malformed immutable wrong-recipient fixture; original API guards unchanged')
 wrong_hold=event(payment=unread_only['payment'],target=unread_root);drain()
 case('wrong-recipient immutable read retains otherwise terminal exact source hold',live('receipt_event',wrong_hold)and certs('receipt_event',wrong_hold)==0 and t.scalar('select exists(select 1 from collect_receipt_source_projection.unread_inbox where escalation_id='+q(wrong_delivery)+'and recipient_id='+q(m.UID)+');')=='t')
 # Deep original sources stay in original journals. Bound sweep selects live
 # indexed keys and processes only its original request limit, without claiming
 # physical archive/retention or terminal authority from maintenance.
 t.sql('begin;with inserted as(insert into collect_hybrid.receipt_business_events(source_kind,source_id,source_version,event_kind,collection_id,payment_id,member_record_id,source_state)select \'payment\','+q(normal['payment'])+",5000000+g,'payment_posted',"+q(m.GROUP)+','+q(normal['payment'])+','+q(m.MEMBER)+",'posted'from generate_series(1,5000)g returning id,source_version)insert into collect_receipt_operations.handled_events select id,"+q(run_id)+','+q(principal)+",source_version,'RECEIPT_EXISTS',"+q(receipt)+',clock_timestamp()from inserted;analyze collect_receipt_source_projection.live;analyze collect_ops.receipt_exception_work;commit;',label='declared5000 immutable original source/handled journals plus actual producer membership')
 live_plan=json.loads(t.sql("explain(analyze,buffers,format json)select l.source_id from collect_receipt_source_projection.live l where l.source_kind='receipt_event'and l.source_id>='00000000-0000-0000-0000-000000000000'::uuid and(null::uuid is null or l.source_id>null::uuid)order by l.source_id limit 25;").stdout)
 save(report/'deep-original-source-live-sweep-explain.json',live_plan)
 case('actual sweep uses live primary index and returns at most25 over5000 retained original sources',any(n.get('Index Name')=='live_pkey'for n in nodes(live_plan))and all(n.get('Actual Rows',0)<=25 for n in nodes(live_plan))and t.scalar("select count(*)=5000 from collect_hybrid.receipt_business_events where source_version between5000001 and5005000;".replace('between5000001 and5005000','between 5000001 and 5005000'))=='t')
 bounded=scan();case('actual deep-history scan respects original25 bound and preserves original retired source lookup',bounded['processed']<=25 and not bounded['source_scan_complete']and not bounded['financial_action']and not bounded['send_action']and not live('receipt_event',normal['event']['id'])and t.scalar('select exists(select 1 from collect_hybrid.receipt_business_events where id='+q(normal['event']['id'])+')and exists(select 1 from collect_receipt_operations.handled_events where event_id='+q(normal['event']['id'])+');')=='t')
 # Every original immutable evidence row remains addressable; no broad delete,
 # physical relocation or false business/delivery completion is introduced.
 case('live/admission/certificate and original work/scan equality holds after every transition',exact())
 for table in ['installations','admissions','certificates','certificate_observations']:
  bad=t.sql('begin;delete from collect_receipt_source_projection.'+table+';rollback;',check=False)
  case(table+' immutable DELETE evidence is protected',bad.returncode!=0 and 'receipt_source_projection_evidence_immutable'in bad.stderr)
  bad=t.sql('begin;truncate collect_receipt_source_projection.'+table+' cascade;rollback;',check=False)
  case(table+' immutable TRUNCATE evidence is protected',bad.returncode!=0 and 'receipt_source_projection_evidence_immutable'in bad.stderr)
 # Final private helper metadata must be shipping bytes, no fixture hooks left.
 case('all projection fixture hooks removed without altering original source functions',t.scalar("select not exists(select 1 from pg_proc where pronamespace='public'::regnamespace and proname like 'projection_fixture_%');")=='t')
