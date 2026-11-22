import {readNativeBody,discardNativeBody,requireActiveNativeRequest,nativeRequestErrorStatus,MAX_NATIVE_REQUEST_BYTES,MAX_NATIVE_BATCH_REQUEST_BYTES,MAX_NATIVE_PREVIEW_REQUEST_BYTES} from './wire/request-boundary.mjs';
import {ContractViolation,CONTRACT_VERSION,parseWire,contractRoute,requestBinding,validateNativeRequest,bindNativeResponse,validateNativeQuery,heldObservationOperation} from './wire/native-contract.mjs';
import {BuriError,ObservationUploadUnresolved,requirePort,requireThat} from './errors.js';
import {exactKeys,requireId,requireRequestId} from './values.js';
import {LISTING_QUERY_KEYS} from './listing-query.js';
/** Candidate native API adapter; attach only to an admitted Collect Edge request.
 * Do not replace the current router or bypass its application fence.
 * Origin/networkBucket are server-owned deployment inputs, not forwarded client claims.
 */
export function createNativeHandler({auth,records,contributions,members,gateway,observations=null,cursor=null,origin,networkBucket,strictContract=false,groupId,requestReadTimeoutMs=15000,verifiedObservationStatusEnabled=false}) {
  requirePort(auth,['login','authenticate','logout','changePasscode','manageStaff']);
  requirePort(records,['home','page','detail','exportLedger','commandStatus']);
  requirePort(contributions,['allocate']);requirePort(members,['enroll','setActive']);
  requirePort(gateway,['status','replace']);
  requireThat(typeof networkBucket==='function','trusted_network_resolver_required',503);
  const configured=new URL(origin);requireThat(configured.protocol==='https:'&&configured.origin===origin,'tls_origin_required',503);
  if(strictContract)requireId(groupId);
  const headers={...(strictContract?{'X-BuriMunsi-Contract':CONTRACT_VERSION}:{}),'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Pragma':'no-cache','X-Content-Type-Options':'nosniff'};
  const paymentReferenceHeader='X-BuriMunsi-Payment-Reference-Version';
  async function readBody(req,allowed,required=allowed,maxBytes=MAX_NATIVE_REQUEST_BYTES) {
    requireThat((req.headers.get('content-type')??'').split(';')[0].trim()==='application/json','json_required',415);
    const all=await readNativeBody(req,{timeoutMs:requestReadTimeoutMs,maxBytes});
    let value;try{value=strictContract?parseWire(all,maxBytes):JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));}catch(error){if(error instanceof ContractViolation)throw error;throw new BuriError('invalid_json',400);}finally{all.fill(0);}
    return strictContract?value:exactKeys(value,allowed,required);
  }
  return async req=>{
    // Request-local state prevents concurrent requests from sharing identity metadata.
    let wireRoute=null,wireBinding=null,requestBody=null,wireQuery=null;
    const body=async(request,allowed,required=allowed)=>{
      const maxBytes=wireRoute?.operation==='onboardingPreview'?MAX_NATIVE_PREVIEW_REQUEST_BYTES:
        wireRoute?.operation==='membersImport'?MAX_NATIVE_BATCH_REQUEST_BYTES:MAX_NATIVE_REQUEST_BYTES;
      const value=await readBody(request,allowed,required,maxBytes);
      if(strictContract)validateNativeRequest(wireRoute.operation,value);
      requireActiveNativeRequest(req);requestBody=value;return value;
    };
    const json=(data,status=200)=>{
      let value={ok:true,data};
      if(strictContract){
        try{value=bindNativeResponse(wireRoute,wireBinding,requestBody,data,req.headers.get('x-burimunsi-operation-origin'));}
        catch(_){throw new BuriError('contract_invalid_response',503);}
      }
      return new Response(JSON.stringify(value),{status,headers:wireRoute?.operation==='paymentDetailV1'?{...headers,[paymentReferenceHeader]:'1'}:headers});
    };
    try{
      requireActiveNativeRequest(req);
      const url=new URL(req.url);
      requireThat(url.origin===origin,'origin_denied',403);
      // Native client doesn't need CORS. Unexpected browser cross-origin requests fail closed.
      const requestOrigin=req.headers.get('origin');requireThat(!requestOrigin||requestOrigin===origin,'origin_denied',403);
      requireThat(url.pathname.startsWith('/v1/burimunsi/'),'not_found',404);
      const route=url.pathname.slice('/v1/burimunsi'.length),method=req.method;
      const heldOperation=heldObservationOperation(url.pathname);
      if(heldOperation)requireThat(heldOperation==='observationReconcileVerifiedStatus'&&method==='GET'&&
        verifiedObservationStatusEnabled===true,'not_found',404);
      const installationId=req.headers.get('x-burimunsi-installation');requireId(installationId);
      if(strictContract){
        wireBinding=requestBinding(req,installationId,groupId);
        const csv=method==='GET'&&/^\/members\/[A-Za-z0-9_-]+\/ledger\.csv$/.test(route);
        if(!csv){wireRoute=contractRoute(method,route);if(method==='GET')validateNativeRequest(wireRoute.operation,null);}
        wireQuery=validateNativeQuery(csv?'csv':wireRoute.operation,url.search.slice(1));
      }
      if(route==='/session/login'&&method==='POST'){
        const b=await body(req,['phone','pin']);
        const network=await networkBucket(req);requireActiveNativeRequest(req);
        const data=await auth.login({...b,installationId,installationToken:req.headers.get('x-burimunsi-device')},network);
        if(strictContract)wireBinding.actorId=data?.profile?.id;
        return json(data);
      }
      const token=(req.headers.get('authorization')??'').match(/^Bearer ([a-f0-9]{64})$/)?.[1];
      requireActiveNativeRequest(req);
      const actor=await auth.authenticate(token,installationId);
      requireActiveNativeRequest(req);
      if(strictContract){requireThat(actor.groupId===groupId,'access_denied',403);wireBinding.actorId=actor.id;}
      if(route==='/session'&&method==='GET')return json({groupId:actor.groupId,profile:{id:actor.id,name:actor.name,phone:actor.phone,role:actor.role,capabilities:actor.capabilities},expiresAt:actor.expiresAt});
      if(route==='/session/logout'&&method==='POST'){await body(req,[]);return json(await auth.logout(actor));}
      if(route==='/session/passcode'&&method==='POST')return json(await auth.changePasscode(actor,await body(req,['current','newPin','confirm','replacementToken'])));
      const recovery=/^\/operations\/([A-Za-z0-9_-]+)\/recovery$/.exec(route);
      if(recovery&&method==='GET'){
        requireThat([...url.searchParams.keys()].length===0,'invalid_query');
        requirePort(records,['recoverCommandStatus']);
        // Historical selector, not authentication. Keep out of query/body logs.
        return json(await records.recoverCommandStatus(actor,recovery[1],req.headers.get('x-burimunsi-operation-origin')));
      }
      const resolution=/^\/operations\/([A-Za-z0-9_-]+)\/staff-resolution$/.exec(route);
      if(resolution&&method==='POST'){
        requireThat([...url.searchParams.keys()].length===0,'invalid_query');
        requirePort(auth,['resolveStaffCommand']);
        const input=await body(req,['operation']);
        return json(await auth.resolveStaffCommand(actor,{requestId:resolution[1],
          originDigest:req.headers.get('x-burimunsi-operation-origin'),operation:input.operation}));
      }
      const outcome=/^\/operations\/([A-Za-z0-9_-]+)$/.exec(route);
      if(outcome&&method==='GET')return json(await records.commandStatus(actor,outcome[1]));
      if(route==='/home'&&method==='GET')return json(await records.home(actor));
      if(route==='/members/suggestions'&&method==='GET'){
        requirePort(records,['onboardingSuggestions']);
        const query=strictContract?wireQuery:Object.fromEntries(url.searchParams);
        if(!strictContract&&query.limit!==undefined)query.limit=Number(query.limit);
        return json(await records.onboardingSuggestions(actor,query));
      }
      if(route==='/members/import/preview'&&method==='POST'){
        requirePort(records,['onboardingPreview']);
        const required=['mimeType','fileBytes','externalOcrConsent'];
        const input=await body(req,[...required,'importFlowId','ocrDisclosureVersion'],required);
        requireThat(typeof input.fileBytes==='string'&&input.fileBytes.length>0&&input.fileBytes.length%4===0&&
          /^[A-Za-z0-9+/]*={0,2}$/.test(input.fileBytes),'smart_import_invalid');
        let binary;try{binary=atob(input.fileBytes);}catch{throw new BuriError('smart_import_invalid',400);}
        requireThat(binary.length>0&&binary.length<=5*1024*1024&&btoa(binary)===input.fileBytes,'smart_import_invalid');
        const bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
        let preview;
        try{
          preview=await records.onboardingPreview(actor,{bytes,mimeType:input.mimeType,externalOcrConsent:input.externalOcrConsent,
            importFlowId:input.importFlowId,ocrDisclosureVersion:input.ocrDisclosureVersion,signal:req.signal});
        }catch(error){
          requireActiveNativeRequest(req);throw error;
        }finally{bytes.fill(0);}
        requireActiveNativeRequest(req);
        return json(preview);
      }
      if(route==='/members/import'&&method==='POST'){
        requirePort(members,['importMembers']);return json(await members.importMembers(actor,await body(req,['requestId','rows'])));
      }
      if(route==='/sms/observation-consent'&&method==='GET'){
        requirePort(observations,['readConsent']);return json(await observations.readConsent(actor));
      }
      if(route==='/sms/observation-consent'&&method==='POST'){
        requirePort(observations,['setConsent']);return json(await observations.setConsent(actor,await body(req,['enabled','generation'])));
      }
      if(route==='/sms/observation-profile'&&method==='GET'){
        requirePort(observations,['profile']);return json(await observations.profile(actor));
      }
      if(route==='/sms/observations'&&method==='POST'){
        requirePort(observations,['observe']);return json(await observations.observe(actor,await body(req,
          ['requestId','rawSender','rawBody','sourceMode','complete','capturedAt','serviceCentreAt','inboxReceivedAt','subscriptionId'])));
      }
      if(route==='/sms/observations'&&method==='GET'){
        requirePort(observations,['page']);
        requireThat([...url.searchParams.keys()].every(k=>['q','filter','limit','cursor','sort','fromAt','untilAt'].includes(k))&&
          [...new Set(url.searchParams.keys())].every(k=>url.searchParams.getAll(k).length===1),'invalid_query');
        const query=strictContract?wireQuery:Object.fromEntries(url.searchParams);
        if(!strictContract&&query.limit!==undefined)query.limit=Number(query.limit);
        return json(await observations.page(actor,query,cursor));
      }
      if(route==='/sms/observations/processing-status'&&method==='POST'){
        requirePort(observations,['processingStatus']);
        return json(await observations.processingStatus(actor,await body(req,['sourceIds'])));
      }
      if(route==='/sms/observations/reconcile'&&method==='POST'){
        requirePort(observations,['reconcile']);
        return json(await observations.reconcile(actor,await body(req,
          ['sourceKey','bodySha256','rawSender','serviceCentreAt','inboxReceivedAt','subscriptionId'])));
      }
      if(route==='/sms/observations/reconcile-batch'&&method==='POST'){
        requirePort(observations,['reconcileBatch']);
        return json(await observations.reconcileBatch(actor,await body(req,['items'])));
      }
      if(route==='/sms/observations/reconcile-status'&&method==='GET'){
        requirePort(observations,['reconcileStatus']);
        return json(await observations.reconcileStatus(actor));
      }
      if(heldOperation==='observationReconcileVerifiedStatus'){
        requirePort(observations,['reconcileVerifiedStatus']);
        return json(await observations.reconcileVerifiedStatus(actor));
      }
      const observedRetry=/^\/sms\/observations\/([A-Za-z0-9_-]+)\/retry$/.exec(route);
      if(observedRetry&&method==='POST'){
        requirePort(observations,['processingRetry']);
        return json(await observations.processingRetry(actor,observedRetry[1],await body(req,['requestId'])));
      }
      const observedReveal=/^\/sms\/observations\/([A-Za-z0-9_-]+)\/reveal$/.exec(route);
      if(observedReveal&&method==='POST'){
        requirePort(observations,['reveal']);const input=await body(req,['reason','displayHintsVersion'],['reason']);
        return json(await observations.reveal(actor,observedReveal[1],{...input,
          requestId:requireRequestId(req.headers.get('x-burimunsi-request'))}));
      }
      if(method==='GET'&&/^\/(payments|members|ledger|sms|staff|audit)$/.test(route)){
        requireThat([...url.searchParams.keys()].every(k=>LISTING_QUERY_KEYS.includes(k)),'invalid_query');
        requireThat([...new Set(url.searchParams.keys())].every(k=>url.searchParams.getAll(k).length===1),'invalid_query');
        const query=strictContract?wireQuery:Object.fromEntries(url.searchParams);if(!strictContract&&query.limit!==undefined)query.limit=Number(query.limit);
        return json(await records.page(actor,route.slice(1),query));
      }
      const history=/^\/payments\/([A-Za-z0-9_-]+)\/history$/.exec(route);
      if(history&&method==='GET'){
        requireThat([...url.searchParams.keys()].every(k=>['q','filter','limit','cursor','sort','fromAt','untilAt','minRwf','maxRwf'].includes(k)),'invalid_query');
        requireThat([...new Set(url.searchParams.keys())].every(k=>url.searchParams.getAll(k).length===1),'invalid_query');
        requirePort(records,['paymentHistory']);
        const query=strictContract?wireQuery:Object.fromEntries(url.searchParams);if(!strictContract&&query.limit!==undefined)query.limit=Number(query.limit);
        return json(await records.paymentHistory(actor,history[1],query));
      }
      const detail=/^\/(payments|members|sms)\/([A-Za-z0-9_-]+)$/.exec(route);
      if(detail?.[1]==='payments'&&method==='GET'&&req.headers.has(paymentReferenceHeader)){
        requireThat(req.headers.get(paymentReferenceHeader)==='1','unsupported_payment_reference_version',400);
        wireRoute={operation:'paymentDetailV1',recordId:detail[2]};
        return json(await records.detail(actor,'payment',detail[2],{includePaymentReference:true}));
      }
      if(detail&&method==='GET')return json(await records.detail(actor,{payments:'payment',members:'member',sms:'sms'}[detail[1]],detail[2]));
      const reveal=/^\/sms\/([A-Za-z0-9_-]+)\/reveal$/.exec(route);
      if(reveal&&method==='POST'){
        const request=await body(req,['reason']);requirePort(records,['revealSms']);
        return json(await records.revealSms(actor,reveal[1],{...request,
          requestId:requireRequestId(req.headers.get('x-burimunsi-request'))}));
      }
      const allocation=/^\/payments\/([A-Za-z0-9_-]+)\/allocate$/.exec(route);
      if(allocation&&method==='POST')return json(await contributions.allocate(actor,{...await body(req,['memberId','expectedVersion','note','requestId']),transactionId:allocation[1]}));
      if(route==='/members'&&method==='POST')return json(await members.enroll(actor,await body(req,['name','phone','requestId'])));
      if(detail?.[1]==='members'&&method==='PATCH')return json(await members.setActive(actor,{...await body(req,['active','expectedVersion','requestId']),memberId:detail[2]}));
      if(route==='/staff'&&method==='POST')return json(await auth.manageStaff(actor,await body(req,['action','phone','pin','name','capabilities','requestId'],['action','phone','name','capabilities','requestId'])));
      if(route==='/staff'&&method==='PATCH')return json(await auth.manageStaff(actor,await body(req,['action','id','expectedVersion','phone','name','pin','capabilities','requestId'],['action','id','expectedVersion','requestId'])));
      if(route==='/gateway'&&method==='GET')return json(await gateway.status(actor));
      if(route==='/gateway/pair'&&method==='POST'){requirePort(gateway,['pair']);return json(await gateway.pair(actor,await body(req,['pairingCode','replace','requestId'])));}
      if(route==='/gateway/replace'&&method==='POST')return json(await gateway.replace(actor,await body(req,['replacementCode','requestId'])));
      const exportRoute=/^\/members\/([A-Za-z0-9_-]+)\/ledger.csv$/.exec(route);
      if(exportRoute&&method==='GET')return new Response(await records.exportLedger(actor,exportRoute[1]),{headers:{...headers,'Content-Type':'text/csv; charset=utf-8','Content-Disposition':'attachment; filename="burimunsi-ledger.csv"'}});
      throw new BuriError('not_found',404);
    }catch(error){
      // No request body, raw SMS, token, phone, PIN, stack, or SQL in client failures.
      const known=error instanceof BuriError;const contract=error instanceof ContractViolation;
      const code=contract?error.code.toLowerCase():known?error.code:'service_unavailable';
      // Only the verified observation-specific exception carries this proof.
      // It binds to this request without returning SMS content or a body hash.
      const proof=strictContract&&wireRoute?.operation==='observation'&&error instanceof ObservationUploadUnresolved&&
       requestBody?.requestId===error.requestId&&wireBinding?.requestId?
       {'X-BuriMunsi-Observation-Unresolved':'v1','X-BuriMunsi-Observation-Request-Id':error.requestId,
        'X-BuriMunsi-Correlation-Id':wireBinding.requestId}:{};
      return new Response(JSON.stringify({...(strictContract?{contractVersion:CONTRACT_VERSION}:{}),ok:false,error:{code}}),{status:contract?nativeRequestErrorStatus(error):known?error.status:503,headers:{...headers,...proof}});
    }finally{discardNativeBody(req);}
  };
}
