// Rehearse the actual staff adapter on a fresh, owned PostgreSQL 17 socket.
import assert from 'node:assert/strict';
import {startOwnedPg17} from '../../../scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs';
import {ownedFixturePool} from './postgres-fixture-pool.mjs';
import {PostgresNativeAuthStore} from '../../functions/_shared/domain/burimunsi/postgres-auth-store.js';
import {readRecoveryProof} from '../../functions/_shared/domain/burimunsi/postgres-operation-recovery.js';
import {projectRecoveredOutcome} from '../../functions/_shared/domain/burimunsi/operation-recovery.js';

let pool,sql;
const uuid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const groupId='fixture-group',owner=uuid(1),originId=uuid(2),currentId=uuid(3),installation=uuid(4),grant=uuid(5),digest='a'.repeat(64);
const now=1794132000000;
const defer=()=>{let resolve;const promise=new Promise(r=>resolve=r);return{promise,resolve};};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let holdNext=null,revokeOnAudit=false,revoked=false;
const work={assert:async()=>{if(revoked)throw Error('synthetic_work_revoked')}};
const db={applicationWork:work,context:async()=>{},readContext:async()=>{},
 transaction:fn=>pool.begin(async pg=>{
   const tx={unsafe:async(q,p)=>{
     const rows=await pg.unsafe(q,p);
     if(q.includes('pg_advisory_xact_lock')&&holdNext){const h=holdNext;holdNext=null;h.held.resolve();await h.release.promise;}
     if(revokeOnAudit&&q.includes('INSERT INTO private.burimunsi_audit'))revoked=true;
     return rows;
   }};
   return fn(tx);
 })};
