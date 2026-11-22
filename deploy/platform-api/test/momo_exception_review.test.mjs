import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture} from './admin_sms_support/fixture.mjs';
import {processMomoJob,validateMomoExtraction} from '../src/momo_pipeline.js';

const synthetic=JSON.parse(await readFile(new URL('fixtures/momo-synthetic.json',import.meta.url),'utf8'));
const copy=value=>structuredClone(value),date=()=>new Date().toISOString();
async function operator(f,options={}){const account=await f.seedAccount(options);return {...await f.stepUp(await f.login(account)),account};}
const action=(s,path,body,key=randomUUID(),headers={})=>s.f.call('/api/admin/momo/'+path,{cookie:s.owner.cookie,data:body,headers:{'Idempotency-Key':key,...headers}});
function negative(kind,excerpt){const output=copy(synthetic.output);for(const key of Object.keys(output))if(key.endsWith('_raw'))output[key]=null;
 output.event_kind=kind;output.payment_outcome={outgoing:'successful',failed:'failed',pending:'pending',unknown:'unknown'}[kind]??'unknown';
 output.evidence=Object.fromEntries(Object.keys(output.evidence).map(key=>[key,null]));output.evidence.incoming_success=excerpt;output.issues=[];return output;}
function amountOutput(amount){const output=copy(synthetic.output);output.principal_amount_raw=amount;output.evidence.principal='RWF '+amount;output.evidence.incoming_success='You have received RWF '+amount;return output;}
async function setup(t){
 const f=await fixture(t,{MOMO_PROCESSING_PAUSED:'true'},{migrationsThrough:15}),owner=await operator(f),s={f,owner};
 const account=await action(s,'accounts',{provider:'mtn_momo',public_code:'+250788123456',recipient_name:'Synthetic exception receiver',reason:'Create controlled exception-review receiving account'});assert.equal(account.status,200,JSON.stringify(account));s.accountId=account.body.id;
 assert.equal((await action(s,`accounts/${s.accountId}/profile`,{profile:synthetic.profile,profile_version:'synthetic.v1',reason:'Approve invented fixture format for isolated validation only'})).status,200);
 const binding=await action(s,'bindings',{receiving_account_id:s.accountId,reason:'Enroll controlled exception-review capture source'});assert.equal(binding.status,200);
 const pair=await f.call('/v1/momo/gateway/pair',{origin:null,data:{pairing_code:binding.body.pairing_code,installation_id:randomUUID()}});assert.equal(pair.status,200);s.pair=pair.body;
 let output=copy(synthetic.output),calls=0;
 s.setOutput=value=>{output=value;};s.aiCalls=()=>calls;
 s.env={DB:f.db,PRIVATE_MEDIA:await f.mf.getR2Bucket('PRIVATE_MEDIA'),DATA_KEY_ID:'admin-test-v1',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),AI:{run:async()=>{calls++;return {response:copy(output)};}}};
 s.capture=async({body=synthetic.body,sender=synthetic.sender,complete=true}={})=>{
  const upload=await f.call('/v1/momo/gateway/ingest',{origin:null,headers:{Authorization:'Bearer '+s.pair.gateway_token},data:{client_envelope_id:randomUUID(),raw_sender:sender,raw_body:body,gateway_binding_id:s.pair.binding.id,gateway_binding_version:s.pair.binding.version,
   service_centre_at:date(),captured_at:date(),inbox_received_at:null,source_mode:'live',subscription_id:null,complete}});assert.equal(upload.status,200,JSON.stringify(upload));return upload.body.receipt.raw_sms_id;
 };
 s.process=raw=>processMomoJob(s.env,raw);
 s.job=raw=>f.db.prepare('SELECT j.*,s.body_sha256 FROM momo_processing_jobs j JOIN sms_receipts s ON s.id=j.raw_sms_id WHERE j.raw_sms_id=?').bind(raw).first();
 s.reviewBody=async(raw,extraction=copy(synthetic.output))=>{const job=await s.job(raw);return {expected_state:job.state,expected_attempt_count:job.attempt_count,expected_body_sha256:job.body_sha256,extraction,
  evidence_reference:'Controlled retained source and provider-profile evidence',reason:'Review exact source fields against the approved fixture profile'};};
 s.exception=async(options={})=>{const raw=await s.capture(options);s.setOutput({...copy(synthetic.output),principal_amount_raw:'9,999'});assert.equal((await s.process(raw)).state,'needs_review');return raw;};
 s.noMoney=async()=>{for(const table of ['payments','ledger_entries','notification_events'])assert.equal((await f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n,0);};
 return s;
}

