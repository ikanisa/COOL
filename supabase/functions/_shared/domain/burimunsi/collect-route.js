import {verifyToken} from '../../auth-http.js';
import {projectSession,startOtp} from '../auth.js';
import {ApiError} from '../core.js';
import {MANAGED_EMAIL_OTP_PATH,admitManagedEmailOtp} from './managed-email-otp.js';
import {applicationWork,applicationWorkTuple} from '../../application-fence.js';
import {canonicalProfile,validateDeploymentProfile,verifyDeploymentProfile} from '../../deployment-profile.js';
import {createManagedRequestGate} from './managed-request-gate.js';
import {createPhonePinRequestGate} from './phone-pin-request.js';
import {composePostgresNativeRequest} from './compose-postgres.js';
import {BuriError,requireThat} from './errors.js';
import {requireId} from './values.js';
import {CONTRACT_VERSION,ContractViolation,heldObservationOperation} from './wire/native-contract.mjs';
import {discardNativeBody,requireActiveNativeRequest,nativeRequestErrorStatus} from './wire/request-boundary.mjs';

const compositions=new WeakSet();
const HEADERS={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',
  'Pragma':'no-cache','X-Content-Type-Options':'nosniff','X-BuriMunsi-Contract':CONTRACT_VERSION};
function failure(error){
  const native=error instanceof BuriError||error instanceof ApiError,contract=error instanceof ContractViolation;
  const fenced=['application_fenced','application_fence_unavailable'].includes(error?.code);
  const code=contract?error.code.toLowerCase():native||fenced?error.code:'native_service_unavailable';
  const status=contract?nativeRequestErrorStatus(error):native?error.status:503;
  return new Response(JSON.stringify({contractVersion:CONTRACT_VERSION,ok:false,error:{code}}),{status,headers:HEADERS});
}
export function isCollectNativeRoute(request){
  const path=new URL(request.url).pathname;
  return path==='/v1/burimunsi'||path.startsWith('/v1/burimunsi/');
}
// The signed predecessor has no original-consent proof. The deployed catalog
// also lacks the separate verified-status function. Decide before ingress
// buffers an SMS or opens a database, fence, or provider connection.
export function unavailableHeldObservation(request){
  if(!heldObservationOperation(new URL(request.url).pathname))return null;
  discardNativeBody(request);
  return failure(new BuriError('not_found',404));
}

/** Server composition only, installed as env.BURIMUNSI_NATIVE_ROUTE after the
 * ordinary Collect DB/fence admission. Deno environment strings, request JSON,
 * headers and an arbitrary function cannot install a composition.
 *
 * The caller must supply the exact current deployment profile and existing
 * collection ID, explicit enabled canonical flags, PIN/cursor secrets and the
 * trusted network-bucket resolver. bridgeFactory receives THIS request's DB,
 * branded work and verified existing Admin principal; it must supply the real
 * gateway, sourceReader,
 * canonical provider/fence bindings, custody decrypt and preparation media/
 * encryption ports required by createPostgresNativePorts. Missing ports fail
 * closed there. Canonical composition resolves staff only from explicit owner
 * approvals of existing shared Collect identities and installs the canonical
 * shared person/membership commands; injected replacements are rejected.
 * No alternate writer, principal, approval, group or activation is invented.
 *
 * This factory opens no pool, creates no fence, migrates nothing and supplies no
 * separate ledger. The existing shared posting adapters remain the only writer.
 * A generic Supabase installation without Collect's reviewed business schema
 * and BuriMunsi extensions is not a commissioned target for this composition.
 */
