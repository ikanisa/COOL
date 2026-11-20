import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';

const field=(o,k)=>{
 const d=o&&typeof o==='object'&&!Array.isArray(o)?Object.getOwnPropertyDescriptor(o,k):null;
 requireThat(d?.enumerable===true&&Object.hasOwn(d,'value'),'native_grant_invalid',503);return d.value;
};
const record=rows=>{
 requireThat(Array.isArray(rows)&&rows.length===1&&rows[0]?.result&&typeof rows[0].result==='object'&&!Array.isArray(rows[0].result),'native_grant_unavailable',503);
 return rows[0].result;
};
const boundedVersion=v=>typeof v==='string'&&v.length>=1&&v.length<=128&&!/[\u0000-\u001f\u007f]/.test(v);
const owner=v=>typeof v==='string'&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(v);

/** A narrow port for an existing authenticated Admin request. The database
 * repeats the current owner, BFF/session, recent-email, fence and policy checks.
 * A lost response must be reconciled by lookup using the original requestId. */
export class PostgresNativeWorkGrants {
 constructor({authority,actorArgs}){
  requirePort(authority,['write']);requireId(authority.groupId);
  requireThat(Array.isArray(actorArgs)&&actorArgs.length===4&&actorArgs.every(x=>typeof x==='string'&&x.length>0),'native_grant_invalid',503);
  this.authority=authority;this.groupId=authority.groupId;this.actorArgs=Object.freeze([...actorArgs]);Object.freeze(this);
 }
 async issue(input){
  const requestId=field(input,'requestId'),grantId=field(input,'grantId'),workerOwner=field(input,'owner'),version=field(input,'version'),
   policyVersion=field(input,'policyVersion'),expiresAt=field(input,'expiresAt');
  const enabled=Object.hasOwn(input,'enabled')?field(input,'enabled'):false;
  requireRequestId(requestId);requireRequestId(grantId);
  requireThat(owner(workerOwner)&&Number.isSafeInteger(version)&&version>0&&boundedVersion(policyVersion)&&
   Number.isSafeInteger(expiresAt)&&expiresAt>0&&typeof enabled==='boolean','native_grant_invalid',503);
  return this.authority.write(async sql=>{
   const r=record(await sql.unsafe('SELECT private.burimunsi_native_grant_issue($1,$2,$3,$4,$5,$6::uuid,$7::uuid,$8,$9::bigint,$10,$11::bigint,$12::boolean) AS result',
    [...this.actorArgs,this.groupId,requestId,grantId,workerOwner,version,policyVersion,expiresAt,enabled]));
   requireThat(field(r,'groupId')===this.groupId&&field(r,'grantId')===grantId&&field(r,'owner')===workerOwner&&
    pgInteger(field(r,'version'),{minimum:1,code:'native_grant_unavailable'})===version&&field(r,'enabled')===enabled&&
    pgInteger(field(r,'expiresAt'),{minimum:1,code:'native_grant_unavailable'})===expiresAt,'native_grant_unavailable',503);
   return Object.freeze({grantId,groupId:this.groupId,owner:workerOwner,version,enabled,expiresAt});
  });
 }
 async revoke(input){
  const requestId=field(input,'requestId'),grantId=field(input,'grantId');
  requireRequestId(requestId);requireRequestId(grantId);
  return this.authority.write(async sql=>{
   const r=record(await sql.unsafe('SELECT private.burimunsi_native_grant_revoke($1,$2,$3,$4,$5,$6::uuid,$7::uuid) AS result',
    [...this.actorArgs,this.groupId,requestId,grantId]));
   requireThat(field(r,'groupId')===this.groupId&&field(r,'grantId')===grantId&&field(r,'revoked')===true&&typeof field(r,'applied')==='boolean','native_grant_unavailable',503);
   return Object.freeze({grantId,groupId:this.groupId,revoked:true,applied:r.applied});
  });
 }
 async lookup(requestId){
  requireRequestId(requestId);
  return this.authority.write(async sql=>{
   const r=record(await sql.unsafe('SELECT private.burimunsi_native_grant_command($1,$2,$3,$4,$5,$6::uuid) AS result',
    [...this.actorArgs,this.groupId,requestId]));
   const found=field(r,'found');requireThat(typeof found==='boolean','native_grant_unavailable',503);
   if(!found)return Object.freeze({found:false});
   const operation=field(r,'operation'),receipt=field(r,'receipt');
   requireThat(['issue','revoke'].includes(operation)&&receipt&&typeof receipt==='object'&&!Array.isArray(receipt)&&
    field(receipt,'groupId')===this.groupId,'native_grant_unavailable',503);
   const grantId=field(receipt,'grantId');requireRequestId(grantId);
   if(operation==='revoke'){
    const revoked=field(receipt,'revoked'),applied=field(receipt,'applied');
    requireThat(revoked===true&&typeof applied==='boolean','native_grant_unavailable',503);
    return Object.freeze({found:true,operation,receipt:Object.freeze({grantId,groupId:this.groupId,revoked,applied})});
   }
   const workerOwner=field(receipt,'owner'),version=pgInteger(field(receipt,'version'),{minimum:1,code:'native_grant_unavailable'}),
    enabled=field(receipt,'enabled'),expiresAt=pgInteger(field(receipt,'expiresAt'),{minimum:1,code:'native_grant_unavailable'});
   requireThat(owner(workerOwner)&&typeof enabled==='boolean','native_grant_unavailable',503);
   return Object.freeze({found:true,operation,receipt:Object.freeze({grantId,groupId:this.groupId,owner:workerOwner,version,enabled,expiresAt})});
  });
 }
}
