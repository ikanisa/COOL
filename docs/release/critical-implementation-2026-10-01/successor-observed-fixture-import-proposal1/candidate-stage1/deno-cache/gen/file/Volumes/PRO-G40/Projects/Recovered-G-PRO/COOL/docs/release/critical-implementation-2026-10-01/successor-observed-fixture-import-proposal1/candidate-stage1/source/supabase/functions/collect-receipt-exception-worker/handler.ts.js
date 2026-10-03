const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const fields = (v, keys)=>v !== null && typeof v === "object" && !Array.isArray(v) && Object.keys(v).sort().join(",") === keys.split(",").sort().join(",");
const integer = (v, min = 0, max = Number.MAX_SAFE_INTEGER)=>Number.isSafeInteger(v) && Number(v) >= min && Number(v) <= max;
const timestamp = (v)=>typeof v === "string" && /^\d{4}-\d\d-\d\dT.*Z$/.test(v) && Number.isFinite(Date.parse(v));
function assert(v) {
  if (!v) throw new Error("worker_contract_invalid");
}
function scanReceipt(v, id) {
  assert(fields(v, "contract_version,request_id,checked_at,expires_at,status,seeded,processed,refused,observations_added,activated,cleared,unchanged,pending,scan_epoch,scan_phase,source_scan_complete,financial_action,send_action"));
  assert(v.contract_version === 1 && v.request_id === id && timestamp(v.checked_at) && timestamp(v.expires_at) && [
    "processed",
    "busy"
  ].includes(String(v.status)) && [
    "receipt_event",
    "receipt_backlog"
  ].includes(String(v.scan_phase)) && v.source_scan_complete === false && v.financial_action === false && v.send_action === false && integer(v.scan_epoch, 1, 1000000000));
  for (const k of [
    "seeded",
    "processed",
    "refused",
    "unchanged"
  ]){
    assert(integer(v[k], 0, 25));
  }
  for (const k of [
    "observations_added",
    "activated",
    "cleared",
    "pending"
  ]){
    assert(integer(v[k]));
  }
  assert(Number(v.refused) <= Number(v.processed) && Number(v.unchanged) <= Number(v.processed));
  if (v.status === "busy") {
    for (const k of [
      "seeded",
      "processed",
      "refused",
      "observations_added",
      "activated",
      "cleared",
      "unchanged"
    ]){
      assert(v[k] === 0);
    }
  }
}
export function validateWorkerReceipt(v, id) {
  assert(fields(v, "contract_version,request_id,configuration_revision,recorded_at,expires_at,status,scan,escalation,financial_action,send_action,external_send"));
  assert(v.contract_version === 1 && v.request_id === id && integer(v.configuration_revision, 1, 1000000000) && timestamp(v.recorded_at) && timestamp(v.expires_at) && Date.parse(String(v.expires_at)) > Date.parse(String(v.recorded_at)) && [
    "completed",
    "busy"
  ].includes(String(v.status)) && v.financial_action === false && v.send_action === false && v.external_send === false);
  scanReceipt(v.scan, id);
  const scan = v.scan;
  assert(scan.expires_at === v.expires_at && v.status === "busy" === (scan.status === "busy"));
  assert(fields(v.escalation, "contract_version,channel,delivered,obsolete,recipient_unavailable,external_send"));
  const e = v.escalation;
  assert(e.contract_version === 1 && e.channel === "admin_inbox" && e.external_send === false);
  for (const k of [
    "delivered",
    "obsolete",
    "recipient_unavailable"
  ]){
    assert(integer(e[k], 0, 20));
  }
  assert(Number(e.delivered) + Number(e.obsolete) + Number(e.recipient_unavailable) <= 20);
  if (v.status === "busy") {
    assert(e.delivered === 0 && e.obsolete === 0 && e.recipient_unavailable === 0);
  }
  return v;
}
export function validateWorkerLookup(v, id, now) {
  assert(fields(v, "contract_version,request_id,checked_at,sample_valid_until,status,expires_at,receipt"));
  assert(v.contract_version === 1 && v.request_id === id && timestamp(v.checked_at) && timestamp(v.sample_valid_until) && Date.parse(String(v.checked_at)) <= now + 5000 && Date.parse(String(v.checked_at)) >= now - 60000 && Date.parse(String(v.sample_valid_until)) > now && Date.parse(String(v.sample_valid_until)) - Date.parse(String(v.checked_at)) === 60000 && [
    "recorded",
    "not_recorded",
    "in_progress"
  ].includes(String(v.status)) && (v.expires_at === null || timestamp(v.expires_at)));
  if (v.status === "recorded") {
    const r = validateWorkerReceipt(v.receipt, id);
    assert(r.expires_at === v.expires_at);
  } else assert(v.receipt === null);
  return v;
}
async function sameSecret(actual, expected) {
  const digest = async (s)=>new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  const [a, b] = await Promise.all([
    digest(actual),
    digest(expected)
  ]);
  let different = 0;
  for(let i = 0; i < a.length; i++)different |= a[i] ^ b[i];
  return different === 0;
}
async function boundedBody(req) {
  if (!req.body) throw new Error("worker_request_invalid");
  const reader = req.body.getReader();
  let length = 0;
  const chunks = [];
  try {
    while(true){
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 2048) throw new Error("worker_request_invalid");
      chunks.push(value);
    }
  } finally{
    await reader.cancel();
  }
  const all = new Uint8Array(length);
  let offset = 0;
  for (const c of chunks){
    all.set(c, offset);
    offset += c.length;
  }
  return JSON.parse(new TextDecoder("utf-8", {
    fatal: true
  }).decode(all));
}
const response = (data, status = 200)=>new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store"
    }
  });