test('contrary model labels cannot silently discard a recognizable incoming receipt or unsupported negative evidence',()=>{
 const account={status:'active',profile_status:'approved',profile_version:'synthetic.v1',profile_json:JSON.stringify(synthetic.profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'},source={raw_sender:synthetic.sender,raw_body:synthetic.body,completeness:'complete'};
 for(const change of [output=>{output.event_kind='other';},output=>{output.payment_outcome='unknown';},output=>{output.event_kind='outgoing';},output=>{output.event_kind='failed';output.payment_outcome='failed';output.evidence.incoming_success='invented failed marker';}]){
  const output=copy(synthetic.output);change(output);const checked=validateMomoExtraction(output,source,account);assert.equal(checked.accepted,false);assert.equal(checked.nonPayment,false);
 }
 for(const [kind,body] of [['outgoing','You have sent RWF 5,000.'],['failed','The requested payment failed.'],['pending','Your withdrawal is pending.']]){
  assert.equal(validateMomoExtraction(negative(kind,body),{...source,raw_body:body},account).nonPayment,true);
  assert.equal(validateMomoExtraction(negative(kind,body+' invented'),{...source,raw_body:body},account).nonPayment,false);
 }
 assert.equal(validateMomoExtraction(negative('failed','Payment failed.'),{...source,raw_body:synthetic.body+' Payment failed.'},account).nonPayment,false);
 assert.equal(validateMomoExtraction(negative('failed','Payment failed.'),{...source,raw_body:'Payment reversal. Payment failed.'},account).nonPayment,false);
});

test('source correction appends a labelled validated attempt atomically, returns no private extraction, and exact replay cannot duplicate it',async t=>{
 const s=await setup(t),raw=await s.exception(),before=(await s.f.db.prepare('SELECT * FROM momo_parse_attempts WHERE raw_sms_id=?').bind(raw).all()).results;
 const page=await s.f.call('/api/admin/momo/sources?status=needs_review',{method:'GET',cookie:s.owner.cookie});assert.equal(page.status,200);assert.equal(page.body.rows[0].body_sha256,(await s.job(raw)).body_sha256);assert.ok(!JSON.stringify(page.body).includes('output_json'));assert.ok(!JSON.stringify(page.body).includes(synthetic.body));
 const staff=await operator(s.f,{role:'staff',email:'source-metadata-only@example.test'}),hidden=await s.f.call(`/api/admin/momo/sources/${raw}/content`,{method:'GET',cookie:staff.cookie,headers:{'X-Collect-Review-Reason':'Controlled role-separated source review'}});assert.equal(hidden.status,403);
 const reveal=await s.f.call(`/api/admin/momo/sources/${raw}/content`,{method:'GET',cookie:s.owner.cookie,headers:{'X-Collect-Review-Reason':'Review retained candidate before correcting extraction'}});assert.equal(reveal.status,200);assert.equal(reveal.body.raw_body,synthetic.body);assert.equal(JSON.parse(reveal.body.latest_attempt.output_json).principal_amount_raw,'9,999');
 const body=await s.reviewBody(raw),key=randomUUID(),calls=s.aiCalls(),review=await action(s,`sources/${raw}/correct-extraction`,body,key);assert.equal(review.status,200,JSON.stringify(review));assert.equal(review.body.financial_effects,0);assert.equal(review.body.status,'review_recorded');assert.equal(s.aiCalls(),calls,'Explicit operator correction must not invoke an AI provider');
 assert.deepEqual((await action(s,`sources/${raw}/correct-extraction`,body,key)).body,review.body);
 assert.equal((await action(s,`sources/${raw}/correct-extraction`,{...body,reason:body.reason+' changed'},key)).status,409,'The original request key cannot adopt different review content');
 const attempts=(await s.f.db.prepare('SELECT * FROM momo_parse_attempts WHERE raw_sms_id=? ORDER BY attempt_number').bind(raw).all()).results;assert.equal(attempts.length,2);assert.deepEqual(attempts[0],before[0]);assert.equal(attempts[1].model_id,'operator_review');assert.equal(attempts[1].prompt_version,'operator-evidence.v1');assert.equal(attempts[1].outcome,'accepted');
 assert.equal(JSON.parse(attempts[1].validation_json)[0].actor_user_id,s.owner.account.userId);assert.equal((await s.job(raw)).state,'completed');assert.equal((await s.f.db.prepare('SELECT amount_minor FROM momo_transactions').first()).amount_minor,5000);
 assert.equal((await action(s,`sources/${raw}/correct-extraction`,await s.reviewBody(raw))).status,409,'An accepted canonical source cannot be rewritten');
 const receipts=JSON.stringify((await s.f.db.prepare("SELECT response_json FROM request_receipts WHERE operation='momo.source.corrected'").all()).results),audit=JSON.stringify((await s.f.db.prepare("SELECT details_json FROM audit_log WHERE action='momo.source.corrected'").all()).results);
 assert.ok(!receipts.includes('extraction'));assert.ok(!receipts.includes(synthetic.body));assert.ok(!audit.includes(synthetic.body));assert.ok(!audit.includes('principal_amount_raw'));
 await s.noMoney();
});

test('human non-payment classification requires source-supported direction/status and cannot close real incoming, incomplete or unapproved sources',async t=>{
 const s=await setup(t);
 for(const [kind,excerpt] of [['outgoing','You have sent RWF 5,000.'],['failed','The requested payment failed.'],['pending','Your withdrawal is pending.']]){
  const raw=await s.capture({body:excerpt});s.setOutput(negative('unknown',null));assert.equal((await s.process(raw)).state,'needs_review');const body={...await s.reviewBody(raw,negative(kind,excerpt)),classification_evidence:excerpt};
  const result=await action(s,`sources/${raw}/classify-non-payment`,body);assert.equal(result.status,200,JSON.stringify(result));assert.equal((await s.job(raw)).state,'completed');assert.equal((await s.f.db.prepare('SELECT outcome FROM momo_parse_attempts WHERE id=?').bind(result.body.parse_attempt_id).first()).outcome,'non_payment');
 }
 for(const change of [output=>{output.event_kind='other';},output=>{output.payment_outcome='unknown';}]){
  const raw=await s.capture(),output=copy(synthetic.output);change(output);s.setOutput(output);assert.equal((await s.process(raw)).state,'needs_review');
  assert.equal((await s.f.db.prepare('SELECT outcome FROM momo_parse_attempts WHERE raw_sms_id=?').bind(raw).first()).outcome,'needs_review');
 }
 const incoming=await s.exception({body:synthetic.body+' Payment failed.'}),fake={...await s.reviewBody(incoming,negative('failed','Payment failed.')),classification_evidence:'Payment failed.'};assert.equal((await action(s,`sources/${incoming}/classify-non-payment`,fake)).status,400);assert.equal((await s.job(incoming)).state,'needs_review');
 const incomplete=await s.exception({complete:false});assert.equal((await action(s,`sources/${incomplete}/correct-extraction`,await s.reviewBody(incomplete))).status,400);
 const wrongSender=await s.exception({sender:'UNREVIEWED'});assert.equal((await action(s,`sources/${wrongSender}/correct-extraction`,await s.reviewBody(wrongSender))).status,400);
 const unapproved=await s.exception();await s.f.db.prepare("UPDATE momo_receiving_accounts SET profile_status='unverified' WHERE id=?").bind(s.accountId).run();assert.equal((await action(s,`sources/${unapproved}/correct-extraction`,await s.reviewBody(unapproved))).status,409);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_transactions').first()).n,0);await s.noMoney();
});

test('source review rechecks attempt state and live extraction permission at commit without retaining partial results',async t=>{
 const s=await setup(t),raw=await s.exception(),body=await s.reviewBody(raw),attempts=(await s.f.db.prepare('SELECT count(*) AS n FROM momo_parse_attempts').first()).n;
 assert.equal((await action(s,`sources/${raw}/correct-extraction`,{...body,expected_body_sha256:'a'.repeat(64)})).status,409);
 assert.equal((await action(s,`sources/${raw}/correct-extraction`,{...body,expected_attempt_count:body.expected_attempt_count+1})).status,409);
 s.f.setGate(async()=>{const reparse=await action(s,`sources/${raw}/reparse`,{reason:'Concurrent deliberate source reparse claims the current work'});assert.equal(reparse.status,200,JSON.stringify(reparse));});
 const stale=await action(s,`sources/${raw}/correct-extraction`,body,randomUUID(),{'X-Test-Pause':'before_commit'});assert.equal(stale.status,409,JSON.stringify(stale));assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_parse_attempts').first()).n,attempts);
 await s.f.db.prepare("UPDATE momo_processing_jobs SET state='needs_review' WHERE raw_sms_id=?").bind(raw).run();
 s.f.setGate(async()=>s.f.db.prepare("UPDATE momo_receiving_accounts SET profile_version='changed-profile' WHERE id=?").bind(s.accountId).run());
 const changed=await action(s,`sources/${raw}/correct-extraction`,body,randomUUID(),{'X-Test-Pause':'before_commit'});assert.equal(changed.status,409,JSON.stringify(changed));
 await s.f.db.prepare("UPDATE momo_receiving_accounts SET profile_version='synthetic.v1' WHERE id=?").bind(s.accountId).run();
 s.f.setGate(async()=>s.f.db.prepare("UPDATE momo_receiving_accounts SET status='suspended' WHERE id=?").bind(s.accountId).run());
 const suspended=await action(s,`sources/${raw}/correct-extraction`,body,randomUUID(),{'X-Test-Pause':'before_commit'});assert.equal(suspended.status,409,JSON.stringify(suspended));
 await s.f.db.prepare("UPDATE momo_receiving_accounts SET status='active' WHERE id=?").bind(s.accountId).run();
 s.f.setGate(async()=>s.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='sms.read'").bind(s.owner.account.userId).run());
 const hidden=await action(s,`sources/${raw}/correct-extraction`,body,randomUUID(),{'X-Test-Pause':'before_commit'});assert.ok([403,409].includes(hidden.status),JSON.stringify(hidden));
 await s.f.db.prepare("INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,'sms.read','controlled-test-reinstatement',?)").bind(s.owner.account.userId,date()).run();
 s.f.setGate(async()=>s.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='sms.extract'").bind(s.owner.account.userId).run());
 const denied=await action(s,`sources/${raw}/correct-extraction`,body,randomUUID(),{'X-Test-Pause':'before_commit'});assert.ok([403,409].includes(denied.status),JSON.stringify(denied));assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_parse_attempts').first()).n,attempts);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_transactions').first()).n,0);await s.noMoney();
});

test('admin-account revocation winning before operator review commit releases no new attempt or canonical receipt',async t=>{
 const s=await setup(t),raw=await s.exception(),body=await s.reviewBody(raw);
 s.f.setGate(async()=>s.f.db.prepare("UPDATE admin_users SET status='revoked' WHERE id=?").bind(s.owner.account.adminId).run());
 const denied=await action(s,`sources/${raw}/correct-extraction`,body,randomUUID(),{'X-Test-Pause':'before_commit'});assert.ok([401,403,409].includes(denied.status),JSON.stringify(denied));
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_parse_attempts').first()).n,1);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_transactions').first()).n,0);await s.noMoney();
});

