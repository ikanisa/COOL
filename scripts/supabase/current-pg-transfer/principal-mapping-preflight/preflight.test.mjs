import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {observePrincipalMapping,preflightPlanDigest,PreflightError} from './preflight.mjs';
const srcAuth='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',cloudAuth='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',otherAuth='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const sourceId='synthetic-local-owner',targetId='synthetic-cloud-owner',profile='synthetic-profile',profileHash=createHash('sha256').update(profile).digest('hex');
const code=x=>e=>e instanceof PreflightError&&e.code===x;
test('explicit cloud-primary mapping yields only bounded aggregate observations',{timeout:90000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_mapping_fixture'}),clients=[];
 async function connect(database,user='fixture_bootstrap'){const c=new pg.Client({host:f.socket,port:f.port,database,user});await c.connect();clients.push(c);return c;}
 try{
  const admin=await connect('postgres');await admin.query('CREATE DATABASE collect_fixture_source');await admin.query('CREATE DATABASE collect_fixture_target');
  const source=await connect('collect_fixture_source'),target=await connect('collect_fixture_target');
  for(const c of [source,target])await c.query(`CREATE SCHEMA app;CREATE SCHEMA auth;CREATE SCHEMA private;
   CREATE TABLE app.users(id text PRIMARY KEY,phone text,email text,public_id text NOT NULL,access_status text NOT NULL);
   CREATE TABLE auth.users(id uuid PRIMARY KEY,email varchar(255),deleted_at timestamptz,banned_until timestamptz);
   CREATE TABLE private.auth_principal_links(auth_user_id uuid,user_id text);
   CREATE TABLE private.collect_deployment_identity(singleton boolean PRIMARY KEY,profile_raw text,profile_sha256 text);`);
  await source.query('INSERT INTO private.collect_deployment_identity VALUES(true,$1,$2)',[profile,profileHash]);
  await source.query("INSERT INTO auth.users(id,email) VALUES($1,' Owner@Example.test ')",[srcAuth]);await source.query("INSERT INTO app.users VALUES('synthetic-local-owner','+250700000001','source@example.test','local-public','active'),('synthetic-local-other','+250700000002','other@example.test','local-other','active')");await source.query("INSERT INTO private.auth_principal_links VALUES($1,'synthetic-local-owner')",[srcAuth]);
  await target.query("INSERT INTO auth.users(id,email) VALUES($1,'owner@example.test'),($2,'owner@example.test')",[cloudAuth,otherAuth]);await target.query("INSERT INTO app.users VALUES('synthetic-cloud-owner','+250700000001','cloud@example.test','cloud-public','active'),('synthetic-local-owner','+250700000001','source@example.test','local-public','active')");await target.query("INSERT INTO private.auth_principal_links VALUES($1,'synthetic-cloud-owner'),($2,'synthetic-local-owner')",[cloudAuth,otherAuth]);
  const side=(database,auth_user_id,app_user_id,isSource)=>({kind:'synthetic',host:f.socket,port:f.port,database,session_user:'fixture_bootstrap',current_user:'fixture_bootstrap',profile_sha256:isSource?profileHash:null,auth_user_id,app_user_id});
  const base={format:'collect.principal-mapping-preflight.v1',project_ref:'rrlduytparvsjfmegalh',owner_decision:'same_person_keep_cloud_primary',decision_reference_sha256:'a'.repeat(64),source_set_sha256:'b'.repeat(64),max_rows:16,statement_timeout_ms:3000,total_timeout_ms:15000,
   source:side('collect_fixture_source',srcAuth,sourceId,true),target:side('collect_fixture_target',cloudAuth,targetId,false)};
  const sensitive=[srcAuth,cloudAuth,otherAuth,sourceId,targetId,'owner@example.test','source@example.test','+250700000001'];let sqlCalls=0;
  async function observe(plan=base,user='fixture_bootstrap'){
   const a=await connect('collect_fixture_source',user),b=await connect('collect_fixture_target',user);
   for(const c of [a,b]){const original=c.query.bind(c);c.query=(q,...rest)=>{if(q&&typeof q==='object'){sqlCalls++;assert.deepEqual(q.values,[]);for(const value of sensitive)assert(!q.text.toLowerCase().includes(value.toLowerCase()));}return original(q,...rest);};}
   return observePrincipalMapping({sourceClient:a,targetClient:b,plan,expectedPlanSha256:preflightPlanDigest(plan)});
  }
  await t.test('owner-selected pair is preserved while unrelated target collisions are counted',async()=>{
   const r=await observe();assert.equal(r.status,'aggregate_observation');assert.equal(r.owner_decision,'same_person_keep_cloud_primary');assert.equal(r.write_authorized,false);
   assert.equal(r.source.selected_exact_links,1);assert.equal(r.target.selected_exact_links,1);assert.equal(r.conflicts.selected_auth_email_matches,true);
   assert.deepEqual(r.conflicts.selected_source_app_key_conflicts,{id:1,phone:1,email:1,public_id:1});assert.equal(r.conflicts.other_cloud_auth_email_matches,1);
   assert.equal(r.email_is_identity_proof,false);assert.equal(r.other_identity_mappings_inferred,false);assert(sqlCalls>0);
   const json=JSON.stringify(r);for(const value of sensitive)assert(!json.toLowerCase().includes(value.toLowerCase()));
   assert.equal((await source.query('SELECT count(*)::int AS n FROM private.auth_principal_links')).rows[0].n,1);assert.equal((await target.query('SELECT count(*)::int AS n FROM private.auth_principal_links')).rows[0].n,2);
  });
  await t.test('email mismatch and missing owner link are reported without inferred mappings',async()=>{
   await target.query("UPDATE auth.users SET email='different@example.test' WHERE id=$1",[cloudAuth]);await source.query('DELETE FROM private.auth_principal_links');
   try{const r=await observe();assert.equal(r.source.selected_exact_links,0);assert.equal(r.conflicts.selected_auth_email_matches,false);assert.equal(r.write_authorized,false);}
   finally{await target.query("UPDATE auth.users SET email='owner@example.test' WHERE id=$1",[cloudAuth]);await source.query('INSERT INTO private.auth_principal_links VALUES($1,$2)',[srcAuth,sourceId]);}
  });
  await t.test('dangling links remain visible as counts',async()=>{
   await target.query("INSERT INTO private.auth_principal_links VALUES('dddddddd-dddd-4ddd-8ddd-dddddddddddd','missing-user')");
   try{const r=await observe();assert.equal(r.target.dangling_links,1);assert.equal(r.write_authorized,false);}finally{await target.query("DELETE FROM private.auth_principal_links WHERE user_id='missing-user'");}
  });
  await t.test('an unrelated cloud Auth ID or unselected local key collision is counted, not merged',async()=>{
   await target.query("INSERT INTO auth.users(id,email) VALUES($1,'different@example.test')",[srcAuth]);await source.query("UPDATE app.users SET email='cloud@example.test' WHERE id='synthetic-local-other'");
   try{const r=await observe();assert.equal(r.conflicts.selected_auth_ids_equal,false);assert.equal(r.conflicts.other_cloud_auth_id_conflicts,1);assert.equal(r.conflicts.unselected_source_app_key_conflicts.email,1);assert.equal(r.other_identity_mappings_inferred,false);}
   finally{await target.query('DELETE FROM auth.users WHERE id=$1',[srcAuth]);await source.query("UPDATE app.users SET email='other@example.test' WHERE id='synthetic-local-other'");}
  });
  await t.test('changed source profile and exceeded row capacity fail closed',async()=>{
   const wrong={...base,source:{...base.source,profile_sha256:'c'.repeat(64)}};await assert.rejects(observe(wrong),code('source_profile_refused'));
   await assert.rejects(observe({...base,max_rows:1}),code('data_bound_refused'));
  });
  await t.test('inheritance is refused rather than silently ignoring child rows',async()=>{
   await source.query('CREATE TABLE app.fixture_child () INHERITS (app.users)');try{await assert.rejects(observe(),code('visibility_or_topology_refused'));}finally{await source.query('DROP TABLE app.fixture_child');}
  });
  await t.test('catalogue drift is refused rather than changing the comparison meaning',async()=>{
   await target.query('ALTER TABLE app.users ALTER COLUMN access_status TYPE varchar(20)');try{await assert.rejects(observe(),code('key_catalog_refused'));}finally{await target.query('ALTER TABLE app.users ALTER COLUMN access_status TYPE text');}
  });
  await t.test('a child committed while the source lock waits cannot be hidden by an older snapshot',async()=>{
   const blocker=await connect('collect_fixture_source'),a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target');let pending,created=false;
   try{await blocker.query('BEGIN');await blocker.query('LOCK TABLE ONLY app.users IN ACCESS EXCLUSIVE MODE');
    pending=observePrincipalMapping({sourceClient:a,targetClient:b,plan:base,expectedPlanSha256:preflightPlanDigest(base)}).then(result=>({result}),error=>({error}));
    let waiting=false;const end=Date.now()+750;while(Date.now()<end&&!waiting){const q=await source.query('SELECT wait_event_type FROM pg_catalog.pg_stat_activity WHERE pid=$1',[a.processID]);waiting=q.rows[0]?.wait_event_type==='Lock';if(!waiting)await new Promise(resolve=>setTimeout(resolve,10));}
    assert.equal(waiting,true);await blocker.query('CREATE TABLE app.fixture_child () INHERITS (app.users)');await blocker.query('COMMIT');created=true;
    assert(code('visibility_or_topology_refused')((await pending).error));
   }finally{await blocker.query('ROLLBACK').catch(()=>{});if(pending)await pending;if(created)await source.query('DROP TABLE app.fixture_child');}
  });
  await t.test('held identity-table locks prevent concurrent changes during the observation',async()=>{
   const a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target'),writer=await connect('collect_fixture_source'),original=a.query.bind(a);let attempted=false;
   a.query=async(q,...rest)=>{if(!attempted&&q&&typeof q==='object'&&q.text.startsWith('SELECT id::text AS id,email')){attempted=true;await writer.query('BEGIN');await writer.query("SET LOCAL lock_timeout='75ms'");
    await assert.rejects(writer.query("UPDATE app.users SET email='changed@example.test' WHERE id=$1",[sourceId]),e=>e.code==='55P03');await writer.query('ROLLBACK');}return original(q,...rest);};
   try{const r=await observePrincipalMapping({sourceClient:a,targetClient:b,plan:base,expectedPlanSha256:preflightPlanDigest(base)});assert.equal(r.status,'aggregate_observation');assert.equal(attempted,true);}
   finally{await writer.query('ROLLBACK').catch(()=>{});}
  });
  await t.test('an interrupted and restarted transaction is not accepted as the locked observation',async()=>{
   const a=await connect('collect_fixture_source'),b=await connect('collect_fixture_target'),original=a.query.bind(a);let changed=false;
   a.query=async(q,...rest)=>{const r=await original(q,...rest);if(!changed&&q&&typeof q==='object'&&q.text.startsWith('SELECT id::text AS id,email')){changed=true;await original('COMMIT');await original('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');}return r;};
   await assert.rejects(observePrincipalMapping({sourceClient:a,targetClient:b,plan:base,expectedPlanSha256:preflightPlanDigest(base)}),code('transaction_refused'));assert.equal(changed,true);
  });
  await t.test('active row security cannot be mistaken for complete visibility',async()=>{
   await admin.query('CREATE ROLE fixture_reader LOGIN');for(const c of [source,target])await c.query('GRANT USAGE ON SCHEMA app,auth,private TO fixture_reader; GRANT SELECT,UPDATE ON ALL TABLES IN SCHEMA app,auth,private TO fixture_reader');
   await source.query('ALTER TABLE app.users ENABLE ROW LEVEL SECURITY');const p={...base,source:{...base.source,session_user:'fixture_reader',current_user:'fixture_reader'},target:{...base.target,session_user:'fixture_reader',current_user:'fixture_reader'}};
   try{await assert.rejects(observe(p,'fixture_reader'),e=>e instanceof PreflightError&&['visibility_or_topology_refused','database_read_refused'].includes(e.code));}
   finally{await source.query('ALTER TABLE app.users DISABLE ROW LEVEL SECURITY');}
  });
  await t.test('hostile plan and envelope accessors are not evaluated',async()=>{let calls=0;const p={...base};Object.defineProperty(p,'source',{enumerable:true,get(){calls++;throw Error('synthetic-secret');}});assert.throws(()=>preflightPlanDigest(p),code('plan_refused'));
   const input={targetClient:null,plan:base,expectedPlanSha256:preflightPlanDigest(base)};Object.defineProperty(input,'sourceClient',{enumerable:true,get(){calls++;throw Error('synthetic-secret');}});
   await assert.rejects(observePrincipalMapping(input),code('plan_refused'));assert.equal(calls,0);});
 }finally{await Promise.allSettled(clients.map(c=>c.end().catch(()=>{})));const r=await f.close();assert.equal(r.removed,true);}
});