export function createExceptionWorkerHandler(d) {
  const clock = d.now ?? Date.now;
  return async (req)=>{
    if (req.method !== "POST") {
      return response({
        error: "METHOD_NOT_ALLOWED"
      }, 405);
    }
    const secret = d.secret();
    if (secret.length < 32 || secret.length > 256 || /[\r\n]/.test(secret)) {
      return response({
        error: "WORKER_UNCONFIGURED"
      }, 503);
    }
    if (!await sameSecret(req.headers.get("x-collect-receipt-worker") ?? "", secret)) {
      return response({
        error: "WORKER_AUTH_REQUIRED"
      }, 401);
    }
    let body;
    try {
      const v = await boundedBody(req);
      assert(fields(v, "contract_version,action,request_id") || fields(v, "contract_version,action,request_id,configuration_revision,expires_at"));
      assert(v.contract_version === 1 && typeof v.request_id === "string" && UUID.test(v.request_id));
      if (v.action === "execute") {
        assert(fields(v, "contract_version,action,request_id,configuration_revision,expires_at") && integer(v.configuration_revision, 1, 1000000000) && timestamp(v.expires_at));
        const remaining = Date.parse(String(v.expires_at)) - clock();
        assert(remaining > 0 && remaining <= 120000);
      } else {
        assert(v.action === "reconcile" && fields(v, "contract_version,action,request_id"));
      }
      body = v;
    } catch  {
      return response({
        error: "WORKER_REQUEST_INVALID"
      }, 400);
    }
    const id = String(body.request_id);
    const lookup = async ()=>{
      const r = await d.rpc("get_receipt_exception_worker_request_v1", {
        p_request_id: id
      }, AbortSignal.timeout(3000));
      if (r.error) throw new Error("worker_lookup_unavailable");
      return validateWorkerLookup(r.data, id, clock());
    };
    if (body.action === "reconcile") {
      try {
        return response(await lookup());
      } catch  {
        return response({
          error: "WORKER_LOOKUP_UNAVAILABLE",
          request_id: id
        }, 503);
      }
    }
    try {
      const r = await d.rpc("execute_receipt_exception_worker_v1", {
        p_request_id: id,
        p_configuration_revision: body.configuration_revision,
        p_expires_at: body.expires_at
      }, AbortSignal.timeout(8000));
      if (r.error) {
        if (r.error.code === "42501") {
          return response({
            error: "WORKER_AUTHORITY_REFUSED",
            request_id: id
          }, 403);
        }
        if (r.error.code === "22023") {
          return response({
            error: "WORKER_ORIGINAL_CONFLICT",
            request_id: id
          }, 409);
        }
        throw new Error("worker_outcome_unknown");
      }
      assert(fields(r.data, "contract_version,request_id,status,receipt") && r.data.contract_version === 1 && r.data.request_id === id);
      if (r.data.status === "in_progress") {
        assert(r.data.receipt === null);
        return response(r.data, 202);
      }
      assert(r.data.status === "recorded");
      const receipt = validateWorkerReceipt(r.data.receipt, id);
      assert(receipt.configuration_revision === body.configuration_revision && receipt.expires_at === body.expires_at);
      return response(r.data);
    } catch  {
      // A lost response never causes this handler to rerun the mutation.
      // Return only a fresh original lookup, or retain explicit uncertainty.
      try {
        const found = await lookup();
        if (found.status === "recorded") {
          const original = found.receipt;
          if (original.configuration_revision !== body.configuration_revision || original.expires_at !== body.expires_at) {
            return response({
              error: "WORKER_ORIGINAL_CONFLICT",
              request_id: id
            }, 409);
          }
        }
        return response(found, found.status === "recorded" ? 200 : 202);
      } catch  {
        return response({
          error: "WORKER_OUTCOME_UNKNOWN",
          request_id: id
        }, 202);
      }
    }
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1leGNlcHRpb24td29ya2VyL2hhbmRsZXIudHMiXSwic291cmNlc0NvbnRlbnQiOlsidHlwZSBPYmplY3RWYWx1ZSA9IFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xuZXhwb3J0IHR5cGUgV29ya2VyRGVwZW5kZW5jaWVzID0ge1xuICBzZWNyZXQ6ICgpID0+IHN0cmluZztcbiAgcnBjOiAobmFtZTogc3RyaW5nLCBhcmdzOiBPYmplY3RWYWx1ZSwgc2lnbmFsOiBBYm9ydFNpZ25hbCkgPT4gUHJvbWlzZTx7XG4gICAgZGF0YTogdW5rbm93bjtcbiAgICBlcnJvcjogeyBjb2RlPzogc3RyaW5nIH0gfCBudWxsO1xuICB9PjtcbiAgbm93PzogKCkgPT4gbnVtYmVyO1xufTtcbmNvbnN0IFVVSUQgPSAvXlswLTlhLWZdezh9LVswLTlhLWZdezR9LVswLTlhLWZdezR9LVswLTlhLWZdezR9LVswLTlhLWZdezEyfSQvO1xuY29uc3QgZmllbGRzID0gKHY6IHVua25vd24sIGtleXM6IHN0cmluZyk6IHYgaXMgT2JqZWN0VmFsdWUgPT5cbiAgdiAhPT0gbnVsbCAmJiB0eXBlb2YgdiA9PT0gXCJvYmplY3RcIiAmJiAhQXJyYXkuaXNBcnJheSh2KSAmJlxuICBPYmplY3Qua2V5cyh2KS5zb3J0KCkuam9pbihcIixcIikgPT09IGtleXMuc3BsaXQoXCIsXCIpLnNvcnQoKS5qb2luKFwiLFwiKTtcbmNvbnN0IGludGVnZXIgPSAodjogdW5rbm93biwgbWluID0gMCwgbWF4ID0gTnVtYmVyLk1BWF9TQUZFX0lOVEVHRVIpID0+XG4gIE51bWJlci5pc1NhZmVJbnRlZ2VyKHYpICYmIE51bWJlcih2KSA+PSBtaW4gJiYgTnVtYmVyKHYpIDw9IG1heDtcbmNvbnN0IHRpbWVzdGFtcCA9ICh2OiB1bmtub3duKSA9PlxuICB0eXBlb2YgdiA9PT0gXCJzdHJpbmdcIiAmJiAvXlxcZHs0fS1cXGRcXGQtXFxkXFxkVC4qWiQvLnRlc3QodikgJiZcbiAgTnVtYmVyLmlzRmluaXRlKERhdGUucGFyc2UodikpO1xuZnVuY3Rpb24gYXNzZXJ0KHY6IHVua25vd24pOiBhc3NlcnRzIHYge1xuICBpZiAoIXYpIHRocm93IG5ldyBFcnJvcihcIndvcmtlcl9jb250cmFjdF9pbnZhbGlkXCIpO1xufVxuZnVuY3Rpb24gc2NhblJlY2VpcHQodjogdW5rbm93biwgaWQ6IHN0cmluZykge1xuICBhc3NlcnQoXG4gICAgZmllbGRzKFxuICAgICAgdixcbiAgICAgIFwiY29udHJhY3RfdmVyc2lvbixyZXF1ZXN0X2lkLGNoZWNrZWRfYXQsZXhwaXJlc19hdCxzdGF0dXMsc2VlZGVkLHByb2Nlc3NlZCxyZWZ1c2VkLG9ic2VydmF0aW9uc19hZGRlZCxhY3RpdmF0ZWQsY2xlYXJlZCx1bmNoYW5nZWQscGVuZGluZyxzY2FuX2Vwb2NoLHNjYW5fcGhhc2Usc291cmNlX3NjYW5fY29tcGxldGUsZmluYW5jaWFsX2FjdGlvbixzZW5kX2FjdGlvblwiLFxuICAgICksXG4gICk7XG4gIGFzc2VydChcbiAgICB2LmNvbnRyYWN0X3ZlcnNpb24gPT09IDEgJiYgdi5yZXF1ZXN0X2lkID09PSBpZCAmJlxuICAgICAgdGltZXN0YW1wKHYuY2hlY2tlZF9hdCkgJiYgdGltZXN0YW1wKHYuZXhwaXJlc19hdCkgJiZcbiAgICAgIFtcInByb2Nlc3NlZFwiLCBcImJ1c3lcIl0uaW5jbHVkZXMoU3RyaW5nKHYuc3RhdHVzKSkgJiZcbiAgICAgIFtcInJlY2VpcHRfZXZlbnRcIiwgXCJyZWNlaXB0X2JhY2tsb2dcIl0uaW5jbHVkZXMoU3RyaW5nKHYuc2Nhbl9waGFzZSkpICYmXG4gICAgICB2LnNvdXJjZV9zY2FuX2NvbXBsZXRlID09PSBmYWxzZSAmJiB2LmZpbmFuY2lhbF9hY3Rpb24gPT09IGZhbHNlICYmXG4gICAgICB2LnNlbmRfYWN0aW9uID09PSBmYWxzZSAmJiBpbnRlZ2VyKHYuc2Nhbl9lcG9jaCwgMSwgMTAwMDAwMDAwMCksXG4gICk7XG4gIGZvciAoY29uc3QgayBvZiBbXCJzZWVkZWRcIiwgXCJwcm9jZXNzZWRcIiwgXCJyZWZ1c2VkXCIsIFwidW5jaGFuZ2VkXCJdKSB7XG4gICAgYXNzZXJ0KGludGVnZXIodltrXSwgMCwgMjUpKTtcbiAgfVxuICBmb3IgKGNvbnN0IGsgb2YgW1wib2JzZXJ2YXRpb25zX2FkZGVkXCIsIFwiYWN0aXZhdGVkXCIsIFwiY2xlYXJlZFwiLCBcInBlbmRpbmdcIl0pIHtcbiAgICBhc3NlcnQoaW50ZWdlcih2W2tdKSk7XG4gIH1cbiAgYXNzZXJ0KFxuICAgIE51bWJlcih2LnJlZnVzZWQpIDw9IE51bWJlcih2LnByb2Nlc3NlZCkgJiZcbiAgICAgIE51bWJlcih2LnVuY2hhbmdlZCkgPD0gTnVtYmVyKHYucHJvY2Vzc2VkKSxcbiAgKTtcbiAgaWYgKHYuc3RhdHVzID09PSBcImJ1c3lcIikge1xuICAgIGZvciAoXG4gICAgICBjb25zdCBrIG9mIFtcbiAgICAgICAgXCJzZWVkZWRcIixcbiAgICAgICAgXCJwcm9jZXNzZWRcIixcbiAgICAgICAgXCJyZWZ1c2VkXCIsXG4gICAgICAgIFwib2JzZXJ2YXRpb25zX2FkZGVkXCIsXG4gICAgICAgIFwiYWN0aXZhdGVkXCIsXG4gICAgICAgIFwiY2xlYXJlZFwiLFxuICAgICAgICBcInVuY2hhbmdlZFwiLFxuICAgICAgXVxuICAgICkge1xuICAgICAgYXNzZXJ0KHZba10gPT09IDApO1xuICAgIH1cbiAgfVxufVxuZXhwb3J0IGZ1bmN0aW9uIHZhbGlkYXRlV29ya2VyUmVjZWlwdCh2OiB1bmtub3duLCBpZDogc3RyaW5nKTogT2JqZWN0VmFsdWUge1xuICBhc3NlcnQoXG4gICAgZmllbGRzKFxuICAgICAgdixcbiAgICAgIFwiY29udHJhY3RfdmVyc2lvbixyZXF1ZXN0X2lkLGNvbmZpZ3VyYXRpb25fcmV2aXNpb24scmVjb3JkZWRfYXQsZXhwaXJlc19hdCxzdGF0dXMsc2Nhbixlc2NhbGF0aW9uLGZpbmFuY2lhbF9hY3Rpb24sc2VuZF9hY3Rpb24sZXh0ZXJuYWxfc2VuZFwiLFxuICAgICksXG4gICk7XG4gIGFzc2VydChcbiAgICB2LmNvbnRyYWN0X3ZlcnNpb24gPT09IDEgJiYgdi5yZXF1ZXN0X2lkID09PSBpZCAmJlxuICAgICAgaW50ZWdlcih2LmNvbmZpZ3VyYXRpb25fcmV2aXNpb24sIDEsIDEwMDAwMDAwMDApICYmXG4gICAgICB0aW1lc3RhbXAodi5yZWNvcmRlZF9hdCkgJiYgdGltZXN0YW1wKHYuZXhwaXJlc19hdCkgJiZcbiAgICAgIERhdGUucGFyc2UoU3RyaW5nKHYuZXhwaXJlc19hdCkpID4gRGF0ZS5wYXJzZShTdHJpbmcodi5yZWNvcmRlZF9hdCkpICYmXG4gICAgICBbXCJjb21wbGV0ZWRcIiwgXCJidXN5XCJdLmluY2x1ZGVzKFN0cmluZyh2LnN0YXR1cykpICYmXG4gICAgICB2LmZpbmFuY2lhbF9hY3Rpb24gPT09IGZhbHNlICYmIHYuc2VuZF9hY3Rpb24gPT09IGZhbHNlICYmXG4gICAgICB2LmV4dGVybmFsX3NlbmQgPT09IGZhbHNlLFxuICApO1xuICBzY2FuUmVjZWlwdCh2LnNjYW4sIGlkKTtcbiAgY29uc3Qgc2NhbiA9IHYuc2NhbiBhcyBPYmplY3RWYWx1ZTtcbiAgYXNzZXJ0KFxuICAgIHNjYW4uZXhwaXJlc19hdCA9PT0gdi5leHBpcmVzX2F0ICYmXG4gICAgICAoKHYuc3RhdHVzID09PSBcImJ1c3lcIikgPT09IChzY2FuLnN0YXR1cyA9PT0gXCJidXN5XCIpKSxcbiAgKTtcbiAgYXNzZXJ0KFxuICAgIGZpZWxkcyhcbiAgICAgIHYuZXNjYWxhdGlvbixcbiAgICAgIFwiY29udHJhY3RfdmVyc2lvbixjaGFubmVsLGRlbGl2ZXJlZCxvYnNvbGV0ZSxyZWNpcGllbnRfdW5hdmFpbGFibGUsZXh0ZXJuYWxfc2VuZFwiLFxuICAgICksXG4gICk7XG4gIGNvbnN0IGUgPSB2LmVzY2FsYXRpb247XG4gIGFzc2VydChcbiAgICBlLmNvbnRyYWN0X3ZlcnNpb24gPT09IDEgJiYgZS5jaGFubmVsID09PSBcImFkbWluX2luYm94XCIgJiZcbiAgICAgIGUuZXh0ZXJuYWxfc2VuZCA9PT0gZmFsc2UsXG4gICk7XG4gIGZvciAoY29uc3QgayBvZiBbXCJkZWxpdmVyZWRcIiwgXCJvYnNvbGV0ZVwiLCBcInJlY2lwaWVudF91bmF2YWlsYWJsZVwiXSkge1xuICAgIGFzc2VydChpbnRlZ2VyKGVba10sIDAsIDIwKSk7XG4gIH1cbiAgYXNzZXJ0KFxuICAgIE51bWJlcihlLmRlbGl2ZXJlZCkgKyBOdW1iZXIoZS5vYnNvbGV0ZSkgK1xuICAgICAgICBOdW1iZXIoZS5yZWNpcGllbnRfdW5hdmFpbGFibGUpIDw9IDIwLFxuICApO1xuICBpZiAodi5zdGF0dXMgPT09IFwiYnVzeVwiKSB7XG4gICAgYXNzZXJ0KFxuICAgICAgZS5kZWxpdmVyZWQgPT09IDAgJiYgZS5vYnNvbGV0ZSA9PT0gMCAmJiBlLnJlY2lwaWVudF91bmF2YWlsYWJsZSA9PT0gMCxcbiAgICApO1xuICB9XG4gIHJldHVybiB2O1xufVxuZXhwb3J0IGZ1bmN0aW9uIHZhbGlkYXRlV29ya2VyTG9va3VwKFxuICB2OiB1bmtub3duLFxuICBpZDogc3RyaW5nLFxuICBub3c6IG51bWJlcixcbik6IE9iamVjdFZhbHVlIHtcbiAgYXNzZXJ0KFxuICAgIGZpZWxkcyhcbiAgICAgIHYsXG4gICAgICBcImNvbnRyYWN0X3ZlcnNpb24scmVxdWVzdF9pZCxjaGVja2VkX2F0LHNhbXBsZV92YWxpZF91bnRpbCxzdGF0dXMsZXhwaXJlc19hdCxyZWNlaXB0XCIsXG4gICAgKSxcbiAgKTtcbiAgYXNzZXJ0KFxuICAgIHYuY29udHJhY3RfdmVyc2lvbiA9PT0gMSAmJiB2LnJlcXVlc3RfaWQgPT09IGlkICYmXG4gICAgICB0aW1lc3RhbXAodi5jaGVja2VkX2F0KSAmJiB0aW1lc3RhbXAodi5zYW1wbGVfdmFsaWRfdW50aWwpICYmXG4gICAgICBEYXRlLnBhcnNlKFN0cmluZyh2LmNoZWNrZWRfYXQpKSA8PSBub3cgKyA1MDAwICYmXG4gICAgICBEYXRlLnBhcnNlKFN0cmluZyh2LmNoZWNrZWRfYXQpKSA+PSBub3cgLSA2MDAwMCAmJlxuICAgICAgRGF0ZS5wYXJzZShTdHJpbmcodi5zYW1wbGVfdmFsaWRfdW50aWwpKSA+IG5vdyAmJlxuICAgICAgRGF0ZS5wYXJzZShTdHJpbmcodi5zYW1wbGVfdmFsaWRfdW50aWwpKSAtXG4gICAgICAgICAgICBEYXRlLnBhcnNlKFN0cmluZyh2LmNoZWNrZWRfYXQpKSA9PT0gNjAwMDAgJiZcbiAgICAgIFtcInJlY29yZGVkXCIsIFwibm90X3JlY29yZGVkXCIsIFwiaW5fcHJvZ3Jlc3NcIl0uaW5jbHVkZXMoU3RyaW5nKHYuc3RhdHVzKSkgJiZcbiAgICAgICh2LmV4cGlyZXNfYXQgPT09IG51bGwgfHwgdGltZXN0YW1wKHYuZXhwaXJlc19hdCkpLFxuICApO1xuICBpZiAodi5zdGF0dXMgPT09IFwicmVjb3JkZWRcIikge1xuICAgIGNvbnN0IHIgPSB2YWxpZGF0ZVdvcmtlclJlY2VpcHQodi5yZWNlaXB0LCBpZCk7XG4gICAgYXNzZXJ0KHIuZXhwaXJlc19hdCA9PT0gdi5leHBpcmVzX2F0KTtcbiAgfSBlbHNlIGFzc2VydCh2LnJlY2VpcHQgPT09IG51bGwpO1xuICByZXR1cm4gdjtcbn1cbmFzeW5jIGZ1bmN0aW9uIHNhbWVTZWNyZXQoYWN0dWFsOiBzdHJpbmcsIGV4cGVjdGVkOiBzdHJpbmcpIHtcbiAgY29uc3QgZGlnZXN0ID0gYXN5bmMgKHM6IHN0cmluZykgPT5cbiAgICBuZXcgVWludDhBcnJheShcbiAgICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuZGlnZXN0KFwiU0hBLTI1NlwiLCBuZXcgVGV4dEVuY29kZXIoKS5lbmNvZGUocykpLFxuICAgICk7XG4gIGNvbnN0IFthLCBiXSA9IGF3YWl0IFByb21pc2UuYWxsKFtkaWdlc3QoYWN0dWFsKSwgZGlnZXN0KGV4cGVjdGVkKV0pO1xuICBsZXQgZGlmZmVyZW50ID0gMDtcbiAgZm9yIChsZXQgaSA9IDA7IGkgPCBhLmxlbmd0aDsgaSsrKSBkaWZmZXJlbnQgfD0gYVtpXSBeIGJbaV07XG4gIHJldHVybiBkaWZmZXJlbnQgPT09IDA7XG59XG5hc3luYyBmdW5jdGlvbiBib3VuZGVkQm9keShyZXE6IFJlcXVlc3QpOiBQcm9taXNlPHVua25vd24+IHtcbiAgaWYgKCFyZXEuYm9keSkgdGhyb3cgbmV3IEVycm9yKFwid29ya2VyX3JlcXVlc3RfaW52YWxpZFwiKTtcbiAgY29uc3QgcmVhZGVyID0gcmVxLmJvZHkuZ2V0UmVhZGVyKCk7XG4gIGxldCBsZW5ndGggPSAwO1xuICBjb25zdCBjaHVua3M6IFVpbnQ4QXJyYXlbXSA9IFtdO1xuICB0cnkge1xuICAgIHdoaWxlICh0cnVlKSB7XG4gICAgICBjb25zdCB7IHZhbHVlLCBkb25lIH0gPSBhd2FpdCByZWFkZXIucmVhZCgpO1xuICAgICAgaWYgKGRvbmUpIGJyZWFrO1xuICAgICAgbGVuZ3RoICs9IHZhbHVlLmxlbmd0aDtcbiAgICAgIGlmIChsZW5ndGggPiAyMDQ4KSB0aHJvdyBuZXcgRXJyb3IoXCJ3b3JrZXJfcmVxdWVzdF9pbnZhbGlkXCIpO1xuICAgICAgY2h1bmtzLnB1c2godmFsdWUpO1xuICAgIH1cbiAgfSBmaW5hbGx5IHtcbiAgICBhd2FpdCByZWFkZXIuY2FuY2VsKCk7XG4gIH1cbiAgY29uc3QgYWxsID0gbmV3IFVpbnQ4QXJyYXkobGVuZ3RoKTtcbiAgbGV0IG9mZnNldCA9IDA7XG4gIGZvciAoY29uc3QgYyBvZiBjaHVua3MpIHtcbiAgICBhbGwuc2V0KGMsIG9mZnNldCk7XG4gICAgb2Zmc2V0ICs9IGMubGVuZ3RoO1xuICB9XG4gIHJldHVybiBKU09OLnBhcnNlKG5ldyBUZXh0RGVjb2RlcihcInV0Zi04XCIsIHsgZmF0YWw6IHRydWUgfSkuZGVjb2RlKGFsbCkpO1xufVxuY29uc3QgcmVzcG9uc2UgPSAoZGF0YTogdW5rbm93biwgc3RhdHVzID0gMjAwKSA9PlxuICBuZXcgUmVzcG9uc2UoSlNPTi5zdHJpbmdpZnkoZGF0YSksIHtcbiAgICBzdGF0dXMsXG4gICAgaGVhZGVyczoge1xuICAgICAgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICBcImNhY2hlLWNvbnRyb2xcIjogXCJuby1zdG9yZVwiLFxuICAgIH0sXG4gIH0pO1xuZXhwb3J0IGZ1bmN0aW9uIGNyZWF0ZUV4Y2VwdGlvbldvcmtlckhhbmRsZXIoZDogV29ya2VyRGVwZW5kZW5jaWVzKSB7XG4gIGNvbnN0IGNsb2NrID0gZC5ub3cgPz8gRGF0ZS5ub3c7XG4gIHJldHVybiBhc3luYyAocmVxOiBSZXF1ZXN0KTogUHJvbWlzZTxSZXNwb25zZT4gPT4ge1xuICAgIGlmIChyZXEubWV0aG9kICE9PSBcIlBPU1RcIikge1xuICAgICAgcmV0dXJuIHJlc3BvbnNlKHsgZXJyb3I6IFwiTUVUSE9EX05PVF9BTExPV0VEXCIgfSwgNDA1KTtcbiAgICB9XG4gICAgY29uc3Qgc2VjcmV0ID0gZC5zZWNyZXQoKTtcbiAgICBpZiAoc2VjcmV0Lmxlbmd0aCA8IDMyIHx8IHNlY3JldC5sZW5ndGggPiAyNTYgfHwgL1tcXHJcXG5dLy50ZXN0KHNlY3JldCkpIHtcbiAgICAgIHJldHVybiByZXNwb25zZSh7IGVycm9yOiBcIldPUktFUl9VTkNPTkZJR1VSRURcIiB9LCA1MDMpO1xuICAgIH1cbiAgICBpZiAoXG4gICAgICAhKGF3YWl0IHNhbWVTZWNyZXQoXG4gICAgICAgIHJlcS5oZWFkZXJzLmdldChcIngtY29sbGVjdC1yZWNlaXB0LXdvcmtlclwiKSA/PyBcIlwiLFxuICAgICAgICBzZWNyZXQsXG4gICAgICApKVxuICAgICkge1xuICAgICAgcmV0dXJuIHJlc3BvbnNlKHsgZXJyb3I6IFwiV09SS0VSX0FVVEhfUkVRVUlSRURcIiB9LCA0MDEpO1xuICAgIH1cbiAgICBsZXQgYm9keTogT2JqZWN0VmFsdWU7XG4gICAgdHJ5IHtcbiAgICAgIGNvbnN0IHYgPSBhd2FpdCBib3VuZGVkQm9keShyZXEpO1xuICAgICAgYXNzZXJ0KFxuICAgICAgICBmaWVsZHModiwgXCJjb250cmFjdF92ZXJzaW9uLGFjdGlvbixyZXF1ZXN0X2lkXCIpIHx8XG4gICAgICAgICAgZmllbGRzKFxuICAgICAgICAgICAgdixcbiAgICAgICAgICAgIFwiY29udHJhY3RfdmVyc2lvbixhY3Rpb24scmVxdWVzdF9pZCxjb25maWd1cmF0aW9uX3JldmlzaW9uLGV4cGlyZXNfYXRcIixcbiAgICAgICAgICApLFxuICAgICAgKTtcbiAgICAgIGFzc2VydChcbiAgICAgICAgdi5jb250cmFjdF92ZXJzaW9uID09PSAxICYmIHR5cGVvZiB2LnJlcXVlc3RfaWQgPT09IFwic3RyaW5nXCIgJiZcbiAgICAgICAgICBVVUlELnRlc3Qodi5yZXF1ZXN0X2lkKSxcbiAgICAgICk7XG4gICAgICBpZiAodi5hY3Rpb24gPT09IFwiZXhlY3V0ZVwiKSB7XG4gICAgICAgIGFzc2VydChcbiAgICAgICAgICBmaWVsZHMoXG4gICAgICAgICAgICB2LFxuICAgICAgICAgICAgXCJjb250cmFjdF92ZXJzaW9uLGFjdGlvbixyZXF1ZXN0X2lkLGNvbmZpZ3VyYXRpb25fcmV2aXNpb24sZXhwaXJlc19hdFwiLFxuICAgICAgICAgICkgJiZcbiAgICAgICAgICAgIGludGVnZXIodi5jb25maWd1cmF0aW9uX3JldmlzaW9uLCAxLCAxMDAwMDAwMDAwKSAmJlxuICAgICAgICAgICAgdGltZXN0YW1wKHYuZXhwaXJlc19hdCksXG4gICAgICAgICk7XG4gICAgICAgIGNvbnN0IHJlbWFpbmluZyA9IERhdGUucGFyc2UoU3RyaW5nKHYuZXhwaXJlc19hdCkpIC0gY2xvY2soKTtcbiAgICAgICAgYXNzZXJ0KHJlbWFpbmluZyA+IDAgJiYgcmVtYWluaW5nIDw9IDEyMDAwMCk7XG4gICAgICB9IGVsc2Uge2Fzc2VydChcbiAgICAgICAgICB2LmFjdGlvbiA9PT0gXCJyZWNvbmNpbGVcIiAmJlxuICAgICAgICAgICAgZmllbGRzKHYsIFwiY29udHJhY3RfdmVyc2lvbixhY3Rpb24scmVxdWVzdF9pZFwiKSxcbiAgICAgICAgKTt9XG4gICAgICBib2R5ID0gdjtcbiAgICB9IGNhdGNoIHtcbiAgICAgIHJldHVybiByZXNwb25zZSh7IGVycm9yOiBcIldPUktFUl9SRVFVRVNUX0lOVkFMSURcIiB9LCA0MDApO1xuICAgIH1cbiAgICBjb25zdCBpZCA9IFN0cmluZyhib2R5LnJlcXVlc3RfaWQpO1xuICAgIGNvbnN0IGxvb2t1cCA9IGFzeW5jICgpID0+IHtcbiAgICAgIGNvbnN0IHIgPSBhd2FpdCBkLnJwYyhcImdldF9yZWNlaXB0X2V4Y2VwdGlvbl93b3JrZXJfcmVxdWVzdF92MVwiLCB7XG4gICAgICAgIHBfcmVxdWVzdF9pZDogaWQsXG4gICAgICB9LCBBYm9ydFNpZ25hbC50aW1lb3V0KDMwMDApKTtcbiAgICAgIGlmIChyLmVycm9yKSB0aHJvdyBuZXcgRXJyb3IoXCJ3b3JrZXJfbG9va3VwX3VuYXZhaWxhYmxlXCIpO1xuICAgICAgcmV0dXJuIHZhbGlkYXRlV29ya2VyTG9va3VwKHIuZGF0YSwgaWQsIGNsb2NrKCkpO1xuICAgIH07XG4gICAgaWYgKGJvZHkuYWN0aW9uID09PSBcInJlY29uY2lsZVwiKSB7XG4gICAgICB0cnkge1xuICAgICAgICByZXR1cm4gcmVzcG9uc2UoYXdhaXQgbG9va3VwKCkpO1xuICAgICAgfSBjYXRjaCB7XG4gICAgICAgIHJldHVybiByZXNwb25zZShcbiAgICAgICAgICB7IGVycm9yOiBcIldPUktFUl9MT09LVVBfVU5BVkFJTEFCTEVcIiwgcmVxdWVzdF9pZDogaWQgfSxcbiAgICAgICAgICA1MDMsXG4gICAgICAgICk7XG4gICAgICB9XG4gICAgfVxuICAgIHRyeSB7XG4gICAgICBjb25zdCByID0gYXdhaXQgZC5ycGMoXCJleGVjdXRlX3JlY2VpcHRfZXhjZXB0aW9uX3dvcmtlcl92MVwiLCB7XG4gICAgICAgIHBfcmVxdWVzdF9pZDogaWQsXG4gICAgICAgIHBfY29uZmlndXJhdGlvbl9yZXZpc2lvbjogYm9keS5jb25maWd1cmF0aW9uX3JldmlzaW9uLFxuICAgICAgICBwX2V4cGlyZXNfYXQ6IGJvZHkuZXhwaXJlc19hdCxcbiAgICAgIH0sIEFib3J0U2lnbmFsLnRpbWVvdXQoODAwMCkpO1xuICAgICAgaWYgKHIuZXJyb3IpIHtcbiAgICAgICAgaWYgKHIuZXJyb3IuY29kZSA9PT0gXCI0MjUwMVwiKSB7XG4gICAgICAgICAgcmV0dXJuIHJlc3BvbnNlKFxuICAgICAgICAgICAgeyBlcnJvcjogXCJXT1JLRVJfQVVUSE9SSVRZX1JFRlVTRURcIiwgcmVxdWVzdF9pZDogaWQgfSxcbiAgICAgICAgICAgIDQwMyxcbiAgICAgICAgICApO1xuICAgICAgICB9XG4gICAgICAgIGlmIChyLmVycm9yLmNvZGUgPT09IFwiMjIwMjNcIikge1xuICAgICAgICAgIHJldHVybiByZXNwb25zZShcbiAgICAgICAgICAgIHsgZXJyb3I6IFwiV09SS0VSX09SSUdJTkFMX0NPTkZMSUNUXCIsIHJlcXVlc3RfaWQ6IGlkIH0sXG4gICAgICAgICAgICA0MDksXG4gICAgICAgICAgKTtcbiAgICAgICAgfVxuICAgICAgICB0aHJvdyBuZXcgRXJyb3IoXCJ3b3JrZXJfb3V0Y29tZV91bmtub3duXCIpO1xuICAgICAgfVxuICAgICAgYXNzZXJ0KFxuICAgICAgICBmaWVsZHMoci5kYXRhLCBcImNvbnRyYWN0X3ZlcnNpb24scmVxdWVzdF9pZCxzdGF0dXMscmVjZWlwdFwiKSAmJlxuICAgICAgICAgIHIuZGF0YS5jb250cmFjdF92ZXJzaW9uID09PSAxICYmIHIuZGF0YS5yZXF1ZXN0X2lkID09PSBpZCxcbiAgICAgICk7XG4gICAgICBpZiAoci5kYXRhLnN0YXR1cyA9PT0gXCJpbl9wcm9ncmVzc1wiKSB7XG4gICAgICAgIGFzc2VydChyLmRhdGEucmVjZWlwdCA9PT0gbnVsbCk7XG4gICAgICAgIHJldHVybiByZXNwb25zZShyLmRhdGEsIDIwMik7XG4gICAgICB9XG4gICAgICBhc3NlcnQoci5kYXRhLnN0YXR1cyA9PT0gXCJyZWNvcmRlZFwiKTtcbiAgICAgIGNvbnN0IHJlY2VpcHQgPSB2YWxpZGF0ZVdvcmtlclJlY2VpcHQoci5kYXRhLnJlY2VpcHQsIGlkKTtcbiAgICAgIGFzc2VydChcbiAgICAgICAgcmVjZWlwdC5jb25maWd1cmF0aW9uX3JldmlzaW9uID09PSBib2R5LmNvbmZpZ3VyYXRpb25fcmV2aXNpb24gJiZcbiAgICAgICAgICByZWNlaXB0LmV4cGlyZXNfYXQgPT09IGJvZHkuZXhwaXJlc19hdCxcbiAgICAgICk7XG4gICAgICByZXR1cm4gcmVzcG9uc2Uoci5kYXRhKTtcbiAgICB9IGNhdGNoIHtcbiAgICAgIC8vIEEgbG9zdCByZXNwb25zZSBuZXZlciBjYXVzZXMgdGhpcyBoYW5kbGVyIHRvIHJlcnVuIHRoZSBtdXRhdGlvbi5cbiAgICAgIC8vIFJldHVybiBvbmx5IGEgZnJlc2ggb3JpZ2luYWwgbG9va3VwLCBvciByZXRhaW4gZXhwbGljaXQgdW5jZXJ0YWludHkuXG4gICAgICB0cnkge1xuICAgICAgICBjb25zdCBmb3VuZCA9IGF3YWl0IGxvb2t1cCgpO1xuICAgICAgICBpZiAoZm91bmQuc3RhdHVzID09PSBcInJlY29yZGVkXCIpIHtcbiAgICAgICAgICBjb25zdCBvcmlnaW5hbCA9IGZvdW5kLnJlY2VpcHQgYXMgT2JqZWN0VmFsdWU7XG4gICAgICAgICAgaWYgKFxuICAgICAgICAgICAgb3JpZ2luYWwuY29uZmlndXJhdGlvbl9yZXZpc2lvbiAhPT0gYm9keS5jb25maWd1cmF0aW9uX3JldmlzaW9uIHx8XG4gICAgICAgICAgICBvcmlnaW5hbC5leHBpcmVzX2F0ICE9PSBib2R5LmV4cGlyZXNfYXRcbiAgICAgICAgICApIHtcbiAgICAgICAgICAgIHJldHVybiByZXNwb25zZSh7XG4gICAgICAgICAgICAgIGVycm9yOiBcIldPUktFUl9PUklHSU5BTF9DT05GTElDVFwiLFxuICAgICAgICAgICAgICByZXF1ZXN0X2lkOiBpZCxcbiAgICAgICAgICAgIH0sIDQwOSk7XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICAgIHJldHVybiByZXNwb25zZShmb3VuZCwgZm91bmQuc3RhdHVzID09PSBcInJlY29yZGVkXCIgPyAyMDAgOiAyMDIpO1xuICAgICAgfSBjYXRjaCB7XG4gICAgICAgIHJldHVybiByZXNwb25zZShcbiAgICAgICAgICB7IGVycm9yOiBcIldPUktFUl9PVVRDT01FX1VOS05PV05cIiwgcmVxdWVzdF9pZDogaWQgfSxcbiAgICAgICAgICAyMDIsXG4gICAgICAgICk7XG4gICAgICB9XG4gICAgfVxuICB9O1xufVxuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQVNBLE1BQU0sT0FBTztBQUNiLE1BQU0sU0FBUyxDQUFDLEdBQVksT0FDMUIsTUFBTSxRQUFRLE9BQU8sTUFBTSxZQUFZLENBQUMsTUFBTSxPQUFPLENBQUMsTUFDdEQsT0FBTyxJQUFJLENBQUMsR0FBRyxJQUFJLEdBQUcsSUFBSSxDQUFDLFNBQVMsS0FBSyxLQUFLLENBQUMsS0FBSyxJQUFJLEdBQUcsSUFBSSxDQUFDO0FBQ2xFLE1BQU0sVUFBVSxDQUFDLEdBQVksTUFBTSxDQUFDLEVBQUUsTUFBTSxPQUFPLGdCQUFnQixHQUNqRSxPQUFPLGFBQWEsQ0FBQyxNQUFNLE9BQU8sTUFBTSxPQUFPLE9BQU8sTUFBTTtBQUM5RCxNQUFNLFlBQVksQ0FBQyxJQUNqQixPQUFPLE1BQU0sWUFBWSx3QkFBd0IsSUFBSSxDQUFDLE1BQ3RELE9BQU8sUUFBUSxDQUFDLEtBQUssS0FBSyxDQUFDO0FBQzdCLFNBQVMsT0FBTyxDQUFVO0VBQ3hCLElBQUksQ0FBQyxHQUFHLE1BQU0sSUFBSSxNQUFNO0FBQzFCO0FBQ0EsU0FBUyxZQUFZLENBQVUsRUFBRSxFQUFVO0VBQ3pDLE9BQ0UsT0FDRSxHQUNBO0VBR0osT0FDRSxFQUFFLGdCQUFnQixLQUFLLEtBQUssRUFB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
// denoCacheMetadata=13697912527965663570,17711478770382565195