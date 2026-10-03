require_relative 'promote/scripts/audits/collect_inactive_restore_overlay'
require 'open3'
require 'base64'
require 'openssl'
C=JSON.parse(File.read(ARGV.fetch(0)));O=CollectInactiveRestoreOverlay;P=C.fetch('report');R={'status'=>'running','checks'=>[],'commands'=>[],
 'scope'=>'current208 synthetic SQL guard fixture; original reused205 raw/plain dump stays distinct; owner stop has no Auth actor; fixture APIs use retained synthetic operator/session or service-role SQL, no signed hosted JWT/Edge/device claim'}
def save;File.write(File.join(P,'driver-result.json'),JSON.pretty_generate(R)+"\n");end
def check(name,value);R['checks']<<{'name'=>name,'passed'=>!!value};save;puts((value ? 'PASS ':'FAIL ')+name);raise name unless value;end
def record(av,text,out,err,status)
 prefix=File.join(P,format('ruby-%04d',R['commands'].length));File.write(prefix+'.stdout',out);File.write(prefix+'.stderr',err)
 R['commands']<<{'argv'=>av,'input_sha256'=>Digest::SHA256.hexdigest(text),'exit_code'=>status.exitstatus,'stdout_sha256'=>Digest::SHA256.hexdigest(out),'stderr_sha256'=>Digest::SHA256.hexdigest(err),'prefix'=>prefix};save
end
def argv(user='postgres');[C['docker'],'exec','-i',C['target'],'psql','-XqAt','-h','/run/collect','-U',user,'-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'];end
def sql(text,user='postgres',failure:false)
 av=argv(user);out,err,status=Open3.capture3(*av,stdin_data:text);record(av,text,out,err,status)
 raise 'actual SQL failed: '+(err.length>1000 ? err[-1000..] : err) unless status.success?||failure
 [out,err,status]
end
def js(text,user='postgres');JSON.parse(sql(text,user).first.strip);end
def q(v);O.literal(v.to_s);end
def uid;SecureRandom.uuid;end
def service(expr,failure:false)
 sql("BEGIN;SET LOCAL ROLE service_role;SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);SELECT #{expr};COMMIT;",failure:failure)
end
def sj(expr);JSON.parse(service(expr).first.strip.split("\n").last);end
def operator(expr)
 raw=sql("BEGIN;SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claims','{\"sub\":\"99780000-0000-4000-8000-000000000001\",\"session_id\":\"99780000-0000-4000-8000-000000010001\",\"role\":\"authenticated\",\"aal\":\"aal1\"}',true);SELECT #{expr};COMMIT;").first
 JSON.parse(raw.strip.split("\n").last)
end
def gateway(name,device,payload,request=uid)
 "public.#{name}(#{q(device)},#{q(request)},#{q('e'*64)},#{q(JSON.generate(payload))}::jsonb)"
end
def state
 js("SELECT jsonb_build_object('policy',(SELECT to_jsonb(t)FROM collect_receipt_operations.policy t),'fence',(SELECT value FROM collect_receipt_operations.fence),
 'worker',(SELECT to_jsonb(t)FROM collect_ops.receipt_worker_configuration t),'history',(SELECT to_jsonb(t)FROM collect_receipt_worker_history.configuration t),
 'successor',(SELECT to_jsonb(t)FROM collect_receipt_successors.configuration t),'telemetry',(SELECT to_jsonb(t)FROM collect_receipt_telemetry.configuration t),
 'flag',(SELECT to_jsonb(t)FROM public.feature_flags t WHERE key='hybrid_sms_notifications'),'config_history',(SELECT count(*)FROM collect_ops.receipt_worker_configuration_history),
 'cold_objects',(SELECT count(*)FROM collect_receipt_worker_history.objects),'capsule',to_regnamespace('collect_recovery_restore')IS NOT NULL); ")
end
def retained_lookup(value,original,from,until_time)
 # Shipping700 get-worker body exposes exactly these two current sample clocks; every other wire field stays exact.
 keys=%w[contract_version request_id checked_at sample_valid_until status expires_at receipt]
 return false unless value.keys.sort==keys.sort&&original.keys.sort==keys.sort
 checked=Time.parse(value.fetch('checked_at'));valid=Time.parse(value.fetch('sample_valid_until'))
 value.reject{|k,_|%w[checked_at sample_valid_until].include?(k)}==original.reject{|k,_|%w[checked_at sample_valid_until].include?(k)}&&checked>=from&&checked<=until_time&&((valid-checked)-60).abs<0.00001
end
def process_phase(name)
 rows={}
 { 'target'=>[C['docker'],'inspect',C['target'],'--format','{{json .}}'],
   'postgres_os_uid'=>[C['docker'],'exec',C['target'],'id','-u','postgres'],
   'postmaster'=>[C['docker'],'exec',C['target'],'sh','-c','pid=$(head -1 /var/lib/postgresql/collect-rehearsal/data/postmaster.pid); printf "%s\n" "$pid"; cat /proc/$pid/status; cat /proc/1/status; cat /proc/$pid/cmdline']}.each do|kind,av|
  out,err,status=Open3.capture3(*av);record(av,'read-only actual process phase '+name,out,err,status);raise 'process phase unavailable' unless status.success?;rows[kind]=out
 end
 target=JSON.parse(rows['target']);pg=rows['postmaster'];pid=pg.lines.first.to_i;uid=pg[/^Uid:\s+(\d+)/,1];pid1=target.fetch('State').fetch('Pid')
 result={'phase'=>name,'target_id'=>target['Id'],'target_name'=>target['Name'],'container_running'=>target['State']['Running'],'host_pid1'=>pid1,'postmaster_pid'=>pid,'postmaster_uid'=>uid,'expected_postmaster_uid'=>rows['postgres_os_uid'].strip,'pgdata'=>'/var/lib/postgresql/collect-rehearsal/data','raw_process_sha256'=>Digest::SHA256.hexdigest(pg)}
 File.write(File.join(P,'process-'+name+'.json'),JSON.pretty_generate(result)+"\n");result