async function addConflict(s,amount){const raw=await s.capture({body:synthetic.body.replace('5,000',amount)});s.setOutput(amountOutput(amount));assert.equal((await s.process(raw)).state,'needs_review');return raw;}
async function conflictBody(s,txId){const detail=await s.f.call('/api/admin/momo/transactions/'+txId,{method:'GET',cookie:s.owner.cookie});assert.equal(detail.status,200);return {expected_version:detail.body.transaction.version,expected_conflicting_attempt_ids:detail.body.conflicting_attempt_ids,decision:'retain_original',
 evidence_reference:'Controlled independent source comparison and original provider identity',reason:'Retain original exact facts after reviewing every conflicting extraction'};}

test('conflict review retains original immutable facts and every source, requires exact set/version, and a later conflict reflags',async t=>{
 const s=await setup(t),accepted=await s.capture();assert.equal((await s.process(accepted)).state,'completed');const original=await s.f.db.prepare('SELECT * FROM momo_transactions').first(),txId=original.id;
 await addConflict(s,'6,000');const body=await conflictBody(s,txId),key=randomUUID(),review=await action(s,`transactions/${txId}/review-conflict`,body,key);assert.equal(review.status,200,JSON.stringify(review));assert.equal(review.body.financial_effects,0);
 const cleared=await s.f.db.prepare('SELECT * FROM momo_transactions WHERE id=?').bind(txId).first();assert.equal(cleared.has_conflict,0);assert.equal(cleared.allocation_state,'unallocated');for(const field of ['amount_minor','provider_transaction_id','receiving_account_id','parse_attempt_id','created_at'])assert.equal(cleared[field],original[field]);
 assert.deepEqual((await action(s,`transactions/${txId}/review-conflict`,body,key)).body,review.body);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_parse_attempts').first()).n,2);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_transaction_sources').first()).n,2);
 await addConflict(s,'7,000');const current=await conflictBody(s,txId);assert.equal(current.expected_conflicting_attempt_ids.length,2);assert.equal((await s.f.db.prepare('SELECT has_conflict FROM momo_transactions').first()).has_conflict,1);
 assert.equal((await action(s,`transactions/${txId}/review-conflict`,{...current,expected_conflicting_attempt_ids:current.expected_conflicting_attempt_ids.slice(0,1)})).status,409);
 s.f.setGate(async()=>addConflict(s,'8,000'));
 const raced=await action(s,`transactions/${txId}/review-conflict`,current,randomUUID(),{'X-Test-Pause':'before_commit'});assert.equal(raced.status,409,JSON.stringify(raced));assert.equal((await s.f.db.prepare('SELECT has_conflict FROM momo_transactions').first()).has_conflict,1);assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='momo.conflict.reviewed'").first()).n,1);await s.noMoney();
});

test('financially linked canonical conflicts cannot be dismissed through source or conflict review',async t=>{
 const s=await setup(t),raw=await s.capture();const accepted=await s.process(raw),member=await s.f.seedMember();
 const group=await s.f.operation('groups',s.owner.cookie,{title:'Linked conflict destination',slug:'linked-conflict-destination',collection_type:'ikimina',owner_user_id:member.id,receiver:{label:'Controlled receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create controlled linked financial destination'});assert.equal(group.status,200);
 const assigned=await action(s,`transactions/${accepted.transaction_id}/assign`,{group_id:group.body.resource_id,member_id:member.id,expected_version:1,reason:'Retain destination before independent financial review'});assert.equal(assigned.status,200,JSON.stringify(assigned));
 const conflictRaw=await addConflict(s,'6,000'),body=await conflictBody(s,accepted.transaction_id);
 assert.equal((await action(s,`transactions/${accepted.transaction_id}/review-conflict`,body)).status,409);
 assert.equal((await action(s,`sources/${conflictRaw}/correct-extraction`,await s.reviewBody(conflictRaw,amountOutput('6,000')))).status,409);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM payments').first()).n,1);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM notification_events').first()).n,0);
});
