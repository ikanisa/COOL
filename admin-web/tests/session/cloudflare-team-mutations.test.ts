import {beforeEach, describe, expect, it, vi} from 'vitest';
import {readPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {sha256Text} from '../../src/features/core/pendingAttempt';
import {checkCloudflareTeam, readCloudflareTeamTarget, restoreCloudflareTeam, retryCloudflareTeam, submitCloudflareTeam,
  type CloudflareTeamContext} from '../../src/session/teamMutations';

const actor = '11111111-1111-4111-8111-111111111111', principal = '22222222-2222-4222-8222-222222222222', member = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444';
const input = {kind:'invite' as const, email:'staff@example.test', role:'staff' as const, displayName:'Staff Example'};
const identity = (): PendingIdentity => ({id:actor, sessionId:'session-a', email:'info@ikanisa.com', role:'owner', permissions:['admin_users.read','admin_users.manage'], expiresAt:new Date(Date.now()+3600000).toISOString()});
function context(request: CloudflareTeamContext['request']): CloudflareTeamContext {
  return {identity:identity(), principalId:principal, request, allowMutations:true, current:() => true, storage:sessionStorage, sharedStorage:localStorage,
    lock:async (_name, work) => work(), createKey:() => key};
}
async function receipt(status: 'accepted' | 'unknown' = 'accepted') {
  const hash = await sha256Text(`collect-admin-team-v1:${principal}:${key}`), requestId = `${hash.slice(0,8)}-${hash.slice(8,12)}-4${hash.slice(13,16)}-8${hash.slice(17,20)}-${hash.slice(20,32)}`;
  const intentSha256=await sha256Text('{"body":{"displayName":"Staff Example","email":"staff@example.test","role":"staff"},"path":"/team/cloudflare/v1/invite"}');
  return {ok:true, found:true, contractVersion:1, requestId, operation:'invite', memberId:member, email:input.email, role:'staff', accessStatus:'invited', authVersion:1, eventId:requestId, emailStatus:status,intentSha256};
}
async function revision(ctx: CloudflareTeamContext) {const state=await restoreCloudflareTeam(ctx); if(state.kind!=='ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Cloudflare team request recovery', () => {
  it('fails closed without the explicit gate, current proof or owner grant', async () => {
    const request=vi.fn(), ctx=context(request);
    await expect(submitCloudflareTeam({...ctx,allowMutations:false},input,'')).rejects.toThrow(/not enabled/);
    await expect(submitCloudflareTeam({...ctx,current:() => false},input,'')).rejects.toThrow(/verify/i);
    await expect(submitCloudflareTeam({...ctx,identity:{...ctx.identity,permissions:['admin_users.read']}},input,'')).rejects.toThrow(/verify/i);
    expect(request).not.toHaveBeenCalled();
  });
  it('retains the exact invitation before sending and validates its server-correlated result', async () => {
    const response=await receipt(), request=vi.fn(async (path:string, options) => {
      const saved=await readPending(identity(),'team-cloudflare-v1','team');
      expect(saved).toMatchObject({request_key:key,intent:{operation:'invite',email:input.email,role:'staff',body:{email:input.email,role:'staff',displayName:input.displayName}}});
      expect(path).toBe('team/cloudflare/v1/invite'); expect(options).toEqual({authenticated:true,method:'POST',body:{email:input.email,role:'staff',displayName:input.displayName},idempotencyKey:key});
      return response;
    }), ctx=context(request);
    expect(await submitCloudflareTeam(ctx,input,await revision(ctx))).toMatchObject({status:'recorded',receipt:{emailStatus:'accepted'}});
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).toBeNull();
  });
  it('retains a lost response and treats a found unknown result as unresolved with writes disabled', async () => {
    const request=vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(await receipt('unknown')),ctx=context(request);
    await expect(submitCloudflareTeam(ctx,input,await revision(ctx))).rejects.toThrow(/unconfirmed/);
    const saved=await restoreCloudflareTeam(ctx);
    expect(saved).toMatchObject({kind:'owned',requestKey:key,attempt:{intent:{operation:'invite'}}});
    expect(await checkCloudflareTeam({...ctx,allowMutations:false},saved)).toMatchObject({emailStatus:'unknown'});
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).not.toBeNull();
    expect(request.mock.calls.filter(([,options]) => options?.method==='POST')).toHaveLength(1);
  });
  it('retries a not-found original only with the retained key and original body', async () => {
    const missing={ok:true,found:false,contractVersion:1}, request=vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(missing)
      .mockResolvedValueOnce(missing).mockResolvedValueOnce(await receipt()),ctx=context(request);
    await expect(submitCloudflareTeam(ctx,input,await revision(ctx))).rejects.toThrow(/unconfirmed/);
    const saved=await restoreCloudflareTeam(ctx); expect(await checkCloudflareTeam({...ctx,allowMutations:false},saved)).toBeNull();
    expect(await retryCloudflareTeam(ctx,saved)).toMatchObject({status:'recorded'});
    const sends=request.mock.calls.filter(([,options]) => options?.method==='POST');expect(sends).toHaveLength(2);expect(sends[1]).toEqual(sends[0]);
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).toBeNull();
  });
  it('never resends a found pending/unknown reservation on retry', async () => {
    const request=vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValue(await receipt('unknown')),ctx=context(request);
    await expect(submitCloudflareTeam(ctx,input,await revision(ctx))).rejects.toThrow(/unconfirmed/);
    const saved=await restoreCloudflareTeam(ctx);
    expect(await retryCloudflareTeam(ctx,saved)).toMatchObject({status:'unknown'});
    expect(request.mock.calls.filter(([,options]) => options?.method==='POST')).toHaveLength(1);
  });
  it('does not trust a different principal or a receipt for a different account', async () => {
    const request=vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({...await receipt(),email:'other@example.test'}),ctx=context(request);
    await expect(submitCloudflareTeam(ctx,input,await revision(ctx))).rejects.toThrow(/unconfirmed/);
    const wrong=await restoreCloudflareTeam({...ctx,principalId:'55555555-5555-4555-8555-555555555555'});
    expect(wrong).toEqual({kind:'owned',requestKey:key,attempt:null});
    await expect(retryCloudflareTeam({...ctx,principalId:'55555555-5555-4555-8555-555555555555'},wrong)).rejects.toThrow();
    await expect(checkCloudflareTeam(ctx,await restoreCloudflareTeam(ctx))).rejects.toThrow(/could not be verified/);
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).not.toBeNull();
  });
  it('does not clear a same-account receipt whose retained intent digest differs', async () => {
    const request=vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({...await receipt(),intentSha256:'f'.repeat(64)}),ctx=context(request);
    await expect(submitCloudflareTeam(ctx,input,await revision(ctx))).rejects.toThrow(/unconfirmed/);
    await expect(checkCloudflareTeam(ctx,await restoreCloudflareTeam(ctx))).rejects.toThrow(/could not be verified/);
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).toMatchObject({request_key:key});
  });
  it('rechecks versioned target details before a resend or access removal', async () => {
    const original={contractVersion:1,memberId:member,email:'staff@example.test',role:'staff',accessStatus:'invited',authVersion:1,invitationCount:1,canResend:true};
    const request=vi.fn().mockResolvedValueOnce(original).mockResolvedValueOnce({...original,authVersion:2}),ctx=context(request);
    const target=await readCloudflareTeamTarget(ctx,member), observed=await revision(ctx);
    await expect(submitCloudflareTeam(ctx,{kind:'resend',member:target},observed)).rejects.toThrow(/changed/);
    expect(request.mock.calls.every(([,options]) => options?.method!=='POST')).toBe(true);
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).toBeNull();
  });
  it('never submits when the gate closes during the target read', async () => {
    let enabled=true;
    const row={contractVersion:1,memberId:member,email:'staff@example.test',role:'staff',accessStatus:'active',authVersion:1,invitationCount:1,canResend:false};
    const request=vi.fn(async () => {enabled=false; return row;}),ctx={...context(request),isEnabled:() => enabled};
    await expect(submitCloudflareTeam(ctx,{kind:'revoke',member:row as never},await revision(ctx))).rejects.toThrow(/not enabled/);
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).toBeNull();
  });
  it('keeps the original reference when owner authority changes during a successful response', async () => {
    let current=true; const accepted=await receipt();
    const request=vi.fn(async()=>{current=false;return accepted;}),ctx={...context(request),current:()=>current};
    await expect(submitCloudflareTeam(ctx,input,await revision(ctx))).rejects.toThrow(/unconfirmed/);
    expect(await readPending(ctx.identity,'team-cloudflare-v1','team')).toMatchObject({request_key:key});
  });
  it('blocks a concurrent team submission and does not expose invitation details in the shared fence', async () => {
    let release!: () => void, started!: () => void, locked=false;
    const entered=new Promise<void>(resolve=>{started=resolve;}), lost=new Promise<never>((_resolve,reject)=>{release=()=>reject(new Error('lost'));});
    const lock:NonNullable<CloudflareTeamContext['lock']>=async (_name,work)=>{if(locked) throw new Error('locked');locked=true;try{return await work();}finally{locked=false;}};
    const request=vi.fn(async()=>{started();return lost;}),ctx={...context(request),lock},first=await revision(ctx),second=await revision(ctx);
    const sending=submitCloudflareTeam(ctx,input,first);await entered;
    await expect(submitCloudflareTeam(ctx,input,second)).rejects.toThrow('locked');
    release();await expect(sending).rejects.toThrow(/unconfirmed/);
    const shared=localStorage.getItem('collect.admin.pending-fence.v2')!;
    expect(shared).not.toContain(input.email);expect(shared).not.toContain(input.displayName);expect(request).toHaveBeenCalledTimes(1);
  });
});
