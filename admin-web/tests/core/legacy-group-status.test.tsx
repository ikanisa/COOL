import {render,screen,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {LegacyGroupPage} from '../../src/features/core/LegacyGroupPage';
import {PENDING_KEY,readPending,retainPending,type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {lookupLegacyGroupAction,restoreLegacyGroupAction} from '../../src/features/core/legacyGroupActions';
import {buildLegacyGroupStatusIntent,currentLegacyGroupStatusSource,lookupLegacyGroupStatus,restoreLegacyGroupStatus,retryLegacyGroupStatus,submitLegacyGroupStatus,type LegacyGroupStatusContext} from '../../src/features/core/legacyGroupStatus';

const actor='11111111-1111-4111-8111-111111111111',key='22222222-2222-4222-8222-222222222222',requestId='33333333-3333-4333-8333-333333333333',groupId='44444444-4444-4444-8444-444444444444',ownerId='55555555-5555-4555-8555-555555555555',receiverId='66666666-6666-4666-8666-666666666666';
const reason='Review this group status',group={id:groupId,slug:'test-group',title:'Test group',collection_type:'ikimina',description:'',category_subtype:null,purpose_label:null,recurring_cadence:null,suggested_amount_rwf:null,status:'draft',visibility:'private',is_platform_sponsored:0,country_code:'RW',currency:'RWF',version:1};
const owner={id:ownerId,collect_user_id:ownerId,public_id:'123456',display_name:'Recorded owner',display_name_recorded:true,member_type:'app',momo_number:'0788123456',status:'active',version:2};
const receiver={id:receiverId,group_id:groupId,label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:'008000',status:'active',currency:'RWF',rail:'rwanda_momo',version:3};
const membership={group_id:groupId,user_id:ownerId,role:'owner',status:'active',version:4};
function identity():PendingIdentity{return {id:actor,sessionId:'session-1',email:'admin@example.test',role:'admin',permissions:['collections.read','collections.manage','users.read','receivers.read','overview.read'],expiresAt:new Date(Date.now()+3600000).toISOString()};}
function groupResponse(resource:Record<string,unknown>){return {resource_type:'groups',current_actor_id:actor,can_manage:true,resource};}
function related(resource:Record<string,unknown>,type:'memberships'|'payees',values:Record<string,unknown>[]){return {...groupResponse(resource),related:{[type]:values},related_pages:{[type]:{total:values.length,limit:100,offset:0,next_offset:null}},related_truncated:false};}
const serverReceipt={request_id:requestId,resource_type:'groups',resource_id:groupId,version:2,status:'succeeded'};
function fixture(){
  let resource:Record<string,unknown>=group,ownerRow:Record<string,unknown>=owner,receiverRow:Record<string,unknown>=receiver,memberships:Record<string,unknown>[]=[membership],lost=false,committed=false;
  const request=vi.fn(async(path:string,options?:{method?:string;body?:Record<string,unknown>;idempotencyKey?:string})=>{
    if(path.includes('?relation=memberships'))return related(resource,'memberships',memberships);
    if(path.includes('?relation=payees'))return related(resource,'payees',[receiverRow]);
    if(path===`operations/users/${ownerId}`)return {resource_type:'users',current_actor_id:actor,can_manage:true,resource:ownerRow};
    if(path===`operations/payees/${receiverId}`)return {resource_type:'payees',current_actor_id:actor,can_manage:true,resource:receiverRow};
    if(path===`operations/groups/${groupId}`&&options?.method==='PATCH'){
      if(lost)throw new Error('lost');committed=true;resource={...resource,status:options.body?.status,version:2};return serverReceipt;
    }
    if(path===`operations/groups/${groupId}`)return groupResponse(resource);
    if(path===`operations/requests/${key}`)return committed?{status:'succeeded',request_id:requestId,receipt:serverReceipt}:{status:'not_found'};
    throw new Error(`Unexpected ${path}`);
  });
  return {request,lose:()=>{lost=true;},recover:()=>{lost=false;},commit:(status:string)=>{committed=true;resource={...resource,status,version:2};},setGroup:(value:Record<string,unknown>)=>{resource=value;},setOwner:(value:Record<string,unknown>)=>{ownerRow=value;},setReceiver:(value:Record<string,unknown>)=>{receiverRow=value;},setMemberships:(value:Record<string,unknown>[])=>{memberships=value;}};
}
function context(request:LegacyGroupStatusContext['request']):LegacyGroupStatusContext{const actorIdentity=identity();return {mode:'edit',groupId,request,identity:actorIdentity,actorId:actor,permissions:actorIdentity.permissions,financialModel:'transaction_journals',enabled:true,isCurrent:()=>true,verifyFresh:async()=>true,storage:sessionStorage,sharedStorage:localStorage,lock:async(_name,work)=>work(),createKey:()=>key};}
async function setup(ctx:LegacyGroupStatusContext,target:'active'|'draft'|'suspended'|'archived'){const pending=await restoreLegacyGroupStatus(ctx);if(pending.kind!=='ready')throw new Error('expected ready');return {revision:pending.revision,source:await currentLegacyGroupStatusSource(ctx,target)};}
const locks=Object.getOwnPropertyDescriptor(navigator,'locks');
beforeEach(()=>{sessionStorage.clear();localStorage.clear();Object.defineProperty(navigator,'locks',{configurable:true,value:{request:async(name:string,_options:unknown,work:(lock:{name:string})=>Promise<unknown>)=>work({name})}});});
afterEach(()=>{if(locks)Object.defineProperty(navigator,'locks',locks);else Reflect.deleteProperty(navigator,'locks');});

describe('legacy group status actions',()=>{
  it('binds the exact reviewed active owner, membership and receiver versions and verifies the original result',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'active'),intent=buildLegacyGroupStatusIntent(prepared.source,'active',reason);
    expect(intent).toEqual({status:'active',expected_version:1,reason,expected_owner_id:ownerId,expected_owner_version:2,expected_membership_version:4,expected_receiver_id:receiverId,expected_receiver_version:3});
    expect(await submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision)).toEqual({status:'succeeded',receipt:{requestId,groupId,version:2}});
    expect(base.request.mock.calls.find(([,options])=>options?.method==='PATCH')?.[1]).toEqual({method:'PATCH',body:intent,idempotencyKey:key});
    expect(await readPending(identity(),'legacy-group-status-v2',groupId)).toBeNull();
  });
  it('requires separate enablement, fresh verification and the current owner and receiver',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'active'),intent=buildLegacyGroupStatusIntent(prepared.source,'active',reason);
    await expect(submitLegacyGroupStatus({...ctx,enabled:false},intent,prepared.source,prepared.revision)).rejects.toThrow(/not enabled/);
    await expect(submitLegacyGroupStatus({...ctx,verifyFresh:async()=>false},intent,prepared.source,prepared.revision)).rejects.toThrow(/verification/);
    base.setMemberships([]);await expect(currentLegacyGroupStatusSource(ctx,'active')).rejects.toThrow(/owner and receiver/);
    expect(base.request.mock.calls.some(([,options])=>options?.method==='PATCH')).toBe(false);
  });
  it('rejects changed group, owner, membership or receiver before creating a checkpoint',async()=>{
    for(const changed of ['group','owner','membership','receiver']){
      sessionStorage.clear();localStorage.clear();const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'active'),intent=buildLegacyGroupStatusIntent(prepared.source,'active',reason);
      if(changed==='group')base.setGroup({...group,version:2});if(changed==='owner')base.setOwner({...owner,version:3});if(changed==='membership')base.setMemberships([{...membership,version:5}]);if(changed==='receiver')base.setReceiver({...receiver,version:4});
      await expect(submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision)).rejects.toThrow();expect(base.request.mock.calls.some(([,options])=>options?.method==='PATCH')).toBe(false);
    }
  });
  it('supports suspension and permanent archive, refuses archived-group reopening, and requires no activation lookup for suspension',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'suspended');expect(prepared.source.activation).toBeNull();
    expect(base.request.mock.calls.some(([path])=>path.includes('?relation='))).toBe(false);
    const intent=buildLegacyGroupStatusIntent(prepared.source,'suspended',reason);expect(intent).toEqual({status:'suspended',expected_version:1,reason});
    expect((await submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision)).status).toBe('succeeded');
    sessionStorage.clear();localStorage.clear();const archived=fixture(),archiveContext=context(archived.request),archive=await setup(archiveContext,'archived');
    expect((await submitLegacyGroupStatus(archiveContext,buildLegacyGroupStatusIntent(archive.source,'archived',reason),archive.source,archive.revision)).status).toBe('succeeded');
    archived.setGroup({...group,status:'archived',version:3});await expect(currentLegacyGroupStatusSource(archiveContext,'draft')).rejects.toThrow();
  });
  it('recovers an unknown result only with the original key, original source and explicit retry',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'active'),intent=buildLegacyGroupStatusIntent(prepared.source,'active',reason);base.lose();
    expect(await submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision)).toEqual({status:'unknown',requestKey:key});const pending=await restoreLegacyGroupStatus(ctx);
    expect(await lookupLegacyGroupStatus({...ctx,enabled:false},pending)).toEqual({status:'not_found',retryAvailable:true});base.recover();
    expect((await retryLegacyGroupStatus(ctx,pending)).status).toBe('succeeded');
    const posts=base.request.mock.calls.filter(([,options])=>options?.method==='PATCH');expect(posts).toHaveLength(2);expect(posts[0][1]).toEqual(posts[1][1]);
  });
  it('blocks new status changes while an older Flutter group edit is pending',async()=>{
    await retainPending(identity(),'operating-updategroup',groupId,key,'collections.manage',{expected_version:1,status:'active',reason});
    const base=fixture(),ctx=context(base.request);expect(await restoreLegacyGroupStatus(ctx)).toEqual({kind:'older'});
    expect(base.request).not.toHaveBeenCalled();expect(await readPending(identity(),'operating-updategroup',groupId)).not.toBeNull();
  });
  it('shares a group fence with descriptive edits and does not clear an unbound status reference',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'suspended'),intent=buildLegacyGroupStatusIntent(prepared.source,'suspended',reason);base.lose();
    await submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision);expect((await restoreLegacyGroupAction(ctx)).kind).toBe('guarded');
    sessionStorage.clear();const unbound=await restoreLegacyGroupAction(ctx);expect(unbound).toMatchObject({kind:'owned',requestKey:key,attempt:null});
    expect(await lookupLegacyGroupAction(ctx,unbound)).toEqual({status:'not_found',retryAvailable:false});expect((await restoreLegacyGroupStatus(ctx)).kind).toBe('owned');
  });
  it('does not clear a surviving shared fence when a status receipt is found without its intent',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'suspended'),intent=buildLegacyGroupStatusIntent(prepared.source,'suspended',reason);base.lose();
    await submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision);base.commit('suspended');sessionStorage.clear();
    const unbound=await restoreLegacyGroupAction(ctx);expect(unbound).toMatchObject({kind:'owned',requestKey:key,attempt:null});
    expect(await lookupLegacyGroupAction(ctx,unbound)).toEqual({status:'succeeded',receipt:{requestId,groupId,version:2}});
    expect(await restoreLegacyGroupStatus(ctx)).toEqual({kind:'owned',requestKey:key,attempt:null});
  });
  it('retains a check-only reference without dispatch when authority changes during checkpoint storage',async()=>{
    let active=true;
    const storage:Storage={get length(){return sessionStorage.length;},clear:()=>sessionStorage.clear(),key:index=>sessionStorage.key(index),getItem:name=>sessionStorage.getItem(name),removeItem:name=>sessionStorage.removeItem(name),setItem:(name,value)=>{sessionStorage.setItem(name,value);if(name===PENDING_KEY)active=false;}};
    const base=fixture(),ctx={...context(base.request),storage,isCurrent:()=>active},prepared=await setup(ctx,'suspended');
    expect(await submitLegacyGroupStatus(ctx,buildLegacyGroupStatusIntent(prepared.source,'suspended',reason),prepared.source,prepared.revision)).toEqual({status:'unknown',requestKey:key});
    active=true;const pending=await restoreLegacyGroupStatus(ctx);expect(await lookupLegacyGroupStatus(ctx,pending)).toEqual({status:'not_found',retryAvailable:false});
    expect(base.request.mock.calls.some(([,options])=>options?.method==='PATCH')).toBe(false);
  });
  it('keeps a tampered source or changed activation identity check-only',async()=>{
    const base=fixture(),ctx=context(base.request),prepared=await setup(ctx,'active'),intent=buildLegacyGroupStatusIntent(prepared.source,'active',reason);base.lose();await submitLegacyGroupStatus(ctx,intent,prepared.source,prepared.revision);
    const pending=await restoreLegacyGroupStatus(ctx);base.setReceiver({...receiver,version:4});await expect(retryLegacyGroupStatus(ctx,pending)).rejects.toThrow(/changed/);
    const envelope=JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries:Array<{intent:{reason:string}}>};envelope.entries[0].intent.reason='Changed original reason';sessionStorage.setItem(PENDING_KEY,JSON.stringify(envelope));
    expect(await lookupLegacyGroupStatus(ctx,await restoreLegacyGroupStatus(ctx))).toEqual({status:'not_found',retryAvailable:false});
  });
});

