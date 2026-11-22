import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { handleOperations, OPERATIONS_MANAGE_PERMISSIONS, OPERATIONS_CREATE_PERMISSIONS, OperationsError } from '../src/operations.mjs';
import { CORE_READ_PERMISSIONS, AVAILABLE_PERSON_PUBLIC_ID_SQL } from '../src/core.mjs';
import { digest, randomToken } from '../src/security.mjs';
import { receiverFact, transactionAdditionalFields } from './transaction-source-fixture.mjs';
const origin='https://admin.collect.ikanisa.com', root=fileURLToPath(new URL('..',import.meta.url));
const timestamp=Math.floor(Date.now()/1000), uuid=()=>crypto.randomUUID(), reason='Reviewed the original operating evidence.';
let runtime,db,owner,admin,staff;
const q=(sql,...v)=>db.prepare(sql).bind(...v), run=(sql,...v)=>q(sql,...v).run(), first=(sql,...v)=>q(sql,...v).first();
async function actor(role='admin') {
  const id=uuid(), token=randomToken(), hash=await digest(token);
  await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,'active','test-only',?,?)",id,role==='owner'?'info@ikanisa.com':`${id}@example.com`,role,timestamp,timestamp);
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)',hash,uuid(),id,timestamp,timestamp+3600);
  return {id,role,token_hash:hash,cookie:`__Host-collect_admin=${token}`,status:'active',auth_version:1,permissions:[...CORE_READ_PERMISSIONS,...OPERATIONS_CREATE_PERMISSIONS,...(role==='staff'?[]:OPERATIONS_MANAGE_PERMISSIONS)]};
}
async function api(path,method='GET',data=null,user=owner,key=uuid()) {
  const response=await runtime.dispatchFetch(`${origin}/api/admin/operations/${path}`,{method,headers:{Origin:origin,...(user?{Cookie:user.cookie}:{}),'Content-Type':'application/json','Idempotency-Key':key},...(data===null?{}:{body:JSON.stringify({reason,...data})})});
  return {status:response.status,body:await response.json(),key};
}
async function ok(...args) {const r=await api(...args);assert.equal(r.status,200,JSON.stringify(r.body));return r.body;}
// Historical records used by read/posting tests. This is direct ephemeral D1
// setup, never an alternative API allocation path.
async function historicalAllocation(transaction,group,member,amount,advanceVersion=true) {
  const operation=uuid(),allocation=uuid();
  const statements=[q("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'test.historical_allocation',?,?,?)",operation,owner.id,uuid(),'f'.repeat(64),timestamp),
    q('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)',allocation,transaction,group,member,amount,operation,owner.id,timestamp)];
  if(advanceVersion)statements.push(q('UPDATE collect_transactions SET version=version+1 WHERE id=?',transaction));
  await db.batch(statements);return allocation;
}
before(async()=>{
  // This Worker harness resolves real D1 sessions and exercises the same exported
  // operations handler used by the integrating Worker, without any provider.
  const bundle=await build({stdin:{resolveDir:root,contents:`
    import {handleOperations,OPERATIONS_MANAGE_PERMISSIONS,OPERATIONS_CREATE_PERMISSIONS} from './src/operations.mjs';
    import {CORE_READ_PERMISSIONS} from './src/core.mjs';import {digest} from './src/security.mjs';
    export default {async fetch(request,env){try{
      if(request.headers.get('Origin')!==env.ADMIN_ORIGIN)return Response.json({error:'origin_rejected'},{status:403});
      const token=(request.headers.get('Cookie')||'').split('=')[1];
      const user=token?await env.ADMIN_DB.prepare("SELECT a.*,s.token_hash FROM admin_users a JOIN admin_sessions s ON s.user_id=a.id WHERE s.token_hash=? AND a.status='active' AND s.auth_version=a.auth_version AND s.expires_at>unixepoch()").bind(await digest(token)).first():null;
      if(user)user.permissions=[...CORE_READ_PERMISSIONS,...OPERATIONS_CREATE_PERMISSIONS,...(['owner','admin'].includes(user.role)?OPERATIONS_MANAGE_PERMISSIONS:[])];
      return Response.json(await handleOperations(request,env,user));
    }catch(e){return Response.json({error:e.code||'unexpected',message:e.message},{status:e.status||500});}}};
  `},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022'});
  runtime=new Miniflare(convertV4MiniflareOptions({modules:true,script:bundle.outputFiles[0].text,compatibilityDate:'2026-10-04',bindings:{ADMIN_ORIGIN:origin},d1Databases:['ADMIN_DB']}));
  db=await runtime.getD1Database('ADMIN_DB');
  for(const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql','0004_operating_actions.sql','0005_member_cloudflare.sql','0006_gateway_cloudflare.sql','0007_email_only_dispatch.sql','0008_admin_people.sql','0009_admin_reconciliation.sql','0010_admin_sms_facts.sql','0011_admin_transaction_sms_lineage.sql']){
    const sql=await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8');
    const split=spawnSync(process.execPath,['-e',"const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"],{cwd:root,input:sql,encoding:'utf8',timeout:15000});
    assert.equal(split.status,0,split.stderr);await db.batch(JSON.parse(split.stdout).map(sql=>db.prepare(sql)));
  }
  owner=await actor('owner');admin=await actor('admin');staff=await actor('staff');
});
after(async()=>{await runtime?.dispose();});
const f={};
test('operating allowlist refuses anonymous/staff writes, malformed keys and client-selected privileges',async()=>{
  assert.equal((await api('groups','POST',{title:'Example'},null)).status,401);
  assert.equal((await api('users','POST',{display_name:'Example',email:'staff-cannot@example.com'},staff)).status,403);
  assert.equal((await api('rpc','POST',{sql:'DELETE FROM collect_users'})).status,404);
  assert.equal((await api('groups','POST',{title:'Example'},owner,'short')).status,400);
  assert.equal((await api('users','POST',{display_name:'Someone',email:'someone@example.com',role:'owner'})).status,400);
  assert.equal((await api('groups','POST',{title:'Example',slug:'example',collection_type:'ikimina',suggested_amount_rwf:1.5})).status,400);
  assert.equal((await api('groups','DELETE')).status,405);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operation_requests')).n,0);
});
test('fresh operational lifecycle requires an active owner and immutable receiver before group activation',async()=>{
  const g=await ok('groups','POST',{title:'Rwanda Savings',slug:'rwanda-savings',collection_type:'ikimina',suggested_amount_rwf:2500});f.group=g.resource_id;
  assert.deepEqual([g.resource_type,g.version,g.status],['groups',1,'succeeded']);
  assert.equal((await api(`groups/${f.group}`,'PATCH',{expected_version:1,status:'active'})).status,409);
  f.user=(await ok('users','POST',{display_name:'Alice Umuhoza',email:'Alice@example.com',phone_e164:'+250788123456',status:'active'})).resource_id;
  const user=await ok(`users/${f.user}`);assert.match(user.resource.public_id,/^[0-9]{6}$/);assert.equal(user.resource.email,'alice@example.com');
  const m=await ok('memberships','POST',{group_id:f.group,user_id:f.user,role:'owner',status:'active'});assert.equal(m.resource_id,`${f.group}/${f.user}`);
  f.payee=(await ok('payees','POST',{group_id:f.group,label:'Member receiver',network:'mtn_momo',momo_number_or_code:'250788123456'})).resource_id;
  assert.equal((await ok(`groups/${f.group}`,'PATCH',{expected_version:1,status:'active'})).version,2);
  assert.equal((await api(`memberships/${f.group}/${f.user}`,'PATCH',{expected_version:1,role:'member'})).status,409);
  assert.equal((await api(`users/${f.user}`,'PATCH',{expected_version:1,status:'closed'})).status,409);
  assert.equal((await api(`payees/${f.payee}`,'PATCH',{expected_version:1,status:'inactive'})).status,409);
  assert.equal((await api(`payees/${f.payee}`,'PATCH',{expected_version:1,momo_number_or_code:'1234'})).status,400);
  await ok(`payees/${f.payee}`,'PATCH',{expected_version:1,label:'Reviewed receiver'});
  const projected=await ok(`users/${f.user}`,'GET',null,staff);assert.equal(projected.can_manage,false);assert.equal(projected.resource.email,'alice@example.com');assert.equal(projected.resource.phone_e164,'+250788123456');assert.equal(projected.resource.phone_masked,'••••3456');
  assert.equal((await ok(`payees/${f.payee}`,'GET',null,staff)).resource.momo_number_or_code,'250788123456');
  assert.equal((await ok('lookups?kind=users&search=alice%40example.com')).rows.length,1);
  assert.equal((await ok('lookups?kind=users&search=Umuhoza')).rows.length,1);
  assert.equal((await ok(`groups/${f.group}`)).related.memberships.length,1);
});
test('payee lifecycle preserves active-group denial and rollback until explicit suspension and receiver reactivation',async()=>{
  const member=(await ok('users','POST',{display_name:'Receiver lifecycle owner',member_type:'direct',momo_number:'0788100456',status:'active'})).resource_id;
  const group=(await ok('groups','POST',{title:'Receiver lifecycle group',slug:`receiver-lifecycle-${uuid()}`,collection_type:'ikimina',owner_user_id:member})).resource_id;
  const label='Receiver lifecycle route';
  const payee=(await ok('payees','POST',{group_id:group,label,network:'mtn_momo',momo_number_or_code:'006999',status:'inactive'})).resource_id;
  assert.equal((await ok(`payees/${payee}`,'PATCH',{expected_version:1,status:'active'})).version,2);
  assert.equal((await ok(`groups/${group}`,'PATCH',{expected_version:1,status:'active'})).version,2);
  const snapshot=()=>first(`SELECT
    (SELECT status FROM collect_groups WHERE id=?) AS group_status,
    (SELECT version FROM collect_groups WHERE id=?) AS group_version,
    (SELECT status FROM collect_payees WHERE id=?) AS payee_status,
    (SELECT version FROM collect_payees WHERE id=?) AS payee_version,
    (SELECT label FROM collect_payees WHERE id=?) AS payee_label,
    (SELECT momo_number_or_code FROM collect_payees WHERE id=?) AS payee_route,
    (SELECT count(*) FROM collect_operation_requests) AS requests,
    (SELECT count(*) FROM collect_operations_audit) AS audits,
    (SELECT count(*) FROM collect_mutation_guards) AS guards`,group,group,payee,payee,payee,payee);
  const before=await snapshot();
  assert.equal(before.group_status,'active');assert.equal(before.group_version,2);
  assert.equal(before.payee_status,'active');assert.equal(before.payee_version,2);
  const denied=await api(`payees/${payee}`,'PATCH',{expected_version:2,label,status:'inactive'});
  assert.equal(denied.status,409);assert.equal(denied.body.error,'state_conflict');
  assert.deepEqual(await snapshot(),before);
  assert.deepEqual(await ok(`requests/${denied.key}`),{status:'not_found'});

  assert.equal((await ok(`groups/${group}`,'PATCH',{expected_version:2,status:'suspended'})).version,3);
  assert.equal((await ok(`payees/${payee}`,'PATCH',{expected_version:2,status:'inactive'})).version,3);
  const suspended=await snapshot();
  assert.equal(suspended.group_status,'suspended');assert.equal(suspended.group_version,3);
  assert.equal(suspended.payee_status,'inactive');assert.equal(suspended.payee_version,3);
  const noReceiver=await api(`groups/${group}`,'PATCH',{expected_version:3,status:'active'});
  assert.equal(noReceiver.status,409);assert.equal(noReceiver.body.error,'state_conflict');
  assert.deepEqual(await snapshot(),suspended);
  assert.deepEqual(await ok(`requests/${noReceiver.key}`),{status:'not_found'});

  assert.equal((await ok(`payees/${payee}`,'PATCH',{expected_version:3,status:'active'})).version,4);
  assert.equal((await ok(`groups/${group}`,'PATCH',{expected_version:3,status:'active'})).version,4);
  const restored=await snapshot();
  assert.deepEqual(restored,{...before,group_version:4,payee_version:4,requests:before.requests+4,audits:before.audits+4});
});
test('concurrent same-key retries commit one object/audit/outbox, with immutable actor-scoped replay',async()=>{
  const key=uuid(),body={display_name:'Retry Person',email:'retry@example.com',status:'active'};
  const results=await Promise.all([api('users','POST',body,owner,key),api('users','POST',body,owner,key)]);
  assert.ok(results.every(r=>r.status===200),JSON.stringify(results));assert.deepEqual(results[0].body,results[1].body);
  assert.equal((await first('SELECT count(*) AS n FROM collect_users WHERE email=?',body.email)).n,1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE operation_request_id=?',results[0].body.request_id)).n,1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_notification_outbox WHERE recipient_user_id=?',results[0].body.resource_id)).n,1);
  assert.equal((await api('users','POST',{...body,display_name:'Changed content'},owner,key)).status,409);
  const before=(await first('SELECT count(*) AS n FROM collect_operation_requests')).n;
  assert.equal((await api('users','POST',body)).status,409);assert.equal((await first('SELECT count(*) AS n FROM collect_operation_requests')).n,before);
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});
test('racing expected-version edits allow one winner; failed contact mutation rolls back profile and audit',async()=>{
  const results=await Promise.all([api(`users/${f.user}`,'PATCH',{expected_version:1,display_name:'Alice Updated'}),api(`users/${f.user}`,'PATCH',{expected_version:1,display_name:'Alice Other'})]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);const before=await ok(`users/${f.user}`);assert.equal(before.resource.version,2);
  assert.equal((await api(`users/${f.user}`,'PATCH',{expected_version:2,display_name:'Must roll back',email:null,phone_e164:null})).status,409);
  const after=await ok(`users/${f.user}`);assert.equal(after.resource.version,2);assert.equal(after.resource.display_name,before.resource.display_name);
});
test('review/allocation/posting require independent actors, exact balance and conserved immutable payment evidence',async()=>{
  f.tx=(await ok('transactions','POST',{group_id:f.group,payee_id:f.payee,provider_reference:'REF-OPERATIONS-001',amount_rwf:2500,observed_at:timestamp,evidence:{kind:'receiver_statement',reference:'Receiver statement page 1',sha256:'a'.repeat(64)}})).resource_id;
  let tx=await ok(`transactions/${f.tx}`);assert.equal(tx.resource.verification_status,'pending');const eid=tx.related.evidence[0].id;
  assert.equal((await api(`transactions/${f.tx}/allocations`,'POST',{expected_version:1,member_user_id:f.user,amount_rwf:2500})).status,409);
  assert.equal((await api(`transactions/${f.tx}/verification`,'POST',{expected_version:1,evidence_id:eid,outcome:'confirmation_recorded'})).status,409);
  await ok(`transactions/${f.tx}/verification`,'POST',{expected_version:1,evidence_id:eid,outcome:'confirmation_recorded'},admin);
  await historicalAllocation(f.tx,f.group,f.user,2500);
  assert.equal((await api(`transactions/${f.tx}/allocations`,'POST',{expected_version:3,member_user_id:f.user,amount_rwf:1})).status,409);
  tx=await ok(`transactions/${f.tx}`);f.allocation=tx.related.allocations[0].id;
  f.debit=(await ok('accounts','POST',{group_id:f.group,code:'1000',name:'Recorded receiver funds',account_type:'asset',normal_side:'debit'})).resource_id;
  f.credit=(await ok('accounts','POST',{group_id:f.group,code:'2000',name:'Member contributions',account_type:'liability',normal_side:'credit'})).resource_id;
  const lines=[{account_id:f.debit,debit_rwf:2500,credit_rwf:0},{account_id:f.credit,debit_rwf:0,credit_rwf:2500}];
  f.journal=(await ok('journals','POST',{group_id:f.group,allocation_id:f.allocation,description:'Record reviewed contribution',entries:lines})).resource_id;
  assert.equal((await api(`journals/${f.journal}/post`,'POST',{expected_version:1})).status,409);
  await ok(`journals/${f.journal}/post`,'POST',{expected_version:1},admin);assert.equal((await ok(`journals/${f.journal}`)).resource.status,'posted');
  assert.equal((await api(`journals/${f.journal}`,'PATCH',{expected_version:2,description:'Alter posted evidence',entries:lines})).status,409);
  assert.equal((await api(`transactions/${f.tx}/verification`,'POST',{expected_version:3,evidence_id:eid,outcome:'rejection_recorded'},admin)).status,409);
  assert.equal((await first('SELECT sum(debit_rwf)-sum(credit_rwf) AS balance FROM collect_journal_entries WHERE journal_id=?',f.journal)).balance,0);
  assert.equal((await first('SELECT count(*) AS n FROM collect_transaction_reviews WHERE transaction_id=?',f.tx)).n,1);
  const notice=await first("SELECT * FROM collect_notification_outbox WHERE transaction_id=? AND notification_type='contribution_posted'",f.tx);
  assert.equal(notice.status,'queued');assert.equal(notice.channel,'email');assert.equal(JSON.parse(notice.payload_json).to,'alice@example.com');assert.equal(notice.provider_reference,null);
});
test('draft editor cannot approve own changes; bad entries and cumulative exact-money overflow cannot partially post',async()=>{
  const lines=[{account_id:f.debit,debit_rwf:100,credit_rwf:0},{account_id:f.credit,debit_rwf:0,credit_rwf:100}];
  const j=await ok('journals','POST',{group_id:f.group,description:'Initial adjustment',entries:lines});
  await ok(`journals/${j.resource_id}`,'PATCH',{expected_version:1,description:'Reviewed adjustment',entries:lines},admin);
  assert.equal((await api(`journals/${j.resource_id}/post`,'POST',{expected_version:2},admin)).status,409);
  assert.equal((await api(`journals/${j.resource_id}/post`,'POST',{expected_version:2},owner)).status,409);
  await ok(`journals/${j.resource_id}/post`,'POST',{expected_version:2},await actor());
  const before=(await first('SELECT count(*) AS n FROM collect_journals')).n;
  assert.equal((await api('journals','POST',{group_id:f.group,description:'Bad account',entries:[lines[0],{...lines[1],account_id:uuid()}]})).status,409);
  assert.equal((await first('SELECT count(*) AS n FROM collect_journals')).n,before);
  assert.equal((await api('journals','POST',{group_id:f.group,description:'Unbalanced journal',entries:[lines[0],{...lines[1],credit_rwf:99}]})).status,400);
  const max=Number.MAX_SAFE_INTEGER,huge=[{account_id:f.debit,debit_rwf:max,credit_rwf:0},{account_id:f.credit,debit_rwf:0,credit_rwf:max}];
  const exact=await ok('journals','POST',{group_id:f.group,description:'Exact maximum draft',entries:huge});assert.equal((await ok(`journals/${exact.resource_id}`)).related.entries[0].debit_rwf,max);
  assert.equal((await api(`journals/${exact.resource_id}/post`,'POST',{expected_version:1},admin)).status,409);
  assert.equal((await api('journals','POST',{group_id:f.group,description:'Overflow total',entries:[...huge,...lines]})).status,400);
});
test('revocation and role changes between preflight and atomic mutation reject without side effects',async()=>{
  for(const mode of ['revoke','role']){
    const user=await actor();let batches=0;const email=`${uuid()}@example.com`;
    const wrapped={prepare:sql=>db.prepare(sql),batch:async statements=>{batches++;if(batches===2){if(mode==='revoke')await run('DELETE FROM admin_sessions WHERE token_hash=?',user.token_hash);else await run("UPDATE admin_users SET role='staff' WHERE id=?",user.id);}return db.batch(statements);}};
    const request=new Request(`${origin}/api/admin/operations/users`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({reason,display_name:'Race person',email,status:'active'})});
    await assert.rejects(handleOperations(request,{ADMIN_DB:wrapped},user),error=>error instanceof OperationsError&&error.status===401);
    assert.equal((await first('SELECT count(*) AS n FROM collect_users WHERE email=?',email)).n,0);
  }
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});
test('lost responses recover through bounded actor-scoped request receipts without another mutation',async()=>{
  const key=uuid(),data={title:'Recoverable Group',slug:'recoverable-group',collection_type:'other'},receipt=await ok('groups','POST',data,owner,key);
  assert.deepEqual(await ok(`requests/${key}`),{status:'succeeded',request_id:receipt.request_id,receipt});assert.deepEqual(await ok(`requests/${key}`,'GET',null,admin),{status:'not_found'});
  assert.deepEqual(await ok('groups','POST',data,owner,key),receipt);
  const history=await ok('requests?limit=2&offset=0');assert.equal(history.rows.length,2);assert.ok(history.total>2);assert.ok(history.rows.every(row=>row.receipt&&row.idempotency_key));
  assert.equal((await ok('requests?limit=100','GET',null,staff)).total,0);
  assert.equal((await api('requests?limit=101')).status,400);assert.equal((await api('lookups?kind=payees')).status,400);assert.equal((await api('lookups?kind=users&search=abc&search=def')).status,400);
});

