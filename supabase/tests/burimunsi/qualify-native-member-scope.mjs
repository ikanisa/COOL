// Native member-scope rehearsal on a fresh, owned PostgreSQL 17 socket.
import '../../functions/_shared/tests/helpers/node-postgres-import.mjs';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {withOwnedArchiveFixture} from '../../../scripts/supabase/managed-migration-next/synthetic-fixture.mjs';
import {loadRetainedMigrationPrefix} from '../../../scripts/supabase/testing/retained-postgres-history.mjs';
import {ownedFixturePool} from './postgres-fixture-pool.mjs';
const {openApplicationWork,sqlFenceBackend}=await import('../../functions/_shared/application-fence.js');
const {PostgresDatabase}=await import('../../functions/_shared/postgres.js');
const {createPhonePinRequestGate}=await import('../../functions/_shared/domain/burimunsi/phone-pin-request.js');
const {PostgresNativeAuthStore}=await import('../../functions/_shared/domain/burimunsi/postgres-auth-store.js');
const {PostgresPhonePinSessions}=await import('../../functions/_shared/domain/burimunsi/postgres-phone-pin-sessions.js');
const {PostgresOperatorDirectory}=await import('../../functions/_shared/domain/burimunsi/postgres-operator-directory.js');
const {PostgresCanonicalStore}=await import('../../functions/_shared/domain/burimunsi/postgres-canonical-store.js');
const {PostgresCollectMemberCommands}=await import('../../functions/_shared/domain/burimunsi/postgres-collect-members.js');
const {PostgresRematchJobStore}=await import('../../functions/_shared/domain/burimunsi/postgres-rematch-job-store.js');
const {PostgresRecordsStore}=await import('../../functions/_shared/domain/burimunsi/postgres-records-store.js');
const {MemberService}=await import('../../functions/_shared/domain/burimunsi/member-service.js');
const {RecordsService}=await import('../../functions/_shared/domain/burimunsi/records-service.js');

const source='fd420e522ee7d7cbbac3facdb088afb925e249dcef62a372a28e837ab26153af',group='synthetic-collection';
const roles={
 admin:{role:'admin', token:'a',device:'b',installation:'99999999-9999-4999-8999-999999999999',
   phone:'+250780000101',capabilities:['records.read','members.enroll','staff.manage']},
 staff:{role:'staff',token:'e',device:'c',installation:'99999999-9999-4999-8999-999999999992',
   phone:'+250780000102',capabilities:['records.read','members.enroll']},
 viewer:{role:'staff',token:'f',device:'d',installation:'99999999-9999-4999-8999-999999999993',
   phone:'+250780000103',capabilities:['records.read']},
};
const root=fileURLToPath(new URL('../../../',import.meta.url)).replace(/\/$/,'');
const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const digest=value=>createHash('sha256').update(value).digest('hex');

async function installMemberScope(owner) {
 const history=await loadRetainedMigrationPrefix(root);
 assert.equal(history[31].name,'20261110143000_burimunsi_native_phone_pin.sql');
 await owner.query("ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz, ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false");
 for(const item of history.slice(16,32))await owner.query(item.sql);
 await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),source,baseline]);
 const fence=randomUUID(),state=[fence,1,source];
 await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',state);
 assert.equal((await owner.query('SELECT private.collect_fence_drain($1,$2,$3) AS result',state)).rows[0].result.mode,'fenced');
 // The current Members read path uses the new keyset functions. Exercise its
 // real migration after the retained 32-position native authorization schema.
 const listing=await readFile(new URL('../../migrations/20261119114500_burimunsi_members_keyset.sql',import.meta.url),'utf8');
 await owner.query(listing);
 assert.equal((await owner.query('SELECT private.collect_fence_release($1,$2,$3) AS result',[randomUUID(),1,source])).rows[0].result.mode,'open');
}

