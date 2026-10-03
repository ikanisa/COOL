import {spawn} from "node:child_process";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {boundedJson, withinDeadline} from "./operational_client.ts";
import {validateKeychainHelper} from "./keychain_store.ts";
import {envelope, keys, object, validResult, hash, uuid, unattendedEndpoint} from "./unattended_contract.ts";
import type {UnattendedIdentity, UnattendedRequest, Json} from "./unattended_contract.ts";
export type UnattendedSigner = (bytes: Uint8Array, signal: AbortSignal) => Promise<{keySha256: string; signature: string}>;
export function validSignature(value: unknown, expectedKey: string): value is {keySha256: string; signature: string} {
  return keys(value, ["keySha256", "signature"]) && value.keySha256 === expectedKey && typeof value.signature === "string" &&
    value.signature.length <= 100 && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value.signature) &&
    Buffer.from(value.signature, "base64").toString("base64") === value.signature &&
    Buffer.from(value.signature, "base64").length >= 8;
}
/** Exactly one fixed-endpoint request. Every operational caller must use the
 * durable journal; this transport never changes a UUID or retries a mutation. */
export async function callUnattended(identity: UnattendedIdentity, input: UnattendedRequest, signer: UnattendedSigner,
  fetcher: typeof fetch = fetch, now: () => number = Date.now, timeoutMs = 5000, parentSignal?: AbortSignal): Promise<Json> {
  const started = now(), body = JSON.stringify(envelope(identity, input, started));
  if (typeof signer !== "function" || typeof fetcher !== "function" || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), timeoutMs);
  const signal = parentSignal ? AbortSignal.any([controller.signal, parentSignal]) : controller.signal;
  let sent = false;
  try {
    const signature = await withinDeadline(signer(new TextEncoder().encode(body), signal), signal);
    if (!validSignature(signature, identity.keySha256)) throw new Error("UNATTENDED_SIGNING_UNAVAILABLE");
    signal.throwIfAborted(); sent = true;
    const response = await withinDeadline(fetcher(unattendedEndpoint, {method: "POST", redirect: "error", cache: "no-store", signal,
      headers: {"content-type": "application/json", Accept: "application/json", "X-Collect-Supervisor-Key-Id": identity.keySha256,
        "X-Collect-Supervisor-Signature": signature.signature}, body}), signal);
    const result = await boundedJson(response, signal);
    if (!response.ok || response.redirected || !keys(result, ["contract_version", "principal_id", "request_id", "action", "result"]) ||
        result.contract_version !== 2 || result.principal_id !== identity.principalId || result.request_id !== input.requestId || result.action !== input.action ||
        !validResult(result.result, identity, input)) throw new Error("UNATTENDED_OUTCOME_UNKNOWN");
    const observation = input.action === "reconcile_request" ? result.result.receipt : result.result;
    if (observation !== null && (!object(observation) || typeof observation.observed_at !== "string" ||
        Date.parse(observation.observed_at) > now() + 10000)) throw new Error("UNATTENDED_OUTCOME_UNKNOWN");
    if (input.action !== "reconcile_request" && observation !== null &&
        (Date.parse((observation as Json).observed_at as string) < started - 10000 || Date.parse((observation as Json).observed_at as string) >= Date.parse(identity.expiresAt))) throw new Error("UNATTENDED_OUTCOME_UNKNOWN");
    if (input.action === "begin_run" && result.result.ok === true && Date.parse(result.result.expires_at as string) > Date.parse(identity.expiresAt)) throw new Error("UNATTENDED_OUTCOME_UNKNOWN");
    if (input.action === "prove_key" && (result.result as Json).expires_at !== identity.expiresAt) throw new Error("UNATTENDED_OUTCOME_UNKNOWN");
    return result.result;
  } catch (error) {
    if (error instanceof Error && error.message === "UNATTENDED_SIGNING_UNAVAILABLE") throw error;
    throw new Error(sent ? (input.action === "reconcile_request" ? "UNATTENDED_LOOKUP_UNAVAILABLE" : "UNATTENDED_OUTCOME_UNKNOWN") : "UNATTENDED_SIGNING_UNAVAILABLE");
  } finally {clearTimeout(timer);}
}
/** Separate v2 hardware helper, reviewed hash binding, private pipe and minimal
 * environment. No member/operator/service-role credential is consumed. */
export function unattendedKeychainSigner(helper: string, expectedHash: string, keyTagId?: string): UnattendedSigner {
  return async (bytes, signal) => {
    try {
      if (!hash(expectedHash) || keyTagId !== undefined && !uuid(keyTagId)) throw Error();
      await validateKeychainHelper(helper);
      if (createHash("sha256").update(await readFile(helper)).digest("hex") !== expectedHash) throw Error();
    } catch {throw new Error("UNATTENDED_SIGNING_UNAVAILABLE");}
    signal.throwIfAborted();
    return await new Promise((resolve, reject) => {
      const child = spawn(helper, keyTagId === undefined ? ["sign"] : ["sign", keyTagId], {stdio: ["pipe", "pipe", "ignore"], env: {PATH: "/usr/bin:/bin", LANG: "C"}});
      const chunks: Buffer[] = []; let length = 0, settled = false;
      const done = (value?: {keySha256: string; signature: string}) => {
        if (settled) return; settled = true; signal.removeEventListener("abort", abort);
        if (value) resolve(value); else reject(new Error("UNATTENDED_SIGNING_UNAVAILABLE"));
      };
      const abort = () => {child.kill(); done();};
      signal.addEventListener("abort", abort, {once: true});
      child.on("error", () => done()); child.stdin.on("error", () => done());
      child.stdout.on("data", (chunk: Buffer) => {length += chunk.length; if (length > 2048) {child.kill(); done();} else chunks.push(chunk);});
      child.on("close", code => {
        if (code !== 0) return done();
        try {
          const value: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          if (keys(value, ["contract_version", "key_sha256", "signature_base64"]) && value.contract_version === 2 &&
              hash(value.key_sha256) && typeof value.signature_base64 === "string") done({keySha256: value.key_sha256, signature: value.signature_base64});
          else done();
        } catch {done();}
      });
      if (signal.aborted) abort(); else child.stdin.end(bytes);
    });
  };
}
