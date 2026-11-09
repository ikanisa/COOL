import {readNativeBody,discardNativeBody,requireActiveNativeRequest,nativeRequestErrorStatus} from './wire/request-boundary.mjs';
import {ContractViolation,CONTRACT_VERSION,parseWire,contractRoute,requestBinding,validateNativeRequest,bindNativeResponse,validateNativeQuery} from './wire/native-contract.mjs';
import {BuriError,requirePort,requireThat} from './errors.js';
import {exactKeys,requireId} from './values.js';
/** Candidate native API adapter; attach only to an admitted Collect Edge request.
 * Do not replace the current router or bypass its application fence.
 * Origin/networkBucket are server-owned deployment inputs, not forwarded client claims.
 */
export function createNativeHandler({auth,records,contributions,members,gateway,origin,networkBucket,strictContract=false,groupId,requestReadTimeoutMs=15000}) {
  requirePort(auth,['login','authenticate','logout','changePasscode','manageStaff']);
  requirePort(records,['home','page','detail','exportLedger','commandStatus']);
  requirePort(contributions,['allocate']);requirePort(members,['enroll','setActive']);
  requirePort(gateway,['status','replace']);
  requireThat(typeof networkBucket==='function','trusted_network_resolver_required',503);
  const configured=new URL(origin);requireThat(configured.protocol==='https:'&&configured.origin===origin,'tls_origin_required',503);
  if(strictContract)requireId(groupId);
  const headers={...(strictContract?{'X-BuriMunsi-Contract':CONTRACT_VERSION}:{}),'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Pragma':'no-cache','X-Content-Type-Options':'nosniff'};
  async function readBody(req,allowed,required=allowed) {
    requireThat((req.headers.get('content-type')??'').split(';')[0].trim()==='application/json','json_required',415);
    const all=await readNativeBody(req,{timeoutMs:requestReadTimeoutMs});
    let value;try{value=strictContract?parseWire(all,8192):JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));}catch(error){if(error instanceof ContractViolation)throw error;throw new BuriError('invalid_json',400);}
    return strictContract?value:exactKeys(value,allowed,required);
  }
  return async req=>{
    // Request-local state prevents concurrent requests from sharing identity metadata.
    let wireRoute=null,wireBinding=null,requestBody=null,wireQuery=null;
    const body=async(request,allowed,required=allowed)=>{
      const value=await readBody(request,allowed,required);
      if(strictContract)validateNativeRequest(wireRoute.operation,value);
      requireActiveNativeRequest(req);requestBody=value;return value;
    };
    const json=(data,status=200)=>{
      let value={ok:true,data};
      if(strictContract){
        try{value=bindNativeResponse(wireRoute,wireBinding,requestBody,data,req.headers.get('x-burimunsi-operation-origin'));}
        catch(_){throw new BuriError('contract_invalid_response',503);}
      }
      return new Response(JSON.stringify(value),{status,headers});
    };
    try{
      requireActiveNativeRequest(req);
      const url=new URL(req.url);
      requireThat(url.origin===origin,'origin_denied',403);
      // Native client doesn't need CORS. Unexpected browser cross-origin requests fail closed.
      const requestOrigin=req.headers.get('origin');requireThat(!requestOrigin||requestOrigin===origin,'origin_denied',403);
      requireThat(url.pathname.startsWith('/v1/burimunsi/'),'not_found',404);
      const route=url.pathname.slice('/v1/burimunsi'.length),method=req.method;
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
      if(route==='/session'&&method==='GET')return json({profile:{id:actor.id,name:actor.name,phone:actor.phone,role:actor.role,capabilities:actor.capabilities},expiresAt:actor.expiresAt});
      if(route==='/session/logout'&&method==='POST'){await body(req,[]);return json(await auth.logout(actor));}
      if(route==='/session/passcode'&&method==='POST')return json(await auth.changePasscode(actor,await body(req,['current','newPin','confirm'])));
      const recovery=/^\/operations\/([A-Za-z0-9_-]+)\/recovery$/.exec(route);
      if(recovery&&method==='GET'){
        requireThat([...url.searchParams.keys()].length===0,'invalid_query');
        requirePort(records,['recoverCommandStatus']);
        // Historical selector, not authentication. Keep out of query/body logs.
        return json(await records.recoverCommandStatus(actor,recovery[1],req.headers.get('x-burimunsi-operation-origin')));
      }
      const outcome=/^\/operations\/([A-Za-z0-9_-]+)$/.exec(route);
      if(outcome&&method==='GET')return json(await records.commandStatus(actor,outcome[1]));
      if(route==='/home'&&method==='GET')return json(await records.home(actor));
      if(method==='GET'&&/^\/(payments|members|ledger|sms|staff|audit)$/.test(route)){
        requireThat([...url.searchParams.keys()].every(k=>['q','filter','limit','memberId','cursor'].includes(k)),'invalid_query');
        requireThat([...new Set(url.searchParams.keys())].every(k=>url.searchParams.getAll(k).length===1),'invalid_query');
        const query=strictContract?wireQuery:Object.fromEntries(url.searchParams);if(!strictContract&&query.limit!==undefined)query.limit=Number(query.limit);
        return json(await records.page(actor,route.slice(1),query));
      }
      const history=/^\/payments\/([A-Za-z0-9_-]+)\/history$/.exec(route);
      if(history&&method==='GET'){
        requireThat([...url.searchParams.keys()].every(k=>['limit','cursor'].includes(k)),'invalid_query');
        requireThat([...new Set(url.searchParams.keys())].every(k=>url.searchParams.getAll(k).length===1),'invalid_query');
        requirePort(records,['paymentHistory']);
        const query=strictContract?wireQuery:Object.fromEntries(url.searchParams);if(!strictContract&&query.limit!==undefined)query.limit=Number(query.limit);
        return json(await records.paymentHistory(actor,history[1],query));
      }
      const detail=/^\/(payments|members|sms)\/([A-Za-z0-9_-]+)$/.exec(route);
      if(detail&&method==='GET')return json(await records.detail(actor,{payments:'payment',members:'member',sms:'sms'}[detail[1]],detail[2]));
      const allocation=/^\/payments\/([A-Za-z0-9_-]+)\/allocate$/.exec(route);
      if(allocation&&method==='POST')return json(await contributions.allocate(actor,{...await body(req,['memberId','expectedVersion','note','requestId']),transactionId:allocation[1]}));
      if(route==='/members'&&method==='POST')return json(await members.enroll(actor,await body(req,['name','phone','requestId'])));
      if(detail?.[1]==='members'&&method==='PATCH')return json(await members.setActive(actor,{...await body(req,['active','expectedVersion','requestId']),memberId:detail[2]}));
      if(route==='/staff'&&method==='POST')return json(await auth.manageStaff(actor,await body(req,['action','phone','pin','name','capabilities','requestId'])));
      if(route==='/staff'&&method==='PATCH')return json(await auth.manageStaff(actor,await body(req,['action','id','expectedVersion','phone','name','pin','capabilities','requestId'],['action','id','expectedVersion','requestId'])));
      if(route==='/gateway'&&method==='GET')return json(await gateway.status(actor));
      if(route==='/gateway/replace'&&method==='POST')return json(await gateway.replace(actor,await body(req,['installationId','expectedBindingId','expectedVersion','requestId'])));
      const exportRoute=/^\/members\/([A-Za-z0-9_-]+)\/ledger.csv$/.exec(route);
      if(exportRoute&&method==='GET')return new Response(await records.exportLedger(actor,exportRoute[1]),{headers:{...headers,'Content-Type':'text/csv; charset=utf-8','Content-Disposition':'attachment; filename="burimunsi-ledger.csv"'}});
      throw new BuriError('not_found',404);
    }catch(error){
      // No request body, raw SMS, token, phone, PIN, stack, or SQL in client failures.
      const known=error instanceof BuriError;const contract=error instanceof ContractViolation;
      const code=contract?error.code.toLowerCase():known?error.code:'service_unavailable';
      return new Response(JSON.stringify({...(strictContract?{contractVersion:CONTRACT_VERSION}:{}),ok:false,error:{code}}),{status:contract?nativeRequestErrorStatus(error):known?error.status:503,headers});
    }finally{discardNativeBody(req);}
  };
}
