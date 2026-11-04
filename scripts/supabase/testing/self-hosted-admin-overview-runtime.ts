// Narrow, local synthetic SQL-to-Dart Admin overview proof; no hosted/Auth proof.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile,readdir,writeFile,realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import postgres from 'npm:postgres@3.4.7';
import {snapshotSelfHostedHistorySources} from './self-hosted-member-history.mjs';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {adminRpc} from '../../../supabase/functions/_shared/domain/admin.js';

const root=resolve(import.meta.dirname!,'../../..');
const sha=(v:Uint8Array|string)=>createHash('sha256').update(v).digest('hex');
async function inputs(){
 const history=await snapshotSelfHostedHistorySources(root);
 const extra=['scripts/supabase/testing/self-hosted-admin-overview-runtime.ts','test/self_hosted_admin_overview_sql_receipts_test.dart',
  ...(await readdir(root+'/lib/admin/core')).filter(n=>n.endsWith('.dart')).map(n=>'lib/admin/core/'+n)].sort();
 const files=await Promise.all(extra.map(async role=>{const p=root+'/'+role;assert.equal(await realpath(p),p);const raw=await readFile(p);return {role,bytes:raw.length,sha256:sha(raw)};}));
 return {history,extra:files};
}
assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
const fixture=JSON.parse(await readFile(Deno.env.get('COLLECT_ADMIN_OVERVIEW_FIXTURE')!,'utf8'));
const target=validateCurrentFixtureDescriptor(fixture,{purpose:'backend'});assert.equal(target.port,'55445');
assert.match(target.pathname,/^\/collect_selfhost_backend_[a-f0-9]{24}_test$/);
const output=Deno.env.get('COLLECT_ADMIN_OVERVIEW_OUTPUT')!;assert.equal(resolve(output),output);assert.equal(await realpath(resolve(output,'..')),resolve(output,'..'));
const source=await inputs();const owner=postgres(fixture.url,{max:1,prepare:false,ssl:false});const db=connection(fixture.url),control=fenceConnection(fixture.url);let packet:any;
const originalFetch=globalThis.fetch;globalThis.fetch=()=>{throw new Error('EXTERNAL_FETCH_FORBIDDEN');};
try{
 const schema=await installCurrentFixtureAdditions(owner);assert.equal(schema.migration_count,25);
 const status=(await owner`SELECT private.collect_fence_owner_status_v3() AS value`)[0].value;assert.equal(status.mode,'open');assert.equal(status.sourceSha256,fixture.source_sha256);
 const actorId=randomUUID(),targetId=randomUUID(),auth=randomUUID(),sid=randomUUID(),at=Math.floor(Date.now()/1000),stamp='2026-10-30T00:00:00.000Z';
 await owner`INSERT INTO auth.users(id,email) VALUES(${auth},'overview-admin@example.invalid')`;
 await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES(${sid},${auth},'aal1',now()+interval '1 hour')`;
 await owner`INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES(${actorId},'overview-admin@example.invalid','870001',${stamp},${stamp}),(${targetId},'overview-member@example.invalid','870002',${stamp},${stamp})`;
 await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${auth},${actorId},'synthetic-overview')`;
 await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(${sid},${actorId},'admin',${at},${at},${at+3600})`;
 const expected=await owner`SELECT (SELECT count(*) FROM app.users)::int AS users,(SELECT count(*) FROM app.collections)::int AS collections,(SELECT count(*) FROM app.payments)::int AS payments`;
 const claims={sub:auth,session_id:sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
 const work=await (openApplicationWork as any)({backend:sqlFenceBackend(db,control),sourceSha256:status.sourceSha256,kind:'http_collect'});
 let value:any,limited:any,denied=false;const statements:any[]=[];
 try{
  const runtime=new (PostgresDatabase as any)(db,claims,work);const actual=runtime.statement.bind(runtime);
  runtime.statement=async(tx:any,s:any)=>{const result=await actual(tx,s);statements.push({sql:s.sql,parameters:s.values,result});return result;};
  const native=await runtime.prepare("SELECT current_user AS role,session_user AS session,current_setting('collect.edge_verified') AS verified").first();
  assert.equal(native.role,'collect_runtime');assert.equal(native.session,'postgres');assert.equal(native.verified,'true');
  const environment={DB:runtime};
  const actor={userId:actorId,sessionId:sid,permissions:new Set(['overview.read','users.read','collections.read','payments.read'])};
  value=(await adminRpc('admin_overview',{},environment,actor)).value;
  assert.deepEqual(value.metrics.map((m:any)=>[m.label,m.value]),[['Members',expected[0].users],['Groups',expected[0].collections],['Recorded payments',expected[0].payments]]);
  limited=(await adminRpc('admin_overview',{},environment,{...actor,permissions:new Set(['overview.read','users.read'])})).value;
  assert.deepEqual(limited.metrics.map((m:any)=>m.label),['Members']);
  try{await adminRpc('admin_overview',{},environment,{...actor,permissions:new Set(['users.read'])});}catch(e:any){assert.equal(e.status,403);denied=true;}
  assert.equal(denied,true);
 }finally{await work.finish();}
 assert.equal(JSON.stringify(await inputs()),JSON.stringify(source),'SOURCE_CHANGED_DURING_SQL');
 packet={format:'collect.selfhost.admin-overview.synthetic.v1',source,source_sha256:sha(JSON.stringify(source)),schema:{migration_count:25,production_acceptance:false},overview:value,limited,denied,statements,provider_calls:0,synthetic_actor_permissions:true,hosted_acceptance:false};
 await writeFile(output,JSON.stringify(packet,null,2)+'\n',{flag:'wx',mode:0o600});
 console.log(JSON.stringify({status:'PASS',source_sha256:packet.source_sha256,packet_sha256:sha(await readFile(output)),statements:statements.length,provider_calls:0,hosted_acceptance:false}));
}finally{globalThis.fetch=originalFetch;await owner.end();await db.end({timeout:5});await control.end({timeout:5});}
