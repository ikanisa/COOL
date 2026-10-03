import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {pathToFileURL} from "node:url";
import {connectionPreflight} from "./preflight.ts";
import {productionOrigin, scopedRuntime} from "./runtime_credentials.ts";
import {loginSession, resolveStoredSession} from "./session_renewal.ts";
import {keychainStore, validateKeychainHelper, withSessionLock} from "./keychain_store.ts";

export const operatorEmail = "info@ikanisa.com"; // Owner-selected enrolled operator; no signup.
const cli = "/Volumes/PRO-G40/Development/User-Developer/supabase_2_84_2_codex/supabase"; // Pinned, locally verified CLI 2.84.2.

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

export async function requestOperatorEmailOtp(key:string, fetcher:typeof fetch = fetch) {
  return authRequest("/otp",{email:operatorEmail,create_user:false},key,fetcher);
}

export async function verifyOperatorEmailOtp(token:string,key:string,fetcher:typeof fetch = fetch) {
  if(!/^\d{6}$/.test(token)) throw new Error("INVALID_OTP_FORMAT");
  const session=await authRequest("/verify",{email:operatorEmail,token,type:"email"},key,fetcher);
  try {
    if(!session || typeof session!=="object" || Array.isArray(session)) throw new Error();
    const user=session.user;
    if(!user || typeof user!=="object" || Array.isArray(user)) throw new Error();
    const identity=user as Record<string,unknown>;
    if(typeof identity.email!=="string" || identity.email.trim().toLowerCase()!==operatorEmail ||
       typeof identity.id!=="string" || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(identity.id) ||
       typeof session.access_token!=="string") throw new Error();
    const parts=session.access_token.split(".");
    if(parts.length!==3) throw new Error();
    const claims=JSON.parse(Buffer.from(parts[1]!,"base64url").toString()) as Record<string,unknown>;
    if(!claims || typeof claims!=="object" || Array.isArray(claims) || claims.sub!==identity.id) throw new Error();
    return session;
  } catch {
    throw new Error("OPERATOR_EMAIL_IDENTITY_UNCONFIRMED");
  }
}

async function readOtp():Promise<string> {
  if(!process.stdin.isTTY || typeof process.stdin.setRawMode!=="function") throw new Error("PRIVATE_TERMINAL_REQUIRED");
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stderr.write("Enter the fresh approved-operator email OTP (input hidden):\n");
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
    const runtime=await withSessionLock(helper,()=>resolveStoredSession(keychainStore(helper),process.env,fetch,Date.now,{refreshNow:true,requiredEmail:operatorEmail}));
    const check=await connectionPreflight(runtime,true);
    if(check.status!=="PASS_AUTHENTICATED_READ_ONLY") throw new Error("OPERATOR_AUTHORIZATION_NOT_ESTABLISHED");
    console.log(JSON.stringify({status:"KEYCHAIN_SESSION_RENEWED",preflight:check,credentials_printed:false}));
    return;
  }
  const key=await publicKey();
  if(mode==="request"){
    await requestOperatorEmailOtp(key);
    console.log(JSON.stringify({status:"EMAIL_OTP_REQUESTED",creates_user:false}));
    return;
  }
  const helper=process.env.COLLECT_OPERATOR_KEYCHAIN_HELPER;
  if(!helper) throw new Error("KEYCHAIN_HELPER_REQUIRED");
  await validateKeychainHelper(helper);
  const session=await verifyOperatorEmailOtp(await readOtp(),key);
  const environment={...process.env,COLLECT_SUPABASE_URL:productionOrigin};
  const stored=loginSession(session,key,environment);
  const runtime=scopedRuntime({origin:productionOrigin,anon_key:key,access_token:session.access_token},environment);
  const check=await connectionPreflight(runtime,true);
  if(check.status!=="PASS_AUTHENTICATED_READ_ONLY") throw new Error("OPERATOR_AUTHORIZATION_NOT_ESTABLISHED");
  await withSessionLock(helper,()=>keychainStore(helper).write(stored));
  console.log(JSON.stringify({status:"KEYCHAIN_SESSION_SAVED",preflight:check,session_expires_at:session.expires_at,refresh_token_stored:Object.hasOwn(stored,"refresh_token")}));
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
  main().catch(()=>{console.error("Collect operator email login incomplete; no credential was printed. Check existing email enrollment, delivery, active approval and Keychain availability before retrying.");process.exitCode=2;});
}
