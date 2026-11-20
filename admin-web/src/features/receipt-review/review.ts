/* eslint-disable no-control-regex -- Reject control characters in audit reasons and transaction labels. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import {clearPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {parseMemberDetail, type MemberReceipt} from '../operations/contracts';
import {withPendingFence, type FenceAccess, type FenceLock} from '../operations/pendingFence';

const FAMILY = 'member-receipt-review-v2', PERMISSION = 'payments.manage';
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const text = z.string().min(1).max(1000).refine(value => !/[\x00-\x1f\x7f]/.test(value));
const transactionSchema = z.object({id:z.string().regex(UUID),label:text,version:z.number().int().min(1).max(Number.MAX_SAFE_INTEGER-1),
  amount_rwf:z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),group_id:z.string().regex(UUID),group_name:text,provider_reference:text}).strict();
const receiptSchema = z.object({request_id:z.string().regex(UUID),resource_type:z.literal('member_receipts'),resource_id:z.string().regex(UUID),
  version:z.number().int().min(2).max(Number.MAX_SAFE_INTEGER),status:z.literal('succeeded')}).strict();
export type ReviewTransaction = z.infer<typeof transactionSchema>;
export interface ReceiptReviewContext {
  request:AdminRequest; identity:PendingIdentity; receipt:MemberReceipt; financialModel:'transaction_journals'|'canonical_evidence_ledger';
  canManage:boolean; enabled:boolean; allowAttachment:boolean; isCurrent:()=>boolean; isEnabled?:()=>boolean; attachmentEnabled?:()=>boolean;
  storage?:Storage; sharedStorage?:Storage; lock?:FenceLock; createKey?:()=>string;
}
export type ReceiptReviewPending = {kind:'ready';revision:string}|{kind:'owned';requestKey:string;attempt:PendingAttempt|null}|{kind:'foreign'};
export type ReceiptReviewResult = {status:'succeeded';requestId:string}|{status:'unknown';requestKey:string}|{status:'existing';pending:ReceiptReviewPending};
export type ReceiptReviewLookup = {status:'succeeded';requestId:string;verifiedIntent:boolean}|{status:'not_found';retryAvailable:boolean}|{status:'pending'|'failed'};
export type ReceiptOutcome = 'reviewed'|'rejected';
interface ReviewIntent {
  model:'transaction_journals'; expected_version:number; outcome:ReceiptOutcome; transaction_id:string|null; expected_transaction_version:number|null;
  source_sha256:string; source_user_id:string; reason_sha256:string; transaction_sha256:string|null;
}
function fail(message:string):never {throw new Error(message);}
function object(value:unknown):value is Record<string,unknown>{return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function exact(value:Record<string,unknown>,keys:string[]){return Object.keys(value).length===keys.length&&keys.every(key=>Object.hasOwn(value,key));}
function current(context:ReceiptReviewContext){
  const expiration=Date.parse(context.identity.expiresAt), receipt=context.receipt;
  if(!context.isCurrent()||context.financialModel!=='transaction_journals'||context.identity.role==='staff'||!context.canManage||receipt.source_kind==='capture'||
      !['payments.read',PERMISSION,'overview.read'].every(permission=>context.identity.permissions.includes(permission))||!Number.isFinite(expiration)||expiration<=Date.now()||
      !UUID.test(receipt.id)||!UUID.test(receipt.user_id)||!HASH.test(receipt.body_sha256)) fail('Receipt review is unavailable to your current account.');
}
function write(context:ReceiptReviewContext, attachment:boolean){
  current(context);if(!context.enabled||context.isEnabled&&!context.isEnabled())fail('Receipt review is not enabled.');
  if(attachment&&(!context.allowAttachment||context.attachmentEnabled&&!context.attachmentEnabled()))fail('Transaction attachment is not enabled.');
}
export function reviewReason(value:string):string {
  const reason=value.trim();if(reason.length<8||reason.length>1000||/[\x00-\x1f\x7f]/.test(reason))fail('Enter a reason of 8 to 1000 characters on one line.');return reason;
}
class CurrentStorage implements Storage {
  constructor(private readonly context:ReceiptReviewContext){}
  get length(){return 0;}clear():void{throw new Error('Unsupported recovery operation.');}key():string|null{return null;}
  getItem(key:string):string|null{current(this.context);return (this.context.storage??sessionStorage).getItem(key);}
  setItem(key:string,value:string):void{current(this.context);(this.context.storage??sessionStorage).setItem(key,value);}
  removeItem(key:string):void{current(this.context);(this.context.storage??sessionStorage).removeItem(key);}
}
function storage(context:ReceiptReviewContext){return new CurrentStorage(context);}
async function fence<T>(context:ReceiptReviewContext,work:(access:FenceAccess)=>Promise<T>):Promise<T>{
  current(context);return withPendingFence({identity:context.identity,family:FAMILY,resourceId:context.receipt.id,isCurrent:()=>{try{current(context);return true;}catch{return false;}},storage:context.sharedStorage,lock:context.lock},work);
}
function intent(attempt:PendingAttempt,context:ReceiptReviewContext):ReviewIntent {
  const data=attempt.intent;
  if(attempt.family!==FAMILY||attempt.permission!==PERMISSION||attempt.resource_id!==context.receipt.id||!UUID.test(attempt.request_key)||
    !exact(data,['model','expected_version','outcome','transaction_id','expected_transaction_version','source_sha256','source_user_id','reason_sha256','transaction_sha256'])||
    data.model!=='transaction_journals'||typeof data.expected_version!=='number'||!Number.isSafeInteger(data.expected_version)||data.expected_version<1||data.expected_version>=Number.MAX_SAFE_INTEGER||
    !['reviewed','rejected'].includes(String(data.outcome))||data.source_sha256!==context.receipt.body_sha256||data.source_user_id!==context.receipt.user_id||
    typeof data.reason_sha256!=='string'||!HASH.test(data.reason_sha256))fail('The original receipt review could not be verified.');
  if(data.transaction_id===null){if(data.expected_transaction_version!==null||data.transaction_sha256!==null)fail('The original receipt review could not be verified.');}
  else if(typeof data.transaction_id!=='string'||!UUID.test(data.transaction_id)||data.outcome!=='reviewed'||typeof data.expected_transaction_version!=='number'||
      !Number.isSafeInteger(data.expected_transaction_version)||data.expected_transaction_version<1||data.expected_transaction_version>=Number.MAX_SAFE_INTEGER||
      typeof data.transaction_sha256!=='string'||!HASH.test(data.transaction_sha256))fail('The original receipt review could not be verified.');
  return data as unknown as ReviewIntent;
}
async function restore(context:ReceiptReviewContext,access:FenceAccess):Promise<ReceiptReviewPending>{
  current(context);const state=access.read();if(state.kind==='foreign')return {kind:'foreign'};
  const saved=await readPending(context.identity,FAMILY,context.receipt.id,storage(context));if(saved)intent(saved,context);current(context);
  if(state.kind==='owned'){if(saved&&saved.request_key!==state.requestKey)fail('The original receipt review could not be verified.');return {kind:'owned',requestKey:state.requestKey,attempt:saved};}
  if(saved){access.reserve(saved.request_key,state.revision);return {kind:'owned',requestKey:saved.request_key,attempt:saved};}
  return {kind:'ready',revision:state.revision};
}
export async function restoreReceiptReview(context:ReceiptReviewContext):Promise<ReceiptReviewPending>{return fence(context,access=>restore(context,access));}
function snapshot(value:ReviewTransaction){return JSON.stringify({id:value.id,version:value.version,amount_rwf:value.amount_rwf,group_id:value.group_id,
  group_name:value.group_name,provider_reference:value.provider_reference,label:value.label});}
async function sourceHash(context:ReceiptReviewContext,value:string){const result=await sha256Text(value);current(context);return result;}
export async function searchReceiptTransactions(context:ReceiptReviewContext,search:string):Promise<ReviewTransaction[]>{
  current(context);if(!context.allowAttachment||context.attachmentEnabled&&!context.attachmentEnabled())fail('Transaction attachment is not enabled.');
  const term=search.trim();if(term.length>200||/[\x00-\x1f\x7f]/.test(term))fail('Check the transaction search.');
  const query=new URLSearchParams({search:term,limit:'100'}),body=await context.request(`gateway/receipts/${context.receipt.id}/transactions?${query}`);current(context);
  if(!object(body)||!exact(body,['rows']))fail('Eligible transactions could not be verified.');
  const rows=z.array(transactionSchema).max(100).parse(body.rows);
  if(new Set(rows.map(row=>row.id)).size!==rows.length)fail('Eligible transactions could not be verified.');return rows;
}
async function verifyCurrent(context:ReceiptReviewContext,value:ReviewIntent,selected:ReviewTransaction|null){
  current(context);
  const detail=parseMemberDetail(await context.request(`gateway/receipts/${context.receipt.id}`),context.receipt.id,context.identity.id,false,false);current(context);
  if(!detail.canManage||detail.resource.status!=='needs_review'||detail.resource.version!==value.expected_version||detail.resource.body_sha256!==value.source_sha256||
      detail.resource.user_id!==value.source_user_id||detail.reviews.length!==0)fail('The receipt changed. Check the original request before continuing.');
  if(value.transaction_id!==null){
    if(!selected||selected.id!==value.transaction_id||selected.version!==value.expected_transaction_version||await sourceHash(context,snapshot(selected))!==value.transaction_sha256)fail('Choose the exact originally reviewed transaction.');
    const rows=await searchReceiptTransactions(context,selected.provider_reference),fresh=rows.find(row=>row.id===value.transaction_id);
    if(!fresh||await sourceHash(context,snapshot(fresh))!==value.transaction_sha256)fail('The transaction changed. Check the original request before continuing.');
  }else if(selected!==null)fail('This review did not select a transaction.');
}
function verifiedReceipt(value:unknown,context:ReceiptReviewContext,saved:PendingAttempt|null){
  const result=receiptSchema.parse(value);if(result.resource_id!==context.receipt.id||saved&&result.version!==intent(saved,context).expected_version+1)fail('The receipt review result could not be verified.');return result;
}
async function verifyResult(context:ReceiptReviewContext,saved:PendingAttempt,receipt:z.infer<typeof receiptSchema>){
  const expected=intent(saved,context),detail=parseMemberDetail(await context.request(`gateway/receipts/${context.receipt.id}`),context.receipt.id,context.identity.id,false,false);current(context);
  const matches=detail.reviews.filter(row=>row.actor_admin_id===context.identity.id&&row.outcome===expected.outcome&&row.transaction_id===expected.transaction_id);
  if(detail.resource.status!==expected.outcome||detail.resource.version!==receipt.version||detail.resource.user_id!==expected.source_user_id||
      detail.resource.transaction_id!==expected.transaction_id||detail.resource.body_sha256!==expected.source_sha256||detail.reviews.length!==1||matches.length!==1||await sourceHash(context,matches[0].reason)!==expected.reason_sha256||
      (expected.transaction_id===null?matches[0].evidence_id!==null:matches[0].evidence_id===null))fail('The saved receipt review could not be verified.');
}
async function lookup(context:ReceiptReviewContext,saved:Extract<ReceiptReviewPending,{kind:'owned'}>):Promise<ReceiptReviewLookup>{
  const body=await context.request(`operations/requests/${saved.requestKey}`);current(context);
  if(body.status==='not_found'&&exact(body,['status']))return {status:'not_found',retryAvailable:saved.attempt!==null};
  if(!exact(body,['status','request_id','receipt'])||typeof body.request_id!=='string'||!UUID.test(body.request_id))fail('The original receipt request could not be verified.');
  if((body.status==='pending'||body.status==='failed')&&body.receipt===null)return {status:body.status};
  if(body.status!=='succeeded')fail('The original receipt request could not be verified.');
  const result=verifiedReceipt(body.receipt,context,saved.attempt);if(result.request_id!==body.request_id)fail('The original receipt request could not be verified.');
  if(saved.attempt)await verifyResult(context,saved.attempt,result);
  return {status:'succeeded',requestId:result.request_id,verifiedIntent:saved.attempt!==null};
}
async function clear(context:ReceiptReviewContext,access:FenceAccess,saved:Extract<ReceiptReviewPending,{kind:'owned'}>){
  if(!saved.attempt)fail('The original review intent is unavailable.');
  await clearPending(context.identity,FAMILY,context.receipt.id,saved.requestKey,storage(context));current(context);access.clear(saved.requestKey);
}
async function dispatch(context:ReceiptReviewContext,access:FenceAccess,saved:Extract<ReceiptReviewPending,{kind:'owned'}>,reason:string):Promise<ReceiptReviewResult>{
  if(!saved.attempt)fail('The original review intent is unavailable.');const value=intent(saved.attempt,context);
  if(await sourceHash(context,reviewReason(reason))!==value.reason_sha256)fail('Re-enter the exact original review reason.');
  const body={expected_version:value.expected_version,outcome:value.outcome,transaction_id:value.transaction_id,reason,
    ...(value.transaction_id!==null?{expected_transaction_version:value.expected_transaction_version}:{} )};
  try{
    write(context,value.transaction_id!==null);
    const result=verifiedReceipt(await context.request(`gateway/receipts/${context.receipt.id}/review`,{method:'POST',body,idempotencyKey:saved.requestKey}),context,saved.attempt);
    current(context);
    // A response alone does not bind the receipt to this original key. Confirm
    // the actor-scoped lookup and the retained intent before clearing recovery.
    const original=await lookup(context,saved);
    if(original.status!=='succeeded'||!original.verifiedIntent||original.requestId!==result.request_id)fail('The original review receipt could not be verified.');
    await clear(context,access,saved);return {status:'succeeded',requestId:result.request_id};
  }catch{return {status:'unknown',requestKey:saved.requestKey};}
}
export async function submitReceiptReview(context:ReceiptReviewContext,outcome:ReceiptOutcome,reason:string,selected:ReviewTransaction|null,revealedHash:string,observedRevision:string):Promise<ReceiptReviewResult>{
  write(context,selected!==null);const why=reviewReason(reason),receipt=context.receipt;
  if(revealedHash!==receipt.body_sha256||receipt.status!=='needs_review'||!Number.isSafeInteger(receipt.version)||receipt.version<1||receipt.version>=Number.MAX_SAFE_INTEGER||
      !['reviewed','rejected'].includes(outcome)||outcome==='rejected'&&selected)fail('Review the original receipt and classification.');
  if(selected)selected=transactionSchema.parse(selected);
  const value:ReviewIntent={model:'transaction_journals',expected_version:receipt.version,outcome,transaction_id:selected?.id??null,
    expected_transaction_version:selected?.version??null,source_sha256:receipt.body_sha256,source_user_id:receipt.user_id,
    reason_sha256:await sourceHash(context,why),transaction_sha256:selected?await sourceHash(context,snapshot(selected)):null};
  return fence(context,async access=>{
    const existing=await restore(context,access);if(existing.kind!=='ready')return {status:'existing',pending:existing};
    await verifyCurrent(context,value,selected);write(context,selected!==null);
    const key=(context.createKey??(()=>crypto.randomUUID()))();if(!UUID.test(key))fail('A secure request reference is unavailable.');
    access.reserve(key,observedRevision);let attempt:PendingAttempt;
    try{attempt=await retainPending(context.identity,FAMILY,receipt.id,key,PERMISSION,{...value},storage(context));}
    catch{ return {status:'unknown',requestKey:key}; }
    if(!context.isCurrent()||context.isEnabled&&!context.isEnabled())return {status:'unknown',requestKey:key};
    return dispatch(context,access,{kind:'owned',requestKey:key,attempt},why);
  });
}
export async function lookupReceiptReview(context:ReceiptReviewContext,pending:ReceiptReviewPending):Promise<ReceiptReviewLookup>{
  if(pending.kind!=='owned')fail('The original account must check this request.');
  return fence(context,async access=>{
    const saved=await restore(context,access);if(saved.kind!=='owned'||saved.requestKey!==pending.requestKey)fail('The original review could not be verified.');
    const result=await lookup(context,saved);if(result.status==='succeeded'&&saved.attempt)await clear(context,access,saved);return result;
  });
}
export async function retryReceiptReview(context:ReceiptReviewContext,pending:ReceiptReviewPending,reason:string,selected:ReviewTransaction|null,revealedHash:string):Promise<ReceiptReviewResult>{
  if(pending.kind!=='owned'||!pending.attempt)fail('The original review intent is unavailable.');const previous=pending.attempt.intent;
  return fence(context,async access=>{
    const saved=await restore(context,access);if(saved.kind!=='owned'||!saved.attempt||saved.requestKey!==pending.requestKey||JSON.stringify(saved.attempt.intent)!==JSON.stringify(previous))fail('The original review could not be verified.');
    const original=intent(saved.attempt,context);write(context,original.transaction_id!==null);
    if(revealedHash!==original.source_sha256||await sourceHash(context,reviewReason(reason))!==original.reason_sha256)fail('Review the source and re-enter the exact original reason.');
    const status=await lookup(context,saved);if(status.status==='succeeded'){await clear(context,access,saved);return {status:'succeeded',requestId:status.requestId};}
    if(status.status!=='not_found')fail('The original review remains unresolved.');
    if(selected)selected=transactionSchema.parse(selected);await verifyCurrent(context,original,selected);write(context,original.transaction_id!==null);
    return dispatch(context,access,saved,reviewReason(reason));
  });
}
