import test from 'node:test';
import assert from 'node:assert/strict';
import {createCollectTransport} from '../src/supabase-transport.js';
const origin='https://platform-admin.collect.ikanisa.com',device='a'.repeat(64);
const request=(path,secret=device)=>new Request(origin+path,{method:'POST',headers:{Origin:origin,
 'Content-Type':'application/json','X-BuriMunsi-Device':secret,'X-Collect-CSRF':'fixture-csrf',Cookie:'__Host-collect_admin=fixture'},body:'{}'});
test('private managed device proof is forwarded only to its exact BFF access route',async()=>{
 for(const path of ['/api/admin/burimunsi/access','/api/admin/auth/login','/api/admin/team','/v1/auth/otp']){
  let calls=0;
  const proxy=createCollectTransport({frontendOrigin:origin,fetchImpl:async upstream=>{
   calls++;assert.equal(upstream.headers.get('X-BuriMunsi-Device'),path==='/api/admin/burimunsi/access'?device:null);
   return Response.json({ok:true});
  }});
  assert.equal((await proxy(request(path))).status,200);assert.equal(calls,1);
 }
});
test('malformed native device proof is rejected before upstream or credential dispatch',async()=>{
 let calls=0;const proxy=createCollectTransport({frontendOrigin:origin,fetchImpl:async()=>{calls++;throw Error('Forbidden dispatch');}});
 assert.equal((await proxy(request('/api/admin/burimunsi/access','1234'))).status,400);assert.equal(calls,0);
});
