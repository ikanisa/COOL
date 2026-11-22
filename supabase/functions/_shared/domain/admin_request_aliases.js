import {digest,stableJson,id,now} from './core.js';
import {fail} from './admin_records.js';

export const requestId=async(account,key)=>{if(typeof key!=='string'||!/^[a-zA-Z0-9_.-]{8,200}$/.test(key))fail(400,'invalid_request','Supply an Idempotency-Key of 8 to 200 letters, digits, dots, hyphens or underscores.');
 const value=await digest(`collect-admin:${account.principal_id}:${key}`);return `${value.slice(0,8)}-${value.slice(8,12)}-4${value.slice(13,16)}-8${value.slice(17,20)}-${value.slice(20,32)}`;};
export function domainGuard(env,condition,args=[]){const guardId=id();return [env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN ${condition} THEN 1 ELSE 0 END)`).bind(guardId,...args),env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId)];}
export function receipt(requestId,type,resourceId,version){return {status:'succeeded',request_id:requestId,resource_type:type,resource_id:resourceId,version};}

// Preserve the UI's arbitrary idempotency keys while canonical mutations keep
// their UUID request ID. The alias and the actual receipt commit together.
export function requestEnvironment(env,account,key,rid,operation,source,{before=[],after=[]}={}){
 const map=new WeakMap(),shaPromise=digest(stableJson(source));
 const wrapStatement=(stmt,query)=>{const proxy=new Proxy(stmt,{get(target,name){if(name==='bind')return(...args)=>wrapStatement(target.bind(...args),query);const value=Reflect.get(target,name,target);return typeof value==='function'?value.bind(target):value;}});map.set(proxy,{stmt,query});return proxy;};
 const db=new Proxy(env.DB,{get(target,name){
  if(name==='prepare')return query=>wrapStatement(target.prepare(query),query);
  if(name==='batch')return async statements=>{
   const originals=statements.map(v=>map.get(v)?.stmt??v);
   const writesReceipt=statements.some(v=>/INSERT INTO request_receipts\b/.test(map.get(v)?.query??''));
   if(!writesReceipt)return target.batch(originals);
   const sha=await shaPromise,guardId=id();
   const extra=[target.prepare(`INSERT INTO admin_bridge_requests(admin_user_id,idempotency_key,request_id,session_id,operation,body_sha256,created_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(admin_user_id,idempotency_key) DO NOTHING`).bind(account.id,key,rid,account.auth_session_id,operation,sha,now()),
    target.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(SELECT 1 FROM admin_bridge_requests WHERE admin_user_id=? AND idempotency_key=? AND request_id=? AND session_id=? AND operation=? AND body_sha256=?) THEN 1 ELSE 0 END)`).bind(guardId,account.id,key,rid,account.auth_session_id,operation,sha)];
   const result=await target.batch([...extra,...before,...originals,...after,target.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId)]);
   return result.slice(extra.length+before.length,extra.length+before.length+originals.length);
  };
  if(name==='withSession')return()=>db;const value=Reflect.get(target,name,target);return typeof value==='function'?value.bind(target):value;
 }});return {...env,DB:db};
}