async function seedMemberScope(admin,pool){
 const at=new Date().toISOString(),ownerId=randomUUID(),authId=randomUUID(),sharedId=randomUUID();
 const wallet='synthetic-wallet',email='fixture-owner@example.invalid';
 const actors=Object.values(roles).map((role,index)=>({...role,userId:index===0?ownerId:randomUUID(),accountId:randomUUID(),publicId:'98000'+(index+1)}));
 const owner=actors[0];
 await admin.query('BEGIN');
 try{
  await admin.query("SELECT set_config('burimunsi.collection_id',$1,true)",[group]);
  const corrected=await admin.query("UPDATE app.users SET public_id='989999' WHERE id='synthetic-primary' AND public_id='synthetic-public'");
  assert.equal(corrected.rowCount,1);
  for(const actor of actors) await admin.query(`INSERT INTO app.users(id,full_name,public_id,member_type,created_at,updated_at)
   VALUES($1,'Synthetic Operator',$2,'operator',$3,$3)`,[actor.userId,actor.publicId,at]);
  await admin.query('INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,$2,now())',[authId,email]);
  await admin.query("INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,$2,'owned-pg-fixture')",[authId,ownerId]);
  await admin.query(`INSERT INTO app.admin_users(id,email,role,status,password_hash,created_at,updated_at)
    VALUES($1,$2,'admin','active','supabase-managed',1,1)`,[sharedId,email]);
  await admin.query(`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
    VALUES($1,$2,$2,$3)`,[sharedId,ownerId,at]);
  await admin.query(`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
    VALUES($1,$1,$2,'Synthetic Scope','community',$3,$3)`,[group,ownerId,at]);
  await admin.query(`INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at)
    VALUES($1,'mtn_momo','00000','Fixture Wallet',repeat('c',64),'Africa/Kigali',$2)`,[wallet,at]);
  await admin.query('INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at) VALUES($1,$2,false,1)',[group,wallet]);
  await admin.query(`INSERT INTO private.burimunsi_operator_approvals(collection_id,principal_user_id,admin_user_id,phone,role,capabilities,active,version,approved_by,created_at,updated_at)
    VALUES($1,$2,$3,$4,'admin',$5::text[],true,1,$2,1,1)`,[group,ownerId,sharedId,owner.phone,owner.capabilities]);
  for(const actor of actors){
   if(actor!==owner)await admin.query(`INSERT INTO private.burimunsi_native_staff_delegations(collection_id,principal_user_id,parent_account_id,capability_ceiling,created_request_id,creation_fingerprint,created_at)
     VALUES($1,$2,$3,$4::text[],$5,repeat('d',64),1)`,[group,actor.userId,owner.accountId,actor.capabilities,randomUUID()]);
   await admin.query(`INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
     VALUES($1,$2,$3,$4,'Synthetic Operator',$5,$6::text[],'{}'::jsonb,1,1)`,
     [actor.accountId,group,actor.userId,actor.phone,actor.role,actor.capabilities]);
  }
  await admin.query('COMMIT');
 }catch(error){await admin.query('ROLLBACK');throw error;}

 const work=await openApplicationWork({backend:sqlFenceBackend(pool,pool),sourceSha256:source,kind:'http_collect'});
 const db=new PostgresDatabase(pool,{},work);
 let failed=true;
 try{
  for(const actor of actors)await db.transaction(async sql=>{
   await db.context(sql);
   const now=Date.now();
   const rows=await sql.unsafe(`SELECT private.burimunsi_pin_create_session(
    $1,$2::uuid,$3::uuid,'staff',$4,1,$5::uuid,$6,$7,$8,1) AS result`,
    [group,actor.accountId,actor.installation,digest(actor.device.repeat(64)),randomUUID(),digest(actor.token.repeat(64)),now,now+1800000]);
   assert.equal(rows[0].result.created,true);
  });
  failed=false;
 }finally{assert.equal((await work.finish({failed})).state,'settled');}
}

