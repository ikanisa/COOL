/* eslint-disable no-control-regex -- Reject control characters in source records. */
import type {AdminRequest} from '../../api/client';
import {listPending,type PendingIdentity} from './pendingAttempt';

// Read-only preparation for the legacy model. It does not call a transfer or
// membership mutation, and must not be used as evidence of commit-time state.
const UUID=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const roles=['owner','admin','receiver','member','contributor','viewer'];
const states=['active','invited','removed','left'];
const permissions=['overview.read','collections.read','collections.manage','users.read','users.manage'];
function fail():never {throw new Error('Ownership review is unavailable.');}
const object=(x:unknown):x is Record<string,unknown>=>!!x&&typeof x==='object'&&!Array.isArray(x);
const version=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>0&&x<Number.MAX_SAFE_INTEGER;
const name=(x:unknown):x is string=>typeof x==='string'&&x===x.trim()&&x.length>=1&&x.length<=160&&!/[\x00-\x1f\x7f]/.test(x);
export interface OwnershipReviewContext {
  request:AdminRequest;groupId:string;actorId:string;role:'owner'|'admin'|'staff';identity:PendingIdentity;
  permissions:readonly string[];financialModel:'transaction_journals'|'canonical_evidence_ledger';
  enabled:boolean;isCurrent:()=>boolean;storage?:Storage;
}
export interface OwnershipMember {id:string;publicId:string;displayName:string|null;role:string;version:number;}
export interface OwnershipReview {group:{id:string;title:string;version:number};owner:OwnershipMember;members:OwnershipMember[];}
export interface OwnershipTarget {owner:OwnershipMember;target:OwnershipMember;ownerVersion:number;targetVersion:number;targetEmail:string;}
export type OwnershipRecovery = {kind:'pending';requestKeys:string[]} | {kind:'ready'};
function check(context:OwnershipReviewContext) {
  const expiry=Date.parse(context.identity.expiresAt);
  if(!context.enabled||!context.isCurrent()||context.financialModel!=='transaction_journals'||!UUID.test(context.groupId)||!UUID.test(context.actorId)||
    context.role==='staff'||context.identity.role!==context.role||context.identity.id!==context.actorId||!context.identity.sessionId||
    !permissions.every(value=>context.permissions.includes(value)&&context.identity.permissions.includes(value))||!Number.isFinite(expiry)||expiry<=Date.now()) fail();
}
function same(a:unknown,b:unknown){return JSON.stringify(a)===JSON.stringify(b);}

