import {spawn} from "node:child_process";
import {validateKeychainHelper} from "./keychain_store.ts";
import {boundedJson, withinDeadline} from "./operational_client.ts";
import {validateSupervisorResult} from "../../../supabase/functions/collect-receipt-supervisor/handler.ts";

export const supervisorAudience = "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt";
const endpoint = "https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-supervisor";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const hash = /^[0-9a-f]{64}$/;
type Action = "prove_key" | "shadow_health" | "reconcile";
type Json = Record<string, unknown>;
export interface SupervisorIdentity {principalId: string; keySha256: string; expiresAt: string}
export type SupervisorSigner = (bytes: Uint8Array, signal: AbortSignal) => Promise<{keySha256: string; signature: string}>;
export interface SupervisorRequest {action: Action; requestId: string; targetRequestId?: string}
function object(value: unknown): value is Json {return value !== null && typeof value === "object" && !Array.isArray(value);}
function keys(value: unknown, names: string[]): value is Json {
  return object(value) && Object.keys(value).length === names.length && names.every(name => Object.hasOwn(value, name));
}
function utc(value: string) {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(Date.parse(value)).toISOString().slice(0,19) === value.slice(0,19);
}
const refusals: Record<string, number> = {
  SUPERVISOR_METHOD_REFUSED:405, SUPERVISOR_REQUEST_INVALID:400, SUPERVISOR_KEY_REFUSED:401,
  SUPERVISOR_BODY_TOO_LARGE:413,
  SUPERVISOR_SIGNATURE_REFUSED:401, SUPERVISOR_AUTHORITY_REFUSED:403, SUPERVISOR_PRINCIPAL_PENDING:403,
  SUPERVISOR_AUTHORITY_BUSY:409, SUPERVISOR_REQUEST_REFUSED:409, SUPERVISOR_AUTH_UNAVAILABLE:503,
  SUPERVISOR_OUTCOME_UNKNOWN:503,
};
function failure(action: Action) {return action === "reconcile" ? "SUPERVISOR_LOOKUP_UNAVAILABLE" : "SUPERVISOR_OUTCOME_UNKNOWN";}

/** One explicit request, one fixed endpoint, no operator token and no retry.
 * The caller must retain the request UUID before invocation; reconcile looks
 * up that original UUID and never reissues the original mutation. */
