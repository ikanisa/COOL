// Exact 032 schema, synthetic data, network-none container; never a live DB.
import '../../functions/_shared/tests/helpers/node-postgres-import.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fixturePool} from './psql-fixture-transport.mjs';
import {openApplicationWork,sqlFenceBackend} from '../../functions/_shared/application-fence.js';
import {PostgresDatabase} from '../../functions/_shared/postgres.js';
import {createPhonePinRequestGate} from '../../functions/_shared/domain/burimunsi/phone-pin-request.js';
import {PostgresNativeAuthStore} from '../../functions/_shared/domain/burimunsi/postgres-auth-store.js';
import {PostgresPhonePinSessions} from '../../functions/_shared/domain/burimunsi/postgres-phone-pin-sessions.js';
import {PostgresOperatorDirectory} from '../../functions/_shared/domain/burimunsi/postgres-operator-directory.js';
import {PostgresCanonicalStore} from '../../functions/_shared/domain/burimunsi/postgres-canonical-store.js';
import {PostgresCollectMemberCommands} from '../../functions/_shared/domain/burimunsi/postgres-collect-members.js';
import {PostgresRematchJobStore} from '../../functions/_shared/domain/burimunsi/postgres-rematch-job-store.js';
import {PostgresRecordsStore} from '../../functions/_shared/domain/burimunsi/postgres-records-store.js';
import {MemberService} from '../../functions/_shared/domain/burimunsi/member-service.js';
import {RecordsService} from '../../functions/_shared/domain/burimunsi/records-service.js';

const receipt=JSON.parse(readFileSync(process.env.BURI_MEMBER_FIXTURE_RECEIPT,'utf8'));
const docker='/Applications/Docker.app/Contents/Resources/bin/docker',host='unix:///Volumes/SupaRuntime/.colima/supabase-local/docker.sock';
const image='sha256:c141fd17ac6a76c4323e90b3aee8ff1a23d2e89e547c2b963cfadc309c079cc2';
const live='2b1edd8ffa8f4149445d1af4042d6d10f6dfdb44a6ecd839e8ed0d94ce43abb6';
const info=JSON.parse(execFileSync(docker,['-H',host,'inspect',receipt.container_id],{encoding:'utf8'}))[0];
assert.notEqual(receipt.container_id,live);assert.equal(info.Id,receipt.container_id);assert.equal(info.Image,image);
assert.equal(info.HostConfig.NetworkMode,'none');assert.equal(info.Config.Labels['io.collect.member-scope-qa'],receipt.operation);
assert.equal(info.State.Running,true);assert.equal(Object.keys(info.NetworkSettings.Ports??{}).length,0);
assert.equal(info.Mounts.length,0);assert.match(info.HostConfig.Tmpfs['/tmp'],/size=256m/);
const source='fd420e522ee7d7cbbac3facdb088afb925e249dcef62a372a28e837ab26153af',group='synthetic-collection';
const roles={admin:{token:'a',device:'b',installation:'99999999-9999-4999-8999-999999999999'},
 staff:{token:'e',device:'c',installation:'99999999-9999-4999-8999-999999999992'},
 viewer:{token:'f',device:'d',installation:'99999999-9999-4999-8999-999999999993'}};
const pool=fixturePool({docker,host,container:receipt.container_id,database:'postgres',record:e=>{
 if(e.kind==='psql_exit'&&e.code)console.error('synthetic PostgreSQL diagnostic:',e.stderr);
}});
const no=()=>{throw Error('financial or external port must not be called')};
const cursor={create:no,read:no};
async function run(role,callback,{claimedGroup=group}={}){
 const r=roles[role],backend=sqlFenceBackend(pool,pool),work=await openApplicationWork({backend,sourceSha256:source,kind:'http_collect'});
 const db=new PostgresDatabase(pool,{},work),gate=createPhonePinRequestGate({secrets:{},networkBucket:async()=> '1'.repeat(64)});
 const request=new Request('https://synthetic.invalid/v1/burimunsi/members',{method:'POST',headers:{
  Authorization:'Bearer '+r.token.repeat(64),'X-BuriMunsi-Auth':'phone_pin','X-BuriMunsi-Installation':r.installation,
  'X-BuriMunsi-Device':r.device.repeat(64),'X-BuriMunsi-Profile':'staff','X-BuriMunsi-Group':claimedGroup}});
 let failed=true;
 try{return await gate({request,env:{DB:db}},async principal=>{
  const sessions=new PostgresPhonePinSessions({db,groupId:group});
  const directory=new PostgresOperatorDirectory({db,groupId:group,managedSessions:sessions});
  const auth=new PostgresNativeAuthStore({db,groupId:group,sessionBinding:sessions,operatorDirectory:directory,createOperatorPrincipal:no});
  const member=new PostgresCollectMemberCommands({authority:auth});
  const rematch=new PostgresRematchJobStore({authority:auth,admission:{assertInTransaction:no},canonical:{outcome:no}});
  const commands={postContribution:no,createDirectMember:(...v)=>member.createDirectMember(...v),
    setMembershipActive:(...v)=>member.setMembershipActive(...v),enqueueEligibleRematch:(...v)=>rematch.enqueueInTransaction(...v)};
  const canonical=new PostgresCanonicalStore({authority:auth,commands,identities:{policy:no,members:no,verified:no},jobs:{assertPostingLease:no}});
  const records=new PostgresRecordsStore({authority:auth,sourceReader:{revision:no,page:no,detail:no}});
  const actor={id:principal.nativeAccountId,sessionId:principal.principalSessionId};
  const result=await callback({actor,canonical,rematch,members:new MemberService({store:canonical,groupId:group}),
   records:new RecordsService({store:records,groupId:group,cursor})});failed=false;return result;
 });}finally{const finish=await work.finish({failed});assert.equal(finish.state,'settled');}
}
async function counts(){
 const q=`SELECT jsonb_build_object('members',(SELECT count(*) FROM app.memberships WHERE collection_id='synthetic-collection')::int,
  'payments',(SELECT count(*) FROM app.payments)::int,'ledger',(SELECT count(*) FROM app.ledger_entries)::int,
  'rematches',(SELECT count(*) FROM private.burimunsi_rematch_jobs WHERE collection_id='synthetic-collection')::int,
  'receipts',(SELECT count(*) FROM private.burimunsi_command_receipts WHERE collection_id='synthetic-collection')::int,
  'unpaired',(SELECT count(*) FROM private.burimunsi_scopes WHERE collection_id='synthetic-collection' AND enabled=false AND active_binding_id IS NULL)::int)`;
 const result=execFileSync(docker,['-H',host,'exec','-i',receipt.container_id,'psql','-h','/tmp','-U','supabase_admin','-d','postgres','-XAtq','-v','ON_ERROR_STOP=1'],{input:q,encoding:'utf8'});
 return JSON.parse(result);
}

