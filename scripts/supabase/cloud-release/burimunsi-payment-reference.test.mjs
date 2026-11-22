import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {test} from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {mutation} from '../../../supabase/functions/_shared/domain/mutations.js';
import {list} from '../../../supabase/functions/_shared/domain/admin_records.js';
import {PostgresRecordsStore} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-records-store.js';
import {RecordsService} from '../../../supabase/functions/_shared/domain/burimunsi/records-service.js';
import {ScopedCursor} from '../../../supabase/functions/_shared/domain/burimunsi/cursor.js';

const migration = name => readFile(new URL('../../../supabase/migrations/' + name, import.meta.url),'utf8');
const [baseline,catalogSource,payerSms,identity,authority] = await Promise.all([
  '20261020134444_collect_curated_platform_baseline.sql','20261101030502_collect_sms_application_fence.sql',
  '20261118090305_burimunsi_automatic_payment_sms.sql','20261119114700_collect_payment_display_reference.sql',
  '20261120104500_collect_payment_reference_authority.sql',
].map(migration));
const stamp='2026-11-01T11:00:00.000Z';
const insert='INSERT INTO app.payments(id,collection_id,evidence_id,amount_minor,status,created_at) VALUES($1,$2,$3,1250,\'recorded\',$4) RETURNING payment_reference';
const add=(db,id,group='group-a')=>db.query(insert,[id,group,'evidence-'+id,stamp]);
const reference=async(db,id)=>(await db.query('SELECT payment_reference FROM app.payments WHERE id=$1',[id])).rows[0]?.payment_reference;
const descriptor=async db=>(await db.query('SELECT private._retention_manifest_catalog_v2() AS c')).rows[0].c;
const exactColumns=async db=>(await db.query("SELECT attname FROM pg_attribute WHERE attrelid='app.payments'::regclass AND attnum>0 AND NOT attisdropped ORDER BY attnum")).rows.map(r=>r.attname);

async function setup(t) {
  const owned=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'collect_fixture'});
  const clients=[];
  const connect=async(database='postgres')=>{
    const db=new pg.Client({host:owned.socket,port:owned.port,user:owned.initialUser,database});
    clients.push(db);await db.connect();return db;
  };
  t.after(async()=>{try{await Promise.all(clients.map(db=>db.end()));}finally{assert.equal((await owned.close()).removed,true);}});
  const db=await connect();
  await db.query('CREATE ROLE postgres SUPERUSER; CREATE ROLE collect_runtime; CREATE ROLE collect_importer; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; SET ROLE postgres');
  const tables=['payments','request_receipts','mutation_guards','audit_log'].map(name=>{
    const found=baseline.split('\n').filter(line=>line.startsWith('CREATE TABLE '+name+' '));assert.equal(found.length,1);return found[0];
  });
  await db.query(`CREATE SCHEMA private;CREATE SCHEMA app;SET search_path=app,public,pg_catalog;
    CREATE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$SELECT pg_input_is_valid(value,'jsonb')$$;
    ${tables.join('\n')}
    GRANT USAGE ON SCHEMA app,private TO collect_runtime; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA app TO collect_runtime;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO collect_runtime;
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,mode text);
    INSERT INTO private.collect_fence_control VALUES(true,'fenced');
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS $$SELECT$$;`);
  const start=catalogSource.indexOf('CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2()');
  const end=catalogSource.indexOf('$function$;',start);assert.ok(start>=0&&end>start);
  await db.query(catalogSource.slice(start,end+'$function$;'.length));
  await db.query(`REVOKE ALL ON FUNCTION private._retention_manifest_catalog_v2() FROM PUBLIC;
    CREATE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
      BEGIN RETURN jsonb_build_array('private:burimunsi_observation_retry_commands','managed:storage_iceberg');END$$;
    REVOKE ALL ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) TO collect_runtime;`);
  const layer=payerSms.indexOf('DO $retention$');assert.ok(layer>=0);
  await db.query(payerSms.slice(layer,payerSms.indexOf('END;$retention$;',layer)+'END;$retention$;'.length));
  return {db,owned,connect};
}