/** Check retained entries from this tab only. Other clients remain unqualified. */
export async function ownershipRecovery(context:OwnershipReviewContext):Promise<OwnershipRecovery> {
  check(context);
  const found=await Promise.all([
    listPending(context.identity,'operating-updategroup','collections.manage',context.storage),
    listPending(context.identity,'legacy-group-status-v2','collections.manage',context.storage),
    listPending(context.identity,'operating-updatemembership','users.manage',context.storage),
    listPending(context.identity,'operating-createmembership','users.manage',context.storage),
  ]);check(context);
  const keys=found.flat().filter(entry=>entry.resource_id===context.groupId || entry.resource_id.startsWith(`${context.groupId}:`) ||
    entry.family==='operating-createmembership' && (entry.intent.group_id===context.groupId || typeof entry.intent.group_id!=='string')).map(entry=>entry.request_key);
  return keys.length?{kind:'pending',requestKeys:[...new Set(keys)]}:{kind:'ready'};
}
export async function loadOwnershipReview(context:OwnershipReviewContext):Promise<OwnershipReview> {
  check(context);
  let offset=0,total:number|null=null,group:OwnershipReview['group']|null=null,creator:string|null=null;
  const members:OwnershipMember[]=[],seen=new Set<string>();
  do {
    const query=new URLSearchParams({relation:'memberships',limit:'100',offset:String(offset)});
    const value=await context.request(`operations/groups/${context.groupId}?${query}`);check(context);
    if(value.contract_version!==undefined||value.model!==undefined||value.resource_type!=='groups'||value.current_actor_id!==context.actorId||value.can_manage!==true||
      !object(value.resource)||!object(value.related)||Object.keys(value.related).length!==1||!Array.isArray(value.related.memberships)||
      !object(value.related_pages)||Object.keys(value.related_pages).length!==1||!object(value.related_pages.memberships)) fail();
    const r=value.resource,p=value.related_pages.memberships,rows=value.related.memberships;
    if(r.id!==context.groupId||!name(r.title)||r.title.length<3||r.status!=='active'||r.visibility!=='private'||r.is_platform_sponsored!==0||
      r.country_code!=='RW'||r.currency!=='RWF'||!version(r.version)||typeof r.creator_user_id!=='string'||!UUID.test(r.creator_user_id)||
      Object.keys(p).length!==4||!Number.isSafeInteger(p.total)||typeof p.total!=='number'||p.total<0||p.total>1000||p.limit!==100||p.offset!==offset||
      rows.length!==Math.max(0,Math.min(100,p.total-offset))||p.next_offset!==(offset+rows.length<p.total?offset+rows.length:null)||
      value.related_truncated!==(p.total>rows.length)||total!==null&&p.total!==total) fail();
    const observed={id:context.groupId,title:r.title,version:r.version};
    if(group&&!same(group,observed)||creator!==null&&creator!==r.creator_user_id) fail();
    group=observed;creator=r.creator_user_id;total=p.total;
    for(const row of rows) {
      if(!object(row)||row.group_id!==context.groupId||typeof row.user_id!=='string'||!UUID.test(row.user_id)||seen.has(row.user_id)||
        !roles.includes(String(row.role))||!states.includes(String(row.status))||!version(row.version)||row.group_title!==group.title) fail();
      seen.add(row.user_id);
      if(row.status!=='active') continue;
      if(typeof row.public_id!=='string'||!/^\d{6}$/.test(row.public_id)||!(row.display_name===null||name(row.display_name))||
        row.display_name_recorded!==0&&row.display_name_recorded!==1||(row.display_name_recorded===1)!==(row.display_name!==null)) fail();
      members.push({id:row.user_id,publicId:row.public_id,displayName:row.display_name as string|null,role:String(row.role),version:row.version});
    }
    offset+=rows.length;
  } while(total!==null&&offset<total);
  if(!group||total===null||seen.size!==total) fail();
  const owners=members.filter(value=>value.role==='owner');
  if(owners.length!==1||owners[0].id!==creator) fail();
  return {group,owner:owners[0],members:members.filter(value=>value.role!=='owner')};
}
async function person(context:OwnershipReviewContext,entry:OwnershipMember) {
  const value=await context.request(`operations/users/${entry.id}`);check(context);
  if(value.contract_version!==undefined||value.model!==undefined||value.resource_type!=='users'||value.current_actor_id!==context.actorId||!object(value.resource)) fail();
  const row=value.resource;
  if(row.id!==entry.id||row.collect_user_id!==entry.id||row.public_id!==entry.publicId||row.display_name!==entry.displayName||
    row.display_name_recorded!==(entry.displayName!==null)||row.status!=='active'||!version(row.version)||
    !['app','direct'].includes(String(row.member_type))||!(row.email===null||typeof row.email==='string'&&row.email===row.email.trim().toLowerCase()&&
    row.email.length>=3&&row.email.length<=254&&row.email.indexOf('@')>=1&&!/[\x00-\x20\x7f]/.test(row.email))) fail();
  return {version:row.version,email:row.email as string|null,memberType:row.member_type};
}
export async function reviewOwnershipTarget(context:OwnershipReviewContext,initial:OwnershipReview,targetId:string):Promise<OwnershipTarget> {
  check(context);if(!UUID.test(targetId))fail();
  const pending=await ownershipRecovery(context);if(pending.kind!=='ready')fail();
  const latest=await loadOwnershipReview(context);if(!same(initial,latest))fail();
  const selected=latest.members.find(value=>value.id===targetId);if(!selected)fail();
  const [owner,target]=await Promise.all([person(context,latest.owner),person(context,selected)]);check(context);
  if(target.memberType!=='app'||target.email===null)fail();
  return {owner:latest.owner,target:selected,ownerVersion:owner.version,targetVersion:target.version,targetEmail:target.email};
}
