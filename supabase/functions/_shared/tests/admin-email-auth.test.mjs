import {test} from './helpers/fenced-node-test.js';
import {fixtureEnvironment} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {isAbsolute,join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Actual JS + intercepted HTTP + deliberately synthetic SQL state machine.
// No real signature, PostgreSQL authority, provider delivery or hosted proof.
const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root==='string'&&isAbsolute(root),'Use the coherent actual _shared source tree.');
const actual=name=>import(pathToFileURL(join(root,name)).href);
const {loadAdminEmailAccount,requestAdminEmail,verifyAdminEmail,recordInitialAdminEmail,handleAdminEmail,isAdminEmailDenialError}=await actual('domain/admin_email_auth.js');
const {attestAdminEmailAccount,bindAdminEmailActor,adminEmailState,requireFreshAdminEmail,requestedAdminEmail,hasFreshAdminEmail}=await actual('domain/admin_email_policy.js');
const {ApiError}=await actual('domain/core.js');
const NOW=1792497600,PROJECT='https://admin-email.synthetic.invalid',ORIGIN='https://admin-supabase-qa.collect.ikanisa.com';
const ADMIN='11111111-1111-4111-8111-111111111111',PRINCIPAL='22222222-2222-4222-8222-222222222222';
const AUTH='33333333-3333-4333-8333-333333333333',SID='44444444-4444-4444-8444-444444444444';
const CANDIDATE='55555555-5555-4555-8555-555555555555',PUBLIC='66666666-6666-4666-8666-666666666666';
const PROOF='77777777-7777-4777-8777-777777777777',INITIAL='88888888-8888-4888-8888-888888888888';
const EMAIL='synthetic.admin@example.invalid',KEY='sb_publishable_synthetic_admin_email',REFRESH='synthetic-private-refresh';
const DETAIL='synthetic-private-provider-or-SQL-detail',CODE='184275';
const clone=value=>structuredClone(value);
const claims=(sid,extra={})=>({sub:AUTH,session_id:sid,role:'authenticated',aud:'authenticated',aal:'aal1',iss:PROJECT+'/auth/v1',exp:NOW+3600,iat:NOW,amr:[{method:sid===SID?'password':'otp',timestamp:NOW}],...extra});
const jwt=value=>[Buffer.from('{"alg":"synthetic-only"}').toString('base64url'),Buffer.from(JSON.stringify(value)).toString('base64url'),'synthetic-signature'].join('.');
const baseUser=()=>({id:AUTH,email:EMAIL,email_confirmed_at:'2026-10-20T12:00:00Z'});
const isError=(status,code)=>error=>error instanceof ApiError&&error.status===status&&error.code===code;
const prefix='?::text,?::text,?::text,?::text';
const suffix={status:'',prepare:',?::text',send_claim:',?::text,?::uuid',send_finish:',?::text,?::uuid,?::text',verify_claim:',?::text,?::uuid',record:',?::text,?::uuid',verify_finish:',?::text,?::uuid,?::text',cleanup_claim:',?::text,?::uuid,?::uuid',cleanup_finish:',?::text,?::uuid,?::uuid,?::text',record_initial:',?::text'};
const queries=Object.fromEntries(Object.entries(suffix).map(([name,s])=>[`SELECT private.admin_email_${name}(${prefix}${s}) AS result`,name]));
class Statement{
 constructor(db,sql){this.db=db;this.sql=sql;this.args=[];}
 bind(...args){this.args=args;return this;}
 first(){return this.db.first(this.sql,this.args);}
}
class Database{
 constructor(options={}){this.options=options;this.claims={};this.calls=[];this.violations=[];this.c=null;this.proof=null;this.candidatePresent=true;this.attempts=0;}
 prepare(sql){assert.ok(queries[sql],'Only the closed Admin email protocol helpers are used');return new Statement(this,sql);}
 setClaims(value){this.claims=clone(value);}
 result(extra={}){return {result:{challenge:clone(this.c),...extra}};}
 async first(sql,args){
  const name=queries[sql];this.calls.push({name,args:clone(args),claims:clone(this.claims)});
  this.options.trace?.push('db:'+name);
  assert.deepEqual(args.slice(0,4),[ADMIN,'a'.repeat(64),ORIGIN,PUBLIC]);
  if(this.options.denied||this.options.failBefore===name)throw new Error(this.options.failureMessage??'admin_email_denied '+DETAIL);
  if(name==='status')return {result:{contract_version:1,public_session_id:PUBLIC,email_verified_at:this.proof?.at??null,proof_id:this.proof?.id??null}};
  if(name==='prepare'){
   this.c={id:args[4],identity_value:EMAIL,created_at:this.options.createdAt??NOW,expires_at:(this.options.createdAt??NOW)+300,delivery_status:'reserved',verification_state:'not_started',cleanup_state:'not_started',original_auth_user_id:AUTH,original_session_id:SID,principal_id:PRINCIPAL,verified_session_id:null,verified_amr_at:null};
   return this.result({created:true});
  }
  if(name==='record_initial'){
   assert.equal(args[4],INITIAL);assert.equal(this.claims.session_id,SID);
   const entry=this.claims.amr?.find(x=>x.method==='otp'&&x.timestamp===NOW);
   if(!entry||this.options.notConsumedInitial)throw new Error('admin_email_candidate_denied');
   this.proof={id:PROOF,at:entry.timestamp};return {result:{recorded:true}};
  }
  assert.ok(this.c,'A server-prepared challenge is required');assert.equal(args[4],this.c.id);
  if(name==='send_claim'){
   if(this.sendClaim)return this.result({claimed:false});this.sendClaim=args[5];return this.result({claimed:true});
  }
  if(name==='send_finish'){
   assert.equal(args[5],this.sendClaim);assert.ok(['accepted','rejected','unknown'].includes(args[6]));this.c.delivery_status=args[6];return this.result();
  }
  if(name==='verify_claim'){
   if(!['not_started','rejected'].includes(this.c.verification_state)||this.attempts>=5||this.c.expires_at<NOW)return this.result({claimed:false});
   this.operation=args[5];this.attempts++;this.c.verification_state='verifying';return this.result({claimed:true});
  }
  assert.equal(args[5],this.operation);
  if(name==='verify_finish'){
   assert.ok(['rejected','unconfirmed'].includes(args[6]));this.c.verification_state=args[6];return this.result();
  }
  if(name==='record'){
   assert.equal(this.claims.sub,AUTH);assert.notEqual(this.claims.session_id,SID);
   assert.equal(this.claims.session_id,this.options.candidateSid??CANDIDATE);
   this.c.verification_state='verified';this.c.verified_session_id=this.claims.session_id;this.c.verified_amr_at=NOW;
   if(this.options.loseRecord)throw new Error(DETAIL);return this.result();
  }
  if(name==='cleanup_claim'){
   if(this.cleanupClaim)return this.result({claimed:false});this.cleanupClaim=args[6];this.c.cleanup_state='claimed';return this.result({claimed:true});
  }
  if(name==='cleanup_finish'){
   assert.equal(args[6],this.cleanupClaim);assert.ok(['confirmed','unconfirmed'].includes(args[7]));
   if(args[7]==='confirmed')assert.equal(this.candidatePresent,false,'The real SQL independently checks absence; this fake models it');
   this.c.cleanup_state=args[7];if(args[7]==='confirmed')this.proof={id:PROOF,at:NOW};
   if(this.options.loseCleanupFinish)throw new Error(DETAIL);return this.result();
  }
  throw new Error('Unexpected fixture phase');
 }
}
async function fixture(options,run){
 const originalClaims=claims(SID,options.originalClaims??{}),candidateClaims=claims(options.candidateSid??CANDIDATE,options.candidateClaims??{});
 const originalToken=jwt(originalClaims),candidateToken=jwt(candidateClaims);
 const account={id:ADMIN,principal_id:PRINCIPAL,auth_user_id:AUTH,auth_session_id:SID,token_hash:'a'.repeat(64),public_id:PUBLIC,origin:ORIGIN,auth_version:1,email:EMAIL,role:'owner',issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,supabaseTokens:{access_token:originalToken,refresh_token:'original-refresh'}};
 const trace=[],db=new Database({...options,trace}),env=fixtureEnvironment({DB:db,SUPABASE_URL:PROJECT,SUPABASE_PUBLISHABLE_KEY:KEY}),calls=[];
 const oldNow=Date.now,oldFetch=globalThis.fetch;Date.now=()=>NOW*1000;
 globalThis.fetch=async(input,init)=>{
  const r=new Request(input,init),path=new URL(r.url).pathname,body=init.body===undefined?null:JSON.parse(init.body),token=r.headers.get('Authorization');
  const call={url:r.url,method:r.method,redirect:r.redirect,body,token};calls.push(call);trace.push('auth:'+new URL(r.url).pathname);
  if(path==='/auth/v1/user'){
   if(token==='Bearer '+originalToken)return Response.json({...baseUser(),...options.originalUser});
   assert.equal(token,'Bearer '+candidateToken);return Response.json({...baseUser(),...options.candidateUser});
  }
  if(path==='/auth/v1/otp'){
   assert.deepEqual(body,{email:EMAIL,create_user:false,gotrue_meta_security:options.captcha?{captcha_token:options.captcha}:{}});
   if(options.sendUnknown)throw new Error(DETAIL);if(options.sendRejected)return Response.json({error_code:'captcha_failed',msg:DETAIL},{status:400});
   return Response.json({});
  }
  if(path==='/auth/v1/verify'){
   assert.equal(body.email,EMAIL);assert.equal(body.type,'email');assert.equal(body.token,CODE);
   if(options.verifyUnknown)throw new Error(DETAIL);
   if(options.wrongCode)return Response.json({error_code:'otp_expired',msg:DETAIL},{status:422});
   return Response.json({access_token:candidateToken,refresh_token:REFRESH});
  }
  if(path==='/auth/v1/logout'){
   assert.equal(r.url,PROJECT+'/auth/v1/logout?scope=local');assert.equal(token,'Bearer '+candidateToken);assert.notEqual(token,'Bearer '+originalToken);
   assert.ok(db.cleanupClaim,'Durable single-use cleanup admission must precede provider logout');
   if(options.cleanupUnknown)throw new Error(DETAIL);if(!options.cleanupAckWithoutRemoval)db.candidatePresent=false;return new Response(null,{status:204});
  }
  throw new Error('Unexpected intercepted route');
 };
 const send=body=>requestAdminEmail(env,account,body??{});
 const verify=()=>verifyAdminEmail(env,account,{challenge_id:db.c.id,code:CODE});
 try{await loadAdminEmailAccount(env,account);await run({env,db,account,calls,send,verify,originalToken,candidateToken,trace});}
 finally{Date.now=oldNow;globalThis.fetch=oldFetch;for(const call of calls){assert.equal(call.redirect,'error');assert.ok(call.url.startsWith(PROJECT+'/auth/v1/'));}}
}
function publicSafe(value){const text=JSON.stringify(value);for(const x of [EMAIL,KEY,REFRESH,DETAIL,'access_token','refresh_token','csrfToken','Set-Cookie'])assert.equal(text.includes(x),false);}
test('Admin EMAIL OTP proof keeps original AAL1 session and truthfully gates sensitive actions', {concurrency:false}, async t=>{
 await t.test('real-shaped OTP exchange cleans distinct candidate once, preserves original SID/cookie and returns sidecar only',()=>fixture({},async f=>{
  assert.deepEqual(adminEmailState(f.account),{contractVersion:1,sessionId:PUBLIC,emailVerifiedAt:null});
  assert.throws(()=>requireFreshAdminEmail(f.account),isError(403,'recent_email_sign_in_required'));
  const original=clone(f.account.supabaseTokens),sent=await f.send(),receipt=await sent.json();assert.equal(sent.status,202);assert.equal(receipt.delivery_status,'accepted');assert.equal(receipt.retry_after,60);assert.equal(receipt.expires_in,300);assert.deepEqual(Object.keys(receipt).sort(),['challenge_id','delivery_status','expires_in','retry_after']);publicSafe(receipt);
  const reply=await f.verify(),state=await reply.json();assert.equal(reply.status,200);assert.equal(reply.headers.has('Set-Cookie'),false);
  assert.deepEqual(state,{contractVersion:1,sessionId:PUBLIC,emailVerifiedAt:new Date(NOW*1000).toISOString()});publicSafe(state);
  assert.deepEqual(f.account.supabaseTokens,original);assert.equal(f.account.auth_session_id,SID);assert.equal(f.account.issued_assurance_level,1);assert.equal(f.account.issued_mfa_at,null);requireFreshAdminEmail(f.account);
  const actor={surface:'admin',userId:PRINCIPAL,sessionId:SID,assuranceLevel:1,mfaAt:null};bindAdminEmailActor(actor,f.account);assert.equal(requestedAdminEmail(actor,2),true);assert.equal(actor.assuranceLevel,1);assert.equal(actor.mfaAt,null);
  assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,1);assert.equal(f.calls.filter(x=>x.url.endsWith('/logout?scope=local')).length,1);assert.deepEqual(f.db.claims,claims(SID));
  await assert.rejects(f.verify(),isError(503,'admin_email_operation_unknown'));assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,1);
 }));
 for(const amr of [[{method:'otp',timestamp:NOW-1}],[{method:'otp',timestamp:NOW+1}],[{method:'otp',timestamp:NOW-5},{method:'otp',timestamp:NOW}]])await t.test('SQL-authoritative OTP event matches explicit signed-event tolerance: '+JSON.stringify(amr),()=>fixture({createdAt:NOW-10,candidateClaims:{amr}},async f=>{await f.send();const reply=await f.verify();assert.equal(reply.status,200);requireFreshAdminEmail(f.account);assert.equal(f.db.c.cleanup_state,'confirmed');}));
 await t.test('SEND preserves human CAPTCHA and current server-resolved email',()=>fixture({captcha:'human-public-proof'},async f=>{const reply=await f.send({captcha_token:'human-public-proof'});assert.equal(reply.status,202);}));
 for(const body of [{email:'other@example.invalid'},{should_create_user:true},{surface:'member'},{session_id:CANDIDATE},{code:CODE},{captcha_token:''}])await t.test('SEND caller cannot select identity/session/registration: '+Object.keys(body)[0],()=>fixture({},async f=>{
  const before=f.calls.length;await assert.rejects(f.send(body),isError(400,'admin_email_invalid'));assert.equal(f.calls.length,before);assert.equal(f.db.c,null);
 }));
 for(const code of ['', '12345', '1234567', '12345x', 184275])await t.test('dedicated configured six-digit OTP parser rejects: '+JSON.stringify(code),()=>fixture({},async f=>{await f.send();const before=f.calls.length;await assert.rejects(verifyAdminEmail(f.env,f.account,{challenge_id:f.db.c.id,code}),isError(400,'admin_email_invalid'));assert.equal(f.calls.length,before);}));
 await t.test('expired local challenge is400 without a new verify dispatch',()=>fixture({},async f=>{await f.send();f.db.c.created_at=NOW-301;f.db.c.expires_at=NOW-1;await assert.rejects(f.verify(),isError(400,'invalid_credentials'));assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,0);}));
 await t.test('winning original authority change blocks verification before provider action',()=>fixture({},async f=>{await f.send();f.db.options.denied=true;await assert.rejects(f.verify(),isError(403,'admin_email_denied'));assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,0);}));
 await t.test('unknown SEND is recorded without automatic resend',()=>fixture({sendUnknown:true},async f=>{const reply=await f.send();assert.equal(reply.status,202);assert.equal((await reply.json()).delivery_status,'unknown');assert.equal(f.calls.filter(x=>x.url.endsWith('/otp')).length,1);assert.equal(f.db.c.delivery_status,'unknown');assert.equal(adminEmailState(f.account).emailVerifiedAt,null);}));
 await t.test('known SEND rejection is distinct from BFF expiry',()=>fixture({sendRejected:true},async f=>{await assert.rejects(f.send(),isError(400,'admin_email_send_rejected'));assert.equal(f.db.c.delivery_status,'rejected');}));
 await t.test('wrong code is400, permits only bounded explicit attempts, and never logs out',()=>fixture({wrongCode:true},async f=>{await f.send();for(let n=0;n<5;n++)await assert.rejects(f.verify(),isError(400,'invalid_credentials'));await assert.rejects(f.verify(),isError(503,'admin_email_operation_unknown'));assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,5);assert.equal(f.calls.filter(x=>x.url.includes('/logout')).length,0);assert.equal(f.db.proof,null);}));
 for(const options of [{verifyUnknown:true},{candidateSid:SID},{candidateSid:''},{candidateSid:'00000000-0000-0000-0000-000000000000'},{candidateSid:'not-a-uuid'},{candidateUser:{id:ADMIN}},{candidateUser:{email:'other@example.invalid'}},{candidateUser:{email_confirmed_at:null}},{candidateClaims:{amr:[{method:'oauth',timestamp:NOW}]}},{candidateClaims:{amr:[{method:'otp',timestamp:NOW-301}]}},{candidateClaims:{amr:[{method:'otp',timestamp:NOW+2}]}}])await t.test('candidate identity/OTP evidence fails closed: '+JSON.stringify(options),()=>fixture(options,async f=>{
  await f.send();await assert.rejects(f.verify(),isError(503,'admin_email_operation_unknown'));assert.equal(f.db.proof,null);assert.equal(f.db.c.verification_state,'unconfirmed');assert.equal(f.calls.filter(x=>x.url.includes('/logout')).length,0);await assert.rejects(f.verify(),isError(503,'admin_email_operation_unknown'));assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,1);
 }));
 for(const options of [{cleanupUnknown:true},{cleanupAckWithoutRemoval:true},{loseRecord:true},{failBefore:'cleanup_claim'},{loseCleanupFinish:true}])await t.test('unknown record/cleanup acknowledgement never replays work: '+JSON.stringify(options),()=>fixture(options,async f=>{
  await f.send();await assert.rejects(f.verify(),error=>error instanceof ApiError&&[403,503].includes(error.status));const count=f.calls.length;await assert.rejects(f.verify(),isError(503,'admin_email_operation_unknown'));assert.equal(f.calls.length,count+1,'Only original GET/user validation, no repeated verify/logout');
  assert.equal(f.calls.filter(x=>x.url.endsWith('/verify')).length,1);assert.ok(f.calls.filter(x=>x.url.includes('/logout')).length<=1);
  if(!options.loseCleanupFinish)assert.equal(adminEmailState(f.account).emailVerifiedAt,null);
 }));
 await t.test('initial OTP login validates the current Auth bearer before recording proof',()=>fixture({originalClaims:{amr:[{method:'otp',timestamp:NOW}]}},async f=>{
  await recordInitialAdminEmail(f.env,f.account,INITIAL);requireFreshAdminEmail(f.account);assert.equal(f.calls.filter(x=>x.method==='POST').length,0);
  assert.ok(f.trace.indexOf('auth:/auth/v1/user')<f.trace.indexOf('db:record_initial'));
 }));
 for(const [label,options,expected] of [
  ['user mismatch',{originalUser:{id:ADMIN}},[401,'invalid_session']],
  ['email mismatch',{originalUser:{email:'other@example.invalid'}},[403,'admin_email_denied']],
  ['unconfirmed email',{originalUser:{email_confirmed_at:null}},[403,'admin_email_denied']],
 ])await t.test('initial proof refuses '+label+' before the SQL write',()=>fixture({originalClaims:{amr:[{method:'otp',timestamp:NOW}]},...options},async f=>{
  await assert.rejects(recordInitialAdminEmail(f.env,f.account,INITIAL),isError(...expected));
  assert.equal(f.db.calls.filter(x=>x.name==='record_initial').length,0);assert.equal(f.db.proof,null);
 }));
 for(const failureMessage of ['admin_email_candidate_denied','admin_email_binding_changed'])await t.test('the exact SQL denial code '+failureMessage+' maps to a safe403',()=>fixture({originalClaims:{amr:[{method:'otp',timestamp:NOW}]},failBefore:'record_initial',failureMessage},async f=>{
  await assert.rejects(recordInitialAdminEmail(f.env,f.account,INITIAL),isError(403,'admin_email_denied'));
  assert.equal(f.db.proof,null);
 }));
 for(const failureMessage of ['xadmin_email_candidate_denied','admin_email_candidate_denied_extra','xadmin_email_binding_changed','admin_email_binding_changed_extra'])await t.test('SQL near-match '+failureMessage+' remains an unknown503',()=>fixture({failBefore:'prepare',failureMessage},async f=>{
  await assert.rejects(f.send(),isError(503,'admin_email_operation_unknown'));
 }));
 await t.test('initial proof refuses a token from a different Auth session before the SQL write',()=>fixture({originalClaims:{amr:[{method:'otp',timestamp:NOW}]}},async f=>{
  f.account.auth_session_id='99999999-9999-4999-8999-999999999999';
  await assert.rejects(recordInitialAdminEmail(f.env,f.account,INITIAL),isError(403,'admin_email_denied'));
  assert.equal(f.db.calls.filter(x=>x.name==='record_initial').length,0);assert.equal(f.db.proof,null);
 }));
 for(const method of ['password','oauth','token_refresh','mfa/totp'])await t.test('initial '+method+' cannot manufacture email proof',()=>fixture({originalClaims:{amr:[{method,timestamp:NOW}]}},async f=>{await assert.rejects(recordInitialAdminEmail(f.env,f.account,INITIAL),isError(403,'admin_email_denied'));assert.equal(adminEmailState(f.account).emailVerifiedAt,null);}));
 await t.test('sidecar route returns exact fields and never adds CSRF/token/cookie',()=>fixture({},async f=>{const reply=await handleAdminEmail(new Request(ORIGIN+'/api/admin/auth/email-verification'),f.env,f.account,'/auth/email-verification');assert.deepEqual(await reply.json(),{contractVersion:1,sessionId:PUBLIC,emailVerifiedAt:null});assert.equal(reply.headers.has('Set-Cookie'),false);}));
});

