import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {Button, Card, Dialog, ErrorState, LoadingState, PageHeader} from '../../ui';
import type {PendingIdentity} from '../core/pendingAttempt';
import {usePendingIdentity} from '../core/usePendingIdentity';
import type {FeatureAccess} from '../core/types';
import '../core/core.css';
import {currentGroup, lookupAccountCreate, originalAccountBody, parseAccountBody, restoreAccountCreate, retryAccountCreate, submitAccountCreate,
  type AccountBody, type AccountCreateContext, type AccountPending, type GroupSnapshot} from './actions';

export interface LegacyLedgerAccountCreateProps extends FeatureAccess {groupId:string; identity:PendingIdentity; allowMutations?:boolean;}
interface Draft {body:AccountBody; group:GroupSnapshot; mode:'new'|'retry'; revision:string;}
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;

/** New account requests stay disabled until the guarded backend is qualified. */
export function LegacyLedgerAccountCreatePage(props:LegacyLedgerAccountCreateProps){
  const {identity}=props;
  const scope=JSON.stringify([props.authorityKey,props.groupId,props.actorId,props.role,props.principalId,props.financialModel,props.allowMutations??false,
    [...new Set(props.permissions)].sort(),identity.id,identity.sessionId,identity.email,identity.role,identity.expiresAt,[...new Set(identity.permissions)].sort()]);
  return <LegacyLedgerAccountCreateSession key={scope} {...props}/>;
}
function LegacyLedgerAccountCreateSession({groupId,request,permissions,actorId,role,authorityKey,financialModel,navigate,identity,allowMutations=false}:LegacyLedgerAccountCreateProps){
  const identityPermissions=JSON.stringify([...new Set(identity.permissions)].sort()), suppliedPermissions=JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = usePendingIdentity(identity);
  const stablePermissions=useMemo<readonly string[]>(()=>JSON.parse(suppliedPermissions) as string[],[suppliedPermissions]);
  const allowed=financialModel==='transaction_journals'&&UUID.test(groupId)&&UUID.test(actorId)&&role!=='staff'&&stableIdentity.id===actorId&&stableIdentity.role===role&&
    ['collections.read','ledger.read','ledger.manage','overview.read'].every(value=>stablePermissions.includes(value)&&stableIdentity.permissions.includes(value));
  const scope=JSON.stringify([authorityKey,groupId,financialModel,actorId,role,stableIdentity.id,stableIdentity.sessionId,stableIdentity.email,stableIdentity.expiresAt,identityPermissions,suppliedPermissions]);
  const activeScope=useRef(scope),gate=useRef(allowMutations),busy=useRef(false);
  useLayoutEffect(()=>{activeScope.current=scope;return()=>{activeScope.current='';};},[scope]);
  useLayoutEffect(()=>{gate.current=allowMutations;return()=>{gate.current=false;};},[allowMutations]);
  const context=useMemo<AccountCreateContext>(()=>({groupId,request,identity:stableIdentity,actorId,permissions:stablePermissions,financialModel,enabled:allowMutations,
    isCurrent:()=>activeScope.current===scope&&Date.parse(stableIdentity.expiresAt)>Date.now(),isEnabled:()=>gate.current}),[groupId,request,stableIdentity,actorId,stablePermissions,financialModel,allowMutations,scope]);
  const [pending,setPending]=useState<AccountPending|null>(null),[source,setSource]=useState<GroupSnapshot|null>(null),[loaded,setLoaded]=useState('');
  const [state,setState]=useState<'loading'|'ready'|'checking'|'sending'|'success'|'error'>('loading'),[message,setMessage]=useState(''),[createdId,setCreatedId]=useState('');
  const [code,setCode]=useState(''),[name,setName]=useState(''),[kind,setKind]=useState<AccountBody['account_type']>('asset'),[side,setSide]=useState<AccountBody['normal_side']>('debit'),[reason,setReason]=useState('');
  const [draft,setDraft]=useState<Draft|null>(null),[confirmed,setConfirmed]=useState(false),[retryAvailable,setRetryAvailable]=useState(false);
  useEffect(()=>{
    if(!allowed)return;let live=true;
    restoreAccountCreate(context).then(async saved=>{
      const group=saved.kind==='ready'&&allowMutations?await currentGroup(context):null;
      if(live&&context.isCurrent()){setPending(saved);setSource(group);setLoaded(scope);setState('ready');setMessage('');}
    }).catch(()=>{if(live&&context.isCurrent()){setLoaded(scope);setState('error');setMessage('The group or recovery data could not be verified.');}});
    return()=>{live=false;};
  },[allowed,allowMutations,context,scope]);
  const ready=pending?.kind==='ready'?pending:null,unresolved=pending&&pending.kind!=='ready'?pending:null;
  const original=unresolved?.kind==='owned'?originalAccountBody(unresolved):null;
  const makeReview=(event:FormEvent)=>{
    event.preventDefault();if(!ready||!source||!allowMutations||busy.current||!context.isCurrent())return;
    try{const body=parseAccountBody({group_id:groupId,code:code.trim(),name:name.trim(),account_type:kind,normal_side:side,reason:reason.trim(),expected_group_version:source.version});
      setDraft({body,group:source,mode:'new',revision:ready.revision});setConfirmed(false);setMessage('');}
    catch{setMessage('Check the account code, name, type, normal side and reason.');}
  };
  const checkOriginal=async()=>{
    if(!unresolved||(unresolved.kind!=='owned'&&unresolved.kind!=='legacy')||busy.current||!context.isCurrent())return;
    busy.current=true;setState('checking');setMessage('');setRetryAvailable(false);
    try{
      const result=await lookupAccountCreate(context,unresolved);if(!context.isCurrent())return;
      if(result.status==='succeeded'&&result.verifiedIntent){setCreatedId(result.receipt.accountId);
        if(unresolved.kind==='owned'){setPending(null);setState('success');setMessage('The original ledger account creation was recorded.');}
        else setMessage('The original request was recorded. Its older recovery reference remains in the original workflow.');}
      else if(result.status==='succeeded')setMessage(`The server recorded account request ${result.receipt.requestId}, but its original details cannot be verified. Keep the reference for investigation.`);
      else if(result.status==='not_found'){setRetryAvailable(result.retryAvailable&&allowMutations);setMessage(result.retryAvailable?(allowMutations?'No server receipt was found. Review the same request before an explicit retry.':'No server receipt was found. Keep the original reference; retries are not enabled.'):'No server receipt was found. Keep the original reference; its intent cannot be retried here.');}
      else setMessage('The original request remains unresolved. Keep its reference and check again.');
    }catch{if(context.isCurrent())setMessage('The original request or resulting account could not be verified. Keep the reference and check again.');}
    finally{busy.current=false;if(context.isCurrent())setState(previous=>previous==='checking'?'ready':previous);}
  };
  const reviewSame=async()=>{
    if(!unresolved||unresolved.kind!=='owned'||!original||!retryAvailable||!allowMutations||busy.current||!context.isCurrent())return;
    busy.current=true;setState('checking');setMessage('');
    try{const group=await currentGroup(context);if(!context.isCurrent()||!gate.current)return;
      if(original.group_id!==group.id||original.expected_group_version!==group.version)throw new Error('Group changed');
      setDraft({body:original,group,mode:'retry',revision:''});setConfirmed(false);}
    catch{if(context.isCurrent()){setRetryAvailable(false);setMessage('The group changed or could not be verified. Check the original request before continuing.');}}
    finally{busy.current=false;if(context.isCurrent())setState(previous=>previous==='checking'?'ready':previous);}
  };
  const send=async()=>{
    if(!draft||!confirmed||!allowMutations||busy.current||!context.isCurrent())return;
    busy.current=true;setState('sending');setMessage('');setRetryAvailable(false);
    try{
      const result=draft.mode==='new'?await submitAccountCreate(context,draft.body,draft.group,draft.revision):await retryAccountCreate(context,unresolved!);
      if(!context.isCurrent())return;
      if(result.status==='succeeded'){setPending(null);setCreatedId(result.receipt.accountId);setState('success');setMessage('The ledger account was recorded.');}
      else if(result.status==='existing'){setPending(result.pending);setState('ready');setMessage('An original account request needs recovery.');}
      else{setPending({kind:'owned',requestKey:result.requestKey,attempt:null});setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`);try{const saved=await restoreAccountCreate(context);if(context.isCurrent())setPending(saved);}catch{/* Keep the reference visible. */}}
    }catch{if(context.isCurrent()){setMessage('The group or recovery data could not be verified. Check the original request before continuing.');try{const saved=await restoreAccountCreate(context);if(context.isCurrent())setPending(saved);}catch{if(context.isCurrent())setState('error');}}}
    finally{busy.current=false;if(context.isCurrent()){setState(previous=>previous==='sending'?'ready':previous);setDraft(null);setConfirmed(false);}}
  };
  const header=<PageHeader title="Create ledger account" subtitle="Record an account for this group." actions={<Button onClick={()=>navigate(UUID.test(groupId)?`/admin/groups/${groupId}`:'/admin/groups')}>Back to group</Button>}/>;
  if(!allowed)return <>{header}<ErrorState title="Creation unavailable" message={financialModel==='canonical_evidence_ledger'?'Separate legacy ledger accounts are unavailable in the canonical model.':'Your account cannot use this workflow.'}/></>;
  if(state==='loading'||loaded!==scope)return <>{header}<LoadingState label="Checking ledger account recovery"/></>;
  if(state==='error')return <>{header}<ErrorState message={message}/></>;
  if(state==='success')return <>{header}<Card><div className="core-detail" role="status"><h2>Ledger account recorded</h2><p>{message}</p><Button onClick={()=>navigate(`/admin/ledger-accounts/${createdId}`)}>View account</Button></div></Card></>;
  return <>{header}<Card><div className="core-detail">
    {message&&<p role="status">{message}</p>}
    {createdId&&<Button onClick={()=>navigate(`/admin/ledger-accounts/${createdId}`)}>View recorded account</Button>}
    {unresolved?.kind==='foreign'&&<p>Another account or session has an unresolved ledger account request. The original account must check it.</p>}
    {unresolved?.kind==='conflict'&&<p>Both an older and a newer account request need recovery. Resolve the original requests before creating another account.</p>}
    {unresolved&&(unresolved.kind==='owned'||unresolved.kind==='legacy')&&<section><h2>Original request needs review</h2><p>Request reference: <code>{unresolved.kind==='owned'?unresolved.requestKey:unresolved.attempt.request_key}</code></p>
      {unresolved.kind==='legacy'&&<p>This older request can be checked here; its original workflow is required for any retry.</p>}
      {original&&original.group_id!==groupId&&<p>This request belongs to group {original.group_id}. Open that group before considering a retry.</p>}
      <Button disabled={state!=='ready'} onClick={()=>void checkOriginal()}>Check original request</Button>{allowMutations&&retryAvailable&&<Button disabled={state!=='ready'} onClick={()=>void reviewSame()}>Review same request</Button>}</section>}
    {!unresolved&&!allowMutations&&<p>Ledger account creation is unavailable in this workspace.</p>}
    {ready&&source&&allowMutations&&<form className="core-edit-form" onSubmit={makeReview}><p>Group: {source.title} · {source.status} · version {source.version}.</p>
      <label>Account code<input className="admin-input" value={code} maxLength={40} required onChange={event=>setCode(event.target.value)}/></label>
      <label>Account name<input className="admin-input" value={name} minLength={2} maxLength={120} required onChange={event=>setName(event.target.value)}/></label>
      <label>Account type<select className="admin-input" value={kind} onChange={event=>setKind(event.target.value as AccountBody['account_type'])}>{['asset','liability','equity','income','expense'].map(value=><option key={value} value={value}>{value}</option>)}</select></label>
      <label>Normal side<select className="admin-input" value={side} onChange={event=>setSide(event.target.value as AccountBody['normal_side'])}><option value="debit">Debit</option><option value="credit">Credit</option></select></label>
      <label>Reason for creation<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event=>setReason(event.target.value)}/></label>
      <Button type="submit" variant="primary" disabled={state!=='ready'}>Review ledger account</Button></form>}
    <Dialog open={draft!==null} title={draft?.mode==='retry'?'Review same account request':'Review ledger account'} onClose={()=>{if(state!=='sending')setDraft(null);}} footer={<><Button onClick={()=>setDraft(null)} disabled={state==='sending'}>Cancel</Button><Button variant="primary" disabled={!confirmed||state==='sending'} onClick={()=>void send()}>{draft?.mode==='retry'?'Confirm same request':'Confirm account'}</Button></>}>
      {draft&&<><p>Group: {draft.group.title} · {draft.group.status} · version {draft.group.version}.</p><dl><div><dt>Code</dt><dd>{draft.body.code}</dd></div><div><dt>Name</dt><dd>{draft.body.name}</dd></div><div><dt>Type</dt><dd>{draft.body.account_type}</dd></div><div><dt>Normal side</dt><dd>{draft.body.normal_side}</dd></div><div><dt>Reason</dt><dd>{draft.body.reason}</dd></div></dl><p>{draft.mode==='retry'?'This uses the original request key and may create the account if the earlier request did not commit.':'The account will be recorded in RWF for this group.'}</p><label><input type="checkbox" checked={confirmed} onChange={event=>setConfirmed(event.target.checked)}/> I reviewed the group and account details.</label></>}
    </Dialog>
  </div></Card></>;
}
