import test from 'node:test';
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import {setImmediate} from 'node:timers';
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const SOURCE='a'.repeat(64);

test('real HTTP handler passes disconnect signal and closes admitted work before domain dispatch',async()=>{
 const hooks=registerHooks({resolve(specifier,context,next){
  if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){return {begin(){globalThis.__fixtureDbActions++;throw Error("unexpected SQL")},reserve(){globalThis.__fixtureDbActions++;throw Error("unexpected lease")}}}',shortCircuit:true};
  if(specifier==='npm:nodemailer@10.1.7')return {url:'data:text/javascript,export function createTransport(){throw Error("unexpected SMTP")}',shortCircuit:true};
  return next(specifier,context);
 }});
 try{
  const {createHandler}=await import('../serve.js');
  const {openApplicationWork}=await import('../application-fence.js');
  const controller=new AbortController(),events=[];let signalSeen,finalized;globalThis.__fixtureDbActions=0;
  const closed=new Promise(resolve=>{finalized=resolve;}),rows=new Map();
  const backend={
   async register(id,source,kind){events.push('register');const row={contractVersion:1,admissionId:id,sourceSha256:source,epoch:1,kind,state:'active',mode:'open'};rows.set(id,row);return row;},
   async lease(id){events.push('lease');return {row:rows.get(id),async assert(){return rows.get(id);},async release(){events.push('release');}};},
   async close(id,epoch,source,state,reason,externalDispatches,uncertainDispatches){events.push('close');const row={...rows.get(id),epoch,sourceSha256:source,state,reason,externalDispatches,uncertainDispatches};rows.set(id,row);finalized();return row;},
   async status(id){return {...rows.get(id),found:rows.has(id)};}
  };
  const env={APP_ENVIRONMENT:'test',SUPABASE_URL:'https://example.test',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/fixture',BUILD_SOURCE_ID:SOURCE};
  const handler=createHandler('collect-api',()=>env,{reportHealth:()=>{},openWork:async options=>{
   signalSeen=options.signal;const work=await openApplicationWork({...options,backend});controller.abort();return work;
  }});
  const req=new Request('https://example.test/functions/v1/collect-api/health',{signal:controller.signal});
  const response=await handler(req);await Promise.race([closed,new Promise((_,reject)=>setTimeout(()=>reject(Error('completion not observed')),1000))]);await tick();
  assert.equal(response.status,503);assert.equal(signalSeen,req.signal);assert.equal(globalThis.__fixtureDbActions,0);
  assert.equal(events.filter(x=>x==='close').length,1);assert.equal([...rows.values()][0].externalDispatches,0);
 }finally{delete globalThis.__fixtureDbActions;hooks.deregister();}
});
