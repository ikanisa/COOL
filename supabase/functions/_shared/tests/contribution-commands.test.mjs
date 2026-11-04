import {test,afterEach} from 'node:test';
import assert from 'node:assert/strict';
await import('./helpers/node-postgres-import.mjs');
const {contributionCommandRpc}=await import('../domain/contribution_commands.js');
const {contributionIntentJson,financialRpc,normalizeContributionSender}=await import('../domain/payments.js');
const {digest,stableJson}=await import('../domain/core.js');
const {PostgresDatabase}=await import('../postgres.js');
import {syntheticFixtureWork,finishFixtureWork} from './helpers/fenced-unit.js';

// Handler/parser/cleanup unit tests only. The actual adapter readContext and SQL
// compiler run against a controlled connection. PostgreSQL/HTTP authorization,
// locks and provider behavior require the separate native integration proof.
const user='10000000-0000-4000-8000-000000000001';
const auth='20000000-0000-4000-8000-000000000001';
const session='30000000-0000-4000-8000-000000000001';
const previousSession='30000000-0000-4000-8000-000000000002';
const collection='40000000-0000-4000-8000-000000000001';
const request='50000000-0000-4000-8000-000000000001';
const intent='60000000-0000-4000-8000-000000000001';
// This isolated handler fixture does not need a live managed-project origin.
const issuer='https://synthetic-project.example.invalid';
const senderHash=await digest('+250788123491');
const original={collection,p_expected_amount_rwf:500,p_sender_phone_hash:senderHash,p_request_id:request};
const lookup=(body={})=>({p_contract_version:1,p_original_request_id:request,p_original_session_id:session,p_collection_id:collection,p_original_body:original,...body});
const review=(body={})=>({p_contract_version:1,p_intent_id:intent,p_collection_id:collection,...body});
afterEach(finishFixtureWork);

function fixture(options={}){
 const now=Math.floor(Date.now()/1000),work=syntheticFixtureWork(),calls=[],released=[];
 const claims={sub:auth,session_id:session,role:'authenticated',aal:'aal1',aud:'authenticated',exp:now+900,iss:issuer+'/auth/v1'};
 const actor={userId:user,sessionId:session,surface:'member',user:{auth_user_id:auth}};
 let row={authority_user_id:user,authority_session_id:session,surface:'member',authority_expires_at:now+900,managed_expires_at:now+900,admin_expires_at:null,
  observed_at:new Date(),receipt_request_id:request,id:intent,collection_id:collection,member_id:user,amount_minor:500,currency:'RWF',rail:'rwanda_momo',status:'pending',
  receiver_momo_number:'250788123492',receiver_network:'mtn_momo',receiver_label:'Original receiver',originating_session_id:session,created_at:new Date().toISOString(),expires_at:new Date(Date.now()+600000).toISOString(),
  group_status:'active',collection_revision:1,current_receiver_number:'250788123492',current_receiver_network:'mtn_momo',current_receiver_label:'Original receiver',membership_active:1,profile_momo_number:'+250788123491',profile_country_code:'RW',linked_payment_exists:false,...options.row};
 row.response_json=options.response??JSON.stringify(contributionIntentJson({...row,status:'pending',sender_phone_hash:senderHash}));
 row.creation_response_json=options.creationResponse??JSON.stringify(contributionIntentJson({...row,status:'pending',sender_phone_hash:senderHash}));
 const tx=async(strings,...values)=>{calls.push({text:String.raw({raw:strings},...values.map(()=>'?')),values});return [];};
 tx.unsafe=async(text,values=[])=>{
  calls.push({text,values});
  if(text==='SHOW transaction_read_only')return [{transaction_read_only:options.readOnly??'on'}];
  if(text==='SHOW transaction_isolation')return [{transaction_isolation:options.isolation??'read committed'}];
  if(text==='COMMIT'&&options.commitFailure)throw Error('SYNTHETIC_PRIVATE_COMMIT_DETAIL');
  if(text==='ROLLBACK'&&options.rollbackFailure)throw Error('SYNTHETIC_PRIVATE_ROLLBACK_DETAIL');
  if(text.startsWith('WITH authority')){
   await options.beforeReturn?.({claims,actor,row});
   if(options.queryFailure)throw Error('SYNTHETIC_PRIVATE_QUERY_DETAIL');
   return options.noRow?[]:[row];
  }
  return [];
 };
 tx.release=()=>{released.push(true);if(options.releaseFailure)throw Error('SYNTHETIC_PRIVATE_RELEASE_DETAIL');};
 const sql={async reserve(){if(options.reserveFailure)throw Error('SYNTHETIC_PRIVATE_RESERVE_DETAIL');return tx;}};
 const db=new PostgresDatabase(sql,claims,work);
 const env={DB:db,COLLECT_FENCE_WORK:work,AUTH_ACTOR:actor,AUTH_VERIFIED:{claims,token:'synthetic-server-verified-token',user:{id:auth}},SUPABASE_URL:issuer};
 return {env,actor,claims,calls,released,row,tx};
}
const invoke=(f,name,input)=>contributionCommandRpc(name,input,f.env,f.actor);
const lookupName='get_current_member_contribution_command_v1',reviewName='review_current_member_contribution_intent_v1',sessionName='get_current_member_contribution_session_v1';
const denied=(status,code)=>error=>error.status===status&&error.code===code&&!String(error.message).includes('SYNTHETIC_PRIVATE');

