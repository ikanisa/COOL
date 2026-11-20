import test from 'node:test';
import assert from 'node:assert/strict';
import {X509Certificate,createHash} from 'node:crypto';
import {hasPinnedProviderSSL,loadProviderRoot,validateProviderRoot,PROVIDER_ROOT_SHA256} from './provider-ca.mjs';

test('provider database CA is a valid self-signed root with the pinned DER fingerprint',()=>{
 const pem=loadProviderRoot(),cert=new X509Certificate(pem);
 assert.equal(createHash('sha256').update(cert.raw).digest('hex'),PROVIDER_ROOT_SHA256);
 assert.equal(cert.ca,true);assert.equal(cert.verify(cert.publicKey),true);
 assert.equal(validateProviderRoot(pem),pem);
});

test('TLS options require only the pinned root and built-in hostname verification',()=>{
 const ca=loadProviderRoot();
 assert.equal(hasPinnedProviderSSL({ca,rejectUnauthorized:true}),true);
 assert.equal(hasPinnedProviderSSL({ca,rejectUnauthorized:true},ca),true);
 assert.equal(hasPinnedProviderSSL({ca,rejectUnauthorized:true},'untrusted-root'),false);
 for(const value of [
  {ca:'synthetic-untrusted-ca',rejectUnauthorized:true},
  {ca,rejectUnauthorized:false},
  {ca,rejectUnauthorized:true,checkServerIdentity:()=>undefined},
  {ca,rejectUnauthorized:true,secureContext:{}},
  {ca,rejectUnauthorized:true,servername:'other.example'},
  {get ca(){return ca;},rejectUnauthorized:true},
  Object.assign(Object.create(null),{ca,rejectUnauthorized:true}),
 ])assert.equal(hasPinnedProviderSSL(value),false);
});

test('provider CA refuses malformed, substituted, appended and out-of-validity certificates',()=>{
 const pem=loadProviderRoot(),cert=new X509Certificate(pem);
 const altered=pem.replace(/\n([A-Za-z0-9])/,(_,c)=>'\n'+(c==='A'?'B':'A'));
 for(const value of ['',{},pem+pem,altered,'not-a-certificate'])
  assert.throws(()=>validateProviderRoot(value),/provider_ca_unavailable/);
 for(const now of [NaN,Date.parse(cert.validFrom)-1,Date.parse(cert.validTo)])
  assert.throws(()=>validateProviderRoot(pem,now),/provider_ca_unavailable/);
});
