import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {encrypt} from '../src/encryption.js';
import {processingInsert,validateMomoExtraction,exactMinor} from '../src/momo_pipeline.js';
const require=createRequire(import.meta.url),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??'miniflare');
const {build}=await import(process.env.COLLECT_ESBUILD_MODULE??'esbuild');
const root=new URL('../',import.meta.url),synthetic=JSON.parse(await readFile(new URL('fixtures/momo-synthetic.json',import.meta.url),'utf8'));
const hash=v=>createHash('sha256').update(v).digest('hex'),copy=v=>structuredClone(v),stamp=()=>new Date().toISOString();
const secrets={DATA_KEY_ID:'momo-fixture-only',DATA_ENCRYPTION_KEY:Buffer.alloc(32,7).toString('base64')};
let bundle;
async function fixture(t){
 bundle??=(await build({stdin:{resolveDir:fileURLToPath(root),contents:`
  import {processMomoJob,drainMomoJobs} from './src/momo_pipeline.js';
  export default {async fetch(request,env){
   const command=await request.json(),current={...env,AI:{run:async(model,args)=>{const response=await env.TEST_AI.fetch('https://ai.test',{method:'POST',body:JSON.stringify({model,args})});if(!response.ok)throw new Error('controlled_model_failure');return response.json();}}};
   return Response.json(command.drain?await drainMomoJobs(current,{limit:command.limit??5}):await processMomoJob(current,command.id));
  }};`},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022'})).outputFiles[0].text;
 let model=()=>({response:copy(synthetic.output)}),calls=0;
 const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script:bundle,compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,r2Buckets:{PRIVATE_MEDIA:randomUUID()},r2Persist:false,bindings:secrets,
 serviceBindings:{TEST_AI:async request=>{calls++;const input=await request.json();assert.equal(input.model,'@cf/meta/llama-3.3-70b-instruct-fp8-fast');assert.equal(input.args.response_format.type,'json_schema');assert.ok(!Object.hasOwn(input.args,'tools'));const result=await model(input);return result instanceof Response?result:Response.json(result);}}}));
 t.after(()=>mf.dispose());const db=await mf.getD1Database('DB'),bucket=await mf.getR2Bucket('PRIVATE_MEDIA');
 for(const name of(await readdir(new URL('migrations/',root))).filter(n=>/^\d+.*\.sql$/.test(n)&&Number(n.slice(0,4))<=14).sort())await db.batch(unstable_splitSqlQuery(await readFile(new URL('migrations/'+name,root),'utf8')).map(sql=>db.prepare(sql)));
 const owner=randomUUID(),session=randomUUID(),account=randomUUID(),binding=randomUUID(),receiverHash=hash('+250788123456'),at=stamp(),sec=Math.floor(Date.now()/1000);
 await db.prepare('INSERT INTO users(id,phone,public_id,created_at,updated_at) VALUES(?,?,?,?,?)').bind(owner,'+250788123456','991122',at,at).run();
 await db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(session,owner,sec,sec,sec+3600).run();
 await db.prepare("INSERT INTO momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,profile_status,profile_version,profile_json,created_at) VALUES(?,'mtn_momo','123456','Synthetic Collect Receiver',?,'RWF','Africa/Kigali','approved','synthetic.v1',?,?)").bind(account,receiverHash,JSON.stringify(synthetic.profile),at).run();
 await db.prepare('INSERT INTO momo_gateway_bindings(id,owner_user_id,receiving_account_id,created_at) VALUES(?,?,?,?)').bind(binding,owner,account,at).run();
 const f={mf,db,bucket,owner,session,account,binding,receiverHash,calls:()=>calls,setModel:value=>{model=value;}};
 f.capture=async({body=synthetic.body,sender=synthetic.sender,mode='live',enrolled=true,completeness='complete',bindingId=binding,bindingVersion=1}={})=>{
  const rawId=randomUUID(),bytes=new TextEncoder().encode(JSON.stringify({raw_body:body,raw_sender:sender,completeness})),sha=hash(bytes),key='sms/'+rawId;
  await bucket.put(key,await encrypt(secrets,bytes,`sms:${rawId}:${sha}`));
  const raw=db.prepare('INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)').bind(rawId,owner,session,randomUUID(),hash(body),receiverHash,key,sha,bytes.length,stamp());
  await db.batch([raw,processingInsert({DB:db},rawId,{bindingId:enrolled?bindingId:null,bindingVersion:enrolled?bindingVersion:null,mode})]);return rawId;
 };
 f.process=async id=>{const response=await mf.dispatchFetch('https://pipeline.test',{method:'POST',body:JSON.stringify({id})});assert.equal(response.status,200,await response.clone().text());return response.json();};
 f.drain=async()=>{const response=await mf.dispatchFetch('https://pipeline.test',{method:'POST',body:JSON.stringify({drain:true})});assert.equal(response.status,200,await response.clone().text());return response.json();};
 f.count=async table=>(await db.prepare('SELECT count(*) AS n FROM '+table).first()).n;
 return f;
}

