import {passwordHash,validPassword,OWNER_EMAIL} from './security.js';
const uuid=value=>{if(typeof value!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value))throw new TypeError('An explicit UUID is required.');return value.toLowerCase();};
const literal=value=>"'"+value.replace(/'/g,"''")+"'";
// Trusted offline bootstrap ONLY. No HTTP route, email send, standard password,
// matching identity grant, or log output. Persist caller-generated credentials
// privately BEFORE provider execution; retry/readback must retain these IDs.
export async function ownerBootstrapSql({password,approvalReference,displayName='Main administrator',adminUserId,principalUserId,operationId,createdAt=new Date().toISOString()}){
 if(!validPassword(password))throw new TypeError('Use a unique strong password.');
 if(typeof approvalReference!=='string'||approvalReference.length<8||approvalReference.length>200||/[\u0000-\u001f]/.test(approvalReference))throw new TypeError('An explicit bootstrap approval reference is required.');
 if(typeof displayName!=='string'||displayName.length<2||displayName.length>120||/[\u0000-\u001f]/.test(displayName))throw new TypeError('Invalid administrator name.');
 const timestamp=Date.parse(createdAt);if(!Number.isFinite(timestamp)||new Date(timestamp).toISOString()!==createdAt)throw new TypeError('Use a canonical UTC timestamp.');
 const hash=await passwordHash(password);
 const values=[uuid(operationId),uuid(adminUserId),uuid(principalUserId),hash,displayName,approvalReference,createdAt].map(literal);
 return {ownerEmail:OWNER_EMAIL,adminUserId,principalUserId,operationId,
  sql:`INSERT INTO admin_owner_bootstrap_claims(operation_id,admin_user_id,principal_user_id,password_hash,display_name,approval_reference,created_at,created_seconds) VALUES(${values.join(',')},${Math.floor(timestamp/1000)});`,
  readback:{operationId,adminUserId,principalUserId,ownerEmail:OWNER_EMAIL,passwordHash:hash}};
}
