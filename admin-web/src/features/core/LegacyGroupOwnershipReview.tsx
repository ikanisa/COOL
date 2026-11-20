import {useEffect,useLayoutEffect,useMemo,useRef,useState} from 'react';
import {Button,Card,ErrorState,LoadingState} from '../../ui';
import {loadOwnershipReview,ownershipRecovery,reviewOwnershipTarget,type OwnershipReview,type OwnershipReviewContext,type OwnershipTarget} from './legacyGroupOwnership';
import type {PendingIdentity} from './pendingAttempt';
import type {FeatureAccess} from './types';

// Intentionally unmounted. This prepares a read-only review only; there is no
// mutation route until a qualified atomic backend exists for the serving model.
export interface LegacyGroupOwnershipReviewProps extends FeatureAccess {
  groupId:string;identity:PendingIdentity;enabled?:boolean;
}
export function LegacyGroupOwnershipReview({groupId,request,actorId,role,authorityKey,financialModel,permissions,identity,enabled=false}:LegacyGroupOwnershipReviewProps) {
  const permissionKey=JSON.stringify([...new Set(permissions)].sort()),identityKey=JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity=useMemo<PendingIdentity>(()=>({id:identity.id,sessionId:identity.sessionId,email:identity.email,role:identity.role,
    expiresAt:identity.expiresAt,permissions:JSON.parse(identityKey) as string[]}),[identity.id,identity.sessionId,identity.email,identity.role,identity.expiresAt,identityKey]);
  const stablePermissions=useMemo<readonly string[]>(()=>JSON.parse(permissionKey) as string[],[permissionKey]);
  const scope=JSON.stringify([groupId,actorId,role,authorityKey,financialModel,stableIdentity,permissionKey]),current=useRef(''),gate=useRef(false),busy=useRef(false);
  useLayoutEffect(()=>{current.current=scope;gate.current=enabled;return()=>{current.current='';gate.current=false;};},[scope,enabled]);
  const context=useMemo<OwnershipReviewContext>(()=>({groupId,request,actorId,role,financialModel,identity:stableIdentity,permissions:stablePermissions,
    enabled,isCurrent:()=>current.current===scope&&gate.current}),[groupId,request,actorId,role,financialModel,stableIdentity,stablePermissions,enabled,scope]);
  const [state,setState]=useState<'loading'|'ready'|'checking'|'error'>('loading'),[loaded,setLoaded]=useState(''),[review,setReview]=useState<OwnershipReview|null>(null),
    [pending,setPending]=useState<string[]>([]),[selected,setSelected]=useState(''),[target,setTarget]=useState<OwnershipTarget|null>(null),[message,setMessage]=useState('');
  useEffect(()=>{
    if(!enabled)return;let live=true;
    void (async()=>{
      try {
        const recovery=await ownershipRecovery(context);
        if(recovery.kind==='pending'){if(live&&context.isCurrent()){setPending(recovery.requestKeys);setReview(null);setTarget(null);setLoaded(scope);setState('ready');}return;}
        const source=await loadOwnershipReview(context);
        if(live&&context.isCurrent()){setPending([]);setReview(source);setTarget(null);setSelected('');setLoaded(scope);setState('ready');setMessage('');}
      } catch {if(live&&context.isCurrent()){setLoaded(scope);setState('error');setMessage('The group, account or recovery data could not be verified.');}}
    })();
    return()=>{live=false;};
  },[context,enabled,scope]);
  async function reviewSelected() {
    if(!review||!selected||busy.current||!context.isCurrent())return;
    busy.current=true;setState('checking');setMessage('');
    try {const result=await reviewOwnershipTarget(context,review,selected);if(context.isCurrent())setTarget(result);}
    catch {if(context.isCurrent()){setTarget(null);setMessage('The group or member changed, or a previous request needs review. Refresh before continuing.');}}
    finally {busy.current=false;if(context.isCurrent())setState('ready');}
  }
  if(!enabled)return null;
  if(state==='loading'||loaded!==scope)return <LoadingState label="Checking group ownership"/>;
  if(state==='error')return <ErrorState title="Ownership review unavailable" message={message}/>;
  return <Card><div className="core-detail"><h2>Review group ownership</h2>
    {message&&<p role="alert">{message}</p>}
    {pending.length>0?<section><p>A previous request in this tab needs review in its original workflow.</p>{pending.map(key=><p key={key}>Request reference: <code>{key}</code></p>)}</section>:
      review&&<><p>Group: {review.group.title} · version {review.group.version}</p><p>Current owner: {review.owner.displayName??'Name not recorded'} · {review.owner.publicId}</p>
        {review.members.length?<><label>Member to review<select className="admin-input" value={selected} onChange={event=>{setSelected(event.target.value);setTarget(null);}}><option value="">Select member</option>{review.members.map(member=><option key={member.id} value={member.id}>{member.displayName??'Name not recorded'} · {member.publicId} · {member.role}</option>)}</select></label>
          <Button type="button" disabled={!selected||state!=='ready'} onClick={()=>void reviewSelected()}>Review member</Button></>:<p>No other active members were found.</p>}
        {target&&<section aria-label="Ownership review"><h3>Reviewed member</h3><p>{target.target.displayName??'Name not recorded'} · {target.target.publicId} · {target.target.role}</p><p>Ownership transfer is unavailable until the service supports an atomic change.</p></section>}</>}
  </div></Card>;
}