function creationFixture({profile='+250788123491',pending=null,prior=null}={}){
 const actor={userId:user,sessionId:session},batches=[];
 const env={DB:{prepare(sql){return {bind(...values){return {sql,values,async first(){
  if(sql.includes('FROM collections c JOIN memberships'))return {id:collection,revision:1,receiver_momo_number:'250788123492',receiver_network:'mtn_momo',receiver_display_label:'Original receiver'};
  if(sql.startsWith('SELECT momo_number,country_code'))return {momo_number:profile,country_code:'RW'};
  if(sql.startsWith('SELECT * FROM request_receipts'))return prior;
  if(sql.startsWith('SELECT p.*,r.response_json AS creation_response_json'))return pending;
  throw Error('unexpected synthetic query');
 }};}};},async batch(statements){batches.push(statements);}}};
 return {env,actor,batches};
}
test('creation binds normalized live profile to its immutable response receipt',async()=>{
 const f=creationFixture({profile:'0788 123 491'}),{value}=await financialRpc('create_contribution_intent',original,f.env,f.actor);
 assert.equal(value.sender_phone_hash,senderHash);assert.equal(f.batches.length,1);
 const receipt=f.batches[0].find(s=>s.sql.startsWith('INSERT INTO request_receipts'));
 assert.equal(JSON.parse(receipt.values[5]).sender_phone_hash,senderHash);
});
test('creation rejects absent, malformed and mismatched sender hashes without mutation',async()=>{
 for(const supplied of [undefined,'x'.repeat(64),'a'.repeat(64)]){
  const f=creationFixture();await assert.rejects(()=>financialRpc('create_contribution_intent',{...original,p_sender_phone_hash:supplied},f.env,f.actor),denied(409,'contribution_sender_changed'));assert.equal(f.batches.length,0);
 }
});
test('creation refuses pending intents lacking the immutable sender binding',async()=>{
 const pending={id:intent,collection_id:collection,amount_minor:500,currency:'RWF',rail:'rwanda_momo',status:'pending',receiver_momo_number:'250788123492',receiver_network:'mtn_momo',receiver_label:'Original receiver',originating_session_id:session,created_at:'2026-01-01T00:00:00.000Z',expires_at:'2099-01-01T00:00:00.000Z',creation_response_json:null};
 for(const receipt of [null,JSON.stringify(contributionIntentJson({...pending,sender_phone_hash:''}))]){
  const f=creationFixture({pending:{...pending,creation_response_json:receipt}});await assert.rejects(()=>financialRpc('create_contribution_intent',original,f.env,f.actor),denied(409,'contribution_sender_changed'));assert.equal(f.batches.length,0);
 }
});
test('creation reuses a pending intent only when its original receipt binds the current sender',async()=>{
 const pending={id:intent,collection_id:collection,amount_minor:500,currency:'RWF',rail:'rwanda_momo',status:'pending',receiver_momo_number:'250788123492',receiver_network:'mtn_momo',receiver_label:'Original receiver',originating_session_id:session,created_at:'2026-01-01T00:00:00.000Z',expires_at:'2099-01-01T00:00:00.000Z'};
 pending.creation_response_json=JSON.stringify(contributionIntentJson({...pending,sender_phone_hash:senderHash}));
 const f=creationFixture({pending}),result=await financialRpc('create_contribution_intent',original,f.env,f.actor);
 assert.equal(result.value.id,intent);assert.equal(result.value.sender_phone_hash,senderHash);
 assert.equal(f.batches.length,1);assert.equal(f.batches[0].some(s=>s.sql.startsWith('INSERT INTO payment_intents')),false);
});
test('idempotent creation replay rejects an old receipt without the current sender binding',async()=>{
 const prior={operation:'create_contribution_intent',session_id:session,body_sha256:await digest(stableJson(original)),response_json:JSON.stringify({id:intent,sender_phone_hash:''})};
 const f=creationFixture({prior});await assert.rejects(()=>financialRpc('create_contribution_intent',original,f.env,f.actor),denied(409,'contribution_sender_changed'));
 assert.equal(f.batches.length,1);assert.equal(f.batches[0].some(s=>s.sql.startsWith('INSERT INTO payment_intents')),false);
});
test('sender normalization mirrors Rwanda client cases and rejects malformed numbers',()=>{
 for(const input of ['+250788123491','00250 788 123 491','0788-123-491','788123491'])assert.equal(normalizeContributionSender(input),'+250788123491');
 for(const input of ['',null,'+25078812349','+250788+123491','0719123491','+254788123491'])assert.equal(normalizeContributionSender(input),null);
});

