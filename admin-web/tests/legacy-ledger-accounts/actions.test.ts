import {beforeEach, describe, expect, it, vi} from 'vitest';
import {PENDING_KEY, readPending, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {currentGroup, lookupAccountCreate, restoreAccountCreate, retryAccountCreate, submitAccountCreate, type AccountCreateContext} from '../../src/features/legacy-ledger-accounts/actions';

const actor='11111111-1111-4111-8111-111111111111',group='22222222-2222-4222-8222-222222222222',account='33333333-3333-4333-8333-333333333333',key='44444444-4444-4444-8444-444444444444',operation='55555555-5555-4555-8555-555555555555';
const reason='Create the group ledger account', body={group_id:group,code:'1000',name:'Cash control',account_type:'asset' as const,normal_side:'debit' as const,reason,expected_group_version:2};
const savedReceipt={request_id:operation,resource_type:'accounts',resource_id:account,version:1,status:'succeeded'};
const groupDetail={resource_type:'groups',current_actor_id:actor,can_manage:true,resource:{id:group,title:'Fixture group',status:'active',visibility:'private',version:2,country_code:'RW',currency:'RWF'}};
const accountDetail={resource_type:'accounts',current_actor_id:actor,can_manage:true,related:{},related_pages:{},related_truncated:false,resource:{id:account,group_id:group,code:'1000',name:'Cash control',account_type:'asset',normal_side:'debit',currency:'RWF',status:'active',created_by_admin_id:actor,created_at:1790000000,version:1}};
function identity():PendingIdentity{return {id:actor,sessionId:'session-1',email:'admin@example.test',role:'admin',permissions:['collections.read','ledger.read','ledger.manage','overview.read'],expiresAt:new Date(Date.now()+3600000).toISOString()};}
function context(request:AccountCreateContext['request']):AccountCreateContext{return {groupId:group,request,identity:identity(),actorId:actor,permissions:identity().permissions,financialModel:'transaction_journals',enabled:true,isCurrent:()=>true,storage:sessionStorage,sharedStorage:localStorage,lock:async(_name,work)=>work(),createKey:()=>key};}
async function setup(ctx:AccountCreateContext){const pending=await restoreAccountCreate(ctx);if(pending.kind!=='ready')throw new Error('expected ready');return {revision:pending.revision,group:await currentGroup(ctx)};}
beforeEach(()=>{sessionStorage.clear();localStorage.clear();});

describe('legacy ledger account creation',()=>{
  it('requires explicit enablement, current matching authority and all read/manage permissions',async()=>{
    const request=vi.fn(),ctx=context(request),source={id:group,title:'Fixture group',status:'active' as const,visibility:'private' as const,version:2};
    await expect(submitAccountCreate({...ctx,enabled:false},body,source,'')).rejects.toThrow(/not enabled/);
    await expect(submitAccountCreate({...ctx,financialModel:'canonical_evidence_ledger'},body,source,'')).rejects.toThrow(/unavailable/);
    await expect(submitAccountCreate({...ctx,identity:{...ctx.identity,role:'staff'}},body,source,'')).rejects.toThrow(/unavailable/);
    await expect(submitAccountCreate({...ctx,permissions:['ledger.manage']},body,source,'')).rejects.toThrow(/unavailable/);
    await expect(submitAccountCreate({...ctx,isCurrent:()=>false},body,source,'')).rejects.toThrow(/unavailable/);
    expect(request).not.toHaveBeenCalled();
  });
  it('validates the reviewed group, persists the original guarded intent, and verifies the actor-scoped receipt and account',async()=>{
    let posted=false;
    const request=vi.fn(async(path:string,options?:{body?:unknown;idempotencyKey?:string})=>{
      if(path==='operations/accounts'){
        expect(options).toEqual({method:'POST',body,idempotencyKey:key});
        expect(await readPending(identity(),'legacy-account-create-v2','new')).toMatchObject({request_key:key,intent:{model:'transaction_journals',body}});
        posted=true;return savedReceipt;
      }
      if(path.includes('operations/requests/'))return {status:'succeeded',request_id:operation,receipt:savedReceipt};
      if(path.includes('operations/accounts/'))return accountDetail;
      return groupDetail;
    });
    const ctx=context(request),source=await setup(ctx);
    expect(await submitAccountCreate(ctx,body,source.group,source.revision)).toEqual({status:'succeeded',receipt:{requestId:operation,accountId:account,version:1}});
    expect(posted).toBe(true);expect(await readPending(identity(),'legacy-account-create-v2','new')).toBeNull();
  });
  it('refuses an archived, changed, misidentified or stale group before posting',async()=>{
    let data:Record<string,unknown>=groupDetail;
    const request=vi.fn(async(_path:string)=>data),ctx=context(request),source=await setup(ctx);
    data={...groupDetail,resource:{...groupDetail.resource,version:3}};
    await expect(submitAccountCreate(ctx,body,source.group,source.revision)).rejects.toThrow(/group changed/i);
    data={...groupDetail,resource:{...groupDetail.resource,status:'archived'}};
    await expect(currentGroup(ctx)).rejects.toThrow(/group could not be verified/i);
    data={...groupDetail,current_actor_id:account};await expect(currentGroup(ctx)).rejects.toThrow(/group could not be verified/i);
    expect(request.mock.calls.every(call=>String(call[0]).startsWith('operations/groups/'))).toBe(true);
  });
  it('retains a lost result, permits checking with writes off, and retries the exact original key after another lookup',async()=>{
    let posts=0;
    const request=vi.fn(async(path:string,options?:{body?:unknown;idempotencyKey?:string})=>{
      if(path==='operations/accounts'){posts++;expect(options?.idempotencyKey).toBe(key);if(posts===1)throw new Error('lost response');return savedReceipt;}
      if(path.includes('operations/requests/'))return posts>1?{status:'succeeded',request_id:operation,receipt:savedReceipt}:{status:'not_found'};
      if(path.includes('operations/accounts/'))return accountDetail;return groupDetail;
    });
    const ctx=context(request),source=await setup(ctx);
    expect(await submitAccountCreate(ctx,body,source.group,source.revision)).toEqual({status:'unknown',requestKey:key});
    const pending=await restoreAccountCreate(ctx);
    expect(await lookupAccountCreate({...ctx,enabled:false},pending)).toEqual({status:'not_found',retryAvailable:true});
    expect(await retryAccountCreate(ctx,pending)).toEqual({status:'succeeded',receipt:{requestId:operation,accountId:account,version:1}});
    const sent=request.mock.calls.filter(call=>call[0]==='operations/accounts');expect(sent).toHaveLength(2);expect(sent[0][1]).toEqual(sent[1][1]);
  });
  it('does not retry after group change, intent tampering or lost ownership binding',async()=>{
    let changed=false;
    const request=vi.fn(async(path:string)=>path==='operations/accounts'?Promise.reject(new Error('lost')):path.includes('operations/requests/')?{status:'not_found'}:changed?{...groupDetail,resource:{...groupDetail.resource,version:3}}:groupDetail);
    const ctx=context(request),source=await setup(ctx);await submitAccountCreate(ctx,body,source.group,source.revision);
    const pending=await restoreAccountCreate(ctx);changed=true;await expect(retryAccountCreate(ctx,pending)).rejects.toThrow(/group changed/i);
    sessionStorage.removeItem('collect.admin.legacy-account-create.context.v2');
    expect(await lookupAccountCreate(ctx,pending)).toEqual({status:'not_found',retryAvailable:false});
    await expect(retryAccountCreate(ctx,pending)).rejects.toThrow();expect(request.mock.calls.filter(call=>call[0]==='operations/accounts')).toHaveLength(1);
  });
  it('makes old Flutter attempts check-only, blocks new writes, and leaves the older checkpoint intact',async()=>{
    const {expected_group_version,...old}=body;void expected_group_version;
    await retainPending(identity(),'operating-createaccount','new',key,'ledger.manage',old);
    const request=vi.fn(async()=>({status:'not_found'})),ctx=context(request),pending=await restoreAccountCreate(ctx);
    expect(pending.kind).toBe('legacy');expect(await lookupAccountCreate(ctx,pending)).toEqual({status:'not_found',retryAvailable:false});
    await expect(retryAccountCreate(ctx,pending)).rejects.toThrow(/intent is unavailable/);
    expect(await readPending(identity(),'operating-createaccount','new')).toMatchObject({request_key:key});expect(request).toHaveBeenCalledOnce();
  });
  it('checks a completed Flutter request against the created account without clearing the older checkpoint',async()=>{
    const {expected_group_version,...old}=body;void expected_group_version;
    await retainPending(identity(),'operating-createaccount','new',key,'ledger.manage',old);
    const request=vi.fn(async(path:string)=>path.includes('operations/requests/')?{status:'succeeded',request_id:operation,receipt:savedReceipt}:accountDetail),ctx=context(request),pending=await restoreAccountCreate(ctx);
    expect(await lookupAccountCreate(ctx,pending)).toEqual({status:'succeeded',receipt:{requestId:operation,accountId:account,version:1},verifiedIntent:true});
    expect(await readPending(identity(),'operating-createaccount','new')).toMatchObject({request_key:key});
  });
  it('does not retry if the stored intent changes after its binding was saved',async()=>{
    const request=vi.fn(async(path:string)=>path==='operations/accounts'?Promise.reject(new Error('lost')):path.includes('operations/requests/')?{status:'not_found'}:groupDetail);
    const ctx=context(request),source=await setup(ctx);await submitAccountCreate(ctx,body,source.group,source.revision);
    const envelope=JSON.parse(sessionStorage.getItem(PENDING_KEY)!);envelope.entries[0].intent.body.name='Altered account';sessionStorage.setItem(PENDING_KEY,JSON.stringify(envelope));
    const pending=await restoreAccountCreate(ctx);expect(await lookupAccountCreate(ctx,pending)).toEqual({status:'not_found',retryAvailable:false});
    await expect(retryAccountCreate(ctx,pending)).rejects.toThrow();expect(request.mock.calls.filter(call=>call[0]==='operations/accounts')).toHaveLength(1);
  });
  it('keeps a missing-intent fence check-only and refuses a foreign authority',async()=>{
    const request=vi.fn(async(path:string)=>path==='operations/accounts'?Promise.reject(new Error('lost')):path.includes('operations/requests/')?{status:'succeeded',request_id:operation,receipt:savedReceipt}:groupDetail);
    const ctx=context(request),source=await setup(ctx);await submitAccountCreate(ctx,body,source.group,source.revision);sessionStorage.clear();
    const pending=await restoreAccountCreate(ctx);expect(pending).toEqual({kind:'owned',requestKey:key,attempt:null});
    expect(await lookupAccountCreate({...ctx,enabled:false},pending)).toEqual({status:'succeeded',receipt:{requestId:operation,accountId:account,version:1},verifiedIntent:false});
    expect((await restoreAccountCreate(ctx)).kind).toBe('owned');
    expect(await restoreAccountCreate({...ctx,identity:{...ctx.identity,sessionId:'another-session'}})).toEqual({kind:'foreign'});
  });
  it('does not clear an attempt for a mismatched lookup or unexpected created account',async()=>{
    const request=vi.fn(async(path:string)=>path==='operations/accounts'?savedReceipt:path.includes('operations/requests/')?{status:'succeeded',request_id:operation,receipt:savedReceipt}:path.includes('operations/accounts/')?{...accountDetail,resource:{...accountDetail.resource,group_id:account}}:groupDetail);
    const ctx=context(request),source=await setup(ctx);
    expect(await submitAccountCreate(ctx,body,source.group,source.revision)).toEqual({status:'unknown',requestKey:key});
    expect((await restoreAccountCreate(ctx)).kind).toBe('owned');
  });
});