function fixtureDatabase(client,{readOnly=false,onFirstLookup=async()=>{}}={}) {
  let firstLookup=true;
  return {prepare(statement){
    const bind=(...values)=>{
      let i=0;const text=statement.replace(/\?/g,()=>'$'+(++i)).replace(/\binstr\(/g,'pg_catalog.strpos(');assert.equal(i,values.length);
      return {text,values,async first(){
        const {rows}=await client.query(text,values);
        if(firstLookup&&statement.startsWith('SELECT * FROM request_receipts')){firstLookup=false;await onFirstLookup();}
        return rows[0]??null;
      }};
    };
    return {bind};
  },async batch(statements){
    await client.query(readOnly?'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;SET LOCAL ROLE collect_runtime;SET LOCAL search_path=app,pg_catalog':'BEGIN');
    try {
      if(!readOnly)await client.query('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
      const result=[];for(const s of statements)result.push({results:(await client.query(s.text,s.values)).rows});
      await client.query('COMMIT');return result;
    } catch(error){await client.query('ROLLBACK');throw error;}
  }};
}

test('payment allocation preserves historical identity, exact retention scope, concurrent receipts and the restored sequence tail', {timeout:60000}, async t=>{
  const {db,owned,connect}=await setup(t);
  await db.query(insert.split(' RETURNING ')[0],['historical','group-a','historical-evidence',stamp]);
  await db.query(identity);
  const previous=await descriptor(db), original=await reference(db,'historical');
  assert.deepEqual(previous.application.payments.columns,(await exactColumns(db)).slice(0,-1));
  const runtime=await connect();
  await runtime.query('SET ROLE collect_runtime; SET search_path=app,pg_catalog');
  const oldHigh='700000000001';
  await runtime.query("INSERT INTO app.payments(id,collection_id,evidence_id,amount_minor,status,created_at,payment_reference) OVERRIDING SYSTEM VALUE VALUES('previous-high','group-a','old',1,'recorded',$1,$2)",[stamp,oldHigh]);
  await db.query("UPDATE private.collect_fence_control SET mode='open'");
  await assert.rejects(db.query(authority),e=>e.code==='55000');await db.query('ROLLBACK');
  await db.query("UPDATE private.collect_fence_control SET mode='fenced'");
  await db.query(authority);
  assert.equal(await reference(db,'historical'),original);assert.equal(await reference(db,'previous-high'),oldHigh);
  const current=await descriptor(db);assert.deepEqual(current.application.payments.columns,await exactColumns(db));
  const expected=structuredClone(previous);expected.application.payments.columns.push('payment_reference');
  assert.deepEqual(current,expected);
  await assert.rejects(runtime.query('SELECT private._retention_manifest_catalog_v2()'),e=>e.code==='42501');
  const sequence=(await db.query("SELECT pg_get_serial_sequence('app.payments','payment_reference') AS seq")).rows[0].seq;
  const state=async client=>(await client.query('SELECT last_value,is_called FROM '+sequence)).rows[0];
  assert.deepEqual(await state(db),{last_value:oldHigh,is_called:true});
  await assert.rejects(runtime.query("INSERT INTO app.payments(id,collection_id,evidence_id,amount_minor,status,created_at,payment_reference) OVERRIDING SYSTEM VALUE VALUES('bad','group-a','bad',1,'recorded',$1,$2)",[stamp,'900000000000']),e=>e.code==='42501');
  await assert.rejects(runtime.query("UPDATE app.payments SET payment_reference=DEFAULT WHERE id='historical'"),e=>e.code==='42501');
  await assert.rejects(runtime.query('SELECT setval($1::regclass,100000000000)',[sequence]),e=>e.code==='42501');
  await runtime.query("UPDATE app.payments SET status='reconciled',member_id='beneficiary',revision=revision+1 WHERE id='historical'");
  await runtime.query("UPDATE app.payments SET status='reversed',revision=revision+1 WHERE id='historical'");
  assert.equal(await reference(db,'historical'),original);
  const second=await connect();await second.query('SET ROLE collect_runtime;SET search_path=app,pg_catalog');
  let arrived=0,release;const both=new Promise(resolve=>{release=resolve;});
  const barrier=async()=>{if(++arrived===2)release();await both;};
  const actor={userId:'fixture-principal',sessionId:'fixture-session'};
  const body={evidence_id:'fixture-source'},key='same-request';
  const send=(conn,id,gate,requestBody=body)=>{
    const env={DB:fixtureDatabase(conn,{onFirstLookup:gate})};
    const write=env.DB.prepare("INSERT INTO payments(id,collection_id,evidence_id,amount_minor,status,created_at) VALUES(?,'group-a','fixture-source',1250,'recorded',?)").bind(id,stamp);
    return mutation(env,actor,'payment.record',key,requestBody,{payment_id:id,source_id:'fixture-source'},[write]);
  };
  const [a,b]=await Promise.all([send(runtime,'candidate-a',barrier),send(second,'candidate-b',barrier)]);
  assert.deepEqual(a,b);assert.equal(a.source_id,'fixture-source');
  const issued=await reference(db,a.payment_id);
  assert.equal(BigInt(issued),BigInt(oldHigh)+1n);
  assert.deepEqual(await send(runtime,'lost-response',undefined),a);
  await assert.rejects(send(second,'changed',undefined,{evidence_id:'different'}),e=>e.code==='request_conflict');
  assert.equal((await db.query("SELECT count(*)::int AS n FROM app.payments WHERE evidence_id='fixture-source'")).rows[0].n,1);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM app.audit_log WHERE request_id=$1",[key])).rows[0].n,1);
  const deleted=(await add(runtime,'removed-in-fixture')).rows[0].payment_reference;
  await db.query("DELETE FROM app.payments WHERE id='removed-in-fixture'");
  await runtime.query('BEGIN');const rolledBack=(await add(runtime,'aborted')).rows[0].payment_reference;await runtime.query('ROLLBACK');
  assert.ok(BigInt(rolledBack)>BigInt(deleted));assert.equal((await state(db)).last_value,rolledBack);
  const connectArgs=['-h',owned.socket,'-p',String(owned.port),'-U',owned.initialUser];
  const dump=execFileSync(join(owned.bin,'pg_dump'),[...connectArgs,'--format=custom','postgres']);
  await db.query('CREATE DATABASE reference_restored');
  execFileSync(join(owned.bin,'pg_restore'),[...connectArgs,'--exit-on-error','--single-transaction','--dbname=reference_restored'],{input:dump});
  const restored=await connect('reference_restored');
  assert.deepEqual(await state(restored),{last_value:rolledBack,is_called:true});
  assert.equal(await reference(restored,'removed-in-fixture'),undefined);assert.equal(await reference(restored,'aborted'),undefined);
  assert.equal(await reference(restored,a.payment_id),issued);assert.equal(await reference(restored,'historical'),original);
  await restored.query('SET ROLE collect_runtime; SET search_path=app,pg_catalog');
  assert.deepEqual(await send(restored,'retry-after-restore',undefined),a);
  assert.equal(BigInt((await add(restored,'fresh-after-restore')).rows[0].payment_reference),BigInt(rolledBack)+1n);
});

test('Admin and both native payment search contracts resolve a display reference and retain the original receipt identities',async t=>{
  const {db,connect}=await setup(t);
  await db.query(`CREATE TABLE private.burimunsi_transaction_scopes(collection_id text,transaction_id text,receiving_account_id text,native_source_id text);
    CREATE TABLE private.burimunsi_scopes(collection_id text,enabled boolean,active_binding_id text,receiving_account_id text,binding_version bigint);
    CREATE TABLE app.momo_gateway_bindings(id text,receiving_account_id text,version bigint,status text);
    CREATE TABLE app.momo_gateway_credentials(binding_id text,installation_id text,revoked_at text);
    CREATE TABLE app.momo_transactions(id text PRIMARY KEY,receiving_account_id text,payer_name text,payer_identifier text,
      amount_minor bigint,transaction_at text,transaction_timezone text,transaction_datetime_raw text,provider_transaction_id text,
      allocation_state text,has_conflict integer,version bigint,created_at text,event_kind text);
    CREATE TABLE app.momo_financial_links(transaction_id text,payment_id text,beneficiary_member_id text);
    CREATE TABLE app.memberships(id text,collection_id text,user_id text,revision bigint);
    CREATE TABLE app.users(id text,full_name text,momo_number text,revision bigint);
    CREATE TABLE app.ledger_entries(id text,payment_id text,collection_id text,kind text,amount_minor bigint,evidence_id text,member_id text);
    CREATE TABLE app.collections(id text,title text);
    CREATE TABLE app.payment_evidence(id text,receiver_display_label text,receiver_network text,receiver_momo_number text,authenticity text,
      external_reference text,observed_at text,object_sha256 text,owner_user_id text);
    CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,relation text);
    INSERT INTO private.burimunsi_transaction_scopes VALUES('group-a','tx-a','wallet-a',NULL),('group-b','tx-b','wallet-b',NULL),
      ('group-a','tx-cross','wallet-a',NULL),('group-a','tx-provider','wallet-a',NULL);
    INSERT INTO app.momo_transactions SELECT transaction_id,receiving_account_id,'Fixture payer','masked',1250,
      '2026-11-01T11:00:00.000Z','Africa/Kigali','01/11/26 13:00:00','FT-'||transaction_id,'linked',0,1,'2026-11-01T11:00:00.000Z','incoming_receipt'
      FROM private.burimunsi_transaction_scopes;
    UPDATE app.momo_transactions SET provider_transaction_id='123456789012' WHERE id='tx-provider';
    INSERT INTO app.momo_financial_links VALUES('tx-a','payment-a',NULL),('tx-b','payment-b',NULL),('tx-cross','payment-b',NULL);
    INSERT INTO app.momo_transaction_sources VALUES('tx-a','source-a','accepted'),('tx-b','source-b','accepted');
    INSERT INTO app.payments(id,collection_id,evidence_id,amount_minor,status,created_at)
      VALUES('payment-a','group-a','evidence-a',1250,'recorded','2026-11-01T11:00:00.000Z'),('payment-b','group-b','evidence-b',1250,'recorded','2026-11-01T11:00:00.000Z');
    INSERT INTO app.collections VALUES('group-a','A'),('group-b','B');
    INSERT INTO app.payment_evidence(id,external_reference,observed_at,authenticity)
      SELECT evidence_id,'provider-'||id,created_at,'operator_recorded' FROM app.payments;
    GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO collect_runtime;`);
  const reader=await connect();
  const adminReader=await connect();
  adminReader.setTypeParser(20,Number);adminReader.setTypeParser(1700,Number);
  const adminSearch=q=>{
    const url=new URL('https://example.invalid/api/admin/core/transactions');url.searchParams.set('search',q);
    return list({DB:fixtureDatabase(adminReader,{readOnly:true})},'transactions',url);
  };
  const predecessor=(await adminSearch('provider-payment-a')).rows[0];
  assert.equal(predecessor.id,'payment-a');assert.equal(predecessor.payment_reference,undefined);
  const actor={id:'operator',sessionId:'session',groupId:'group-a',role:'staff',capabilities:['records.read'],active:true,expiresAt:Date.now()+600000,installationId:'staff-device'};
  const port={async unsafe(q,args){return (await reader.query(q,args)).rows;}};
  const authorityPort={groupId:actor.groupId,async session(){return actor;},async read(fn){
    await reader.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;SET LOCAL ROLE collect_runtime');
    try {const result=await fn(port);await reader.query('COMMIT');return result;}catch(error){await reader.query('ROLLBACK');throw error;}
  }};
  const unused=()=>assert.fail('unrelated data access');
  const service=new RecordsService({groupId:actor.groupId,store:new PostgresRecordsStore({authority:authorityPort,sourceReader:{revision:unused,page:unused,detail:unused}}),
    cursor:new ScopedCursor(new Uint8Array(32).fill(1))});
  const page=(q,advanced)=>service.page(actor,'payments',{q,limit:25,...(advanced?{sort:'newest'}:{})});
  const detail=id=>service.detail(actor,'payment',id,{includePaymentReference:true});
  const predecessorDetail=await service.detail(actor,'payment','tx-a');
  assert.deepEqual(await detail('tx-a'),{payment:predecessorDetail,paymentReference:null});
  for(const advanced of [false,true]){
    assert.deepEqual((await page('123456789012',advanced)).items.map(r=>r.id),['tx-provider']);
    assert.equal((await page('700000000001',advanced)).totalCount,0);
  }
  await db.query(identity);await db.query(authority);
  const inScope=await reference(db,'payment-a'),outOfScope=await reference(db,'payment-b');
  assert.notEqual(inScope,outOfScope);
  assert.deepEqual(await service.detail(actor,'payment','tx-a'),predecessorDetail);
  assert.deepEqual(await detail('tx-a'),{payment:predecessorDetail,paymentReference:inScope});
  assert.equal((await detail('tx-cross')).paymentReference,null);
  assert.equal((await detail('tx-provider')).paymentReference,null);
  await assert.rejects(detail('tx-b'),e=>e.code==='record_unavailable'&&e.status===404);
  const admin=(await adminSearch(inScope)).rows[0];
  assert.deepEqual([admin.id,admin.payment_reference,admin.evidence_id,admin.provider_reference],
    ['payment-a',inScope,'evidence-a','provider-payment-a']);
  assert.equal((await adminSearch('provider-payment-a')).rows[0].payment_reference,inScope);
  for(const advanced of [false,true]){
    const result=await page(inScope,advanced);assert.equal(result.totalCount,1);
    const row=result.items[0];assert.equal(row.id,'tx-a');assert.equal(row.ftId,'FT-tx-a');assert.equal(row.sourceId,'source-a');
    assert.ok(!Object.values(row).includes(inScope));
    assert.equal((await page(outOfScope,advanced)).totalCount,0);
    assert.equal((await page(inScope.slice(0,10),advanced)).totalCount,0);
    assert.deepEqual((await page('123456789012',advanced)).items.map(r=>r.id),['tx-provider']);
  }
  await db.query("UPDATE app.payments SET status='reversed',revision=revision+1 WHERE id='payment-a'");
  const adjusted=(await page(inScope,true)).items[0];assert.equal(adjusted.state,'reversed');
  assert.deepEqual([adjusted.id,adjusted.ftId,adjusted.sourceId],['tx-a','FT-tx-a','source-a']);
  assert.deepEqual(await detail('tx-a'),{payment:{...predecessorDetail,state:'reversed'},paymentReference:inScope});
  await db.query("UPDATE app.momo_transactions SET provider_transaction_id=$1,version=version+1 WHERE id='tx-provider'",[inScope]);
  for(const advanced of [false,true]){
    const query={q:inScope,limit:1,...(advanced?{sort:'newest'}:{})};
    const first=await service.page(actor,'payments',query),next=await service.page(actor,'payments',{...query,cursor:first.nextCursor});
    assert.equal(first.totalCount,2); assert.equal(next.nextCursor,null);
    assert.deepEqual([first.items[0].id,next.items[0].id].sort(),['tx-a','tx-provider']);
  }
});

test('an empty identity keeps its initial value, and a spent or exhausted reference is never recycled',async t=>{
  const {db,connect}=await setup(t);
  await db.query(identity);await db.query(authority);
  const runtime=await connect();await runtime.query('SET ROLE collect_runtime');
  assert.equal((await add(runtime,'first')).rows[0].payment_reference,'100000000000');
  await db.query("SELECT setval(pg_get_serial_sequence('app.payments','payment_reference'),999999999999,false)");
  assert.equal((await add(runtime,'last')).rows[0].payment_reference,'999999999999');
  await db.query("DELETE FROM app.payments WHERE id='last'");
  await assert.rejects(add(runtime,'exhausted'),e=>e.code==='2200H');
  assert.equal(await reference(db,'exhausted'),undefined);
});
