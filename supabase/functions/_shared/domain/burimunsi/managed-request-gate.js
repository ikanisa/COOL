import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId,canonicalJson} from './values.js';

const activeDatabases=new WeakSet();
/** Server-imported Collect verification/projection and branded application fence.
 * This is not a PIN-to-managed-identity exchange. Use one DB context per request.
 */
export function createManagedRequestGate({verifyToken,projectSession,applicationWorkTuple,clock=()=>Date.now()}) {
  requireThat([verifyToken,projectSession,applicationWorkTuple,clock].every(f=>typeof f==='function'),'collect_adapter_required',503);
  return async function withManagedRequest({request,env,groupId,resolveGroup,requireGroupAssertion=false},operation) {
    if(groupId!==undefined)requireId(groupId);
    requireThat(typeof operation==='function'&&(groupId!==undefined||typeof resolveGroup==='function')&&
      !(groupId!==undefined&&resolveGroup!==undefined),'collect_adapter_required',503);
    const db=env?.DB,work=db?.applicationWork;
    requirePort(db,['setClaims']);requirePort(work,['assert']);
    requireThat(!activeDatabases.has(db),'managed_context_busy',503);
    const raw=request?.headers?.get('X-BuriMunsi-Collect-Session');
    requireThat(typeof raw==='string'&&raw.length>=20&&raw.length<=8192&&/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(raw),
      'managed_session_required',401);
    const original=canonicalJson(applicationWorkTuple(work));
    const owned=async()=>{requireThat(db.applicationWork===work,'request_not_admitted',503);await work.assert();
      requireThat(db.applicationWork===work&&canonicalJson(applicationWorkTuple(work))===original,'request_not_admitted',503);};
    activeDatabases.add(db);
    const local={...env};delete local.AUTH_ACTOR;delete local.AUTH_VERIFIED;
    // A caller cannot turn the ordinary native request into an admin exchange.
    delete local.ADMIN_AUTH_EXCHANGE;
    try {
      await owned();let verified;
      try{verified=await verifyToken(local,raw);}catch{throw new BuriError('managed_session_required',401);}
      await owned();const claims=verified?.claims,user=verified?.user;
      requireRequestId(claims?.sub);requireRequestId(claims?.session_id);
      requireThat(user?.id===claims.sub&&user.is_anonymous!==true&&claims.is_anonymous!==true&&
        Number.isSafeInteger(claims.exp)&&claims.exp>Math.floor(clock()/1000),'managed_session_required',401);
      let actor;
      try{actor=await projectSession(local,verified,{surface:'admin',existingLinkOnly:true});}
      catch{throw new BuriError('managed_session_required',401);}
      await owned();requireId(actor?.userId);
      requireThat(actor.sessionId===claims.session_id&&actor.surface==='admin','managed_session_required',401);
      // A group header is an intent assertion, never a scope selector. Discovery
      // happens only after genuine managed verification, from the exact current
      // principal + installation/device grant in this request's existing DB.
      const selected=groupId??await resolveGroup(Object.freeze({request,env:local,principalUserId:actor.userId,principalSessionId:actor.sessionId}));
      requireId(selected);await owned();
      if(requireGroupAssertion)requireThat(request.headers.get('X-BuriMunsi-Group')===selected,'managed_scope_changed',403);
      const result=await operation(Object.freeze({groupId:selected,principalUserId:actor.userId,principalSessionId:actor.sessionId}),local);
      await owned();return result;
    } finally {
      try{db.setClaims({});}finally{delete local.AUTH_ACTOR;delete local.AUTH_VERIFIED;activeDatabases.delete(db);}
    }
  };
}
