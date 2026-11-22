from pathlib import Path
import hashlib,json,re,subprocess,sys
# Build only: execution requires the separate disposable, fenced PG harness.
# Do not point this generator at a live database or overwrite retained evidence.
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
if len(sys.argv)!=2:raise SystemExit('usage: records-query-build.py <new-output-sql-path>')
source=(ROOT/'supabase/tests/burimunsi/source-scope-contract.sql').read_text()
setup=source[:source.index("SELECT pg_temp.source_capture('source-contract-complete-a'")].replace('__SOURCE_FUNCTIONS__','')
support=(ROOT/'supabase/tests/burimunsi/gateway-handoff-support.sql').read_text()
helper=support[support.index('CREATE FUNCTION pg_temp.h_seed_financial_storage'):support.index('-- Initial disabled scope')]
captured=json.loads(subprocess.run(['node',str(HERE/'records-query-capture.mjs')],capture_output=True,text=True,check=True).stdout)
def literal(v):
 if v is None:return 'NULL'
 if isinstance(v,int) and not isinstance(v,bool):return str(v)
 if isinstance(v,str):return "'"+v.replace("'","''")+"'"
 raise TypeError(type(v))
def bind(q):
 args=q['args'];return re.sub(r'\$(\d+)',lambda m:literal(args[int(m.group(1))-1]),q['text'])
expected={'all':[1,2,3,4,6,7,8,20,21,22,23],'payer':[1],'payer_phone':[1],'reference':[1],'amount':[1],
 'date':[1,2,3,4,6,7,8,20,21,22,23],'member_name':[1,2,20,21,22],'member_local':[1,2,20,21,22],'member_e164':[1,2,20,21,22],'other_member_name':[],
 'literal_percent':[2],'literal_underscore':[6],'literal_slash':[],'allocated':[1,6,7],
 'unallocated':[4],'processing':[2,20,21,22,23],'member_a':[1,2,20,21,22],'member_b':[3,6,7,8],'other':[5],'other_member':[5]}
assert set(expected)=={c['name'] for c in captured['cases']}
parts=[]
for c in captured['cases']:
 ids=['query-tx-'+str(i) for i in expected[c['name']]]
 array='ARRAY['+','.join(literal(x) for x in sorted(ids))+']::text[]' if ids else 'ARRAY[]::text[]'
 parts.append("SELECT set_config('burimunsi.collection_id',"+literal(c['groupId'])+",true);")
 parts.append("DO $test$ DECLARE ids text[]; n bigint; BEGIN SELECT coalesce(array_agg(z.id ORDER BY z.id),ARRAY[]::text[]) INTO ids FROM ("+bind(c['page'])+") z; SELECT countrow.total INTO n FROM ("+bind(c['count'])+") countrow; IF ids IS DISTINCT FROM "+array+" OR n<>"+str(len(ids))+" THEN RAISE EXCEPTION 'Payment qualification "+c['name']+" got %, count %',ids,n; END IF; END $test$;")
