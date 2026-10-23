import {performance} from 'node:perf_hooks';
import {acquireHumanChallenge} from '../../collect-admin-mcp/src/human_challenge.mjs';
import {ORIGINS,need} from './contract.mjs';

// Opaque, one-use memory custody, bound to the exact origin and intended send.
const candidates=new WeakMap();
async function acquire(origin,purpose,operation,{onPairing,signal}={}) {
  need(ORIGINS.includes(origin),'independently_approved_frontend_origin_required');
  let expiresAt;const started=performance.now();
  const token=await acquireHumanChallenge({origin},{operation,signal,onPairing:pairing=>{
    expiresAt=pairing.descriptor.expires_at_ms;return onPairing(pairing);
  }});
  const proof=Object.freeze({});candidates.set(proof,{origin,purpose,token,expiresAt,started,signal});return proof;
}
function consume(proof,origin,purpose) {
  const candidate=proof&&typeof proof==='object'?candidates.get(proof):undefined;
  if(candidate)candidates.delete(proof);
  need(candidate&&candidate.origin===origin&&candidate.purpose===purpose&&!candidate.signal?.aborted&&Date.now()<candidate.expiresAt&&performance.now()-candidate.started<120000,'fresh_bound_human_captcha_required');
  return candidate.token;
}
export function acquireEmailProof({origin,purpose='sign_in'},options={}) {
  need(['sign_in','sensitive'].includes(purpose),'invalid_email_proof_purpose');return acquire(origin,purpose,'admin.email_otp.send',options);
}
export function consumeEmailProof(proof,origin,purpose) {
  need(['sign_in','sensitive'].includes(purpose),'invalid_email_proof_purpose');return consume(proof,origin,purpose);
}
// Compatibility only: no password capability can substitute for an email send.
export const acquirePasswordProof=({origin},options={})=>acquire(origin,'password','admin.password.sign_in',options);
export const consumePasswordProof=(proof,origin)=>consume(proof,origin,'password');
