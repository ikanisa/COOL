// Synthetic loopback transport fixture. It is not database/provider acceptance.
import { createHash, randomUUID } from 'node:crypto';
const digest = value => createHash('sha256').update(value).digest('hex');
export function createLocalBrowserFixture() {
  const users=['99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000002'];
  const emails=['operator-a@example.invalid','operator-b@example.invalid'];
  const sessions=new Map(), sources=new Map(), drafts=new Map(), intents=new Map(), results=new Map();
  const calls=[];
  let actorIndex=0,revoked=false,missingNextSource=false;const lostResponses=new Set();
  const permissions=['collections.read','receivers.read','payments.read','payment_events.read','ledger.read','overview.read','collections.moderate','receivers.manage','users.read','transactions.read','reconciliation.manage','ledgers.read','sms_receipts.read','notifications.read','audit.read','settings.manage','feature_flags.manage','system_health.read','admin_users.manage'];
  function authResponse() {
    const sid=randomUUID(), uid=users[actorIndex],exp=Math.floor(Date.now()/1000)+3600;
    const claims={sub:uid,session_id:sid,role:'authenticated',aal:'aal1',exp};
    const token=Buffer.from('{}').toString('base64url')+'.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.synthetic-loopback-only';
    const user={id:uid,aud:'authenticated',role:'authenticated',email:emails[actorIndex],email_confirmed_at:'2026-09-30T00:00:00Z',app_metadata:{},user_metadata:{},created_at:'2026-09-30T00:00:00Z'};
    sessions.set(token,{uid,sid,active:true});
    return {access_token:token,refresh_token:'synthetic-refresh-'+sid,token_type:'bearer',expires_in:3600,expires_at:exp,user};
  }
  function caller(req) {
    const token=(req.headers.authorization||'').replace(/^Bearer /,'');const s=sessions.get(token);
    if(!s?.active) throw Error('roster_session_required');if(revoked)throw Error('roster_actor_unavailable');return s;
  }
  function owned(source,s) {if(!source||source.uid!==s.uid||source.sid!==s.sid)throw Error('roster_import_unavailable');}
  function preview(source,rows,{parent=null,requestId=null}={}) {
    const normalized=rows.map(r=>({member_name:r.member_name,momo_name:r.momo_name,momo_number:r.momo_number.startsWith('+')?r.momo_number:'+250'+r.momo_number.replace(/^0/,'')}));
    const value={contract_version:1,ok:true,import_id:source.id,source_sha256:source.sha,source_kind:'text',source_receipt:{request_id:source.request,source_size:source.size,client_filename:'pasted-roster.txt',declared_mime:'text/plain',detected_type:'utf8_text',derived_sha256:null,derived_assurance:null,extraction_id:null,ai_consent:false,consent_version:null,parser_version:'collect-roster-parser-v1',schema_version:'collect-roster-rows-v1'},revision_id:randomUUID(),parent_revision_id:parent?.revision_id??null,revision_number:parent?parent.revision_number+1:1,reviewed_rows_sha256:digest(JSON.stringify(normalized)),can_submit:!!parent,requires_human_review:!parent,processing_method:parent?'human_review':'deterministic',model:null,rows:normalized.map((r,i)=>({source_row:i+2,...r,confidence:1,issues:[],ready:true})),row_count:normalized.length,ready_count:normalized.length,error_count:0,normalized_rows:normalized,expires_at:source.expires};
    if(requestId)results.set(requestId,value);return value;
  }
  function status(source) {return {contract_version:1,ok:true,import_id:source.id,state:source.commit?'committed':'preview_ready',expires_at:source.expires,preview:{...source.latest,can_submit:source.commit?false:source.latest.can_submit},commit:source.commit??null,error_code:null};}
  async function handle(req,res,path,body) {
    // Receiving response bytes prevents Chromium's transport retry of a reused
    // socket closed before headers. The body is deliberately incomplete; the
    // caller cannot receive or decode an acknowledgement.
    const loseTransport=()=>{res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store','Content-Length':'4096'});res.flushHeaders();res.write('{');setTimeout(()=>res.destroy(),20);};
    const reply=(value,code=200)=>{if(lostResponses.delete(path.split('/').at(-1))){loseTransport();return;}res.writeHead(code,{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':req.headers.origin||'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Access-Control-Expose-Headers':'content-range'});res.end(JSON.stringify(value));};
    if(req.method==='OPTIONS'){reply({});return true;}
    if(!path.startsWith('/auth/v1/')&&!path.startsWith('/rest/v1/')&&!path.startsWith('/functions/v1/'))return false;
    const action=path.split('/').at(-1);calls.push({method:req.method,action,time:new Date().toISOString(),payloadDigest:body?digest(JSON.stringify(body)):null});
    try {
      if(path==='/auth/v1/otp'){
        if(req.method!=='POST'||!emails.includes(body.email)||body.phone!=null||body.create_user!==false)throw Error('synthetic_approved_email_required');
        reply({});return true;
      }
      if(path==='/auth/v1/verify'){
        if(req.method!=='POST'||!emails.includes(body.email)||body.phone!=null||body.type!=='email'||body.token!=='123456')throw Error('synthetic_email_verification_required');
        const previous=actorIndex;actorIndex=emails.indexOf(body.email);const response=authResponse();actorIndex=previous;
        reply(response);return true;
      }
      if(path==='/auth/v1/logout'){const c=caller(req);for(const v of sessions.values())if(v.uid===c.uid)v.active=false;reply({});return true;}
      if(path==='/auth/v1/user'){const c=caller(req);reply({id:c.uid,aud:'authenticated',role:'authenticated',email:emails[users.indexOf(c.uid)],email_confirmed_at:'2026-09-30T00:00:00Z',app_metadata:{},user_metadata:{},created_at:'2026-09-30T00:00:00Z'});return true;}
      const s=caller(req);
      if(action==='admin_current_user'){reply({user_id:s.uid,display_name:s.uid===users[0]?'Local Operator A':'Local Operator B',phone_masked:'+250 *** 9001',roles:['platform_owner'],permissions});return true;}
      if(action==='admin_get_operator_approval_v1'){
        if(body.p_user_id!==s.uid)throw Error('synthetic_operator_target_mismatch');
        reply({contract_version:1,user_id:s.uid,provider:'email',mode:'email',identity_masked:'o***@***',approved_at:'2026-09-30T00:00:00Z',expires_at:null,status:'approved',approved:true,role_granted:true,admin_access:true,access_status:'active'});return true;
      }
      if(action==='admin_runtime_config'){reply({navigation_items:[],queue_specs:[]});return true;}
      if(action==='admin_overview'){reply({metrics:[{label:'Local synthetic receipts',value:'0',status:'ok'}]});return true;}
      if(action==='admin_queue_sla'){reply(null);return true;}
      if(action.startsWith('admin_list')){reply({rows:[],total:0});return true;}
      if(action==='prepare-roster-import') {
        if(missingNextSource){missingNextSource=false;loseTransport();return true;}
        const text=body.content;if(typeof text!=='string'||text.trim().split('\n')[0]!=='member_name,momo_name,momo_number')throw Error('fixture_roster_text_invalid');const source={id:randomUUID(),request:body.request_id,sha:digest(text),size:Buffer.byteLength(text),uid:s.uid,sid:s.sid,expires:new Date(Date.now()+86400000).toISOString()};
        const parsed=text.trim().split('\n').slice(1).map(line=>{const [member_name,momo_name,momo_number]=line.split(',');return {member_name,momo_name,momo_number};});
        source.initial=preview(source,parsed);source.latest=source.initial;sources.set(source.request,source);reply(source.initial);return true;
      }
      const source=[...sources.values()].find(x=>x.id===body.p_import_id);
      if(action==='admin_save_roster_import_draft') {
        owned(source,s);const old=drafts.get(source.id);
        if(old?.checkpoint_id===body.p_checkpoint_id){if(old.payload!==body.p_payload)throw Error('roster_request_conflict');}
        else {if((old?.checkpoint_id??null)!==body.p_previous_checkpoint_id)throw Error('roster_draft_superseded');
          if(digest(body.p_payload)!==body.p_payload_sha256)throw Error('roster_recovery_payload_invalid');
          drafts.set(source.id,{checkpoint_id:body.p_checkpoint_id,payload:body.p_payload,payload_sha256:body.p_payload_sha256});}
        reply({contract_version:1,ok:true,import_id:source.id,checkpoint_id:body.p_checkpoint_id,payload_sha256:body.p_payload_sha256,expires_at:source.expires});return true;
      }
      if(action==='admin_stage_roster_import_intent') {
        owned(source,s);if(digest(body.p_payload)!==body.p_payload_sha256)throw Error('roster_recovery_payload_invalid');
        const old=intents.get(body.p_request_id);if(old&&old.p_payload!==body.p_payload)throw Error('roster_request_conflict');
        intents.set(body.p_request_id,body);reply({contract_version:1,ok:true,import_id:source.id,request_id:body.p_request_id,kind:body.p_kind,payload_sha256:body.p_payload_sha256,expires_at:source.expires});return true;
      }
      if(action==='admin_execute_roster_import_intent') {
        const i=intents.get(body.p_request_id),p=JSON.parse(i.p_payload),src=[...sources.values()].find(x=>x.id===i.p_import_id);owned(src,s);
        if(!body.p_human_affirmed||body.p_payload_sha256!==i.p_payload_sha256)throw Error('roster_confirmation_required');
        let result=results.get(body.p_request_id);
        if(!result && i.p_kind==='review'){if(p.p_parent_revision_id!==src.latest.revision_id)throw Error('roster_revision_superseded');result=preview(src,p.p_rows,{parent:src.latest,requestId:body.p_request_id});src.latest=result;}
        if(!result && i.p_kind==='commit'){result={contract_version:1,ok:true,request_id:p.p_request_id,import_id:src.id,revision_id:p.p_revision_id,reviewed_rows_sha256:p.p_reviewed_rows_sha256,collection_id:p.p_collection_id??randomUUID(),mode:p.p_mode,roster_count:src.latest.row_count,share_code_ready:true,replayed:false};src.commit=result;results.set(body.p_request_id,result);}
        reply({contract_version:1,ok:true,request_id:body.p_request_id,import_id:src.id,kind:i.p_kind,payload_sha256:i.p_payload_sha256,result});return true;
      }
      if(action==='admin_recover_roster_import') {
        const src=sources.get(body.p_upload_request_id);if(!src){reply({contract_version:1,ok:true,upload_request_id:body.p_upload_request_id,import_id:null,source_sha256:null,state:'missing_source',initial_preview:null,status:null,requested_intent_id:body.p_pending_request_id,intent:null,draft:null});return true;}owned(src,s);const i=intents.get(body.p_pending_request_id);
        reply({contract_version:1,ok:true,upload_request_id:src.request,import_id:src.id,source_sha256:src.sha,state:src.commit?'committed':'preview_ready',initial_preview:src.initial,status:status(src),requested_intent_id:body.p_pending_request_id,intent:i?{request_id:i.p_request_id,kind:i.p_kind,payload_sha256:i.p_payload_sha256,payload:i.p_payload,result:results.get(i.p_request_id)??null,expired:false}:null,draft:drafts.get(src.id)??null});return true;
      }
      if(action==='admin_get_roster_import'){owned(source,s);reply(status(source));return true;}
      reply({code:'PGRST202',message:'Synthetic fixture endpoint unavailable'},404);return true;
    } catch(error){reply({code:'42501',message:error.message},403);return true;}
  }
  return {handle,calls,lastIssuedOwner:()=>{const value=[...sessions.values()].at(-1);return value?{actor:value.uid,session:value.sid}:null;},issueSession:index=>{const previous=actorIndex;actorIndex=index;const session=authResponse();actorIndex=previous;return session;},omitNextSource:()=>missingNextSource=true,loseNextResponse:action=>lostResponses.add(action),setActor:index=>actorIndex=index,setRevoked:value=>revoked=value,privateValues:()=>[...drafts.values()].map(v=>v.payload),counts:()=>({sources:sources.size,drafts:drafts.size,intents:intents.size,executions:results.size})};
}
