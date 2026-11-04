import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {join} from 'node:path';
const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(root,'Explicit source root required');
const {handleAdminAccounts}=await import(pathToFileURL(join(root,'domain/admin_accounts.js')).href);
const {ApiError}=await import(pathToFileURL(join(root,'domain/core.js')).href);
const origin='https://platform-admin.collect.ikanisa.com';
const env={ADMIN_ORIGIN:origin,DB:{prepare(){throw new Error('Signed-out admission must not query the database');}}};
const failure=(status,code)=>error=>error instanceof ApiError&&error.status===status&&error.code===code;

// Actual proposed entry module including its new imported controller. No
// synthetic signed-in actor, cookie custody or live session is asserted here.
for(const path of ['/team/v2','/team/v2/invitation-status','/team','/team/invitation-status']){
 test(`GET ${path} reaches the existing signed-out gate`,async()=>{
  const request=new Request(origin+'/api/admin'+path,{headers:{Origin:origin}});
  await assert.rejects(handleAdminAccounts(request,env,{}),failure(401,'unauthenticated'));
 });
}
for(const path of ['/team/v2/invite','/team/v2/44444444-4444-4444-8444-444444444444/resend','/team/v2/44444444-4444-4444-8444-444444444444/access-notice']){
 test(`GET cannot mutate ${path}`,async()=>{
  await assert.rejects(handleAdminAccounts(new Request(origin+'/api/admin'+path,{headers:{Origin:origin}}),env,{}),failure(405,'method_not_allowed'));
 });
 test(`POST ${path} retains the signed-out gate`,async()=>{
  const request=new Request(origin+'/api/admin'+path,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:'{}'});
  await assert.rejects(handleAdminAccounts(request,env,{}),failure(401,'unauthenticated'));
 });
 test(`POST ${path} rejects a foreign origin before account access`,async()=>{
  const request=new Request(origin+'/api/admin'+path,{method:'POST',headers:{Origin:'https://foreign.invalid','Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:'{}'});
  await assert.rejects(handleAdminAccounts(request,env,{}),failure(403,'origin_rejected'));
 });
}
test('POST v2 invite rejects missing Admin request marker',async()=>{
 const request=new Request(origin+'/api/admin/team/v2/invite',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:'{}'});
 await assert.rejects(handleAdminAccounts(request,env,{}),failure(403,'origin_rejected'));
});
