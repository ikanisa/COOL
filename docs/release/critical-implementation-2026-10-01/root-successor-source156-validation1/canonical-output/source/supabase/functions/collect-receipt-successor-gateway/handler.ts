import { derToP1363 } from "../collect-android-gateway/handler.ts";
import { Action, AUDIENCE, digest, FAMILY, hash, Json, keys, payload, result, RPC, sameUuid, utc, uuid } from "./wire.ts";
export interface SuccessorDependencies {
 rpc(name: string, args: Json, signal: AbortSignal): Promise<{data: unknown; error: {code?: string}|null}>;
 now?: () => number; timeoutMs?: number;
}
class Refusal extends Error { constructor(readonly status: number, readonly code: string) { super(code); } }
function require(condition: unknown): asserts condition { if (!condition) throw new Refusal(400, "GATEWAY_REQUEST_INVALID"); }
function base64(value: unknown, max: number): Uint8Array {
  require(
    typeof value === "string" && value.length <= max &&
      /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
        value,
      ),
  );
  let decoded: string;
  try {
    decoded = atob(value);
  } catch {
    throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
  }
  require(btoa(decoded) === value);
  return Uint8Array.from(decoded, (c) => c.charCodeAt(0));
}
function parseStrict(text: string): unknown {
  let at = 0;
  const ws = () => {
    while (/[\t\n\r ]/.test(text[at] ?? "x")) at++;
  };
  const string = (): string => {
    require(text[at] === '"');
    const start = at++;
    while (at < text.length) {
      if (text[at++] === "\\") {
        at++;
        continue;
      }
      if (text[at - 1] === '"') return JSON.parse(text.slice(start, at));
    }
    throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
  };
  const value = (depth: number): void => {
    require(depth <= 8);
    ws();
    if (text[at] === "{") {
      at++;
      ws();
      const seen = new Set<string>();
      if (text[at] === "}") {
        at++;
        return;
      }
      while (true) {
        ws();
        const key = string();
        require(!seen.has(key));
        seen.add(key);
        ws();
        require(text[at++] === ":");
        value(depth + 1);
        ws();
        if (text[at] === "}") {
          at++;
          return;
        }
        require(text[at++] === ",");
      }
    } else if (text[at] === "[") {
      at++;
      ws();
      if (text[at] === "]") {
        at++;
        return;
      }
      while (true) {
        value(depth + 1);
        ws();
        if (text[at] === "]") {
          at++;
          return;
        }
        require(text[at++] === ",");
      }
    } else if (text[at] === '"') string();
    else {
      const token =
        /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(
          text.slice(at),
        );
      require(token);
      at += token[0].length;
    }
  };
  value(0);
  ws();
  require(at === text.length);
  try {
    return JSON.parse(text);
  } catch {
    throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
  }
}
async function body(request: Request, timeout: number): Promise<Uint8Array> {
  require(
    /^application\/json(?:;\s*charset=utf-8)?$/i.test(
      request.headers.get("content-type") ?? "",
    ),
  );
  require(!request.headers.has("content-encoding"));
  const length = request.headers.get("content-length");
  if (length !== null) require(/^\d+$/.test(length) && Number(length) <= 8192);
  require(request.body);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let count = 0;
  const deadline = Date.now() + timeout;
  try {
    while (true) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const chunk = await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            reader.cancel().catch(() => {});
            reject(new Refusal(408, "GATEWAY_REQUEST_INVALID"));
          }, Math.max(1, deadline - Date.now()));
        }),
      ]).finally(() => {
        if (timer !== undefined) clearTimeout(timer);
      });
      if (chunk.done) break;
      count += chunk.value.length;
      if (count > 8192) {
        await reader.cancel();
        throw new Refusal(413, "GATEWAY_BODY_TOO_LARGE");
      }
      chunks.push(chunk.value);
    }
  } finally {
    reader.releaseLock();
  }
  require(count > 0 && (length === null || Number(length) === count));
  const result = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  require(!(result[0] === 0xef && result[1] === 0xbb && result[2] === 0xbf));
  return result;
}

