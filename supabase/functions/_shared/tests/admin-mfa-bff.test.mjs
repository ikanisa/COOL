import {test} from 'node:test';
import assert from 'node:assert/strict';
import {adminMfaPorts,decryptAdminMfaOldCookie,resolveAdminMfaCandidate,logoutAdminMfaCandidate,recoverAdminMfaIntent,logoutAdminMfaIntent} from '../domain/admin_mfa_bff.js';
import {digest} from '../domain/core.js';
import {adminMfaReplayHashes,encrypt} from '../domain/encryption.js';
import {handleAdminAccounts} from '../domain/admin_accounts.js';

const SID='22222222-2222-4222-8222-222222222222',USER='11111111-1111-4111-8111-111111111111';
const FACTOR='33333333-3333-4333-8333-333333333333',COOKIE='a'.repeat(64),ORIGIN='https://admin.example.test';
const CHALLENGE='77777777-7777-4777-8777-777777777777',VERIFICATION='9'.repeat(64);
const KEY=btoa('q'.repeat(32));
const fixture=async({loseCommit=false,corruptWinner=false,loseCompletion=false,denyCompletion=false,completionDuringLogout=false,refreshToken='old-refresh'}={})=>{
 const hash=await digest(COOKIE),calls=[],parameters=[];
 const account={id:'44444444-4444-4444-8444-444444444444',role:'owner',auth_version:1,
  principal_id:'55555555-5555-4555-8555-555555555555',auth_user_id:USER,auth_session_id:SID,token_hash:hash,
  origin:ORIGIN,public_id:'66666666-6666-4666-8666-666666666666',email:'owner@example.test',
  issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,bff_version:7};
 const oldCipher=await encrypt({DATA_KEY_ID:'synthetic-bff',DATA_ENCRYPTION_KEY:KEY},new TextEncoder().encode(JSON.stringify({access_token:'old-access',refresh_token:refreshToken})),`bff:${SID}:${USER}`);
 const row={version:7,token_hash:hash,auth_user_id:USER,auth_session_id:SID,refresh_lease:null,refresh_lease_until:null,
  mfa_pending_hash:null,mfa_pending_old_cookie_ciphertext:null,mfa_pending_factor:null,mfa_pending_at:null,mfa_pending_state:null,token_ciphertext:oldCipher,deleted:false};
 let attempts=0;const replayKeys=new Set();
 const db={claims:null,setClaims(c){this.claims=c;},prepare(sql){return{sql,bind(...args){return{sql,args,first:async()=>{
   if(sql.startsWith('SELECT b.*,s.user_id AS id')){
    const key=sql.includes('WHERE b.mfa_pending_hash=?')?row.mfa_pending_hash:row.token_hash;
    const matchingIntent=!sql.includes('AND b.mfa_intent_hash=?')||args[2]===row.mfa_intent_hash&&args[3]===row.mfa_intent_factor&&args[4]===row.mfa_intent_challenge;
    return args[0]===key&&args[1]===ORIGIN&&matchingIntent?{...row,...account,token_hash:row.token_hash}:null;
   }
   throw new Error('unexpected synthetic read');
  }};}};},async batch(stmts){
  const out=[];
  for(const st of stmts){
   const {sql,args}=st;calls.push(sql);parameters.push(args);let values=[];
   if(sql.startsWith('SELECT private.collect_admin_mfa_authorize_v1'))values=[{result:{version:1,authorized:true,action:args[4]}}];
   else if(sql.startsWith('INSERT INTO admin_rate_limits')){
    if(row.refresh_lease===null&&row.mfa_pending_hash===null&&args[3]===hash)values=[{count:++attempts}];
   }
   else if(sql.startsWith('WITH replay AS')){
    const hashes=args.slice(6,-14),tail=args.slice(-10),lease=tail[7],expiry=tail[8],source=tail[1];
    if(row.refresh_lease===null&&row.mfa_pending_hash===null&&source===hash&&attempts<=5&&!hashes.some(v=>replayKeys.has(v))){
     replayKeys.add(hashes[0]);row.refresh_lease=lease;row.refresh_lease_until=expiry;row.mfa_intent_hash=tail[6];row.mfa_intent_factor=tail[4];row.mfa_intent_challenge=tail[5];row.mfa_intent_old_tokens=row.token_ciphertext;values=[{result:{state:'claimed',version:row.version}}];
    }
   }else if(sql.startsWith('SELECT coalesce(sum(count),0) AS total')){
    values=[{total:attempts}];
   }else if(sql.startsWith('SELECT count(*) AS total FROM admin_rate_limits')){
    values=[{total:args.slice(0,-1).filter(v=>replayKeys.has(v)).length}];
   }else if(sql.startsWith('SELECT private.collect_admin_mfa_intent_release_v1')){
    if(row.token_hash===args[1]&&row.version===args[8]&&row.refresh_lease===args[7]&&row.mfa_intent_hash===args[6]){row.refresh_lease=null;row.refresh_lease_until=null;row.mfa_intent_hash=null;}
   }else if(sql.startsWith('SELECT private.collect_admin_mfa_intent_recover_v1')){
    if(row.token_hash!==args[1]||row.mfa_intent_factor!==args[4]||row.mfa_intent_challenge!==args[5]||row.mfa_intent_hash!==args[6])throw new Error('synthetic wrong intent');
    if(row.mfa_pending_state==='staged')values=[{result:{state:'staged',candidate_hash:row.mfa_pending_hash,candidate_ciphertext:row.mfa_intent_candidate_ciphertext}}];
    else if(row.refresh_lease_until>Math.floor(Date.now()/1000))throw Object.assign(new Error('synthetic active lease'),{code:'55000'});
    else{row.refresh_lease=args[7];row.refresh_lease_until=args[8];values=[{result:{state:'claimed',version:row.version,old_tokens:row.mfa_intent_old_tokens}}];}
   }else if(sql.startsWith('SELECT private.collect_admin_mfa_intent_prepare_v1')){
    if(args[1]!==hash||args[4]!==row.version||args[5]!==row.refresh_lease)throw new Error('synthetic lease mismatch');
    row.version++;row.refresh_lease=null;row.refresh_lease_until=null;row.mfa_pending_factor=args[6];row.mfa_pending_hash=args[9];
    row.mfa_pending_at=1000;row.mfa_pending_state='staged';
    row.token_ciphertext=args[10];row.mfa_pending_old_cookie_ciphertext=args[11];row.mfa_intent_candidate_ciphertext=args[12];values=[{result:{version:1,state:'pending'}}];
    if(loseCommit){if(corruptWinner)row.token_ciphertext='different-winner';throw new Error('synthetic lost commit reply');}
   }else if(sql.startsWith('SELECT private.collect_admin_mfa_intent_complete_v1')){
    if(denyCompletion||args[0]!==row.mfa_pending_hash||row.mfa_pending_state!=='staged')throw new Error('synthetic no completion');
    row.token_hash=row.mfa_pending_hash;account.issued_assurance_level=2;account.issued_mfa_factor_id=row.mfa_pending_factor;account.issued_mfa_at=row.mfa_pending_at;
    row.mfa_pending_hash=null;row.mfa_pending_old_cookie_ciphertext=null;row.mfa_pending_factor=null;row.mfa_pending_at=null;row.mfa_pending_state=null;
    values=[{result:{version:1,state:'complete',public_session_id:account.public_id}}];
    if(loseCompletion)throw new Error('synthetic lost completion reply');
   }else if(sql.startsWith('SELECT private.collect_admin_mfa_intent_restore_v1')){
    if(args[0]!==row.mfa_pending_hash)throw new Error('synthetic no pending candidate');
    row.mfa_pending_state='restoring';row.token_ciphertext=row.mfa_intent_old_tokens;values=[{result:{version:1,state:'restore',original_hash:row.token_hash,
     old_cookie_ciphertext:row.mfa_pending_old_cookie_ciphertext,auth_user_id:USER,auth_session_id:SID,public_session_id:account.public_id}}];
   }else if(sql.startsWith('SELECT b.version,b.token_ciphertext'))values=[{...row}];
   out.push({success:true,results:values,meta:{changes:values.length}});
  }
  return out;
 },async context(){},async transaction(fn){
  if(completionDuringLogout){row.token_hash=row.mfa_pending_hash;row.mfa_pending_hash=null;}
  const sql={unsafe:async(query,args=[])=>{
   if(query.startsWith('SELECT pg_advisory'))return [];
   if(query.startsWith('SELECT b.token_hash')){
    if(query.includes('b.mfa_intent_hash=$2')){
     const same=!row.deleted&&args[0]===ORIGIN&&args[1]===row.mfa_intent_hash&&args[2]===row.mfa_intent_factor&&args[3]===row.mfa_intent_challenge&&
      (row.token_hash===args[4]||row.mfa_pending_hash===args[4]&&row.mfa_pending_state==='staged');
     return same?[{token_hash:row.token_hash,auth_user_id:USER,auth_session_id:SID,token_ciphertext:row.token_ciphertext}]:[];
    }
    const same=(!row.deleted&&args[0]===ORIGIN&&args[1]===account.public_id&&args[2]===USER&&args[3]===SID&&
      (row.token_hash===args[4]&&row.mfa_pending_hash===args[5]||row.token_hash===args[5]&&row.mfa_pending_hash===null));
    return same?[{token_hash:row.token_hash,auth_user_id:USER,auth_session_id:SID,token_ciphertext:row.token_ciphertext}]:[];
   }
   if(query.startsWith('DELETE FROM app.admin_sessions')){row.deleted=true;return [];}
   throw new Error('unexpected synthetic transaction');
  }};return fn(sql);
 }};
 const env={DB:db,SESSION_KEY_ID:'synthetic-bff',SESSION_ENCRYPTION_KEY:KEY,ADMIN_ORIGIN:ORIGIN};
 const request=new Request(ORIGIN+'/api/admin/auth/mfa/verify',{method:'POST',headers:{Cookie:`__Host-collect_admin=${COOKIE}`}});
 const raw=adminMfaPorts(env,account,request),ports={...raw,
  claim:args=>raw.claim({...args,challengeId:CHALLENGE,verificationId:VERIFICATION}),
  release:args=>raw.release({...args,factorId:FACTOR,challengeId:CHALLENGE,verificationId:VERIFICATION}),
  stage:args=>raw.stage({...args,challengeId:CHALLENGE,verificationId:VERIFICATION})};
 return {account,row,env,request,calls,parameters,ports};
};
const verified={claims:{sub:USER,session_id:SID,role:'authenticated',aal:'aal2'}};
const tokens={access_token:'synthetic-access',refresh_token:'synthetic-refresh'};

