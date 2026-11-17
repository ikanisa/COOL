import test from 'node:test';
import assert from 'node:assert/strict';
import {workerEnvironment} from './edge-main/environment.mjs';

const material={
 COLLECT_NATIVE_INGRESS_KEY_BASE64:'synthetic-ingress-key',COLLECT_NATIVE_INGRESS_KEY_ID:'fixture-only',
 COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:'synthetic-proof',COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256:'synthetic-digest',
 BURIMUNSI_PIN_PEPPER_BASE64:'synthetic-native-pepper',BURIMUNSI_PIN_PEPPER_ID:'native-fixture-only',
 BURIMUNSI_CURSOR_KEY_BASE64:'synthetic-cursor-key',BURIMUNSI_COLLECTION_ID:'fixture-group',
 SUPABASE_URL:'https://supabase.example.invalid',BUILD_SOURCE_ID:'synthetic-build',
};
for(const name of ['collect-api','admin-api','collect-jobs','collect-email-jobs','collect-sms','send-sms-hook']){
 test('private native settings stay within actual function responsibilities: '+name,()=>{
  const scoped=Object.fromEntries(workerEnvironment(name,material));
  for(const key of Object.keys(material).filter(key=>key.startsWith('COLLECT_NATIVE_INGRESS_')))
   assert.equal(scoped[key],name==='collect-api'?material[key]:undefined,key);
  for(const key of Object.keys(material).filter(key=>key.startsWith('BURIMUNSI_')))
   assert.equal(scoped[key],['collect-api','admin-api','collect-jobs'].includes(name)?material[key]:undefined,key);
  assert.equal(scoped.SUPABASE_FUNCTION_SLUG,name);
 });
}
test('future native ingress settings cannot silently reach unrelated functions',()=>{
 const source={...material,COLLECT_NATIVE_INGRESS_NEXT_PRIVATE_SETTING:'synthetic-future-secret'};
 assert.equal(Object.fromEntries(workerEnvironment('collect-api',source)).COLLECT_NATIVE_INGRESS_NEXT_PRIVATE_SETTING,source.COLLECT_NATIVE_INGRESS_NEXT_PRIVATE_SETTING);
 assert.equal(Object.fromEntries(workerEnvironment('admin-api',source)).COLLECT_NATIVE_INGRESS_NEXT_PRIVATE_SETTING,undefined);
});
test('Auth-only SMTP and Turnstile secrets never enter a function environment',()=>{
 const source={...material,TURNSTILE_SITE_KEY:'synthetic-public-site-key',TURNSTILE_SECRET_KEY:'synthetic-private-captcha-secret',
  COLLECT_AUTH_TURNSTILE_SECRET:'synthetic-server-captcha-secret',COLLECT_AUTH_SMTP_PASS:'synthetic-server-smtp-secret',
  SMTP_PASS:'synthetic-smtp-secret',GOTRUE_SECURITY_CAPTCHA_SECRET:'synthetic-auth-captcha-secret'};
 for(const name of ['collect-api','admin-api','collect-jobs','collect-email-jobs','collect-sms','send-sms-hook']){
  const scoped=Object.fromEntries(workerEnvironment(name,source));
  for(const key of Object.keys(source).filter(key=>key==='TURNSTILE_SECRET_KEY'||key.startsWith('COLLECT_AUTH_')||key.startsWith('SMTP_')||key.startsWith('GOTRUE_')))
   assert.equal(scoped[key],undefined,name+': '+key);
  if(['collect-api','admin-api'].includes(name))assert.equal(scoped.TURNSTILE_SITE_KEY,source.TURNSTILE_SITE_KEY);
 }
});
