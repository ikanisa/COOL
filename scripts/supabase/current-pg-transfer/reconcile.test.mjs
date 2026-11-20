// Uses only a freshly initdb-created PG17 cluster on an exclusive Unix socket.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {contractDigest,identityDigest,reconcileCurrentPg,isSyntheticReconciliationSocket,validateReconciliationInputs} from './reconcile.mjs';
import {isManagedReconciliationTarget,managedReconciliationSsl,isManagedReconciliationPeer} from './managed-target.mjs';
import {startOwnedPg17} from './test-support/owned-pg17.mjs';

const {Client} = pg;
const sha = s => createHash('sha256').update(s).digest('hex');
const SOURCE = 'collect_fixture_source', TARGET = 'collect_fixture_target';
const secret = 'synthetic-private-marker@example.invalid';
const op = '00000000-0000-4000-8000-000000000001';
const base = 'a'.repeat(64), sourceSha = 'b'.repeat(64), targetSha = 'c'.repeat(64);
const rawProfile = 'synthetic-private-profile';

test('managed reconciliation admits only the pinned target, TLS root and verified peer', () => {
  const direct={host:'db.rrlduytparvsjfmegalh.supabase.co',port:5432,database:'postgres',user:'postgres'};
  const pooler={...direct,host:'aws-0-eu-north-1.pooler.supabase.com',user:'postgres.rrlduytparvsjfmegalh'};
  const tls={encrypted:true,authorized:true,servername:direct.host};
  const client=new Client({...direct,ssl:managedReconciliationSsl()});
  assert.equal(isManagedReconciliationPeer(client.connectionParameters,tls),true);
  assert.equal(isManagedReconciliationPeer({...pooler,ssl:managedReconciliationSsl()},{...tls,servername:pooler.host}),true);
  for (const changed of [
    {...direct,host:'db.other.supabase.co'}, {...direct,port:6543}, {...direct,database:'other'},
    {...direct,user:'another_role'}, {...pooler,host:'aws-1-eu-north-1.pooler.supabase.com'},
    {...pooler,user:'other.rrlduytparvsjfmegalh'},
  ]) assert.equal(isManagedReconciliationTarget(changed),false);
  for (const ssl of [undefined,{rejectUnauthorized:false,ca:managedReconciliationSsl().ca},
    {rejectUnauthorized:true,ca:'untrusted root'}, {...managedReconciliationSsl(),checkServerIdentity:()=>undefined},
    {...managedReconciliationSsl(),servername:'other.example'}])
    assert.equal(isManagedReconciliationPeer({...direct,ssl},tls),false);
  for (const peer of [{...tls,authorized:false},{...tls,encrypted:false},{...tls,servername:'other.example'}])
    assert.equal(isManagedReconciliationPeer({...direct,ssl:managedReconciliationSsl()},peer),false);
});

