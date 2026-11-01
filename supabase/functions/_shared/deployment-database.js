import {resolveDeploymentProfile} from './deployment-profile.js';

// Read-only before admission. A valid public profile cannot accidentally run
// against another deployment's database even if its connection is reachable.
export async function assertRuntimeDeployment(sql,env){
 if(env.COLLECT_DEPLOYMENT_PROFILE===undefined||resolveDeploymentProfile(env).mode!=='self_hosted')return;
 await sql.begin(async tx=>{
  await tx`SET LOCAL ROLE collect_runtime`;
  const rows=await tx`SELECT private.collect_assert_deployment(${env.COLLECT_DEPLOYMENT_PROFILE_SHA256}::text) AS allowed`;
  if(rows.length!==1||rows[0].allowed!==true)throw new Error('deployment_identity_mismatch');
 });
}