describe('separately gated group status UI',()=>{
  it('requires exact activation review and confirmation without enabling descriptive edits',async()=>{
    const base=fixture(),user=userEvent.setup(),actorIdentity=identity(),navigate=vi.fn();
    const request=vi.fn(async(path:string,options?:{method?:string;body?:Record<string,unknown>;idempotencyKey?:string})=>{
      if(options?.method==='PATCH'){expect(options.body).toMatchObject({status:'active',expected_owner_id:ownerId,expected_owner_version:2,expected_membership_version:4,expected_receiver_id:receiverId,expected_receiver_version:3});return base.request(path,options);}
      if(path.startsWith('operations/requests/'))return {status:'succeeded',request_id:requestId,receipt:serverReceipt};return base.request(path,options);
    });
    render(<LegacyGroupPage mode="edit" id={groupId} request={request} identity={actorIdentity} actorId={actor} principalId={null} role="admin" permissions={actorIdentity.permissions} financialModel="transaction_journals" authorityKey="session-1" navigate={navigate} allowStatusChanges verifyFresh={async()=>true}/>);
    await user.type(await screen.findByLabelText('Reason for status change'),reason);await user.click(screen.getByRole('button',{name:'Review status change'}));
    expect(await screen.findByText(/membership version 4/)).toBeVisible();expect(screen.getByRole('button',{name:'Confirm status change'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox',{name:'I reviewed the status and current group records.'}));await user.click(screen.getByRole('button',{name:'Confirm status change'}));
    expect(await screen.findByText('The group status change was recorded.')).toBeVisible();
  });
  it('keeps the status control unavailable by default',async()=>{
    const base=fixture(),actorIdentity=identity();render(<LegacyGroupPage mode="edit" id={groupId} request={base.request} identity={actorIdentity} actorId={actor} principalId={null} role="admin" permissions={actorIdentity.permissions} financialModel="transaction_journals" authorityKey="session-1" navigate={()=>undefined} verifyFresh={async()=>true}/>);
    expect(await screen.findByText('Group changes are not enabled for this workspace.')).toBeVisible();await waitFor(()=>expect(screen.queryByRole('button',{name:'Review status change'})).not.toBeInTheDocument());
    expect(base.request).not.toHaveBeenCalled();
  });
});