const no=()=>{throw Error('financial or external port must not be called')};
const cursor={create:no,read:no};
async function run(pool,role,callback,{claimedGroup=group}={}){
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
async function counts(admin){
 const q=`SELECT jsonb_build_object('members',(SELECT count(*) FROM app.memberships WHERE collection_id='synthetic-collection')::int,
  'payments',(SELECT count(*) FROM app.payments)::int,'ledger',(SELECT count(*) FROM app.ledger_entries)::int,
  'rematches',(SELECT count(*) FROM private.burimunsi_rematch_jobs WHERE collection_id='synthetic-collection')::int,
  'receipts',(SELECT count(*) FROM private.burimunsi_command_receipts WHERE collection_id='synthetic-collection')::int,
  'unpaired',(SELECT count(*) FROM private.burimunsi_scopes WHERE collection_id='synthetic-collection' AND enabled=false AND active_binding_id IS NULL)::int)`;
 const {rows}=await admin.query(q+' AS counts');
 return rows[0].counts;
}

async function qualify(pool,admin){
 const firstId='33333333-3333-4333-8333-333333333331',staffId='33333333-3333-4333-8333-333333333332';
 const first=await run(pool,'admin',({actor,members})=>members.enroll(actor,{name:'Synthetic Member One',phone:'+250789444111',requestId:firstId}));
 assert.equal(first.groupId,group);assert.equal(first.phone,'+250789444111');assert.equal(first.active,true);assert.equal(first.balanceRwf,0);
 const replay=await run(pool,'admin',({actor,members})=>members.enroll(actor,{name:'Synthetic Member One',phone:'+250789444111',requestId:firstId}));assert.deepEqual(replay,first);
 const existing=await run(pool,'admin',({actor,members})=>members.enroll(actor,{name:'Different display name',phone:'0789444111',requestId:crypto.randomUUID()}));assert.equal(existing.id,first.id);
 await assert.rejects(run(pool,'admin',({actor,members})=>members.enroll(actor,{name:'Changed body',phone:'+250789444112',requestId:firstId})),/idempotency_conflict/);
 const staff=await run(pool,'staff',({actor,members})=>members.enroll(actor,{name:'Synthetic Member Two',phone:'+250789444112',requestId:staffId}));assert.notEqual(staff.id,first.id);
 for(const role of ['admin','staff','viewer']){
  const page=await run(pool,role,({actor,records})=>records.page(actor,'members',{limit:40}));
  assert.equal(page.totalCount,2);assert.equal(page.items.length,2);assert(page.items.every(v=>v.groupId===group));
 }
 await assert.rejects(run(pool,'viewer',({actor,members})=>members.enroll(actor,{name:'Denied Viewer',phone:'+250789444113',requestId:crypto.randomUUID()})),/access_denied/);
 await assert.rejects(run(pool,'staff',({actor,members})=>members.setActive(actor,{memberId:first.id,active:false,expectedVersion:1,requestId:crypto.randomUUID()})),/access_denied/);
 await assert.rejects(run(pool,'admin',()=>{}, {claimedGroup:'different-collection'}),/native_scope_changed/);
 await run(pool,'admin',async({canonical,rematch})=>{
  await assert.rejects(canonical.inCanonicalTransaction(async()=>{}),/scope_unavailable/);
  await canonical.inMemberTransaction(async tx=>{assert.equal(tx.postCanonicalContribution,undefined);assert.equal(tx.planCanonicalContribution,undefined);});
  await assert.rejects(rematch.claimNext({groupId:group,owner:'synthetic-worker'}),/scope_unavailable/);
 });
 const actual=await counts(admin);assert.deepEqual(actual,{members:2,payments:0,ledger:0,rematches:2,receipts:3,unpaired:1});
 return {status:'pass',schema:'retained_032_plus_member_keyset',synthetic_only:true,network:'none',owner_enrollment:true,delegated_staff_enrollment:true,
  member_read_by_authorized_roles:true,same_request_replay:true,existing_member_reuse:true,changed_request_refused:true,
  viewer_enrollment_refused:true,staff_lifecycle_refused:true,cross_group_refused:true,financial_scope_refused:true,
  queued_rematch_cannot_be_claimed:true,counts:actual};
}

const result=await withOwnedArchiveFixture(async ({owner,admin,database,fixtureRoot})=>{
 await installMemberScope(owner);
 const {host:socket,port}=owner.connectionParameters;
 const pool=await ownedFixturePool({root:fixtureRoot,socket,port:Number(port),database,user:'postgres',clusterName:'collect_archive_next_fixture'});
 try{
  await seedMemberScope(admin,pool);
  return await qualify(pool,admin);
 }finally{await pool.end();}
});
console.log(JSON.stringify(result));