test('Admin email denial matching accepts only exact stable SQL authority tokens',()=>{
 for(const code of ['admin_email_candidate_denied','admin_email_denied','admin_email_authority','admin_email_binding','admin_email_binding_changed','admin_email_session_changed'])assert.equal(isAdminEmailDenialError(new Error('ERROR: '+code)),true,code);
 for(const code of ['xadmin_email_binding_changed','admin_email_binding_changed_extra','admin_email_candidate_denied_extra','admin_email_session_changed_suffix'])assert.equal(isAdminEmailDenialError(new Error(code)),false,code);
});

test('Admin proof attestation rejects ABA, stale/future and fake AAL without changing members',()=>{
 const oldNow=Date.now;Date.now=()=>NOW*1000;try{
  const account={id:ADMIN,principal_id:PRINCIPAL,auth_user_id:AUTH,auth_session_id:SID,token_hash:'a'.repeat(64),public_id:PUBLIC,origin:ORIGIN,auth_version:1};
  assert.throws(()=>requireFreshAdminEmail({...account,assuranceLevel:2,mfaAt:NOW,emailVerifiedAt:NOW}),isError(403,'recent_email_sign_in_required'));
  attestAdminEmailAccount(account,{contract_version:1,public_session_id:PUBLIC,email_verified_at:NOW-300,proof_id:PROOF});assert.equal(hasFreshAdminEmail(account),true);
  attestAdminEmailAccount(account,{contract_version:1,public_session_id:PUBLIC,email_verified_at:NOW-301,proof_id:PROOF});assert.equal(hasFreshAdminEmail(account),false);
  assert.throws(()=>attestAdminEmailAccount(account,{contract_version:1,public_session_id:PUBLIC,email_verified_at:NOW+1,proof_id:PROOF}),isError(503,'admin_email_verification_unavailable'));
  attestAdminEmailAccount(account,{contract_version:1,public_session_id:PUBLIC,email_verified_at:NOW,proof_id:PROOF});account.auth_version++;assert.throws(()=>requireFreshAdminEmail(account),isError(403,'recent_email_sign_in_required'));
  assert.equal(requestedAdminEmail({surface:'member',assuranceLevel:1,mfaAt:null},2),false,'Member assurance policy is not normalized');
 }finally{Date.now=oldNow;}
});