other=next(c for c in captured['cases'] if c['name']=='other')
parts.append("SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);")
parts.append("DO $test$ BEGIN IF EXISTS(SELECT 1 FROM ("+bind(other['page'])+") z) THEN RAISE EXCEPTION 'cross-group RLS escape'; END IF; END $test$;")
a=next(c for c in captured['cases'] if c['name']=='member_a')
parts.append("DO $test$ BEGIN IF NOT EXISTS(SELECT 1 FROM ("+bind(a['page'])+") z WHERE z.id='query-tx-2' AND z.member_id='f3000000-0000-4000-8000-000000000011') THEN RAISE EXCEPTION 'linked beneficiary missing'; END IF; END $test$;")
parts.append("DO $test$ DECLARE n bigint; BEGIN SELECT count(*) INTO n FROM ("+bind(a['page'])+") z WHERE id IN ('query-tx-20','query-tx-21','query-tx-22') AND ledger_posted=false; IF n<>3 THEN RAISE EXCEPTION 'missing, partial, or wrong-member contribution marked posted'; END IF; END $test$;")
allq=next(c for c in captured['cases'] if c['name']=='all')
parts.append("DO $test$ BEGIN IF NOT EXISTS(SELECT 1 FROM ("+bind(allq['page'])+") z WHERE id='query-tx-23' AND member_id IS NULL AND momo_number IS NULL AND ledger_posted=false) THEN RAISE EXCEPTION 'cross-group member attribution leaked'; END IF; END $test$;")
revision=bind(captured['revision'])
parts.append("CREATE TEMP TABLE payment_revision_before AS SELECT jsonb_agg(to_jsonb(z) ORDER BY z.id) AS value FROM ("+revision+") z;")
parts.append("RESET ROLE; UPDATE app.users SET full_name='Changed synthetic member' WHERE id='f3000000-0000-4000-8000-000000000011'; SET LOCAL ROLE collect_runtime;")
parts.append("DO $test$ DECLARE revised jsonb; BEGIN SELECT jsonb_agg(to_jsonb(z) ORDER BY z.id) INTO revised FROM ("+revision+") z; IF revised IS NOT DISTINCT FROM (SELECT value FROM payment_revision_before) THEN RAISE EXCEPTION 'member search revision did not change'; END IF; END $test$;")
parts.append('SAVEPOINT ledger_revision_only;')
parts.append("CREATE TEMP TABLE ledger_revision_before AS SELECT jsonb_agg(to_jsonb(z) ORDER BY z.id) AS value FROM ("+revision+") z;")
parts.append("RESET ROLE; INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) "
 "SELECT 'query-ledger-20',id,collection_id,member_id,amount_minor,'contribution',evidence_id,'f3000000-0000-4000-8000-000000000001',"
 "'query-ledger-request-20','2026-11-10T10:00:00Z' FROM app.payments WHERE id='query-payment-20'; SET LOCAL ROLE collect_runtime;")
parts.append("DO $test$ DECLARE revised jsonb; BEGIN SELECT jsonb_agg(to_jsonb(z) ORDER BY z.id) INTO revised FROM ("+revision+") z; IF revised IS NOT DISTINCT FROM (SELECT value FROM ledger_revision_before) THEN RAISE EXCEPTION 'ledger-only payment revision did not change'; END IF; END $test$;")
parts.append('ROLLBACK TO ledger_revision_only;')
base=[]
for n in [1,3,5,6,7,8,21,22,23]:
 g='buri-qualification-group-2' if n==5 else 'buri-qualification-group'
 base.append("SELECT set_config('burimunsi.collection_id',"+literal(g)+",true);")
 amount='1' if n==21 else 'amount_minor'
 member="'f3000000-0000-4000-8000-000000000012'" if n==22 else 'member_id'
 base.append("INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) "
  "SELECT 'query-ledger-"+str(n)+"',id,collection_id,"+member+","+amount+",'contribution',evidence_id,"
  "'f3000000-0000-4000-8000-000000000001','query-ledger-request-"+str(n)+"','2026-11-10T10:00:00Z' FROM app.payments WHERE id='query-payment-"+str(n)+"';")
home=[]
home.append("RESET ROLE; SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);")
new=[(9,'2026-11-12T10:00:00Z','Africa/Kigali'),(10,'2026-11-10T10:00:00Z','Africa/Kigali'),
 (11,'2026-11-11T16:00:00Z','Africa/Kigali'),(12,None,'Africa/Kigali'),(13,'2026-90-90T10:00:00Z','Africa/Kigali'),
 (14,'2026-11-11T09:00:00Z','Invalid/Timezone'),(15,'2026-11-11 10:00:00','Africa/Kigali'),
 (16,'2026-11-11T03:00:00Z','America/New_York'),(17,'2026-11-10T22:00:00Z','Africa/Kigali'),
 (18,'2026-11-11T22:00:00Z','Africa/Kigali'),(19,'2026-11-10T21:59:59.999Z','Africa/Kigali')]