export async function callSupervisor(
  identity: SupervisorIdentity, input: SupervisorRequest, signer: SupervisorSigner,
  fetcher: typeof fetch = fetch, now: () => number = Date.now, timeoutMs = 5000,
) {
  const started = now();
  if (!keys(identity, ["principalId", "keySha256", "expiresAt"]) ||
      typeof identity.principalId !== "string" || !uuid.test(identity.principalId) ||
      typeof identity.keySha256 !== "string" || !hash.test(identity.keySha256) ||
      typeof identity.expiresAt !== "string" || !utc(identity.expiresAt) ||
      Date.parse(identity.expiresAt) <= started + 5000 ||
      !object(input) ||
      !keys(input, input.action === "reconcile" ? ["action", "requestId", "targetRequestId"] : ["action", "requestId"]) ||
      !["prove_key", "shadow_health", "reconcile"].includes(input.action) ||
      typeof input.requestId !== "string" || !uuid.test(input.requestId) ||
      (input.action === "reconcile" && (typeof input.targetRequestId !== "string" ||
        !uuid.test(input.targetRequestId) || input.targetRequestId === input.requestId)) ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000 ||
      !Number.isFinite(started)) throw new Error("SUPERVISOR_ARGUMENTS_INVALID");
  const payload: Json = input.action === "reconcile" ? {target_request_id:input.targetRequestId} : {};
  // Sorted ASCII-only keys agree with the hardware helper's canonical check.
  const envelope = {action:input.action, audience:supervisorAudience, contract_version:1,
    issued_at:new Date(started).toISOString(), payload, principal_id:identity.principalId, request_id:input.requestId};
  const bytes = new TextEncoder().encode(JSON.stringify(envelope));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let sent = false;
  try {
    const signature = await withinDeadline(signer(bytes, controller.signal), controller.signal);
    if (!keys(signature, ["keySha256", "signature"]) || signature.keySha256 !== identity.keySha256 ||
        typeof signature.signature !== "string" || signature.signature.length > 100 ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(signature.signature) ||
        Buffer.from(signature.signature,"base64").toString("base64") !== signature.signature ||
        Buffer.from(signature.signature,"base64").length < 8) throw new Error("SUPERVISOR_SIGNING_UNAVAILABLE");
    sent = true;
    const response = await withinDeadline(fetcher(endpoint, {
      method:"POST",redirect:"error",cache:"no-store",signal:controller.signal,
      headers:{"content-type":"application/json",Accept:"application/json",
        "X-Collect-Supervisor-Key-Id":identity.keySha256, "X-Collect-Supervisor-Signature":signature.signature},
      body:JSON.stringify(envelope),
    }), controller.signal);
    const result = await boundedJson(response, controller.signal);
    if (!response.ok || response.redirected) {
      if (!response.redirected && keys(result,["ok","code"]) && result.ok === false &&
          typeof result.code === "string" && Object.hasOwn(refusals,result.code) &&
          (refusals[result.code] === response.status || (result.code === "SUPERVISOR_OUTCOME_UNKNOWN" && response.status === 502))) {
        throw new Error(result.code);
      }
      throw new Error(failure(input.action));
    }
    if (!keys(result,["contract_version","principal_id","request_id","action","result"]) ||
        result.contract_version !== 1 || result.principal_id !== identity.principalId ||
        result.request_id !== input.requestId || result.action !== input.action ||
        !validateSupervisorResult(result.result,identity.principalId,input.requestId,input.action,payload)) {
      throw new Error(failure(input.action));
    }
    const observation = input.action === "reconcile" ? result.result.receipt : result.result;
    if (observation !== null && (!object(observation) || observation.expires_at !== identity.expiresAt ||
        Date.parse(observation.observed_at as string) > now() + 10000)) throw new Error(failure(input.action));
    if (input.action !== "reconcile" && object(observation) &&
        (Date.parse(observation.observed_at as string) < started - 10000 ||
          (input.action === "shadow_health" && Date.parse(observation.sample_valid_until as string) <= now()))) {
      throw new Error(failure(input.action));
    }
    return {contract_version:1, principal_id:identity.principalId, request_id:input.requestId,
      action:input.action, result:result.result as Json};
  } catch (error) {
    if (error instanceof Error && (Object.hasOwn(refusals,error.message) ||
        ["SUPERVISOR_SIGNING_UNAVAILABLE","SUPERVISOR_LOOKUP_UNAVAILABLE"].includes(error.message))) throw error;
    throw new Error(sent ? failure(input.action) : "SUPERVISOR_SIGNING_UNAVAILABLE");
  } finally {clearTimeout(timer);}
}

/** The helper is a separately installed, owner-private reviewed binary. Body
 * bytes travel on stdin; neither arguments nor stderr contain credentials. */
export function supervisorKeychainSigner(helper: string): SupervisorSigner {
  return async (bytes, signal) => {
    try {await validateKeychainHelper(helper);} catch {throw new Error("SUPERVISOR_SIGNING_UNAVAILABLE");}
    signal.throwIfAborted();
    return await new Promise((resolve,reject) => {
      const child = spawn(helper,["sign"],{stdio:["pipe","pipe","ignore"]});
      const chunks: Buffer[] = []; let length = 0; let settled = false;
      const done = (value?: {keySha256:string;signature:string}) => {
        if (settled) return; settled = true; signal.removeEventListener("abort",aborted);
        if (value) resolve(value); else reject(new Error("SUPERVISOR_SIGNING_UNAVAILABLE"));
      };
      const aborted = () => {child.kill(); done();};
      signal.addEventListener("abort",aborted,{once:true});
      child.on("error",()=>done()); child.stdin.on("error",()=>done());
      child.stdout.on("data",(data:Buffer)=>{length+=data.length;if(length>2048){child.kill();done();}else chunks.push(data);});
      child.on("close",code=>{
        if (code !== 0) return done();
        try {
          const value: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          if (keys(value,["contract_version","key_sha256","signature_base64"]) && value.contract_version===1 &&
              typeof value.key_sha256==="string" && hash.test(value.key_sha256) && typeof value.signature_base64==="string") {
            done({keySha256:value.key_sha256,signature:value.signature_base64});
          } else done();
        } catch {done();}
      });
      if (signal.aborted) aborted(); else child.stdin.end(bytes);
    });
  };
}
