type Json = Record<string, unknown>;
type V1Action = "heartbeat" | "reconcile" | "callback" | "dispatch_grant";
type V2Action =
  | "dispatch_grant"
  | "arm_dispatch"
  | "callback"
  | "reconcile"
  | "attempt_status";
type Action = V1Action | V2Action;
const V1_RPC: Record<V1Action, string> = {
  heartbeat: "gateway_heartbeat_v1",
  callback: "gateway_callback_v1",
  reconcile: "gateway_reconcile_v1",
  dispatch_grant: "gateway_dispatch_grant_v1",
};
const V2_RPC: Record<V2Action, string> = {
  dispatch_grant: "gateway_dispatch_grant_v2",
  arm_dispatch: "gateway_arm_dispatch_v2",
  callback: "gateway_callback_v2",
  reconcile: "gateway_reconcile_v2",
  attempt_status: "gateway_attempt_status_v2",
};
export interface GatewayDependencies {
  rpc(
    name: string,
    args: Json,
    signal: AbortSignal,
  ): Promise<{ data: unknown; error: { code?: string } | null }>;
  now?: () => number;
  timeoutMs?: number;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
class Refusal extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}
function object(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function keys(value: unknown, expected: string[]): value is Json {
  return object(value) && Object.keys(value).length === expected.length &&
    expected.every((k) => Object.hasOwn(value, k));
}
function uuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}
function hash(value: unknown): value is string {
  return typeof value === "string" && HASH.test(value);
}
function integer(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) &&
    value >= min && value <= max;
}
function utc(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value)
  ) return false;
  const ms = Date.parse(value);
  return Number.isFinite(ms) &&
    new Date(ms).toISOString().slice(0, 19) === value.slice(0, 19);
}
function require(condition: unknown): asserts condition {
  if (!condition) throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
}
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
function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
async function digest(bytes: Uint8Array): Promise<string> {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  );
}
// Android emits canonical DER; WebCrypto expects fixed-width P1363 r||s.
export function derToP1363(der: Uint8Array): Uint8Array {
  require(
    der.length >= 8 && der.length <= 72 && der[0] === 0x30 &&
      der[1] === der.length - 2,
  );
  let offset = 2;
  const output = new Uint8Array(64);
  for (let component = 0; component < 2; component++) {
    require(der[offset++] === 0x02);
    const size = der[offset++];
    require(size >= 1 && size <= 33 && offset + size <= der.length);
    let value = der.slice(offset, offset + size);
    offset += size;
    require(!(value[0] & 0x80));
    require(value.length === 1 || value[0] !== 0 || !!(value[1] & 0x80));
    if (value[0] === 0) value = value.slice(1);
    require(value.length <= 32 && value.length > 0);
    const number = BigInt("0x" + hex(value));
    require(
      number > 0n &&
        number <
          0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n,
    );
    output.set(value, component * 32 + 32 - value.length);
  }
  require(offset === der.length);
  return output;
}
// Reject duplicate keys before JSON.parse loses them; impose a shallow bound.
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
function payload(action: Action, p: unknown): asserts p is Json {
  if (action === "heartbeat") {
    require(
      keys(p, [
        "sms_permission",
        "network",
        "telephony",
        "sim_selected",
        "sim_revision_sha256",
        "local_pause",
        "reported_at",
      ]),
    );
    require(
      typeof p.sms_permission === "boolean" &&
        typeof p.sim_selected === "boolean" &&
        typeof p.local_pause === "boolean",
    );
    require(
      ["validated", "unvalidated", "offline", "unknown"].includes(
        p.network as string,
      ),
    );
    require(
      ["ready", "unavailable", "unknown"].includes(p.telephony as string),
    );
    require(
      p.sim_selected
        ? hash(p.sim_revision_sha256)
        : p.sim_revision_sha256 === null,
    );
    require(utc(p.reported_at));
  } else if (action === "callback") {
    require(
      keys(p, [
        "callback_id",
        "attempt_id",
        "fence_version",
        "segment_index",
        "segment_count",
        "body_sha256",
        "destination_sha256",
        "callback_kind",
        "result_code",
        "tp_status",
        "occurred_at",
      ]),
    );
    require(
      uuid(p.callback_id) && uuid(p.attempt_id) &&
        integer(p.fence_version, 1, 1e9),
    );
    require(
      integer(p.segment_index, 0, 9) && integer(p.segment_count, 1, 10) &&
        p.segment_index < p.segment_count,
    );
    require(
      hash(p.body_sha256) && hash(p.destination_sha256) &&
        ["sent", "delivery"].includes(p.callback_kind as string),
    );
    require(
      integer(p.result_code, -1, 200) &&
        (p.tp_status === null || integer(p.tp_status, 0, 255)) &&
        utc(p.occurred_at),
    );
  } else if (action === "reconcile") {
    require(keys(p, ["target_request_id"]) && uuid(p.target_request_id));
  } else if (action === "attempt_status") {
    require(
      keys(p, ["attempt_id", "fence_version"]) && uuid(p.attempt_id) &&
        integer(p.fence_version, 1, 1e9),
    );
  } else if (action === "arm_dispatch") {
    require(
      keys(p, [
        "attempt_id",
        "fence_version",
        "body_sha256",
        "destination_sha256",
        "callbacks",
        "reservation_sha256",
      ]),
    );
    require(
      uuid(p.attempt_id) && integer(p.fence_version, 1, 1e9) &&
        hash(p.body_sha256) && hash(p.destination_sha256) &&
        hash(p.reservation_sha256) && Array.isArray(p.callbacks) &&
        p.callbacks.length >= 1 && p.callbacks.length <= 10,
    );
    const callbackIds = new Set<string>();
    for (const [index, callback] of p.callbacks.entries()) {
      require(
        keys(callback, [
          "segment_index",
          "sent_callback_id",
          "delivery_callback_id",
        ]) && callback.segment_index === index &&
          uuid(callback.sent_callback_id) &&
          uuid(callback.delivery_callback_id),
      );
      for (
        const id of [callback.sent_callback_id, callback.delivery_callback_id]
      ) {
        const normalized = id.toLowerCase();
        require(!callbackIds.has(normalized));
        callbackIds.add(normalized);
      }
    }
  } else require(keys(p, []));
}
function validResult(
  action: V1Action,
  data: unknown,
  device: string,
  request: string,
  p?: Json,
): data is Json {
  if (action === "heartbeat") {
    return keys(data, [
      "observation_id",
      "ingested_at",
      "replay",
      "carrier_proof",
    ]) && uuid(data.observation_id) && utc(data.ingested_at) &&
      typeof data.replay === "boolean" && data.carrier_proof === false;
  }
  if (action === "callback") {
    return keys(data, [
      "callback_id",
      "recorded_at",
      "replay",
      "carrier_proof",
    ]) && uuid(data.callback_id) &&
      (!p || data.callback_id === p.callback_id) && utc(data.recorded_at) &&
      typeof data.replay === "boolean" && data.carrier_proof === false;
  }
  if (action === "dispatch_grant") {
    return keys(data, ["ok", "code", "device_id", "request_id", "replay"]) &&
      data.ok === false && data.code === "GATEWAY_DISPATCH_AUTHORITY_PENDING" &&
      data.device_id === device && data.request_id === request &&
      typeof data.replay === "boolean";
  }
  if (
    !keys(data, [
      "target_request_id",
      "outcome",
      "recorded_action",
      "recorded_result",
    ]) || !uuid(data.target_request_id) ||
    (p && data.target_request_id !== p.target_request_id)
  ) return false;
  if (data.outcome === "unknown") {
    return data.recorded_action === null && data.recorded_result === null;
  }
  if (
    data.outcome !== "recorded" ||
    !["heartbeat", "callback", "dispatch_grant"].includes(
      data.recorded_action as string,
    )
  ) return false;
  return validResult(
    data.recorded_action as V1Action,
    data.recorded_result,
    device,
    data.target_request_id,
  );
}
function sameUuid(left: unknown, right: unknown): boolean {
  return uuid(left) && uuid(right) &&
    left.toLowerCase() === right.toLowerCase();
}
const DISPATCH_REFUSALS = new Set([
  "OPERATIONS_PAUSED",
  "NO_CURRENT_RUN",
  "DEVICE_NOT_READY",
  "NO_ELIGIBLE_RECEIPT",
  "QUOTA_EXHAUSTED",
  "ORIGINAL_REQUEST_RECORDED",
]);
function dispatchRefusal(
  data: unknown,
  device: string,
  request: string,
): data is Json {
  return keys(data, ["ok", "code", "device_id", "request_id", "replay"]) &&
    data.ok === false && DISPATCH_REFUSALS.has(data.code as string) &&
    sameUuid(data.device_id, device) && sameUuid(data.request_id, request) &&
    typeof data.replay === "boolean";
}
function dispatchDeadline(
  start: unknown,
  expires: unknown,
  now: number,
): boolean {
  return utc(start) && utc(expires) &&
    Date.parse(expires) > Date.parse(start) &&
    Date.parse(expires) <= Date.parse(start) + 30000 &&
    Date.parse(expires) > now;
}
function dispatchCounts(data: Json, segmentCount?: unknown): boolean {
  const count = integer(segmentCount, 1, 10) ? segmentCount : 10;
  return integer(data.sent_observations, 0, count) &&
    integer(data.delivery_observations, 0, count) &&
    typeof data.conflicting_observations === "boolean" &&
    data.carrier_proof === false &&
    (data.state !== "observed_sent" ||
      (data.conflicting_observations === false && data.sent_observations > 0 &&
        (segmentCount === undefined || data.sent_observations === count)));
}
async function validDispatchResult(
  action: V2Action,
  data: unknown,
  device: string,
  request: string,
  now: number,
  p?: Json,
): Promise<boolean> {
  if (action === "dispatch_grant" || action === "arm_dispatch") {
    if (dispatchRefusal(data, device, request)) return true;
    if (action === "dispatch_grant") {
      if (
        !keys(data, [
          "ok",
          "code",
          "device_id",
          "request_id",
          "attempt_id",
          "receipt_id",
          "run_id",
          "fence_version",
          "policy_revision",
          "issued_at",
          "expires_at",
          "segment_count",
          "body",
          "destination_e164",
          "body_sha256",
          "destination_sha256",
          "sim_revision_sha256",
          "replay",
        ]) || data.ok !== true || data.code !== "DISPATCH_GRANTED" ||
        !sameUuid(data.device_id, device) ||
        !sameUuid(data.request_id, request) ||
        !uuid(data.attempt_id) || !uuid(data.receipt_id) ||
        !uuid(data.run_id) ||
        !integer(data.fence_version, 1, 1e9) ||
        !integer(data.policy_revision, 1, 1e9) ||
        !dispatchDeadline(data.issued_at, data.expires_at, now) ||
        !integer(data.segment_count, 1, 10) ||
        typeof data.body !== "string" || data.body.length === 0 ||
        [...data.body].length > 1000 ||
        typeof data.destination_e164 !== "string" ||
        !/^\+2507[2389][0-9]{7}$/.test(data.destination_e164) ||
        !hash(data.body_sha256) || !hash(data.destination_sha256) ||
        !hash(data.sim_revision_sha256) || data.replay !== false
      ) return false;
      const encoder = new TextEncoder();
      const encodedBody = encoder.encode(data.body);
      return encodedBody.length <= 4000 &&
        await digest(encodedBody) === data.body_sha256 &&
        await digest(encoder.encode(data.destination_e164)) ===
          data.destination_sha256;
    }
    return keys(data, [
      "ok",
      "code",
      "device_id",
      "request_id",
      "attempt_id",
      "fence_version",
      "reservation_sha256",
      "armed_at",
      "expires_at",
      "replay",
      "carrier_proof",
    ]) && data.ok === true && data.code === "DISPATCH_ARMED" &&
      sameUuid(data.device_id, device) && sameUuid(data.request_id, request) &&
      uuid(data.attempt_id) && integer(data.fence_version, 1, 1e9) &&
      hash(data.reservation_sha256) &&
      (!p || (sameUuid(data.attempt_id, p.attempt_id) &&
        data.fence_version === p.fence_version &&
        data.reservation_sha256 === p.reservation_sha256)) &&
      dispatchDeadline(data.armed_at, data.expires_at, now) &&
      data.replay === false && data.carrier_proof === false;
  }
  if (action === "callback") {
    return keys(data, [
      "callback_id",
      "recorded_at",
      "replay",
      "carrier_proof",
      "state",
      "sent_observations",
      "delivery_observations",
      "conflicting_observations",
    ]) && uuid(data.callback_id) &&
      (!p || sameUuid(data.callback_id, p.callback_id)) &&
      utc(data.recorded_at) && typeof data.replay === "boolean" &&
      ["send_started", "observed_sent", "uncertain"].includes(
        data.state as string,
      ) &&
      dispatchCounts(data, p?.segment_count);
  }
  if (action === "attempt_status") {
    return keys(data, [
      "attempt_id",
      "fence_version",
      "state",
      "armed_at",
      "sent_observations",
      "delivery_observations",
      "conflicting_observations",
      "terminal_archive_ack",
      "carrier_proof",
      "segment_count",
    ]) && uuid(data.attempt_id) && integer(data.fence_version, 1, 1e9) &&
      (!p || (sameUuid(data.attempt_id, p.attempt_id) &&
        data.fence_version === p.fence_version)) &&
      ["granted", "send_started", "observed_sent", "uncertain"].includes(
        data.state as string,
      ) &&
      (data.armed_at === null || utc(data.armed_at)) &&
      data.terminal_archive_ack === false &&
      integer(data.segment_count, 1, 10) &&
      dispatchCounts(data, data.segment_count);
  }
  if (
    !keys(data, [
      "target_request_id",
      "outcome",
      "recorded_action",
      "recorded_result",
    ]) || !uuid(data.target_request_id) ||
    (p && !sameUuid(data.target_request_id, p.target_request_id))
  ) return false;
  if (data.outcome === "unknown") {
    return data.recorded_action === null && data.recorded_result === null;
  }
  if (
    data.outcome !== "recorded" || typeof data.recorded_action !== "string" ||
    !["dispatch_grant", "arm_dispatch", "callback", "attempt_status"].includes(
      data.recorded_action,
    )
  ) return false;
  // A lookup proves that the original request was recorded. It cannot recover
  // a body or replay a carrier permit, even while its original lease is live.
  if (
    data.recorded_action === "dispatch_grant" ||
    data.recorded_action === "arm_dispatch"
  ) {
    return dispatchRefusal(
      data.recorded_result,
      device,
      data.target_request_id,
    ) &&
      data.recorded_result.code === "ORIGINAL_REQUEST_RECORDED" &&
      data.recorded_result.replay === true;
  }
  return await validDispatchResult(
    data.recorded_action as V2Action,
    data.recorded_result,
    device,
    data.target_request_id,
    now,
  );
}
function response(status: number, data: Json): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}
export function createGatewayHandler(
  deps: GatewayDependencies,
): (request: Request) => Promise<Response> {
  const now = deps.now ?? Date.now;
  const timeout = Math.min(10000, Math.max(1, deps.timeoutMs ?? 5000));
  async function rpc(name: string, args: Json): Promise<unknown> {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const operation = deps.rpc(name, args, controller.signal);
      const result = await Promise.race([
        operation,
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            controller.abort();
            reject(new Refusal(504, "GATEWAY_OUTCOME_UNKNOWN"));
          }, timeout);
        }),
      ]);
      if (result.error) {
        if (result.error.code === "42501") {
          throw new Refusal(403, "GATEWAY_AUTHORITY_REFUSED");
        }
        if (["22023", "23505", "55000"].includes(result.error.code ?? "")) {
          throw new Refusal(409, "GATEWAY_REQUEST_REFUSED");
        }
        throw new Refusal(503, "GATEWAY_OUTCOME_UNKNOWN");
      }
      if (JSON.stringify(result.data).length > 8192) {
        throw new Refusal(502, "GATEWAY_OUTCOME_UNKNOWN");
      }
      return result.data;
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }
  return async (request) => {
    try {
      if (request.method !== "POST") {
        throw new Refusal(405, "GATEWAY_POST_REQUIRED");
      }
      const raw = await body(request, timeout);
      let text: string;
      try {
        text = new TextDecoder("utf-8", { fatal: true }).decode(raw);
      } catch {
        throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
      }
      const envelope = parseStrict(text);
      require(
        keys(envelope, [
          "contract_version",
          "action",
          "device_id",
          "request_id",
          "issued_at",
          "payload",
        ]),
      );
      require(
        typeof envelope.action === "string" &&
          ((envelope.contract_version === 1 &&
            Object.hasOwn(V1_RPC, envelope.action)) ||
            (envelope.contract_version === 2 &&
              Object.hasOwn(V2_RPC, envelope.action))),
      );
      require(
        uuid(envelope.device_id) && uuid(envelope.request_id) &&
          utc(envelope.issued_at),
      );
      require(Math.abs(now() - Date.parse(envelope.issued_at)) <= 120000);
      const action = envelope.action as Action;
      payload(action, envelope.payload);
      if (action === "callback") {
        require(envelope.payload.callback_id !== envelope.request_id);
        if (envelope.contract_version === 2) {
          require(!sameUuid(envelope.payload.callback_id, envelope.request_id));
        }
      }
      if (envelope.contract_version === 2 && action === "arm_dispatch") {
        for (const callback of envelope.payload.callbacks as Json[]) {
          for (
            const id of [
              callback.sent_callback_id,
              callback.delivery_callback_id,
            ]
          ) {
            require(
              !sameUuid(id, envelope.request_id) &&
                !sameUuid(id, envelope.payload.attempt_id),
            );
          }
        }
      }
      const keyId = request.headers.get("X-Collect-Gateway-Key-Id");
      require(hash(keyId));
      const signature = derToP1363(
        base64(request.headers.get("X-Collect-Gateway-Signature"), 100),
      );
      const key = await rpc("gateway_device_key_v1", {
        p_device_id: envelope.device_id,
      });
      if (
        !keys(key, [
          "device_id",
          "state",
          "public_key_spki_base64",
          "key_sha256",
          "installation_id",
          "signing_certificate_sha256",
        ]) || (envelope.contract_version === 2
          ? !sameUuid(key.device_id, envelope.device_id)
          : key.device_id !== envelope.device_id) ||
        !["pending", "active", "revoked"].includes(key.state as string) ||
        !uuid(key.installation_id) || !hash(key.key_sha256) ||
        !hash(key.signing_certificate_sha256)
      ) {
        throw new Refusal(401, "GATEWAY_KEY_REFUSED");
      }
      const spki = base64(key.public_key_spki_base64, 124);
      if (
        spki.length !== 91 || await digest(spki) !== key.key_sha256 ||
        key.key_sha256 !== keyId
      ) {
        throw new Refusal(401, "GATEWAY_KEY_REFUSED");
      }
      let verified = false;
      try {
        const imported = await crypto.subtle.importKey(
          "spki",
          new Uint8Array(spki),
          { name: "ECDSA", namedCurve: "P-256" },
          false,
          ["verify"],
        );
        verified = await crypto.subtle.verify(
          { name: "ECDSA", hash: "SHA-256" },
          imported,
          new Uint8Array(signature),
          new Uint8Array(raw),
        );
      } catch {
        verified = false;
      }
      if (!verified) {
        throw new Refusal(401, "GATEWAY_SIGNATURE_REFUSED");
      }
      if (
        key.state === "revoked" && action !== "callback" &&
        action !== "reconcile" &&
        !(envelope.contract_version === 2 && action === "attempt_status")
      ) {
        throw new Refusal(403, "GATEWAY_DEVICE_REVOKED");
      }
      const name = envelope.contract_version === 1
        ? V1_RPC[action as V1Action]
        : V2_RPC[action as V2Action];
      const result = await rpc(name, {
        p_device_id: envelope.device_id,
        p_request_id: envelope.request_id,
        p_request_sha256: await digest(raw),
        p_payload: envelope.payload,
      });
      if (
        !(envelope.contract_version === 1
          ? validResult(
            action as V1Action,
            result,
            envelope.device_id,
            envelope.request_id,
            envelope.payload,
          )
          : await validDispatchResult(
            action as V2Action,
            result,
            envelope.device_id,
            envelope.request_id,
            now(),
            envelope.payload,
          ))
      ) {
        throw new Refusal(502, "GATEWAY_OUTCOME_UNKNOWN");
      }
      return response(200, {
        contract_version: envelope.contract_version,
        action,
        device_id: envelope.device_id,
        request_id: envelope.request_id,
        result,
      });
    } catch (error) {
      if (error instanceof Refusal) {
        return response(error.status, { ok: false, code: error.code });
      }
      return response(503, { ok: false, code: "GATEWAY_OUTCOME_UNKNOWN" });
    }
  };
}
