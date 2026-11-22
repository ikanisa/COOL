import {requireThat} from './errors.js';
import {requireId,requireRequestId,exactKeys} from './values.js';

export const GATEWAY_REPLACEMENT='burimunsi.gateway.replace';
export const GATEWAY_OUTCOME_SQL=`SELECT r.collection_id,r.actor_id,r.request_id,r.operation,r.response
 FROM private.burimunsi_command_receipts r
 JOIN private.burimunsi_sessions origin ON origin.id=r.session_id AND origin.account_id=r.actor_id
  AND origin.collection_id=r.collection_id AND origin.principal_user_id=$4
 WHERE r.collection_id=$1 AND r.actor_id=$2::uuid AND r.request_id=$3::uuid LIMIT 2`;

/** Historical control-plane commit, never proof of pairing, delivery or capture. */
export function gatewayReplacementResponse(value){
 exactKeys(value,['id','installationId','receivingAccountId']);
 requireRequestId(value.id);requireRequestId(value.installationId);requireId(value.receivingAccountId);
 return Object.freeze({...value});
}
export async function readGatewayReplacementOutcome(sql,{groupId,actorId,requestId,principalUserId}){
 requireId(groupId);requireRequestId(actorId);requireRequestId(requestId);requireId(principalUserId);
 const rows=await sql.unsafe(GATEWAY_OUTCOME_SQL,[groupId,actorId,requestId,principalUserId]);
 requireThat(rows.length<=1,'gateway_outcome_inconsistent',503);
 if(!rows.length)return null;
 const row=rows[0];
 requireThat(row.collection_id===groupId&&row.actor_id===actorId&&row.request_id===requestId&&
  row.operation===GATEWAY_REPLACEMENT,'gateway_outcome_inconsistent',503);
 return Object.freeze({groupId,actorId,requestId,operation:GATEWAY_REPLACEMENT,state:'committed',
  financialState:'not_applicable',response:gatewayReplacementResponse(row.response)});
}