async function waitForBlocked(){
 for(let i=0;i<200;i++){const r=await sql`SELECT count(*)::int AS n FROM pg_locks WHERE locktype='advisory' AND NOT granted`;if(r[0].n>0)return;await sleep(10);}
 throw Error('second PostgreSQL transaction did not wait on the advisory lock');
}
async function main(){
 const existing=await sql`SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname IN ('private','app')) AS present`;
 assert.equal(existing[0].present,false,'refusing nonempty database');
 await sql.fixtureScript(`
 CREATE SCHEMA private; CREATE SCHEMA app;
 CREATE TABLE app.users(id text PRIMARY KEY,access_status text NOT NULL);
 CREATE TABLE private.burimunsi_accounts(id uuid PRIMARY KEY,collection_id text NOT NULL,principal_user_id text NOT NULL,
   phone text,name text,role text,capabilities text[],active boolean NOT NULL DEFAULT true,removed boolean NOT NULL DEFAULT false,
   pin_hash jsonb,credential_version bigint NOT NULL DEFAULT 1,version bigint NOT NULL DEFAULT 1,created_at bigint,updated_at bigint,
   UNIQUE(id,collection_id));
 CREATE TABLE private.burimunsi_device_grants(id uuid PRIMARY KEY,collection_id text,version bigint,profile text,installation_id uuid,active boolean);
 CREATE TABLE private.burimunsi_device_accounts(grant_id uuid,account_id uuid,collection_id text);
 CREATE TABLE private.burimunsi_scopes(collection_id text PRIMARY KEY,enabled boolean);
 CREATE TABLE private.burimunsi_sessions(id uuid PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,installation_id uuid,
   grant_id uuid,grant_version bigint,credential_version bigint,token_hash text,created_at bigint,expires_at bigint,revoked boolean,auth_method text);
 CREATE TABLE private.burimunsi_command_receipts(collection_id text NOT NULL,actor_id uuid NOT NULL,request_id uuid NOT NULL,
   session_id uuid NOT NULL,operation text NOT NULL,fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
   response jsonb NOT NULL,created_at bigint NOT NULL,PRIMARY KEY(collection_id,actor_id,request_id),
   FOREIGN KEY(actor_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id));
 CREATE TABLE private.burimunsi_audit(id uuid PRIMARY KEY,collection_id text,actor_id uuid,action text,entity_id text,request_id uuid,at_ms bigint);
 `);
 await sql`INSERT INTO app.users VALUES ('fixture-principal','active'),('fixture-staff-principal','active')`;
 await sql`INSERT INTO private.burimunsi_scopes VALUES (${groupId},true)`;
 await sql`INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
  VALUES (${owner},${groupId},'fixture-principal','fixture-owner','Fixture owner','admin',ARRAY['records.read','staff.manage'],'{}'::jsonb,${now-100000},${now-100000})`;
 await sql`INSERT INTO private.burimunsi_device_grants VALUES(${grant},${groupId},1,'internal_receiver',${installation},true)`;
 await sql`INSERT INTO private.burimunsi_device_accounts VALUES(${grant},${owner},${groupId})`;
 await sql`INSERT INTO private.burimunsi_sessions VALUES
   (${originId},${groupId},${owner},'fixture-principal',${installation},${grant},1,1,${digest},${now-60000},${now+60000},false,'phone_pin'),
   (${currentId},${groupId},${owner},'fixture-principal',${installation},${grant},1,1,${'b'.repeat(64)},${now-30000},${now+60000},false,'phone_pin')`;
 const store=new PostgresNativeAuthStore({db,groupId,clock:()=>now,createOperatorPrincipal:async()=>({id:'fixture-staff-principal'})});
 const actor=await store.read(tx=>store.session(tx,{id:currentId,now}));
 const input=n=>({groupId,actorId:owner,sessionId:currentId,requestId:uuid(n),originDigest:digest,operation:'burimunsi.staff.create'});
 const command=n=>({groupId,actorId:owner,actorSessionId:originId,requestId:uuid(n),action:'create',fingerprint:'c'.repeat(64),
  name:'Fixture staff',phone:'fixture-staff-'+n,pinHash:{fixture:true},capabilities:['records.read']});
 const race=async(first,second)=>{
   const held=defer(),release=defer();holdNext={held,release};
   const one=first();
   await Promise.race([held.promise,one.then(()=>{throw Error("First transaction returned before acquiring its lock");})]);
   const two=second();
   try{await waitForBlocked()}finally{release.resolve();}
   return Promise.allSettled([one,two]);
 };
 // The actual adapter and actual shared transaction lock race on separate connections.
 let pair=await race(()=>store.mutateStaff(command(10)),()=>store.resolveStaffCommand(input(10)));
 assert.equal(pair[0].status,'fulfilled');assert.equal(pair[1].value.state,'committed');
 let rows=await sql`SELECT operation,response FROM private.burimunsi_command_receipts WHERE request_id=${uuid(10)}`;
 assert.equal(rows[0].operation,'burimunsi.staff.create');assert.equal(rows[0].response.applied,true);
 console.log('PASS PostgreSQL writer wins lock and committed receipt remains unchanged');
 pair=await race(()=>store.resolveStaffCommand(input(11)),()=>store.mutateStaff(command(11)));
 assert.equal(pair[0].value.state,'cancelled');assert.equal(pair[1].status,'rejected');assert.match(String(pair[1].reason),/staff_command_cancelled/);
 await assert.rejects(store.mutateStaff(command(11)),/staff_command_cancelled/);
 rows=await sql`SELECT operation,response FROM private.burimunsi_command_receipts WHERE request_id=${uuid(11)}`;
 assert.equal(rows[0].operation,'burimunsi.staff.cancelled.create');assert.deepEqual(rows[0].response,{});
 console.log('PASS PostgreSQL cancellation wins lock and concurrent or late original cannot apply');
 assert.equal(await store.retainedStaffCommand({groupId,actorId:owner,sessionId:originId,requestId:uuid(12),now}),null);
 await store.resolveStaffCommand(input(12));await assert.rejects(store.mutateStaff(command(12)),/staff_command_cancelled/);
 console.log('PASS PostgreSQL preflight before cancellation cannot permit a late apply');
 await store.resolveStaffCommand(input(13)); // Deliberately discard the acknowledgement.
 const proof=await store.read(tx=>readRecoveryProof(tx,{groupId,actorId:owner,currentSessionId:currentId,requestId:uuid(13),originDigest:digest}));
 assert.equal(projectRecoveredOutcome({proof,actor,groupId,requestId:uuid(13),originDigest:digest,now}).state,'cancelled');
 assert.equal((await store.resolveStaffCommand(input(13))).state,'cancelled');
 rows=await sql`SELECT count(*)::int AS n FROM private.burimunsi_audit WHERE request_id=${uuid(13)}`;assert.equal(rows[0].n,1);
 console.log('PASS PostgreSQL lost acknowledgement recovers exact cancellation without a duplicate audit');
 await sql`UPDATE private.burimunsi_sessions SET installation_id=${uuid(77)} WHERE id=${originId}`;
 await assert.rejects(store.resolveStaffCommand(input(14)),/operation_recovery_denied/);
 rows=await sql`SELECT count(*)::int AS n FROM private.burimunsi_command_receipts WHERE request_id=${uuid(14)}`;assert.equal(rows[0].n,0);
 await sql`UPDATE private.burimunsi_sessions SET installation_id=${installation} WHERE id=${originId}`;
 console.log('PASS PostgreSQL mismatched original installation is denied without a receipt');
 revokeOnAudit=true;await assert.rejects(store.resolveStaffCommand(input(15)),/synthetic_work_revoked/);revoked=false;revokeOnAudit=false;
 rows=await sql`SELECT count(*)::int AS n FROM private.burimunsi_command_receipts WHERE request_id=${uuid(15)}`;assert.equal(rows[0].n,0);
 console.log('PASS PostgreSQL revoked admission rolls the cancellation and audit back');
}
const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_staff_resolution'});
try {
 pool=await ownedFixturePool({...fixture,database:'postgres',user:fixture.initialUser});
 sql=await pool.reserve();
 await main();
} finally {
 try { sql?.release(); await pool?.end(); }
 finally { assert.equal((await fixture.close()).removed,true); }
}
