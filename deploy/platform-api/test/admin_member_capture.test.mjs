import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {fixture} from './admin_member_support/fixture.mjs';
import {exportDtos} from './support/dto_export.mjs';
import {captureDeviceSeconds} from '../src/admin_sms_receipts.js';

const base='/api/admin/gateway/receipts',hash=v=>createHash('sha256').update(v).digest('hex');
const read=(f,cookie,path=base)=>f.call(path,{method:'GET',cookie});
async function operator(f,role='staff'){
 const account=await f.seedAccount({role,email:role==='owner'?'info@ikanisa.com':role+'-member-capture@example.test'});
 return {account,...await f.login(account)};
}
async function captures(f){
 const member=await f.seedMember({name:'Recorded Capture Owner'}),session=randomUUID(),seconds=Math.floor(Date.now()/1000);
 await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)")
  .bind(session,member.id,seconds,seconds,seconds+3600).run();
 const statuses=['received','under_review','rejected','linked'];
 const times=['2026-10-16T14:00:00+02:00','2026-10-15T12:00:00',null,'1969-12-31T23:59:59.999999999Z','0000-01-01T00:00:00+00:01','1970-01-01T00:00:00Z','2026-10-16','2026-02-30T12:00:00Z'];
 const output=[];
 for(let i=0;i<28;i++){
  const id=randomUUID(),status=statuses[i%4],received=times[i%times.length],created=new Date(Date.UTC(2026,9,16,12)-i*1000).toISOString(),raw='Private capture '+i;
  // Declared synthetic canonical captures only; no native admission or parser,
  // transaction, review, provider or retained raw-object access is asserted.
  await f.db.prepare(`INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,status,created_at)
   VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id,member.id,session,randomUUID(),hash(raw),hash('private receiver'),`sms/private-${id}`,hash('encrypted object'),64,received,status,created).run();
  output.push({id,status,received,created,hash:hash(raw)});
 }
 return {member,rows:output};
}
function noPrivate(value){const text=JSON.stringify(value);for(const forbidden of ['object_key','object_sha256','receiver_hash','raw_body','raw_sender','originating_session_id','client_envelope_id','Private capture'])assert.ok(!text.includes(forbidden),forbidden);}
const scalar=async(f,table)=>(await f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n;

test('Staff and Admin receive exact truthful capture metadata across actual list/detail pagination',async t=>{
 const f=await fixture(t),staff=await operator(f),admin=await operator(f,'admin'),data=await captures(f);
 const session=await read(f,staff.cookie,'/api/admin/auth/session');assert.ok(session.body.user.permissions.includes('payments.read'));
 const first=await read(f,staff.cookie,base+'?limit=25&offset=0'),next=await read(f,staff.cookie,base+'?limit=25&offset=25'),all=await read(f,staff.cookie,base+'?limit=100&offset=0');
 for(const response of [first,next,all]){assert.equal(response.status,200,JSON.stringify(response));assert.deepEqual(Object.keys(response.body).sort(),['rows','total']);noPrivate(response.body);}
 assert.equal(first.body.total,28);assert.equal(first.body.rows.length,25);assert.equal(next.body.rows.length,3);assert.deepEqual([...first.body.rows,...next.body.rows],all.body.rows);
 const fields=['id','user_id','body_sha256','status','version','received_at','created_at','public_id','display_name','transaction_id','reviewed_at','source_kind','received_at_device','evidence_level','provider_confirmation','settlement_status','source_content_reveal_required'].sort(),details=[];
 for(let i=0;i<data.rows.length;i++){
  const source=data.rows[i],row=all.body.rows[i];assert.deepEqual(Object.keys(row).sort(),fields);
  assert.equal(row.id,source.id);assert.equal(row.status,source.status);assert.equal(row.body_sha256,source.hash);assert.equal(row.created_at,source.created);assert.equal(row.received_at_device,source.received);
  const seconds=captureDeviceSeconds(source.received);assert.equal(row.received_at,seconds===null?null:new Date(seconds*1000).toISOString());
  assert.equal(row.source_kind,'capture');assert.equal(row.evidence_level,'client_received');assert.equal(row.version,1);assert.equal(row.transaction_id,null);assert.equal(row.reviewed_at,null);
  assert.equal(row.provider_confirmation,false);assert.equal(row.settlement_status,'not_asserted');assert.equal(row.source_content_reveal_required,true);
  if(i<8){const detail=await read(f,staff.cookie,`${base}/${source.id}`);assert.equal(detail.status,200,JSON.stringify(detail));assert.deepEqual(Object.keys(detail.body).sort(),['can_manage','current_actor_id','related','related_truncated','resource','resource_type']);assert.deepEqual(detail.body.resource,row);assert.equal(detail.body.current_actor_id,staff.account.adminId);assert.equal(detail.body.resource_type,'member_receipts');assert.equal(detail.body.can_manage,false);assert.equal(detail.body.related_truncated,false);assert.deepEqual(detail.body.related,{reviews:[]});noPrivate(detail.body);details.push(detail.body);}
 }
 const adminRead=await read(f,admin.cookie);assert.equal(adminRead.status,200);assert.deepEqual(adminRead.body.rows,first.body.rows);
 const adminDetail=await read(f,admin.cookie,`${base}/${data.rows[0].id}`);assert.equal(adminDetail.status,200);assert.equal(adminDetail.body.can_manage,false);
 assert.equal(await scalar(f,'ledger_entries'),0);assert.equal(await scalar(f,'payments'),0);
 await exportDtos('admin-member-capture-dto-examples.json',{scope:'Isolated actual workerd/D1 HTTP responses over declared canonical capture rows; not hosted/native/provider proof.',session:session.body,list:first.body,list_next:next.body,list_all:all.body,detail:details[0],details});
});

test('capture statuses, bounded pagination and unsupported legacy status searches preserve recorded facts',async t=>{
 const f=await fixture(t),staff=await operator(f);await captures(f);
 for(const status of ['received','under_review','rejected','linked']){const response=await read(f,staff.cookie,base+'?status='+status);assert.equal(response.status,200);assert.equal(response.body.total,7);assert.ok(response.body.rows.every(row=>row.status===status));}
 for(const status of ['needs_review','reviewed']){const response=await read(f,staff.cookie,base+'?status='+status);assert.equal(response.status,200);assert.deepEqual(response.body,{rows:[],total:0});}
 assert.deepEqual((await read(f,staff.cookie,base+'?offset=100')).body,{rows:[],total:28});
 for(const query of ['limit=0','limit=101','offset=-1','offset=2147483648','limit=1&limit=2','status=confirmed','search=private','user_id='+randomUUID()])assert.equal((await read(f,staff.cookie,base+'?'+query)).status,400,query);
});

test('capture reads grant no content, transaction lookup, review, raw or assisted action',async t=>{
 const f=await fixture(t),staff=await operator(f),admin=await operator(f,'admin'),data=await captures(f),id=data.rows[0].id;
 for(const actor of [staff,admin]){
  assert.equal((await f.call(base,{cookie:actor.cookie,data:{}})).status,405);
  for(const suffix of ['/content','/transactions','/review'])assert.equal((await read(f,actor.cookie,base+'/'+id+suffix)).status,404);
  assert.equal((await f.call(`${base}/${id}/review`,{cookie:actor.cookie,data:{expected_version:1,outcome:'reviewed',reason:'No review authority',transaction_id:null},headers:{'Idempotency-Key':randomUUID()}})).status,405);
 }
 assert.equal((await read(f,staff.cookie,`${base}/${randomUUID()}`)).status,404);assert.equal((await read(f,staff.cookie,`${base}/${id}?limit=25`)).status,400);
 assert.equal((await read(f,null)).status,401);assert.equal((await f.call(base,{method:'GET',cookie:staff.cookie,origin:'https://foreign.example'})).status,403);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='payments.read'").bind(staff.account.userId).run();
 for(const path of [base,`${base}/${id}`])assert.equal((await read(f,staff.cookie,path)).status,403);
 for(const table of ['ledger_entries','payments','request_receipts','assisted_sms_jobs'])assert.equal(await scalar(f,table),0,table);
});

test('current permission or account revocation before the guarded read releases no capture rows',async t=>{
 for(const action of ['permission','account'])await t.test(action,async t=>{
  const f=await fixture(t),staff=await operator(f);await captures(f);
  f.setGate(async()=>{await(action==='permission'?f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='payments.read'").bind(staff.account.userId):f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(staff.account.adminId)).run();});
  const result=await f.call(base,{method:'GET',cookie:staff.cookie,headers:{'X-Test-Pause':'member_metadata_read'}});assert.equal(result.status,403,JSON.stringify(result));assert.equal(result.body.rows,undefined);
 });
});
