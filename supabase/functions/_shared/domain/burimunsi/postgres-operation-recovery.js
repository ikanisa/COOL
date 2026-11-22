import {requireThat} from './errors.js';
import {pgInteger} from './postgres-values.js';

// Shared by authenticated reads and the locked staff-only resolution transaction.
export async function readRecoveryProof(sql,{groupId:g,actorId,currentSessionId,requestId,originDigest}){
          // Current session was freshly admitted by within/reloadActor. The old
          // session supplies identity snapshots only, even after expiry/revocation.
          const rows=await sql.unsafe(`SELECT
            o.id AS origin_session_id,o.collection_id AS origin_group_id,o.account_id AS origin_actor_id,
            o.principal_user_id AS origin_principal_id,o.installation_id AS origin_installation_id,
            o.grant_id AS origin_grant_id,o.grant_version AS origin_grant_version,
            o.token_hash AS origin_token_hash,o.created_at AS origin_created_at,
            c.id AS current_session_id,c.collection_id AS current_group_id,c.account_id AS current_actor_id,
            c.principal_user_id AS current_principal_id,c.installation_id AS current_installation_id,
            c.grant_id AS current_grant_id,c.grant_version AS current_grant_version
            FROM private.burimunsi_sessions c
            JOIN private.burimunsi_sessions o ON o.collection_id=c.collection_id AND o.account_id=c.account_id
            WHERE c.collection_id=$1 AND c.account_id=$2::uuid AND c.id=$3::uuid AND o.token_hash=$4
            LIMIT 2`,[g,actorId,currentSessionId,originDigest]);
          requireThat(rows.length<=1,'invalid_recovery_proof',503);
          if(!rows.length)return null;
          const r=rows[0];
          const origin={sessionId:r.origin_session_id,groupId:r.origin_group_id,actorId:r.origin_actor_id,
            principalUserId:r.origin_principal_id,installationId:r.origin_installation_id,
            grantId:r.origin_grant_id,grantVersion:pgInteger(r.origin_grant_version),
            tokenHash:r.origin_token_hash,createdAt:pgInteger(r.origin_created_at)};
          const current={sessionId:r.current_session_id,groupId:r.current_group_id,actorId:r.current_actor_id,
            principalUserId:r.current_principal_id,installationId:r.current_installation_id,
            grantId:r.current_grant_id,grantVersion:pgInteger(r.current_grant_version)};
          const receipts=await sql.unsafe(`SELECT collection_id,actor_id,request_id,session_id,operation,created_at,
              CASE WHEN operation LIKE 'burimunsi.staff.cancelled.%' THEN response='{}'::jsonb ELSE NULL END AS cancellation_marker_valid
            FROM private.burimunsi_command_receipts
            WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid LIMIT 2`,[g,actorId,requestId]);
          requireThat(receipts.length<=1,'invalid_recovery_receipt',503);
          const x=receipts[0];
          return {origin,current,receipt:x?{groupId:x.collection_id,actorId:x.actor_id,requestId:x.request_id,
            sessionId:x.session_id,operation:x.operation,createdAt:pgInteger(x.created_at),
            cancellationMarkerValid:x.cancellation_marker_valid}:null};
}