test('integer wire validation rejects pre-parse fractional rounding and numeric exponent amounts',async()=>{
  for(const amount of ['1.0000000000000001','1e3','9007199254740992']){
    const response=await runtime.dispatchFetch(`${origin}/api/admin/operations/groups`,{method:'POST',headers:{Origin:origin,Cookie:owner.cookie,'Content-Type':'application/json','Idempotency-Key':uuid()},body:`{"reason":"${reason}","title":"Wire amount","slug":"wire-${uuid()}","collection_type":"other","suggested_amount_rwf":${amount}}`});
    assert.equal(response.status,400);
  }
  const response=await runtime.dispatchFetch(`${origin}/api/admin/operations/groups`,{method:'POST',headers:{Origin:origin,Cookie:owner.cookie,'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({reason,title:'Amount 1.25 in prose',slug:`prose-${uuid()}`,collection_type:'other',description:'The string 1e3 is text, not an amount',suggested_amount_rwf:1000})});
  assert.equal(response.status,200);
});

test('untrusted evidence cannot masquerade as provider verification, be reused across transactions or self-approved',async()=>{
  const tx=(await ok('transactions','POST',{group_id:f.group,payee_id:f.payee,provider_reference:'REF-ADVERSARIAL-002',amount_rwf:300,observed_at:timestamp,evidence:{kind:'payer_receipt',reference:'Payer supplied artifact',sha256:'b'.repeat(64)}})).resource_id;
  let detail=await ok(`transactions/${tx}`);const payerEvidence=detail.related.evidence[0].id;
  assert.equal((await api(`transactions/${tx}/verification`,'POST',{expected_version:1,evidence_id:payerEvidence,outcome:'confirmation_recorded'},admin)).status,409);
  const otherEvidence=(await ok(`transactions/${f.tx}`)).related.evidence[0].id;
  assert.equal((await api(`transactions/${tx}/verification`,'POST',{expected_version:1,evidence_id:otherEvidence,outcome:'confirmation_recorded'},admin)).status,409);
  await ok(`transactions/${tx}/evidence`,'POST',{expected_version:1,evidence:{kind:'provider_statement',reference:'Provider statement reviewed page 2',sha256:'c'.repeat(64)}},admin);
  detail=await ok(`transactions/${tx}`);const providerEvidence=detail.related.evidence.find(e=>e.kind==='provider_statement').id;
  for(const sameActor of [owner,admin])assert.equal((await api(`transactions/${tx}/verification`,'POST',{expected_version:2,evidence_id:providerEvidence,outcome:'confirmation_recorded'},sameActor)).status,409);
  await ok(`transactions/${tx}/verification`,'POST',{expected_version:2,evidence_id:providerEvidence,outcome:'confirmation_recorded'},await actor());
  const results=await Promise.allSettled([historicalAllocation(tx,f.group,f.user,200),historicalAllocation(tx,f.group,f.user,200)]);
  assert.deepEqual(results.map(r=>r.status).sort(),['fulfilled','rejected']);
  detail=await ok(`transactions/${tx}`);assert.equal(detail.resource.allocated_amount_rwf,200);assert.equal(detail.related.allocations.length,1);
  assert.equal((await api(`transactions/${tx}/allocations`,'POST',{expected_version:4,member_user_id:uuid(),amount_rwf:100})).status,409);
  const members=await ok(`lookups?kind=members&group_id=${f.group}`);assert.deepEqual(members.rows.map(row=>row.id),[f.user]);
  assert.equal((await api('lookups?kind=members')).status,400);
  await assert.rejects(run('UPDATE collect_transaction_evidence SET reference=? WHERE id=?','Altered artifact',payerEvidence),/append-only/);
  await assert.rejects(run('DELETE FROM collect_transaction_reviews WHERE transaction_id=?',tx),/append-only/);
  await assert.rejects(run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,verification_status,verified_by_admin_id,verified_at,observed_at,created_at) VALUES(?,?,?,'mtn_momo','INSERT-BYPASS',1,'confirmation_recorded',?,?,?,?)",uuid(),f.group,f.payee,owner.id,timestamp,timestamp,timestamp),/independent review/);
});

test('transaction detail aggregate remains authoritative when allocation rows are truncated',async()=>{
  const tx=(await ok('transactions','POST',{group_id:f.group,payee_id:f.payee,provider_reference:'REF-PAGING-003',amount_rwf:1000,observed_at:timestamp,evidence:{kind:'operator_observation',reference:'Paging evidence fixture',sha256:'d'.repeat(64)}})).resource_id;
  const statements=[];
  for(let i=0;i<201;i++){
    const op=uuid();statements.push(q('INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?)',op,owner.id,'test.allocation',uuid(),'f'.repeat(64),timestamp));
    statements.push(q('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,1,?,?,?)',uuid(),tx,f.group,f.user,op,owner.id,timestamp));
  }
  await db.batch(statements);
  const detail=await ok(`transactions/${tx}`);assert.equal(detail.related.allocations.length,50);assert.equal(detail.related_truncated,true);assert.equal(detail.resource.allocated_amount_rwf,201);
  assert.deepEqual(detail.related_pages.allocations,{total:201,limit:50,offset:0,next_offset:50});
  const seen=[];
  for(const offset of [0,100,200]){const page=await ok(`transactions/${tx}?relation=allocations&limit=100&offset=${offset}`);
    assert.deepEqual(Object.keys(page.related),['allocations']);assert.equal(page.related_pages.allocations.total,201);
    seen.push(...page.related.allocations.map(x=>x.id));assert.equal(page.resource.allocated_amount_rwf,201);}
  assert.equal(seen.length,201);assert.equal(new Set(seen).size,201);
});

test('Direct members need recorded MoMo data, optional codes and no App login or App notification',async()=>{
  assert.equal((await api('users','POST',{display_name:'Direct Missing Number',member_type:'direct',email:'direct-missing@example.com'})).status,400);
  const receipt=await ok('users','POST',{display_name:'Diane Nyiransabimana',member_type:'direct',momo_number:'+250 788 765 432',momo_pay_code:'008000',status:'active'});
  const person=await ok(`users/${receipt.resource_id}`,'GET',null,staff);
  assert.deepEqual(person.resource.user_types,['Direct']);assert.equal(person.resource.whatsapp_number,null);
  assert.equal(person.resource.display_name_recorded,true);
  assert.equal(person.resource.phone_e164,'+250788765432');assert.equal(person.resource.momo_number,'0788765432');assert.equal(person.resource.momo_pay_code,'008000');
  assert.equal((await first('SELECT count(*) AS n FROM collect_notification_outbox WHERE recipient_user_id=?',receipt.resource_id)).n,0);
  await assert.rejects(run('INSERT INTO member_sessions(id,user_id,token_hash,refresh_hash,created_at,expires_at,refresh_until,verified_at) VALUES(?,?,?,?,?,?,?,?)',uuid(),receipt.resource_id,'d'.repeat(64),'e'.repeat(64),timestamp,timestamp+60,timestamp+120,timestamp),/Direct members/);
  await ok(`users/${receipt.resource_id}`,'PATCH',{expected_version:1,momo_pay_code:null});
  assert.equal((await ok(`users/${receipt.resource_id}`)).resource.momo_pay_code,null);
  assert.equal((await api(`users/${receipt.resource_id}`,'PATCH',{expected_version:2,momo_number:''})).status,409);
  const members=await ok(`lookups?kind=users&search=${encodeURIComponent('+250788765432')}`,'GET',null,staff);
  assert.equal(members.rows.length,1);assert.equal(members.rows[0].momo_number,'0788765432');assert.equal(members.rows[0].whatsapp_number,null);
});

test('unknown member-auth name is shown honestly and an audited Admin name input records it',async()=>{
  const person=uuid();await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'unknown-recorded-name@example.com','active',?,?)",person,timestamp,timestamp);
  await run(`INSERT INTO collect_profiles(user_id,public_id,display_name,display_name_recorded,created_at,updated_at) SELECT ?,(${AVAILABLE_PERSON_PUBLIC_ID_SQL}),'Collect member',0,?,?`,person,timestamp,timestamp);
  const before=await ok(`users/${person}`,'GET',null,staff);assert.equal(before.resource.display_name,null);assert.equal(before.resource.display_name_recorded,false);
  await ok(`users/${person}`,'PATCH',{expected_version:1,display_name:'Recorded Jean Umuhoza'});
  const after=await ok(`users/${person}`);assert.equal(after.resource.display_name,'Recorded Jean Umuhoza');assert.equal(after.resource.display_name_recorded,true);
  assert.equal(after.resource.name_verification,'recorded_not_provider_verified');
});

test('global six-digit identities are unique under concurrent creation and explicit operator links do not grant privileges',async()=>{
  const bodies=Array.from({length:6},(_,i)=>({display_name:`Concurrent Person ${i}`,email:`concurrent-${i}@example.com`,member_type:'app',status:'active'}));
  const created=await Promise.all(bodies.map(body=>api('users','POST',body)));
  assert.ok(created.every(r=>r.status===200),JSON.stringify(created));
  const ids=await Promise.all(created.map(r=>ok(`users/${r.body.resource_id}`)));
  assert.equal(new Set(ids.map(r=>r.resource.public_id)).size,6);
  assert.ok(ids.every(r=>/^[0-9]{6}$/.test(r.resource.public_id)));
  const account=created[0].body.resource_id;
  const adminAlias=(await first('SELECT public_id FROM collect_public_identities WHERE admin_user_id=?',admin.id)).public_id;
  assert.equal((await api(`users/${account}`,'PATCH',{expected_version:1,operator_admin_id:admin.id},admin)).status,403);
  await ok(`users/${account}`,'PATCH',{expected_version:1,operator_admin_id:admin.id});
  const direct=await ok(`users/${admin.id}`,'GET',null,staff);
  assert.equal(direct.resource.id,account);assert.equal(direct.resource.operator_public_id,adminAlias);
  assert.deepEqual(direct.resource.user_types,['Admin','App']);
  assert.ok(!JSON.stringify(direct).includes('password_hash'));assert.ok(!JSON.stringify(direct).includes('auth_version'));
  assert.equal((await api(`users/${created[1].body.resource_id}`,'PATCH',{expected_version:1,operator_admin_id:admin.id})).status,409);
  await assert.rejects(run('UPDATE collect_profiles SET public_id=? WHERE user_id=?','999998',account),/immutable/);
  await assert.rejects(run('UPDATE collect_public_identities SET public_id=? WHERE source_id=?','999997',admin.id),/immutable/);
  await assert.rejects(run('DELETE FROM collect_public_identities WHERE source_id=?',admin.id),/reserved/);
  assert.equal((await first('SELECT role FROM admin_users WHERE id=?',admin.id)).role,'admin');
});

test('contribution detail totals are independent of list limits and separately identify posted ledger amounts',async()=>{
  const person=await ok(`users/${f.user}`,'GET',null,staff);
  assert.ok(person.resource.total_contributed_rwf>=2500);
  assert.equal(person.resource.posted_contributed_rwf,2500);
  const group=person.related.memberships.find(row=>row.group_id===f.group);
  assert.equal(group.total_contributed_rwf,person.resource.total_contributed_rwf);
  assert.equal(group.posted_contributed_rwf,2500);assert.equal(group.role,'owner');
  assert.equal(group.whatsapp_number,'+250788123456');
  assert.equal(person.resource.contribution_basis,'confirmation_recorded_allocations');
  const lookup=await ok(`lookups?kind=members&group_id=${f.group}&search=${encodeURIComponent('+250 788 123 456')}`,'GET',null,staff);
  const membership=await first('SELECT version FROM collect_memberships WHERE group_id=? AND user_id=?',f.group,f.user);
  assert.equal(lookup.rows.length,1);assert.equal(lookup.rows[0].version,membership.version);assert.equal(lookup.rows[0].role,'owner');
  assert.equal(lookup.rows[0].whatsapp_number,'+250788123456');
});

test('Staff creates private groups with one audited receipt and never acquires broad write or publication access',async()=>{
  const key=uuid(),draft={title:'Staff private draft',slug:`staff-${uuid()}`,collection_type:'ikimina'};
  const responses=await Promise.all([api('groups','POST',draft,staff,key),api('groups','POST',draft,staff,key)]);
  assert.ok(responses.every(x=>x.status===200),JSON.stringify(responses));assert.deepEqual(responses[0].body,responses[1].body);
  const receipt=responses[0].body,detail=await ok(`groups/${receipt.resource_id}`,'GET',null,staff);
  assert.equal(detail.resource.visibility,'private');assert.equal(detail.resource.status,'draft');assert.equal(detail.resource.is_platform_sponsored,0);
  assert.equal(detail.resource.created_by_admin_id,staff.id);assert.equal(detail.can_manage,false);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE operation_request_id=?',receipt.request_id)).n,1);
  assert.deepEqual((await ok(`requests/${key}`,'GET',null,staff)).receipt,receipt);
  assert.equal((await ok(`requests/${key}`,'GET',null,owner)).status,'not_found');
  assert.equal((await api(`groups/${receipt.resource_id}`,'PATCH',{expected_version:1,visibility:'public_approved'},staff)).status,403);
  assert.equal((await api('groups','POST',{...draft,slug:`public-${uuid()}`,visibility:'public_approved'},staff)).status,403);
  assert.equal((await api('groups','POST',{...draft,slug:`sponsored-${uuid()}`,is_platform_sponsored:true},staff)).status,403);
  assert.equal((await api('groups','POST',{...draft,slug:`unsafe-${uuid()}`,status:'active'},staff)).status,400);
  assert.equal((await api('payees','POST',{group_id:receipt.resource_id,label:'Forbidden route',network:'mtn_momo',momo_number_or_code:'008000'},staff)).status,403);
  const request=new Request(`${origin}/api/admin/operations/groups`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({reason,...draft})});
  await assert.rejects(handleOperations(request,{ADMIN_DB:db},{...staff,permissions:CORE_READ_PERMISSIONS}),e=>e instanceof OperationsError&&e.status===403);
});

test('Staff active-group creation atomically requires a selected active owner and an immutable receiver',async()=>{
  const payload={title:'Staff active private group',slug:`active-${uuid()}`,collection_type:'ikimina',status:'active',owner_user_id:f.user,
    receiver:{label:'Recorded Receiver',network:'mtn_momo',momo_number_or_code:'008000'}};
  const receipt=await ok('groups','POST',payload,staff),detail=await ok(`groups/${receipt.resource_id}`,'GET',null,staff);
  assert.equal(detail.resource.status,'active');assert.equal(detail.resource.visibility,'private');
  assert.equal(detail.related.memberships.length,1);assert.equal(detail.related.memberships[0].user_id,f.user);assert.equal(detail.related.memberships[0].role,'owner');
  assert.equal(detail.related.payees.length,1);assert.equal(detail.related.payees[0].momo_number_or_code,'008000');
  assert.equal(detail.related.payees[0].created_by_admin_id,staff.id);
  const before=(await first('SELECT count(*) AS n FROM collect_groups')).n;
  assert.equal((await api('groups','POST',{...payload,slug:`invalid-owner-${uuid()}`,owner_user_id:uuid()},staff)).status,409);
  assert.equal((await first('SELECT count(*) AS n FROM collect_groups')).n,before);
  assert.equal((await api('groups','POST',{...payload,slug:`invalid-route-${uuid()}`,receiver:{...payload.receiver,momo_number_or_code:'bad'}},staff)).status,400);
  assert.equal((await api('groups','POST',{...payload,slug:`forged-route-${uuid()}`,receiver:{...payload.receiver,status:'inactive'}},staff)).status,400);
  await assert.rejects(run("UPDATE collect_payees SET momo_number_or_code='009999' WHERE id=?",detail.related.payees[0].id),/immutable/);
});

test('Staff private-create snapshot fence rolls back after revocation or actor-role change',async()=>{
  for(const mode of ['revoke','role']){
    const actorNow=await actor('staff');let batches=0;const slug=`staff-race-${uuid()}`;
    const wrapped={prepare:sql=>db.prepare(sql),batch:async statements=>{batches++;if(batches===2){if(mode==='revoke')await run('DELETE FROM admin_sessions WHERE token_hash=?',actorNow.token_hash);else await run("UPDATE admin_users SET role='admin' WHERE id=?",actorNow.id);}return db.batch(statements);}};
    const request=new Request(`${origin}/api/admin/operations/groups`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':uuid()},body:JSON.stringify({reason,title:'Fenced Staff group',slug,collection_type:'other'})});
    await assert.rejects(handleOperations(request,{ADMIN_DB:wrapped},actorNow),e=>e instanceof OperationsError&&e.status===401);
    assert.equal((await first('SELECT count(*) AS n FROM collect_groups WHERE slug=?',slug)).n,0);
  }
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});

test('related views paginate complete user memberships and group accounts in stable same-timestamp order',async()=>{
  const statements=[];
  for(let i=0;i<205;i++){
    const group=uuid();statements.push(q("INSERT INTO collect_groups(id,slug,title,collection_type,status,created_by_admin_id,created_at,updated_at) VALUES(?,?,?,'other','draft',?,?,?)",group,`related-${group}`,`Related group ${i}`,owner.id,timestamp,timestamp));
    statements.push(q("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'member','active',?,?,?)",group,f.user,timestamp,timestamp,timestamp));
    statements.push(q("INSERT INTO collect_ledger_accounts(id,group_id,code,name,account_type,normal_side,created_by_admin_id,created_at) VALUES(?,?,?,?,'asset','debit',?,?)",uuid(),f.group,`PAGE-${String(i).padStart(3,'0')}`,`Paged account ${i}`,owner.id,timestamp));
    const person=uuid();statements.push(q("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,?,'active',?,?)",person,`related-${person}@example.com`,timestamp,timestamp));
    statements.push(q(`INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) SELECT ?,(${AVAILABLE_PERSON_PUBLIC_ID_SQL}),?,?,?`,person,`Paged Member ${i}`,timestamp,timestamp));
    statements.push(q("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'member','active',?,?,?)",f.group,person,timestamp,timestamp,timestamp));
  }
  await db.batch(statements);
  for(const [path,relation,key] of [[`users/${f.user}`,'memberships','group_id'],[`groups/${f.group}`,'accounts','id'],[`groups/${f.group}`,'memberships','user_id']]){
    const initial=await ok(path,'GET',null,staff);assert.equal(initial.related[relation].length,50);assert.ok(initial.related_pages[relation].total>200);
    const identifiers=[];let offset=0,total=initial.related_pages[relation].total;
    do{const page=await ok(`${path}?relation=${relation}&limit=100&offset=${offset}`,'GET',null,staff);
      assert.deepEqual(Object.keys(page.related),[relation]);assert.equal(page.related_pages[relation].total,total);
      identifiers.push(...page.related[relation].map(x=>x[key]));offset=page.related_pages[relation].next_offset;
    }while(offset!==null);
    assert.equal(identifiers.length,total);assert.equal(new Set(identifiers).size,total);
    const replay=await ok(`${path}?relation=${relation}&limit=100&offset=0`,'GET',null,staff);
    assert.deepEqual(replay.related[relation].map(x=>x[key]),identifiers.slice(0,100));
  }
  const payee=await ok(`payees/${f.payee}`);assert.deepEqual(payee.related_pages,{});
  for(const suffix of ['?relation=unknown','?relation=memberships&limit=101','?relation=memberships&offset=-1','?relation=memberships&limit=01','?relation=memberships&relation=memberships','?limit=50'])
    assert.equal((await api(`users/${f.user}${suffix}`)).status,400,suffix);
});

test('journal related-entry pagination preserves every immutable line beyond the default window',async()=>{
  const journal=(await ok('journals','POST',{group_id:f.group,description:'Long source journal',entries:[{account_id:f.debit,debit_rwf:1,credit_rwf:0},{account_id:f.credit,debit_rwf:0,credit_rwf:1}]})).resource_id;
  const statements=[];
  for(let i=0;i<100;i++)for(const credit of [false,true])statements.push(q('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,?,?,?)',uuid(),journal,f.group,credit?f.credit:f.debit,i*2+(credit?4:3),credit?0:1,credit?1:0));
  await db.batch(statements);
  const initial=await ok(`journals/${journal}`);assert.equal(initial.related.entries.length,50);assert.equal(initial.related_pages.entries.total,202);
  const lines=[];for(const offset of [0,100,200]){const page=await ok(`journals/${journal}?relation=entries&limit=100&offset=${offset}`,'GET',null,staff);lines.push(...page.related.entries.map(x=>x.line_number));}
  assert.deepEqual(lines,Array.from({length:202},(_,i)=>i+1));
});

test('legacy raw allocation endpoint requires reviewed reconciliation with no financial or receipt effect',async()=>{
  const counts=async()=>first('SELECT (SELECT count(*) FROM collect_payment_allocations) AS allocations,(SELECT count(*) FROM collect_operation_requests) AS requests,(SELECT count(*) FROM collect_operations_audit) AS audits,(SELECT count(*) FROM collect_transaction_reviews) AS reviews');
  const before=await counts(),old=(await ok(`transactions/${f.tx}`)).resource;
  for(const actorNow of [owner,admin,staff])for(const body of [{member_user_id:null,amount_rwf:1},{expected_version:old.version,member_user_id:f.user,amount_rwf:1}]){
    const result=await api(`transactions/${f.tx}/allocations`,'POST',body,actorNow);
    assert.equal(result.status,actorNow.role==='staff'?403:409,JSON.stringify(result.body));
    assert.equal(result.body.error,actorNow.role==='staff'?'permission_required':'reconciliation_required');
  }
  const receiptKey=uuid();
  await run("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,status,response_json,created_at,completed_at) VALUES(?,?,'transactions.post.allocations',? ,?,'succeeded',?,?,?)",uuid(),owner.id,receiptKey,'a'.repeat(64),JSON.stringify({status:'succeeded',resource_id:f.tx}),timestamp,timestamp);
  const beforeReplay=await counts();
  const replay=await api(`transactions/${f.tx}/allocations`,'POST',{},owner,receiptKey);assert.equal(replay.status,409);assert.equal(replay.body.error,'reconciliation_required');assert.deepEqual(await counts(),beforeReplay);
  assert.equal((await counts()).allocations,before.allocations);assert.equal((await counts()).audits,before.audits);
  assert.equal((await ok(`transactions/${f.tx}`)).resource.version,old.version);
});

async function sourceContext() {
  const member=(await ok('users','POST',{display_name:'Source Payer Recorded',member_type:'direct',email:`source-${uuid()}@example.com`,momo_number:'0782501234',momo_pay_code:'0041258',status:'active'})).resource_id;
  const group=(await ok('groups','POST',{title:'Source facts group',slug:`source-${uuid()}`,collection_type:'ikimina',status:'active',owner_user_id:member,receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:'0041258'}})).resource_id;
  const payee=(await ok(`groups/${group}`)).related.payees[0].id;
  return {member,group,payee};
}
const transactionBody=(context,reference,factId,amount=700,observed=timestamp)=>({group_id:context.group,payee_id:context.payee,provider_reference:reference,amount_rwf:amount,observed_at:observed,...(factId?{source_fact_id:factId}:{}),evidence:{kind:'receiver_statement',reference:`Receiver source ${reference}`,sha256:'a'.repeat(64)}});

test('source-linked transaction retries persist one immutable cryptographic reference, exact facts and actor-scoped receipt',async()=>{
  const context=await sourceContext(),reference='OPS-SOURCE-REPLAY',key=uuid();
  const fact=await receiverFact(db,{actorId:owner.id,payeeId:context.payee,reference,payerPhone:'+250782501234',time:timestamp});
  const payload=transactionBody(context,reference,fact.id);
  const responses=await Promise.all([api('transactions','POST',payload,owner,key),api('transactions','POST',payload,owner,key)]);
  assert.ok(responses.every(x=>x.status===200),JSON.stringify(responses));assert.deepEqual(responses[0].body,responses[1].body);
  const receipt=responses[0].body,detail=await ok(`transactions/${receipt.resource_id}`,'GET',null,staff),row=detail.resource;
  for(const field of transactionAdditionalFields)assert.ok(Object.hasOwn(row,field),field);
  assert.match(row.transaction_reference,/^234258[0-9]{12}$/);assert.equal(row.reference_random_source,'crypto_get_random_values');
  assert.equal(row.source_fact_id,fact.id);assert.equal(row.reference_source_fact_id,fact.id);assert.equal(row.source_parsed_at,timestamp);assert.equal(row.payer_phone,'+250782501234');
  assert.equal(row.payee_momo_number,null);assert.equal(row.payee_momo_code,null);assert.equal(row.payee_momo_number_or_code,'0041258');
  assert.equal(row.source_amount_rwf,700);assert.equal(row.wallet_balance_rwf,50000);assert.equal(row.momo_timezone_offset,'+02:00');
  assert.equal(row.provider_confirmation,false);assert.equal(row.settlement_status,'not_asserted');assert.equal(row.payer_source_match_status,'unique_recorded_match');
  assert.equal(row.payer_insights_status,'available');assert.equal(detail.related.payer_insights.length,1);
  const insight=detail.related.payer_insights[0];assert.equal(insight.member_user_id,context.member);assert.equal(insight.momo_number,'0782501234');assert.deepEqual(insight.attribution_basis,['source_full_momo_phone']);assert.equal(insight.name_verification,'recorded_not_provider_verified');
  assert.equal(insight.total_contributed_rwf,0);assert.equal(insight.posted_contributed_rwf,0);assert.equal(insight.attributed_transaction_count,1);
  assert.equal(insight.latest_transaction_reference,row.transaction_reference);assert.equal(insight.latest_transaction_observed_at,timestamp);assert.equal(insight.latest_transaction_verification_status,'pending');
  assert.equal((await first('SELECT count(*) AS n FROM collect_transaction_public_references WHERE transaction_id=?',receipt.resource_id)).n,1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE operation_request_id=?',receipt.request_id)).n,1);
  assert.deepEqual((await ok(`requests/${key}`)).receipt,receipt);
  assert.equal((await ok(`requests/${key}`,'GET',null,admin)).status,'not_found');
  assert.equal((await api('transactions','POST',{...payload,source_fact_id:uuid()},owner,key)).body.error,'idempotency_conflict');
  assert.deepEqual((await ok(`transactions/${receipt.resource_id}`)).resource,row);
  for(const field of ['public_reference','payer_source_match_count','allocated_member_count','public_reference_source_fact_id'])assert.equal(Object.hasOwn(row,field),false,field);
  await assert.rejects(run('UPDATE collect_transaction_public_references SET public_reference=? WHERE transaction_id=?','000000000000000001',receipt.resource_id),/immutable/);
  await assert.rejects(run('UPDATE collect_sms_facts SET payer_name=? WHERE id=?','Forged payer',fact.id),/immutable/);
});

test('masked payer digits and absent time zone remain facts and never identify a member by name, suffix or WhatsApp',async()=>{
  const context=await sourceContext(),reference='OPS-SOURCE-MASKED';
  const fact=await receiverFact(db,{actorId:owner.id,payeeId:context.payee,reference,payerPhone:'***234',payerName:'Source Payer Recorded',offset:'',time:timestamp});
  const receipt=await ok('transactions','POST',transactionBody(context,reference,fact.id)),detail=await ok(`transactions/${receipt.resource_id}`);
  assert.equal(detail.resource.payer_phone,null);assert.equal(detail.resource.payer_masked_phone,'***234');assert.equal(detail.resource.payer_last3,'234');
  assert.equal(detail.resource.reference_payer_last3_known,true);assert.equal(detail.resource.momo_timestamp_local,'2026-10-05T12:35:45');assert.equal(detail.resource.momo_timezone_offset,null);assert.equal(detail.resource.timezone_known,false);
  assert.equal(detail.resource.payer_source_match_status,'not_recorded');assert.equal(detail.resource.payer_insights_status,'not_attributed');assert.deepEqual(detail.related.payer_insights,[]);assert.equal(detail.related_pages.payer_insights.total,0);
  assert.equal(detail.resource.payer_name,'Source Payer Recorded');assert.equal(detail.resource.provider_reference,reference);
});

test('transaction creation without an explicit fact link remains unknown even when provider references match',async()=>{
  const context=await sourceContext(),reference='OPS-SOURCE-UNLINKED';
  await receiverFact(db,{actorId:owner.id,payeeId:context.payee,reference,payerPhone:'+250782501234',time:timestamp});
  const receipt=await ok('transactions','POST',transactionBody(context,reference,null)),detail=await ok(`transactions/${receipt.resource_id}`);
  assert.match(detail.resource.transaction_reference,/^000000[0-9]{12}$/);assert.equal(detail.resource.reference_random_source,'crypto_get_random_values');
  assert.equal(detail.resource.reference_payer_last3_known,false);assert.equal(detail.resource.reference_payee_last3_known,false);
  assert.equal(detail.resource.source_fact_id,null);assert.equal(detail.resource.payer_name,null);assert.equal(detail.resource.payer_last3,null);assert.equal(detail.resource.is_payment,null);
  assert.deepEqual(detail.related.payer_insights,[]);assert.equal(detail.resource.payee_momo_number_or_code,'0041258');
});

test('wrong or conflicting source facts roll back the entire transaction, reference, operation and audit',async()=>{
  const context=await sourceContext(),reference='OPS-SOURCE-CONTEXT';
  const fact=await receiverFact(db,{actorId:owner.id,payeeId:context.payee,reference,time:timestamp});
  const count=()=>first('SELECT (SELECT count(*) FROM collect_transactions) AS transactions,(SELECT count(*) FROM collect_transaction_public_references) AS references_count,(SELECT count(*) FROM collect_operation_requests) AS requests,(SELECT count(*) FROM collect_operations_audit) AS audits');
  for(const payload of [transactionBody(context,reference,fact.id,701),transactionBody(context,'OPS-SOURCE-WRONG-REFERENCE',fact.id),transactionBody({group:f.group,payee:f.payee},reference,fact.id),transactionBody(context,reference,uuid())]){
    const before=await count(),result=await api('transactions','POST',payload);
    assert.equal(result.status,409,JSON.stringify(result.body));assert.deepEqual(await count(),before);
    assert.equal((await ok(`requests/${result.key}`)).status,'not_found');
  }
  assert.equal((await api('transactions','POST',transactionBody(context,reference,fact.id),staff)).status,403);
  await receiverFact(db,{actorId:owner.id,payeeId:context.payee,reference,payerPhone:'***999',time:timestamp});
  const before=await count(),conflict=await api('transactions','POST',transactionBody(context,reference,fact.id));assert.equal(conflict.status,409);assert.deepEqual(await count(),before);
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});

test('reference collision is a failed atomic claim and cannot leave an orphan or duplicate transaction',async()=>{
  const existing=(await ok(`transactions/${f.tx}`)).resource.transaction_reference,key=uuid(),reference='OPS-REFERENCE-COLLISION';
  const wrapped={prepare:sql=>({bind(...values){if(sql.startsWith('INSERT INTO collect_transaction_public_references('))values[1]=existing;return db.prepare(sql).bind(...values);}}),batch:statements=>db.batch(statements)};
  const request=new Request(`${origin}/api/admin/operations/transactions`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify({reason,...transactionBody({group:f.group,payee:f.payee},reference,null)})});
  const before=(await first('SELECT count(*) AS n FROM collect_transaction_public_references')).n;
  await assert.rejects(handleOperations(request,{ADMIN_DB:wrapped},owner),e=>e instanceof OperationsError&&e.status===409&&e.code==='state_conflict');
  assert.equal((await first('SELECT count(*) AS n FROM collect_transaction_public_references')).n,before);
  assert.equal((await first('SELECT count(*) AS n FROM collect_transactions WHERE provider_reference=?',reference)).n,0);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?',owner.id,key)).n,0);
  assert.equal((await first('SELECT count(*) AS n FROM collect_transaction_public_references r LEFT JOIN collect_transactions t ON t.id=r.transaction_id WHERE t.id IS NULL')).n,0);
});

test('payer insight attribution rejects ambiguous full-phone matches but honors explicit allocated-member history with exact paged totals',async()=>{
  const context=await sourceContext(),reference='OPS-INSIGHT-ALLOCATION';
  const fact=await receiverFact(db,{actorId:owner.id,payeeId:context.payee,reference,payerPhone:'+250782501234',time:timestamp});
  const receipt=await ok('transactions','POST',transactionBody(context,reference,fact.id)),transaction=receipt.resource_id;
  // Different recorded people may share a MoMo number. Neither match is guessed.
  const duplicate=(await ok('users','POST',{display_name:'Different Recorded Person',member_type:'direct',email:`duplicate-${uuid()}@example.com`,momo_number:'0782501234',status:'active'})).resource_id;
  let detail=await ok(`transactions/${transaction}`);assert.equal(detail.resource.payer_source_match_status,'ambiguous');assert.equal(detail.resource.payer_insights_status,'ambiguous');assert.deepEqual(detail.related.payer_insights,[]);
  const evidenceId=detail.related.evidence[0].id;await ok(`transactions/${transaction}/verification`,'POST',{expected_version:1,evidence_id:evidenceId,outcome:'confirmation_recorded'},admin);
  const allocation=await historicalAllocation(transaction,context.group,context.member,700);
  const debit=(await ok('accounts','POST',{group_id:context.group,code:'1000',name:'Received funds',account_type:'asset',normal_side:'debit'})).resource_id;
  const credit=(await ok('accounts','POST',{group_id:context.group,code:'2000',name:'Recorded contributions',account_type:'liability',normal_side:'credit'})).resource_id;
  const journal=(await ok('journals','POST',{group_id:context.group,allocation_id:allocation,description:'Historical reviewed allocation',entries:[{account_id:debit,debit_rwf:700,credit_rwf:0},{account_id:credit,debit_rwf:0,credit_rwf:700}]})).resource_id;
  await ok(`journals/${journal}/post`,'POST',{expected_version:1},admin);
  const secondGroup=(await ok('groups','POST',{title:'Related contribution group',slug:`insight-${uuid()}`,collection_type:'other'})).resource_id;
  await ok('memberships','POST',{group_id:secondGroup,user_id:context.member,role:'member',status:'active'});
  detail=await ok(`transactions/${transaction}`,'GET',null,staff);assert.equal(detail.resource.payer_source_match_status,'ambiguous');assert.equal(detail.resource.payer_insights_status,'available');assert.equal(detail.related.payer_insights.length,2);
  const identifiers=[];
  for(const offset of [0,1]){
    const page=await ok(`transactions/${transaction}?relation=payer_insights&limit=1&offset=${offset}`,'GET',null,staff);
    assert.deepEqual(Object.keys(page.related),['payer_insights']);assert.deepEqual(page.related_pages.payer_insights,{total:2,limit:1,offset,next_offset:offset===0?1:null});
    const row=page.related.payer_insights[0];identifiers.push(row.id);assert.equal(row.member_user_id,context.member);assert.notEqual(row.member_user_id,duplicate);assert.deepEqual(row.attribution_basis,['allocated_member']);
    assert.equal(row.total_contributed_rwf,700);assert.equal(row.posted_contributed_rwf,700);assert.equal(row.attributed_transaction_count,1);assert.equal(row.latest_transaction_id,transaction);assert.equal(row.latest_transaction_reference,detail.resource.transaction_reference);
    assert.equal(row.group_total_contributed_rwf,row.group_id===context.group?700:0);assert.equal(row.group_posted_contributed_rwf,row.group_id===context.group?700:0);assert.equal(row.transaction_allocated_rwf,row.group_id===context.group?700:0);
    assert.equal(row.contribution_basis,'confirmation_recorded_allocations');assert.equal(row.name_verification,'recorded_not_provider_verified');
  }
  assert.equal(new Set(identifiers).size,2);assert.deepEqual((await ok(`transactions/${transaction}?relation=payer_insights&limit=1&offset=0`)).related.payer_insights.map(x=>x.id),identifiers.slice(0,1));
});

test('payer insights enumerate every attributed membership beyond 200 with stable totals and complete deterministic pages',async()=>{
  const initial=await ok(`transactions/${f.tx}`,'GET',null,staff),metadata=initial.related_pages.payer_insights;
  assert.ok(metadata.total>200);assert.equal(initial.related.payer_insights.length,50);
  const ids=[],all=[];let offset=0;
  do{const page=await ok(`transactions/${f.tx}?relation=payer_insights&limit=100&offset=${offset}`,'GET',null,staff);
    assert.equal(page.related_pages.payer_insights.total,metadata.total);assert.deepEqual(Object.keys(page.related),['payer_insights']);
    for(const row of page.related.payer_insights){assert.equal(row.member_user_id,f.user);assert.deepEqual(row.attribution_basis,['allocated_member']);assert.equal(row.total_contributed_rwf,initial.related.payer_insights[0].total_contributed_rwf);assert.equal(row.posted_contributed_rwf,2500);ids.push(row.id);all.push(row);}
    offset=page.related_pages.payer_insights.next_offset;
  }while(offset!==null);
  assert.equal(ids.length,metadata.total);assert.equal(new Set(ids).size,metadata.total);
  assert.deepEqual((await ok(`transactions/${f.tx}?relation=payer_insights&limit=100&offset=0`)).related.payer_insights,all.slice(0,100));
});