function response(status: number, data: Json): Response {
 return new Response(JSON.stringify(data), {status, headers: {"content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff"}});
}
export function createSuccessorGatewayHandler(deps: SuccessorDependencies): (request: Request) => Promise<Response> {
 const now = deps.now ?? Date.now; const timeout = Math.min(10000, Math.max(1, deps.timeoutMs ?? 5000));
 async function rpc(name: string, args: Json): Promise<unknown> {
  const controller = new AbortController(); let timer: ReturnType<typeof setTimeout>|undefined;
  try {
   const value = await Promise.race([deps.rpc(name, args, controller.signal), new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Refusal(504, "GATEWAY_OUTCOME_UNKNOWN")); }, timeout); })]);
   if (value.error) {
    if (value.error.code === "42501") throw new Refusal(403, "GATEWAY_AUTHORITY_REFUSED");
    if (["22023", "23505", "55000"].includes(value.error.code ?? "")) throw new Refusal(409, "GATEWAY_REQUEST_REFUSED");
    throw new Refusal(503, "GATEWAY_OUTCOME_UNKNOWN");
   }
   if (JSON.stringify(value.data).length > 8192) throw new Refusal(502, "GATEWAY_OUTCOME_UNKNOWN");
   return value.data;
  } finally { if (timer !== undefined) clearTimeout(timer); }
 }
 return async request => {
  try {
   if (request.method !== "POST") throw new Refusal(405, "GATEWAY_POST_REQUIRED");
   const raw = await body(request, timeout); let text: string;
   try { text = new TextDecoder("utf-8", {fatal: true}).decode(raw); } catch { throw new Refusal(400, "GATEWAY_REQUEST_INVALID"); }
   const envelope = parseStrict(text);
   require(keys(envelope, ["contract_version", "protocol_family", "audience", "action", "device_id", "request_id", "issued_at", "payload"]));
   require(envelope.contract_version === 1 && envelope.protocol_family === FAMILY && envelope.audience === AUDIENCE && typeof envelope.action === "string" && Object.hasOwn(RPC, envelope.action));
   require(uuid(envelope.device_id) && uuid(envelope.request_id) && utc(envelope.issued_at) && Math.abs(now() - Date.parse(envelope.issued_at)) <= 120000);
   const action = envelope.action as Action;
   require(payload(action, envelope.payload, envelope.request_id));
   const keyId = request.headers.get("X-Collect-Gateway-Key-Id"); require(hash(keyId));
   let signature: Uint8Array; try { signature = derToP1363(base64(request.headers.get("X-Collect-Gateway-Signature"), 100)); } catch { throw new Refusal(400, "GATEWAY_REQUEST_INVALID"); }
   const key = await rpc("gateway_device_key_v1", {p_device_id: envelope.device_id});
   if (!keys(key, ["device_id", "state", "public_key_spki_base64", "key_sha256", "installation_id", "signing_certificate_sha256"]) || !sameUuid(key.device_id, envelope.device_id) || !["pending", "active", "revoked"].includes(key.state as string) || !uuid(key.installation_id) || !hash(key.key_sha256) || !hash(key.signing_certificate_sha256)) throw new Refusal(401, "GATEWAY_KEY_REFUSED");
   const spki = base64(key.public_key_spki_base64, 124);
   if (spki.length !== 91 || await digest(spki) !== key.key_sha256 || key.key_sha256 !== keyId) throw new Refusal(401, "GATEWAY_KEY_REFUSED");
   let verified = false;
   try { const imported = await crypto.subtle.importKey("spki", new Uint8Array(spki), {name: "ECDSA", namedCurve: "P-256"}, false, ["verify"]); verified = await crypto.subtle.verify({name: "ECDSA", hash: "SHA-256"}, imported, new Uint8Array(signature), new Uint8Array(raw)); } catch { verified = false; }
   if (!verified) throw new Refusal(401, "GATEWAY_SIGNATURE_REFUSED");
   if (key.state !== "active" && ["dispatch_grant", "arm_dispatch"].includes(action)) throw new Refusal(403, "GATEWAY_DEVICE_REVOKED");
   const value = await rpc(RPC[action], {p_device_id: envelope.device_id, p_request_id: envelope.request_id, p_request_sha256: await digest(raw), p_payload: envelope.payload});
   if (!await result(action, value, envelope.device_id, envelope.request_id, envelope.payload, now())) throw new Refusal(502, "GATEWAY_OUTCOME_UNKNOWN");
   return response(200, {contract_version: 1, protocol_family: FAMILY, audience: AUDIENCE, action, device_id: envelope.device_id, request_id: envelope.request_id, result: value});
  } catch (error) {
   if (error instanceof Refusal) return response(error.status, {ok: false, code: error.code, send_authority: false});
   return response(503, {ok: false, code: "GATEWAY_OUTCOME_UNKNOWN", send_authority: false});
  }
 };
}
