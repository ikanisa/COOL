import {test} from 'node:test';
import assert from 'node:assert/strict';
import {adminManagedMfa} from '../domain/admin_managed_mfa.js';
import {ApiError} from '../domain/core.js';

const SID='22222222-2222-4222-8222-222222222222',USER='11111111-1111-4111-8111-111111111111';
const FACTOR='33333333-3333-4333-8333-333333333333',OTHER='44444444-4444-4444-8444-444444444444';
const CHALLENGE='55555555-5555-4555-8555-555555555555',NOW=1800000000;
const SECRET='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567', EMAIL='owner@example.test';
const COOKIE=`__Host-collect_admin=${'a'.repeat(64)}; Path=/; HttpOnly; SameSite=Strict; Max-Age=34560000; Secure`;
const account={role:'owner',auth_user_id:USER,auth_session_id:SID,principal_id:'principal',email:EMAIL,supabaseTokens:{access_token:'old-token'}};
const sample=(status='unverified')=>({id:FACTOR,factor_type:'totp',status,friendly_name:'Collect Admin'});
const identity=(aal='aal1',factor=sample())=>({user:{id:USER,email:EMAIL,email_confirmed_at:'yes',factors:[factor]},claims:{sub:USER,session_id:SID,aal,role:'authenticated'}});
const setup=()=>{
 const calls=[];let old=identity(),next=identity('aal2',sample('verified')),guardFailure=null,staged=0;
 const provider={identity:async token=>{calls.push(['identity',token]);return token==='new-token'?next:old;},request:async(path,opts)=>{
  calls.push(['request',path,opts]);
  if(path==='/factors')return {id:FACTOR,type:'totp',friendly_name:'Collect Admin',totp:{secret:SECRET,uri:`otpauth://totp/${encodeURIComponent('Collect:'+EMAIL)}?secret=${SECRET}&issuer=Collect`}};
  if(path.endsWith('/challenge'))return {id:CHALLENGE,type:'totp',expires_at:NOW+90};
  if(path.endsWith('/verify'))return {access_token:'new-token',refresh_token:'new-refresh'};
  return {id:FACTOR};
 }};
 const guard=async context=>{calls.push(['guard',context]);if(guardFailure)throw guardFailure;};
 const claim=async context=>{calls.push(['claim',context]);return{id:'synthetic-lease',version:1};};
 const release=async context=>{calls.push(['release',context]);};
 const stage=async context=>{calls.push(['stage',context]);staged++;return {ok:true,cookie:COOKIE};};
 return {calls,provider,guard,claim,release,stage,clock:()=>NOW,staged:()=>staged,setOld:v=>old=v,setNext:v=>next=v,failGuard:v=>guardFailure=v};
};
const exec=(f,operation,body,changes={})=>adminManagedMfa({enabled:true,account,operation,body,provider:f.provider,guard:f.guard,claim:f.claim,release:f.release,stage:f.stage,clock:f.clock,...changes});
const rejectsCode=(p,status,code)=>assert.rejects(p,e=>e.status===status&&e.code===code);

