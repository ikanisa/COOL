import {BuriError,requireThat,requirePort} from './errors.js';
import {normalizePhone,requirePin,requireId,requireRequestId,sha256,exactKeys} from './values.js';
import {PinHasher,newBearer,PIN_ITERATIONS} from './pin.js';
import {COLLECT_MUTATION_LOCK} from './postgres-authority.js';
import {readNativeBody,requireActiveNativeRequest} from './wire/request-boundary.mjs';
import {parseWire,validateNativeRequest,requestBinding,bindNativeResponse,CONTRACT_VERSION} from './wire/native-contract.mjs';
import {pgInteger} from './postgres-values.js';

// Proof is scoped to the admitted request-owned database, never an environment
// flag, actor object, stored hash or client-selected collection. Raw credentials
// remain in this closure and are passed only as parameterized SQL arguments.
const proofs=new WeakMap(),active=new WeakSet();
export const PIN_CONTEXT_SQL='SELECT * FROM private.burimunsi_pin_session_context($1,$2::uuid,$3,$4)';
export const PIN_SET_CONTEXT_SQL='SELECT private.burimunsi_set_pin_context($1,$2::uuid,$3,$4) AS result';
export const PIN_RENEW_SQL='SELECT * FROM private.burimunsi_pin_renew_session($1,$2::uuid,$3,$4,$5,$6)';
export const PIN_LOGOUT_SQL='SELECT private.burimunsi_pin_logout_barrier($1,$2::uuid,$3,$4,$5,$6) AS result';
export const RETIREMENT_OUTCOME_SQL='SELECT private.burimunsi_gateway_retirement_outcome($1,$2::uuid,$3,$4,$5::uuid,$6) AS result';
// Matches the bound already enforced when PostgreSQL creates a PIN session.
// This applies only after the database has independently validated the session.
export const PIN_CLOCK_SKEW_MS=5000;
export function hasPhonePinContext(db){return proofs.has(db);}
export async function applyPhonePinContext(db,sql,groupId){
  const proof=proofs.get(db);if(!proof)return false;
  requireThat(proof.groupId===groupId,'access_denied',403);
  let rows;
  try{rows=await sql.unsafe(PIN_SET_CONTEXT_SQL,proof.values);}
  catch(error){if(error?.code==='42501')throw new BuriError('session_unavailable',401);throw error;}
  requireThat(rows.length===1&&rows[0].result?.collection_id===groupId,'session_unavailable',401);
  return true;
}
// Rebind the request-owned proof at the final Storage start transaction. No
// caller-supplied group, identity or stored hash can replace the active proof.
// Non-native Storage work returns false and retains its existing behavior.
export async function applyStoragePhonePinContext(db,sql){
  const proof=proofs.get(db);if(!proof)return false;
  requireActiveNativeRequest(proof.request);
  const result=await applyPhonePinContext(db,sql,proof.groupId);
  requireActiveNativeRequest(proof.request);return result;
}
const integer=v=>pgInteger(v,{minimum:0,code:'session_unavailable'});
function current(row,installation,profile,now){
  requireThat(row&&row.installation_id===installation&&row.profile===profile,'session_unavailable',401);
  requireId(row.collection_id);requireId(row.principal_user_id);requireRequestId(row.account_id);requireRequestId(row.native_session_id);
  requireThat(Number.isSafeInteger(now)&&now>=0&&integer(row.created_at)-now<=PIN_CLOCK_SKEW_MS&&integer(row.expires_at)>now&&
    ['admin','staff'].includes(row.role)&&Array.isArray(row.capabilities),'session_unavailable',401);
  return Object.freeze({verified:true,authMethod:'phone_pin',groupId:row.collection_id,principalUserId:row.principal_user_id,
    principalSessionId:row.native_session_id,nativeAccountId:row.account_id,installationId:installation,installationProfile:profile});
}
function headers(){return {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Pragma':'no-cache',
  'X-Content-Type-Options':'nosniff','X-BuriMunsi-Contract':CONTRACT_VERSION};}
