import type {Transaction} from './transactions.ts';
export type ReceiptAccess={tokenHash:string;scope:'messages:read'|'messages:write';applicationId?:string};
export class AccessDenied extends Error {constructor(){super('application_unavailable');}}
const SHA=/^[a-f0-9]{64}$/;
function stringList(value:unknown,maximum:number){
 if(typeof value!=='string'||value.length>8192)throw new AccessDenied();let list:unknown;
 try{list=JSON.parse(value);}catch{throw new AccessDenied();}
 if(!Array.isArray(list)||list.length>maximum||list.some(v=>typeof v!=='string'||v.length<1||v.length>128)||new Set(list).size!==list.length)throw new AccessDenied();
 return list as string[];
}
/** Locks the active credential row until this business transaction ends. */
export async function lockReceiptPrincipal(tx:Transaction,access:ReceiptAccess){
 if(!access||!SHA.test(access.tokenHash)||!['messages:read','messages:write'].includes(access.scope))throw new AccessDenied();
 const rows=await tx.query('SELECT application_id,allowed_kinds,scopes FROM collect_sms.applications WHERE token_hash=$1 AND revoked_at IS NULL FOR UPDATE',[access.tokenHash]);
 if(!Array.isArray(rows)||rows.length>1)throw Error('application_lookup_unconfirmed');
 const row=rows[0];if(rows.length===0||typeof row?.application_id!=='string'||row.application_id.length<1||row.application_id.length>200)throw new AccessDenied();
 const kinds=stringList(row.allowed_kinds,16),scopes=stringList(row.scopes,32);
 if(!kinds.includes('receipt')||!scopes.includes(access.scope)||(access.applicationId!==undefined&&access.applicationId!==row.application_id))throw new AccessDenied();
 access.applicationId=row.application_id;return row.application_id as string;
}
/** The only admitted write is the existing immutable receipt insertion. */
export function validateReceiptWrite(text:string,values:unknown[],applicationId:string){
 if(/^\s*SELECT\b/i.test(text))return;
 if(!/^\s*INSERT\b/i.test(text))throw new AccessDenied();
 const match=/^INSERT INTO messages\(([^)]+)\) VALUES\(([^)]+)\)\s*$/.exec(text);
 if(!match)throw new AccessDenied();const columns=match[1].split(',');
 if(new Set(columns).size!==columns.length||columns.length!==values.length||
   values[columns.indexOf('application_id')]!==applicationId||values[columns.indexOf('kind')]!=='receipt')throw new AccessDenied();
}
