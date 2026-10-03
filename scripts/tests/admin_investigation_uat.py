#!/usr/bin/env python3
"""Current investigation/email/scope reads in an isolated schema153 subset."""
import argparse,datetime,hashlib,json,pathlib,uuid
import collect_admin_combined_upgrade_uat as c
u=c.u;f=c.foundation;ROOT=u.ROOT
STAGES=['supabase/migrations/20260930213000_operator_email_auth.sql',
 'supabase/migrations/20260930230100_receipt_backlog_events.sql',
 'supabase/migrations/20260930230300_admin_transaction_lifecycle.sql',
 'supabase/migrations/20260930230400_admin_investigation.sql']
def quote(value):return "'"+str(value).replace("'","''")+"'"
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 report=pathlib.Path(args.report_dir).resolve();assert not report.exists();report.mkdir(parents=True)
 evidence={'kind':'current_investigation_email_scope_schema153_subset','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'production_written':False,'shared_source_written':False,'source_rows_copied':False,'provider_called':False,'carrier_called':False,'otp_sent':False,'signed_jwt_tested':False,'clean_install_tested':False,'hosted124_upgrade_tested':False,'cases':[]}
 def save():(report/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def case(name,fn):
  value=fn();evidence['cases'].append({'name':name,'status':'pass','detail':value});save();print('PASS '+name,flush=True);return value
 db='collect_investigation_'+uuid.uuid4().hex[:12];made=False
 u.SQL_LOG=report/'queries.log';f.RAW_QUERY_LOG=report/'queries.sql'
 try:
  labels=json.loads(u.command([u.DOCKER,'inspect',u.CONTAINER,'--format','{{json .Config.Labels}}']).stdout)
  ports=json.loads(u.command([u.DOCKER,'inspect',u.CONTAINER,'--format','{{json .HostConfig.PortBindings}}']).stdout)
  assert labels['com.supabase.cli.project']==u.PROJECT and labels['com.docker.compose.project']==u.PROJECT and all(x['HostPort']=='55722' for x in ports['5432/tcp'])
  assert json.loads(u.psql('postgres',"select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'));").stdout)=={'cron':'off','net':'0'}
  evidence['local_container_guard']={'project':u.PROJECT,'port':'55722','cron':'off','net':'0'}
  dump=(c.BASELINE/'schema-only.sql').read_bytes();acl=(c.BASELINE/'api-acl.sql').read_bytes();assert c.sha(dump)==c.DUMP_HASH and c.sha(acl)==c.ACL_HASH
  prior=json.loads((c.BASELINE/'result.json').read_text());assert prior['source_metadata']==prior['source_metadata_after_dump']=={'count':153,'latest':'20260930220000','cron':'off','net':'0'}
  bodies={p:(ROOT/p).read_bytes() for p in STAGES};evidence['source_sha256']={p:c.sha(data)for p,data in bodies.items()};evidence['runner_sha256']=c.sha(pathlib.Path(__file__).read_bytes())
  evidence['baseline']={'captured_migration_count':153,'dump_sha256':c.DUMP_HASH,'acl_sha256':c.ACL_HASH,'metadata_before_and_after_capture':prior['source_metadata'],'authority_prerequisite':prior['authority_prerequisite'],'known_extra_migration_parity':prior['known_extra_migration_parity'],'source':'Retained attempt8 schema-only capture; no shared rows copied or fresh dump','owners_normalized':True,'excluded_runtime':['pg_cron','pg_net','pg_graphql','pg_stat_statements'],'not_attested':'Registry source parity is not universal deployed-function body attestation'};evidence['database']=db
  (report/'prerequisite-parity.json').write_text(json.dumps(evidence['baseline'],indent=2)+'\n')
  (report/'api-acl.sql').write_bytes(acl)
  u.psql('postgres','create database '+db+' template template0;');made=True
  restore=u.psql(db,'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+dump.decode()+acl.decode(),False)
  (report/'restore.log').write_text(restore.stdout+restore.stderr);assert restore.returncode==0,restore.stderr[-3000:]
  # Seed the existing identity/group/consent scaffold without a payment: first
  # exercise the empty investigation surface before any financial posting.
  original=f.payment_sql
  try:f.payment_sql=lambda *args,**kwargs:'';f.seed(db)
  finally:f.payment_sql=original
  empty=f.business_fingerprint(db);evidence['empty_business_before_install']=empty
  for path,body in bodies.items():
   installed=u.psql(db,body.decode(),False);(report/(pathlib.Path(path).stem+'.install.log')).write_text(installed.stdout+installed.stderr);assert installed.returncode==0,installed.stderr[-4000:]
   case(path+' preserves empty canonical business tables',lambda:f.equal(empty,f.business_fingerprint(db)))
  run_cases(db,case,evidence,report)
  evidence['source_after_sha256']={p:c.sha((ROOT/p).read_bytes())for p in STAGES};assert evidence['source_after_sha256']==evidence['source_sha256'],'Selected source changed during UAT'
  evidence['status']='pass'
 except Exception as error:evidence['status']='failed';evidence['failure']=str(error);save();raise
 finally:
  if made:evidence['isolated_database_removed']=u.psql('postgres','drop database '+db+' with(force);',False).returncode==0
  u.SQL_LOG=None;f.RAW_QUERY_LOG=None;evidence['case_count']=len(evidence['cases']);evidence['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
def run_cases(db,case,evidence,report):
 sql=lambda text:u.psql(db,text).stdout.strip();check=c.check;truth=lambda text:check(sql(text)=='t');call=lambda text:u.call(db,text)
 sql("insert into public.admin_permissions(name,description) values('payments.read','Synthetic investigation'),('admin_users.manage','Synthetic investigation');insert into public.admin_role_permissions(role_id,permission_name) select '%s',name from public.admin_permissions on conflict do nothing;"%f.ROLE)
 # Isolated owner fixture only. It represents an already verified and approved
 # email account; no bootstrap, email verification, OTP or real account occurs.
 sql("update auth.users set email='investigation-owner@collect.example',email_confirmed_at=clock_timestamp(),phone_confirmed_at=null where id='%s';insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason) values('%s','investigation-owner@collect.example',clock_timestamp()-interval '2 minutes','Synthetic already-approved email owner');"%(u.UID,u.UID))
 mode=call("select public.admin_set_operator_email_mode_v1('Synthetic investigation email-only fixture');")
 case('current shared authority accepts verified email owner without phone confirmation',lambda:check(mode['mode']=='email' and sql("select phone_confirmed_at is null from auth.users where id='%s';"%u.UID)=='t'))
 def get(kind,identifier):return call("select public.admin_get_collect_investigation_v1('%s','%s');"%(kind,identifier))
 absent=get('transaction',str(uuid.uuid4()));(report/'observed-empty.json').write_text(json.dumps(absent,indent=2)+'\n')
 case('empty investigation target returns missing sections without invented data',lambda:check(absent['scope']=='unclassified' and absent['payment_state']=='missing' and absent['receipt_state']=='missing' and absent['payment'] is None and absent['receipt'] is None))
 phone='+250788971001';route_hash=hashlib.sha256(phone.encode()).hexdigest()
 sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network) values('%s','%s','%s','%s','mtn_momo');"%(f.GROUP,u.UID,phone,route_hash))
 def ids(n):return tuple('99760000-0000-4000-8000-%012d'%(base+n)for base in(10000,20000,30000))
 def observation(n,amount=300,posted=False,parsed=True,parse='parsed',mobile=True,network='mtn_momo',currency='RWF',direction='incoming',raw_hash=route_hash,event_hash=route_hash,event_user=u.UID,raw_user=u.UID,collection=f.GROUP):
  raw,event,payment=ids(n);reference='INVESTIGATION-%02d'%n;collection_sql='null'if collection is None else quote(collection)
  text="insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device,ingested_at) values('%s',%s,'%s','M-Money','Protected synthetic observation %d',encode(extensions.digest('investigation-body-%d','sha256'),'hex'),'%s','%s',clock_timestamp()-interval '1 day',clock_timestamp());"%(raw,collection_sql,raw_user,n,n,raw_hash,parse)
  if parsed:
   text+="insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name,created_at) values('%s','%s',%s,'%s',%s,'%s','%s','%s','%s',%d,'%s','unallocated','Protected synthetic payer',clock_timestamp());"%(event,raw,collection_sql,event_user,'true'if mobile else'false',network,currency,direction,event_hash,amount,reference)
   if posted:text+=f.payment_sql(payment,amount=amount,ref=reference,parsed=event).replace("repeat('a',64)",quote(route_hash))
  sql(f.service(text));return raw,event,payment
 observation(1,300,posted=True);observation(2,500,posted=True)
 observation(3,parsed=False,parse='failed');observation(4,parsed=False,parse='pending')
 observation(5,parsed=False,parse='pending',raw_hash='f'*64)
 observation(6,mobile=False);observation(7,network='unknown',currency='unknown',direction='unknown');observation(8,direction='outgoing');observation(9,event_user=u.OTHER)
 observation(10,event_hash='f'*64);observation(11,network='airtel_money')
 wallet='0788971002';wallet_hash=hashlib.sha256(('+250'+wallet[1:]).encode()).hexdigest()
 sql("update public.profiles set country_code='RW',currency_code='RWF',momo_number='%s',momo_number_hash='%s',momo_provider='mtn_momo',momo_number_verified_at=clock_timestamp() where id='%s';"%(wallet,wallet_hash,u.OTHER))
 observation(12,parsed=False,parse='pending',raw_user=u.OTHER,raw_hash=wallet_hash,collection=None)
 baseline=f.business_fingerprint(db);evidence['populated_business_baseline']=baseline
 first=get('transaction',ids(1)[0]);(report/'observed-posted-transaction.json').write_text(json.dumps(first,indent=2)+'\n')
 receipt_id=sql("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';"%ids(1)[2]);receipt=get('receipt',receipt_id);(report/'observed-posted-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 case('actual posted transaction exposes separately authorized payment and receipt evidence',lambda:check(first['scope']=='rwanda_momo' and first['payment_state']==first['receipt_state']=='available' and first['payment']['lifecycle']['verification']=='confirmation_recorded' and first['payment']['lifecycle']['ledger']=='posted' and first['payment']['lifecycle']['notification']=='queued'))
 case('receipt reconstruction is explicitly bound to matching immutable posting snapshot',lambda:check(receipt['receipt']['preview_source']=='immutable_posting_snapshot' and receipt['receipt']['masked_snapshot_preview'] is not None and receipt['receipt']['snapshot_captured_at'] is not None))
 case('historical receipt balance remains300 while separately updated current balance is800',lambda:check(receipt['receipt']['member_balance_rwf']==receipt['receipt']['group_balance_rwf']=='300' and receipt['payment']['current_balances']['member_rwf']==receipt['payment']['current_balances']['group_rwf']=='800' and receipt['payment']['current_balances']['group_updated_at'] is not None))
 case('actual event and posting times stay distinct from observation read time',lambda:check(first['payment']['times']['received_at_device']<first['payment']['times']['ingested_at'] and first['payment']['times']['parsed_recorded_at']is not None and first['payment']['times']['allocation_recorded_at']is None and first['payment']['times']['provider_confirmed_at']is not None and first['payment']['times']['payment_posted_at']is not None))
 case('actual journal and receipt snapshot values match canonical posting',lambda:check(len(first['payment']['journals'])==1 and first['payment']['journals'][0]['amount_rwf']=='300' and first['payment']['journals'][0]['snapshot']['delta_rwf']=='300'))
 denied_keys={'message_body','destination_e164','body_sha256','destination_sha256','claim_token','claimed_by','operator_user_id','worker_id','evidence_reference','outcome_note','reference','sender_name','raw_body'}
 def redacted(value):
  if isinstance(value,dict):return not(set(value)&denied_keys)and all(redacted(x)for x in value.values())
  if isinstance(value,list):return all(redacted(x)for x in value)
  return True
 case('investigation exposes no stored body hashes credentials reference or operator identity',lambda:check(redacted(first)and 'Protected synthetic'not in json.dumps(first)and phone not in json.dumps(first)and 'INVESTIGATION-01'not in json.dumps(first)))
 for n,label in [(3,'known route parse failure'),(4,'known route pending parse'),(12,'verified matching Rwanda profile wallet')]:
  value=get('transaction',ids(n)[0]);case(label+' retains supported observation without invented posting',lambda value=value:check(value['scope']=='rwanda_momo'and value['payment_state']=='available'and value['payment']['lifecycle']['ledger']=='not_posted'and value['receipt_state']=='missing'))
 for n,label in [(5,'unknown receiving hash'),(6,'nonpayment parsed event'),(7,'unknown network currency and direction'),(8,'outgoing event'),(9,'cross-receiver user'),(10,'mismatched parsed receiving hash'),(11,'mismatched parsed receiving provider')]:
  value=get('transaction',ids(n)[0]);case(label+' is unclassified and exposes no section data',lambda value=value:check(value['scope']=='unclassified'and value['payment_state']==value['receipt_state']=='unsupported'and value['payment']is None and value['receipt']is None))
 supported_list=call('select public.admin_list_collect_transactions();');case('current transaction list includes only known route/wallet observations',lambda:check(supported_list['total']==5 and {r['raw_sms_id']for r in supported_list['rows']}=={ids(n)[0]for n in[1,2,3,4,12]}))
 for role in['anon','service_role']:case(role+' cannot call investigation read',lambda role=role:u.expected_error(db,"select public.admin_get_collect_investigation_v1('transaction','%s');"%ids(1)[0],'42501',role=role))
 for signature in['collect_security.rwanda_sms_scope(uuid)','collect_security.transaction_lifecycle(uuid,boolean)','collect_security.transaction_read_authority(text)']:
  case('private helper is unavailable to API roles: '+signature,lambda signature=signature:truth("select bool_and(not has_function_privilege(role,%s,'execute')) from unnest(array['anon','authenticated','service_role'])role;"%quote(signature)))
 for table in['sms_notification_outbox','sms_notification_confirmations','sms_notification_attempts','momo_journal_entries','momo_balance_snapshots','member_balances','collection_balances']:
  case('private source table has RLS and no direct authenticated grant: '+table,lambda table=table:truth("select c.relrowsecurity and not has_table_privilege('authenticated',c.oid,'select') from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='collect_hybrid'and c.relname=%s;"%quote(table)))
 for args in["null,'%s'"%ids(1)[0],"'unsafe','%s'"%ids(1)[0],"'transaction',null"]:case('invalid investigation target '+args,lambda args=args:u.expected_error(db,'select public.admin_get_collect_investigation_v1('+args+');','22023','investigation_target_invalid'))
 def altered(mutation,kind='transaction',identifier=ids(1)[0]):return json.loads(sql('begin;'+mutation+u.auth()+"select public.admin_get_collect_investigation_v1('%s','%s');rollback;"%(kind,identifier)).splitlines()[-1])
 def denied(mutation,kind='transaction',identifier=ids(1)[0]):
  r=u.psql(db,'begin;'+mutation+u.auth()+"select public.admin_get_collect_investigation_v1('%s','%s');rollback;"%(kind,identifier),False);return check(r.returncode!=0 and '42501:'in r.stderr)
 no_notice="delete from public.admin_role_permissions where role_id='%s'and permission_name='notifications.read';"%f.ROLE
 value=altered(no_notice);case('transaction payment authority works independently from denied receipt read',lambda:check(value['payment_state']=='available'and value['receipt_state']=='denied'and value['receipt']is None and value['payment']['lifecycle']['notification']=='access_required'))
 no_payment="delete from public.admin_role_permissions where role_id='%s'and permission_name='payments.read';"%f.ROLE
 value=altered(no_payment,'receipt',receipt_id);case('receipt read works independently while current balances and payment journal are denied',lambda:check(value['receipt_state']=='available'and value['payment_state']=='denied'and value['payment']is None and value['receipt']['masked_snapshot_preview']is not None))
 case('receipt target still requires receipt authority',lambda:denied(no_notice,'receipt',receipt_id))
 case('transaction target still requires payment authority',lambda:denied(no_payment))
 for label,mutation in[
  ('email approval revoked',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='%s';"%u.UID),
  ('email unverified',"update auth.users set email_confirmed_at=null where id='%s';"%u.UID),
  ('email changed',"update auth.users set email='different@collect.example'where id='%s';"%u.UID),
  ('role grant revoked',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='%s';"%u.UID),
  ('session expired',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='%s';"%u.SID),
 ]:case('current email authority denies '+label,lambda mutation=mutation:denied(mutation))
 wallet_unverified="update public.profiles set momo_number_verified_at=null where id='%s';"%u.OTHER
 case('unverified fallback wallet cannot classify pending raw as Rwanda',lambda:check(altered(wallet_unverified,identifier=ids(12)[0])['scope']=='unclassified'))
 case('clean and populated investigation reads leave sixteen business fingerprints unchanged',lambda:f.equal(baseline,f.business_fingerprint(db)))
 # Fault injection is isolated and rolled back. It must hide reconstructed
 # content when the claimed snapshot no longer matches immutable source.
 fault="alter table collect_hybrid.sms_notification_outbox disable trigger user;update collect_hybrid.sms_notification_outbox set member_balance_rwf=member_balance_rwf+1 where id='%s';"%receipt_id
 value=altered(fault,'receipt',receipt_id);case('mismatched snapshot values refuse preview reconstruction',lambda:check(value['receipt']['preview_source']=='snapshot_unavailable'and value['receipt']['masked_snapshot_preview']is None and value['receipt']['snapshot_captured_at']is None))
 case('snapshot fault injection restores every business byte',lambda:f.equal(baseline,f.business_fingerprint(db)))
 reversal=call("select public.admin_reverse_momo_payment('%s','Synthetic investigation reversal','%s');"%(ids(1)[2],uuid.uuid4()))
 reversed_value=get('transaction',ids(1)[0]);(report/'observed-reversed-transaction.json').write_text(json.dumps(reversed_value,indent=2)+'\n')
 case('compensating reversal yields two actual journals while retaining original receipt snapshot',lambda:check(reversal['ok']and reversed_value['payment']['lifecycle']['ledger']=='reversed'and len(reversed_value['payment']['journals'])==2 and reversed_value['receipt']['member_balance_rwf']=='300'and reversed_value['payment']['current_balances']['member_rwf']=='500'))
 # A real server pre-send attempt is a fixture only, never a carrier action.
 sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
 service=lambda text:json.loads(sql(f.service(text)).splitlines()[-1]);job2=sql("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';"%ids(2)[2])
 claim=service("select public.collect_claim_receipt('%s','%s','investigation-synthetic-worker','%s');"%(u.UID,job2,uuid.uuid4()))
 exact=service("select public.collect_get_claimed_receipt('%s','%s','%s',%d);"%(u.UID,job2,claim['claim_token'],claim['fence_version']))
 approval=str(uuid.uuid4());service("select public.collect_confirm_receipt('%s','%s','%s',%d,%d,'%s','%s');"%(u.UID,job2,claim['claim_token'],claim['fence_version'],exact['destination_revision'],exact['body_sha256'],approval))
 attempt=service("select public.collect_record_send_start('%s','%s','%s',%d,'%s');"%(u.UID,job2,claim['claim_token'],claim['fence_version'],approval))
 # Synthetic historical rows test the bounded read; they do not attest sixty
 # actual sends or approvals. Every inserted record is confined to this DB.
 history="""do $$declare n integer;confirmation uuid;token uuid;begin for n in 2..61 loop
 confirmation:=gen_random_uuid();token:=gen_random_uuid();insert into collect_hybrid.sms_notification_confirmations select(jsonb_populate_record(null::collect_hybrid.sms_notification_confirmations,to_jsonb(c)||jsonb_build_object('id',confirmation,'claim_token',token,'fence_version',n,'approved_at',clock_timestamp()-n*interval '1 second','expires_at',clock_timestamp()+interval '1 hour','consumed_at',null))).* from collect_hybrid.sms_notification_confirmations c where c.id='%s';
 insert into collect_hybrid.sms_notification_attempts select(jsonb_populate_record(null::collect_hybrid.sms_notification_attempts,to_jsonb(a)||jsonb_build_object('id',gen_random_uuid(),'confirmation_id',confirmation,'claim_token',token,'fence_version',n,'attempt_number',n,'state','uncertain','outcome_at',clock_timestamp(),'evidence_reference','synthetic bounded history','outcome_note','No carrier called'))).* from collect_hybrid.sms_notification_attempts a where a.id='%s';end loop;end$$;"""%(approval,attempt['attempt_id'])
 sql(history.replace('in2..61','in 2..61'));sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
 (report/'synthetic-history.sql').write_text('-- Local bounded-history fixture; no approval or send attestation.\n'+history.replace('in2..61','in 2..61')+'\n')
 histories=get('receipt',job2);(report/'observed-bounded-history.json').write_text(json.dumps(histories,indent=2)+'\n')
 case('approval and attempt history bounds retain50 rows with exact61 totals',lambda:check(histories['history_limit']==50 and histories['receipt']['approval_total']==histories['receipt']['attempt_total']==61 and len(histories['receipt']['approvals'])==len(histories['receipt']['attempts'])==50))
 case('latest bounded histories are deterministic and preserve actual timestamps',lambda:check(histories['receipt']['attempts'][0]['attempt_number']==61 and histories['receipt']['attempts'][-1]['attempt_number']==12 and all(a['approved_at']is not None and a['expires_at']is not None for a in histories['receipt']['approvals'])))
 case('bounded approval and attempt rows expose only approved safe fields',lambda:check(all(set(a)=={'id','approved_at','expires_at','consumed_at'}for a in histories['receipt']['approvals'])and all(set(a)=={'id','attempt_number','state','send_started_at','outcome_at'}for a in histories['receipt']['attempts'])and redacted(histories)))
 final=f.business_fingerprint(db);get('receipt',job2);get('transaction',ids(2)[0]);case('bounded history reads cannot modify populated source evidence',lambda:f.equal(final,f.business_fingerprint(db)))
 case('all nonempty receipt/reversal journals retain exactly balanced canonical lines',lambda:truth("select not exists(select 1 from collect_hybrid.momo_journal_entries e left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=e.id group by e.id,e.amount_rwf having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else-l.amount_rwf end)<>0);"))
 evidence['final_business_fingerprints']=f.business_fingerprint(db);evidence['limits']=['Current four-migration subset on retained schema153; no clean install or full hosted124 upgrade','Synthetic already-approved verified email owner; no OTP/bootstrap/live identity provision or signed JWT','Historical approval/attempt rows are explicit local bounds fixtures, not actual approval/send evidence','No provider/carrier/Android callback or live performance acceptance','Preview is a masked snapshot reconstruction, not stored original message or current balance']
if __name__=='__main__':main()
