import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fixture} from './support/notification_operator_integration_fixture.mjs';
import {signed,totp} from './support/auth_fixture.mjs';
const base='/api/admin/notification-operator';
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r.body));return r.body.result??r.body;};
const hash=x=>createHash('sha256').update(x).digest('hex');
const count=async(s,table)=>(await s.f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n;
const post=(s,path,data,extra={})=>s.f.call(base+path,{cookie:s.operator.cookie,data,headers:{'X-Collect-Admin':'1',...extra}});
const get=(s,path,extra={})=>s.f.call(base+path,{method:'GET',cookie:s.operator.cookie,headers:extra});
const access=(s,enabled,expected= !enabled)=>post(s,'/access',{request_id:randomUUID(),expected_read:expected,expected_manage:expected,expected_decision_revision:Number(expected),enabled,...(enabled?{owner_confirmation:true}:{})});
const policy=(s,revision,enabled=false)=>post(s,'/policies/'+s.group,{request_id:randomUUID(),expected_revision:revision,enabled,...(enabled?{owner_confirmation:true}:{})});
async function setup(t,{role='owner',assurance=2,through=12,enabled=true}={}){
 const f=await fixture(t,{}, {migrationsThrough:through}),account=await f.seedAccount({role,email:role==='owner'?'info@ikanisa.com':role+'@history.synthetic.test'}),login=await f.login(account),operator=assurance===2?await f.stepUp(login):login;
 const member=await f.seedMember(),group=randomUUID(),date=new Date().toISOString();
 await f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,'Synthetic history group','ikimina',?,?)").bind(group,'history-'+group,member.id,date,date).run();
 const s={f,account,operator,member,group};if(through===12&&enabled&&role==='owner'&&assurance===2)ok(await access(s,true,false));return s;
}
async function bearer(s){const current=ok(await s.f.call('/api/admin/auth/session',{method:'GET',cookie:s.operator.cookie})).user;
 const row=await s.f.db.prepare('SELECT a.* FROM auth_sessions a JOIN admin_sessions p ON p.auth_session_id=a.id WHERE p.public_id=?').bind(current.sessionId).first(),seconds=Math.floor(Date.now()/1000);
 return signed({iss:'collect-test',aud:'collect',sub:s.account.userId,session_id:row.id,iat:seconds,exp:seconds+300,auth_time:row.auth_at,role:'authenticated',aal:'aal2',mfa_at:row.mfa_at,mfa_factor_id:row.mfa_factor_id});
}
const generic=(s,token)=>s.f.call('/v1/rpc/admin_list_notifications',{origin:'https://collect.example',data:{},headers:{Authorization:'Bearer '+token}});
async function fresh(s){const factor=s.operator.factor,login=await s.f.login(s.account),challenge=await s.f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:factor.id}});assert.equal(challenge.status,200);
 const verified=await s.f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:factor.id,challenge_id:challenge.body.challenge_id,code:totp(factor.totp.secret,Math.floor(Date.now()/30000)+1)}});assert.equal(verified.status,200,JSON.stringify(verified));return verified;}
