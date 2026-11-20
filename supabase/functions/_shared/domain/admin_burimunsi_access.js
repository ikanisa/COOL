import {ApiError,json,readJson,uuid,digest} from './core.js';
import {claimsOf} from '../auth-http.js';
import {adminAccountSession,adminCanonicalActor} from './admin_accounts.js';
import {applicationWork,applicationWorkTuple} from '../application-fence.js';
import {verifyDeploymentProfile} from '../deployment-profile.js';
import {adminSessionOriginMatches} from '../admin-security.js';
import {PostgresNativeAuthority} from './burimunsi/postgres-authority.js';
import {resolveNativeCollection} from './burimunsi/postgres-scope-discovery.js';

const PATH='/api/admin/burimunsi/access';
const denied=()=>{throw new ApiError(403,'burimunsi_access_denied','This Collect account or receiving phone no longer has BuriMunsi access.');};
const unavailable=()=>{throw new ApiError(503,'burimunsi_unavailable','BuriMunsi is not configured for this deployment.');};

/** A device-bound read of the genuine managed access token already in BFF
 * custody. It never creates an identity/session/grant or returns refresh tokens.
 * The device secret stays in the native transport, outside browser JavaScript.
 */
export async function adminBuriMunsiAccess(request,env){
 if(new URL(request.url).pathname!==PATH)return null;
 if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','Use POST.');
 const account=await adminAccountSession(request,env);
 const work=applicationWork(env);
 if(work.kind!=='http_admin'||env.DB?.applicationWork!==work||applicationWorkTuple(work)[2]!==env.BUILD_SOURCE_ID)unavailable();
 const profile=await verifyDeploymentProfile(env);
 // The existing Admin proxy routes to the shared Supabase function. The
 // cookie's verified public Origin, not that internal transport URL, is the
 // Admin identity. logicalRequest deliberately keeps the Supabase URL.
 if(!adminSessionOriginMatches(request,env,profile,account))unavailable();
 const tuple=JSON.stringify(applicationWorkTuple(work));
 const owned=async()=>{await work.assert();if(env.DB?.applicationWork!==work||JSON.stringify(applicationWorkTuple(work))!==tuple)unavailable();};
 await owned();
 const body=await readJson(request,256);
 if(Object.keys(body).length!==1||!Object.hasOwn(body,'installationId'))throw new ApiError(400,'invalid_request','Supply the managed installation identity.');
 const installation=uuid(body.installationId,'installationId');
 if(body.installationId!==installation)throw new ApiError(400,'invalid_request','Use the exact managed installation identity.');
 const deviceToken=request.headers.get('X-BuriMunsi-Device');
 if(typeof deviceToken!=='string'||!/^[a-f0-9]{64}$/.test(deviceToken))denied();
 const actor=await adminCanonicalActor(request,env,account);
 const token=account.supabaseTokens?.access_token,claims=claimsOf(token);
 if(actor.surface!=='admin'||actor.userId!==account.principal_id||actor.sessionId!==account.auth_session_id||
    claims.sub!==account.auth_user_id||claims.session_id!==actor.sessionId)denied();
 let group;try{group=await resolveNativeCollection({env,installationId:installation,deviceToken});}catch{denied();}
 const at=Math.floor(Date.now()/1000),deviceHash=await digest(deviceToken),authority=new PostgresNativeAuthority({db:env.DB,groupId:group});
 const records=await authority.read(tx=>tx.unsafe(`SELECT a.id AS operator_id,a.role AS operator_role,
   a.version AS account_version,a.credential_version,d.profile AS device_profile,d.version AS grant_version,
   c.version AS scope_version,ss.expires_at AS principal_expires_at,s.expires_at AS cookie_expires_at
  FROM private.burimunsi_accounts a
  JOIN private.burimunsi_device_accounts da ON da.account_id=a.id AND da.collection_id=a.collection_id
  JOIN private.burimunsi_device_grants d ON d.id=da.grant_id AND d.collection_id=a.collection_id
  JOIN private.burimunsi_scopes c ON c.collection_id=a.collection_id
  JOIN app.collections g ON g.id=c.collection_id AND g.status='active'
  JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
  JOIN app.admin_principal_links l ON l.user_id=u.id
  JOIN app.admin_users au ON au.id=l.admin_user_id
  JOIN app.admin_sessions s ON s.user_id=au.id AND s.auth_version=au.auth_version
  JOIN app.auth_sessions ss ON ss.id=s.auth_session_id AND ss.user_id=u.id
  WHERE a.collection_id=$1 AND a.principal_user_id=$2 AND a.active AND NOT a.removed
   AND d.installation_id=$3::uuid AND d.token_hash=$4 AND d.active AND c.enabled
   AND d.profile IN ('staff','internal_receiver') AND a.role IN ('staff','admin')
   AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities)
   AND (a.role='staff' OR au.role IN ('owner','admin'))
   AND (d.profile='staff' OR (a.role='admin' AND d.custodian_account_id=a.id))
   AND au.id=$5 AND au.status='active' AND au.role=$6 AND au.auth_version=$7
   AND s.token_hash=$8 AND s.public_id=$9 AND s.origin=$10 AND s.expires_at>$11
   AND ss.id=$12 AND ss.surface='admin' AND ss.revoked_at IS NULL AND ss.expires_at>$11
   AND private.is_managed_session($13::uuid,$12::uuid)`,
  [group,actor.userId,installation,deviceHash,account.id,account.role,account.auth_version,
   account.token_hash,account.public_id,account.origin,at,actor.sessionId,account.auth_user_id]));
 if(records.length!==1)denied();
 const row=records[0],versions=['account_version','credential_version','grant_version','scope_version'].map(k=>Number(row[k]));
 const expires=Math.min(Number(row.principal_expires_at),Number(row.cookie_expires_at),claims.exp);
 if(versions.some(v=>!Number.isSafeInteger(v)||v<1)||!Number.isSafeInteger(expires)||expires<=Math.floor(Date.now()/1000)+30)denied();
 await owned();
 return json({contractVersion:'burimunsi.collect-session.v1',accessToken:token,expiresAt:expires*1000,
  authUserId:claims.sub,principalUserId:actor.userId,principalSessionId:actor.sessionId,
  operatorId:row.operator_id,collectionId:group,installationId:installation,profile:row.device_profile,
  accountVersion:versions[0],credentialVersion:versions[1],grantVersion:versions[2],scopeVersion:versions[3]},
  200,{'Pragma':'no-cache','Cache-Control':'no-store, private','Vary':'Cookie, Origin, X-BuriMunsi-Device'});
}
