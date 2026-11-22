import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fixture} from './admin_sms_support/fixture.mjs';
import {exportDtos} from './support/dto_export.mjs';
import {captureDeviceSeconds} from '../src/admin_sms_receipts.js';

const base='/api/admin/sms/receipts',hash=v=>createHash('sha256').update(v).digest('hex');
const read=(f,cookie,path=base)=>f.call(path,{method:'GET',cookie});
async function operator(f,role='staff'){
 const account=await f.seedAccount({role,email:role==='owner'?'info@ikanisa.com':role+'-sms@example.test'});
 return {account,...await f.login(account)};
}
async function captures(f){
 const member=await f.seedMember({name:'Recorded Capture Owner'}),session=randomUUID(),seconds=Math.floor(Date.now()/1000);
 await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)")
  .bind(session,member.id,seconds,seconds,seconds+3600).run();
 const values=[['received','2026-10-16T14:00:00+02:00'],['under_review','2026-10-15T12:00:00'],['rejected',null],['linked','1969-12-31T23:59:59.999999999Z']];
 const output=[];
 for(let i=0;i<values.length;i++){
  const id=randomUUID(),[status,received]=values[i],created=`2026-10-${String(16-i).padStart(2,'0')}T12:00:00.000Z`,raw='Private unparsed capture '+i;
  // Controlled declared source rows only. This fixture does not claim native
  // capture admission or parsed financial facts. No raw R2 object is needed.
  await f.db.prepare(`INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,status,created_at)
   VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id,member.id,session,randomUUID(),hash(raw),hash('private receiver'),`sms/private-${id}`,hash('encrypted object'),64,received,status,created).run();
  output.push({id,status,received,created,hash:hash(raw)});
 }
 return {member,rows:output};
}
const noPrivate=value=>{
 const text=JSON.stringify(value);for(const forbidden of ['object_key','object_sha256','receiver_hash','raw_body','raw_sender','originating_session_id','client_envelope_id','Private unparsed capture'])assert.ok(!text.includes(forbidden),forbidden);
};
const scalar=async(f,table)=>(await f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n;

test('Staff and Admin read actual capture list/detail pages without fabricated facts or financial finality',async t=>{
 const f=await fixture(t),staff=await operator(f),admin=await operator(f,'admin'),data=await captures(f);
 const session=await read(f,staff.cookie,'/api/admin/auth/session');assert.ok(session.body.user.permissions.includes('sms.read'));
 for(const denied of ['sms.raw.reveal','sms.reveal','sms.extract','assisted_sms.read','assisted_sms.manage'])assert.ok(!session.body.user.permissions.includes(denied));
 const first=await read(f,staff.cookie,base+'?limit=2&offset=0'),next=await read(f,staff.cookie,base+'?limit=2&offset=2'),all=await read(f,staff.cookie,base+'?limit=100&offset=0');
 for(const response of [first,next,all]){assert.equal(response.status,200,JSON.stringify(response));noPrivate(response.body);}
 assert.equal(first.body.total,4);assert.equal(first.body.next_offset,2);assert.equal(next.body.next_offset,null);
 assert.deepEqual([...first.body.rows,...next.body.rows],all.body.rows);assert.equal(new Set(all.body.rows.map(r=>r.id)).size,4);
 const details=[];
 for(let i=0;i<data.rows.length;i++){
  const record=data.rows[i],row=all.body.rows[i],detail=await read(f,staff.cookie,`${base}/capture/${record.id}?limit=25&offset=0`);
  assert.equal(detail.status,200,JSON.stringify(detail));assert.equal(detail.body.current_actor_id,staff.account.adminId);assert.deepEqual(detail.body.resource,row);
  assert.deepEqual(detail.body.related.duplicate_references,{rows:[],total:0,limit:25,offset:0,next_offset:null});assert.equal(detail.body.can_extract,false);
  assert.equal(row.source_kind,'capture');assert.equal(row.status,record.status);assert.equal(row.evidence_level,'client_received');assert.equal(row.source_sha256,record.hash);
  assert.equal(row.received_at_device,record.received);assert.equal(row.received_at,captureDeviceSeconds(record.received));assert.equal(row.version,1);
  assert.equal(row.extraction_status,'not_extracted');assert.equal(row.provider_confirmation,false);assert.equal(row.settlement_status,'not_asserted');assert.equal(row.source_content_reveal_required,true);
  for(const field of ['source_fact_id','parser_version','source_body_sha256','source_payload_sha256','parsed_at','payer_name','payer_phone','payee_momo_number','amount_rwf','wallet_balance_rwf','network','direction','is_payment','transaction_id','transaction_reference'])assert.equal(row[field],null,field);
  assert.equal(row.duplicate_reference_count,0);assert.equal(row.conflicting_reference_count,0);noPrivate(detail.body);details.push(detail.body);
 }
 const adminRead=await read(f,admin.cookie);assert.equal(adminRead.status,200);assert.deepEqual(adminRead.body.rows,all.body.rows);
 assert.equal(await scalar(f,'ledger_entries'),0);assert.equal(await scalar(f,'payments'),0);
 await exportDtos('admin-sms-capture-dto-examples.json',{scope:'Isolated real workerd/D1 HTTP metadata responses over declared capture rows; not hosted/native/provider proof.',session:session.body,list:first.body,list_next:next.body,list_all:all.body,detail:details[0],details});
});

test('metadata search and filters are bounded, literal and preserve canonical capture state',async t=>{
 const f=await fixture(t),staff=await operator(f),data=await captures(f);
 for(const query of [data.rows[0].id,data.member.public_id,'Recorded Capture']){
  const result=await read(f,staff.cookie,base+'?search='+encodeURIComponent(query));assert.equal(result.status,200);assert.ok(result.body.rows.length>0);
 }
 for(const status of ['received','under_review','rejected','linked']){const result=await read(f,staff.cookie,base+'?status='+status);assert.equal(result.status,200);assert.equal(result.body.total,1);assert.equal(result.body.rows[0].status,status);}
 for(const query of ['source_kind=receiver','source_kind=member','extraction_status=parsed','extraction_status=needs_review','duplicates=all','duplicates=conflicting',"search=%25%27_OR_1%3D1--"]){const result=await read(f,staff.cookie,base+'?'+query);assert.equal(result.status,200);assert.equal(result.body.total,0);}
 assert.equal((await read(f,staff.cookie,base+'?source_kind=capture&extraction_status=not_extracted')).body.total,4);
 assert.deepEqual((await read(f,staff.cookie,base+'?offset=100')).body,{rows:[],total:4,limit:25,offset:100,next_offset:null});
 for(const query of ['limit=0','limit=101','offset=-1','limit=1&limit=2','search=%0a','source_kind=unknown','status=confirmed','extraction_status=confirmed','duplicates=unknown','user_id='+data.member.id])assert.equal((await read(f,staff.cookie,base+'?'+query)).status,400,query);
});

test('metadata permission is capped and no read grant enables raw/extraction/assisted actions',async t=>{
 const f=await fixture(t),staff=await operator(f),data=await captures(f),id=data.rows[0].id;
 assert.equal((await f.call(base,{cookie:staff.cookie,data:{}})).status,405);
 for(const path of [`${base}/capture/${id}/content`,`${base}/capture/${id}/extract`,'/api/admin/sms/requests/'+randomUUID()])assert.equal((await read(f,staff.cookie,path)).status,404,path);
 assert.equal((await f.call(`${base}/capture/${id}/extract`,{cookie:staff.cookie,data:{reason:'Unadmitted extraction'},headers:{'Idempotency-Key':randomUUID()}})).status,405);
 assert.equal((await f.call('/api/admin/notification-operator',{cookie:staff.cookie,data:{action:'list_pending'},headers:{'X-Collect-Admin':'1'}})).status,403);
 assert.equal((await read(f,staff.cookie,`${base}/member/${id}`)).status,404);
 assert.equal((await read(f,staff.cookie,`${base}/capture/${randomUUID()}`)).status,404);
 assert.equal((await read(f,null)).status,401);assert.equal((await f.call(base,{method:'GET',cookie:staff.cookie,origin:'https://foreign.example'})).status,403);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='sms.read'").bind(staff.account.userId).run();
 for(const path of [base,`${base}/capture/${id}`])assert.equal((await read(f,staff.cookie,path)).status,403);
 assert.equal(await scalar(f,'assisted_sms_jobs'),0);assert.equal(await scalar(f,'assisted_sms_send_starts'),0);
});

test('permission or account revocation before guarded metadata batch releases no rows',async t=>{
 for(const action of ['permission','account'])await t.test(action,async t=>{
  const f=await fixture(t),staff=await operator(f);await captures(f);
  f.setGate(async()=>{await(action==='permission'?f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='sms.read'").bind(staff.account.userId):f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(staff.account.adminId)).run();});
  const result=await f.call(base,{method:'GET',cookie:staff.cookie,headers:{'X-Test-Pause':'sms_metadata_read'}});
  assert.equal(result.status,403,JSON.stringify(result));assert.equal(result.body.rows,undefined);
 });
});

test('opaque device text is preserved; only real explicit calendar/zone datetimes project signed whole seconds',()=>{
 const samples=[[null,null],['2026-10-16',null],['2026-10-16T12:00:00',null],['2026-02-30T12:00:00Z',null],['2026-10-16T24:00:00Z',null],['2026-10-16T12:60:00Z',null],['2026-10-16T12:00:60Z',null],['2026-10-16T12:00:00+24:00',null],['1970-01-01T00:00:00Z',0],['1969-12-31T23:59:59.999999999Z',-1],['1970-01-01T00:00:00.999Z',0],['1970-01-01T01:00:00+01:00',0],['0000-01-01T00:00:00Z',-62167219200],['0099-01-01T00:00:00Z',-59042995200],['2000-02-29T00:00:00Z',951782400]];
 for(const [raw,expected] of samples)assert.equal(captureDeviceSeconds(raw),expected,String(raw));
});

test('0013 upgrade adopts active canonical operator principals only and adds no raw or assisted grant',async t=>{
 const f=await fixture(t,{}, {migrationsThrough:12}),accounts=[];
 for(const role of ['owner','admin','staff'])accounts.push(await f.seedAccount({role,email:role==='owner'?'info@ikanisa.com':role+'-pre13@example.test'}));
 const revoked=await f.seedAccount({role:'staff',status:'revoked',email:'revoked-pre13@example.test'}),invited=await f.seedAccount({role:'staff',status:'invited',email:'invited-pre13@example.test'}),unlinked=await f.seedAccount({role:'staff',linked:false,email:'unlinked-pre13@example.test'}),suspended=await f.seedAccount({role:'staff',email:'suspended-pre13@example.test'});
 await f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(suspended.userId).run();
 const before=(await f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results;
 const require=createRequire(import.meta.url),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
 const sql=await readFile(new URL('../migrations/0013_sms_receipt_metadata_read.sql',import.meta.url),'utf8');await f.db.batch(unstable_splitSqlQuery(sql).map(q=>f.db.prepare(q)));
 const grants=(await f.db.prepare("SELECT * FROM admin_grants WHERE permission='sms.read' ORDER BY user_id").all()).results;
 assert.deepEqual(new Set(grants.map(r=>r.user_id)),new Set(accounts.map(a=>a.userId)));
 assert.deepEqual((await f.db.prepare("SELECT * FROM admin_grants WHERE permission!='sms.read' ORDER BY user_id,permission").all()).results,before);
 for(const a of accounts){const row=await f.db.prepare('SELECT member_type,phone,email FROM users WHERE id=?').bind(a.userId).first();assert.equal(row.member_type,'operator');assert.equal(row.phone,null);assert.equal(row.email,null);const login=await f.login(a);assert.ok(login.body.user.permissions.includes('sms.read'));}
 for(const account of [revoked,invited,unlinked,suspended])assert.ok(!grants.some(g=>g.user_id===account.userId));
 const later=await f.seedAccount({role:'staff',email:'later@example.test'});assert.equal((await f.db.prepare("SELECT count(*) AS n FROM admin_grants WHERE user_id=? AND permission='sms.read'").bind(later.userId).first()).n,1);
 await f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(later.adminId).run();
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM admin_grants WHERE user_id=? AND permission='sms.read'").bind(later.userId).first()).n,0);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM admin_grants WHERE permission IN('sms.raw.reveal','sms.extract','sms.reveal','assisted_sms.read','assisted_sms.manage')").first()).n,0);
});