test('isolated PostgreSQL reconciliation', {timeout:90000}, async t => {
  const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'collect_fixture'});
  const {socket,port}=fixture,clients=[];let admin,setupSource,setupTarget;
  const client = database => new Client({host:socket,port,database,user:'collect_fixture',connectionTimeoutMillis:3000});
  const connect = async database => { const c = client(database);c.on('error',()=>{});clients.push(c);await c.connect();return c; };
  try {
    assert.equal(isSyntheticReconciliationSocket(socket),true);
    assert.equal(isSyntheticReconciliationSocket('/private/tmp/collect-pg-transfer-Ab12/s','darwin'),true);
    assert.equal(isSyntheticReconciliationSocket('/tmp/collect-pg-transfer-Ab12/s','linux'),true);
    assert.equal(isSyntheticReconciliationSocket('/tmp/collect-pg-transfer-Ab12/s','darwin'),false);
    assert.equal(isSyntheticReconciliationSocket('/private/tmp/collect-pg-transfer-Ab12/s','linux'),false);
    assert.equal(isSyntheticReconciliationSocket('/tmp/collect-pg-transfer-Ab12/../s','linux'),false);
    assert.equal(isSyntheticReconciliationSocket('/tmp/collect-quarantine-Ab12/s','linux'),false);
    assert.equal(isSyntheticReconciliationSocket('/tmp/collect-pg-transfer-Ab12/s','win32'),false);
    assert.equal(isSyntheticReconciliationSocket('/tmp/collect-pg-transfer-Ab_12/s','linux'),false);
    admin = await connect('postgres');
    const guard = (await admin.query("SELECT inet_server_addr() IS NULL AS unix, current_setting('server_version_num')::int / 10000 AS major")).rows[0];
    assert.deepEqual(guard,{unix:true,major:17});
    await admin.query(`CREATE DATABASE ${SOURCE}`);
    await admin.query(`CREATE DATABASE ${TARGET}`);
    setupSource = await connect(SOURCE); setupTarget = await connect(TARGET);
    for (const [c,hash] of [[setupSource,sourceSha],[setupTarget,targetSha]]) {
      await c.query(`CREATE SCHEMA private; CREATE SCHEMA app;
        CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,
          source_sha256 text,epoch bigint,mode text,operation_id uuid);
        CREATE TABLE private.collect_deployment_identity(singleton boolean PRIMARY KEY,profile_raw text,profile_sha256 text)`);
      await c.query("INSERT INTO private.collect_fence_control VALUES(true,$1,$2,$3,1,'open',$4)",['rrlduytparvsjfmegalh',base,hash,op]);
      await c.query('INSERT INTO private.collect_deployment_identity VALUES(true,$1,$2)',[rawProfile,sha(rawProfile)]);
    }
    const textCol = (name,nullable,compare=true) => ({name,type:'text',nullable,compare,collation:{schema:'pg_catalog',name:'default'},default_sha256:null,identity:'',generated:''});
    const contract = () => ({format:'collect.current-pg-reconciliation.v1',source_set_sha256:'d'.repeat(64),
      source_identity_sha256:identityDigest(expected(true)),target_identity_sha256:identityDigest(expected(false)),
      limits:{rows_per_relation:100,bytes_per_cell:256,bytes_total:10000,statement_timeout_ms:1000,total_timeout_ms:10000},
      relations:[{schema:'app',name:'people',columns:[textCol('id',true),textCol('email',true),textCol('payload',true),
        {name:'counter',type:'bigint',nullable:false,compare:true,collation:null,default_sha256:null,identity:'',generated:''}],constraints:[],key:['id'],
        unique_checks:[{column:'email',classification:'principal_email',normalization:'ascii_lower_trim'}]}]});
    const expected = source => ({transport:{kind:source?'local':'synthetic',host:socket,port},database:source?SOURCE:TARGET,
      session_user:'collect_fixture',current_user:'collect_fixture',project_ref:'rrlduytparvsjfmegalh',
      baseline_manifest_sha256:base,source_sha256:source?sourceSha:targetSha,epoch:'1',mode:'open',operation_id:op,
      profile_sha256:source?sha(rawProfile):null});
    const pair = async () => ({sourceClient:await connect(SOURCE),targetClient:await connect(TARGET),sourceIdentity:expected(true),targetIdentity:expected(false)});
    const run = async (c=contract(), override={}) => {
      const p = await pair();
      return reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c),...override});
    };
    const reset = async () => {
      for (const c of [setupSource,setupTarget]) await c.query('DROP TABLE IF EXISTS app.people; CREATE TABLE app.people(id text,email text,payload text,counter bigint NOT NULL)');
    };
    const insert = async (c,id,email,payload,counter=1) => c.query('INSERT INTO app.people VALUES($1,$2,$3,$4)',[id,email,payload,counter]);
    const typedCol = (name,type) => ({name,type,nullable:true,compare:true,collation:null,default_sha256:null,identity:'',generated:''});
    const typedContract = () => {
      const c=contract();c.relations=[{schema:'app',name:'typed_values',columns:[textCol('id',false),typedCol('amount','numeric'),
        typedCol('occurred_at','timestamp with time zone'),typedCol('document','jsonb'),typedCol('payload','bytea'),
        typedCol('fixed_amount','numeric(12,3)'),typedCol('rounded_at','timestamp(3) with time zone')],constraints:[],key:['id'],unique_checks:[]}];
      return c;
    };
    const resetTyped = async () => {
      for (const db of [setupSource,setupTarget]) await db.query(`DROP TABLE IF EXISTS app.typed_values;
        CREATE TABLE app.typed_values(id text NOT NULL,amount numeric,occurred_at timestamp with time zone,document jsonb,
          payload bytea,fixed_amount numeric(12,3),rounded_at timestamp(3) with time zone)`);
    };
    const insertTyped = (db,id,amount,time,document,payload,fixed,rounded) => db.query(
      "INSERT INTO app.typed_values VALUES($1,$2,$3,$4,decode($5,'hex'),$6,$7)",[id,amount,time,document,payload,fixed,rounded]);

    await t.test('identical data and sensitive values remain absent from output', async () => {
      await reset();
      for (const c of [setupSource,setupTarget]) await insert(c,'synthetic-id',secret,'synthetic-secret-payload');
      const result = await run();
      assert.equal(result.relations[0].matching_keys_equal_selected,1);
      assert.equal(result.write_authorized,false);
      assert.equal(result.identities_resolved,false);
      assert.equal(result.quiescence_proven,false);
      assert.doesNotMatch(JSON.stringify(result),/synthetic-id|synthetic-private-marker|synthetic-secret-payload/);
    });

    await t.test('same count but different content and ID is visible in aggregate', async () => {
      await reset(); await insert(setupSource,'same','a@example.invalid','old'); await insert(setupTarget,'same','a@example.invalid','new');
      let result = await run(); assert.equal(result.relations[0].matching_keys_changed_selected,1);
      await setupTarget.query("UPDATE app.people SET id='different'");
      result = await run(); assert.equal(result.relations[0].source_only_keys,1); assert.equal(result.relations[0].target_only_keys,1);
    });

    await t.test('same normalized email with different IDs is a conflict, never a merge', async () => {
      await reset(); await insert(setupSource,'local',' Person@Example.invalid ','x'); await insert(setupTarget,'managed','person@example.invalid','x');
      const result = await run();
      assert.equal(result.relations[0].unique_checks[0].same_value_different_key,1);
      assert.equal(result.identities_resolved,false);
      assert.doesNotMatch(JSON.stringify(result),/Person|person@example|managed|local/);
    });

    await t.test('same ID with different principal email is a conflict', async () => {
      await reset(); await insert(setupSource,'same','one@example.invalid','x'); await insert(setupTarget,'same','two@example.invalid','x');
      assert.equal((await run()).relations[0].unique_checks[0].same_key_different_value,1);
    });

    await t.test('exact numeric, instant, JSONB and bytea comparisons ignore session formatting', async () => {
      await resetTyped();
      await insertTyped(setupSource,'row','12345678901234567890.45000','2025-01-01 00:00:00.123456+00',
        '{"b":[1,2],"a":"x"}','00ff10','2.500','2025-01-01 00:00:00.123+00');
      await insertTyped(setupTarget,'row','12345678901234567890.45','2025-01-01 05:30:00.123456+05:30',
        '{ "a" : "x", "b" : [1,2] }','00ff10','2.5','2024-12-31 19:00:00.123-05');
      const p=await pair(),c=typedContract();
      await p.sourceClient.query("SET TIME ZONE 'Pacific/Honolulu'; SET DateStyle TO 'SQL, DMY'; SET bytea_output TO 'escape'");
      await p.targetClient.query("SET TIME ZONE 'Asia/Kathmandu'; SET DateStyle TO 'ISO, YMD'; SET bytea_output TO 'hex'");
      const result=await reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)});
      assert.equal(result.relations[0].matching_keys_equal_selected,1);
      assert.equal(result.write_authorized,false);
      assert.doesNotMatch(JSON.stringify(result),/12345678901234567890|00ff10|2025-01/);
    });

    await t.test('each new type detects a distinct value and SQL NULL stays distinct', async () => {
      await resetTyped();
      for (const db of [setupSource,setupTarget]) await insertTyped(db,'row','1.00000000000000000001',
        '2025-01-01 00:00:00.000001+00','{"a":1}','00ff','1.250','2025-01-01 00:00:00.123+00');
      const changes=[
        ["amount=1.00000000000000000002","amount=1.00000000000000000001"],
        ["occurred_at='2025-01-01 00:00:00.000002+00'","occurred_at='2025-01-01 00:00:00.000001+00'"],
        [`document='{"a":2}'::jsonb`,`document='{"a":1}'::jsonb`],
        ["payload=decode('00fe','hex')","payload=decode('00ff','hex')"],
        ["fixed_amount=1.251","fixed_amount=1.250"],
        ["rounded_at='2025-01-01 00:00:00.124+00'","rounded_at='2025-01-01 00:00:00.123+00'"]
      ];
      for(const [changed,restore] of changes){
        await setupTarget.query('UPDATE app.typed_values SET '+changed);
        assert.equal((await run(typedContract())).relations[0].matching_keys_changed_selected,1,changed);
        await setupTarget.query('UPDATE app.typed_values SET '+restore);
      }
      await setupSource.query("UPDATE app.typed_values SET document='null'::jsonb,payload=NULL");
      await setupTarget.query("UPDATE app.typed_values SET document=NULL,payload=NULL");
      assert.equal((await run(typedContract())).relations[0].matching_keys_changed_selected,1);
      await setupTarget.query("UPDATE app.typed_values SET document='null'::jsonb");
      assert.equal((await run(typedContract())).relations[0].matching_keys_equal_selected,1);
    });

    await t.test('nonfinite built-ins and normalized numeric keys compare without JS precision loss', async () => {
      await resetTyped();
      await insertTyped(setupSource,'row','NaN','infinity','{}','',null,'infinity');
      await insertTyped(setupTarget,'row','NaN','infinity','{}','',null,'infinity');
      assert.equal((await run(typedContract())).relations[0].matching_keys_equal_selected,1);
      await setupTarget.query("UPDATE app.typed_values SET amount='Infinity'::numeric");
      assert.equal((await run(typedContract())).relations[0].matching_keys_changed_selected,1);
      await setupSource.query('UPDATE app.typed_values SET amount=10000000000000000000.0000');
      await setupTarget.query('UPDATE app.typed_values SET amount=10000000000000000000.0');
      const c=typedContract();c.relations[0].key=['amount'];
      assert.equal((await run(c)).relations[0].matching_keys_equal_selected,1);
      await insertTyped(setupSource,'duplicate','10000000000000000000.000000',null,'{}','',null,null);
      await assert.rejects(run(c),{code:'duplicate_key'});
    });

    await t.test('JSONB number scale remains a conservative difference', async () => {
      await resetTyped();
      await insertTyped(setupSource,'row','1',null,'{"amount":1.00}',null,null,null);
      await insertTyped(setupTarget,'row','1',null,'{"amount":1.0}',null,null,null);
      assert.equal((await setupSource.query("SELECT '{\"amount\":1.00}'::jsonb = '{\"amount\":1.0}'::jsonb AS eq")).rows[0].eq,true);
      assert.equal((await run(typedContract())).relations[0].matching_keys_changed_selected,1);
      const c=typedContract(),inputs=()=>({contract:c,sourceIdentity:expected(true),targetIdentity:expected(false),expectedContractSha256:contractDigest(c)});
      c.relations[0].key=['document'];assert.throws(()=>validateReconciliationInputs(inputs()),{code:'invalid_contract'});
      c.relations[0].key=['id'];c.relations[0].unique_checks=[{column:'document',classification:'principal_link',normalization:'exact'}];
      assert.throws(()=>validateReconciliationInputs(inputs()),{code:'invalid_contract'});
    });

    const icu=(await setupSource.query("SELECT EXISTS(SELECT 1 FROM pg_collation WHERE collprovider='i') AS available")).rows[0].available;
    await t.test('nondeterministic source and target keys and unique checks are refused',
      {skip:!icu?'PostgreSQL fixture was built without ICU':false},async () => {
      for(const [db,source] of [[setupSource,true],[setupTarget,false]]){
        await db.query(`CREATE COLLATION app.case_source (provider=icu,locale='und-u-ks-level2',deterministic=${source?'false':'true'});
          CREATE COLLATION app.case_target (provider=icu,locale='und-u-ks-level2',deterministic=${source?'true':'false'});
          CREATE COLLATION app.case_deterministic (provider=icu,locale='und-u-ks-level2',deterministic=true)`);
      }
      assert.equal((await setupSource.query("SELECT 'PAYER'::text COLLATE app.case_source = 'payer'::text AS eq")).rows[0].eq,true);
      assert.equal((await setupTarget.query("SELECT 'PAYER'::text COLLATE app.case_source = 'payer'::text AS eq")).rows[0].eq,false);
      const change = async (column,type,name) => {
        for(const db of [setupSource,setupTarget])
          await db.query(`ALTER TABLE app.people ALTER COLUMN ${column} TYPE ${type} COLLATE app.${name}`);
      };
      const reviewed = (c,i,name) => {c.relations[0].columns[i].collation={schema:'app',name};return c;};
      for(const name of ['case_source','case_target']){
        await reset();await change('id','text',name);
        await insert(setupSource,'PAYER','a@example.invalid','x');await insert(setupTarget,'payer','a@example.invalid','x');
        const c=reviewed(contract(),0,name),p=await pair();let extracts=0;
        for(const client of [p.sourceClient,p.targetClient]){
          const original=client.query.bind(client);
          client.query=async query=>{if(query?.text?.startsWith('WITH s AS MATERIALIZED'))extracts++;return original(query);};
        }
        await assert.rejects(reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)}),{code:'unsupported_key_collation'});
        assert.equal(extracts,0);
      }
      await reset();await change('payload','character varying(20)','case_source');
      await insert(setupSource,'id','a@example.invalid','PAYER');await insert(setupTarget,'id','a@example.invalid','payer');
      let c=reviewed(contract(),2,'case_source');c.relations[0].columns[2].type='character varying(20)';
      c.relations[0].unique_checks=[{column:'payload',classification:'principal_link',normalization:'exact'}];
      await assert.rejects(run(c),{code:'unsupported_key_collation'});
      await reset();await change('email','text','case_target');
      c=reviewed(contract(),1,'case_target');await assert.rejects(run(c),{code:'unsupported_key_collation'});
      // A nondeterministic selected value that is not used as a key remains a
      // conservative byte comparison; it may report a logically equal value changed.
      await reset();await change('payload','text','case_source');
      await insert(setupSource,'id','a@example.invalid','PAYER');await insert(setupTarget,'id','a@example.invalid','payer');
      c=reviewed(contract(),2,'case_source');assert.equal((await run(c)).relations[0].matching_keys_changed_selected,1);
      // A reviewed deterministic ICU key remains usable even if its locale is
      // case insensitive because PostgreSQL breaks equality ties bytewise.
      await reset();await change('id','text','case_deterministic');
      for(const db of [setupSource,setupTarget])await insert(db,'id','a@example.invalid','x');
      c=reviewed(contract(),0,'case_deterministic');assert.equal((await run(c)).relations[0].matching_keys_equal_selected,1);
    });

    await t.test('new representations are checked against size limits before cell transfer', async () => {
      await resetTyped();
      for(const db of [setupSource,setupTarget]) await insertTyped(db,'row','1',null,'{}','ab'.repeat(128),null,null);
      assert.equal((await run(typedContract())).relations[0].matching_keys_equal_selected,1);
      await setupTarget.query("UPDATE app.typed_values SET payload=decode(repeat('ab',129),'hex')");
      let p=await pair(),c=typedContract(),targetReads=0,original=p.targetClient.query.bind(p.targetClient);
      p.targetClient.query=async query=>{if(query?.text?.startsWith('SELECT ')&&query.text.includes(' AS c0'))targetReads++;return original(query);};
      await assert.rejects(reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)}),{code:'input_limit_exceeded'});
      assert.equal(targetReads,0);
      await setupTarget.query("UPDATE app.typed_values SET payload=decode('','hex'),document=to_jsonb(repeat('x',300))");
      await assert.rejects(run(typedContract()),{code:'input_limit_exceeded'});
      await setupTarget.query('UPDATE app.typed_values SET document=\'{}\',amount=$1::numeric',['9'.repeat(260)]);
      await assert.rejects(run(typedContract()),{code:'input_limit_exceeded'});
    });

    await t.test('bounded stdin operator uses synthetic credentials without printing them or rows', async () => {
      await reset(); for (const db of [setupSource,setupTarget]) await insert(db,'private-row-id',secret,'private-row-payload');
      const c = contract(), stdin = JSON.stringify({format:'collect.current-pg-operator.v1',contract:c,
        sourceIdentity:expected(true),targetIdentity:expected(false),credentials:{
          source:{user:'collect_fixture',password:'synthetic-source-password'},
          target:{user:'collect_fixture',password:'synthetic-target-password'}}});
      const invoke = (pin,extraEnv={}) => new Promise((resolve,reject) => {
        const child = fixture.trackChild(spawn(process.execPath,[join(import.meta.dirname,'operator.mjs'),pin],{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin',...extraEnv}}));
        const stdout=[],stderr=[]; child.stdout.on('data',b => stdout.push(b)); child.stderr.on('data',b => stderr.push(b));
        child.on('error',reject); child.on('close',code => resolve({code,out:Buffer.concat(stdout).toString(),err:Buffer.concat(stderr).toString()}));
        child.stdin.on('error',()=>{});
        child.stdin.end(stdin);
      });
      const good = await invoke(contractDigest(c));
      assert.equal(good.code,0); assert.equal(good.err,'');
      assert.equal(JSON.parse(good.out).result.relations[0].matching_keys_equal_selected,1);
      assert.doesNotMatch(good.out,/synthetic-source-password|synthetic-target-password|private-row|synthetic-private-marker/);
      const bad = await invoke('0'.repeat(64));
      assert.equal(bad.code,1); assert.equal(bad.err,''); assert.equal(JSON.parse(bad.out).status,'refused');
      assert.doesNotMatch(bad.out,/synthetic-source-password|synthetic-target-password|private-row|synthetic-private-marker/);
      for (const extraEnv of [{PGOPTIONS:'-c role=other'}, {PGCLIENTENCODING:'LATIN1'}, {PGREPLICATION:'database'}, {NODE_TLS_REJECT_UNAUTHORIZED:'0'}]) {
        const poisoned=await invoke(contractDigest(c),extraEnv);
        assert.equal(poisoned.code,1);assert.equal(JSON.parse(poisoned.out).status,'refused');
        assert.doesNotMatch(poisoned.out,/synthetic-source-password|synthetic-target-password|private-row/);
      }
    });

    await t.test('connected clients with startup options are refused', async () => {
      const c=contract(),source=new Client({host:socket,port,database:SOURCE,user:'collect_fixture',
        options:'-c statement_timeout=5000',connectionTimeoutMillis:3000});
      source.on('error',()=>{});clients.push(source);await source.connect();
      const target=await connect(TARGET);
      await assert.rejects(reconcileCurrentPg({sourceClient:source,targetClient:target,sourceIdentity:expected(true),
        targetIdentity:expected(false),contract:c,expectedContractSha256:contractDigest(c)}),{code:'connection_mismatch'});
    });

    await t.test('type and missing-column drift fail closed', async () => {
      await reset(); await setupTarget.query('ALTER TABLE app.people ALTER COLUMN payload TYPE bigint USING 0');
      await assert.rejects(run(),{code:'catalogue_mismatch'});
      await reset(); await setupTarget.query('ALTER TABLE app.people DROP COLUMN payload');
      await assert.rejects(run(),{code:'catalogue_mismatch'});
    });

    await t.test('reviewed defaults and constraints are checked on both databases', async () => {
      await reset();
      for (const db of [setupSource,setupTarget]) await db.query('ALTER TABLE app.people ALTER COLUMN counter SET DEFAULT 0; ALTER TABLE app.people ADD CONSTRAINT positive_counter CHECK(counter >= 0)');
      const c = contract();
      c.relations[0].columns[3].default_sha256 = sha('0');
      const descriptor = await setupSource.query(`SELECT conname AS name,contype::text AS kind,condeferrable AS deferrable,
        condeferred AS initially_deferred,convalidated AS validated,
        encode(sha256(convert_to(pg_get_constraintdef(oid),'UTF8')),'hex') AS definition_sha256
        FROM pg_constraint WHERE conname='positive_counter'`);
      c.relations[0].constraints = descriptor.rows;
      assert.equal((await run(c)).relations[0].source_rows,0);
      await setupTarget.query('ALTER TABLE app.people ALTER COLUMN counter SET DEFAULT 1');
      await assert.rejects(run(c),{code:'catalogue_mismatch'});
      await setupTarget.query('ALTER TABLE app.people ALTER COLUMN counter SET DEFAULT 0; ALTER TABLE app.people DROP CONSTRAINT positive_counter');
      await assert.rejects(run(c),{code:'catalogue_mismatch'});
    });

    await t.test('null keys, duplicate keys and duplicate principal values fail closed', async () => {
      await reset(); await insert(setupSource,null,'a@example.invalid','x');
      await assert.rejects(run(),{code:'null_key'});
      await reset(); await insert(setupSource,'same','a@example.invalid','x'); await insert(setupSource,'same','b@example.invalid','x');
      await assert.rejects(run(),{code:'duplicate_key'});
      await reset(); await insert(setupSource,'a','SAME@example.invalid','x'); await insert(setupSource,'b','same@example.invalid','x');
      await assert.rejects(run(),{code:'duplicate_unique_value'});
    });

    await t.test('null principal emails remain explicitly unresolved', async () => {
      await reset(); for (const db of [setupSource,setupTarget]) await insert(db,'id',null,'x');
      const result = await run();
      assert.equal(result.relations[0].unique_checks[0].source_nulls,1);
      assert.equal(result.relations[0].unique_checks[0].target_nulls,1);
      assert.equal(result.identities_resolved,false);
    });

    await t.test('unsupported Unicode email, excess rows and oversized values fail without leaking input', async () => {
      await reset(); await insert(setupSource,'id','pérson@example.invalid','x');
      await assert.rejects(run(),{code:'unsupported_principal_email'});
      await reset(); await insert(setupSource,'a','a@example.invalid','x'); await insert(setupSource,'b','b@example.invalid','x');
      let c = contract(); c.limits.rows_per_relation = 1; await assert.rejects(run(c),{code:'input_limit_exceeded'});
      await reset(); await insert(setupSource,'a',secret,'x'.repeat(257));
      await assert.rejects(run(),err => err.code === 'input_limit_exceeded' && !JSON.stringify(err).includes(secret));
      c = contract(); c.limits.bytes_total = 1; await assert.rejects(run(c),{code:'input_limit_exceeded'});
    });

    await t.test('identity, contract and active transaction are rejected', async () => {
      await reset();
      let p = await pair();
      try { await assert.rejects(reconcileCurrentPg({...p,contract:contract(),expectedContractSha256:'0'.repeat(64)}),{code:'invalid_contract'}); }
      finally { await Promise.all([p.sourceClient.end(),p.targetClient.end()]); }
      p = await pair(); p.sourceIdentity.source_sha256 = 'f'.repeat(64);
      const rebound = contract(); rebound.source_identity_sha256 = identityDigest(p.sourceIdentity);
      await assert.rejects(reconcileCurrentPg({...p,contract:rebound,expectedContractSha256:contractDigest(rebound)}),{code:'identity_mismatch'});
      assert.equal(p.sourceClient.connection.stream.destroyed,true); assert.equal(p.targetClient.connection.stream.destroyed,true);
      p = await pair(); await p.sourceClient.query('BEGIN');
      await assert.rejects(reconcileCurrentPg({...p,contract:contract(),expectedContractSha256:contractDigest(contract())}),{code:'connection_not_idle'});
      assert.equal(p.sourceClient.connection.stream.destroyed,true); assert.equal(p.targetClient.connection.stream.destroyed,true);
    });

    await t.test('global pg text parser cannot mask differing rows', async () => {
      await reset(); await insert(setupSource,'id','a@example.invalid','one'); await insert(setupTarget,'id','a@example.invalid','two');
      const original = pg.types.getTypeParser(25,'text');
      try {
        pg.types.setTypeParser(25,'text',() => 'synthetic-parser-tamper');
        const result = await run();
        assert.equal(result.relations[0].matching_keys_changed_selected,1);
      } finally { pg.types.setTypeParser(25,'text',original); }
    });

    await t.test('contract and identity cannot change after admission', async () => {
      await reset();
      for (const db of [setupSource,setupTarget]) { await insert(db,'a','a@example.invalid','x'); await insert(db,'b','b@example.invalid','x'); }
      const p = await pair(), c = contract(), pin = contractDigest(c), original = p.sourceClient.query.bind(p.sourceClient);
      let changed = false;
      p.sourceClient.query = async query => {
        const result = await original(query);
        if (!changed) { changed = true; c.limits.rows_per_relation = 1; p.sourceIdentity.source_sha256 = 'f'.repeat(64); }
        return result;
      };
      const result = await reconcileCurrentPg({...p,contract:c,expectedContractSha256:pin});
      assert.equal(changed,true); assert.equal(result.relations[0].matching_keys_equal_selected,2);
    });

    await t.test('row-level filtering is refused rather than treated as completeness', async () => {
      await reset(); await admin.query('CREATE ROLE collect_reader LOGIN');
      await setupSource.query(`GRANT USAGE ON SCHEMA private,app TO collect_reader;
        GRANT SELECT ON private.collect_fence_control,private.collect_deployment_identity,app.people TO collect_reader;
        ALTER TABLE app.people ENABLE ROW LEVEL SECURITY;
        CREATE POLICY visible_subset ON app.people FOR SELECT TO collect_reader USING (false)`);
      const sourceClient = new Client({host:socket,port,database:SOURCE,user:'collect_reader',connectionTimeoutMillis:3000});
      sourceClient.on('error',()=>{});clients.push(sourceClient);await sourceClient.connect(); const targetClient = await connect(TARGET), sourceIdentity = expected(true);
      sourceIdentity.session_user = 'collect_reader'; sourceIdentity.current_user = 'collect_reader';
      const c = contract(); c.source_identity_sha256 = identityDigest(sourceIdentity);
      await assert.rejects(reconcileCurrentPg({sourceClient,targetClient,sourceIdentity,targetIdentity:expected(false),
        contract:c,expectedContractSha256:contractDigest(c)}),{code:'catalogue_mismatch'});
      assert.equal(sourceClient.connection.stream.destroyed,true); assert.equal(targetClient.connection.stream.destroyed,true);
    });

    await t.test('repeatable-read source snapshot survives a concurrent committed update', async () => {
      await reset(); for (const c of [setupSource,setupTarget]) await insert(c,'id','same@example.invalid','before');
      const p = await pair(), original = p.sourceClient.query.bind(p.sourceClient); let changed = false;
      p.sourceClient.query = async (query,values) => {
        const result = await original(query,values);
        if (!changed && typeof query?.text === 'string' && query.text.startsWith('WITH s AS MATERIALIZED')) {
          changed = true; await setupSource.query("UPDATE app.people SET payload='after'");
        }
        return result;
      };
      const c = contract(), result = await reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)});
      assert.equal(changed,true); assert.equal(result.relations[0].matching_keys_equal_selected,1);
      assert.equal((await setupSource.query("SELECT count(*)::int AS n FROM app.people WHERE payload='after'")).rows[0].n,1);
    });

    await t.test('ordinary read lock prevents DDL between catalogue inspection and extraction', async () => {
      await reset(); for (const db of [setupSource,setupTarget]) await insert(db,'id','same@example.invalid','x');
      await setupSource.query("SET lock_timeout='100ms'");
      const p = await pair(), original = p.sourceClient.query.bind(p.sourceClient); let blocked = false;
      p.sourceClient.query = async query => {
        const result = await original(query);
        if (!blocked && typeof query?.text === 'string' && query.text.includes('FROM pg_catalog.pg_constraint x')) {
          await assert.rejects(setupSource.query('ALTER TABLE app.people ADD COLUMN unexpected text'),{code:'55P03'});
          blocked = true;
        }
        return result;
      };
      try {
        const c = contract(), result = await reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)});
        assert.equal(blocked,true); assert.equal(result.relations[0].matching_keys_equal_selected,1);
      } finally { await setupSource.query('RESET lock_timeout'); }
    });

    await t.test('schema change immediately after snapshot anchoring is blocked', async () => {
      await reset(); for (const db of [setupSource,setupTarget]) await insert(db,'id','same@example.invalid','x');
      await setupSource.query("SET lock_timeout='100ms'");
      const p = await pair(), original = p.sourceClient.query.bind(p.sourceClient); let attempted = false;
      p.sourceClient.query = async query => {
        const result = await original(query);
        if (!attempted && typeof query?.text === 'string' && query.text.includes('FROM private.collect_deployment_identity')) {
          await assert.rejects(setupSource.query('ALTER TABLE app.people ADD COLUMN unexpected text'),{code:'55P03'}); attempted = true;
        }
        return result;
      };
      try {
        const c = contract(), result = await reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)});
        assert.equal(attempted,true); assert.equal(result.relations[0].matching_keys_equal_selected,1);
      } finally { await setupSource.query('RESET lock_timeout'); }
    });

    await t.test('schema change before the relation lock is detected', async () => {
      await reset(); for (const db of [setupSource,setupTarget]) await insert(db,'id','same@example.invalid','x');
      const p = await pair(), original = p.sourceClient.query.bind(p.sourceClient); let changed = false;
      p.sourceClient.query = async query => {
        const result = await original(query);
        if (!changed && query?.text === 'SET LOCAL row_security = off') {
          await setupSource.query('ALTER TABLE app.people ADD COLUMN unexpected text'); changed = true;
        }
        return result;
      };
      const c = contract();
      await assert.rejects(reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)}));
      assert.equal(changed,true);
    });

    await t.test('DDL committed while a multi-relation lock waits cannot hide from catalogue', async () => {
      await reset();
      for (const db of [setupSource,setupTarget]) await db.query('DROP TABLE IF EXISTS app.zzz; CREATE TABLE app.zzz (LIKE app.people)');
      const c = contract(); c.relations.push({...c.relations[0],name:'zzz'}); c.limits.statement_timeout_ms = 3000;
      await setupSource.query('BEGIN; LOCK TABLE app.zzz IN ACCESS EXCLUSIVE MODE');
      const p = await pair(), pid = (await p.sourceClient.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
      const work = reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)});
      try {
        let waiting = false;
        for (let i = 0; i < 30 && !waiting; i++) {
          waiting = (await admin.query("SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid=$1 AND locktype='relation' AND mode='AccessShareLock' AND NOT granted) AS waiting",[pid])).rows[0].waiting;
          if (!waiting) await new Promise(resolve => setTimeout(resolve,10));
        }
        assert.equal(waiting,true);
        await setupSource.query('ALTER TABLE app.zzz ADD COLUMN unexpected text'); await setupSource.query('COMMIT');
        await assert.rejects(work,{code:'catalogue_mismatch'});
      } finally { try { await setupSource.query('ROLLBACK'); } catch {} }
    });

    await t.test('blocked query times out and closes both clients', async () => {
      await reset(); await setupSource.query('BEGIN'); await setupSource.query('LOCK TABLE app.people IN ACCESS EXCLUSIVE MODE');
      const p = await pair(), c = contract(); c.limits.statement_timeout_ms = 200;
      try {
        await assert.rejects(reconcileCurrentPg({...p,contract:c,expectedContractSha256:contractDigest(c)}),{code:'query_timed_out'});
        assert.equal(p.sourceClient.connection.stream.destroyed,true); assert.equal(p.targetClient.connection.stream.destroyed,true);
      } finally { await setupSource.query('ROLLBACK'); }
    });
  } finally {
    for (const c of clients.reverse()) { try { await c.end(); } catch {} }
    if(!(await fixture.close()).removed)throw Error('fixture_cleanup_unconfirmed');
  }
});
