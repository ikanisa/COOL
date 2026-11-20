import test from 'node:test';
import assert from 'node:assert/strict';
import {createCollectTransport} from '../src/supabase-transport.js';

const origin='https://platform-admin.collect.ikanisa.com';
test('owner identity opt-in is forwarded only to the exact Admin session GET',async()=>{
 for(const [path,method,version,expected] of [
  ['/api/admin/auth/session','GET','1','1'],
  ['/functions/v1/admin-api/api/admin/auth/session','GET','1','1'],
  ['/api/admin/auth/session','GET','2',null],
  ['/api/admin/auth/session','GET','1, 1',null],
  ['/api/admin/auth/session/','GET','1',null],
  ['/api/admin/auth/session','POST','1',null],
  ['/api/admin/team','GET','1',null],
  ['/v1/profile','GET','1',null],
 ]){
  let calls=0;
  const proxy=createCollectTransport({frontendOrigin:origin,fetchImpl:async upstream=>{
   calls++;assert.equal(upstream.headers.get('X-Collect-Owner-Identity-Version'),expected);
   return Response.json({ok:true});
  }});
  const headers={Origin:origin,'X-Collect-Owner-Identity-Version':version,
   ...(method==='POST'?{'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'}:{})};
  const response=await proxy(new Request(origin+path,{method,headers,...(method==='POST'?{body:'{}'}:{})}));
  assert.equal(response.status,200,`${method} ${path} ${version}`);assert.equal(calls,1);
 }
});