function correlation(request){
  requireRequestId(request.headers.get('X-BuriMunsi-Request'));
  const generation=request.headers.get('X-BuriMunsi-Generation');
  requireThat(/^(0|[1-9][0-9]{0,15})$/.test(generation??'')&&Number.isSafeInteger(Number(generation)),'invalid_generation',400);
  requireThat(request.headers.get('X-BuriMunsi-Contract')===CONTRACT_VERSION,'contract_version',400);
}

/** Bounded native phone/PIN authentication. Web Admin continues through GoTrue
 * and its own OTP/CAPTCHA path. No Auth identity, BFF session or MFA proof is
 * created. SQL revalidates approved principals and all opaque proof components.
 */
export function createPhonePinRequestGate({secrets,networkBucket,clock=()=>Date.now(),sessionTtlMs=1800000}){
  requireThat(typeof networkBucket==='function'&&typeof clock==='function'&&Number.isSafeInteger(sessionTtlMs)&&
    sessionTtlMs>=60000&&sessionTtlMs<=28800000,'authentication_unconfigured',503);
  // Managed email bootstrap does not invoke PIN authentication. Validate the
  // PIN secret only when this explicit native protocol is actually selected.
  let hasher;
  const pinHasher=()=>hasher??=new PinHasher({pepper:secrets.pinPepper,pepperId:secrets.pinPepperId});
  // An unknown identity performs the same configured derivation after durable
  // admission; this constant record is never an account or usable credential.
  const dummy={algorithm:'pbkdf2-sha256+hmac-v1',pepperId:secrets.pinPepperId,iterations:PIN_ITERATIONS,
    salt:'00000000000000000000000000000000',hash:'0000000000000000000000000000000000000000000000000000000000000000'};
  return async function withPhonePinRequest({request,env},operation){
    const db=env?.DB,work=db?.applicationWork;requirePort(db,['transaction','context','readContext','setClaims']);requirePort(work,['assert']);
    requireThat(!active.has(db),'native_context_busy',503);
    requireThat(request.headers.get('X-BuriMunsi-Auth')==='phone_pin'&&!request.headers.has('X-BuriMunsi-Collect-Session'),'invalid_credentials',401);
    const installation=requireRequestId(request.headers.get('X-BuriMunsi-Installation')),
      profile=request.headers.get('X-BuriMunsi-Profile'),device=request.headers.get('X-BuriMunsi-Device');
    requireThat(['staff','internal_receiver'].includes(profile)&&/^[a-f0-9]{64}$/.test(device??''),'invalid_credentials',401);
    const owned=async()=>{requireActiveNativeRequest(request);requireThat(db.applicationWork===work,'request_not_admitted',503);await work.assert();
      requireThat(db.applicationWork===work,'request_not_admitted',503);requireActiveNativeRequest(request);};
    const transaction=async(write,fn)=>db.transaction(async sql=>{
      await owned();if(write){await db.context(sql);await sql.unsafe(`SELECT pg_advisory_xact_lock(${COLLECT_MUTATION_LOCK}::bigint)`);}
      else{await sql.unsafe('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');await db.readContext(sql,{isolation:'repeatable read'});}
      const result=await fn(sql);await owned();return result;
    });
    active.add(db);const local={...env};delete local.AUTH_ACTOR;delete local.AUTH_VERIFIED;delete local.ADMIN_AUTH_EXCHANGE;
    try{
      db.setClaims({});await owned();
      const url=new URL(request.url),retirement=/^\/v1\/burimunsi\/gateway\/replacements\/([a-f0-9-]{36})\/outcome$/.exec(url.pathname);
      if(request.method==='POST'&&url.pathname==='/v1/burimunsi/session/logout'){
        // The narrow barrier is allowed even when account access is temporarily
        // suspended. It validates exact device proofs and can only revoke them;
        // no general actor or protected data is exposed by this path.
        correlation(request);requireThat(url.search==='','invalid_query',400);
        requireThat((request.headers.get('content-type')??'').split(';')[0].trim()==='application/json','json_required',415);
        const token=(request.headers.get('authorization')??'').match(/^Bearer ([a-f0-9]{64})$/)?.[1];
        requireThat(token,'session_unavailable',401);
        const groupId=requireId(request.headers.get('X-BuriMunsi-Group'));
        const body=parseWire(await readNativeBody(request,{timeoutMs:15000}),8192);validateNativeRequest('logout',body);
        let value;
        try{value=await transaction(true,async sql=>{
          const rows=await sql.unsafe(PIN_LOGOUT_SQL,[token,installation,device,profile,groupId,body.replacementToken??null]);
          requireThat(rows.length===1&&rows[0].result,'session_unavailable',401);return rows[0].result;
        });}catch(error){if(error?.code==='42501')throw new BuriError('session_unavailable',401);throw error;}
        exactKeys(value,['accountId','collectionId']);requireRequestId(value.accountId);
        requireThat(value.collectionId===groupId,'session_unavailable',401);
        const binding=requestBinding(request,installation,groupId);binding.actorId=value.accountId;
        const response=bindNativeResponse({operation:'logout'},binding,body,{signedOut:true});
        await owned();return new Response(JSON.stringify(response),{status:200,headers:headers()});
      }
      if(request.method==='GET'&&retirement){
        // A retired proof is useful only for this historical ACK. Never install
        // a native actor/context, compose ports, disclose data or retry a write.
        correlation(request);requireThat(url.search==='','invalid_query',400);
        const requestId=requireRequestId(retirement[1]),fingerprint=request.headers.get('X-BuriMunsi-Handoff-Fingerprint');
        const token=(request.headers.get('authorization')??'').match(/^Bearer ([a-f0-9]{64})$/)?.[1];
        requireThat(token&&/^[a-f0-9]{64}$/.test(fingerprint??''),'session_unavailable',401);
        let value;
        try{value=await transaction(false,async sql=>{
          requireThat((await sql.unsafe('SELECT pg_is_in_recovery() AS replica'))[0]?.replica===false,'command_primary_required',503);
          const rows=await sql.unsafe(RETIREMENT_OUTCOME_SQL,[token,installation,device,profile,requestId,fingerprint]);
          requireThat(rows.length===1&&rows[0].result,'session_unavailable',401);return rows[0].result;
        });}catch(error){if(error?.code==='42501')throw new BuriError('session_unavailable',401);throw error;}
        exactKeys(value,['kind','collectionId','actorId','sessionId','installationId','profile','requestId','fingerprint','state','ack']);
        requireId(value.collectionId);requireRequestId(value.actorId);requireRequestId(value.sessionId);
        requireThat(value.kind==='gateway_retirement_outcome'&&value.installationId===installation&&value.profile===profile&&
          value.requestId===requestId&&value.fingerprint===fingerprint&&['retired','unknown'].includes(value.state),
          'gateway_outcome_inconsistent',503);
        requireThat(request.headers.get('X-BuriMunsi-Group')===value.collectionId,'native_scope_changed',403);
        const binding=requestBinding(request,installation,value.collectionId);binding.actorId=value.actorId;
        const data={protocol:'burimunsi.receiver-retirement.v1',requestId,fingerprint,state:value.state,ack:value.ack};
        const response=bindNativeResponse({operation:'retirementOutcome',recordId:requestId},binding,null,data,undefined,fingerprint);
        await owned();return new Response(JSON.stringify(response),{status:200,headers:headers()});
      }
      const login=request.method==='POST'&&new URL(request.url).pathname==='/v1/burimunsi/session/login';
      if(login){
        requireThat(!request.headers.has('X-BuriMunsi-Group')&&!request.headers.has('authorization'),'invalid_credentials',401);
        requireThat((request.headers.get('content-type')??'').split(';')[0].trim()==='application/json','json_required',415);
        // Validate request correlation before budget/account access, without any
        // placeholder collection. The real collection is bound only on success.
        correlation(request);
        const body=parseWire(await readNativeBody(request,{timeoutMs:15000}),8192);validateNativeRequest('login',body);
        const phone=normalizePhone(body.phone),pin=requirePin(body.pin),network=await networkBucket(request);await owned();
        requireThat(/^[a-f0-9]{64}$/.test(network??''),'trusted_network_resolver_required',503);
        const now=clock(),phoneHash=await sha256(phone);
        const budget=await transaction(true,async sql=>{
          const rows=await sql.unsafe('SELECT private.burimunsi_pin_login_account($1,$2,$3::uuid,$4,$5) AS result',[phone,phoneHash,installation,network,now]);
          requireThat(rows.length===1&&typeof rows[0].result?.allowed==='boolean','authentication_unavailable',503);return rows[0].result;
        });
        // The denied budget transaction has already committed. No identity read,
        // PBKDF2, registration or session creation happens after denial.
        requireThat(budget.allowed,'try_again_later',429);
        const account=budget.account,verified=await pinHasher().verify(account?phone:'+250780000000',pin,account?.pinHash??dummy);await owned();
        requireThat(verified&&account?.phone===phone&&account.active===true&&account.removed===false,'invalid_credentials',401);
        requireId(account.groupId);requireRequestId(account.id);requireId(account.principalUserId);
        const token=newBearer(),id=crypto.randomUUID(),createdAt=clock(),expiresAt=createdAt+sessionTtlMs;
        const tokenHash=await sha256(token),deviceHash=await sha256(device);
        const created=await transaction(true,async sql=>{
          const rows=await sql.unsafe('SELECT private.burimunsi_pin_create_session($1,$2::uuid,$3::uuid,$4,$5,$6,$7::uuid,$8,$9,$10,$11) AS result',
            [account.groupId,account.id,installation,profile,deviceHash,account.credentialVersion,id,tokenHash,createdAt,expiresAt,account.version]);
          requireThat(rows.length===1&&rows[0].result?.created===true,'invalid_credentials',401);return rows[0].result;
        }).catch(error=>{if(error?.code==='42501')throw new BuriError('invalid_credentials',401);throw error;});
        requireThat(integer(created.expiresAt)>clock()&&integer(created.expiresAt)<=expiresAt,'session_unavailable',401);
        const binding=requestBinding(request,installation,account.groupId);binding.actorId=account.id;
        const data={groupId:account.groupId,token,expiresAt:integer(created.expiresAt),profile:{id:account.id,name:account.name,phone:account.phone,
          role:account.role,capabilities:[...account.capabilities]}};
        return new Response(JSON.stringify(bindNativeResponse({operation:'login'},binding,body,data)),{status:200,headers:headers()});
      }
      const token=(request.headers.get('authorization')??'').match(/^Bearer ([a-f0-9]{64})$/)?.[1];
      requireThat(token,'session_unavailable',401);const values=Object.freeze([token,installation,device,profile]);
      // A passcode change must still work when the short lease has elapsed. It
      // continues through its normal body, current-authority and current-PIN
      // checks after exact proof revalidation.
      // No other business command may use an expired proof.
      const renewing=request.method==='GET'&&url.pathname==='/v1/burimunsi/session'||
        request.method==='POST'&&url.pathname==='/v1/burimunsi/session/passcode';
      if(renewing){correlation(request);requireThat(url.search==='','invalid_query',400);}
      const requestedGroup=request.headers.get('X-BuriMunsi-Group');
      if(renewing)requireId(requestedGroup);
      let principal;
      try{principal=await transaction(renewing,async sql=>{
        const rows=await sql.unsafe(renewing?PIN_RENEW_SQL:PIN_CONTEXT_SQL,
          renewing?[...values,requestedGroup,sessionTtlMs]:values);
        requireThat(rows.length===1,'session_unavailable',401);
        return current(rows[0],installation,profile,clock());
      });}catch(error){if(error?.code==='42501')throw new BuriError('session_unavailable',401);throw error;}
      requireThat(request.headers.get('X-BuriMunsi-Group')===principal.groupId,'native_scope_changed',403);
      proofs.set(db,Object.freeze({groupId:principal.groupId,values,request}));
      const result=await operation(principal,local);await owned();return result;
    }finally{proofs.delete(db);try{db.setClaims({});}finally{active.delete(db);}}
  };
}
