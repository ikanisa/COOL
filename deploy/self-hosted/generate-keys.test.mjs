import test from 'node:test';
import assert from 'node:assert/strict';
import {createPublicKey,verify,createHash,createHmac} from 'node:crypto';
import {generateDeploymentKeys} from './generate-keys.mjs';
test('generated keys satisfy the pinned upstream opaque and JWT contracts',()=>{
 const a=generateDeploymentKeys(),b=generateDeploymentKeys();assert.notEqual(a.SUPABASE_SECRET_KEY,b.SUPABASE_SECRET_KEY);assert.notEqual(a.POSTGRES_PASSWORD,b.POSTGRES_PASSWORD);
 for(const value of [a.SUPABASE_PUBLISHABLE_KEY,a.SUPABASE_SECRET_KEY]){
  assert.equal(value.slice(-8),createHash('sha256').update('supabase-self-hosted|'+value.slice(0,-9)).digest('base64url').slice(0,8));
 }
 const publicJwk=JSON.parse(a.JWT_JWKS).keys.find(k=>k.kty==='EC');assert.equal(publicJwk.d,undefined);
 for(const [name,role] of [['ANON_KEY','anon'],['SERVICE_ROLE_KEY','service_role'],['ANON_KEY_ASYMMETRIC','anon'],['SERVICE_ROLE_KEY_ASYMMETRIC','service_role']]){
  const [head,body,sig]=a[name].split('.');assert.equal(JSON.parse(Buffer.from(body,'base64url')).role,role);
  if(name.endsWith('ASYMMETRIC'))assert.equal(verify('SHA256',Buffer.from(head+'.'+body),{key:createPublicKey({key:publicJwk,format:'jwk'}),dsaEncoding:'ieee-p1363'},Buffer.from(sig,'base64url')),true);
  else assert.equal(sig,createHmac('sha256',a.JWT_SECRET).update(head+'.'+body).digest('base64url'));
 }
});
test('fresh native key purposes are private, canonical32-byte and independent across releases',()=>{
 const first=generateDeploymentKeys(),second=generateDeploymentKeys();
 const purposes=['DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY','BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_CURSOR_KEY_BASE64','COLLECT_NATIVE_INGRESS_KEY_BASE64'];
 for(const keys of [first,second]){
  const material=purposes.map(name=>{
   const bytes=Buffer.from(keys[name],'base64');assert.equal(bytes.length,32);assert.equal(bytes.toString('base64'),keys[name]);return bytes.toString('hex');
  });
  assert.equal(new Set(material).size,purposes.length);
  assert.match(keys.BURIMUNSI_PIN_PEPPER_ID,/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/);
  assert.match(keys.COLLECT_NATIVE_INGRESS_KEY_ID,/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/);
  assert.equal(keys.COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON,undefined);
  assert.equal(keys.BURIMUNSI_NATIVE_ENABLED,undefined);assert.equal(keys.BURIMUNSI_COLLECTION_ID,undefined);
 }
 for(const name of purposes)assert.notEqual(first[name],second[name]);
});
