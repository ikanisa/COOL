import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleAdminAccounts} from '../domain/admin_accounts.js';
import {handleAuth} from '../domain/auth.js';

const origin='https://admin.example.test';
const request=(path,method='POST',site=origin)=>new Request(origin+path,{method,headers:{Origin:site,
 'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'},...(['GET','HEAD'].includes(method)?{}:{body:'{}'})});
const error=(status,code)=>e=>e.status===status&&e.code===code;

test('Admin authenticator routes stay retired by default before any identity or provider access',async()=>{
 const env={ADMIN_ORIGIN:origin};
 for(const path of ['factors','enroll','challenge','verify','recover','cancel-enrollment','unknown']){
  await assert.rejects(handleAdminAccounts(request('/api/admin/auth/mfa/'+path),env),error(410,'mfa_not_available'));
 }
});
test('member and native MFA routes remain retired when Admin capability is enabled',async()=>{
 const env={ADMIN_ORIGIN:origin,COLLECT_ADMIN_TOTP_ENABLED:'true'};
 await assert.rejects(handleAuth(request('/v1/auth/mfa/verify'),env),error(410,'mfa_not_available'));
});
test('origin validation still precedes the retired Admin route and unknown enabled routes fail closed',async()=>{
 await assert.rejects(handleAdminAccounts(request('/api/admin/auth/mfa/verify','POST','https://other.example.test'),{ADMIN_ORIGIN:origin}),error(403,'origin_rejected'));
 await assert.rejects(handleAdminAccounts(request('/api/admin/auth/mfa/unknown'),{ADMIN_ORIGIN:origin,COLLECT_ADMIN_TOTP_ENABLED:'true'}),error(404,'not_found'));
});
