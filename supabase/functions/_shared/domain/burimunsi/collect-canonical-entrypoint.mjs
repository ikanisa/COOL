import {verifyToken} from '../../auth-http.js';
import {projectSession} from '../auth.js';
import {applicationWorkTuple} from '../../application-fence.js';
import {validateProviderProfile} from '../momo_pipeline.js';
import {decrypt} from '../encryption.js';
import {createManagedRequestGate} from './managed-request-gate.js';
import {composePostgresNativeRequest,composePostgresNativeWorkers} from './compose-postgres.js';
import {requireThat,BuriError} from './errors.js';
const managedGate=createManagedRequestGate({verifyToken,projectSession,applicationWorkTuple});
function optionsFor(options,env) {
  requireThat(options.config?.canonicalIntegrationEnabled===true&&options.db===env.DB,'canonical_integration_required',503);
  requireThat(options.bridges?.canonical===undefined,'canonical_bridge_conflict',503);
  return {...options,db:env.DB,bridges:{...options.bridges,
    canonical:{env,validateProviderProfile,applicationWorkTuple},
    posting:{...options.bridges.posting,custody:{...options.bridges.posting?.custody,
      decrypt:(sealed,aad)=>decrypt(env,sealed,aad)}}}};
}
/** Call after the existing Collect HTTP authentication/application admission.
 * Never accepts runtime dependencies, group configuration or DB from user JSON.
 */
export async function handleCanonicalNativeRequest(request,options,env) {
  try {
    const url=new URL(request.url);
    requireThat(url.protocol==='https:'&&url.origin===options.config.origin&&url.pathname.startsWith('/v1/burimunsi/'),'origin_denied',403);
    return await managedGate({request,env,groupId:options.config.groupId},async(_binding,local)=>
      composePostgresNativeRequest(optionsFor(options,local))(request));
  } catch(error) {
    const known=error instanceof BuriError;
    return new Response(JSON.stringify({ok:false,error:{code:known?error.code:'canonical_integration_unavailable'}}),
      {status:known?error.status:503,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Pragma':'no-cache'}});
  }
}
/** Not an unauthenticated HTTP job endpoint. The existing scheduler must open a
 * genuine kind=jobs context and supply its approved managed access credential.
 * No cron registration or provider credential issuance is performed here.
 */
export async function runCanonicalScheduledCycle({options,env,managedAccessToken,owner,
 receiptLimit=20,rematchLimit=options.config.rematchEnabled?5:0,targetsPerJob=20,leaseMs=180000,budgetMs=30000}) {
  const work=env.DB?.applicationWork;applicationWorkTuple(work);
  requireThat(work.kind==='jobs','worker_admission_required',503);
  const request=new Request(options.config.origin+'/internal/burimunsi-scheduler',
    {headers:{'X-BuriMunsi-Collect-Session':managedAccessToken}});
  return managedGate({request,env,groupId:options.config.groupId},async(_binding,local)=>{
    const workers=composePostgresNativeWorkers(optionsFor(options,local));
    return workers.runScheduledCycle({owner,receiptLimit,rematchLimit,targetsPerJob,leaseMs,budgetMs});
  });
}
