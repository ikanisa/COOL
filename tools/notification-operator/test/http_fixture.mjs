import http from 'node:http';
import {syntheticPasswordProof,syntheticEmailProof} from './human_fixture.mjs';
import {randomUUID,randomBytes} from 'node:crypto';
import {MARKER,sha,canonical,ORIGINS} from '../src/contract.mjs';

// Deliberately synthetic local HTTP authority; it is not a hosted/provider acceptance fixture.
export async function fixture({origin=ORIGINS[0]}={}) {
  const state={origin,captchas:new Map(),authChecks:[],now:Date.now(),sessions:new Map(),challenges:new Map(),receipts:new Map(),jobs:new Map(),counts:{},effectCounts:{},fault:null,transform:null,
    principal:randomUUID(),account:randomUUID(),password:'synthetic-local-password-unique',code:'012345',current:null};
  function user(session){return {id:state.account,email:'synthetic@example.invalid',role:session.role,sessionId:session.public,expiresAt:new Date(session.expires).toISOString(),permissions:session.permissions,assuranceLevel:session.aal,mfaAt:session.aal===2?new Date(session.mfa).toISOString():null,principalId:state.principal,financialModel:'canonical_evidence_ledger'};}
  const sidecar=session=>({contractVersion:1,sessionId:session.public,emailVerifiedAt:session.emailVerifiedAt===null?null:new Date(session.emailVerifiedAt).toISOString()});
  function createSession(proof){const next=randomBytes(32).toString('hex'),session={canonical:randomUUID(),public:randomUUID(),expires:state.now+3600000,aal:1,mfa:null,emailVerifiedAt:proof?state.now:null,role:'owner',permissions:['assisted_sms.read','assisted_sms.manage']};state.sessions.set(next,session);state.current=session;return {next,session};}
  function captcha(body,purpose){const proof=state.captchas.get(body.captcha_token);state.captchas.delete(body.captcha_token);return proof&&proof.origin===origin&&proof.purpose===purpose&&proof.expires>Date.now();}
  const cookie=token=>`__Host-collect_admin=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${token?'3600':'0'}; Secure`;
  function addJob(){const job={id:randomUUID(),payment:randomUUID(),state:'queued',fence:0,destination:'+250788123456',body:'Collect: your contribution is recorded. This is an internal receipt, not provider settlement.'};state.jobs.set(job.id,job);return job;}
  const first=addJob(),second=addJob();state.first=first;state.second=second;state.addJob=addJob;
  const respond=(response,status,value,headers={})=>{
    const path=response.req.url;
    if(state.authFault===path){state.authFault=null;response.destroy();return;}
    if(path.startsWith('/api/admin/auth/')&&state.authTransform)value=state.authTransform(path,value,headers);
    if(!response.destroyed)response.writeHead(status,{'Content-Type':'application/json',...headers}).end(JSON.stringify(value));
  };
  function fail(response,status,code){respond(response,status,{ok:false,error:{code,message:'synthetic refusal'}});}
  const server=http.createServer(async(req,res)=>{
    try {
      const path=req.url;state.counts[path]=(state.counts[path]??0)+1;
      if(req.headers.origin!==origin||req.headers['x-collect-admin']!=='1'||req.headers['sec-fetch-site']!=='same-origin')return fail(res,403,'origin_required');
      if(req.method==='POST'&&req.headers['x-collect-requested-with']!=='collect-admin')return fail(res,403,'requested_with_required');
      const chunks=[];for await(const chunk of req)chunks.push(chunk);const raw=Buffer.concat(chunks);const body=raw.length?JSON.parse(raw):{};
      const token=(req.headers.cookie??'').match(/^__Host-collect_admin=([a-f0-9]{64})$/)?.[1];let session=state.sessions.get(token);
      if(session?.expires<=state.now){state.sessions.delete(token);session=null;}
      state.authChecks.push({path,cookie:token??null,csrf:req.headers['x-collect-csrf']??null,requestedWith:req.headers['x-collect-requested-with']??null});
      if(path==='/api/admin/auth/otp'&&req.method==='POST') {
        if(!captcha(body,'sign_in'))return fail(res,403,'captcha_verification_failed');
        if(body.email!=='synthetic@example.invalid'||Object.keys(body).some(k=>!['email','captcha_token'].includes(k)))return fail(res,400,'invalid_credentials');
        const id=randomUUID();state.challenges.set(id,{purpose:'sign_in',expiry:state.now+300000});
        return respond(res,200,{challenge_id:id,retry_after:60,expires_in:300,delivery_status:state.deliveryStatus??'accepted',channel:'email'});
      }
      if(path==='/api/admin/auth/verify'&&req.method==='POST') {
        const challenge=state.challenges.get(body.challenge_id);
        if(challenge?.purpose!=='sign_in'||challenge.expiry<=state.now||body.code!==state.code||Object.keys(body).some(k=>!['challenge_id','code','captcha_token'].includes(k)))return fail(res,400,'invalid_credentials');
        state.challenges.delete(body.challenge_id);const created=createSession(true);session=created.session;
        return respond(res,200,{user:user(session),expiresAt:user(session).expiresAt,csrfToken:sha('collect-admin-csrf:'+created.next)},{'Set-Cookie':cookie(created.next)});
      }
      if(path==='/api/admin/auth/login'&&req.method==='POST') {
        if(!captcha(body,'password'))return fail(res,403,'captcha_verification_failed');
        if(body.email!=='synthetic@example.invalid'||body.password!==state.password)return fail(res,401,'invalid_credentials');
        const created=createSession(false);session=created.session;
        return respond(res,200,{user:user(session),expiresAt:user(session).expiresAt,csrfToken:sha('collect-admin-csrf:'+created.next)},{'Set-Cookie':cookie(created.next)});
      }
      if(path==='/api/admin/auth/session'&&req.method==='GET') {
        if(state.sessionFault){const fault=state.sessionFault;state.sessionFault=null;return fail(res,fault,fault===409?'session_refresh_pending':'session_read_failed');}
        return respond(res,200,{user:session?user(session):null,expiresAt:session?user(session).expiresAt:null,ownerEmail:'info@ikanisa.com',csrfToken:session?sha('collect-admin-csrf:'+token):null});
      }
      if(!session)return fail(res,401,'authentication_required');
      if(req.method==='POST'&&req.headers['x-collect-csrf']!==sha('collect-admin-csrf:'+token))return fail(res,403,'csrf_rejected');
      if(path==='/api/admin/auth/email-verification'&&req.method==='GET') {
        if(state.sidecarFault){const status=state.sidecarFault;state.sidecarFault=null;return fail(res,status,status===401?'authentication_required':'admin_email_operation_unknown');}
        return respond(res,200,sidecar(session));
      }
      if(path==='/api/admin/auth/email/request'&&req.method==='POST') {
        if(!captcha(body,'sensitive'))return fail(res,403,'captcha_verification_failed');
        if(Object.keys(body).some(k=>k!=='captcha_token'))return fail(res,400,'invalid_credentials');
        const id=randomUUID();state.challenges.set(id,{purpose:'sensitive',session,cookie:token,expiry:state.now+300000});
        return respond(res,202,{challenge_id:id,retry_after:60,expires_in:300,delivery_status:state.deliveryStatus??'accepted'});
      }
      if(path==='/api/admin/auth/email/verify'&&req.method==='POST') {
        const challenge=state.challenges.get(body.challenge_id);
        if(challenge?.purpose!=='sensitive'||challenge.session!==session||challenge.cookie!==token||challenge.expiry<=state.now||body.code!==state.code||Object.keys(body).some(k=>!['challenge_id','code','captcha_token'].includes(k)))return fail(res,400,'invalid_credentials');
        if(state.emailVerifyFault==='verify'){state.emailVerifyFault=null;return fail(res,503,'admin_email_operation_unknown');}
        state.challenges.delete(body.challenge_id);state.now=Math.max(state.now,(session.emailVerifiedAt??state.now)+1);session.emailVerifiedAt=state.now;
        if(state.emailVerifyFault==='cleanup'){state.emailVerifyFault=null;return fail(res,503,'admin_email_operation_unknown');}
        return respond(res,200,sidecar(session));
      }
      if(path==='/api/admin/auth/logout'&&req.method==='POST'){state.sessions.delete(token);return respond(res,200,{ok:true},{'Set-Cookie':cookie('')});}
      if(path!=='/api/admin/notification-operator'||req.method!=='POST')return fail(res,404,'not_found');
      const action=body.action;state.counts[action]=(state.counts[action]??0)+1;
      if(!Number.isSafeInteger(session.emailVerifiedAt)||session.emailVerifiedAt>state.now||state.now-session.emailVerifiedAt>300000)return fail(res,403,'recent_email_sign_in_required');
      if(!session.permissions.includes(action==='list_pending'?'assisted_sms.read':'assisted_sms.manage'))return fail(res,403,'permission_required');
      const fault=state.fault?.action===action?state.fault:null;if(fault)state.fault=null;
      if(fault?.before){res.destroy();return;}
      const args={...body};delete args.action;
      const old=state.receipts.get(body.request_id);
      let result;
      if(action==='get_operation') {
        if(old&&old.session!==session.canonical)return fail(res,409,'request_conflict');
        result={...MARKER,request_id:body.request_id,observed:!!old,receipt:old?structuredClone(old.stored):null,may_send:false};
      } else if(old) {
        if(old.session!==session.canonical||old.action!==action||old.fingerprint!==canonical(args))return fail(res,409,'request_conflict');
        result=action==='record_send_start'?{...old.stored,replay:true,may_send:false,acknowledgement:'recorded_start_permit_not_reissued'}:{...old.stored,replay:true};
      } else if(action==='list_pending') {
        const jobs=[...state.jobs.values()].filter(job=>['queued','claimed','send_started','uncertain'].includes(job.state));
        result={...MARKER,items:jobs.map(job=>({id:job.id,payment_id:job.payment,state:job.state,created_at:new Date(state.now).toISOString(),fence:job.fence,attempt_id:job.attempt??null})),next_cursor:null};
      } else {
        const job=state.jobs.get(body.job_id)??[...state.jobs.values()].find(job=>job.attempt===body.attempt_id);
        if(!job)return fail(res,404,'job_not_found');
        const currentClaim=()=>job.claim?.session===session.canonical&&job.claim.public===session.public&&job.claim.emailVerifiedAt===session.emailVerifiedAt&&job.claim.token===body.claim_token&&job.fence===body.fence_version&&job.claim.expiry>state.now;
        const common=()=>({job_id:job.id,claim_token:job.claim.token,fence_version:job.fence});
        const pair=()=>({originating_session_id:session.canonical,public_session_id:session.public});
        if(action==='claim') {
          if(job.state!=='queued'||job.fence!==body.expected_fence)return fail(res,409,'claim_conflict');job.fence++;job.state='claimed';
          job.claim={session:session.canonical,public:session.public,emailVerifiedAt:session.emailVerifiedAt,token:randomUUID(),expiry:state.now+120000};
          result={...MARKER,...common(),worker_id:body.worker_id,claim_expires_at:new Date(job.claim.expiry).toISOString(),...pair()};
        } else if(action==='get_claimed') {
          if(!currentClaim()||job.state!=='claimed')return fail(res,409,'claim_stale');
          result={...MARKER,...common(),destination_e164:job.destination,destination_sha256:sha(job.destination),destination_revision:1,message_body:job.body,body_sha256:sha(job.body),payment_id:job.payment,template_key:'contribution_recorded',claim_expires_at:new Date(job.claim.expiry).toISOString()};
        } else if(action==='confirm') {
          if(!currentClaim()||body.body_sha256!==sha(job.body)||body.destination_sha256!==sha(job.destination)||body.destination_revision!==1||body.user_confirmation!==true)return fail(res,409,'confirmation_stale');
          job.confirmation=body.confirmation_id;result={...MARKER,...common(),confirmation_id:job.confirmation,body_sha256:sha(job.body),destination_sha256:sha(job.destination),destination_revision:1,expires_at:new Date(job.claim.expiry).toISOString(),...pair()};
        } else if(action==='record_send_start') {
          if(!currentClaim()||job.state!=='claimed'||body.confirmation_id!==job.confirmation)return fail(res,409,'confirmation_stale');
          job.state='send_started';job.attempt=randomUUID();result={...MARKER,...common(),attempt_id:job.attempt,confirmation_id:job.confirmation,state:'send_started',...pair(),replay:false,may_send:true,acknowledgement:'first_committed_response_only'};
        } else if(action==='record_outcome') {
          if(!job.attempt)return fail(res,409,'attempt_required');job.state=body.observation==='uncertain'?'uncertain':'recorded';
          result={...MARKER,attempt_id:job.attempt,observation:body.observation,evidence_reference_sha256:body.evidence_reference_sha256,may_send:false};
        } else if(action==='release_claim') {
          if(!currentClaim()||job.state!=='claimed')return fail(res,409,'claim_stale');job.state='queued';job.fence++;result={...MARKER,job_id:job.id,state:'queued',fence_version:job.fence};
        } else return fail(res,400,'unsupported_action');
        if(action!=='get_claimed') {
          const stored=structuredClone(result);if(action==='record_send_start'){delete stored.replay;delete stored.may_send;delete stored.acknowledgement;}
          state.receipts.set(body.request_id,{session:session.canonical,action,fingerprint:canonical(args),stored});state.effectCounts[action]=(state.effectCounts[action]??0)+1;
        }
      }
      if(fault?.after){res.destroy();return;}
      if(fault?.gate){fault.entered?.();await fault.gate;}
      if(state.transform)result=state.transform(action,result);
      respond(res,200,{ok:true,result});
    } catch {fail(res,500,'fixture_internal_error');}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const endpoint='http://127.0.0.1:'+server.address().port;
  state.fetch=async(url,options)=>{
    if(!url.startsWith(origin+'/'))throw new Error('fixture_origin_refused');
    return fetch(endpoint+new URL(url).pathname,options);
  };
  state.passwordProof=(options={})=>syntheticPasswordProof({origin,...options,onToken:(token,descriptor)=>state.captchas.set(token,{origin:descriptor.admin_origin,purpose:'password',expires:descriptor.expires_at_ms})});
  state.emailProof=(purpose='sign_in',options={})=>syntheticEmailProof({origin,...options,purpose,onToken:(token,descriptor)=>state.captchas.set(token,{origin:descriptor.admin_origin,purpose,expires:descriptor.expires_at_ms})});
  state.login=async client=>{const challenge=await client.requestEmailSignIn('synthetic@example.invalid',await state.emailProof());return client.verifyEmailSignIn(challenge.challenge_id,state.code);};
  state.reverify=async client=>{state.now+=1;const challenge=await client.requestEmailVerification(await state.emailProof('sensitive'));return client.verifyEmail(challenge.challenge_id,state.code);};
  state.close=()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});
  return state;
}
