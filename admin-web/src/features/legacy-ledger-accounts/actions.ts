/* eslint-disable no-control-regex -- Validate account details and operator reasons. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {clearPending, pendingAuthority, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {parseLedgerAccountDetail} from '../ledger-accounts/contracts';
import {withPendingFence, type FenceAccess, type FenceLock} from '../operations/pendingFence';

// The new group-version field is deliberately stored under a separate family:
// an older Flutter form cannot understand or safely replay this intent.
const FAMILY = 'legacy-account-create-v2', OLD_FAMILY = 'operating-createaccount', RESOURCE = 'new', PERMISSION = 'ledger.manage';
const BINDING = 'collect.admin.legacy-account-create.context.v2';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/, HASH = /^[a-f0-9]{64}$/;
const id = z.string().regex(UUID), version = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),
  field = (min:number,max:number) => z.string().min(min).max(max).refine(value => value === value.trim() && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value));
const oldBody = z.object({group_id:id, code:field(1,40).regex(/^[A-Za-z0-9_.-]+$/), name:field(2,120),
  account_type:z.enum(['asset','liability','equity','income','expense']), normal_side:z.enum(['debit','credit']), reason:field(8,1000)}).strict();
const bodySchema = oldBody.extend({expected_group_version:version}).strict();
const intentSchema = z.object({model:z.literal('transaction_journals'), body:bodySchema, group_sha256:z.string().regex(HASH)}).strict();
const receiptSchema = z.object({request_id:id,resource_type:z.literal('accounts'),resource_id:id,version:z.literal(1),status:z.literal('succeeded')}).strict();
const bindingSchema = z.object({version:z.literal(1),request_key:id,authority_sha256:z.string().regex(HASH),intent_sha256:z.string().regex(HASH),model:z.literal('transaction_journals')}).strict();

export type AccountBody = z.infer<typeof bodySchema>;
export interface GroupSnapshot {id:string; title:string; status:'draft'|'active'|'suspended'; visibility:'private'|'public_approved'; version:number;}
export interface AccountCreateContext {
  groupId:string; request:AdminRequest; identity:PendingIdentity; actorId:string; permissions:readonly string[];
  financialModel:'transaction_journals'|'canonical_evidence_ledger'; enabled:boolean; isCurrent:()=>boolean; isEnabled?:()=>boolean;
  storage?:Storage; sharedStorage?:Storage; lock?:FenceLock; createKey?:()=>string;
}
export type AccountPending = {kind:'ready';revision:string}|{kind:'owned';requestKey:string;attempt:PendingAttempt|null}|{kind:'legacy';attempt:PendingAttempt}|{kind:'foreign'}|{kind:'conflict'};
export type AccountReceipt = {requestId:string;accountId:string;version:1};
export type AccountResult = {status:'succeeded';receipt:AccountReceipt}|{status:'unknown';requestKey:string}|{status:'existing';pending:AccountPending};
export type AccountLookup = {status:'succeeded';receipt:AccountReceipt;verifiedIntent:boolean}|{status:'not_found';retryAvailable:boolean}|{status:'pending'|'failed'};
function fail(message='The original account request could not be verified.'):never {throw new Error(message);}
function object(value:unknown):value is Record<string,unknown>{return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function exact(value:Record<string,unknown>,keys:string[]){return Object.keys(value).length===keys.length&&keys.every(key=>Object.hasOwn(value,key));}
function check(context:AccountCreateContext){
  const expires=Date.parse(context.identity.expiresAt);
  if(!context.isCurrent()||context.financialModel!=='transaction_journals'||!UUID.test(context.groupId)||!UUID.test(context.actorId)||context.identity.id!==context.actorId||context.identity.role==='staff'||
      !['collections.read','ledger.read',PERMISSION,'overview.read'].every(value=>context.identity.permissions.includes(value)&&context.permissions.includes(value))||!Number.isFinite(expires)||expires<=Date.now()) fail('Ledger account creation is unavailable to your current account.');
}
function write(context:AccountCreateContext){check(context);if(!context.enabled||context.isEnabled&&!context.isEnabled())fail('Ledger account creation is not enabled.');}
class CurrentStorage implements Storage {
  constructor(private readonly context:AccountCreateContext){}
  get length(){return 0;} clear():void{fail();} key():string|null{return null;}
  getItem(key:string){check(this.context);return (this.context.storage??sessionStorage).getItem(key);}
  setItem(key:string,value:string){check(this.context);(this.context.storage??sessionStorage).setItem(key,value);}
  removeItem(key:string){check(this.context);(this.context.storage??sessionStorage).removeItem(key);}
}
function storage(context:AccountCreateContext){return new CurrentStorage(context);}
async function fence<T>(context:AccountCreateContext,work:(access:FenceAccess)=>Promise<T>):Promise<T>{
  check(context);return withPendingFence({identity:context.identity,family:FAMILY,resourceId:RESOURCE,isCurrent:()=>{try{check(context);return true;}catch{return false;}},storage:context.sharedStorage,lock:context.lock},work);
}
function parseAttempt(context:AccountCreateContext,attempt:PendingAttempt){
  if(attempt.family!==FAMILY||attempt.resource_id!==RESOURCE||attempt.permission!==PERMISSION||!UUID.test(attempt.request_key))fail();
  return intentSchema.parse(attempt.intent);
}
async function binding(context:AccountCreateContext,key:string,attempt?:PendingAttempt):Promise<'valid'|'missing'|'foreign'|'mismatch'>{
  const raw=storage(context).getItem(BINDING);if(raw===null)return 'missing';if(raw.length>1000)fail();
  let value:unknown;try{value=JSON.parse(raw);}catch{fail();}const bound=bindingSchema.parse(value);
  if(bound.request_key!==key)fail();
  if(bound.authority_sha256!==await pendingAuthority(context.identity))return 'foreign';
  if(attempt&&bound.intent_sha256!==await sha256Text(JSON.stringify(attempt.intent)))return 'mismatch';check(context);return 'valid';
}
async function saveBinding(context:AccountCreateContext,attempt:PendingAttempt){
  if(await binding(context,attempt.request_key)!=='missing')fail();
  const raw=JSON.stringify({version:1,request_key:attempt.request_key,authority_sha256:await pendingAuthority(context.identity),intent_sha256:await sha256Text(JSON.stringify(attempt.intent)),model:'transaction_journals'});
  check(context);const store=storage(context);store.setItem(BINDING,raw);if(store.getItem(BINDING)!==raw)fail();
}
async function clear(context:AccountCreateContext,access:FenceAccess,saved:Extract<AccountPending,{kind:'owned'}>){
  if(!saved.attempt||await binding(context,saved.requestKey,saved.attempt)!=='valid')fail();
  const store=storage(context);store.removeItem(BINDING);if(store.getItem(BINDING)!==null)fail();
  await clearPending(context.identity,FAMILY,RESOURCE,saved.requestKey,store);check(context);access.clear(saved.requestKey);
}
async function restore(context:AccountCreateContext,access:FenceAccess):Promise<AccountPending>{
  check(context);const shared=access.read();if(shared.kind==='foreign')return {kind:'foreign'};
  const legacy=await readPending(context.identity,OLD_FAMILY,RESOURCE,storage(context));
  const saved=await readPending(context.identity,FAMILY,RESOURCE,storage(context));check(context);
  if(legacy&&(legacy.permission!==PERMISSION||!/^[A-Za-z0-9_.-]{8,200}$/.test(legacy.request_key)))fail();
  if(saved)parseAttempt(context,saved);
  if(legacy&&(shared.kind==='owned'||saved))return {kind:'conflict'};
  if(legacy)return {kind:'legacy',attempt:legacy};
  if(shared.kind==='owned'){if(saved&&saved.request_key!==shared.requestKey)fail();return {kind:'owned',requestKey:shared.requestKey,attempt:saved};}
  if(saved){access.reserve(saved.request_key,shared.revision);return {kind:'owned',requestKey:saved.request_key,attempt:saved};}
  if(storage(context).getItem(BINDING)!==null)fail('Recovery data could not be verified. Check the original request before continuing.');
  return {kind:'ready',revision:shared.revision};
}
export async function restoreAccountCreate(context:AccountCreateContext):Promise<AccountPending>{return fence(context,access=>restore(context,access));}
export async function currentGroup(context:AccountCreateContext):Promise<GroupSnapshot>{
  check(context);const data=await context.request(`operations/groups/${context.groupId}`);check(context);
  if(data.contract_version!==undefined||data.model!==undefined||data.resource_type!=='groups'||data.current_actor_id!==context.actorId||data.can_manage!==true||!object(data.resource))fail('The group could not be verified.');
  const row=data.resource;
  if(row.id!==context.groupId||typeof row.title!=='string'||row.title.trim().length<3||row.title.length>160||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(row.title)||
      !['draft','active','suspended'].includes(String(row.status))||!['private','public_approved'].includes(String(row.visibility))||row.country_code!=='RW'||row.currency!=='RWF'||!version.safeParse(row.version).success)fail('The group could not be verified.');
  return {id:context.groupId,title:row.title,status:row.status as GroupSnapshot['status'],visibility:row.visibility as GroupSnapshot['visibility'],version:row.version as number};
}
export function parseAccountBody(value:unknown):AccountBody{return bodySchema.parse(value);}
async function groupHash(context:AccountCreateContext,group:GroupSnapshot){const result=await sha256Text(JSON.stringify(group));check(context);return result;}
async function verifyAccount(context:AccountCreateContext,receipt:AccountReceipt,body:z.infer<typeof oldBody>){
  const detail=parseLedgerAccountDetail(await context.request(`operations/accounts/${receipt.accountId}`),receipt.accountId,context.actorId,context.identity.role);check(context);
  const row=detail.account;
  if(!detail.canManage||row.group_id!==body.group_id||row.code!==body.code||row.name!==body.name||row.account_type!==body.account_type||row.normal_side!==body.normal_side||
      row.created_by_admin_id!==context.actorId||row.version!==1||row.status!=='active'||row.currency!=='RWF')fail('The created account could not be verified.');
}
function receipt(value:unknown):AccountReceipt {const data=receiptSchema.parse(value);return {requestId:data.request_id,accountId:data.resource_id,version:data.version};}
async function lookup(context:AccountCreateContext,saved:Extract<AccountPending,{kind:'owned'|'legacy'}>):Promise<AccountLookup>{
  const key=saved.kind==='owned'?saved.requestKey:saved.attempt.request_key, body=await context.request(`operations/requests/${key}`);check(context);
  if(body.status==='not_found'&&exact(body,['status'])){
    const retryAvailable=saved.kind==='owned'&&!!saved.attempt&&await binding(context,key,saved.attempt)==='valid'&&parseAttempt(context,saved.attempt).body.group_id===context.groupId;
    return {status:'not_found',retryAvailable};
  }
  if(!exact(body,['status','request_id','receipt'])||typeof body.request_id!=='string'||!UUID.test(body.request_id))fail();
  if((body.status==='pending'||body.status==='failed')&&body.receipt===null)return {status:body.status};
  if(body.status!=='succeeded')fail();const result=receipt(body.receipt);if(result.requestId!==body.request_id)fail();
  if(saved.kind==='legacy'){
    const original=oldBody.safeParse(saved.attempt.intent);if(!original.success)return {status:'succeeded',receipt:result,verifiedIntent:false};
    await verifyAccount(context,result,original.data);return {status:'succeeded',receipt:result,verifiedIntent:true};
  }
  if(!saved.attempt||await binding(context,key,saved.attempt)!=='valid')return {status:'succeeded',receipt:result,verifiedIntent:false};
  await verifyAccount(context,result,parseAttempt(context,saved.attempt).body);return {status:'succeeded',receipt:result,verifiedIntent:true};
}
export async function lookupAccountCreate(context:AccountCreateContext,pending:AccountPending):Promise<AccountLookup>{
  if(pending.kind!=='owned'&&pending.kind!=='legacy')fail();return fence(context,async access=>{
    const saved=await restore(context,access), key=pending.kind==='owned'?pending.requestKey:pending.attempt.request_key;
    if(saved.kind!==pending.kind||(saved.kind==='owned'?saved.requestKey:saved.kind==='legacy'?saved.attempt.request_key:null)!==key)fail();
    if(saved.kind!=='owned'&&saved.kind!=='legacy')fail();const result=await lookup(context,saved);
    if(saved.kind==='owned'&&result.status==='succeeded'&&result.verifiedIntent)await clear(context,access,saved);return result;
  });
}
async function dispatch(context:AccountCreateContext,access:FenceAccess,saved:Extract<AccountPending,{kind:'owned'}>):Promise<AccountResult>{
  if(!saved.attempt||await binding(context,saved.requestKey,saved.attempt)!=='valid')fail();const value=parseAttempt(context,saved.attempt);
  try{
    write(context);const direct=receipt(await context.request('operations/accounts',{method:'POST',body:{...value.body},idempotencyKey:saved.requestKey}));check(context);
    const result=await lookup(context,saved);if(result.status!=='succeeded'||!result.verifiedIntent||JSON.stringify(result.receipt)!==JSON.stringify(direct))fail();
    await clear(context,access,saved);return {status:'succeeded',receipt:direct};
  }catch{return {status:'unknown',requestKey:saved.requestKey};}
}
export async function submitAccountCreate(context:AccountCreateContext,input:unknown,reviewedGroup:GroupSnapshot,observedRevision:string):Promise<AccountResult>{
  write(context);const body=parseAccountBody(input);if(body.group_id!==context.groupId||body.expected_group_version!==reviewedGroup.version||reviewedGroup.id!==context.groupId)fail('Review the selected group.');
  const reviewedHash=await groupHash(context,reviewedGroup);
  return fence(context,async access=>{
    const existing=await restore(context,access);if(existing.kind!=='ready')return {status:'existing',pending:existing};
    const latest=await currentGroup(context);if(await groupHash(context,latest)!==reviewedHash)fail('The group changed. Review the current group.');write(context);
    const key=(context.createKey??(()=>crypto.randomUUID()))();if(!UUID.test(key))fail('A secure request reference is unavailable.');access.reserve(key,observedRevision);
    let attempt:PendingAttempt;
    try{attempt=await retainPending(context.identity,FAMILY,RESOURCE,key,PERMISSION,{model:'transaction_journals',body,group_sha256:reviewedHash},storage(context));await saveBinding(context,attempt);}
    catch{return {status:'unknown',requestKey:key};}
    if(!context.isCurrent()||context.isEnabled&&!context.isEnabled())return {status:'unknown',requestKey:key};return dispatch(context,access,{kind:'owned',requestKey:key,attempt});
  });
}
export async function retryAccountCreate(context:AccountCreateContext,pending:AccountPending):Promise<AccountResult>{
  write(context);if(pending.kind!=='owned'||!pending.attempt)fail('The original account intent is unavailable.');
  return fence(context,async access=>{
    const saved=await restore(context,access);if(saved.kind!=='owned'||!saved.attempt||saved.requestKey!==pending.requestKey||JSON.stringify(saved.attempt.intent)!==JSON.stringify(pending.attempt?.intent)||await binding(context,saved.requestKey,saved.attempt)!=='valid')fail();
    const original=parseAttempt(context,saved.attempt);if(original.body.group_id!==context.groupId)fail('Open the original group before retrying.');
    const result=await lookup(context,saved);if(result.status==='succeeded'&&result.verifiedIntent){await clear(context,access,saved);return {status:'succeeded',receipt:result.receipt};}
    if(result.status!=='not_found'||!result.retryAvailable)fail('The original request remains unresolved.');
    if(await groupHash(context,await currentGroup(context))!==original.group_sha256)fail('The group changed. Check the original request before continuing.');write(context);return dispatch(context,access,saved);
  });
}
export function originalAccountBody(pending:AccountPending):AccountBody|null {return pending.kind==='owned'&&pending.attempt?intentSchema.parse(pending.attempt.intent).body:null;}
