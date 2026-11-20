import {render,screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import type {AdminRequest,AdminRequestOptions} from '../../src/api/client';
import {readPending,retainPending,sha256Text,type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {LegacyTransactionCreate} from '../../src/features/legacy-transactions/LegacyTransactionCreate';
import {checkCreate,loadCreateTargets,recoverCreateSource,restoreCreate,retryCreate,submitCreate,verifyCreateReentry,type CreateContext} from '../../src/features/legacy-transactions/create';
import {loadCreateSource,searchCreateSources} from '../../src/features/legacy-transactions/createSource';

const actor='11111111-1111-4111-8111-111111111111',group='22222222-2222-4222-8222-222222222222',payee='33333333-3333-4333-8333-333333333333',transaction='44444444-4444-4444-8444-444444444444',evidenceId='55555555-5555-4555-8555-555555555555',key='66666666-6666-4666-8666-666666666666',requestId='77777777-7777-4777-8777-777777777777',sourceId='88888888-8888-4888-8888-888888888888',factId='99999999-9999-4999-8999-999999999999';
const digest='a'.repeat(64),bodyHash='b'.repeat(64),payloadHash='c'.repeat(64),reason='Record inspected payment evidence',observed='2026-10-04T12:00:00Z',time=Date.parse(observed)/1000;
const body={group_id:group,payee_id:payee,expected_group_version:4,expected_payee_version:3,provider_reference:'PRIVATE-SYNTHETIC-REFERENCE',amount_rwf:2500,observed_at:time,evidence:{kind:'receiver_statement',reference:'Private evidence label',sha256:digest},reason,source_fact_id:factId};
const receipt={request_id:requestId,resource_type:'transactions',resource_id:transaction,version:1,status:'succeeded'};
function identity():PendingIdentity{return {id:actor,sessionId:'session-1',email:'admin@example.test',role:'admin',permissions:['collections.read','receivers.read','payments.read','payments.manage','overview.read','sms.read'],expiresAt:new Date(Date.now()+3600000).toISOString()};}
function ctx(request:AdminRequest):CreateContext {const user=identity();return {request,identity:user,permissions:user.permissions,financialModel:'transaction_journals',enabled:true,isCurrent:()=>true,storage:sessionStorage,sharedStorage:localStorage,lock:async(_name,work)=>work(),createKey:()=>key};}
function details(type:'groups'|'payees',version?:number){const resource=type==='groups'?{id:group,title:'Synthetic group',status:'active',country_code:'RW',currency:'RWF',version:version??4}:{id:payee,group_id:group,label:'Synthetic receiver',status:'active',network:'mtn_momo',momo_number_or_code:'123456',version:version??3};return {resource_type:type,resource,current_actor_id:actor,can_manage:true,related:{},related_pages:{},related_truncated:false};}
function source(overrides:Record<string,unknown>={}){return {source_kind:'receiver',id:sourceId,user_id:null,payee_id:payee,source_sha256:payloadHash,status:'pending',version:1,received_at:time,created_at:time,public_id:null,display_name:'Synthetic receiver',transaction_id:null,evidence_level:'receiver_ingress_unverified',
  source_fact_id:factId,parser_version:'collect-admin-source-facts-v1',extraction_status:'parsed',source_body_sha256:bodyHash,source_payload_sha256:payloadHash,parsed_at:time,payer_name:'Synthetic payer',payer_phone:null,payer_masked_phone:'***567',payer_last3:'567',
  payee_momo_number:null,payee_momo_code:null,momo_transaction_reference:body.provider_reference,momo_timestamp_local:null,momo_timezone_offset:null,amount_rwf:2500,wallet_balance_rwf:null,network:'mtn_momo',direction:'incoming',is_payment:1,transaction_reference:null,
  duplicate_reference_count:0,conflicting_reference_count:0,provider_confirmation:false,settlement_status:'not_asserted',timezone_known:false,payer_last3_known:true,source_content_reveal_required:true,...overrides};}
function sourceDetail(row=source()){return {resource_type:'sms_receipts',resource:row,current_actor_id:actor,can_extract:false,related:{duplicate_references:{rows:[],total:0,limit:25,offset:0,next_offset:null}}};}
function transactionDetail(sourceFact:string|null=factId){return {resource_type:'transactions',resource:{id:transaction,group_id:group,payee_id:payee,network:'mtn_momo',payee_momo_number_or_code:'123456',provider_reference:body.provider_reference,amount_rwf:2500,observed_at:time,verification_status:'pending',version:1,recorded_by_admin_id:actor,reference_source_fact_id:sourceFact,currency:'RWF',provider_confirmation:false,settlement_status:'not_asserted'},current_actor_id:actor,can_manage:true,related:{evidence:[{id:evidenceId,kind:'receiver_statement',reference:body.evidence.reference,sha256:digest,recorded_by_admin_id:actor,recorded_at:time}]},related_pages:{evidence:{total:1,limit:100,offset:0,next_offset:null}},related_truncated:false};}
function fixture(onPost:(options?:AdminRequestOptions)=>Promise<Record<string,unknown>>=async()=>receipt){
  return vi.fn(async(path:string,options?:AdminRequestOptions):Promise<Record<string,unknown>>=>{
    if(path.startsWith('operations/lookups?kind=groups'))return {rows:[{id:group,label:'Synthetic group',version:4}]};
    if(path.startsWith('operations/lookups?kind=payees'))return {rows:[{id:payee,label:'Synthetic receiver',version:3,network:'mtn_momo'}]};
    if(path===`operations/groups/${group}`)return details('groups');if(path===`operations/payees/${payee}`)return details('payees');
    if(path.startsWith('sms/receipts?'))return {rows:[source()],total:1,limit:100,offset:0,next_offset:null};
    if(path===`sms/receipts/receiver/${sourceId}`)return sourceDetail();
    if(path==='operations/transactions')return onPost(options);
    if(path===`operations/transactions/${transaction}?relation=evidence&limit=100&offset=0`)return transactionDetail();
    if(path===`operations/requests/${key}`)return {status:'succeeded',request_id:requestId,receipt};
    if(path==='operations/requests?limit=100&offset=0')return {total:1,rows:[{id:requestId,idempotency_key:key,scope:'transactions.post',status:'succeeded',receipt}]};
    throw new Error(`Unexpected synthetic request ${path}`);
  });
}
async function setup(context:CreateContext){const pending=await restoreCreate(context);if(pending.kind!=='ready')throw new Error('expected ready');return {revision:pending.revision,targets:await loadCreateTargets(context,group,payee),source:await loadCreateSource(context,sourceId)};}
const originalLocks=Object.getOwnPropertyDescriptor(navigator,'locks');
beforeEach(()=>{sessionStorage.clear();localStorage.clear();Object.defineProperty(navigator,'locks',{configurable:true,value:{request:async(name:string,_options:unknown,work:(lock:{name:string})=>Promise<unknown>)=>work({name})}});});
afterEach(()=>{if(originalLocks)Object.defineProperty(navigator,'locks',originalLocks);else Reflect.deleteProperty(navigator,'locks');});

describe('preserved receiver fact selection',()=>{
  it('requires sms.read and returns only a parsed incoming unlinked source for the chosen receiver',async()=>{
    const request=fixture(),context=ctx(request),result=await searchCreateSources(context,'SYNTHETIC',payee);
    expect(result.choices).toHaveLength(1);expect(result.choices[0]).toMatchObject({receiptId:sourceId,factId,payeeId:payee,amount:2500});expect(result.truncated).toBe(false);
    await expect(searchCreateSources({...context,permissions:['payments.manage']},'',payee)).rejects.toThrow();
    const conflicting=fixture();conflicting.mockImplementation(async path=>path.startsWith('sms/receipts?')?{rows:[source({duplicate_reference_count:1,conflicting_reference_count:1})],total:1,limit:100,offset:0,next_offset:null}:{});
    expect((await searchCreateSources(ctx(conflicting),'',payee)).choices).toHaveLength(0);
  });
  it('sends and verifies the exact fact while retaining only IDs and digests for recovery',async()=>{
    const request=fixture(async options=>{
      expect(options).toEqual({method:'POST',body,idempotencyKey:key});const stored=await readPending(identity(),'legacy-guarded-transaction-create','new');
      expect(stored).toMatchObject({request_key:key,intent:{source_fact_id:factId,source_receipt_id:sourceId}});
      const raw=JSON.stringify(stored);expect(raw).not.toContain('Synthetic payer');expect(raw).not.toContain(body.provider_reference);expect(raw).not.toContain(reason);return receipt;
    }),context=ctx(request),selected=await setup(context);
    expect((await submitCreate(context,body,selected.targets,selected.revision,selected.source)).status).toBe('succeeded');
  });
  it('refuses an altered source, different amount, wrong receiver or source-linked receipt mismatch',async()=>{
    const request=fixture(),context=ctx(request),selected=await setup(context);
    await expect(submitCreate(context,{...body,amount_rwf:2501},selected.targets,selected.revision,selected.source)).rejects.toThrow(/source/i);
    await expect(submitCreate(context,body,selected.targets,selected.revision,{...selected.source,payeeId:group})).rejects.toThrow(/source/i);
    const original=request.getMockImplementation()!;request.mockImplementation(async(path,options)=>path===`sms/receipts/receiver/${sourceId}`?sourceDetail(source({payer_name:'Changed source'})):original(path,options));
    await expect(submitCreate(context,body,selected.targets,selected.revision,selected.source)).rejects.toThrow(/source changed/i);
    expect(request.mock.calls.some(([path])=>path==='operations/transactions')).toBe(false);
    request.mockImplementation(async(path,options)=>path===`operations/transactions/${transaction}?relation=evidence&limit=100&offset=0`?transactionDetail(null):original(path,options));
    expect(await submitCreate(context,body,selected.targets,selected.revision,selected.source)).toEqual({status:'unknown',requestKey:key});expect((await restoreCreate(context)).kind).toBe('owned');
  });
  it('restores the exact source for an explicit same-key retry and rejects changed details',async()=>{
    let posted=0,recorded=false;
    const request=fixture(async options=>{posted++;expect(options).toEqual({method:'POST',body,idempotencyKey:key});if(posted===1)throw new Error('lost');recorded=true;return receipt;});
    const original=request.getMockImplementation()!;request.mockImplementation(async(path,options)=>path===`operations/requests/${key}`&&!recorded?{status:'not_found'}:original(path,options));
    const context=ctx(request),selected=await setup(context);expect(await submitCreate(context,body,selected.targets,selected.revision,selected.source)).toEqual({status:'unknown',requestKey:key});
    const pending=await restoreCreate(context);expect(await checkCreate(context,pending)).toEqual({status:'not_found',retryAvailable:true});if(pending.kind!=='owned'||!pending.attempt)throw new Error('missing attempt');
    const recovered=await recoverCreateSource(context,pending.attempt);expect(recovered).toEqual(selected.source);
    await expect(recoverCreateSource({...context,permissions:context.permissions.filter(value=>value!=='sms.read')},pending.attempt)).rejects.toThrow(/source/i);
    const beforeChange=request.getMockImplementation()!;
    request.mockImplementation(async(path,options)=>path===`sms/receipts/receiver/${sourceId}`?sourceDetail(source({payer_name:'Changed source'})):beforeChange(path,options));
    await expect(recoverCreateSource(context,pending.attempt)).rejects.toThrow(/source changed/i);request.mockImplementation(beforeChange);
    await expect(verifyCreateReentry(context,pending.attempt,{...body,reason:'Changed evidence reason'},recovered)).rejects.toThrow(/does not match/);
    await expect(retryCreate(context,pending,body,selected.targets,{...selected.source,amount:2501})).rejects.toThrow(/does not match/);
    expect((await retryCreate(context,pending,body,selected.targets,recovered)).status).toBe('succeeded');expect(posted).toBe(2);
  });
});

describe('source selection and initial group UI',()=>{
  it('loads a fixed group from the server and presents only the selected receiver source',async()=>{
    const user=userEvent.setup(),authority=identity(),request=fixture();let generated='';
    const original=request.getMockImplementation()!;request.mockImplementation(async(path,options)=>{
      if(path==='operations/transactions'){generated=options?.idempotencyKey??'';expect(options?.body).toEqual(body);return receipt;}
      if(path===`operations/requests/${generated}`)return {status:'succeeded',request_id:requestId,receipt};
      if(path==='operations/requests?limit=100&offset=0')return {total:1,rows:[{id:requestId,idempotency_key:generated,scope:'transactions.post',status:'succeeded',receipt}]};return original(path,options);
    });
    render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="one" isCurrent={()=>true} allowMutations initialGroupId={group} onCreated={()=>undefined}/>);
    expect(await screen.findByLabelText('Group')).toHaveValue(group);expect(screen.getByLabelText('Group')).toBeDisabled();expect(screen.queryByRole('button',{name:'Find groups'})).not.toBeInTheDocument();
    await user.click(screen.getByRole('button',{name:'Find receivers'}));await user.selectOptions(await screen.findByLabelText('Receiver'),payee);
    await user.click(screen.getByRole('button',{name:'Find receiver sources'}));await user.selectOptions(await screen.findByLabelText('Preserved receiver source (optional)'),factId);
    await user.type(screen.getByLabelText('Provider reference'),body.provider_reference);await user.type(screen.getByLabelText('Payment amount (RWF)'),'2500');await user.type(screen.getByLabelText('Observed at (UTC)'),observed);
    await user.selectOptions(screen.getByLabelText('Evidence type'),'receiver_statement');await user.type(screen.getByLabelText('Evidence reference'),body.evidence.reference);await user.type(screen.getByLabelText('Evidence SHA-256'),digest);await user.type(screen.getByLabelText('Reason'),reason);
    await user.click(screen.getByRole('button',{name:'Review payment evidence'}));expect(await screen.findByText(new RegExp(factId))).toBeVisible();expect(screen.getByRole('button',{name:'Confirm payment evidence'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox',{name:'I reviewed the payment, receiving account, evidence and reason.'}));await user.click(screen.getByRole('button',{name:'Confirm payment evidence'}));
    expect(await screen.findByText(`Payment evidence recorded. Reference ${requestId}.`)).toBeVisible();
  });
  it('rejects an invalid fixed group and keeps recording unavailable for that entry',async()=>{
    const authority=identity(),request=fixture();render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="one" isCurrent={()=>true} allowMutations initialGroupId="invalid" onCreated={()=>undefined}/>);
    expect(await screen.findByText('The selected group could not be verified.')).toBeVisible();expect(screen.queryByRole('button',{name:'Find groups'})).not.toBeInTheDocument();expect(screen.queryByRole('button',{name:'Find receivers'})).not.toBeInTheDocument();
  });
  it('checks an unresolved request for another group but does not offer its retry on a fixed-group entry',async()=>{
    const {source_fact_id,...manual}=body;void source_fact_id;
    await retainPending(identity(),'legacy-guarded-transaction-create','new',key,'payments.manage',{group_id:group,payee_id:payee,expected_group_version:4,expected_payee_version:3,evidence_sha256:digest,request_sha256:await sha256Text(JSON.stringify(manual))});
    const authority=identity(),request=fixture(),original=request.getMockImplementation()!;
    request.mockImplementation(async(path,options)=>path===`operations/requests/${key}`?{status:'not_found'}:original(path,options));
    const other='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',user=userEvent.setup();
    render(<LegacyTransactionCreate request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="one" isCurrent={()=>true} allowMutations initialGroupId={other} onCreated={()=>undefined}/>);
    await user.click(await screen.findByRole('button',{name:'Check original request'}));
    expect(await screen.findByText(/belongs to another group/)).toBeVisible();
    expect(screen.queryByRole('button',{name:'Review payment evidence'})).not.toBeInTheDocument();
    expect(request.mock.calls.some(([path])=>path==='operations/transactions'||path===`operations/groups/${group}`)).toBe(false);
    expect(await readPending(identity(),'legacy-guarded-transaction-create','new')).toMatchObject({request_key:key});
  });
});