export function createCollectNativeRoute({profile,config,bridgeFactory,secrets,networkBucket,resolveGroup,clock=()=>Date.now()}={}){
  const selected=validateDeploymentProfile(profile),identity=canonicalProfile(selected);
  if(resolveGroup===undefined)requireId(config?.groupId);
  else requireThat(typeof resolveGroup==='function'&&config?.groupId===undefined,'collect_adapter_required',503);
  requireThat(config?.enabled===true&&config.canonicalIntegrationEnabled===true,
    'native_service_unconfigured',503);
  requireThat(config.origin===selected.supabase_origin,'native_profile_mismatch',503);
  requireThat(typeof bridgeFactory==='function'&&typeof networkBucket==='function'&&typeof clock==='function',
    'collect_adapter_required',503);
  requireThat(secrets?.pinPepper instanceof Uint8Array&&secrets.cursorKey instanceof Uint8Array,
    'authentication_unconfigured',503);
  const settings=Object.freeze({...config});
  const keys=Object.freeze({...secrets,pinPepper:new Uint8Array(secrets.pinPepper),cursorKey:new Uint8Array(secrets.cursorKey)});
  const withManagedRequest=createManagedRequestGate({verifyToken,projectSession,applicationWorkTuple,clock});
  const withPhonePinRequest=createPhonePinRequestGate({secrets:keys,networkBucket,clock,sessionTtlMs:settings.sessionTtlMs??1800000});
  const handler=async(request,env)=>{
    requireActiveNativeRequest(request);
    const current=await verifyDeploymentProfile(env);
    requireThat(canonicalProfile(current)===identity,'native_profile_mismatch',503);
    // logicalRequest has already removed /functions/v1/collect-api. Its trusted
    // public Supabase origin, not a forwarded header, selects this same service.
    requireThat(new URL(request.url).origin===selected.supabase_origin,'origin_denied',403);
    const db=env?.DB,work=applicationWork(env),tuple=applicationWorkTuple(work);
    requireThat(db?.applicationWork===work&&work.kind==='http_collect'&&tuple[2]===env.BUILD_SOURCE_ID,
      'request_not_admitted',503);
    // Only this exact route precedes managed session verification. Its separate
    // device/identity proof and durable budgets precede any privileged OTP send.
    if(new URL(request.url).pathname===MANAGED_EMAIL_OTP_PATH){
      const {admission,email}=await admitManagedEmailOtp(request,env,{profile:selected,networkBucket});
      const data=await startOtp(env,{email,surface:'admin'},{nativeAdmission:admission});
      requireActiveNativeRequest(request);await work.assert();
      return new Response(JSON.stringify(data),{status:200,headers:HEADERS});
    }
    const compose=async(principal,local)=>{
      requireActiveNativeRequest(request);
      requireThat(local.DB===db&&db.applicationWork===work,'request_not_admitted',503);
      const admission=Object.freeze({verified:true,...principal});
      const bridges=await bridgeFactory(Object.freeze({env:local,db,work,profile:selected,
        groupId:principal.groupId,admission}));
      requireActiveNativeRequest(request);
      await work.assert();
      requireThat(local.DB===db&&db.applicationWork===work,'request_not_admitted',503);
      const native=composePostgresNativeRequest({admission,config:{...settings,groupId:principal.groupId},db,bridges,secrets:keys,networkBucket,clock});
      return native(request);
    };
    // Explicit protocol selection; a missing/invalid managed token never falls
    // back to PIN authority. Both modes retain the same application fence,
    // shared principal checks, collection scope and canonical ledger adapters.
    if(request.headers.get('X-BuriMunsi-Auth')==='phone_pin')return withPhonePinRequest({request,env},compose);
    return withManagedRequest({request,env,groupId:settings.groupId,resolveGroup,requireGroupAssertion:true},compose);
  };
  compositions.add(handler);
  return handler;
}

/** Namespace hook used by the existing Collect dispatcher. Absent/incomplete
 * server configuration returns a native error before ordinary member auth and
 * before touching provider, native account, receipt or financial commands. */
export async function collectNativeRoute(request,env){
  if(!isCollectNativeRoute(request))return null;
  const unavailable=unavailableHeldObservation(request);
  if(unavailable)return unavailable;
  try{
    const handler=env?.BURIMUNSI_NATIVE_ROUTE;
    requireThat(compositions.has(handler),'native_service_unconfigured',503);
    return await handler(request,env);
  }catch(error){return failure(error);}
  finally{discardNativeBody(request);}
}
