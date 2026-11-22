import {request as httpsRequest} from 'node:https';
import {sha,need,exact,PROJECT} from './codec.mjs';
export const ORGANIZATION='ghnjnepwvwknswrwzepn';
export const ENDPOINT='https://api.supabase.com/v1/projects/'+PROJECT;
export function checkEnvironment(env=process.env){
 for(const [name,value] of Object.entries(env))if(value&&(/^(?:https?|all|no)_proxy$/i.test(name)||['NODE_OPTIONS','NODE_USE_ENV_PROXY','GLOBAL_AGENT_HTTP_PROXY'].includes(name)))need(false,'PROXY_OR_PRELOAD_AMBIGUITY');
 need(!env.NODE_TLS_REJECT_UNAUTHORIZED||env.NODE_TLS_REJECT_UNAUTHORIZED==='1','TLS_OVERRIDE_REFUSED');
}
export function createManagementTransport({token,environment=process.env,requestImpl=httpsRequest,timeoutMs=60000,responseCap=8*1024*1024}={}){
 checkEnvironment(environment);need(typeof token==='string'&&token.length>=16&&token.length<=16384&&!/[\s\x00-\x1f]/.test(token),'TOKEN_INVALID');
 need(Number.isSafeInteger(timeoutMs)&&timeoutMs>0&&timeoutMs<=60000&&Number.isSafeInteger(responseCap)&&responseCap>0&&responseCap<=8*1024*1024,'TRANSPORT_BOUND_INVALID');
 async function exchange(method,url,body,expected,cap){
  const bytes=body===null?null:Buffer.from(JSON.stringify(body));need(!bytes||bytes.length<=4*1024*1024,'REQUEST_BOUND');
  return new Promise((resolve,reject)=>{
   let done=false,req,res,timer;const chunks=[];let length=0;
   const finish=(code,value)=>{if(done)return;done=true;clearTimeout(timer);if(code){res?.destroy();req?.destroy();const e=new Error(code);e.code=code;reject(e);}else resolve(value);};
   timer=setTimeout(()=>finish('TRANSPORT_TIMEOUT'),timeoutMs);
   try{
    req=requestImpl(new URL(url),{method,agent:false,rejectUnauthorized:true,maxHeaderSize:16384,headers:{Authorization:'Bearer '+token,Accept:'application/json',...(bytes?{'Content-Type':'application/json','Content-Length':String(bytes.length)}:{})}},incoming=>{
     res=incoming;
     if(res.statusCode>=300&&res.statusCode<=399)return finish('REDIRECT_REFUSED');
     if(res.statusCode!==expected)return finish('HTTP_STATUS_REFUSED');
     const declared=res.headers?.['content-length'];if(declared!==undefined&&(!/^[0-9]+$/.test(String(declared))||Number(declared)>cap))return finish('RESPONSE_BOUND');
     res.on('data',chunk=>{if(done)return;const data=Buffer.from(chunk);length+=data.length;if(length>cap)return finish('RESPONSE_BOUND');chunks.push(data);});
     res.on('error',()=>finish('TRANSPORT_UNCONFIRMED'));res.on('aborted',()=>finish('TRANSPORT_UNCONFIRMED'));
     res.on('end',()=>{if(declared!==undefined&&length!==Number(declared))return finish('RESPONSE_LENGTH_CHANGED');finish(null,{status:expected,body:Buffer.concat(chunks,length)});});
    });req.on('error',()=>finish('TRANSPORT_UNCONFIRMED'));req.end(bytes??undefined);
   }catch{finish('TRANSPORT_UNCONFIRMED');}
  });
 }
 return Object.freeze({
  async readProject(){const r=await exchange('GET',ENDPOINT,null,200,Math.min(responseCap,1024*1024));try{let p;try{p=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(r.body));}catch{need(false,'PROJECT_RESPONSE_INVALID');}need(p&&(p.ref??p.id)===PROJECT&&p.organization_id===ORGANIZATION&&p.status==='ACTIVE_HEALTHY','PROJECT_IDENTITY_INVALID');return {project_ref:PROJECT,organization_id:ORGANIZATION,status:p.status};}finally{r.body.fill(0);}},
  async query(c){exact(c,['method','url','fixture_database','body','kind','request_id','query_sha256','max_response_bytes']);exact(c.body,['query','read_only']);need(c.method==='POST'&&c.url===ENDPOINT+'/database/query'&&c.fixture_database===null&&['metadata','capture'].includes(c.kind)&&c.body.read_only===true&&typeof c.body.query==='string'&&Buffer.byteLength(c.body.query)<=2*1024*1024&&c.body.query.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n')&&c.body.query.endsWith('\nROLLBACK;')&&sha(c.body.query)===c.query_sha256&&c.max_response_bytes===8*1024*1024,'COMPILED_REQUEST_INVALID');return exchange('POST',c.url,c.body,201,responseCap);}
 });
}