test('unknown operation is not handled and never reads SQL',async()=>{
 const f=fixture();assert.deepEqual(await invoke(f,'unregistered',{}),{handled:false});assert.equal(f.calls.length,0);
});
for(const [name,input]of [
 ['extra envelope field',lookup({extra:true})],['wrong version',lookup({p_contract_version:2})],
 ['different original key',lookup({p_original_request_id:intent})],['different group',lookup({p_collection_id:intent})],
 ['different field shape',lookup({p_original_body:{...original,amount_minor:500}})],
 ['noncanonical UUID',lookup({p_original_session_id:session.toUpperCase().replace('0001','000A')})],
 ['noninteger amount',lookup({p_original_body:{...original,p_expected_amount_rwf:1.5}})],
 ['unsafe amount',lookup({p_original_body:{...original,p_expected_amount_rwf:Number.MAX_SAFE_INTEGER+1}})],
 ['invalid sender hash',lookup({p_original_body:{...original,p_sender_phone_hash:'x'.repeat(64)}})],
])test(`lookup rejects ${name} before SQL`,async()=>{
 const f=fixture();await assert.rejects(()=>invoke(f,lookupName,input),denied(400,'invalid_contribution_command_query'));assert.equal(f.calls.length,0);
});
test('accessor body fields are refused without invoking the accessor',async()=>{
 const f=fixture(),body=lookup();let called=false;Object.defineProperty(body,'p_original_body',{enumerable:true,get(){called=true;return original;}});
 await assert.rejects(()=>invoke(f,lookupName,body),denied(400,'invalid_contribution_command_query'));assert.equal(called,false);assert.equal(f.calls.length,0);
});
test('review rejects extra and malformed fields before SQL',async()=>{
 for(const input of [review({extra:true}),review({p_intent_id:'not-an-id'}),review({p_contract_version:'1'})]){
  const f=fixture();await assert.rejects(()=>invoke(f,reviewName,input),denied(400,'invalid_contribution_review_query'));assert.equal(f.calls.length,0);
 }
});
test('retained lookup returns current intent status and never launch or retry permission',async()=>{
 const f=fixture({row:{status:'cancelled'}}),{value}=await invoke(f,lookupName,lookup());
 assert.equal(value.command_status,'receipt_retained');assert.deepEqual(value.observed_intent,{id:intent,status:'cancelled'});
 assert.equal(value.body_sha256,await digest(stableJson(original)));assert.equal(value.external_payment,'unknown');assert.equal(value.launch_authorized,false);assert.equal(value.retry_authorized,false);
 assert.deepEqual(f.calls.filter(c=>c.text.startsWith('BEGIN')).map(c=>c.text),['BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY']);
 assert.equal(f.calls.filter(c=>c.text.startsWith('WITH authority')).length,1);assert.equal(f.calls.filter(c=>c.text==='COMMIT').length,1);assert.equal(f.released.length,1);
 assert.equal(f.calls.some(c=>/^\s*(INSERT|UPDATE|DELETE)\b/.test(c.text)),false);
});
test('lookup after current same-owner replacement session observes original session only',async()=>{
 const f=fixture({row:{originating_session_id:previousSession}}),{value}=await invoke(f,lookupName,lookup({p_original_session_id:previousSession}));
 assert.equal(value.original_session_id,previousSession);assert.equal(value.command_status,'receipt_retained');assert.equal(value.launch_authorized,false);assert.equal(value.retry_authorized,false);
 const query=f.calls.find(c=>c.text.startsWith('WITH authority'));assert.equal(query.values[1],session);assert.equal(query.values[10],previousSession);assert.equal(query.values[13],previousSession);
});
for(const [name,options]of [
 ['absent receipt',{row:{receipt_request_id:null}}],['malformed receipt',{response:'{"id":'}],
 ['ambiguous receipt encoding',{response:' '+JSON.stringify({id:intent})}],['unexpected stored intent status',{row:{status:'unsupported'}}],
 ['foreign intent snapshot',{row:{collection_id:intent}}],
])test(`${name} stays unknown without another command or payment authority`,async()=>{
 const f=fixture(options),{value}=await invoke(f,lookupName,lookup());assert.equal(value.command_status,'unknown');assert.equal(value.observed_intent,null);assert.equal(value.retry_authorized,false);assert.equal(value.launch_authorized,false);assert.equal(value.external_payment,'unknown');
});
for(const [name,change]of [
 ['missing verified actor',f=>{f.env.AUTH_ACTOR={};}],['different mapped Auth subject',f=>{f.actor.user.auth_user_id=intent;}],
 ['wrong project issuer',f=>{f.env.SUPABASE_URL='https://other.example';}],['wrong role',f=>{f.claims.role='service_role';}],
 ['expired token',f=>{f.claims.exp=0;}],['different current session',f=>{f.actor.sessionId=previousSession;}],
])test(`${name} cannot enter a snapshot`,async()=>{
 const f=fixture();change(f);await assert.rejects(()=>invoke(f,reviewName,review()),denied(403,'contribution_access_changed'));assert.equal(f.calls.length,0);
});
test('post-snapshot token expiry or actor replacement denies disclosure',async()=>{
 for(const beforeReturn of [({claims})=>{claims.exp=0;},({actor})=>{actor.sessionId=previousSession;}]){
  const f=fixture({beforeReturn});await assert.rejects(()=>invoke(f,reviewName,review()),denied(403,'contribution_access_changed'));assert.equal(f.released.length,1);
 }
});
test('SQL authority absence and app/managed/Admin deadline crossing fail closed',async()=>{
 for(const options of [{noRow:true},{row:{authority_expires_at:0}},{row:{managed_expires_at:0}},{row:{surface:'admin',admin_expires_at:0}}]){
  const f=fixture(options);if(options.row?.surface==='admin')f.actor.surface='admin';
  await assert.rejects(()=>invoke(f,lookupName,lookup()),denied(403,'contribution_access_changed'));
 }
});
test('valid current review uses the unchanged creation projection',async()=>{
 const f=fixture(),{value}=await invoke(f,reviewName,review());assert.equal(value.launch_authorized,true);assert.equal(value.retry_authorized,false);assert.equal(value.external_payment,'unknown');assert.equal(value.reviewed_session_id,session);assert.deepEqual(value.intent,contributionIntentJson({...f.row,sender_phone_hash:senderHash}));assert.equal(f.released.length,1);
});
test('review fails closed for linked or indeterminate payment state',async()=>{
 for(const linked_payment_exists of [true,null,undefined]){
  const f=fixture({row:{linked_payment_exists}});
  await assert.rejects(()=>invoke(f,reviewName,review()),denied(404,'contribution_intent_unavailable'));
  const query=f.calls.find(c=>c.text.startsWith('WITH authority')).text;
  assert.match(query,/EXISTS\s*\(SELECT 1 FROM payments linked_payment WHERE linked_payment\.intent_id=p\.id\)/);
 }
});
test('review accepts equivalent profile formats but rejects a changed sender',async()=>{
 for(const phone of ['0788 123 491','00250 788 123 491','788123491']){
  const f=fixture({row:{profile_momo_number:phone}});const {value}=await invoke(f,reviewName,review());assert.equal(value.intent.sender_phone_hash,senderHash);
 }
 const changed=fixture({row:{profile_momo_number:'+250788123490'}});
 await assert.rejects(()=>invoke(changed,reviewName,review()),denied(404,'contribution_intent_unavailable'));
});
test('review denies legacy or mismatched immutable creation receipts',async()=>{
 for(const receipt of [null,'{}',JSON.stringify({id:intent,sender_phone_hash:senderHash}),JSON.stringify(contributionIntentJson({...fixture().row,sender_phone_hash:''}))]){
  const f=fixture({creationResponse:receipt});
  if(receipt===null)f.row.creation_response_json=null;
  await assert.rejects(()=>invoke(f,reviewName,review()),denied(404,'contribution_intent_unavailable'));
 }
});
for(const [name,row]of [
 ['previous sign-in',{originating_session_id:previousSession}],['cancelled intent',{status:'cancelled'}],
 ['expired intent',{expires_at:'2000-01-01T00:00:00.000Z'}],['removed membership',{membership_active:0}],['suspended group',{group_status:'suspended'}],
 ['changed number',{current_receiver_number:'250788999999'}],['changed network',{current_receiver_network:'airtel_money'}],['changed label',{current_receiver_label:'Changed'}],
 ['unready profile',{profile_momo_number:''}],['other geography',{profile_country_code:'KE'}],['malformed amount',{amount_minor:1.5}],
 ['whitespace-only profile',{profile_momo_number:' '}],['malformed receiver',{receiver_momo_number:'not-a-route',current_receiver_number:'not-a-route'}],
 ['missing intent',{id:null}],['different owner',{member_id:intent}],
])test(`review refuses ${name} uniformly`,async()=>{
 const f=fixture({row});await assert.rejects(()=>invoke(f,reviewName,review()),denied(404,'contribution_intent_unavailable'));assert.equal(f.released.length,1);
});
for(const [name,options]of [
 ['read-write transaction',{readOnly:'off'}],['wrong isolation',{isolation:'repeatable read'}],
 ['query failure',{queryFailure:true}],['commit failure',{commitFailure:true}],
 ['rollback failure',{queryFailure:true,rollbackFailure:true}],['release failure',{releaseFailure:true}],['reservation failure',{reserveFailure:true}],
])test(`${name} never returns an allowed review or exposes raw diagnostics`,async()=>{
 const f=fixture(options);await assert.rejects(()=>invoke(f,reviewName,review()),denied(503,'contribution_status_unavailable'));
 if(options.rollbackFailure||options.reserveFailure)assert.equal(f.released.length,0);
 else assert.equal(f.released.length,1);
});
test('malformed observation timestamp is never fabricated',async()=>{
 const f=fixture({row:{observed_at:null}});await assert.rejects(()=>invoke(f,lookupName,lookup()),denied(503,'contribution_status_unavailable'));
});
test('typed session observation is current-owner/session only and grants no action',async()=>{
 const f=fixture({row:{managed_expires_at:Math.floor(Date.now()/1000)+300}}),{value}=await invoke(f,sessionName,{p_contract_version:1});
 assert.equal(value.binding_kind,'current_contribution_session');assert.equal(value.owner_id,user);assert.equal(value.auth_subject,auth);assert.equal(value.session_id,session);assert.equal(value.issuer,issuer+'/auth/v1');
 assert.equal(value.expires_at,f.row.managed_expires_at);assert.equal(value.retry_authorized,false);assert.equal(value.launch_authorized,false);assert.equal(JSON.stringify(value).includes('synthetic-server-verified-token'),false);
});
test('session query accepts exactly its supported version field',async()=>{
 for(const body of [{},{p_contract_version:2},{p_contract_version:1,p_owner_id:user}]){
  const f=fixture();await assert.rejects(()=>invoke(f,sessionName,body),denied(400,'invalid_contribution_session_query'));assert.equal(f.calls.length,0);
 }
});
test('readContext default remains read-only repeatable-read',async()=>{
 const f=fixture({isolation:'repeatable read'});await f.env.DB.readContext(f.tx);
 assert.equal(f.calls.find(c=>c.text==='SHOW transaction_read_only')!==undefined,true);assert.equal(f.calls.find(c=>c.text==='SHOW transaction_isolation')!==undefined,true);
});
test('readContext explicitly admits read-committed read-only and refuses an isolation mismatch',async()=>{
 const f=fixture();await f.env.DB.readContext(f.tx,{isolation:'read committed'});
 const wrong=fixture({isolation:'repeatable read'});await assert.rejects(()=>wrong.env.DB.readContext(wrong.tx,{isolation:'read committed'}));
});
test('readContext closed isolation modes cannot grant writes or accept another isolation',async()=>{
 for(const isolation of ['serializable','read uncommitted','READ COMMITTED','',null]){
  const f=fixture();await assert.rejects(()=>f.env.DB.readContext(f.tx,{isolation}));assert.equal(f.calls.length,0);
 }
 for(const isolation of ['repeatable read','read committed']){
  const f=fixture({readOnly:'off',isolation});await assert.rejects(()=>f.env.DB.readContext(f.tx,{isolation}));
 }
});
test('runtime inventory preserves creation and registers only three bearer-session contribution reads',async()=>{
 const {operationInventory}=await import('../domain/operations.js');assert.equal(operationInventory.length,103);
 assert.equal(operationInventory.find(entry=>entry.name==='create_contribution_intent').source,'payments.js');
 const added=operationInventory.filter(entry=>entry.source==='contribution_commands.js');assert.equal(added.length,3);
 assert.deepEqual(added.map(entry=>entry.name).sort(),[sessionName,lookupName,reviewName].sort());
 assert.equal(added.every(entry=>entry.authentication==='bearer_session'&&entry.method==='POST'),true);
});
