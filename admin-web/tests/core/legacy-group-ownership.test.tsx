import {render,screen,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {beforeEach,describe,expect,it,vi} from 'vitest';
import {LegacyGroupOwnershipReview} from '../../src/features/core/LegacyGroupOwnershipReview';
import {loadOwnershipReview,ownershipRecovery,reviewOwnershipTarget,type OwnershipReviewContext} from '../../src/features/core/legacyGroupOwnership';
import {PENDING_KEY,retainPending,type PendingIdentity} from '../../src/features/core/pendingAttempt';
import type {FeatureAccess} from '../../src/features/core/types';

const actor='11111111-1111-4111-8111-111111111111',group='22222222-2222-4222-8222-222222222222',owner='33333333-3333-4333-8333-333333333333',target='44444444-4444-4444-8444-444444444444',key='55555555-5555-4555-8555-555555555555';
const identity:PendingIdentity={id:actor,sessionId:'session-1',email:'admin@example.test',role:'admin',permissions:['overview.read','collections.read','collections.manage','users.read','users.manage'],expiresAt:'2100-01-01T00:00:00Z'};
const groupRow={id:group,title:'Synthetic group',version:3,status:'active',visibility:'private',is_platform_sponsored:0,country_code:'RW',currency:'RWF',creator_user_id:owner};
const ownerRow={group_id:group,user_id:owner,role:'owner',status:'active',version:2,group_title:'Synthetic group',public_id:'123456',display_name:'First owner',display_name_recorded:1};
const targetRow={...ownerRow,user_id:target,role:'member',version:4,public_id:'654321',display_name:'Second member'};
const detail=(rows:unknown[]=[ownerRow,targetRow])=>({resource_type:'groups',current_actor_id:actor,can_manage:true,resource:groupRow,related:{memberships:rows},
  related_pages:{memberships:{total:rows.length,limit:100,offset:0,next_offset:null}},related_truncated:false});
const user=(id:string)=>({resource_type:'users',current_actor_id:actor,can_manage:true,resource:{id,collect_user_id:id,status:'active',member_type:'app',
  public_id:id===owner?'123456':'654321',display_name:id===owner?'First owner':'Second member',display_name_recorded:true,
  email:id===owner?'first@example.test':'second@example.test',version:id===owner?3:5}});
function fixture(){return vi.fn(async(path:string,options?:{method?:string})=>{expect(options?.method??'GET').toBe('GET');return path.startsWith('operations/groups/')?detail():user(path.endsWith(owner)?owner:target);});}
function context(request:OwnershipReviewContext['request']):OwnershipReviewContext{return {request,groupId:group,actorId:actor,role:'admin',identity,permissions:identity.permissions,
  financialModel:'transaction_journals',enabled:true,isCurrent:()=>true,storage:sessionStorage};}
function props(request:FeatureAccess['request']){return {groupId:group,request,actorId:actor,role:'admin' as const,identity,permissions:identity.permissions,principalId:null,
  financialModel:'transaction_journals' as const,authorityKey:'session-1',navigate:vi.fn()};}
beforeEach(()=>{sessionStorage.clear();localStorage.clear();});

describe('legacy ownership review preparation',()=>{
  it('is default-off and does not contact a backend or expose a transfer action',()=>{
    const request=fixture();const {container}=render(<LegacyGroupOwnershipReview {...props(request)}/>);
    expect(container).toBeEmptyDOMElement();expect(request).not.toHaveBeenCalled();
  });
  it('reads the exact current owner and eligible member but never sends a mutation',async()=>{
    const request=fixture(),userEventApi=userEvent.setup();render(<LegacyGroupOwnershipReview {...props(request)} enabled/>);
    expect(await screen.findByText(/Current owner: First owner/)).toBeVisible();
    await userEventApi.selectOptions(screen.getByLabelText('Member to review'),target);
    await userEventApi.click(screen.getByRole('button',{name:'Review member'}));
    expect(await screen.findByText(/Ownership transfer is unavailable/)).toBeVisible();
    expect(screen.getByRole('region',{name:'Ownership review'})).toHaveTextContent('Second member');
    expect(screen.queryByRole('button',{name:/transfer ownership/i})).not.toBeInTheDocument();
    expect(request.mock.calls.every(([,options])=>!options?.method||options.method==='GET')).toBe(true);
  });
  it('preserves a same-tab legacy request and makes no new request until its original workflow is reviewed',async()=>{
    await retainPending(identity,'operating-updatemembership',`${group}:${target}`,key,'users.manage',{role:'owner',expected_version:4,reason:'Original owner change'});
    const before=sessionStorage.getItem(PENDING_KEY),request=fixture();render(<LegacyGroupOwnershipReview {...props(request)} enabled/>);
    expect(await screen.findByText(key)).toBeVisible();expect(request).not.toHaveBeenCalled();expect(sessionStorage.getItem(PENDING_KEY)).toBe(before);
  });
  it('requires the same live role, session, model and read/manage permissions',async()=>{
    const request=fixture(),base=context(request);
    for(const changed of [{enabled:false},{role:'staff' as const},{financialModel:'canonical_evidence_ledger' as const},
      {permissions:['collections.read']},{identity:{...identity,sessionId:''}},{identity:{...identity,role:'owner' as const}},
      {identity:{...identity,expiresAt:'2000-01-01T00:00:00Z'}},{isCurrent:()=>false}]) {
      await expect(ownershipRecovery({...base,...changed})).rejects.toThrow(/unavailable/);
    }
    expect(request).not.toHaveBeenCalled();
  });
  it('refuses a different creator, malformed owner population, incomplete pages and changed source',async()=>{
    for(const bad of [
      {...detail(),resource:{...groupRow,creator_user_id:target}},detail([targetRow]),detail([ownerRow,{...targetRow,role:'owner'}]),
      {...detail(),related_pages:{memberships:{total:3,limit:100,offset:0,next_offset:2}},related_truncated:true},
    ]) {
      const request=vi.fn().mockResolvedValue(bad);await expect(loadOwnershipReview(context(request))).rejects.toThrow();
    }
    let changed=false;
    const request=vi.fn(async(path:string)=>path.startsWith('operations/groups/')?(changed?{...detail(),resource:{...groupRow,version:4}}:detail()):user(path.endsWith(owner)?owner:target));
    const ctx=context(request),source=await loadOwnershipReview(ctx);changed=true;
    await expect(reviewOwnershipTarget(ctx,source,target)).rejects.toThrow();
    expect(request.mock.calls.every(([path])=>!path.startsWith('operations/memberships/'))).toBe(true);
  });
  it('does not display a stale result when the preview gate closes during a request',async()=>{
    let release!:(value:unknown)=>void;
    const request=vi.fn(()=>new Promise<Record<string,unknown>>(resolve=>{release=resolve as (value:unknown)=>void;}));
    const page=render(<LegacyGroupOwnershipReview {...props(request)} enabled/>);
    await waitFor(()=>expect(release).toBeDefined());page.rerender(<LegacyGroupOwnershipReview {...props(request)} enabled={false}/>);
    release(detail());await waitFor(()=>expect(page.container).toBeEmptyDOMElement());
  });
});
