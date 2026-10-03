type ObjectValue = Record<string, unknown>;
export type WorkerDependencies = {
  secret: () => string;
  rpc: (name: string, args: ObjectValue, signal: AbortSignal) => Promise<{
    data: unknown;
    error: { code?: string } | null;
  }>;
  now?: () => number;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const fields = (v: unknown, keys: string): v is ObjectValue =>
  v !== null && typeof v === "object" && !Array.isArray(v) &&
  Object.keys(v).sort().join(",") === keys.split(",").sort().join(",");
const integer = (v: unknown, min = 0, max = Number.MAX_SAFE_INTEGER) =>
  Number.isSafeInteger(v) && Number(v) >= min && Number(v) <= max;
const timestamp = (v: unknown) =>
  typeof v === "string" && /^\d{4}-\d\d-\d\dT.*Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
function assert(v: unknown): asserts v {
  if (!v) throw new Error("worker_contract_invalid");
}
function scanReceipt(v: unknown, id: string) {
  assert(
    fields(
      v,
      "contract_version,request_id,checked_at,expires_at,status,seeded,processed,refused,observations_added,activated,cleared,unchanged,pending,scan_epoch,scan_phase,source_scan_complete,financial_action,send_action",
    ),
  );
  assert(
    v.contract_version === 1 && v.request_id === id &&
      timestamp(v.checked_at) && timestamp(v.expires_at) &&
      ["processed", "busy"].includes(String(v.status)) &&
      ["receipt_event", "receipt_backlog"].includes(String(v.scan_phase)) &&
      v.source_scan_complete === false && v.financial_action === false &&
      v.send_action === false && integer(v.scan_epoch, 1, 1000000000),
  );
  for (const k of ["seeded", "processed", "refused", "unchanged"]) {
    assert(integer(v[k], 0, 25));
  }
  for (const k of ["observations_added", "activated", "cleared", "pending"]) {
    assert(integer(v[k]));
  }
  assert(
    Number(v.refused) <= Number(v.processed) &&
      Number(v.unchanged) <= Number(v.processed),
  );
  if (v.status === "busy") {
    for (
      const k of [
        "seeded",
        "processed",
        "refused",
        "observations_added",
        "activated",
        "cleared",
        "unchanged",
      ]
    ) {
      assert(v[k] === 0);
    }
  }
}
export function validateWorkerReceipt(v: unknown, id: string): ObjectValue {
  assert(
    fields(
      v,
      "contract_version,request_id,configuration_revision,recorded_at,expires_at,status,scan,escalation,financial_action,send_action,external_send",
    ),
  );
  assert(
    v.contract_version === 1 && v.request_id === id &&
      integer(v.configuration_revision, 1, 1000000000) &&
      timestamp(v.recorded_at) && timestamp(v.expires_at) &&
      Date.parse(String(v.expires_at)) > Date.parse(String(v.recorded_at)) &&
      ["completed", "busy"].includes(String(v.status)) &&
      v.financial_action === false && v.send_action === false &&
      v.external_send === false,
  );
  scanReceipt(v.scan, id);
  const scan = v.scan as ObjectValue;
  assert(
    scan.expires_at === v.expires_at &&
      ((v.status === "busy") === (scan.status === "busy")),
  );
  assert(
    fields(
      v.escalation,
      "contract_version,channel,delivered,obsolete,recipient_unavailable,external_send",
    ),
  );
  const e = v.escalation;
  assert(
    e.contract_version === 1 && e.channel === "admin_inbox" &&
      e.external_send === false,
  );
  for (const k of ["delivered", "obsolete", "recipient_unavailable"]) {
    assert(integer(e[k], 0, 20));
  }
  assert(
    Number(e.delivered) + Number(e.obsolete) +
        Number(e.recipient_unavailable) <= 20,
  );
  if (v.status === "busy") {
    assert(
      e.delivered === 0 && e.obsolete === 0 && e.recipient_unavailable === 0,
    );
  }
  return v;
}
export function validateWorkerLookup(
  v: unknown,
  id: string,
  now: number,
): ObjectValue {
  assert(
    fields(
      v,
      "contract_version,request_id,checked_at,sample_valid_until,status,expires_at,receipt",
    ),
  );
  assert(
    v.contract_version === 1 && v.request_id === id &&
      timestamp(v.checked_at) && timestamp(v.sample_valid_until) &&
      Date.parse(String(v.checked_at)) <= now + 5000 &&
      Date.parse(String(v.checked_at)) >= now - 60000 &&
      Date.parse(String(v.sample_valid_until)) > now &&
      Date.parse(String(v.sample_valid_until)) -
            Date.parse(String(v.checked_at)) === 60000 &&
      ["recorded", "not_recorded", "in_progress"].includes(String(v.status)) &&
      (v.expires_at === null || timestamp(v.expires_at)),
  );
  if (v.status === "recorded") {
    const r = validateWorkerReceipt(v.receipt, id);
    assert(r.expires_at === v.expires_at);
  } else assert(v.receipt === null);
  return v;
}
async function sameSecret(actual: string, expected: string) {
  const digest = async (s: string) =>
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
    );
  const [a, b] = await Promise.all([digest(actual), digest(expected)]);
  let different = 0;
  for (let i = 0; i < a.length; i++) different |= a[i] ^ b[i];
  return different === 0;
}
async function boundedBody(req: Request): Promise<unknown> {
  if (!req.body) throw new Error("worker_request_invalid");
  const reader = req.body.getReader();
  let length = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 2048) throw new Error("worker_request_invalid");
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const all = new Uint8Array(length);
  let offset = 0;
  for (const c of chunks) {
    all.set(c, offset);
    offset += c.length;
  }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(all));
}
const response = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
export function createExceptionWorkerHandler(d: WorkerDependencies) {
  const clock = d.now ?? Date.now;
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return response({ error: "METHOD_NOT_ALLOWED" }, 405);
    }
    const secret = d.secret();
    if (secret.length < 32 || secret.length > 256 || /[\r\n]/.test(secret)) {
      return response({ error: "WORKER_UNCONFIGURED" }, 503);
    }
    if (
      !(await sameSecret(
        req.headers.get("x-collect-receipt-worker") ?? "",
        secret,
      ))
    ) {
      return response({ error: "WORKER_AUTH_REQUIRED" }, 401);
    }
    let body: ObjectValue;
    try {
      const v = await boundedBody(req);
      assert(
        fields(v, "contract_version,action,request_id") ||
          fields(
            v,
            "contract_version,action,request_id,configuration_revision,expires_at",
          ),
      );
      assert(
        v.contract_version === 1 && typeof v.request_id === "string" &&
          UUID.test(v.request_id),
      );
      if (v.action === "execute") {
        assert(
          fields(
            v,
            "contract_version,action,request_id,configuration_revision,expires_at",
          ) &&
            integer(v.configuration_revision, 1, 1000000000) &&
            timestamp(v.expires_at),
        );
        const remaining = Date.parse(String(v.expires_at)) - clock();
        assert(remaining > 0 && remaining <= 120000);
      } else {assert(
          v.action === "reconcile" &&
            fields(v, "contract_version,action,request_id"),
        );}
      body = v;
    } catch {
      return response({ error: "WORKER_REQUEST_INVALID" }, 400);
    }
    const id = String(body.request_id);
    const lookup = async () => {
      const r = await d.rpc("get_receipt_exception_worker_request_v1", {
        p_request_id: id,
      }, AbortSignal.timeout(3000));
      if (r.error) throw new Error("worker_lookup_unavailable");
      return validateWorkerLookup(r.data, id, clock());
    };
    if (body.action === "reconcile") {
      try {
        return response(await lookup());
      } catch {
        return response(
          { error: "WORKER_LOOKUP_UNAVAILABLE", request_id: id },
          503,
        );
      }
    }
    try {
      const r = await d.rpc("execute_receipt_exception_worker_v1", {
        p_request_id: id,
        p_configuration_revision: body.configuration_revision,
        p_expires_at: body.expires_at,
      }, AbortSignal.timeout(8000));
      if (r.error) {
        if (r.error.code === "42501") {
          return response(
            { error: "WORKER_AUTHORITY_REFUSED", request_id: id },
            403,
          );
        }
        if (r.error.code === "22023") {
          return response(
            { error: "WORKER_ORIGINAL_CONFLICT", request_id: id },
            409,
          );
        }
        throw new Error("worker_outcome_unknown");
      }
      assert(
        fields(r.data, "contract_version,request_id,status,receipt") &&
          r.data.contract_version === 1 && r.data.request_id === id,
      );
      if (r.data.status === "in_progress") {
        assert(r.data.receipt === null);
        return response(r.data, 202);
      }
      assert(r.data.status === "recorded");
      const receipt = validateWorkerReceipt(r.data.receipt, id);
      assert(
        receipt.configuration_revision === body.configuration_revision &&
          receipt.expires_at === body.expires_at,
      );
      return response(r.data);
    } catch {
      // A lost response never causes this handler to rerun the mutation.
      // Return only a fresh original lookup, or retain explicit uncertainty.
      try {
        const found = await lookup();
        if (found.status === "recorded") {
          const original = found.receipt as ObjectValue;
          if (
            original.configuration_revision !== body.configuration_revision ||
            original.expires_at !== body.expires_at
          ) {
            return response({
              error: "WORKER_ORIGINAL_CONFLICT",
              request_id: id,
            }, 409);
          }
        }
        return response(found, found.status === "recorded" ? 200 : 202);
      } catch {
        return response(
          { error: "WORKER_OUTCOME_UNKNOWN", request_id: id },
          202,
        );
      }
    }
  };
}
