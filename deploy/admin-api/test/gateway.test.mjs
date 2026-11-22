import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {build} from 'esbuild';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
import {handleGateway,GatewayError,gatewayDerToP1363} from '../src/gateway.mjs';
import {digest,randomToken} from '../src/security.mjs';
const origin='https://admin.collect.ikanisa.com',root=fileURLToPath(new URL('..',import.meta.url)),cert='a'.repeat(64),app='app.cool.mobile.gateway',reason='Reviewed the enrolled device identity.';
const policy=JSON.stringify([{app_id:app,signing_certificate_sha256:cert}]),uuid=()=>crypto.randomUUID(),now=()=>Math.floor(Date.now()/1000);
let runtime,db,bucket,owner,admin,staff;
const q=(sql,...v)=>db.prepare(sql).bind(...v),run=(sql,...v)=>q(sql,...v).run(),first=(sql,...v)=>q(sql,...v).first();
function keypair(){const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),spki=pair.publicKey.export({type:'spki',format:'der'});return{...pair,public_key_spki_base64:spki.toString('base64'),key_sha256:createHash('sha256').update(spki).digest('hex'),installation_id:uuid(),signing_certificate_sha256:cert};}
async function actor(role='admin'){
 const id=uuid(),token=randomToken(),hash=await digest(token),at=now();await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,'active','test-only',?,?)",id,role==='owner'?'info@ikanisa.com':`${id}@example.com`,role,at,at);
 await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)',hash,uuid(),id,at,at+3600);
 return{id,role,status:'active',auth_version:1,token_hash:hash,cookie:`__Host-collect_admin=${token}`,permissions:['gateway.read','payments.read',...(role==='staff'?[]:['gateway.manage','payments.manage'])]};
}
async function api(path,method='GET',data=null,user=owner,key=uuid(),headers={}){
 const response=await runtime.dispatchFetch(`${origin}/api/admin/gateway/${path}`,{method,headers:{Origin:origin,...(user?{Cookie:user.cookie}:{}),'Content-Type':'application/json','Idempotency-Key':key,...headers},...(data===null?{}:{body:JSON.stringify({reason,...data})})});return{status:response.status,body:await response.json()};
}
async function ok(...args){const r=await api(...args);assert.equal(r.status,200,JSON.stringify(r.body));return r.body;}
function enrollment(key){return{label:'Rwanda gateway',app_id:app,installation_id:key.installation_id,public_key_spki_base64:key.public_key_spki_base64,key_sha256:key.key_sha256,signing_certificate_sha256:cert};}
const intent=(key,version)=>({expected_version:version,expected_key_sha256:key.key_sha256,expected_signing_certificate_sha256:cert});
function envelope(device,overrides={}){const time=new Date().toISOString();return{contract_version:1,action:'heartbeat',device_id:device,request_id:uuid(),issued_at:time,payload:{sms_permission:false,network:'validated',telephony:'unknown',sim_selected:false,sim_revision_sha256:null,local_pause:false,reported_at:time},...overrides};}
function signedRequest(key,value,{raw=null,headers={},path='/api/gateway'}={}){
 const bytes=raw===null?Buffer.from(JSON.stringify(value)):Buffer.from(raw);return new Request(`${origin}${path}`,{method:'POST',headers:{'Content-Type':'application/json; charset=utf-8','X-Collect-Gateway-Key-Id':key.key_sha256,'X-Collect-Gateway-Signature':sign('sha256',bytes,key.privateKey).toString('base64'),...headers},body:bytes});
}
async function dispatch(request){return runtime.dispatchFetch(request.url,{method:request.method,headers:Object.fromEntries(request.headers),body:await request.arrayBuffer()});}
async function beat(key,value,options){const response=await dispatch(signedRequest(key,value,options));return{status:response.status,body:await response.json()};}
async function enroll(key=keypair(),activate=true){const result=await ok('devices','POST',enrollment(key));if(activate)await ok(`devices/${result.resource_id}/activate`,'POST',intent(key,1));return{key,id:result.resource_id};}
before(async()=>{
 const bundle=await build({stdin:{resolveDir:root,contents:`import {handleGateway} from './src/gateway.mjs';import {digest} from './src/security.mjs';
 export default{async fetch(request,env){try{let session=null;if(new URL(request.url).pathname.startsWith('/api/admin/')){if(request.headers.get('Origin')!==env.ADMIN_ORIGIN)return Response.json({error:'origin_rejected'},{status:403});const token=(request.headers.get('Cookie')||'').split('=')[1];session=token?await env.ADMIN_DB.prepare("SELECT a.*,s.token_hash FROM admin_users a JOIN admin_sessions s ON s.user_id=a.id WHERE s.token_hash=? AND a.status='active' AND s.auth_version=a.auth_version AND s.expires_at>unixepoch()").bind(await digest(token)).first():null;if(session)session.permissions=['gateway.read','payments.read',...(['owner','admin'].includes(session.role)?['gateway.manage','payments.manage']:[])];}return Response.json(await handleGateway(request,env,session));}catch(e){return Response.json({code:e.code||'unexpected',message:e.message},{status:e.status||500});}}};`},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022'});
 runtime=new Miniflare(convertV4MiniflareOptions({modules:true,script:bundle.outputFiles[0].text,compatibilityDate:'2026-10-04',bindings:{ADMIN_ORIGIN:origin,GATEWAY_ALLOWED_IDENTITIES:policy},d1Databases:['ADMIN_DB'],r2Buckets:['MEMBER_MEDIA']}));db=await runtime.getD1Database('ADMIN_DB');bucket=await runtime.getR2Bucket('MEMBER_MEDIA');
 for(const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql','0004_operating_actions.sql','0005_member_cloudflare.sql','0006_gateway_cloudflare.sql','0007_email_only_dispatch.sql','0008_admin_people.sql','0009_admin_reconciliation.sql','0010_admin_sms_facts.sql','0011_admin_transaction_sms_lineage.sql']){
  const sql=await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8'),split=spawnSync(process.execPath,['-e',"const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"],{cwd:root,input:sql,encoding:'utf8',timeout:15000});assert.equal(split.status,0,split.stderr);await db.batch(JSON.parse(split.stdout).map(sql=>db.prepare(sql)));
 }
 owner=await actor('owner');admin=await actor('admin');staff=await actor('staff');
});
after(async()=>{await runtime?.dispose();});
const f={};
test('gateway identity requires authenticated manager, actual P256 SPKI and approved certificate/application',async()=>{
 const key=keypair();assert.equal((await api('devices','POST',enrollment(key),null)).status,401);assert.equal((await api('devices','POST',enrollment(key),staff)).status,403);
 assert.equal((await api('devices','POST',{...enrollment(key),signing_certificate_sha256:'b'.repeat(64)})).status,403);
 assert.equal((await api('devices','POST',{...enrollment(key),app_id:'app.unreviewed.gateway'})).status,403);
 assert.equal((await api('devices','POST',{...enrollment(key),key_sha256:'c'.repeat(64)})).status,400);
 const malformed=Buffer.from(key.public_key_spki_base64,'base64');malformed.fill(0,27);assert.equal((await api('devices','POST',{...enrollment(key),public_key_spki_base64:malformed.toString('base64'),key_sha256:createHash('sha256').update(malformed).digest('hex')})).status,400);
 const request=new Request(`${origin}/api/admin/gateway/devices`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({...enrollment(key),reason})});
 await assert.rejects(handleGateway(request,{ADMIN_DB:db},owner),e=>e instanceof GatewayError&&e.code==='gateway_identity_policy_unavailable');
 assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_devices')).n,0);
});
test('enrollment is replay-safe, immutable and pending; activation requires exact current fingerprints',async()=>{
 f.key=keypair();const key=uuid(),body=enrollment(f.key),results=await Promise.all([api('devices','POST',body,owner,key),api('devices','POST',body,owner,key)]);
 assert.ok(results.every(r=>r.status===200),JSON.stringify(results));assert.deepEqual(results[0].body,results[1].body);f.device=results[0].body.resource_id;
 assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_devices')).n,1);assert.equal((await api('devices','POST',body)).status,409);
 let detail=await ok(`devices/${f.device}`);assert.equal(detail.resource.state,'pending');assert.equal(detail.resource.send_authority,false);assert.equal(detail.resource.carrier_proof,false);assert.equal(detail.resource.public_key_spki_base64,f.key.public_key_spki_base64);
 assert.deepEqual(detail.enrollment,{contract_version:1,device_id:f.device,installation_id:f.key.installation_id,key_sha256:f.key.key_sha256,signing_certificate_sha256:cert});
 assert.equal((await beat(f.key,envelope(f.device))).status,403);
 assert.equal((await api(`devices/${f.device}/activate`,'POST',{...intent(f.key,1),expected_key_sha256:'d'.repeat(64)})).status,409);
 await ok(`devices/${f.device}/activate`,'POST',intent(f.key,1),admin);detail=await ok(`devices/${f.device}`);assert.equal(detail.resource.version,2);assert.equal(detail.resource.state,'active');
 await assert.rejects(run('UPDATE collect_gateway_devices SET installation_id=? WHERE id=?',uuid(),f.device),/immutable/);
 assert.equal((await ok(`devices/${f.device}`,'GET',null,staff)).can_manage,false);
 assert.equal((await ok('devices?state=active&limit=1')).total,1);assert.equal((await api('devices?limit=101')).status,400);
});
test('native DER exact-byte signatures yield only heartbeat observation receipts with no carrier or send authority',async()=>{
 const value=envelope(f.device),result=await beat(f.key,value);assert.equal(result.status,200,JSON.stringify(result.body));
 assert.deepEqual(Object.keys(result.body),['contract_version','action','device_id','request_id','result']);assert.deepEqual(Object.keys(result.body.result),['observation_id','ingested_at','replay','carrier_proof']);
 assert.equal(result.body.result.carrier_proof,false);assert.equal(result.body.result.replay,false);assert.equal(result.body.device_id,f.device);assert.equal(result.body.request_id,value.request_id);
 const replay=await beat(f.key,value);assert.equal(replay.status,200);assert.equal(replay.body.result.observation_id,result.body.result.observation_id);assert.equal(replay.body.result.ingested_at,result.body.result.ingested_at);assert.equal(replay.body.result.replay,true);
 const changed={...value,payload:{...value.payload,local_pause:true}};assert.equal((await beat(f.key,changed)).status,409);
 const another=envelope(f.device),both=await Promise.all([beat(f.key,another),beat(f.key,another)]);assert.ok(both.every(r=>r.status===200));assert.equal(both[0].body.result.observation_id,both[1].body.result.observation_id);assert.deepEqual(both.map(r=>r.body.result.replay).sort(),[false,true]);
 const detail=await ok(`devices/${f.device}`);assert.equal(detail.related.heartbeats.length,2);assert.ok(detail.resource.last_heartbeat_at);assert.ok(detail.related.heartbeats.every(r=>r.carrier_proof===false&&r.send_authority===false));
 assert.equal((await first('SELECT count(*) AS n FROM collect_transactions')).n,0);
});
test('wrong signatures, ambiguous DER/JSON, body changes, stale timestamps and unsupported legacy actions are refused',async()=>{
 const value=envelope(f.device),wrong=keypair();assert.equal((await beat(wrong,value,{headers:{'X-Collect-Gateway-Key-Id':f.key.key_sha256}})).status,401);
 const original=signedRequest(f.key,value),tampered=JSON.stringify({...value,payload:{...value.payload,network:'offline'}});const response=await dispatch(new Request(original.url,{method:'POST',headers:original.headers,body:tampered}));assert.equal(response.status,401);
 for(const der of [Uint8Array.from([0x30,6,2,1,0,2,1,1]),Uint8Array.from([0x30,7,2,2,0,1,2,1,1]),Uint8Array.from([0x30,6,2,1,0x80,2,1,1]),new Uint8Array(64)])assert.throws(()=>gatewayDerToP1363(der));
 assert.equal((await beat(f.key,value,{headers:{'X-Collect-Gateway-Signature':Buffer.alloc(64).toString('base64')}})).status,400);
 const duplicate=JSON.stringify(value).replace('"contract_version":1','"contract_version":1,"contract_version":1');assert.equal((await beat(f.key,value,{raw:duplicate})).status,400);
 const old=new Date(Date.now()-180000).toISOString();assert.equal((await beat(f.key,envelope(f.device,{issued_at:old,payload:{...value.payload,reported_at:old}}))).status,400);
 const future=new Date(Date.now()+60000).toISOString();assert.equal((await beat(f.key,envelope(f.device,{issued_at:future,payload:{...value.payload,reported_at:future}}))).status,400);
 for(const action of ['dispatch_grant','arm_dispatch','callback','reconcile','archive'])assert.equal((await beat(f.key,{...value,action})).status,400);
 assert.equal((await beat(f.key,{...value,contract_version:2})).status,400);
 assert.equal((await beat(f.key,value,{raw:Buffer.from([0xff,0xfe])})).status,400);
 assert.equal((await beat(f.key,value,{raw:' '.repeat(32769)})).status,413);
});
test('stale identical observations can recover their original receipt without becoming fresh health evidence',async()=>{
 const old=new Date(Date.now()-600000).toISOString(),value=envelope(f.device,{issued_at:old,payload:{sms_permission:false,network:'offline',telephony:'unknown',sim_selected:false,sim_revision_sha256:null,local_pause:true,reported_at:old}}),raw=Buffer.from(JSON.stringify(value)),observation=uuid(),at=now()-600;
 await run('INSERT INTO collect_gateway_heartbeats(id,device_id,request_id,request_sha256,issued_at,reported_at,observations_json,ingested_at) VALUES(?,?,?,?,?,?,?,?)',observation,f.device,value.request_id,createHash('sha256').update(raw).digest('hex'),old,old,JSON.stringify(value.payload),at);
 const reply=await beat(f.key,value);assert.equal(reply.status,200);assert.equal(reply.body.result.replay,true);assert.equal(reply.body.result.observation_id,observation);assert.equal(reply.body.result.ingested_at,new Date(at*1000).toISOString());
});
test('revocation during signature verification is fenced in the same D1 batch and policy removal stops new heartbeats',async()=>{
 const device=await enroll(),value=envelope(device.id);let intercepted=false;
 const wrapped={prepare:sql=>db.prepare(sql),batch:async statements=>{if(!intercepted){intercepted=true;await run("UPDATE collect_gateway_devices SET state='revoked',version=3,revoked_at=?,revoked_by_admin_id=? WHERE id=?",now(),owner.id,device.id);}return db.batch(statements);}};
 await assert.rejects(handleGateway(signedRequest(device.key,value),{ADMIN_DB:wrapped,ADMIN_ORIGIN:origin,GATEWAY_ALLOWED_IDENTITIES:policy}),e=>e instanceof GatewayError&&e.code==='gateway_device_inactive');
 assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_heartbeats WHERE device_id=?',device.id)).n,0);
 assert.equal((await beat(device.key,value)).status,403);assert.equal((await api(`devices/${device.id}/activate`,'POST',intent(device.key,3))).status,409);
 await assert.rejects(handleGateway(signedRequest(f.key,envelope(f.device)),{ADMIN_DB:db,ADMIN_ORIGIN:origin,GATEWAY_ALLOWED_IDENTITIES:JSON.stringify([{app_id:app,signing_certificate_sha256:'b'.repeat(64)}])}),e=>e instanceof GatewayError&&e.code==='gateway_identity_not_allowed');
 assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});
async function receiptFixture({body='You received RWF 500. Ref SAMPLE-TEST',sender='MTN MoMo',user=f.member}={}){
 const id=uuid(),key=`member-receipts/${user}/${id}`,hash=await digest(body);await bucket.put(key,JSON.stringify({raw_sender:sender,raw_body:body}));
 await run('INSERT INTO member_receipt_submissions(id,user_id,body_hash,raw_sender,payload_object_key,received_at,created_at) VALUES(?,?,?,?,?,?,?)',id,user,hash,sender,key,now(),now());return{id,key,hash,body,sender};
}
test('member receipt content is private, reasoned, audited and digest-verified before review',async()=>{
 const at=now();f.member=uuid();f.group=uuid();f.payee=uuid();f.tx=uuid();
 await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'receipt-member@example.com','active',?,?)",f.member,at,at);
 await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'907777','Receipt Member',?,?)",f.member,at,at);
 await run("INSERT INTO collect_groups(id,slug,title,collection_type,status,created_by_admin_id,created_at,updated_at) VALUES(?,'receipt-group','Receipt Group','ikimina','active',?,?,?)",f.group,owner.id,at,at);
 await run("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'owner','active',?,?,?)",f.group,f.member,at,at,at);
 await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'Receipt receiver','mtn_momo','123456',?,?,?)",f.payee,f.group,owner.id,reason,at);
 await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo','RECEIPT-TEST',500,?,?)",f.tx,f.group,f.payee,at,at);
 f.receipt=await receiptFixture();const list=await ok('receipts?status=needs_review','GET',null,staff);assert.equal(list.total,1);assert.equal(list.rows[0].body_sha256,f.receipt.hash);assert.equal(list.rows[0].payload_object_key,undefined);assert.equal(list.rows[0].raw_body,undefined);
 assert.equal((await api(`receipts/${f.receipt.id}/content`,'GET',null,staff,uuid(),{'X-Collect-Review-Reason':reason})).status,403);
 assert.equal((await api(`receipts/${f.receipt.id}/content`)).status,400);
 const content=await ok(`receipts/${f.receipt.id}/content`,'GET',null,owner,uuid(),{'X-Collect-Review-Reason':reason});assert.equal(content.raw_body,f.receipt.body);assert.equal(content.evidence_level,'member_submitted');
 assert.equal((await first("SELECT count(*) AS n FROM collect_operations_audit WHERE action='receipt.reveal' AND subject_id=?",f.receipt.id)).n,1);
 const eligible=await ok(`receipts/${f.receipt.id}/transactions?search=RECEIPT`);assert.deepEqual(eligible.rows.map(r=>r.id),[f.tx]);
 const corrupt=await receiptFixture({body:'Original source'});await bucket.put(corrupt.key,JSON.stringify({raw_sender:corrupt.sender,raw_body:'Replaced source'}));
 assert.equal((await api(`receipts/${corrupt.id}/content`,'GET',null,owner,uuid(),{'X-Collect-Review-Reason':reason})).status,503);
 assert.equal((await api(`receipts/${corrupt.id}/review`,'POST',{expected_version:1,outcome:'reviewed',transaction_id:null})).status,503);
});
test('receipt review creates only pending payer evidence, atomically and replay-safe, with immutable source/history',async()=>{
 const key=uuid(),body={expected_version:1,outcome:'reviewed',transaction_id:f.tx},results=await Promise.all([api(`receipts/${f.receipt.id}/review`,'POST',body,owner,key),api(`receipts/${f.receipt.id}/review`,'POST',body,owner,key)]);
 assert.ok(results.every(r=>r.status===200),JSON.stringify(results));assert.deepEqual(results[0].body,results[1].body);assert.equal(results[0].body.resource_type,'member_receipts');assert.equal(results[0].body.version,2);
 const tx=await first('SELECT * FROM collect_transactions WHERE id=?',f.tx);assert.equal(tx.verification_status,'pending');assert.equal(tx.verified_at,null);assert.equal(tx.version,2);
 const evidence=await first('SELECT * FROM collect_transaction_evidence WHERE transaction_id=?',f.tx);assert.equal(evidence.kind,'payer_receipt');assert.equal(evidence.artifact_sha256,f.receipt.hash);
 const details=await ok(`receipts/${f.receipt.id}`);assert.equal(details.resource.status,'reviewed');assert.equal(details.related.reviews.length,1);assert.equal(details.related.reviews[0].transaction_id,f.tx);
 assert.equal((await api(`receipts/${f.receipt.id}/review`,'POST',{expected_version:2,outcome:'rejected',transaction_id:null})).status,409);
 await assert.rejects(run('DELETE FROM collect_member_receipt_reviews WHERE submission_id=?',f.receipt.id),/append-only/);
 await assert.rejects(run('UPDATE member_receipt_submissions SET body_hash=? WHERE id=?','b'.repeat(64),f.receipt.id),/immutable/);
 const unrelated=uuid();await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'unrelated@example.com','active',?,?)",unrelated,now(),now());const other=await receiptFixture({user:unrelated,body:'Unrelated group source'});
 assert.equal((await api(`receipts/${other.id}/review`,'POST',{expected_version:1,outcome:'reviewed',transaction_id:f.tx})).status,409);
 assert.equal((await first('SELECT status FROM member_receipt_submissions WHERE id=?',other.id)).status,'needs_review');
 await ok(`receipts/${other.id}/review`,'POST',{expected_version:1,outcome:'rejected',transaction_id:null},admin);
 assert.equal((await first('SELECT count(*) AS n FROM collect_transactions')).n,1);assert.equal((await first('SELECT count(*) AS n FROM collect_journals')).n,0);assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});