test('guard and lease use the exact actor and owned factor',async()=>{
 const f=await fixture();await f.ports.guard({fresh:false,operation:'verify',factorId:FACTOR});
 const lease=await f.ports.claim({factorId:FACTOR,code:'123456'});assert.equal(lease.version,7);assert.equal(f.row.refresh_lease,lease.id);
 assert.ok(f.calls.some(v=>v.includes('collect_admin_mfa_authorize_v1')));
});
test('a changed cookie or existing lease cannot acquire the verification lease',async()=>{
 const f=await fixture();const wrong=adminMfaPorts(f.env,f.account,new Request(ORIGIN,{headers:{Cookie:`__Host-collect_admin=${'b'.repeat(64)}`}}));
 await assert.rejects(wrong.claim({factorId:FACTOR,code:'123456'}),e=>e.status===403);assert.equal(f.row.refresh_lease,null);
 await f.ports.claim({factorId:FACTOR,code:'123456'});await assert.rejects(f.ports.claim({factorId:FACTOR,code:'654321'}),e=>e.status===409);
});
test('stale release cannot clear a newer session lease',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});f.row.refresh_lease='newer-lease';
 await f.ports.release({lease});assert.equal(f.row.refresh_lease,'newer-lease');
});
test('a bounded account budget stops the sixth code attempt before provider dispatch',async()=>{
 const f=await fixture();for(let n=0;n<5;n++){const lease=await f.ports.claim({factorId:FACTOR,code:String(n).padStart(6,'0')});await f.ports.release({lease});}
 await assert.rejects(f.ports.claim({factorId:FACTOR,code:'000005'}),e=>e.status===429&&e.code==='rate_limited');
 assert.equal(f.row.refresh_lease,null);
});
test('the same code cannot be sent to a second challenge and is never stored in plaintext',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});await f.ports.release({lease});
 await assert.rejects(f.ports.claim({factorId:FACTOR,code:'123456'}),e=>e.status===429&&e.code==='mfa_code_already_used');
 assert.equal(f.parameters.flat().includes('123456'),false);
});
test('replay HMAC survives a session-key rotation while old decryption keys are retained',async()=>{
 const oldKey=btoa('o'.repeat(32)),newKey=btoa('n'.repeat(32));
 const before=await adminMfaReplayHashes({DATA_KEY_ID:'old',DATA_ENCRYPTION_KEY:oldKey},USER,FACTOR,'123456');
 const after=await adminMfaReplayHashes({DATA_KEY_ID:'new',DATA_ENCRYPTION_KEY:newKey,DATA_DECRYPTION_KEYS_JSON:JSON.stringify({old:oldKey})},USER,FACTOR,'123456');
 assert.equal(before.length,1);assert.equal(after.length,2);assert.equal(after[1],before[0]);assert.notEqual(after[0],before[0]);
 assert.match(before[0],/^[a-f0-9]{64}$/);assert.equal(before[0].includes('123456'),false);
 const other=await adminMfaReplayHashes({DATA_KEY_ID:'old',DATA_ENCRYPTION_KEY:oldKey},USER,'44444444-4444-4444-8444-444444444444','123456');
 assert.notEqual(other[0],before[0]);
});
test('stage returns only the provisional cookie after the exact lease commits',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const result=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 assert.equal(result.ok,true);assert.match(result.cookie,/^__Host-collect_admin=[a-f0-9]{64}; Path=\/; HttpOnly; SameSite=Strict;/);
 const token=result.cookie.split(';')[0].split('=')[1];assert.equal(await digest(token),f.row.mfa_pending_hash);
 assert.equal(JSON.stringify(result).includes('synthetic-refresh'),false);assert.equal(f.row.version,8);assert.equal(f.row.refresh_lease,null);
 assert.deepEqual(f.env.DB.claims,verified.claims);assert.equal(await decryptAdminMfaOldCookie(f.env,f.account,f.row.mfa_pending_old_cookie_ciphertext),COOKIE);
});
test('a lost commit response is recovered only from an exact retained candidate',async()=>{
 const f=await fixture({loseCommit:true}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const result=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 assert.equal(result.ok,true);assert.equal(f.row.version,8);
});
test('a different retained ciphertext is never adopted as the committed candidate',async()=>{
 const f=await fixture({loseCommit:true,corruptWinner:true}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 await assert.rejects(f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease}),e=>e.status===503);
});
test('fallback decryption rejects a cookie from a different original session',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 await assert.rejects(decryptAdminMfaOldCookie(f.env,{...f.account,token_hash:'b'.repeat(64)},f.row.mfa_pending_old_cookie_ciphertext));
 await assert.rejects(decryptAdminMfaOldCookie(f.env,{...f.account,auth_session_id:'44444444-4444-4444-8444-444444444444'},f.row.mfa_pending_old_cookie_ciphertext));
});
const candidateRequest=cookie=>new Request(ORIGIN+'/api/admin/auth/session',{headers:{Cookie:cookie.split(';')[0],Origin:ORIGIN}});
const verifyProvider=async (_env,token)=>{assert.ok(['synthetic-access','old-access'].includes(token));return {...verified,claims:{...verified.claims,aal:token==='old-access'?'aal1':'aal2'},user:{id:USER,email:'owner@example.test',email_confirmed_at:'yes'}};};
test('the presented provisional cookie completes the upgrade, preserving public session identity',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 assert.equal(f.account.issued_assurance_level,1);assert.equal(f.row.token_hash,f.account.token_hash);
 assert.deepEqual(await resolveAdminMfaCandidate(f.env,candidateRequest(staged.cookie),{enabled:true,verify:verifyProvider}),{state:'complete'});
 assert.equal(f.account.issued_assurance_level,2);assert.equal(f.row.mfa_pending_hash,null);
});
test('a disabled feature restores the original cookie and repeated lost replies are safe',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease}),req=candidateRequest(staged.cookie);
 const first=await resolveAdminMfaCandidate(f.env,req,{enabled:false,verify:verifyProvider});
 assert.equal(first.state,'restore');assert.equal(first.token,COOKIE);assert.equal(f.row.mfa_pending_state,'restoring');assert.equal(f.account.issued_assurance_level,1);
 const retry=await resolveAdminMfaCandidate(f.env,req,{enabled:true,verify:verifyProvider});assert.equal(retry.token,COOKIE);assert.equal(f.account.issued_assurance_level,1);
});
test('failed candidate completion restores the original session without issuing AAL2',async()=>{
 const f=await fixture({denyCompletion:true}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 const result=await resolveAdminMfaCandidate(f.env,candidateRequest(staged.cookie),{enabled:true,verify:verifyProvider});
 assert.equal(result.state,'restore');assert.equal(result.token,COOKIE);assert.equal(f.account.issued_assurance_level,1);
});
test('lost completion reply uses only the exact committed new session',async()=>{
 const f=await fixture({loseCompletion:true}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 assert.deepEqual(await resolveAdminMfaCandidate(f.env,candidateRequest(staged.cookie),{enabled:true,verify:verifyProvider}),{state:'complete'});
});
test('foreign candidate or changed provider identity cannot recover a session',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 assert.equal(await resolveAdminMfaCandidate(f.env,candidateRequest(`__Host-collect_admin=${'f'.repeat(64)};`),{enabled:true,verify:verifyProvider}),null);
 await assert.rejects(resolveAdminMfaCandidate(f.env,candidateRequest(staged.cookie),{enabled:true,verify:async()=>({...verified,user:{id:'other',email:'owner@example.test',email_confirmed_at:'yes'}})}),e=>e.status===403);
 assert.equal(f.account.issued_assurance_level,1);
});
const recoveryBody={factor_id:FACTOR,challenge_id:CHALLENGE,verification_id:VERIFICATION};
const recoveryRequest=async(cookie=COOKIE,csrfCookie=cookie)=>new Request(ORIGIN+'/api/admin/auth/mfa/recover',{
 method:'POST',headers:{Origin:ORIGIN,Cookie:`__Host-collect_admin=${cookie}`,'X-Collect-CSRF':await digest('collect-admin-csrf:'+csrfCookie),
 'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'}});
const reloadedRecoveryRequest=()=>new Request(ORIGIN+'/api/admin/auth/mfa/recover',{
 method:'POST',headers:{Origin:ORIGIN,Cookie:`__Host-collect_admin=${COOKIE}`,
 'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'}});
const recoveryVerify=async (_env,token)=>({...verified,claims:{...verified.claims,aal:token==='old-access'?'aal1':'aal2'},
 user:{id:USER,email:'owner@example.test',email_confirmed_at:'yes',factors:[{id:FACTOR,status:'verified',factor_type:'totp'}]}});
test('a lost provider reply recovers only the initiating challenge using its legacy parent token',async()=>{
 const f=await fixture({refreshToken:'abc123def456'}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 f.row.refresh_lease_until=Math.floor(Date.now()/1000)-1;let calls=0;
 const result=await recoverAdminMfaIntent(f.env,await recoveryRequest(),recoveryBody,{verify:recoveryVerify,requestAuth:async(_env,path,options)=>{
  calls++;assert.equal(path,'/token?grant_type=refresh_token');assert.deepEqual(options.body,{refresh_token:'abc123def456'});return tokens;
 }});
 assert.equal(calls,1);assert.equal(result.ok,true);assert.equal(f.account.issued_assurance_level,1);
 assert.equal(f.row.token_hash,f.account.token_hash);assert.equal(f.row.refresh_lease,null);
 assert.equal(await digest(result.cookie.split(';')[0].split('=')[1]),f.row.mfa_pending_hash);
 assert.equal(JSON.stringify(result).includes('abc123def456'),false);assert.notEqual(lease.id,f.row.refresh_lease);
});
test('a previously AAL2 session rechecks its exact newer challenge without changing the old cookie',async()=>{
 const f=await fixture({refreshToken:'abc123def456'});f.account.issued_assurance_level=2;
 const lease=await f.ports.claim({factorId:FACTOR,code:'123456'});f.row.refresh_lease_until=Math.floor(Date.now()/1000)-1;
 const verify=async(_env,token)=>({...await recoveryVerify(_env,token),claims:{...verified.claims,aal:'aal2'}});
 const result=await recoverAdminMfaIntent(f.env,await recoveryRequest(),recoveryBody,{verify,requestAuth:async()=>tokens});
 assert.equal(result.ok,true);assert.equal(f.account.issued_assurance_level,2);assert.equal(f.row.token_hash,f.account.token_hash);
 assert.equal(await digest(result.cookie.split(';')[0].split('=')[1]),f.row.mfa_pending_hash);assert.notEqual(lease.id,f.row.refresh_lease);
});
test('recovery refuses a different intent, cookie, CSRF or an active lease before provider refresh',async()=>{
 const f=await fixture({refreshToken:'abc123def456'});await f.ports.claim({factorId:FACTOR,code:'123456'});let calls=0;
 const options={verify:recoveryVerify,requestAuth:async()=>{calls++;return tokens;}};
 await assert.rejects(recoverAdminMfaIntent(f.env,await recoveryRequest(),{...recoveryBody,verification_id:'8'.repeat(64)},options),e=>e.status===403);
 await assert.rejects(recoverAdminMfaIntent(f.env,await recoveryRequest('b'.repeat(64)),recoveryBody,options),e=>e.status===403);
 await assert.rejects(recoverAdminMfaIntent(f.env,await recoveryRequest(COOKIE,'b'.repeat(64)),recoveryBody,options),e=>e.status===403);
 await assert.rejects(recoverAdminMfaIntent(f.env,await recoveryRequest(),recoveryBody,options),e=>e.status===409&&e.code==='mfa_recovery_pending');
 assert.equal(calls,0);assert.equal(f.account.issued_assurance_level,1);
});
test('a staged lost reply returns only its bound candidate and does not refresh again',async()=>{
 const f=await fixture({refreshToken:'abc123def456'}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({verified,tokens,factorId:FACTOR,lease});let calls=0;
 const result=await recoverAdminMfaIntent(f.env,await recoveryRequest(),recoveryBody,{verify:recoveryVerify,requestAuth:async()=>{calls++;}});
 assert.equal(result.cookie,staged.cookie);assert.equal(calls,0);assert.equal(f.account.issued_assurance_level,1);
});
test('a reloaded tab can recover only with its unguessable intent and the original cookie',async()=>{
 const f=await fixture({refreshToken:'abc123def456'}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({verified,tokens,factorId:FACTOR,lease});
 const options={verify:recoveryVerify,requestAuth:async()=>{throw new Error('unexpected provider refresh');}};
 await assert.rejects(recoverAdminMfaIntent(f.env,reloadedRecoveryRequest(),{...recoveryBody,verification_id:'0'.repeat(64)},options),e=>e.status===403);
 const crossOrigin=new Request(ORIGIN+'/api/admin/auth/mfa/recover',{method:'POST',headers:{Origin:'https://foreign.example.test',
  Cookie:`__Host-collect_admin=${COOKIE}`,'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'}});
 await assert.rejects(recoverAdminMfaIntent(f.env,crossOrigin,recoveryBody,options),e=>e.status===403);
 const noCustomHeader=new Request(ORIGIN+'/api/admin/auth/mfa/recover',{method:'POST',headers:{Origin:ORIGIN,
  Cookie:`__Host-collect_admin=${COOKIE}`,'Content-Type':'application/json'}});
 await assert.rejects(recoverAdminMfaIntent(f.env,noCustomHeader,recoveryBody,options),e=>e.status===403);
 const result=await recoverAdminMfaIntent(f.env,reloadedRecoveryRequest(),recoveryBody,options);
 assert.equal(result.cookie,staged.cookie);assert.equal(f.account.issued_assurance_level,1);
});
test('an unsupported counter token never dispatches a speculative recovery refresh',async()=>{
 const f=await fixture({refreshToken:'v2_unsupported_counter'});await f.ports.claim({factorId:FACTOR,code:'123456'});
 f.row.refresh_lease_until=Math.floor(Date.now()/1000)-1;let calls=0;
 await assert.rejects(recoverAdminMfaIntent(f.env,await recoveryRequest(),recoveryBody,{verify:recoveryVerify,requestAuth:async()=>{calls++;}}),e=>e.status===409&&e.code==='mfa_recovery_unavailable');
 assert.equal(calls,0);assert.equal(f.account.issued_assurance_level,1);
});
test('an expired original access token reports unavailable recovery without clearing the saved session',async()=>{
 const f=await fixture({refreshToken:'abc123def456'});await f.ports.claim({factorId:FACTOR,code:'123456'});
 f.row.refresh_lease_until=Math.floor(Date.now()/1000)-1;let calls=0;
 await assert.rejects(recoverAdminMfaIntent(f.env,await recoveryRequest(),recoveryBody,{
  verify:async()=>{throw Object.assign(new Error('expired'),{status:401});},requestAuth:async()=>{calls++;}
 }),e=>e.status===409&&e.code==='mfa_recovery_unavailable');
 assert.equal(calls,0);assert.equal(f.row.deleted,false);assert.equal(f.account.issued_assurance_level,1);
});
test('after reload explicit sign-out revokes only the exact intent-bound local session',async()=>{
 const f=await fixture();await f.ports.claim({factorId:FACTOR,code:'123456'});
 await assert.rejects(logoutAdminMfaIntent(f.env,reloadedRecoveryRequest(),{...recoveryBody,verification_id:'8'.repeat(64)}),e=>e.status===409);
 assert.equal(f.row.deleted,false);
 const result=await logoutAdminMfaIntent(f.env,reloadedRecoveryRequest(),recoveryBody);
 assert.equal(result.state,'revoked');assert.equal(result.providerLogout,'unconfirmed');assert.equal(f.row.deleted,true);
 assert.match(result.cookie,/Max-Age=0/);
});
test('the same pending intent can revoke a staged replacement cookie after reload',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({verified,tokens,factorId:FACTOR,lease});
 const candidate=staged.cookie.split(';')[0].split('=')[1];
 const req=new Request(ORIGIN+'/api/admin/auth/logout',{method:'POST',headers:{Origin:ORIGIN,Cookie:`__Host-collect_admin=${candidate}`,
  'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'}});
 const result=await logoutAdminMfaIntent(f.env,req,recoveryBody);assert.equal(result.state,'revoked');assert.equal(f.row.deleted,true);
});
test('the existing Admin logout route accepts only a bound recovery intent without CSRF',async()=>{
 const f=await fixture();await f.ports.claim({factorId:FACTOR,code:'123456'});
 const req=new Request(ORIGIN+'/api/admin/auth/logout',{method:'POST',headers:{Origin:ORIGIN,Cookie:`__Host-collect_admin=${COOKIE}`,
  'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'},body:JSON.stringify(recoveryBody)});
 const response=await handleAdminAccounts(req,{...f.env,COLLECT_ADMIN_TOTP_RECOVERY_ENABLED:'true'},{});
 assert.equal(response.status,200);assert.equal((await response.json()).ok,true);assert.equal(f.row.deleted,true);
 assert.match(response.headers.get('Set-Cookie'),/Max-Age=0/);
});
test('sign-out with a provisional cookie revokes the old local session before provider logout',async()=>{
 const f=await fixture(),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
 const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
 const req=new Request(ORIGIN+'/api/admin/auth/logout',{method:'POST',headers:{Origin:ORIGIN,Cookie:staged.cookie.split(';')[0],
  'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json','X-Collect-CSRF':await digest('collect-admin-csrf:'+COOKIE)},body:'{}'});
 const result=await logoutAdminMfaCandidate(f.env,req);assert.equal(result.state,'revoked');assert.equal(result.providerLogout,'unconfirmed');
 assert.equal(f.row.deleted,true);assert.match(result.cookie,/Max-Age=0/);
});
test('pending sign-out refuses incorrect CSRF and handles concurrent candidate completion',async()=>{
 for(const [wrong,race]of [[true,false],[false,true]]){
  const f=await fixture({completionDuringLogout:race}),lease=await f.ports.claim({factorId:FACTOR,code:'123456'});
  const staged=await f.ports.stage({account:f.account,verified,tokens,factorId:FACTOR,lease});
  const req=new Request(ORIGIN+'/api/admin/auth/logout',{method:'POST',headers:{Origin:ORIGIN,Cookie:staged.cookie.split(';')[0],
   'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json','X-Collect-CSRF':wrong?'invalid':await digest('collect-admin-csrf:'+COOKIE)},body:'{}'});
  if(wrong){await assert.rejects(logoutAdminMfaCandidate(f.env,req),e=>e.status===403);assert.equal(f.row.deleted,false);}
  else{assert.equal((await logoutAdminMfaCandidate(f.env,req)).state,'revoked');assert.equal(f.row.deleted,true);}
 }
});