let failure;
try{
 const firstId='33333333-3333-4333-8333-333333333331',staffId='33333333-3333-4333-8333-333333333332';
 const first=await run('admin',({actor,members})=>members.enroll(actor,{name:'Synthetic Member One',phone:'+250789444111',requestId:firstId}));
 assert.equal(first.groupId,group);assert.equal(first.phone,'+250789444111');assert.equal(first.active,true);assert.equal(first.balanceRwf,0);
 const replay=await run('admin',({actor,members})=>members.enroll(actor,{name:'Synthetic Member One',phone:'+250789444111',requestId:firstId}));assert.deepEqual(replay,first);
 const existing=await run('admin',({actor,members})=>members.enroll(actor,{name:'Different display name',phone:'0789444111',requestId:crypto.randomUUID()}));assert.equal(existing.id,first.id);
 await assert.rejects(run('admin',({actor,members})=>members.enroll(actor,{name:'Changed body',phone:'+250789444112',requestId:firstId})),/idempotency_conflict/);
 const staff=await run('staff',({actor,members})=>members.enroll(actor,{name:'Synthetic Member Two',phone:'+250789444112',requestId:staffId}));assert.notEqual(staff.id,first.id);
 for(const role of ['admin','staff','viewer']){
  const page=await run(role,({actor,records})=>records.page(actor,'members',{limit:40}));
  assert.equal(page.totalCount,2);assert.equal(page.items.length,2);assert(page.items.every(v=>v.groupId===group));
 }
 await assert.rejects(run('viewer',({actor,members})=>members.enroll(actor,{name:'Denied Viewer',phone:'+250789444113',requestId:crypto.randomUUID()})),/access_denied/);
 await assert.rejects(run('staff',({actor,members})=>members.setActive(actor,{memberId:first.id,active:false,expectedVersion:1,requestId:crypto.randomUUID()})),/access_denied/);
 await assert.rejects(run('admin',()=>{}, {claimedGroup:'different-collection'}),/native_scope_changed/);
 await run('admin',async({canonical,rematch})=>{
  await assert.rejects(canonical.inCanonicalTransaction(async()=>{}),/scope_unavailable/);
  await canonical.inMemberTransaction(async tx=>{assert.equal(tx.postCanonicalContribution,undefined);assert.equal(tx.planCanonicalContribution,undefined);});
  await assert.rejects(rematch.claimNext({groupId:group,owner:'synthetic-worker'}),/scope_unavailable/);
 });
 const actual=await counts();assert.deepEqual(actual,{members:2,payments:0,ledger:0,rematches:2,receipts:3,unpaired:1});
 console.log(JSON.stringify({status:'pass',schema:'exact_032',synthetic_only:true,network:'none',owner_enrollment:true,delegated_staff_enrollment:true,
  member_read_by_authorized_roles:true,same_request_replay:true,existing_member_reuse:true,changed_request_refused:true,
  viewer_enrollment_refused:true,staff_lifecycle_refused:true,cross_group_refused:true,financial_scope_refused:true,
  queued_rematch_cannot_be_claimed:true,counts:actual}));
}catch(error){failure=error;throw error;}
finally{try{await pool.end();}catch(error){if(!failure)throw error;console.error('synthetic fixture cleanup:',error.message);}}
