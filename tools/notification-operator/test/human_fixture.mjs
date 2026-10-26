// Synthetic protocol peer only. This does not render or solve any real CAPTCHA.
import assert from 'node:assert/strict';
import {request} from 'node:http';
import {createPublicKey,verify,randomUUID} from 'node:crypto';
import {acquirePasswordProof,acquireEmailProof} from '../src/human_login.mjs';
import {ORIGINS} from '../src/contract.mjs';
export function loopback(pairing,method,path,value,{origin=pairing.descriptor.admin_origin}={}) {
  const bytes=value===undefined?undefined:Buffer.from(JSON.stringify(value));
  return new Promise((resolve,reject)=>{
    const req=request({hostname:'127.0.0.1',port:pairing.descriptor.loopback_port,path,method,headers:{Origin:origin,'X-Collect-Handoff-Version':'1','X-Collect-Handoff-Attempt':pairing.descriptor.attempt_id,...bytes?{'Content-Type':'application/json','Content-Length':bytes.length}:{}}},res=>{
      const chunks=[];res.on('data',c=>chunks.push(c));res.on('error',reject);res.on('end',()=>{try{resolve({status:res.statusCode,headers:res.headers,value:JSON.parse(Buffer.concat(chunks))});}catch(error){reject(error);}});
    });req.on('error',reject);req.setTimeout(2000,()=>req.destroy(new Error('synthetic_loopback_timeout')));req.end(bytes);
  });
}
async function syntheticProof({origin=ORIGINS[0],purpose='sign_in',signal,onToken=()=>{},onPairing:inspect=()=>{}}={}) {
  const operation=purpose==='password'?'admin.password.sign_in':'admin.email_otp.send';
  const acquire=purpose==='password'?acquirePasswordProof:acquireEmailProof;
  return acquire({origin,purpose},{signal,onPairing:async pairing=>{
    await inspect(pairing);
    assert.equal(pairing.parentUrl,origin+'/admin/auth/local-challenge');
    assert.equal(pairing.descriptor.operation,operation);assert.equal(pairing.descriptor.admin_origin,origin);
    const offer=await loopback(pairing,'GET','/v1/collect-admin/human-challenge/offer');assert.equal(offer.status,200);
    const payload=Buffer.from(offer.value.payload_base64url,'base64url');
    const publicKey=createPublicKey({key:{kty:'OKP',crv:'Ed25519',x:pairing.descriptor.listener_public_key_ed25519},format:'jwk'});
    assert.equal(verify(null,payload,publicKey,Buffer.from(offer.value.signature_ed25519_base64url,'base64url')),true);
    const signed=JSON.parse(payload);assert.equal(signed.admin_origin,origin);assert.equal(signed.operation,operation);assert.equal(signed.attempt_id,pairing.descriptor.attempt_id);
    const token='SYNTHETIC_NOT_PROVIDER_VERIFIED_'+randomUUID();onToken(token,pairing.descriptor);
    const response=await loopback(pairing,'POST','/v1/collect-admin/human-challenge/complete',{type:'collect.admin.human_challenge.complete.v1',attempt_id:pairing.descriptor.attempt_id,operation,nonce:signed.nonce,widget_attempt_id:pairing.descriptor.attempt_id,token});
    assert.equal(response.status,202);assert.equal(response.value.session_confirmed,false);assert.equal(JSON.stringify(response.value).includes(token),false);
  }});
}

export const syntheticEmailProof=(options={})=>syntheticProof(options);
export const syntheticPasswordProof=(options={})=>syntheticProof({...options,purpose:'password'});