end
def fingerprint(worker_revision,flag_revision,new_invalidation_id=nil)
 text=<<~SQL
 CREATE TEMP TABLE proof_original_rows(name text,n bigint,sha text);
 DO $p$ DECLARE t record;condition text;projection text;h text;n bigint;BEGIN
 FOR t IN SELECT schemaname,tablename FROM pg_tables WHERE(schemaname='public'OR schemaname IN('auth','storage')OR schemaname LIKE'collect_%')AND schemaname<>'collect_recovery_restore'ORDER BY schemaname,tablename LOOP
  IF t.schemaname||'.'||t.tablename=ANY(ARRAY['collect_receipt_operations.policy','collect_receipt_operations.fence','collect_receipt_successors.configuration','collect_ops.receipt_worker_configuration','collect_receipt_worker_history.configuration','collect_receipt_telemetry.configuration'])THEN CONTINUE;END IF;
  condition:='true';projection:='to_jsonb(x)';
  IF t.schemaname||'.'||t.tablename IN('collect_supervisor.identities','collect_gateway.devices')THEN projection:='to_jsonb(x)-ARRAY[''state'',''revoked_at'']';END IF;
  IF t.schemaname||'.'||t.tablename='public.feature_flags'THEN condition:='key<>''hybrid_sms_notifications''';END IF;
  IF t.schemaname||'.'||t.tablename='collect_security.runtime_control_heads'THEN condition:='NOT(family=''feature_flags''AND identity=jsonb_build_object(''key'',''hybrid_sms_notifications''))';END IF;
  IF t.schemaname||'.'||t.tablename='collect_security.runtime_control_events'THEN condition:='NOT(family=''feature_flags''AND identity_sha256=collect_security.runtime_control_hash(jsonb_build_object(''key'',''hybrid_sms_notifications''))AND revision=#{flag_revision+1})';END IF;
  IF t.schemaname||'.'||t.tablename='collect_receipt_worker_history.bindings'THEN condition:='NOT(family=''worker_configuration''AND original_key=''#{worker_revision+1}'')';END IF;
  #{new_invalidation_id ? "IF t.schemaname||'.'||t.tablename='public.app_realtime_events'THEN condition:='id<>''#{new_invalidation_id}''::uuid';END IF;" : ''}
  IF t.schemaname||'.'||t.tablename='collect_ops.receipt_worker_configuration_history'THEN condition:='revision<=#{worker_revision}';END IF;
  EXECUTE format('SELECT count(*),encode(sha256(convert_to(coalesce(string_agg((%s)::text,E''\\n''ORDER BY(%s)::text),''''),''UTF8'')),''hex'')FROM %I.%I x WHERE %s',projection,projection,t.schemaname,t.tablename,condition)INTO n,h;
  INSERT INTO proof_original_rows VALUES(t.schemaname||'.'||t.tablename,n,h);
 END LOOP;END$p$;
 SELECT jsonb_agg(jsonb_build_array(name,n,sha)ORDER BY name)FROM proof_original_rows;
 SQL
 js(text,'supabase_admin')
end
begin
 renewal_before=js("SELECT to_jsonb(s)FROM auth.sessions s WHERE id='99780000-0000-4000-8000-000000010001';")
 sql("UPDATE auth.sessions SET not_after=clock_timestamp()+interval '1 hour' WHERE id='99780000-0000-4000-8000-000000010001'AND user_id='99780000-0000-4000-8000-000000000001';")
 check('only retained synthetic operator session deadline renewed before original baseline',js("SELECT to_jsonb(public._notification_session_is_live('99780000-0000-4000-8000-000000010001','99780000-0000-4000-8000-000000000001'));"))
 renewal_after=js("SELECT to_jsonb(s)FROM auth.sessions s WHERE id='99780000-0000-4000-8000-000000010001';")
 File.write(File.join(P,'synthetic-session-preparation.json'),JSON.pretty_generate({'scope'=>'only synthetic retained test session; before original fixture baseline; not an overlay or raw Auth archive parity claim','old'=>renewal_before,'new'=>renewal_after})+"\n")
 check('synthetic session preparation changes only original not_after',renewal_before.reject{|k,_|k=='not_after'}==renewal_after.reject{|k,_|k=='not_after'})
 document=CollectRecoverySource.build(JSON.parse(File.read(C['catalog'])),root:C['root'])
 contract_raw=JSON.generate(document)+"\n";File.write(File.join(P,'current208-guard-source-contract.json'),contract_raw)
 check('actual ordinary owner and cron EXECUTE without grant or fallback',js("SELECT json_build_object('session',session_user,'effective',current_user,'super',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),'cron',has_function_privilege(current_user,'cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE')); ")=={'session'=>'postgres','effective'=>'postgres','super'=>false,'cron'=>true})
 ident=js("SELECT jsonb_build_object('principal',i.id,'key',i.key_sha256,'device',d.id,'expiry',i.expires_at)FROM collect_supervisor.identities i CROSS JOIN collect_gateway.devices d WHERE i.scope='rw_receipt_operations'AND i.state='active'AND d.state='active'LIMIT 1;")
 check('retained fixture identity unexpired for genuine shipping producer setup',Time.parse(ident['expiry'])>Time.now.utc)
 device=ident['device'];principal=ident['principal']
 caps=%w[run_actions group_actions device_actions global_actions run_sms_segments group_sms_segments device_sms_segments global_sms_segments].to_h{|k|[k,1000]}
 sql("UPDATE public.feature_flags SET enabled=true WHERE key='hybrid_sms_notifications';UPDATE collect_receipt_operations.policy SET revision=revision+1,mode='Live-limited',emergency_stop=false,catchup_enabled=true,principal_ids=ARRAY[#{q(principal)}]::uuid[],collection_ids=ARRAY['99780000-0000-4000-8000-000000030001']::uuid[],device_ids=ARRAY[#{q(device)}]::uuid[],caps=#{q(JSON.generate(caps))}::jsonb WHERE singleton;UPDATE collect_receipt_successors.configuration SET enabled=true,revision=revision+1 WHERE singleton;")
 run=sj("public.receipt_operations_execute_v2(#{q(principal)},#{q(uid)},#{q(ident['key'])},#{q('a'*64)},clock_timestamp(),'begin_run','{}'::jsonb)")
 check('actual shipping begin_run before owner stop',run['code']=='RUN_STARTED')
 heartbeat=lambda{sj(gateway('gateway_heartbeat_v1',device,{'sms_permission'=>true,'network'=>'validated','telephony'=>'ready','sim_selected'=>true,'sim_revision_sha256'=>'d'*64,'local_pause'=>false,'reported_at'=>Time.now.utc.iso8601(6)}))};heartbeat.call
 setup_path=File.join(C['root'],'.cache/receipt-successor-workflows-20261001/accepted-successor-observations-archive-current1/proof/attempt4/inputs/reused-predecessor-setup.sql');setup=File.binread(setup_path)
 check('exact accepted reused financial producer source',Digest::SHA256.hexdigest(setup)=='a9f53ddb1e7e28fa64386e7c6b73956ad6f3f5cbac01b42b4900966b9c21ad06')
 raw_insert=setup.lines.find{|l|l.start_with?('begin;insert into public.raw_payment_sms')&&l.include?("'CLOSURE-1'")};confirm=setup.lines.find{|l|l.start_with?('begin;select set_config')&&l.include?('confirm_provider_payment')&&l.include?("'CLOSURE-1'")}
 ids=%w[235b47fa-920d-44c3-9f19-552415f05207 afb6ba85-a5e6-4bc7-b10f-2f4f7cd13ba5 ee15afdc-b289-411a-abcd-bd25b1d461ed];fresh=ids.map{uid};insert=raw_insert.dup;confirmation=confirm.dup
 ids.zip(fresh).each{|old,newid|insert.gsub!(old,newid);confirmation.gsub!(old,newid)};insert.gsub!('CLOSURE-1','INACTIVE-RESTORE-PRIMARY');confirmation.gsub!('CLOSURE-1','INACTIVE-RESTORE-PRIMARY');sql(insert);sql(confirmation)
 primary=sj(gateway('gateway_dispatch_grant_v2',device,{}));check('actual primary original grant for separate confirmed financial source',primary['ok']&&primary['receipt_id']&&primary['segment_count']>0)
 primary_plan=(0...primary['segment_count']).map{|i|{'segment_index'=>i,'sent_callback_id'=>uid,'delivery_callback_id'=>uid}}
 primary_arm={'attempt_id'=>primary['attempt_id'],'fence_version'=>primary['fence_version'],'body_sha256'=>primary['body_sha256'],'destination_sha256'=>primary['destination_sha256'],'reservation_sha256'=>'d'*64,'callbacks'=>primary_plan}
 check('actual primary final arm before stop',sj(gateway('gateway_arm_dispatch_v2',device,primary_arm))['ok'])
 root=js("SELECT to_jsonb(o)FROM collect_hybrid.sms_notification_outbox o JOIN collect_receipt_successors.original_closures c ON c.root_outbox_id=o.id LIMIT 1;")
 h=operator("public.admin_inspect_receipt_successor_v1(#{q(root['id'])},'retry_uninvoked',#{q(root['snapshot_id'])})")
 approved=operator("public.admin_approve_receipt_successor_v1(#{q(uid)},#{q(root['id'])},'retry_uninvoked',#{q(root['snapshot_id'])},#{h['preview']['root_revision']},#{h['preview']['lineage_revision']},#{q(h['preview_sha256'])},#{q(h['sample_valid_until'])}::timestamptz,'definitely_not_invoked','Synthetic restore late observation fixture')")
 heartbeat.call;successor=sj(gateway('gateway_receipt_successor_grant_v1',device,{}));check('actual successor grant uses permanently closed separate source',successor['route']&&successor['route']['primary_receipt_id']==root['id'])
 successor_plan=(0...successor['segment_count']).map{|i|{'segment_index'=>i,'sent_callback_id'=>uid,'delivery_callback_id'=>uid}}
 successor_arm={'route'=>successor['route'],'attempt_id'=>successor['attempt_id'],'fence_version'=>successor['fence_version'],'body_sha256'=>successor['body_sha256'],'destination_sha256'=>successor['destination_sha256'],'reservation_sha256'=>'f'*64,'callbacks'=>successor_plan}
 check('actual successor final arm before stop',sj(gateway('gateway_receipt_successor_arm_v1',device,successor_arm))['send_authority'])
 cold=js("SELECT jsonb_build_object('key',original_key,'objects',(SELECT count(*)FROM collect_receipt_worker_history.objects))FROM collect_receipt_worker_history.bindings b WHERE family='worker_receipt'AND EXISTS(SELECT 1 FROM collect_receipt_worker_history.relocations r WHERE r.family=b.family AND r.original_key=b.original_key)LIMIT 1;")
 old_lookup=sj("public.get_receipt_exception_worker_request_v1(#{q(cold['key'])})")
 worker_revision=state['worker']['revision'];flag_revision=js("SELECT revision FROM collect_security.runtime_control_heads WHERE family='feature_flags'AND identity=jsonb_build_object('key','hybrid_sms_notifications');")
 producer_query="SELECT jsonb_agg(jsonb_build_object('oid',p.oid,'prosrc_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'acl',p.proacl,'owner',p.proowner,'definition',pg_get_functiondef(p.oid))ORDER BY p.oid)FROM pg_proc p WHERE p.oid IN('collect_receipt_worker_history.capture()'::regprocedure,'collect_receipt_worker_history.bind(text,text,jsonb)'::regprocedure,'public.emit_app_realtime_event()'::regprocedure,'collect_security.govern_runtime_control()'::regprocedure);"
 source_producers=js(producer_query);File.write(File.join(P,'original-producer-vector.json'),JSON.pretty_generate(source_producers)+"\n")
 before_rows=fingerprint(worker_revision,flag_revision);File.write(File.join(P,'original-row-fingerprints.json'),JSON.pretty_generate(before_rows)+"\n")
 tooling=O.tooling(C['root']);File.write(File.join(P,'actual-tooling-vector.json'),JSON.pretty_generate(tooling)+"\n")
 context=O.input!(target:C['target'],document:document,contract_sha256:Digest::SHA256.hexdigest(contract_raw),archive_sha256:C['reused_plain_database_sha256'],comparison_sha256:CollectRecoverySource.digest(before_rows),reason:'Synthetic current208 guard fixture authority stop',tools_sha256:CollectRecoverySource.digest(tooling))
 build=lambda{|overrides={}|O.script(context.merge('expires_at'=>(Time.now.utc+120).iso8601(6)).merge(overrides),document,root:C['root'])}
 initial=state
 # Isolated rollback-only role negative: the real owner name is postgres but its temporary role is SUPERUSER.
 # No role/ACL change commits, and no production privileged execution/fallback is introduced.
 prefix="BEGIN;ALTER ROLE postgres SUPERUSER;SET SESSION AUTHORIZATION postgres;SELECT jsonb_build_object('session',session_user,'effective',current_user,'super',(SELECT rolsuper FROM pg_roles WHERE rolname=session_user));"
 _,err,status=sql(prefix+build.call,'supabase_admin',failure:true)
 check('explicit NOSUPERUSER gate denies same named superuser before catalog use and restores exact role/catalog baseline',!status.success?&&err.include?('restore_stop_owner_isolation_required')&&err.include?('42501')&&state==initial&&js("BEGIN;SET LOCAL search_path=pg_catalog;SET LOCAL timezone='UTC';"+O.source_query(C['root'])+";COMMIT;")==document['catalog'])
 # Exercise the already-false flag branch in one explicit rollback-only fixture transaction.
 # Its temporary receipt is not accepted as a committed stop.
 rollback_script=build.call.sub(/COMMIT;\n\z/,"SELECT jsonb_build_object('new_flag_rows',(SELECT count(*)FROM collect_recovery_restore.stop_items WHERE family='new_flag_realtime_event'),'new_binding_rows',(SELECT count(*)FROM collect_recovery_restore.stop_items WHERE family='new_worker_configuration_binding'),'inactive',NOT(SELECT enabled FROM public.feature_flags WHERE key='hybrid_sms_notifications'));ROLLBACK;\n")
 raw,_,status=sql("BEGIN;UPDATE public.feature_flags SET enabled=false WHERE key='hybrid_sms_notifications';"+rollback_script)
 branch_receipt=JSON.parse(raw.strip.split("\n").last)
 check('actual already-false flag branch has no fabricated invalidation and exact one binding then fully rolls back',status.success?&&branch_receipt=={'new_flag_rows'=>0,'new_binding_rows'=>1,'inactive'=>true}&&state==initial&&fingerprint(worker_revision,flag_revision)==before_rows)
 %w[collect_admin_combined_roster collect-receipt-trusted-worker collect-receipt-history-maintenance collect-ops-workflow collect-receipt-telemetry-sampler].each do |gate|
  av=argv;lock_sql="BEGIN;SELECT pg_advisory_xact_lock(hashtext(#{q(gate)}));SELECT 'READY';SELECT pg_sleep(3);COMMIT;"
  Open3.popen3(*av)do|si,so,se,wait|
   si.write(lock_sql);si.close;Timeout.timeout(5){loop{break if so.gets.to_s.strip=='READY'}}
   _,err,status=sql(build.call,failure:true);check('actual '+gate+' conflict refuses all partial stop work',!status.success?&&err.include?('55P03')&&state==initial)
   lockout=so.read;lockerr=se.read;lockstatus=wait.value;record(av,lock_sql,lockout,lockerr,lockstatus)
  end
 end
 auth_prefix="SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claims','{\"sub\":\"99780000-0000-4000-8000-000000000001\",\"session_id\":\"99780000-0000-4000-8000-000000010001\",\"role\":\"authenticated\",\"aal\":\"aal1\"}',true);"
 fixture_key=OpenSSL::PKey::EC.generate('prime256v1');key_bytes=OpenSSL::ASN1::Sequence.new([OpenSSL::ASN1::Sequence.new([OpenSSL::ASN1::ObjectId.new('id-ecPublicKey'),OpenSSL::ASN1::ObjectId.new('prime256v1')]),OpenSSL::ASN1::BitString.new(fixture_key.public_key.to_bn.to_s(2))]).to_der;new_spki=Base64.strict_encode64(key_bytes);new_key_sha=Digest::SHA256.hexdigest(key_bytes);fixture_key=nil
 held_producers=[
  ['shipping worker configure',"SELECT public.configure_receipt_exception_schedule_v1(#{initial['worker']['revision']},false,#{initial['worker']['scan_limit']},#{initial['worker']['escalation_limit']},#{initial['worker']['day_jobs']},#{initial['worker']['day_scan_sources']},#{initial['worker']['day_escalations']})"],
  ['shipping history prepare',"SELECT collect_receipt_worker_history.prepare(#{initial['history']['revision']},false,#{initial['history']['batch_limit']},#{initial['history']['byte_limit']})"],
  ['shipping owner policy publication',auth_prefix+"SELECT public.admin_configure_receipt_operations_v2(#{q(uid)},#{initial['policy']['revision']},'Live',false,ARRAY[#{q(principal)}]::uuid[],ARRAY['99780000-0000-4000-8000-000000030001']::uuid[],ARRAY[#{q(device)}]::uuid[],#{q(JSON.generate(caps))}::jsonb,true,24,'Synthetic held publication',clock_timestamp()+interval '100 seconds')"],
  ['shipping pending identity enrollment',auth_prefix+"SELECT public.admin_enroll_receipt_operations_identity_v3(#{q(uid)},#{q(new_spki)},#{q(new_key_sha)},clock_timestamp()+interval '1 hour',clock_timestamp()+interval '100 seconds')"]
 ]
 held_producers.each do|name,producer|
  av=argv;held_sql="BEGIN;#{producer};SELECT 'READY';SELECT pg_sleep(2);ROLLBACK;"
  Open3.popen3(*av)do|si,so,se,wait|
   si.write(held_sql);si.close;Timeout.timeout(5){loop{line=so.gets;raise name+' refused before READY '+se.read if line.nil?;break if line.strip=='READY'}}
   _,err,status=sql(build.call,failure:true);check('actual '+name+' overlap refuses stop with all pending producer evidence intact',!status.success?&&err.include?('55P03')&&state==initial)
   heldout=so.read;helderr=se.read;heldstatus=wait.value;record(av,held_sql,heldout,helderr,heldstatus);raise name+' producer failed' unless heldstatus.success?
  end
 end
 # Actual row/table conflicts occur after earlier advisory acquisitions; no global bypass.
 [ ['principal row',"SELECT 1 FROM collect_supervisor.identities WHERE id=#{q(principal)} FOR SHARE"],
   ['device row',"SELECT 1 FROM collect_gateway.devices WHERE id=#{q(device)} FOR SHARE"],
   ['policy row','SELECT 1 FROM collect_receipt_operations.policy WHERE singleton FOR SHARE'],
   ['fence row','SELECT 1 FROM collect_receipt_operations.fence WHERE singleton FOR SHARE'],
   ['successor config','SELECT 1 FROM collect_receipt_successors.configuration WHERE singleton FOR SHARE'],
   ['worker config','SELECT 1 FROM collect_ops.receipt_worker_configuration WHERE singleton FOR SHARE'],
   ['history config','SELECT 1 FROM collect_receipt_worker_history.configuration WHERE singleton FOR SHARE'],
   ['telemetry config','SELECT 1 FROM collect_receipt_telemetry.configuration WHERE singleton FOR SHARE'],
   ['dispatch flag',"SELECT 1 FROM public.feature_flags WHERE key='hybrid_sms_notifications' FOR SHARE"],
   ['runtime head',"SELECT 1 FROM collect_security.runtime_control_heads WHERE family='feature_flags'AND identity=jsonb_build_object('key','hybrid_sms_notifications') FOR SHARE"]].each do |name,locked|
  av=argv;lock_sql="BEGIN;#{locked};SELECT 'READY';SELECT pg_sleep(2);COMMIT;"
  Open3.popen3(*av)do|si,so,se,wait|
   si.write(lock_sql);si.close;Timeout.timeout(5){loop{break if so.gets.to_s.strip=='READY'}}
   _,err,status=sql(build.call,failure:true);check('actual '+name+' contention rolls back earlier locks and stop',!status.success?&&err.include?('55P03')&&state==initial)
   lockout=so.read;lockerr=se.read;lockstatus=wait.value;record(av,lock_sql,lockout,lockerr,lockstatus)
  end
 end
 # cron.alter_job runs after config/history/flag/revocation deltas; its conflict must undo all of them.
 av=argv('supabase_admin');lock_sql="BEGIN;SELECT 1 FROM cron.job WHERE jobname='collect-receipt-exceptions'FOR UPDATE;SELECT 'READY';SELECT pg_sleep(3);COMMIT;"
 Open3.popen3(*av)do|si,so,se,wait|
  si.write(lock_sql);si.close;Timeout.timeout(5){loop{break if so.gets.to_s.strip=='READY'}}
  _,err,status=sql(build.call,failure:true);check('late actual cron API contention rolls back capsule config binding flag event and key revocations',!status.success?&&err.include?('55P03')&&state==initial&&fingerprint(worker_revision,flag_revision)==before_rows)
  lockout=so.read;lockerr=se.read;lockstatus=wait.value;record(av,lock_sql,lockout,lockerr,lockstatus)
 end
 changed=Marshal.load(Marshal.dump(document));changed['catalog']['migrations']=changed['catalog']['migrations'][1..]
 _,err,status=sql(O.script(context.merge('expires_at'=>(Time.now.utc+120).iso8601(6)),changed,root:C['root']),failure:true)
 check('actual changed source catalog refuses before durable changes',!status.success?&&err.include?('restore_stop_source_catalog_changed')&&state==initial)
 [['expired input',{'expires_at'=>(Time.now.utc-1).iso8601}],['null reason',{'reason'=>nil}],['invalid target',{'target'=>'production-live'}],['invalid digest',{'archive_sha256'=>'missing'}]].each do |name,override|
  _,_,status=sql(build.call(override),failure:true);check('actual '+name+' cannot publish authority or capsule',!status.success?&&state==initial)
 end
 helper_av=['docker','exec','-i',C['target'],'psql','-w','-XqAt','-h','/run/collect','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1']
 response=O.execute(helper_av,build.call,error_path:File.join(P,'actual-owner-helper.log'));File.write(File.join(P,'actual-owner-stop.json'),JSON.pretty_generate(response)+"\n")
 check('actual ordinary helper invocation commits owner receipt',response['session_owner']=='postgres'&&response['resume_required']&&response['financial_action']==false&&response['send_action']==false)
 new_event=js("SELECT to_jsonb(original_key) FROM collect_recovery_restore.stop_items WHERE restore_id=#{q(context['restore_id'])}::uuid AND family='new_flag_realtime_event';")
 check('actual helper source resolved tools and query binding unchanged after owner execution',O.tooling(C['root'])==tooling)
 check('unchanged exact producer OID prosrc owner ACL',js(producer_query)==source_producers)
 check('exact one new binding and flag invalidation row causally bound',js("SELECT jsonb_build_object('binding',(SELECT count(*)FROM collect_recovery_restore.stop_items WHERE restore_id=#{q(context['restore_id'])}::uuid AND family='new_worker_configuration_binding'),'event',(SELECT count(*)FROM collect_recovery_restore.stop_items WHERE restore_id=#{q(context['restore_id'])}::uuid AND family='new_flag_realtime_event'),'area',(SELECT area FROM public.app_realtime_events WHERE id=#{q(new_event)}::uuid));")=={'binding'=>1,'event'=>1,'area'=>'feature_flags'})
 check('new configuration binding exact revision payload bytes metadata and logical digest',js("SELECT jsonb_build_object('revision',b.original_key=c.revision::text,'payload',b.payload_sha256=encode(extensions.digest(convert_to(h.configuration::text,'UTF8'),'sha256'),'hex'),'bytes',b.payload_bytes=octet_length(convert_to(h.configuration::text,'UTF8')),'metadata',b.metadata_sha256=collect_receipt_worker_history.sha(to_jsonb(h)-'configuration'),'logical',b.logical_sha256=collect_receipt_worker_history.sha(to_jsonb(h)))FROM collect_receipt_worker_history.bindings b JOIN collect_ops.receipt_worker_configuration_history h ON h.revision::text=b.original_key CROSS JOIN collect_ops.receipt_worker_configuration c WHERE b.family='worker_configuration'AND b.original_key=c.revision::text;")==%w[revision payload bytes metadata logical].to_h{|k|[k,true]})
 check('both exact named cron IDs metadata preserved and inactive',js("SELECT to_jsonb(bool_and((i.prior_metadata-'active')=(i.after_metadata-'active')AND(i.after_metadata->>'active')::boolean=false))FROM collect_recovery_restore.stop_items i WHERE restore_id=#{q(context['restore_id'])}::uuid AND family='cron_job';")==true)
 check('every pre-existing financial/Auth/business/history and invalidation UUID row plus key metadata preserved',fingerprint(worker_revision,flag_revision,new_event)==before_rows)
 lookup_from=Time.now.utc;new_lookup=sj("public.get_receipt_exception_worker_request_v1(#{q(cold['key'])})");lookup_until=Time.now.utc
 File.write(File.join(P,'cold-original-lookup-before-after.json'),JSON.pretty_generate({'original'=>old_lookup,'after'=>new_lookup,'permitted_current_sample_fields'=>%w[checked_at sample_valid_until],'clock_from'=>lookup_from.iso8601(6),'clock_until'=>lookup_until.iso8601(6)})+"\n")
 check('cold original worker UUID all original envelope and immutable receipt exact with fresh documented clocks',retained_lookup(new_lookup,old_lookup,lookup_from,lookup_until))
 stopped=state
 check('all execution controls inactive without financial or completion claim',stopped['policy']['mode']=='Paused'&&stopped['policy']['emergency_stop']&&!stopped['policy']['catchup_enabled']&&!stopped['worker']['enabled']&&!stopped['history']['enabled']&&!stopped['successor']['enabled']&&!stopped['telemetry']['enabled']&&!stopped['flag']['enabled'])
 check('genuine database-owner governed flag event and exact new worker config history',js("SELECT jsonb_build_object('event',EXISTS(SELECT 1 FROM collect_security.runtime_control_events WHERE family='feature_flags'AND revision=#{flag_revision+1} AND authority='database_owner'AND actor_id IS NULL AND session_id IS NULL),'history',(SELECT configuration=to_jsonb(c)-'singleton'FROM collect_ops.receipt_worker_configuration_history h CROSS JOIN collect_ops.receipt_worker_configuration c WHERE h.revision=c.revision));")=={'event'=>true,'history'=>true})
 File.write(File.join(P,'exact-owner-input.json'),JSON.pretty_generate(context)+"\n")
 # Commit succeeds, then the actual helper times out waiting on an appended read-only response delay.
 # This is an injected post-COMMIT communication failure; no second business delta is introduced.
 lost=false
 begin
  O.execute(helper_av,build.call+"SELECT pg_sleep(90);\n",error_path:File.join(P,'actual-owner-lost-response.log'))
 rescue O::Error=>error
  lost=error.message.include?('timed out')
 end
 check('actual owner response timeout claims no success while exact committed stop remains',lost&&state==stopped)
 replay=O.execute(helper_av,build.call,error_path:File.join(P,'actual-owner-replay.log'));check('commit-before-response exact original UUID replay no duplicate revisions',replay==response&&state==stopped)
 # Strengthen only the private guard to ALWAYS inside a rollback-only metadata drift fixture.
 # Original/global immutable triggers are neither disabled nor changed.
 _,err,status=sql("BEGIN;ALTER TABLE collect_recovery_restore.stops ENABLE ALWAYS TRIGGER stop_owner_insert;"+build.call,failure:true)
 check('exact private trigger enabled-state drift refuses replay and rolls back without guard bypass',!status.success?&&err.include?('restore_stop_replay_conflict')&&state==stopped&&O.execute(helper_av,build.call,error_path:File.join(P,'actual-owner-after-private-drift.log'))==response)
 # These changes affect only target-private catalog metadata inside a rollback-only transaction.
 # No original immutable trigger is bypassed and no API ACL is added.
 [
  ['column collation','ALTER TABLE collect_recovery_restore.stops ALTER COLUMN session_owner TYPE text COLLATE "C" USING session_owner::text;'],
  ['column default',"ALTER TABLE collect_recovery_restore.stops ALTER COLUMN effective_owner SET DEFAULT 'postgres';"],
  ['index storage definition','ALTER INDEX collect_recovery_restore.stops_pkey SET (fillfactor=75);'],
  ['namespace owner ACL','REVOKE CREATE ON SCHEMA collect_recovery_restore FROM postgres;']
 ].each do |name,definition|
  _,err,status=sql('BEGIN;'+definition+build.call,failure:true)
  check('exact private '+name+' drift refuses replay and rolls back',!status.success?&&err.include?('restore_stop_replay_conflict')&&state==stopped&&O.execute(helper_av,build.call,error_path:File.join(P,'actual-owner-after-'+name.gsub(' ','-')+'-drift.log'))==response)
 end
 _,_,bad=sql(build.call('reason'=>'Conflicting second stop reason'),failure:true);check('original UUID conflict refuses without duplicate configuration',!bad.success?&&state==stopped)
 operation="public.receipt_operations_execute_v2(#{q(principal)},#{q(uid)},#{q(ident['key'])},#{q('a'*64)},clock_timestamp(),'begin_run','{}'::jsonb)"
 [operation,gateway('gateway_dispatch_grant_v2',device,{}),gateway('gateway_receipt_successor_grant_v1',device,{}),gateway('gateway_arm_dispatch_v2',device,primary_arm),gateway('gateway_receipt_successor_arm_v1',device,successor_arm)].each do |expr|
  _,err,status=service(expr,failure:true)
  arm=expr.start_with?('public.gateway_arm_dispatch_v2(','public.gateway_receipt_successor_arm_v1(')
  refusal=arm ? err.include?('55000')&&err.include?('operations_run_fenced') : err.include?('42501')
  check('old revoked authority denied by actual '+expr.split('(').first,!status.success?&&refusal)
 end
 check('worker and history schedulers inactive without new execution',js('SELECT collect_ops.run_receipt_exception_schedule();')['status']=='inactive'&&js('SELECT collect_receipt_worker_history.run_schedule();')['status']=='inactive')
 [['primary',primary,primary_plan,'gateway_callback_v2'],['successor',successor,successor_plan,'gateway_receipt_successor_callback_v1']].each do |family,g,plan,name|
  callbacks=[]
  plan.each do|cb|
   payload={'callback_id'=>cb['sent_callback_id'],'attempt_id'=>g['attempt_id'],'fence_version'=>g['fence_version'],'segment_index'=>cb['segment_index'],'segment_count'=>g['segment_count'],'body_sha256'=>g['body_sha256'],'destination_sha256'=>g['destination_sha256'],'callback_kind'=>'sent','result_code'=>-1,'tp_status'=>nil,'occurred_at'=>Time.now.utc.iso8601(6)}
   payload['route']=g['route']if family=='successor';expr=gateway(name,device,payload);observed=sj(expr);callbacks<<observed
   check('authenticated late '+family+' callback original UUID replay retains evidence',sj(expr)['state']==observed['state'])
  end
  check('late '+family+' multipart framework observations preserve no carrier proof',callbacks.last['state']=='observed_sent'&&callbacks.last['carrier_proof']==false)
  cb=plan.first;payload={'callback_id'=>cb['sent_callback_id'],'attempt_id'=>g['attempt_id'],'fence_version'=>g['fence_version'],'segment_index'=>cb['segment_index'],'segment_count'=>g['segment_count'],'body_sha256'=>g['body_sha256'],'destination_sha256'=>g['destination_sha256'],'callback_kind'=>'sent','result_code'=>1,'tp_status'=>nil,'occurred_at'=>Time.now.utc.iso8601(6)};payload['route']=g['route']if family=='successor'
  contradiction=sj(gateway(name,device,payload));check('late '+family+' contradictory observation remains uncertain after stop',contradiction['state']=='uncertain'&&contradiction['carrier_proof']==false)
 end
 old_receipt=js("SELECT to_jsonb(s)FROM collect_recovery_restore.stops s WHERE restore_id=#{q(context['restore_id'])}::uuid;")
 before_phase=process_phase('before-postmaster-restart')
 before_restart=js('SELECT to_jsonb(pg_postmaster_start_time());')
 av=[C['docker'],'exec','-i',C['target'],'sh','-c',"su postgres -s /bin/sh -c 'pg_ctl -D /var/lib/postgresql/collect-rehearsal/data -m fast -w restart'"]
 out,err,status=Open3.capture3(*av);record(av,'same target/data postmaster restart',out,err,status)
 raise 'same-target postmaster restart failed '+err unless status.success?
 check('durable stop and immutable receipt survive same-target postmaster restart',js('SELECT to_jsonb(pg_postmaster_start_time());')!=before_restart&&state==stopped&&js("SELECT to_jsonb(s)FROM collect_recovery_restore.stops s WHERE restore_id=#{q(context['restore_id'])}::uuid;")==old_receipt)
 after_phase=process_phase('after-postmaster-restart')
 check('same owned container host PID1 OS postgres and PGDATA across distinct restarted postmaster PID',before_phase['container_running']&&after_phase['container_running']&&%w[target_id target_name host_pid1 postmaster_uid pgdata].all?{|key|before_phase[key]==after_phase[key]}&&before_phase['postmaster_uid']==before_phase['expected_postmaster_uid']&&before_phase['postmaster_pid']!=after_phase['postmaster_pid'])
 restart_lookup_from=Time.now.utc;restart_lookup=sj("public.get_receipt_exception_worker_request_v1(#{q(cold['key'])})");restart_lookup_until=Time.now.utc
 File.write(File.join(P,'cold-original-restart-lookup.json'),JSON.pretty_generate({'original'=>old_lookup,'after_restart'=>restart_lookup,'clock_from'=>restart_lookup_from.iso8601(6),'clock_until'=>restart_lookup_until.iso8601(6)})+"\n")
 check('original UUID replay and cold reconstruction remain exact after same-target restart',O.execute(helper_av,build.call,error_path:File.join(P,'actual-owner-restart-replay.log'))==response&&retained_lookup(restart_lookup,old_lookup,restart_lookup_from,restart_lookup_until))

 %w[anon authenticated service_role].each do|role|
  _,_,status=sql("BEGIN;SET LOCAL ROLE #{role};SELECT *FROM collect_recovery_restore.stops;",failure:true);check('actual '+role+' cannot access private owner capsule',!status.success?)
 end
 ["UPDATE collect_recovery_restore.stops SET reason_sha256=repeat('a',64);","DELETE FROM collect_recovery_restore.stop_items;","TRUNCATE collect_recovery_restore.stops CASCADE;","UPDATE collect_gateway.devices SET state='active',revoked_at=NULL WHERE id=#{q(device)};","UPDATE collect_supervisor.identities SET state='active',revoked_at=NULL WHERE id=#{q(principal)};"].each do|expr|
  _,_,status=sql(expr,failure:true);check('owner cannot rewrite capsule or reactivate original keys',!status.success?)
 end
 R['status']='passed'
rescue Exception=>e;R['status']='failed';R['error']=e.message;raise
ensure;save;end
