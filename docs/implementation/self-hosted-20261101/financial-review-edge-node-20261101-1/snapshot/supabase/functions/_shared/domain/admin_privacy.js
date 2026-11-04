import {ApiError,json,readJson,requirePermission} from './core.js';
import {privacyRpc} from './privacy.js';
import {privacyRetentionRpc,retentionRpcNames} from './privacy_retention_rpc.js';

const reviewOperations=Object.freeze([
 'admin_list_account_deletion_reviews_v1','admin_get_account_deletion_review_v1',
 'admin_claim_account_deletion_review_v1','admin_record_account_deletion_review_v1',
 'admin_get_account_deletion_review_operation_v1',
]);
export async function adminPrivacyRoute(request,env,actor,parts){
 requirePermission(actor,'privacy.review');
 if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','Use the authenticated privacy workspace.');
 if(parts.length!==1||new URL(request.url).search||!reviewOperations.includes(parts[0])&&!retentionRpcNames.includes(parts[0]))
  throw new ApiError(404,'privacy_operation_unavailable','This privacy operation is unavailable.');
 const body=await readJson(request,16384),operation=parts[0];
 const result=await (retentionRpcNames.includes(operation)?privacyRetentionRpc:privacyRpc)(operation,body,env,actor);
 if(!result.handled)throw new Error('Registered privacy operation has no handler.');
 return json(result.value);
}