test('feature remains retired and fails closed without complete guarded ports',async()=>{
 for(const args of [{enabled:false},{guard:null},{provider:null},{stage:null}]){
  const f=setup(),op=args.stage===null?'verify':'list',body=op==='verify'?{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'}:{};
  await assert.rejects(exec(f,op,body,args));assert.equal(f.calls.length,0);
 }
});
test('only an authenticated Admin-surface account can use this adapter',async()=>{
 for(const role of ['member','owner ']){const f=setup();await rejectsCode(exec(f,'list',{}, {account:{...account,role}}),403,'mfa_admin_denied');assert.equal(f.calls.length,0);}
 for(const role of ['owner','admin','staff']){const f=setup();const result=await exec(f,'list',{}, {account:{...account,role}});assert.equal(result.id,'principal');}
});
test('factor listing returns only minimal owned TOTP fields and no secret or provider token',async()=>{
 const f=setup();f.setOld(identity('aal1',{...sample(),secret:'never-return',phone:'never-return'}));
 const result=await exec(f,'list',{});assert.deepEqual(result,{id:'principal',factors:[sample()]});assert.equal(f.calls.filter(v=>v[0]==='guard').length,2);
});
test('malformed or duplicate provider factors fail closed',async()=>{
 for(const factors of [[sample(),sample()], [sample(),{...sample(),id:FACTOR.toUpperCase()}], [{...sample(),id:'bad'}], [{...sample(),status:'unknown'}]]){
  const f=setup(),v=identity();v.user.factors=factors;f.setOld(v);await rejectsCode(exec(f,'list',{}),503,'mfa_operation_unknown');
 }
});
test('enrollment needs current actor and verified-email guard both before and after provider',async()=>{
 const f=setup(),result=await exec(f,'enroll',{friendly_name:'Collect Admin',factor_type:'totp'});
 assert.equal(result.status,'unverified');assert.equal(result.totp.secret,SECRET);
 assert.deepEqual(f.calls.filter(v=>v[0]==='guard').map(v=>v[1]),[{fresh:true,operation:'enroll',factorId:null},{fresh:true,operation:'enroll',factorId:null}]);
 assert.deepEqual(f.calls.find(v=>v[0]==='request').slice(1),['/factors',{method:'POST',token:'old-token',body:{factor_type:'totp',friendly_name:'Collect Admin',issuer:'Collect'}}]);
});
test('enrollment result from a different identity or malformed TOTP URI never reveals a secret',async()=>{
 const f=setup();f.provider.request=async()=>({id:FACTOR,type:'totp',friendly_name:'Collect Admin',totp:{secret:SECRET,uri:`otpauth://totp/Collect:other@example.test?secret=${SECRET}&issuer=Collect`}});
 await rejectsCode(exec(f,'enroll',{friendly_name:'Collect Admin',factor_type:'totp'}),503,'mfa_operation_unknown');
});
test('wrong owner, session, confirmed email or email cannot reach provider mutation',async()=>{
 for(const change of [v=>v.user.id=OTHER,v=>v.claims.sub=OTHER,v=>v.claims.session_id=OTHER,v=>v.claims.role='anon',v=>v.user.is_anonymous=true,v=>v.user.email='other@example.test',v=>v.user.email_confirmed_at=null]){
  const f=setup(),v=identity();change(v);f.setOld(v);
  await rejectsCode(exec(f,'challenge',{factor_id:FACTOR}),403,'mfa_admin_denied');assert.equal(f.calls.some(v=>v[0]==='request'),false);
 }
});
test('challenge and cancellation enforce owned factor, pending status and output identity',async()=>{
 const f=setup();assert.deepEqual(await exec(f,'challenge',{factor_id:FACTOR}),{id:CHALLENGE,challenge_id:CHALLENGE,factor_id:FACTOR,expires_at:NOW+90});
 assert.deepEqual(await exec(f,'cancel',{factor_id:FACTOR}),{id:FACTOR,factor_type:'totp',status:'revoked'});
 const wrong=setup();await rejectsCode(exec(wrong,'challenge',{factor_id:OTHER}),403,'mfa_admin_denied');assert.equal(wrong.calls.some(v=>v[0]==='request'),false);
 const verified=setup();verified.setOld(identity('aal1',sample('verified')));await rejectsCode(exec(verified,'cancel',{factor_id:FACTOR}),403,'mfa_admin_denied');
});
test('successful TOTP verify stages a separately bound cookie and does not expose provider tokens',async()=>{
 const f=setup(),result=await exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'});
 assert.deepEqual(result,{ok:true,cookie:COOKIE});assert.equal(f.staged(),1);
 const staged=f.calls.find(v=>v[0]==='stage')[1];assert.equal(staged.verified.claims.aal,'aal2');assert.equal(staged.factorId,FACTOR);
 assert.equal(JSON.stringify(result).includes('new-refresh'),false);
});
test('verification claims a session lease before contacting the provider',async()=>{
 const f=setup();await exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'});
 assert.ok(f.calls.findIndex(v=>v[0]==='claim')<f.calls.findIndex(v=>v[0]==='request'));
 assert.equal(f.calls.find(v=>v[0]==='stage')[1].lease.id,'synthetic-lease');
});
test('only a definite provider rejection releases the exclusive lease',async()=>{
 for(const [failure,expected]of [[new ApiError(422,'bad_code','synthetic'),true],[new ApiError(503,'unavailable','synthetic'),false],[new Error('unknown provider result'),false]]){
  const f=setup();f.provider.request=async()=>{throw failure;};
  await assert.rejects(exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'}));
  assert.equal(f.calls.some(v=>v[0]==='release'),expected);assert.equal(f.staged(),0);
 }
});
test('a post-verification identity failure is an unknown outcome, never an automatic sign-out',async()=>{
 const f=setup(),identityBefore=f.provider.identity;
 f.provider.identity=async token=>token==='new-token'?Promise.reject(new ApiError(401,'invalid_session','synthetic')):identityBefore(token);
 await rejectsCode(exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'}),503,'mfa_operation_unknown');
 assert.equal(f.calls.some(v=>v[0]==='release'),false);assert.equal(f.staged(),0);
});
test('AAL1, foreign session, foreign owner or unverified factor cannot reach the session-upgrade port',async()=>{
 for(const change of [v=>v.claims.aal='aal1',v=>v.claims.session_id=OTHER,v=>v.user.id=OTHER,v=>v.user.factors=[sample('unverified')]]){
  const f=setup(),v=identity('aal2',sample('verified'));change(v);f.setNext(v);
  await assert.rejects(exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'}));assert.equal(f.staged(),0);
 }
});
test('revoked access during provider verification makes transactional staging fail',async()=>{
 const f=setup();f.stage=async()=>{throw new Error('synthetic transactional authority revoked');};
 await assert.rejects(exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'}));assert.equal(f.staged(),0);
});
test('unconfirmed session staging is not reported as successful verification',async()=>{
 for(const result of [null,{}, {ok:true}, {ok:false,cookie:COOKIE}, {ok:true,cookie:'candidate'}, {ok:true,cookie:COOKIE.replace('HttpOnly; ','')}, {ok:true,cookie:COOKIE.replace('34560000','99999999')}]){
  const f=setup();f.stage=async()=>result;await rejectsCode(exec(f,'verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'123456'}),503,'mfa_operation_unknown');
 }
});
test('extra fields, invalid IDs, invalid code, or unsupported enrollment are rejected before provider calls',async()=>{
 const cases=[['list',{extra:1}],['challenge',{factor_id:'bad'}],['verify',{factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:'9'.repeat(64),code:'12345'}],['enroll',{friendly_name:'Other',factor_type:'totp'}]];
 for(const [op,body]of cases){const f=setup();await rejectsCode(exec(f,op,body),400,'invalid_mfa_request');assert.equal(f.calls.length,0);}
});