test('synthetic enrolled receipt extracts exact facts once without financial effects',async t=>{
 const f=await fixture(t),raw=await f.capture(),result=await f.process(raw);assert.equal(result.state,'completed');assert.equal(result.relation,'accepted');
 const transaction=await f.db.prepare('SELECT * FROM momo_transactions').first();assert.equal(transaction.amount_minor,5000);assert.equal(transaction.wallet_balance_after_minor,125000);assert.equal(transaction.fee_minor,0);
 assert.equal(transaction.provider_transaction_id,'001234567890');assert.equal(transaction.payer_last3,'007');assert.equal(transaction.transaction_at,'2026-10-18T08:15:00.000Z');assert.equal(transaction.allocation_state,'unallocated');
 assert.equal((await f.process(raw)).state,'not_claimed');assert.equal(f.calls(),1);assert.equal(await f.count('momo_parse_attempts'),1);
 for(const table of ['payments','ledger_entries','notification_events'])assert.equal(await f.count(table),0);
});

test('simultaneous job claims and duplicate sources preserve one economic receipt',async t=>{
 const f=await fixture(t),a=await f.capture(),b=await f.capture();const results=await Promise.all([f.process(a),f.process(a),f.process(b)]);
 assert.equal(results.filter(v=>v.state==='not_claimed').length,1);assert.equal(await f.count('momo_transactions'),1);assert.equal(await f.count('momo_transaction_sources'),2);assert.equal(await f.count('momo_parse_attempts'),2);
 assert.deepEqual((await f.db.prepare('SELECT outcome FROM momo_parse_attempts ORDER BY outcome').all()).results.map(v=>v.outcome),['accepted','duplicate']);
 assert.equal(await f.count('ledger_entries'),0);
});

test('same provider identity with conflicting principal preserves original and opens review',async t=>{
 const f=await fixture(t),a=await f.capture();await f.process(a);
 const b=await f.capture({body:synthetic.body.replace('5,000','6,000')});f.setModel(()=>{const output=copy(synthetic.output);output.principal_amount_raw='6,000';output.evidence.principal='RWF 6,000';output.evidence.incoming_success='You have received RWF 6,000';return {response:output};});
 assert.equal((await f.process(b)).state,'needs_review');const tx=await f.db.prepare('SELECT * FROM momo_transactions').first();assert.equal(tx.amount_minor,5000);assert.equal(tx.has_conflict,1);assert.equal(tx.allocation_state,'needs_review');
 assert.equal((await f.db.prepare("SELECT outcome FROM momo_parse_attempts WHERE raw_sms_id=?").bind(b).first()).outcome,'conflict');
 await assert.rejects(f.db.prepare('UPDATE momo_transactions SET amount_minor=1').run(),/immutable/);await assert.rejects(f.db.prepare('DELETE FROM momo_parse_attempts').run(),/retain/);
});

test('ordinary capture, incomplete source and unverified profile never become financial facts',async t=>{
 const f=await fixture(t),ordinary=await f.capture({enrolled:false});assert.equal((await f.process(ordinary)).state,'not_claimed');assert.equal((await f.db.prepare('SELECT state FROM momo_processing_jobs WHERE raw_sms_id=?').bind(ordinary).first()).state,'source_unresolved');
 const incomplete=await f.capture({completeness:'incomplete'});assert.equal((await f.process(incomplete)).state,'needs_review');assert.equal(f.calls(),0);
 await f.db.prepare("UPDATE momo_receiving_accounts SET profile_status='unverified'").run();const raw=await f.capture();assert.equal((await f.process(raw)).state,'needs_review');assert.equal(f.calls(),0);assert.equal(await f.count('momo_transactions'),0);
});