async function addKinds(s){const configured=ok(await policy(s,0)),materialized=ok(await post(s,'/materialize',{request_id:randomUUID(),collection_id:s.group,limit:1}));return {configured,materialized};}
async function durable(s){return {receipts:(await s.f.db.prepare('SELECT * FROM request_receipts ORDER BY user_id,request_id').all()).results,audits:(await s.f.db.prepare('SELECT * FROM audit_log ORDER BY id').all()).results,aliases:(await s.f.db.prepare('SELECT * FROM admin_bridge_requests ORDER BY request_id').all()).results,grants:(await s.f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results};}
function noAuthority(value){assert.equal(value.may_send,false);assert.equal(value.replay_authorized,false);assert.equal(value.recorded_state_only,true);for(const field of ['destination_e164','message_body','claim_token','body_ciphertext','destination_ciphertext','payment_id','entry_id','cancel_path'])assert.equal(JSON.stringify(value).includes('"'+field+'"'),false);}

test('separate assisted capabilities preserve real API17 generic read revoke/regrant/relabel and linked-account lifecycle',async t=>{
 const s=await setup(t,{role:'admin',through:11,enabled:false}),token=await bearer(s),db=s.f.db;
 const grant=()=>db.prepare('INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(s.account.userId,'notifications.read','controlled_generic_history',new Date().toISOString()).run();
 const revoke=()=>db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='notifications.read'").bind(s.account.userId).run();
 const roundtrip=async()=>{assert.equal((await grant()).meta.changes,1);ok(await generic(s,token));await revoke();assert.equal((await generic(s,token)).status,403);assert.equal((await grant()).meta.changes,1);ok(await generic(s,token));
  await db.prepare("UPDATE admin_grants SET permission='notifications.history_test' WHERE user_id=? AND permission='notifications.read'").bind(s.account.userId).run();assert.equal((await generic(s,token)).status,403);await db.prepare("UPDATE admin_grants SET permission='notifications.read',granted_by='controlled_generic_history' WHERE user_id=? AND permission='notifications.history_test'").bind(s.account.userId).run();ok(await generic(s,token));};
 await roundtrip();const unrelated=(await db.prepare("SELECT * FROM admin_grants WHERE user_id=? AND permission!='notifications.read' ORDER BY permission").bind(s.account.userId).all()).results;
 const require=createRequire(import.meta.url),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler'),sql=await readFile(new URL('../migrations/0012_notification_operator.sql',import.meta.url),'utf8');await db.batch(unstable_splitSqlQuery(sql).map(q=>db.prepare(q)));ok(await generic(s,token));await revoke();await roundtrip();
 assert.deepEqual((await db.prepare("SELECT * FROM admin_grants WHERE user_id=? AND permission!='notifications.read' ORDER BY permission").bind(s.account.userId).all()).results,unrelated);
 for(const permission of ['assisted_sms.read','assisted_sms.manage']){const blocked=await db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(s.account.userId,permission,new Date().toISOString()).run();assert.equal(blocked.meta.changes,0);}
 await db.prepare('UPDATE admin_users SET auth_version=auth_version+1 WHERE id=?').bind(s.account.adminId).run();assert.equal((await db.prepare("SELECT count(*) AS n FROM admin_grants WHERE user_id=? AND permission='notifications.read'").bind(s.account.userId).first()).n,1);s.operator=await fresh(s);ok(await generic(s,await bearer(s)));assert.equal((await get(s,'/operations')).status,403);assert.equal((await get(s,'/access')).status,403);
 const second=await s.f.seedAccount({role:'admin',email:'new-generic-history@synthetic.test'});assert.equal((await db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(second.userId,'notifications.read',new Date().toISOString()).run()).meta.changes,1);
});
test('explicit assisted self-enable/revoke never deletes or relabels an existing generic notification history grant',async t=>{
 const s=await setup(t,{enabled:false}),db=s.f.db,token=await bearer(s),timestamp=new Date().toISOString();await db.prepare('INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(s.account.userId,'notifications.read','controlled_generic_history',timestamp).run();
 const old=await db.prepare("SELECT * FROM admin_grants WHERE user_id=? AND permission='notifications.read'").bind(s.account.userId).first();ok(await generic(s,token));assert.equal(ok(await get(s,'/access')).read_granted,false);
 ok(await access(s,true,false));ok(await access(s,false,true));assert.equal(ok(await get(s,'/access')).can_operate,false);ok(await generic(s,token));assert.deepEqual(await db.prepare("SELECT * FROM admin_grants WHERE user_id=? AND permission='notifications.read'").bind(s.account.userId).first(),old);
 assert.equal((await db.prepare("SELECT count(*) AS n FROM admin_account_role_capabilities WHERE permission IN('notifications.read','notifications.manage')").first()).n,0);
});
test('own metadata history exposes exactly three named request kinds and fixed original-status paths without content or authority',async t=>{
 const s=await setup(t),{configured,materialized}=await addKinds(s),before=await durable(s),value=ok(await get(s,'/operations'));assert.equal(value.items.length,3);assert.deepEqual(new Set(value.items.map(x=>x.kind)),new Set(['access','policy','materialization']));assert.equal(value.next_cursor,null);assert.equal(value.original_session_only,true);noAuthority(value);
 for(const item of value.items){assert.deepEqual(Object.keys(item).sort(),['kind','may_send','recorded_at','recorded_outcome','recorded_state_only','request_id','status_path'].sort());assert.match(item.status_path,new RegExp('^/api/admin/notification-operator/(access/operations|policies/operations|materialize)/'+item.request_id+'$'));const status=ok(await get(s,item.status_path.slice(base.length)));assert.equal(status.observed,true);assert.equal(status.may_send,false);}
 assert.equal(value.items.find(x=>x.kind==='policy').request_id,configured.request_id);assert.equal(value.items.find(x=>x.kind==='materialization').request_id,materialized.request_id);assert.deepEqual(await durable(s),before);
});
test('declared synthetic retained-metadata tie cohort paginates completely once with bounded stable cursors and no grants',async t=>{
 const s=await setup(t),source=await s.f.db.prepare("SELECT * FROM request_receipts WHERE operation='assisted_sms.access.set'").first(),ids=[source.request_id],rows=[];
 // Generated retained metadata solely for tie/bound tests. These are not
 // HTTP owner decisions or a production grant, and no transient grant guard
 // exists. The real API-created source record is retained unchanged.
 for(let i=0;i<28;i++){const requestId=randomUUID(),value={...JSON.parse(source.response_json),request_id:requestId};ids.push(requestId);rows.push(s.f.db.prepare('INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(?,?,?,?,?,?,?)').bind(source.user_id,requestId,source.operation,source.session_id,hash('declared synthetic metadata '+requestId),JSON.stringify(value),source.created_at));}
 await s.f.db.batch(rows);const before=await durable(s),seen=[];let cursor=null,pages=0;
 do{const query=cursor?'?limit=7&'+new URLSearchParams(cursor):'?limit=7',page=ok(await get(s,'/operations'+query));assert.ok(page.items.length<=7);seen.push(...page.items.map(x=>x.request_id));cursor=page.next_cursor;pages++;if(cursor)assert.equal(page.items.at(-1).request_id,cursor.after_request_id);}while(cursor);
 assert.equal(pages,5);assert.deepEqual(seen,ids.sort().reverse());assert.equal(new Set(seen).size,29);assert.deepEqual(await durable(s),before);assert.equal(await count(s,'admin_bridge_guards'),0);
 assert.equal(ok(await get(s,'/operations')).items.length,25);assert.equal(ok(await get(s,'/operations?limit=1')).items.length,1);
});
test('history cursor fields are strict paired bounded UTC and UUID values and never become SQL or redirects',async t=>{
 const s=await setup(t);await addKinds(s);const before=await durable(s);
 for(const query of ['?limit=0','?limit=26','?limit=01','?limit=-1','?limit=1.0','?limit=1&limit=2','?unknown=1','?after_created_at=2026-10-16T00:00:00.000Z','?after_request_id='+randomUUID(),'?after_created_at=invalid&after_request_id='+randomUUID(),'?after_created_at=2026-02-31T00:00:00.000Z&after_request_id='+randomUUID(),'?after_created_at=2026-10-16T00:00:00Z&after_request_id='+randomUUID(),'?after_created_at=2026-10-16T00:00:00.000Z&after_request_id=not-a-uuid',"?limit=1%3BDROP%20TABLE%20users"]){assert.equal((await get(s,'/operations'+query)).status,400,query);}
 assert.deepEqual(await durable(s),before);
});
test('history remains discoverable after self-disable but does not authorize policy readback or replay',async t=>{
 const s=await setup(t),{configured}=await addKinds(s);ok(await access(s,false,true));const value=ok(await get(s,'/operations'));assert.equal(value.items.length,4);assert.equal(value.items.filter(x=>x.kind==='access').length,2);noAuthority(value);
 assert.equal((await get(s,'/policies/operations/'+configured.request_id)).status,403);const accessId=value.items.find(x=>x.kind==='access').request_id;assert.equal(ok(await get(s,'/access/operations/'+accessId)).observed,true);assert.equal(ok(await get(s,'/access')).can_operate,false);
});
test('policy operation readback is an immutable decision distinct from separately read current policy; missing can be in flight',async t=>{
 const s=await setup(t),first=ok(await policy(s,0,true));ok(await policy(s,1,false));const before=await durable(s),historical=ok(await get(s,'/policies/operations/'+first.request_id));assert.equal(historical.observed,true);assert.equal(historical.recorded_decision.enabled,true);assert.equal(historical.recorded_decision.revision,1);assert.equal('current_policy' in historical,false);assert.equal(ok(await get(s,'/policies/'+s.group)).enabled,false);assert.equal(historical.may_send,false);assert.equal(historical.replay_authorized,false);
 const missing=ok(await get(s,'/policies/operations/'+randomUUID()));assert.equal(missing.observed,false);assert.equal(missing.may_be_in_flight,true);assert.equal(missing.status,'not_recorded');assert.equal(missing.recorded_decision,null);assert.deepEqual(await durable(s),before);
});
test('new same-user session has its own empty metadata history and cannot adopt original policy/access/materialization receipts',async t=>{
 const s=await setup(t);await addKinds(s);const rows=ok(await get(s,'/operations')).items,original=s.operator;s.operator=await fresh(s);const before=await durable(s);assert.deepEqual(ok(await get(s,'/operations')).items,[]);
 for(const row of rows)assert.equal((await get(s,row.status_path.slice(base.length))).status,409);assert.deepEqual(await durable(s),before);s.operator=original;assert.equal(ok(await get(s,'/operations')).items.length,3);
});
for(const role of ['admin','staff'])test('generic notification read never authorizes '+role+' to view assisted metadata or policy receipts',async t=>{
 const s=await setup(t,{role,enabled:false});await s.f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(s.account.userId,'notifications.read',new Date().toISOString()).run();ok(await generic(s,await bearer(s)));assert.equal((await get(s,'/operations')).status,403);assert.equal((await get(s,'/policies/operations/'+randomUUID())).status,403);
});
test('new history and policy operation routes require current issued AAL2 and exact supported methods/origins',async t=>{
 const low=await setup(t,{assurance:1,enabled:false});for(const path of ['/operations','/policies/operations/'+randomUUID()])assert.equal((await get(low,path)).status,403);
 const s=await setup(t),before=await durable(s);for(const path of ['/operations','/policies/operations/'+randomUUID()]){
  for(const method of ['POST','PATCH','DELETE'])assert.equal((await s.f.call(base+path,{method,cookie:s.operator.cookie,headers:{'X-Collect-Admin':'1'}})).status,405);
  assert.equal((await s.f.call(base+path,{method:'GET',cookie:s.operator.cookie,origin:'https://foreign.example'})).status,403);
 }
 assert.deepEqual(await durable(s),before);
});
for(const kind of ['history','policy'])test(kind+' final read winning authority loss releases neither metadata nor retained decision',async t=>{
 const s=await setup(t),{configured}=await addKinds(s),before=await durable(s);let paused=0;s.f.setGate(async()=>{paused++;await s.f.db.prepare('DELETE FROM admin_grants WHERE user_id=? AND permission=?').bind(s.account.userId,kind==='history'?'admin_users.manage':'assisted_sms.manage').run();});
 const result=await get(s,kind==='history'?'/operations':'/policies/operations/'+configured.request_id,{'X-Test-Pause':kind==='history'?'history_status_final':'policy_status_final'});assert.equal(result.status,403);assert.equal(paused,1);assert.equal(result.body.result,undefined);const after=await durable(s);assert.deepEqual(after.receipts,before.receipts);assert.deepEqual(after.audits,before.audits);assert.deepEqual(after.aliases,before.aliases);
});
test('dedicated discoverability creates no fake global history or cancellation aliases and preserves ordinary global request receipts',async t=>{
 const s=await setup(t);await addKinds(s);const before=await durable(s),history=ok(await get(s,'/operations'));noAuthority(history);assert.equal(ok(await s.f.call('/api/admin/operations/requests',{method:'GET',cookie:s.operator.cookie})).total,0);
 for(const row of history.items){assert.equal('cancel_path' in row,false);assert.equal((await post(s,row.status_path.slice(base.length)+'/cancel',{})).status,501);}
 assert.deepEqual(await durable(s),before);
 const control=ok(await s.f.operation('groups',s.operator.cookie,{title:'Synthetic global history control',slug:'control-'+randomUUID(),collection_type:'ikimina',owner_user_id:s.member.id,receiver:{label:'Synthetic receiver',network:'mtn_momo',momo_number_or_code:'+250788123456'},reason:'Controlled generic request-history preservation'}));
 const global=ok(await s.f.call('/api/admin/operations/requests',{method:'GET',cookie:s.operator.cookie}));assert.equal(global.total,1);assert.equal(global.rows[0].scope,'groups.post');assert.equal(global.rows[0].id,control.request_id);assert.equal(ok(await get(s,'/operations')).items.length,3);
});