test('manager revocation fences both device mutation and sensitive receipt content audit before any result',async()=>{
 for(const content of [false,true]){
  const user=await actor();let batches=0;const wrapped={prepare:sql=>db.prepare(sql),batch:async statements=>{batches++;if(batches===2)await run('DELETE FROM admin_sessions WHERE token_hash=?',user.token_hash);return db.batch(statements);}};
  const pair=keypair(),request=content?new Request(`${origin}/api/admin/gateway/receipts/${f.receipt.id}/content`,{headers:{'X-Collect-Review-Reason':reason}}):new Request(`${origin}/api/admin/gateway/devices`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({...enrollment(pair),reason})});
  const auditBefore=(await first('SELECT count(*) AS n FROM collect_operations_audit WHERE actor_admin_id=?',user.id)).n;
  await assert.rejects(handleGateway(request,{ADMIN_DB:wrapped,MEMBER_MEDIA:bucket,GATEWAY_ALLOWED_IDENTITIES:policy},user),error=>error instanceof GatewayError&&error.status===401);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE actor_admin_id=?',user.id)).n,auditBefore);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_devices WHERE key_sha256=?',pair.key_sha256)).n,0);
 }
});

test('revocation remains available after trust-policy removal and no self-reported SMS permission grants authority',async()=>{
 const device=await enroll(),value=envelope(device.id);value.payload.sms_permission=true;value.payload.telephony='ready';value.payload.sim_selected=true;value.payload.sim_revision_sha256='e'.repeat(64);
 const accepted=await beat(device.key,value,{path:'/api/gateway/heartbeat'});assert.equal(accepted.status,200);assert.equal(accepted.body.result.carrier_proof,false);assert.equal(accepted.body.result.send_authority,undefined);
 const revoke=new Request(`${origin}/api/admin/gateway/devices/${device.id}/revoke`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({...intent(device.key,2),reason})});
 const result=await handleGateway(revoke,{ADMIN_DB:db},owner);assert.equal(result.version,3);assert.equal((await beat(device.key,value)).status,403);
 const detail=await ok(`devices/${device.id}`);assert.equal(detail.resource.send_authority,false);assert.equal(detail.related.heartbeats[0].sms_permission,true);assert.equal(detail.related.heartbeats[0].send_authority,false);
 const request=signedRequest(f.key,envelope(f.device));await assert.rejects(handleGateway(new Request(request.url.replace('https:','http:'),{method:'POST',headers:request.headers,body:await request.arrayBuffer()}),{ADMIN_DB:db,ADMIN_ORIGIN:origin,GATEWAY_ALLOWED_IDENTITIES:policy}),error=>error instanceof GatewayError&&error.code==='origin_rejected');
 assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});