test('binding revision, owner, receiver and revoked source are checked inside raw/job batch',async t=>{
 const f=await fixture(t);await assert.rejects(f.capture({bindingVersion:2}),/gateway_binding_changed/);assert.equal(await f.count('sms_receipts'),0);
 await f.db.prepare("UPDATE momo_gateway_bindings SET status='revoked',revoked_at=? WHERE id=?").bind(stamp(),f.binding).run();await assert.rejects(f.capture(),/gateway_binding_changed/);assert.equal(await f.count('sms_receipts'),0);
});

test('model errors retry within budget and recovery handles expired claims',async t=>{
 const f=await fixture(t),raw=await f.capture();f.setModel(()=>new Response('controlled timeout',{status:503}));
 for(let n=1;n<=4;n++){await f.db.prepare('UPDATE momo_processing_jobs SET available_at=0 WHERE raw_sms_id=?').bind(raw).run();assert.equal((await f.process(raw)).state,n<4?'retry':'needs_review');}
 assert.equal(f.calls(),4);assert.equal(await f.count('momo_parse_attempts'),4);assert.equal((await f.process(raw)).state,'not_claimed');assert.equal(await f.count('momo_transactions'),0);
 const b=await f.capture();await f.db.prepare("UPDATE momo_processing_jobs SET state='processing',lease_token='dead-worker',lease_until=0,attempt_count=1 WHERE raw_sms_id=?").bind(b).run();f.setModel(()=>({response:synthetic.output}));assert.equal((await f.drain()).processed,1);assert.equal(await f.count('momo_transactions'),1);
});

test('historical replay links receipt without credit or stale notification',async t=>{
 const f=await fixture(t),a=await f.capture({mode:'historical'}),b=await f.capture();await f.process(a);await f.process(b);
 assert.equal(await f.count('momo_transactions'),1);assert.equal((await f.db.prepare('SELECT mode FROM momo_transactions').first()).mode,'historical');assert.equal(await f.count('ledger_entries'),0);assert.equal(await f.count('notification_events'),0);
});

test('source and profile changes during inference cannot commit unchecked facts',async t=>{
 const f=await fixture(t),raw=await f.capture();f.setModel(async()=>{await f.db.prepare("UPDATE momo_receiving_accounts SET profile_version='changed.v2'").run();return {response:synthetic.output};});
 assert.equal((await f.process(raw)).state,'superseded');assert.equal(await f.count('momo_transactions'),0);assert.equal(await f.count('momo_parse_attempts'),0);
});

test('independent validation rejects hallucinations, field-role swaps, injection and unsupported amount formats',()=>{
 const account={status:'active',profile_status:'approved',profile_version:'synthetic.v1',profile_json:JSON.stringify(synthetic.profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'},source={raw_sender:synthetic.sender,raw_body:synthetic.body,completeness:'complete'};
 assert.equal(validateMomoExtraction(copy(synthetic.output),source,account).accepted,true);
 for(const change of [o=>{o.principal_amount_raw='125,000';o.evidence.principal='Balance: RWF 125,000';},o=>{o.transaction_id_raw='5000';},o=>{o.member_id='invented';},o=>{o.payer_name_raw='invented';},o=>{o.transaction_datetime_raw='30/02/2026 10:15:00';},o=>{o.currency_raw='USD';}]){const output=copy(synthetic.output);change(output);assert.equal(validateMomoExtraction(output,source,account).accepted,false);}
 assert.equal(validateMomoExtraction(copy(synthetic.output),{...source,raw_body:'Payment reversed. '+synthetic.body},account).accepted,false);
 assert.equal(validateMomoExtraction(copy(synthetic.output),{...source,raw_sender:'SPOOFED'},account).accepted,false);
 for(const raw of ['5.0','5e3','-1','01','9,00','9007199254740992','5,000.00'])assert.equal(exactMinor(raw),null,raw);
 assert.equal(exactMinor('5,000'),5000);
});
