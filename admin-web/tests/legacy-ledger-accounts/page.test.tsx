import {fireEvent, render, screen, within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {readPending, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import { LegacyLedgerAccountCreatePage } from '../../src/features/legacy-ledger-accounts/LegacyLedgerAccountCreatePage';

const actor='11111111-1111-4111-8111-111111111111',group='22222222-2222-4222-8222-222222222222',account='33333333-3333-4333-8333-333333333333',key='44444444-4444-4444-8444-444444444444',operation='55555555-5555-4555-8555-555555555555';
const reason='Create the group ledger account', oldBody={group_id:group,code:'1000',name:'Cash control',account_type:'asset',normal_side:'debit',reason};
const receipt={request_id:operation,resource_type:'accounts',resource_id:account,version:1,status:'succeeded'};
const groupDetail={resource_type:'groups',current_actor_id:actor,can_manage:true,resource:{id:group,title:'Fixture group',status:'active',visibility:'private',version:2,country_code:'RW',currency:'RWF'}};
const accountDetail={resource_type:'accounts',current_actor_id:actor,can_manage:true,related:{},related_pages:{},related_truncated:false,resource:{id:account,group_id:group,code:'1000',name:'Cash control',account_type:'asset',normal_side:'debit',currency:'RWF',status:'active',created_by_admin_id:actor,created_at:1790000000,version:1}};
function identity():PendingIdentity{return {id:actor,sessionId:'session-1',email:'admin@example.test',role:'admin',permissions:['collections.read','ledger.read','ledger.manage','overview.read'],expiresAt:new Date(Date.now()+3600000).toISOString()};}
const request=vi.fn(),navigate=vi.fn(),locks=Object.getOwnPropertyDescriptor(navigator,'locks');
function props(){return {groupId:group,request,permissions:identity().permissions,actorId:actor,principalId:null,role:'admin' as const,authorityKey:'authority-1',financialModel:'transaction_journals' as const,navigate,identity:identity()};}
beforeEach(()=>{sessionStorage.clear();localStorage.clear();Object.defineProperty(navigator,'locks',{configurable:true,value:{request:async(name:string,_options:unknown,work:(lock:{name:string})=>Promise<unknown>)=>work({name})}});});
afterEach(()=>{request.mockReset();navigate.mockReset();if(locks)Object.defineProperty(navigator,'locks',locks);else Reflect.deleteProperty(navigator,'locks');});
async function enterDraft(){
  const user=userEvent.setup();await user.type(await screen.findByLabelText('Account code'),'1000');await user.type(screen.getByLabelText('Account name'),'Cash control');
  await user.type(screen.getByLabelText('Reason for creation'),reason);await user.click(screen.getByRole('button',{name:'Review ledger account'}));return user;
}

describe('legacy ledger account creation page',()=>{
  it('offers no creation by default',async()=>{
    render(<LegacyLedgerAccountCreatePage {...props()}/>);
    expect(await screen.findByText('Ledger account creation is unavailable in this workspace.')).toBeVisible();
    expect(screen.queryByRole('button',{name:'Review ledger account'})).not.toBeInTheDocument();expect(request).not.toHaveBeenCalled();
  });
  it('shows the exact reviewed account and requires confirmation before the guarded POST',async()=>{
    let posted=false;
    request.mockImplementation(async(path:string,options?:{body?:unknown})=>{
      if(path==='operations/accounts'){expect(options?.body).toEqual({...oldBody,expected_group_version:2});posted=true;return receipt;}
      if(path.includes('operations/requests/'))return {status:'succeeded',request_id:operation,receipt};
      if(path.includes('operations/accounts/'))return accountDetail;return groupDetail;
    });
    render(<LegacyLedgerAccountCreatePage {...props()} allowMutations/>);const user=await enterDraft();
    expect(screen.getByRole('button',{name:'Confirm account'})).toBeDisabled();expect(posted).toBe(false);
    fireEvent.change(screen.getByLabelText('Account name'),{target:{value:'Changed behind the dialog'}});
    expect(within(screen.getByRole('dialog')).getByText('Cash control')).toBeVisible();
    await user.click(screen.getByRole('checkbox',{name:'I reviewed the group and account details.'}));await user.click(screen.getByRole('button',{name:'Confirm account'}));
    expect(await screen.findByText('The ledger account was recorded.')).toBeVisible();await user.click(screen.getByRole('button',{name:'View account'}));
    expect(navigate).toHaveBeenCalledWith(`/admin/ledger-accounts/${account}`);
  });
  it('discards an unconfirmed review when the action gate or authority changes',async()=>{
    request.mockResolvedValue(groupDetail);const base=props(),view=render(<LegacyLedgerAccountCreatePage {...base} allowMutations/>);
    await enterDraft();expect(screen.getByRole('dialog')).toBeVisible();
    view.rerender(<LegacyLedgerAccountCreatePage {...base} allowMutations={false}/>);expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    view.rerender(<LegacyLedgerAccountCreatePage {...base} authorityKey="different-authority" allowMutations/>);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();expect(request.mock.calls.some(call=>call[0]==='operations/accounts')).toBe(false);
  });
  it('shows the legacy Flutter checkpoint for lookup only and never submits it',async()=>{
    await retainPending(identity(),'operating-createaccount','new',key,'ledger.manage',oldBody);request.mockResolvedValue({status:'not_found'});
    render(<LegacyLedgerAccountCreatePage {...props()} allowMutations/>);const user=userEvent.setup();
    await user.click(await screen.findByRole('button',{name:'Check original request'}));
    expect(await screen.findByText(/its intent cannot be retried here/)).toBeVisible();expect(screen.queryByRole('button',{name:'Review same request'})).not.toBeInTheDocument();
    expect(request).toHaveBeenCalledOnce();expect(await readPending(identity(),'operating-createaccount','new')).toMatchObject({request_key:key});
  });
  it('checks an unknown request with writes disabled and offers the identical retry only after re-enabling and checking again',async()=>{
    let posts=0, requestKey='';
    request.mockImplementation(async(path:string,options?:{idempotencyKey?:string})=>{
      if(path==='operations/accounts'){posts++;requestKey=String(options?.idempotencyKey);if(posts===1)throw new Error('lost');return receipt;}
      if(path.includes('operations/requests/'))return posts>1?{status:'succeeded',request_id:operation,receipt}:{status:'not_found'};
      if(path.includes('operations/accounts/'))return accountDetail;return groupDetail;
    });
    const base=props(),view=render(<LegacyLedgerAccountCreatePage {...base} allowMutations/>),user=await enterDraft();
    await user.click(screen.getByRole('checkbox',{name:'I reviewed the group and account details.'}));await user.click(screen.getByRole('button',{name:'Confirm account'}));
    expect(await screen.findByText(/The outcome is unknown/)).toBeVisible();expect(requestKey).toBeTruthy();
    view.rerender(<LegacyLedgerAccountCreatePage {...base} allowMutations={false}/>);
    await user.click(await screen.findByRole('button',{name:'Check original request'}));expect(await screen.findByText(/retries are not enabled/)).toBeVisible();
    view.rerender(<LegacyLedgerAccountCreatePage {...base} allowMutations/>);
    await user.click(await screen.findByRole('button',{name:'Check original request'}));
    await user.click(await screen.findByRole('button',{name:'Review same request'}));expect(screen.getByRole('button',{name:'Confirm same request'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox',{name:'I reviewed the group and account details.'}));await user.click(screen.getByRole('button',{name:'Confirm same request'}));
    expect(await screen.findByText('The ledger account was recorded.')).toBeVisible();expect(posts).toBe(2);
    const sent=request.mock.calls.filter(call=>call[0]==='operations/accounts');expect(sent[0][1]).toEqual(sent[1][1]);
  });
});