for n,at,zone in new:
 home.append("SELECT pg_temp.query_fixture("+str(n)+",'buri-qualification-group','synthetic','***999',"
  "'f3000000-0000-4000-8000-000000000011','f3000000-0000-4000-8000-000000000011','confirmed','linked',0,"
  +literal(at)+","+literal(zone)+");")
for n in [x[0] for x in new]:
 g='buri-qualification-group'
 home.append("SELECT set_config('burimunsi.collection_id',"+literal(g)+",true);")
 home.append("INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) "
  "SELECT 'query-ledger-"+str(n)+"',id,collection_id,member_id,amount_minor,'contribution',evidence_id,"
  "'f3000000-0000-4000-8000-000000000001','query-ledger-request-"+str(n)+"','2026-11-10T10:00:00Z' FROM app.payments WHERE id='query-payment-"+str(n)+"';")
home.append("SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);")
home.append("INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) "
 "SELECT 'query-ledger-reverse-8',payment_id,collection_id,member_id,-amount_minor,'reversal',id,evidence_id,actor_user_id,'query-reverse-request-8',posted_at FROM app.ledger_entries WHERE id='query-ledger-8';")
home.append("UPDATE app.payments SET status='corrected',revision=revision+1 WHERE id='query-payment-1';")
home.append("INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) "
 "SELECT 'query-ledger-correction-1',payment_id,collection_id,member_id,-amount_minor,'correction',id,evidence_id,actor_user_id,'query-correction-request-1',posted_at FROM app.ledger_entries WHERE id='query-ledger-1';")
home.append('SET LOCAL ROLE collect_runtime;')
allocated=next(c for c in captured['cases'] if c['name']=='allocated')
home.append("DO $test$ BEGIN IF EXISTS(SELECT 1 FROM ("+bind(allocated['page'])+") q WHERE id='query-tx-1') THEN RAISE EXCEPTION 'corrected payment is allocated'; END IF; END $test$;")
assert len(captured['home'])==4
balance,today,counts,recent=[bind(q) for q in captured['home']]
expected_balance=(sum([3,6,7,22,23]+[x[0] for x in new])*11000)+1
home.append("DO $test$ DECLARE b bigint; d bigint; n bigint; a bigint; BEGIN SELECT balance INTO b FROM ("+balance+") q; SELECT today INTO d FROM ("+today+") q; SELECT unallocated,unallocated_amount INTO n,a FROM ("+counts+") q; IF b<>"+str(expected_balance)+" OR d<>330000 OR n<>1 OR a<>44000 THEN RAISE EXCEPTION 'Home balance %, today %, unallocated % %',b,d,n,a; END IF; END $test$;")
home.append("DO $test$ DECLARE ids text[]; BEGIN SELECT array_agg(id ORDER BY id) INTO ids FROM ("+recent+") q; IF ids IS DISTINCT FROM ARRAY['query-tx-16','query-tx-6','query-tx-7']::text[] OR EXISTS(SELECT 1 FROM ("+recent+") q WHERE id='query-tx-1') THEN RAISE EXCEPTION 'Home recent incorrect %',ids; END IF; END $test$;")
contract=(ROOT/'supabase/tests/burimunsi/records-query-contract.sql').read_text()
contract=contract.replace('__SOURCE_SETUP__',setup).replace('__FINANCIAL_STORAGE_HELPER__',helper).replace('__BASE_LEDGER__','\n'.join(base)).replace('__QUERY_ASSERTIONS__','\n'.join(parts)).replace('__HOME_ASSERTIONS__','\n'.join(home))
assert '__SOURCE_' not in contract and '__QUERY_' not in contract and '__FINANCIAL_' not in contract
dest=Path(sys.argv[1])
with dest.open('x') as f:f.write(contract)
print(json.dumps({'fixture':str(dest),'fixtureSha256':hashlib.sha256(contract.encode()).hexdigest(),
 'storeSha256':hashlib.sha256((ROOT/'supabase/functions/_shared/domain/burimunsi/postgres-records-store.js').read_bytes()).hexdigest(),
 'cases':len(captured['cases'])},indent=2))
