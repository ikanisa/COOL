import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {pathToFileURL} from "node:url";
import {connectionPreflight} from "./preflight.ts";
import {productionOrigin, scopedRuntime} from "./runtime_credentials.ts";
import {loginSession, resolveStoredSession} from "./session_renewal.ts";
import {keychainStore, validateKeychainHelper, withSessionLock} from "./keychain_store.ts";

const phone = "+250788767816"; // Existing user-approved second Admin; no signup.
const cli = "/Users/jeanbosco/.npm/_npx/1517203cdeef2779/node_modules/@supabase/cli-darwin-arm64/bin/supabase";

async function publicKey() {
  const {stdout} = await promisify(execFile)(cli,["projects","api-keys","--project-ref","lhbowpbcpwoiparwnwgt","-o","json","--agent=yes"],{timeout:30000,maxBuffer:100000});
  const rows = JSON.parse(stdout) as {name:string;api_key:string}[];
  const key = rows.find(r=>r.name === "anon")?.api_key;
  if (!key) throw new Error("PUBLIC_CONFIG_UNAVAILABLE");
  return key;
}

export async function authRequest(path:string, body:Record<string,unknown>, key:string, fetcher:typeof fetch = fetch) {
  if (!["/otp","/verify"].includes(path)) throw new Error("INVALID_AUTH_ACTION");
  const response = await fetcher(`${productionOrigin}/auth/v1${path}`,{
    method:"POST",redirect:"error",signal:AbortSignal.timeout(15000),cache:"no-store",
    headers:{apikey:key,"Content-Type":"application/json"},body:JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`AUTH_HTTP_${response.status}`);
  return response.json() as Promise<Record<string,unknown>>;
}

async function readOtp():Promise<string> {
  process.stdin.setRawMode?.(true);
  process.stdin.resume();
  process.stderr.write("Enter the fresh approved-admin OTP (input hidden):\n");
  return new Promise((resolve,reject)=>{
    let buffer="";
    const finish=()=>{process.stdin.removeListener("data",onData);process.stdin.setRawMode?.(false);process.stdin.pause();};
    const onData=(data:Buffer)=>{
      const text=data.toString();
      if(text.includes("\u0003")){finish();reject(new Error("CANCELLED"));return;}
      buffer += text;
      if(buffer.includes("\n") || buffer.includes("\r")){
        finish();const code=buffer.trim();buffer="";
        if(/^\d{6}$/.test(code)) resolve(code); else reject(new Error("INVALID_OTP_FORMAT"));
      }
      if(buffer.length>32){finish();reject(new Error("INVALID_OTP_FORMAT"));}
    };
    process.stdin.on("data",onData);
  });
}

async function main() {
  const mode=process.argv[2];
  if(!["request","verify","renew"].includes(mode??"") || process.argv.length!==3) throw new Error("USE_REQUEST_VERIFY_OR_RENEW");
  if(mode==="renew"){
    const helper=process.env.COLLECT_OPERATOR_KEYCHAIN_HELPER;
    if(!helper) throw new Error("KEYCHAIN_HELPER_REQUIRED");
    await validateKeychainHelper(helper);
    const runtime=await withSessionLock(helper,()=>resolveStoredSession(keychainStore(helper),process.env,fetch,Date.now,{refreshNow:true}));
    const check=await connectionPreflight(runtime,true);
    if(check.status!=="PASS_AUTHENTICATED_READ_ONLY") throw new Error("OPERATOR_AUTHORIZATION_NOT_ESTABLISHED");
    console.log(JSON.stringify({status:"KEYCHAIN_SESSION_RENEWED",preflight:check,credentials_printed:false}));
    return;
  }
  const key=await publicKey();
  if(mode==="request"){
    await authRequest("/otp",{phone,channel:"whatsapp",create_user:false},key);
    console.log(JSON.stringify({status:"OTP_REQUESTED",phone_ending:"7816",creates_user:false}));
    return;
  }
  const helper=process.env.COLLECT_OPERATOR_KEYCHAIN_HELPER;
  if(!helper) throw new Error("KEYCHAIN_HELPER_REQUIRED");
  await validateKeychainHelper(helper);
  const session=await authRequest("/verify",{phone,token:await readOtp(),type:"sms"},key);
  const environment={...process.env,COLLECT_SUPABASE_URL:productionOrigin};
  const stored=loginSession(session,key,environment);
  const runtime=scopedRuntime({origin:productionOrigin,anon_key:key,access_token:session.access_token},environment);
  const check=await connectionPreflight(runtime,true);
  if(check.status!=="PASS_AUTHENTICATED_READ_ONLY") throw new Error("OPERATOR_AUTHORIZATION_NOT_ESTABLISHED");
  await withSessionLock(helper,()=>keychainStore(helper).write(stored));
  console.log(JSON.stringify({status:"KEYCHAIN_SESSION_SAVED",preflight:check,session_expires_at:session.expires_at,refresh_token_stored:Object.hasOwn(stored,"refresh_token")}));
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
  main().catch(()=>{console.error("Collect operator login incomplete; no credential was printed. Check OTP delivery, active approval and Keychain availability before retrying.");process.exitCode=2;});
}
