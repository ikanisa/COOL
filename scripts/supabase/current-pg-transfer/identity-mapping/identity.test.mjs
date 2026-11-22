// Real PostgreSQL 17, synthetic identities only. Never connects to live systems.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {identityPlanDigest,inspectOwnerIdentity,translateOwnerAppUserId} from './identity.mjs';
const {Client}=pg;
const sourceAuth='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',targetAuth='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const sourceApp='synthetic-local-owner',targetApp='synthetic-cloud-owner';
const baseline='a'.repeat(64),sourceSha='b'.repeat(64),targetSha='c'.repeat(64),profile='synthetic-profile';
const sourceOp='11111111-1111-4111-8111-111111111111',targetOp='22222222-2222-4222-8222-222222222222';
const profileSha=createHash('sha256').update(profile).digest('hex');
const code=c=>e=>e?.name==='IdentityMappingError'&&e.code===c&&!String(e.message).includes('synthetic-secret');

test('owner-approved identity mapping holds both existing principals', {timeout:180000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'}),clients=[];
 const connect=async(db,user='postgres')=>{const c=new Client({host:f.socket,port:f.port,database:db,user,connectionTimeoutMillis:3000});await c.connect();clients.push(c);return c;};
 let bootstrap;
 try{
  bootstrap=await connect('postgres','fixture_bootstrap');
  await bootstrap.query('CREATE ROLE postgres LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS');
  await bootstrap.query('GRANT SET ON PARAMETER log_parameter_max_length TO postgres');
  for(const name of ['collect_fixture_source','collect_fixture_target'])await bootstrap.query('CREATE DATABASE '+name+' OWNER postgres');
  const sourceDb=await connect('collect_fixture_source'),targetDb=await connect('collect_fixture_target');
  async function setup(c,isSource){
   await c.query(`CREATE SCHEMA app; CREATE SCHEMA auth; CREATE SCHEMA private;
    CREATE TABLE auth.users(id uuid PRIMARY KEY,email varchar,email_confirmed_at timestamptz,banned_until timestamptz,deleted_at timestamptz);
    CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid REFERENCES auth.users(id),synthetic_token text);
    CREATE TABLE app.users(id text PRIMARY KEY,phone text UNIQUE,email text UNIQUE,full_name text NOT NULL DEFAULT '',public_id text NOT NULL UNIQUE,
      country_code text NOT NULL DEFAULT 'RW',currency_code text NOT NULL DEFAULT 'RWF',momo_provider text NOT NULL DEFAULT '',momo_number text NOT NULL DEFAULT '',
      momo_pay_code text NOT NULL DEFAULT '',access_status text NOT NULL DEFAULT 'active',created_at text NOT NULL,updated_at text NOT NULL,
      member_type text NOT NULL DEFAULT 'app',revision bigint NOT NULL DEFAULT 1);
    CREATE TABLE private.auth_principal_links(auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),user_id text NOT NULL UNIQUE REFERENCES app.users(id),
      linked_at timestamptz NOT NULL DEFAULT now(),proof_reference text NOT NULL CHECK(length(proof_reference)>0));
    CREATE FUNCTION private.trg_auth_principal_link_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_managed_principal_link' USING ERRCODE='42501';END$$;
    ALTER FUNCTION private.trg_auth_principal_link_identity() SET search_path TO pg_catalog, app;
    CREATE TRIGGER auth_principal_link_identity BEFORE UPDATE OR DELETE ON private.auth_principal_links FOR EACH ROW EXECUTE FUNCTION private.trg_auth_principal_link_identity();
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,source_sha256 text,epoch bigint,mode text,operation_id uuid);
    CREATE TABLE private.collect_fence_admissions(state text,uncertain_dispatches integer);
    CREATE TABLE private.collect_deployment_identity(singleton boolean PRIMARY KEY,profile_raw text,profile_sha256 text);`);
   const auth=isSource?sourceAuth:targetAuth,app=isSource?sourceApp:targetApp;
   await c.query('INSERT INTO auth.users(id,email,email_confirmed_at) VALUES ($1,$2,now())',[auth,isSource?'Owner@synthetic.invalid':'owner@synthetic.invalid']);
   await c.query('INSERT INTO auth.sessions VALUES($1,$2,$3)',[isSource?'33333333-3333-4333-8333-333333333333':'44444444-4444-4444-8444-444444444444',auth,'synthetic-secret-never-export']);
   await c.query('INSERT INTO app.users(id,phone,email,full_name,public_id,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7)',
    [app,isSource?'+250700000001':'+250700000002',isSource?'local@synthetic.invalid':'cloud@synthetic.invalid','Synthetic',isSource?'local-public':'cloud-public','2026-01-01','2026-01-01']);
   await c.query('INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,$2,$3)',[auth,app,'synthetic-proof']);
   await c.query('INSERT INTO private.collect_fence_control VALUES(true,$1,$2,$3,1,$4,$5)', ['rrlduytparvsjfmegalh',baseline,isSource?sourceSha:targetSha,'fenced',isSource?sourceOp:targetOp]);
   await c.query('INSERT INTO private.collect_deployment_identity VALUES(true,$1,$2)',[profile,profileSha]);
  }
  await setup(sourceDb,true);await setup(targetDb,false);
  const desc=(source)=>({transport:{kind:source?'local':'synthetic',host:f.socket,port:f.port},database:source?'collect_fixture_source':'collect_fixture_target',
   session_user:'postgres',current_user:'postgres',project_ref:'rrlduytparvsjfmegalh',baseline_manifest_sha256:baseline,source_sha256:source?sourceSha:targetSha,
   epoch:'1',mode:'fenced',operation_id:source?sourceOp:targetOp,profile_sha256:source?profileSha:null});
  const key=randomBytes(32),base={format:'collect.current-pg-identity-mapping.v1',project_ref:'rrlduytparvsjfmegalh',source_set_sha256:'d'.repeat(64),
   decision_reference_sha256:'e'.repeat(64),owner_decision:'same_person_keep_cloud_primary',read_strategy:'strict_parameter_redaction',max_accounts:8,
   source:{identity:desc(true),auth_user_id:sourceAuth,app_user_id:sourceApp,record_hmac:null},
   target:{identity:desc(false),auth_user_id:targetAuth,app_user_id:targetApp,record_hmac:null},statement_timeout_ms:3000,total_timeout_ms:15000};
  const run=async(plan,mode='verify',onVerified)=>inspectOwnerIdentity({sourceClient:await connect('collect_fixture_source'),targetClient:await connect('collect_fixture_target'),
   plan,expectedPlanSha256:identityPlanDigest(plan),key,mode,onVerified});
  const capture=await run(base,'capture');
  const plan={...base,source:{...base.source,record_hmac:capture.source_record_hmac},target:{...base.target,record_hmac:capture.target_record_hmac}};
  await t.test('captures keyed fingerprints only and maps the owner to the existing cloud app user',async()=>{
   assert.equal(capture.status,'fingerprints_captured');assert.equal(capture.write_authorized,false);
   assert.doesNotMatch(JSON.stringify(capture),/Owner@|owner@|synthetic-local-owner|synthetic-cloud-owner|synthetic-secret/);
   let cap;const result=await run(plan,'verify',async binding=>{cap=binding;assert.equal(translateOwnerAppUserId(binding,sourceApp),targetApp);
    assert.throws(()=>translateOwnerAppUserId(binding,'different-synthetic-user'),code('identity_mapping_unavailable'));});
   assert.equal(result.status,'selected_identity_snapshot_verified');assert.equal(result.existing_target_link_unchanged_in_snapshot,true);assert.equal(result.schema_actor_exclusion_verified,false);assert.equal(result.business_rows_migrated,0);
   assert.throws(()=>translateOwnerAppUserId(cap,sourceApp),code('identity_mapping_unavailable'));
   const target=(await targetDb.query('SELECT auth_user_id::text,user_id FROM private.auth_principal_links')).rows;
   assert.deepEqual(target,[{auth_user_id:targetAuth,user_id:targetApp}]);
   assert.equal((await sourceDb.query('SELECT count(*)::int AS n FROM auth.sessions')).rows[0].n,1);
   assert.equal((await targetDb.query('SELECT count(*)::int AS n FROM auth.sessions')).rows[0].n,1);
  });
  await t.test('repeat verification is idempotent and does not write either database',async()=>{
   const a=await run(plan),b=await run(plan);assert.deepEqual(a,b);
   assert.equal((await targetDb.query('SELECT count(*)::int AS n FROM app.users')).rows[0].n,1);
  });
  await t.test('source row drift invalidates the approved preimage',async()=>{
   await sourceDb.query("UPDATE app.users SET revision=2 WHERE id=$1",[sourceApp]);
   try{await assert.rejects(run(plan),code('identity_preimage_changed'));}finally{await sourceDb.query("UPDATE app.users SET revision=1 WHERE id=$1",[sourceApp]);}
  });
  await t.test('target row drift invalidates the approved preimage',async()=>{
   await targetDb.query("UPDATE app.users SET revision=2 WHERE id=$1",[targetApp]);
   try{await assert.rejects(run(plan),code('identity_preimage_changed'));}finally{await targetDb.query("UPDATE app.users SET revision=1 WHERE id=$1",[targetApp]);}
  });
  await t.test('different Auth emails fail without inferring a new identity',async()=>{
   await targetDb.query("UPDATE auth.users SET email='else@synthetic.invalid' WHERE id=$1",[targetAuth]);
   try{await assert.rejects(run(plan),code('identity_evidence_changed'));}finally{await targetDb.query("UPDATE auth.users SET email='owner@synthetic.invalid' WHERE id=$1",[targetAuth]);}
  });
  await t.test('source public ID held by another cloud user is a conflict',async()=>{
   await targetDb.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('other','local-public','2026-01-01','2026-01-01')");
   try{await assert.rejects(run(plan),code('target_user_collision'));}finally{await targetDb.query("DELETE FROM app.users WHERE id='other'");}
  });
  await t.test('a matching local app ID already held by another cloud user is a conflict',async()=>{
   await targetDb.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES($1,'other-public','2026-01-01','2026-01-01')",[sourceApp]);
   try{await assert.rejects(run(plan),code('target_user_collision'));}finally{await targetDb.query('DELETE FROM app.users WHERE id=$1',[sourceApp]);}
  });
  await t.test('missing or wrong principal link fails without altering the link',async()=>{
   const altered={...plan,target:{...plan.target,app_user_id:'unknown-synthetic-user'}};
   await assert.rejects(run(altered),code('identity_unavailable'));
   await assert.rejects(targetDb.query('UPDATE private.auth_principal_links SET user_id=$1 WHERE auth_user_id=$2',[sourceApp,targetAuth]),e=>e.code==='42501');
   await assert.rejects(targetDb.query('DELETE FROM private.auth_principal_links WHERE auth_user_id=$1',[targetAuth]),e=>e.code==='42501');
  });
  await t.test('disabled immutable link guard is refused',async()=>{
   await targetDb.query('ALTER TABLE private.auth_principal_links DISABLE TRIGGER auth_principal_link_identity');
   try{await assert.rejects(run(plan),code('principal_guard_changed'));}finally{await targetDb.query('ALTER TABLE private.auth_principal_links ENABLE TRIGGER auth_principal_link_identity');}
  });
  await t.test('unresolved or uncertain admissions are refused even under a fenced controller',async()=>{
   for(const row of [['unresolved',0],['settled',1],['settled',null]]){
    await targetDb.query('INSERT INTO private.collect_fence_admissions VALUES($1,$2)',row);
    try{await assert.rejects(run(plan),code('unsettled_work'));}finally{await targetDb.query('DELETE FROM private.collect_fence_admissions');}
   }
  });
  await t.test('owner decision, exact plan digest, profile and fence preimages cannot drift',async()=>{
   await assert.rejects(run({...plan,owner_decision:'merge_by_email'}),code('invalid_plan'));
   const changed={...plan,source:{...plan.source,identity:{...plan.source.identity,epoch:'2'}}};
   await assert.rejects(run(changed),code('identity_mismatch'));
   const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');
   await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan,expectedPlanSha256:'f'.repeat(64),key}),code('invalid_plan'));
   await s.end();await d.end();
  });
  await t.test('callback cannot write inside read-only verification transaction',async()=>{
   const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');
   await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan,expectedPlanSha256:identityPlanDigest(plan),key,onVerified:async()=>{
    await assert.rejects(d.query("UPDATE app.users SET full_name='unwanted'"),e=>e.code==='25006');
   }}),code('database_read_failed'));
   assert.equal((await targetDb.query('SELECT full_name FROM app.users WHERE id=$1',[targetApp])).rows[0].full_name,'Synthetic');
  });
  await t.test('a callback that ends or restarts a transaction cannot produce a verification result',async()=>{
   const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');
   await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan,expectedPlanSha256:identityPlanDigest(plan),key,onVerified:async()=>{
    await d.query('COMMIT');await d.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
   }}),code('transaction_changed'));
   assert.equal((await targetDb.query('SELECT full_name FROM app.users WHERE id=$1',[targetApp])).rows[0].full_name,'Synthetic');
  });
  await t.test('held identity locks block concurrent user mutation',async()=>{
   const other=await connect('collect_fixture_target');
   try{await run(plan,'verify',async()=>{
    await other.query('BEGIN');await other.query("SET LOCAL lock_timeout='150ms'");
    await assert.rejects(other.query("UPDATE app.users SET full_name='would-change' WHERE id=$1",[targetApp]),e=>e.code==='55P03');
    await other.query('ROLLBACK');
   });}finally{await other.end();}
  });
  await t.test('the database role must suppress bind parameter logging before sending identity values',async()=>{
   await bootstrap.query('REVOKE SET ON PARAMETER log_parameter_max_length FROM postgres');let valuesSeen=false;
   const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');const original=s.query.bind(s);
   s.query=(...args)=>{const q=args[0];if(q&&typeof q==='object'&&q.values?.length)valuesSeen=true;return original(...args);};
   try{await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan,expectedPlanSha256:identityPlanDigest(plan),key}),code('database_read_failed'));assert.equal(valuesSeen,false);}
   finally{await bootstrap.query('GRANT SET ON PARAMETER log_parameter_max_length TO postgres');}
  });
  await t.test('bounded zero-bind mode works without superuser parameter SET or secret bind values',async()=>{
   await bootstrap.query('REVOKE SET ON PARAMETER log_parameter_max_length FROM postgres');
   const clean={...base,read_strategy:'bounded_zero_bind',max_accounts:2};let count=0,sqlText='';
   const invoke=async(input,mode)=>{
    const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');
    for(const c of [s,d]){const query=c.query.bind(c);c.query=(...args)=>{const q=args[0];if(q&&typeof q==='object'){if(q.values?.length)count++;sqlText+=q.text+'\n';}return query(...args);};}
    return inspectOwnerIdentity({sourceClient:s,targetClient:d,plan:input,expectedPlanSha256:identityPlanDigest(input),key,mode});
   };
   try{
    const first=await invoke(clean,'capture');
    const verified={...clean,source:{...clean.source,record_hmac:first.source_record_hmac},target:{...clean.target,record_hmac:first.target_record_hmac}};
    const result=await invoke(verified,'verify');assert.equal(result.status,'selected_identity_snapshot_verified');assert.equal(result.read_strategy,'bounded_zero_bind');
    assert.equal(count,0);assert.doesNotMatch(sqlText,/synthetic-local-owner|synthetic-cloud-owner|Owner@|owner@|25070000000/);
   }finally{await bootstrap.query('GRANT SET ON PARAMETER log_parameter_max_length TO postgres');}
  });
  await t.test('bounded zero-bind mode rejects excess account scope and target key collisions',async()=>{
   const clean={...base,read_strategy:'bounded_zero_bind',max_accounts:1};
   await sourceDb.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('other','other-public','2026-01-01','2026-01-01')");
   try{await assert.rejects(run(clean,'capture'),code('account_capacity_or_link_mismatch'));}
   finally{await sourceDb.query("DELETE FROM app.users WHERE id='other'");}
   const bigger={...clean,max_accounts:2};
   await targetDb.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('other','local-public','2026-01-01','2026-01-01')");
   try{await assert.rejects(run(bigger,'capture'),code('target_user_collision'));}
   finally{await targetDb.query("DELETE FROM app.users WHERE id='other'");}
  });
  await t.test('bounded zero-bind mode refuses extra unique indexes and key type drift',async()=>{
   const clean={...base,read_strategy:'bounded_zero_bind',max_accounts:2};
   await targetDb.query('CREATE UNIQUE INDEX synthetic_email_fold ON app.users(lower(email))');
   try{await assert.rejects(run(clean,'capture'),code('target_key_catalog_changed'));}
   finally{await targetDb.query('DROP INDEX app.synthetic_email_fold');}
   await targetDb.query('ALTER TABLE app.users ALTER COLUMN phone TYPE varchar(80)');
   try{await assert.rejects(run(clean,'capture'),code('target_key_catalog_changed'));}
   finally{await targetDb.query('ALTER TABLE app.users ALTER COLUMN phone TYPE text');}
  });
  await t.test('zero-bind preflights reject oversized source and target rows before payload queries',async()=>{
   const clean={...base,read_strategy:'bounded_zero_bind',max_accounts:2};
   for(const [db,id,originalEmail] of [[sourceDb,sourceAuth,'Owner@synthetic.invalid'],[targetDb,targetAuth,'owner@synthetic.invalid']]){
    await db.query('UPDATE auth.users SET email=$1 WHERE id=$2',['x'.repeat(2_000_000)+'@synthetic.invalid',id]);
    const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');let payloadQueries=0,binds=0;
    for(const c of [s,d]){const original=c.query.bind(c);c.query=(...args)=>{
     const q=args[0];if(q&&typeof q==='object'){if(q.values?.length)binds++;if(q.text.includes("'auth_email',a.email")||q.text.includes("'phone',phone,'email',email"))payloadQueries++;}
     return original(...args);
    };}
    try{
     await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan:clean,expectedPlanSha256:identityPlanDigest(clean),key,mode:'capture'}),code('identity_data_too_large'));
     assert.equal(payloadQueries,0,'no selected identity payload may be fetched from either side');assert.equal(binds,0);
    }finally{await db.query('UPDATE auth.users SET email=$1 WHERE id=$2',[originalEmail,id]);}
   }
  });
  await t.test('zero-bind aggregate preflight rejects many individually bounded rows before payload queries',async()=>{
   const clean={...base,read_strategy:'bounded_zero_bind',max_accounts:32};
   for(let i=0;i<20;i++)await targetDb.query('INSERT INTO app.users(id,phone,public_id,created_at,updated_at) VALUES($1,$2,$3,$4,$4)',
    ['extra-'+i,'p'.repeat(850)+i,'extra-public-'+i,'2026-01-01']);
   const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');let payloadQueries=0;
   for(const c of [s,d]){const original=c.query.bind(c);c.query=(...args)=>{const q=args[0];if(q&&typeof q==='object'&&(q.text.includes("'auth_email',a.email")||q.text.includes("'phone',phone,'email',email")))payloadQueries++;return original(...args);};}
   try{await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan:clean,expectedPlanSha256:identityPlanDigest(clean),key,mode:'capture'}),code('identity_data_too_large'));assert.equal(payloadQueries,0);}
   finally{await targetDb.query("DELETE FROM app.users WHERE id LIKE 'extra-%'");}
  });
  for(const strategy of ['strict_parameter_redaction','bounded_zero_bind']){
   const seed={...base,read_strategy:strategy,max_accounts:8};
   const fingerprints=await run(seed,'capture');
   const bound={...seed,source:{...seed.source,record_hmac:fingerprints.source_record_hmac},target:{...seed.target,record_hmac:fingerprints.target_record_hmac}};
   for(const source of [true,false]){
    const side=source?'source':'target',db=source?sourceDb:targetDb;
    const tables=['app.users','auth.users','private.auth_principal_links','private.collect_fence_admissions','private.collect_fence_control'];
    if(source)tables.push('private.collect_deployment_identity');
    await t.test(`${strategy}: ${side} rejects inherited children on every inspected relation`,async()=>{
     for(const table of tables){
      await db.query(`CREATE TABLE app.identity_fixture_child () INHERITS (${table})`);
      try{
       if(table==='app.users')await db.query("INSERT INTO app.identity_fixture_child(id,phone,public_id,created_at,updated_at) VALUES('child','+250799999999','child-public','2026-01-01','2026-01-01')");
       await assert.rejects(run(bound),code('inherited_relation_unsupported'),table);
      }finally{await db.query('DROP TABLE app.identity_fixture_child');}
     }
    });
    await t.test(`${strategy}: ${side} rejects an inspected relation inheriting from a parent`,async()=>{
     await db.query('CREATE TABLE app.identity_fixture_parent (id text)');
     try{
      await db.query('ALTER TABLE app.users INHERIT app.identity_fixture_parent');
      await assert.rejects(run(bound),code('inherited_relation_unsupported'));
     }finally{
      await db.query('ALTER TABLE app.users NO INHERIT app.identity_fixture_parent');
      await db.query('DROP TABLE app.identity_fixture_parent');
     }
    });
    await t.test(`${strategy}: ${side} inherited child committed while lock waits is rejected`,async()=>{
     const blocker=await connect(source?'collect_fixture_source':'collect_fixture_target');
     const a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target'),selected=source?a:b;
     let pending,created=false;
     try{
      await blocker.query('BEGIN');await blocker.query('LOCK TABLE ONLY app.users IN ACCESS EXCLUSIVE MODE');
      pending=inspectOwnerIdentity({sourceClient:a,targetClient:b,plan:bound,expectedPlanSha256:identityPlanDigest(bound),key}).then(result=>({result}),error=>({error}));
      let waiting=false;const until=Date.now()+750;
      while(Date.now()<until&&!waiting){const q=await db.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[selected.processID]);waiting=q.rows[0]?.wait_event_type==='Lock';if(!waiting)await new Promise(resolve=>setTimeout(resolve,10));}
      assert.equal(waiting,true,'verifier must be waiting before inheritance is created');
      await blocker.query('CREATE TABLE app.identity_fixture_child () INHERITS (app.users)');
      await blocker.query('COMMIT');created=true;
      const outcome=await pending;assert.ok(code('inherited_relation_unsupported')(outcome.error),String(outcome.error?.code));
     }finally{
      await blocker.query('ROLLBACK').catch(()=>{});if(pending)await pending;if(created)await db.query('DROP TABLE app.identity_fixture_child');await blocker.end();
     }
    });
    await t.test(`${strategy}: ${side} locks an existing child before checking its inheritance`,async()=>{
     await db.query('CREATE TABLE app.identity_fixture_child () INHERITS (app.users)');
     await db.query("INSERT INTO app.identity_fixture_child(id,phone,public_id,created_at,updated_at) VALUES('child','+250799999999','child-public','2026-01-01','2026-01-01')");
     const observer=await connect(source?'collect_fixture_source':'collect_fixture_target');
     const a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target'),selected=source?a:b,original=selected.query.bind(selected);
     let attempted=false;
     selected.query=async(...args)=>{
      const result=await original(...args),q=args[0];
      if(!attempted&&q&&typeof q==='object'&&q.text.startsWith('LOCK TABLE ')){
       attempted=true;await observer.query('BEGIN');await observer.query("SET LOCAL lock_timeout='75ms'");
       await assert.rejects(observer.query("UPDATE app.identity_fixture_child SET phone='+250700000001' WHERE id='child'"),e=>e.code==='55P03');
       await observer.query('ROLLBACK');
      }
      return result;
     };
     try{
      await assert.rejects(inspectOwnerIdentity({sourceClient:a,targetClient:b,plan:bound,expectedPlanSha256:identityPlanDigest(bound),key}),code('inherited_relation_unsupported'));
      assert.equal(attempted,true);
     }finally{await observer.query('ROLLBACK').catch(()=>{});await observer.end();await db.query('DROP TABLE app.identity_fixture_child');}
    });
    await t.test(`${strategy}: ${side} held locks prevent creating inherited children`,async()=>{
     const observer=await connect(source?'collect_fixture_source':'collect_fixture_target');
     try{await run(bound,'verify',async()=>{
      for(const table of tables){
       await observer.query('BEGIN');await observer.query("SET LOCAL lock_timeout='75ms'");
       await assert.rejects(observer.query(`CREATE TABLE app.identity_fixture_child () INHERITS (${table})`),e=>e.code==='55P03',table);
       await observer.query('ROLLBACK');
      }
     });}finally{await observer.end();}
    });
    await t.test(`${strategy}: ${side} held locks prevent an inspected table inheriting a parent`,async()=>{
     await db.query('CREATE TABLE app.identity_fixture_parent (id text)');
     const observer=await connect(source?'collect_fixture_source':'collect_fixture_target');
     try{await run(bound,'verify',async()=>{
      await observer.query('BEGIN');await observer.query("SET LOCAL lock_timeout='75ms'");
      await assert.rejects(observer.query('ALTER TABLE app.users INHERIT app.identity_fixture_parent'),e=>e.code==='55P03');
      await observer.query('ROLLBACK');
     });}finally{await observer.query('ROLLBACK').catch(()=>{});await observer.end();await db.query('DROP TABLE app.identity_fixture_parent');}
    });
   }
   for(const source of [true,false])for(const change of ['fence','admission','identity']){
    const side=source?'source':'target',db=source?sourceDb:targetDb,app=source?sourceApp:targetApp;
    const apply=async c=>{
     if(change==='fence')await c.query("UPDATE private.collect_fence_control SET mode='open' WHERE singleton");
     else if(change==='admission')await c.query("INSERT INTO private.collect_fence_admissions VALUES('unresolved',0)");
     else await c.query('UPDATE app.users SET revision=2 WHERE id=$1',[app]);
    };
    const reset=async()=>{
     if(change==='fence')await db.query("UPDATE private.collect_fence_control SET mode='fenced' WHERE singleton");
     else if(change==='admission')await db.query('DELETE FROM private.collect_fence_admissions');
     else await db.query('UPDATE app.users SET revision=1 WHERE id=$1',[app]);
    };
    const expected=change==='fence'?'identity_mismatch':change==='admission'?'unsettled_work':'identity_preimage_changed';
    await t.test(`${strategy}: ${side} ${change} committed immediately before locks is detected`,async()=>{
     const a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target'),selected=source?a:b,original=selected.query.bind(selected);let changed=false;
     selected.query=async(...args)=>{const q=args[0];if(!changed&&q&&typeof q==='object'&&q.text.startsWith('LOCK TABLE ')){changed=true;await apply(db);}return original(...args);};
     try{
      await assert.rejects(inspectOwnerIdentity({sourceClient:a,targetClient:b,plan:bound,expectedPlanSha256:identityPlanDigest(bound),key}),code(expected));
      assert.equal(changed,true);
     }finally{await reset();}
    });
    await t.test(`${strategy}: ${side} ${change} committed while locks wait is detected`,async()=>{
     const blocker=await connect(source?'collect_fixture_source':'collect_fixture_target');
     const a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target'),selected=source?a:b;
     let pending;
     try{
      await blocker.query('BEGIN');await blocker.query('LOCK TABLE ONLY app.users IN ACCESS EXCLUSIVE MODE');
      pending=inspectOwnerIdentity({sourceClient:a,targetClient:b,plan:bound,expectedPlanSha256:identityPlanDigest(bound),key}).then(result=>({result}),error=>({error}));
      let waiting=false;const until=Date.now()+750;
      while(Date.now()<until&&!waiting){const q=await db.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[selected.processID]);waiting=q.rows[0]?.wait_event_type==='Lock';if(!waiting)await new Promise(resolve=>setTimeout(resolve,10));}
      assert.equal(waiting,true,'identity verifier must be blocked on the owned relation');
      await apply(blocker);await blocker.query('COMMIT');
      const outcome=await pending;assert.ok(outcome.error, 'changed state must not be accepted');assert.ok(code(expected)(outcome.error),String(outcome.error?.code));
     }finally{
      await blocker.query('ROLLBACK').catch(()=>{});if(pending)await pending;await reset();await blocker.end();
     }
    });
   }
   await t.test(`${strategy}: acquired locks prevent later fence, admission and identity mutations`,async()=>{
    for(const source of [true,false]){
     const observer=await connect(source?'collect_fixture_source':'collect_fixture_target'),app=source?sourceApp:targetApp;
     try{await run(bound,'verify',async()=>{
      for(const [sql,values] of [["UPDATE private.collect_fence_control SET mode='open' WHERE singleton",[]],
       ["INSERT INTO private.collect_fence_admissions VALUES('unresolved',0)",[]],['UPDATE app.users SET revision=2 WHERE id=$1',[app]]]){
       await observer.query('BEGIN');await observer.query("SET LOCAL lock_timeout='100ms'");
       await assert.rejects(observer.query(sql,values),e=>e.code==='55P03');await observer.query('ROLLBACK');
      }
     });}finally{await observer.end();}
    }
   });
  }
  await t.test('schema actor replacement is not claimed excluded by selected snapshot verification',async()=>{
   let reached,release;const inCallback=new Promise(resolve=>{reached=resolve;}),gate=new Promise(resolve=>{release=resolve;});
   const pending=run(plan,'verify',async()=>{reached();await gate;});
   try{
    await inCallback;
    await targetDb.query("CREATE OR REPLACE FUNCTION private.trg_auth_principal_link_identity() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NEW;END$$");
    release();const result=await pending;
    assert.equal(result.status,'selected_identity_snapshot_verified');assert.equal(result.schema_actor_exclusion_verified,false);assert.equal(result.write_authorized,false);
   }finally{
    release();await pending.catch(()=>{});
    await targetDb.query(`CREATE OR REPLACE FUNCTION private.trg_auth_principal_link_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_managed_principal_link' USING ERRCODE='42501';END$$`);
    await targetDb.query('ALTER FUNCTION private.trg_auth_principal_link_identity() SET search_path TO pg_catalog, app');
   }
  });
  await t.test('hostile getters and non-owned key memory fail without exposing their messages',async()=>{
   let getterCalls=0;const hostile={...plan};Object.defineProperty(hostile,'source',{enumerable:true,get(){getterCalls++;throw Error('synthetic-secret-plan');}});
   assert.throws(()=>identityPlanDigest(hostile),code('invalid_plan'));assert.equal(getterCalls,0);
   const shared=Buffer.from(new SharedArrayBuffer(32));
   const s=await connect('collect_fixture_source'),d=await connect('collect_fixture_target');
   await assert.rejects(inspectOwnerIdentity({sourceClient:s,targetClient:d,plan,expectedPlanSha256:identityPlanDigest(plan),key:shared}),code('invalid_key'));
   await s.end();await d.end();
  });
  key.fill(0);
 }finally{
  await Promise.allSettled(clients.map(c=>c.end().catch(()=>{})));
  const stopped=await f.close();assert.equal(stopped.removed,true);
 }
});
