#!/usr/bin/env node
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {configuration,SafeError,UUID} from './config.mjs';
import {RetentionApi} from './retention_api.mjs';
import {acquireHumanChallenge} from './human_challenge.mjs';
import {secretPrompt} from './login.mjs';

/** Check the original session once after an uncertain verify reply. Never
 * repeat the OTP/provider request or replace the local Admin session. */
export async function verifyCurrentEmail(api,challengeId,code,{requestedAfter=Date.now()-300000}={}){
 try{return await api.verifyEmail(challengeId,code);}
 catch(error){
  try{const proof=await api.verificationStatus();const at=proof.emailVerifiedAt===null?0:Date.parse(proof.emailVerifiedAt);
   if(at>=requestedAfter&&at<=Date.now()&&Date.now()-at<=300000)return proof;
  }catch{/* No second OTP or provider request. */}
  if(error instanceof SafeError)throw error;
  throw new SafeError('email_verification_unknown','Email verification is unconfirmed. Check the original session; no code was replayed.');
 }
}
export function verificationArguments(args,interactive){
 if(!interactive||args.length!==0&&!(args.length===2&&args[0]==='resume'&&UUID.test(args[1]??'')))
  throw new SafeError('interactive_verification_required','Run npm run verify-email directly in a terminal, optionally with resume and the original challenge UUID. Email codes, passwords and CAPTCHA tokens in arguments, pipes or environment variables are not accepted.');
 return args[1]??null;
}
async function main(){
 const existing=verificationArguments(process.argv.slice(2),process.stdin.isTTY&&process.stderr.isTTY),config=configuration(),api=new RetentionApi(config);
 const current=await api.verificationStatus();
 if(!existing&&current.emailVerifiedAt!==null&&Date.now()-Date.parse(current.emailVerifiedAt)<240000){process.stderr.write('This same Admin session already has fresh email verification. No new code was requested.\n');return;}
 let token='',code='';const requestedAfter=Date.now()-1000;let challengeId=existing;
 try{
  if(!challengeId){
   token=await acquireHumanChallenge(config,{operation:'admin.email_otp.send',onPairing:({descriptor,parentUrl})=>{
    process.stderr.write(`Open ${parentUrl} in your normal browser and connect this public challenge:\n${JSON.stringify(descriptor)}\n`);
   }});
   const challenge=await api.requestVerification(token);token='';challengeId=challenge.challenge_id;
   process.stderr.write(`Original verification reference: ${challengeId}\n`);
   process.stderr.write(challenge.delivery_status==='unknown'?'Delivery is unconfirmed. Enter the original code if it arrives; no replacement was requested.\n':'The code request was accepted. Enter the code sent to this Admin account email.\n');
   process.stderr.write(`Expires within ${challenge.expires_in} seconds. Keep the same local session; do not sign in again.\n`);
  }
  code=await secretPrompt('Email code (hidden): ',6);
  const proof=await verifyCurrentEmail(api,challengeId,code,{requestedAfter:existing?Date.now()-300000:requestedAfter});
  process.stderr.write(`Email verification is current as of ${proof.emailVerifiedAt}. The original Admin session and operation references are preserved.\n`);
 }finally{token='';code='';}
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url)main().catch(error=>{
 process.stderr.write((error instanceof SafeError?error.message:'Email verification could not be confirmed. No code or session credential was printed.')+'\n');process.exitCode=1;
});
