import {webcrypto} from 'node:crypto';
import {fireEvent, render, screen, waitFor, within} from '@testing-library/react';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {sha256Text} from '../../src/features/core/pendingAttempt';
import {SessionProvider} from '../../src/session/SessionProvider';
import {TeamPage} from '../../src/session/TeamPage';

const actor='11111111-1111-4111-8111-111111111111', principal='22222222-2222-4222-8222-222222222222', member='33333333-3333-4333-8333-333333333333', sessionId='55555555-5555-4555-8555-555555555555';
const originalLocks=Object.getOwnPropertyDescriptor(navigator,'locks');
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
beforeEach(() => {
  Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});sessionStorage.clear();localStorage.clear();
  Object.defineProperty(navigator,'locks',{configurable:true,value:{request:async (_name:string,_options:unknown,work:(lock:object)=>Promise<unknown>)=>work({})}});
});
afterEach(() => {if(originalLocks) Object.defineProperty(navigator,'locks',originalLocks);else Reflect.deleteProperty(navigator,'locks');});
function transport() {
  const keys:string[]=[];
  const fetchImpl=vi.fn(async (url:RequestInfo|URL,options?:RequestInit) => {
    const path=String(url), expiresAt=new Date(Date.now()+3600000).toISOString();
    if(path.endsWith('/auth/session')) return reply({user:{id:actor,sessionId,email:'info@ikanisa.com',role:'owner',permissions:['admin_users.read','admin_users.manage'],assuranceLevel:2,mfaAt:new Date().toISOString(),principalId:principal,financialModel:'canonical_evidence_ledger'},expiresAt});
    if(path.endsWith('/team')) return reply({currentEmail:'info@ikanisa.com',canManage:true,permissionsByRole:{},members:[]});
    if(path.endsWith('/team/cloudflare/v1/request-status')) return reply({ok:true,found:false,contractVersion:1});
    if(path.endsWith('/team/cloudflare/v1/invite')) {
      const key=(options?.headers as Record<string,string>)['Idempotency-Key'];keys.push(key);
      if(keys.length===1) throw new TypeError('lost response');
      const hash=await sha256Text(`collect-admin-team-v1:${principal}:${key}`), requestId=`${hash.slice(0,8)}-${hash.slice(8,12)}-4${hash.slice(13,16)}-8${hash.slice(17,20)}-${hash.slice(20,32)}`;
      const intentSha256=await sha256Text('{"body":{"displayName":"Staff Example","email":"staff@example.test","role":"staff"},"path":"/team/cloudflare/v1/invite"}');
      return reply({ok:true,found:true,contractVersion:1,requestId,operation:'invite',memberId:member,email:'staff@example.test',role:'staff',accessStatus:'invited',authVersion:1,eventId:requestId,emailStatus:'accepted',intentSha256});
    }
    return reply({error:{code:'not_found'}},404);
  });
  return {keys,fetchImpl};
}
describe('Cloudflare team review',()=>{
  it('keeps writes off when only the recovery protocol is selected',async()=>{
    const {fetchImpl}=transport();
    render(<SessionProvider config={{backend:'cloudflare',captchaEnabled:false,googleEnabled:false,fetchImpl}}><TeamPage onVerify={()=>undefined} cloudflareRecoveryVersion={1} /></SessionProvider>);
    expect(await screen.findByRole('button',{name:'Review pending team request'})).toBeVisible();
    expect(screen.queryByRole('button',{name:'Review invitation'})).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.every(([,options])=>!options?.method||options.method==='GET')).toBe(true);
  });
  it('shows original details and retries only after checking the same retained key',async()=>{
    const {fetchImpl,keys}=transport();
    render(<SessionProvider config={{backend:'cloudflare',captchaEnabled:false,googleEnabled:false,fetchImpl}}><TeamPage onVerify={()=>undefined} cloudflareRecoveryVersion={1} allowMutations /></SessionProvider>);
    fireEvent.change(await screen.findByLabelText('Team email'),{target:{value:'staff@example.test'}});
    fireEvent.change(screen.getByLabelText('Team name'),{target:{value:'Staff Example'}});
    fireEvent.click(screen.getByRole('button',{name:'Review invitation'}));
    const confirm=screen.getByRole('dialog',{name:'Invite teammate?'});
    expect(within(confirm).getByText('Account: staff@example.test')).toBeVisible();expect(keys).toHaveLength(0);
    fireEvent.click(within(confirm).getByRole('button',{name:'Confirm team request'}));
    await waitFor(()=>expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(await screen.findByText(/team result is unconfirmed/i)).toBeVisible();expect(keys).toHaveLength(1);
    fireEvent.click(await screen.findByRole('button',{name:'Check original team request'}));
    fireEvent.click(await screen.findByRole('button',{name:'Review same team request'}));
    const retry=screen.getByRole('dialog',{name:'Retry original team request?'});
    expect(within(retry).getByText('Email: staff@example.test')).toBeVisible();expect(within(retry).getByText('displayName: Staff Example')).toBeVisible();
    fireEvent.click(within(retry).getByRole('button',{name:'Retry same request'}));
    await waitFor(()=>expect(keys).toHaveLength(2));expect(keys[1]).toBe(keys[0]);
    expect(await screen.findByText('Invitation accepted for sending. Inbox delivery is not confirmed.')).toBeVisible();
  });
});
