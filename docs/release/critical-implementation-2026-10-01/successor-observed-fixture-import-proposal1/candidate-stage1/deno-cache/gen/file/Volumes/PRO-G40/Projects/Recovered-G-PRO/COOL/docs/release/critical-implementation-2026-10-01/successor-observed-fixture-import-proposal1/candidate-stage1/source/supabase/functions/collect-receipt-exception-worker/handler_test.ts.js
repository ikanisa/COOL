import { createExceptionWorkerHandler } from "./handler.ts";
const ID = "99950000-0000-4000-8000-000000000001";
const SECRET = "SYNTHETIC-WORKER-CREDENTIAL-NEVER-A-REAL-SECRET";
const NOW = Date.parse("2026-10-01T12:00:00Z");
const stamp = (delta = 0)=>new Date(NOW + delta).toISOString();
const execute = ()=>({
    contract_version: 1,
    action: "execute",
    request_id: ID,
    configuration_revision: 2,
    expires_at: stamp(90000)
  });
const receipt = ()=>({
    contract_version: 1,
    request_id: ID,
    configuration_revision: 2,
    recorded_at: stamp(),
    expires_at: stamp(90000),
    status: "completed",
    scan: {
      contract_version: 1,
      request_id: ID,
      checked_at: stamp(),
      expires_at: stamp(90000),
      status: "processed",
      seeded: 1,
      processed: 1,
      refused: 0,
      observations_added: 1,
      activated: 1,
      cleared: 0,
      unchanged: 0,
      pending: 0,
      scan_epoch: 1,
      scan_phase: "receipt_event",
      source_scan_complete: false,
      financial_action: false,
      send_action: false
    },
    escalation: {
      contract_version: 1,
      channel: "admin_inbox",
      delivered: 1,
      obsolete: 0,
      recipient_unavailable: 0,
      external_send: false
    },
    financial_action: false,
    send_action: false,
    external_send: false
  });
const recorded = ()=>({
    contract_version: 1,
    request_id: ID,
    status: "recorded",
    receipt: receipt()
  });
const lookup = (status = "recorded")=>({
    contract_version: 1,
    request_id: ID,
    checked_at: stamp(),
    sample_valid_until: stamp(60000),
    status,
    expires_at: stamp(90000),
    receipt: status === "recorded" ? receipt() : null
  });
function assert(v) {
  if (!v) throw Error("assertion_failed");
}
async function invoke(body, overrides = {}, options = {}) {
  const calls = [];
  const handler = createExceptionWorkerHandler({
    now: ()=>NOW,
    secret: ()=>SECRET,
    rpc: async (name, args, signal)=>{
      assert(!signal.aborted);
      calls.push({
        name,
        args
      });
      return overrides.rpc ? await overrides.rpc(name, args, signal) : {
        data: name.startsWith("execute_") ? recorded() : lookup(),
        error: null
      };
    },
    ...Object.fromEntries(Object.entries(overrides).filter(([k])=>k !== "rpc"))
  });
  const r = await handler(new Request("https://worker.test/", {
    method: options.method ?? "POST",
    headers: {
      "x-collect-receipt-worker": options.secret ?? SECRET
    },
    body: options.method === "GET" ? undefined : options.raw ?? JSON.stringify(body)
  }));
  return {
    status: r.status,
    body: await r.json(),
    calls,
    headers: r.headers
  };
}
Deno.test("actual HTTP entry boundary returns exact recorded SQL receipt without private payload", async ()=>{
  const handler = createExceptionWorkerHandler({
    secret: ()=>SECRET,
    now: ()=>NOW,
    rpc: async ()=>({
        data: recorded(),
        error: null
      })
  });
  const server = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    onListen: ()=>{}
  }, handler);
  try {
    const r = await fetch(`http://127.0.0.1:${server.addr.port}/`, {
      method: "POST",
      headers: {
        "x-collect-receipt-worker": SECRET
      },
      body: JSON.stringify(execute())
    });
    assert(r.status === 200 && JSON.stringify(await r.json()) === JSON.stringify(recorded()));
    assert(r.headers.get("cache-control") === "no-store");
  } finally{
    await server.shutdown();
  }
});
Deno.test("method and unconfigured credential refuse before RPC", async ()=>{
  for (const v of [
    await invoke(execute(), {}, {
      method: "GET"
    }),
    await invoke(execute(), {
      secret: ()=>""
    }),
    await invoke(execute(), {
      secret: ()=>"x".repeat(300)
    })
  ]){
    assert(v.status >= 400 && v.calls.length === 0);
  }
});
Deno.test("general internal secret or JWT cannot authorize dedicated worker", async ()=>{
  const v = await invoke(execute(), {}, {
    secret: "DIFFERENT-INTERNAL-SECRET-THAT-IS-LONG"
  });
  assert(v.status === 401 && v.calls.length === 0 && v.body.error === "WORKER_AUTH_REQUIRED");
});
Deno.test("request allowlist rejects arbitrary action destination text quota and extra field", async ()=>{
  for (const body of [
    {
      ...execute(),
      action: "send_sms"
    },
    {
      ...execute(),
      destination: "+250788123456"
    },
    {
      ...execute(),
      text: "Hello"
    },
    {
      ...execute(),
      scan_limit: 100
    },
    {
      ...execute(),
      request_id: "bad"
    },
    {
      ...execute(),
      contract_version: 2
    },
    {
      ...execute(),
      configuration_revision: 1.5
    }
  ]){
    const v = await invoke(body);
    assert(v.status === 400 && v.calls.length === 0);
  }
});
Deno.test("expired or excessive execute deadline refuses without mutation", async ()=>{
  for (const expiry of [
    stamp(-1),
    stamp(120001),
    "infinity",
    "2026-10-01T99:00:00Z"
  ]){
    assert((await invoke({
      ...execute(),
      expires_at: expiry
    })).status === 400);
  }
});
Deno.test("bounded streamed input rejects oversized and malformed JSON before RPC", async ()=>{
  for (const raw of [
    "{",
    JSON.stringify({
      ...execute(),
      extra: "x".repeat(3000)
    })
  ]){
    const v = await invoke(null, {}, {
      raw
    });
    assert(v.status === 400 && v.calls.length === 0);
  }
});
Deno.test("execute sends only exact original job parameters", async ()=>{
  const v = await invoke(execute());
  assert(v.status === 200 && v.calls.length === 1);
  assert(JSON.stringify(v.calls[0]) === JSON.stringify({
    name: "execute_receipt_exception_worker_v1",
    args: {
      p_request_id: ID,
      p_configuration_revision: 2,
      p_expires_at: stamp(90000)
    }
  }));
});
Deno.test("authority refusal and original conflict are finite redacted refusals", async ()=>{
  for (const [code, status] of [
    [
      "42501",
      403
    ],
    [
      "22023",
      409
    ]
  ]){
    const v = await invoke(execute(), {
      rpc: async ()=>({
          data: null,
          error: {
            code
          }
        })
    });
    assert(v.status === status && v.calls.length === 1 && Object.keys(v.body).length === 2);
  }
});
Deno.test("lost mutation response reconciles recorded proof without rerunning execute", async ()=>{
  const v = await invoke(execute(), {
    rpc: async (name)=>{
      if (name.startsWith("execute_")) {
        throw Error("transport_timeout_with_sensitive_body");
      }
      return {
        data: lookup(),
        error: null
      };
    }
  });
  assert(v.status === 200 && v.body.receipt.request_id === ID && v.calls.length === 2 && v.calls[1].name.startsWith("get_"));
  assert(!JSON.stringify(v.body).includes("sensitive"));
});
Deno.test("missing before original expiry preserves uncertain response and original deadline", async ()=>{
  const v = await invoke(execute(), {
    rpc: async (name)=>name.startsWith("execute_") ? {
        data: null,
        error: {
          code: "57014"
        }
      } : {
        data: lookup("not_recorded"),
        error: null
      }
  });
  assert(v.status === 202 && v.body.status === "not_recorded" && v.body.expires_at === stamp(90000) && v.calls.length === 2);
});
Deno.test("recorded recovery is bound to the exact requested configuration and deadline", async ()=>{
  const different = lookup();
  different.receipt.configuration_revision = 3;
  const v = await invoke(execute(), {
    rpc: async (name)=>{
      if (name.startsWith("execute_")) throw Error("network_timeout");
      return {
        data: different,
        error: null
      };
    }
  });
  assert(v.status === 409 && v.body.error === "WORKER_ORIGINAL_CONFLICT" && v.calls.length === 2);
});
Deno.test("global overlap returns explicit in_progress without additional mutation", async ()=>{
  const v = await invoke(execute(), {
    rpc: async ()=>({
        data: {
          contract_version: 1,
          request_id: ID,
          status: "in_progress",
          receipt: null
        },
        error: null
      })
  });
  assert(v.status === 202 && v.body.receipt === null && v.calls.length === 1);
});
Deno.test("unavailable original lookup retains uncertainty with no third attempt", async ()=>{
  const v = await invoke(execute(), {
    rpc: async ()=>{
      throw Error("network_timeout");
    }
  });
  assert(v.status === 202 && v.body.error === "WORKER_OUTCOME_UNKNOWN" && v.calls.length === 2);
});
Deno.test("reconcile calls only read and remains valid after execute expiry", async ()=>{
  const v = await invoke({
    contract_version: 1,
    action: "reconcile",
    request_id: ID
  }, {
    now: ()=>NOW + 200000,
    rpc: async ()=>({
        data: {
          ...lookup(),
          checked_at: stamp(200000),
          sample_valid_until: stamp(260000)
        },
        error: null
      })
  });
  assert(v.status === 200 && v.calls.length === 1 && v.calls[0].name === "get_receipt_exception_worker_request_v1");
});
Deno.test("stale or contradictory lookup cannot prove absence or expose raw response", async ()=>{
  for (const bad of [
    {
      ...lookup("not_recorded"),
      sample_valid_until: stamp(-1)
    },
    {
      ...lookup("not_recorded"),
      receipt: receipt()
    },
    {
      ...lookup(),
      checked_at: stamp(7000)
    },
    {
      ...lookup(),
      recipient: "private"
    }
  ]){
    const v = await invoke({
      contract_version: 1,
      action: "reconcile",
      request_id: ID
    }, {
      rpc: async ()=>({
          data: bad,
          error: null
        })
    });
    assert(v.status === 503 && v.body.error === "WORKER_LOOKUP_UNAVAILABLE" && !JSON.stringify(v.body).includes("private"));
  }
});
Deno.test("mismatched original or nonfinite nested counters cannot fabricate success", async ()=>{
  for (const change of [
    (r)=>{
      r.configuration_revision = 3;
    },
    (r)=>{
      r.scan.processed = 26;
    },
    (r)=>{
      r.scan.refused = 2;
    },
    (r)=>{
      r.escalation.delivered = 21;
    },
    (r)=>{
      r.financial_action = true;
    },
    (r)=>{
      r.scan.source_scan_complete = true;
    }
  ]){
    const r = receipt();
    change(r);
    const v = await invoke(execute(), {
      rpc: async (name)=>name.startsWith("execute_") ? {
          data: {
            ...recorded(),
            receipt: r
          },
          error: null
        } : {
          data: lookup("not_recorded"),
          error: null
        }
    });
    assert(v.status === 202 && v.body.status === "not_recorded" && v.calls.length === 2);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1leGNlcHRpb24td29ya2VyL2hhbmRsZXJfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQge1xuICBjcmVhdGVFeGNlcHRpb25Xb3JrZXJIYW5kbGVyLFxuICB0eXBlIFdvcmtlckRlcGVuZGVuY2llcyxcbn0gZnJvbSBcIi4vaGFuZGxlci50c1wiO1xuY29uc3QgSUQgPSBcIjk5OTUwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMVwiO1xuY29uc3QgU0VDUkVUID0gXCJTWU5USEVUSUMtV09SS0VSLUNSRURFTlRJQUwtTkVWRVItQS1SRUFMLVNFQ1JFVFwiO1xuY29uc3QgTk9XID0gRGF0ZS5wYXJzZShcIjIwMjYtMTAtMDFUMTI6MDA6MDBaXCIpO1xuY29uc3Qgc3RhbXAgPSAoZGVsdGEgPSAwKSA9PiBuZXcgRGF0ZShOT1cgKyBkZWx0YSkudG9JU09TdHJpbmcoKTtcbmNvbnN0IGV4ZWN1dGUgPSAoKSA9PiAoe1xuICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICBhY3Rpb246IFwiZXhlY3V0ZVwiLFxuICByZXF1ZXN0X2lkOiBJRCxcbiAgY29uZmlndXJhdGlvbl9yZXZpc2lvbjogMixcbiAgZXhwaXJlc19hdDogc3RhbXAoOTAwMDApLFxufSk7XG5jb25zdCByZWNlaXB0ID0gKCkgPT4gKHtcbiAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgcmVxdWVzdF9pZDogSUQsXG4gIGNvbmZpZ3VyYXRpb25fcmV2aXNpb246IDIsXG4gIHJlY29yZGVkX2F0OiBzdGFtcCgpLFxuICBleHBpcmVzX2F0OiBzdGFtcCg5MDAwMCksXG4gIHN0YXR1czogXCJjb21wbGV0ZWRcIixcbiAgc2Nhbjoge1xuICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gICAgcmVxdWVzdF9pZDogSUQsXG4gICAgY2hlY2tlZF9hdDogc3RhbXAoKSxcbiAgICBleHBpcmVzX2F0OiBzdGFtcCg5MDAwMCksXG4gICAgc3RhdHVzOiBcInByb2Nlc3NlZFwiLFxuICAgIHNlZWRlZDogMSxcbiAgICBwcm9jZXNzZWQ6IDEsXG4gICAgcmVmdXNlZDogMCxcbiAgICBvYnNlcnZhdGlvbnNfYWRkZWQ6IDEsXG4gICAgYWN0aXZhdGVkOiAxLFxuICAgIGNsZWFyZWQ6IDAsXG4gICAgdW5jaGFuZ2VkOiAwLFxuICAgIHBlbmRpbmc6IDAsXG4gICAgc2Nhbl9lcG9jaDogMSxcbiAgICBzY2FuX3BoYXNlOiBcInJlY2VpcHRfZXZlbnRcIixcbiAgICBzb3VyY2Vfc2Nhbl9jb21wbGV0ZTogZmFsc2UsXG4gICAgZmluYW5jaWFsX2FjdGlvbjogZmFsc2UsXG4gICAgc2VuZF9hY3Rpb246IGZhbHNlLFxuICB9LFxuICBlc2NhbGF0aW9uOiB7XG4gICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICBjaGFubmVsOiBcImFkbWluX2luYm94XCIsXG4gICAgZGVsaXZlcmVkOiAxLFxuICAgIG9ic29sZXRlOiAwLFxuICAgIHJlY2lwaWVudF91bmF2YWlsYWJsZTogMCxcbiAgICBleHRlcm5hbF9zZW5kOiBmYWxzZSxcbiAgfSxcbiAgZmluYW5jaWFsX2FjdGlvbjogZmFsc2UsXG4gIHNlbmRfYWN0aW9uOiBmYWxzZSxcbiAgZXh0ZXJuYWxfc2VuZDogZmFsc2UsXG59KTtcbmNvbnN0IHJlY29yZGVkID0gKCkgPT4gKHtcbiAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgcmVxdWVzdF9pZDogSUQsXG4gIHN0YXR1czogXCJyZWNvcmRlZFwiLFxuICByZWNlaXB0OiByZWNlaXB0KCksXG59KTtcbmNvbnN0IGxvb2t1cCA9IChzdGF0dXMgPSBcInJlY29yZGVkXCIpID0+ICh7XG4gIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gIHJlcXVlc3RfaWQ6IElELFxuICBjaGVja2VkX2F0OiBzdGFtcCgpLFxuICBzYW1wbGVfdmFsaWRfdW50aWw6IHN0YW1wKDYwMDAwKSxcbiAgc3RhdHVzLFxuICBleHBpcmVzX2F0OiBzdGFtcCg5MDAwMCksXG4gIHJlY2VpcHQ6IHN0YXR1cyA9PT0gXCJyZWNvcmRlZFwiID8gcmVjZWlwdCgpIDogbnVsbCxcbn0pO1xuZnVuY3Rpb24gYXNzZXJ0KHY6IHVua25vd24pOiBhc3NlcnRzIHYge1xuICBpZiAoIXYpIHRocm93IEVycm9yKFwiYXNzZXJ0aW9uX2ZhaWxlZFwiKTtcbn1cbmFzeW5jIGZ1bmN0aW9uIGludm9rZShcbiAgYm9keTogdW5rbm93bixcbiAgb3ZlcnJpZGVzOiBQYXJ0aWFsPFdvcmtlckRlcGVuZGVuY2llcz4gPSB7fSxcbiAgb3B0aW9uczogeyBtZXRob2Q/OiBzdHJpbmc7IHNlY3JldD86IHN0cmluZzsgcmF3Pzogc3RyaW5nIH0gPSB7fSxcbikge1xuICBjb25zdCBjYWxsczogeyBuYW1lOiBzdHJpbmc7IGFyZ3M6IFJlY29yZDxzdHJpbmcsIHVua25vd24+IH1bXSA9IFtdO1xuICBjb25zdCBoYW5kbGVyID0gY3JlYXRlRXhjZXB0aW9uV29ya2VySGFuZGxlcih7XG4gICAgbm93OiAoKSA9PiBOT1csXG4gICAgc2VjcmV0OiAoKSA9PiBTRUNSRVQsXG4gICAgcnBjOiBhc3luYyAobmFtZSwgYXJncywgc2lnbmFsKSA9PiB7XG4gICAgICBhc3NlcnQoIXNpZ25hbC5hYm9ydGVkKTtcbiAgICAgIGNhbGxzLnB1c2goeyBuYW1lLCBhcmdzIH0pO1xuICAgICAgcmV0dXJuIG92ZXJyaWRlcy5ycGMgPyBhd2FpdCBvdmVycmlkZXMucnBjKG5hbWUsIGFyZ3MsIHNpZ25hbCkgOiB7XG4gICAgICAgIGRhdGE6IG5hbWUuc3RhcnRzV2l0aChcImV4ZWN1dGVfXCIpID8gcmVjb3JkZWQoKSA6IGxvb2t1cCgpLFxuICAgICAgICBlcnJvcjogbnVsbCxcbiAgICAgIH07XG4gICAgfSxcbiAgICAuLi5PYmplY3QuZnJvbUVudHJpZXMoXG4gICAgICBPYmplY3QuZW50cmllcyhvdmVycmlkZXMpLmZpbHRlcigoW2tdKSA9PiBrICE9PSBcInJwY1wiKSxcbiAgICApLFxuICB9KTtcbiAgY29uc3QgciA9IGF3YWl0IGhhbmRsZXIoXG4gICAgbmV3IFJlcXVlc3QoXCJodHRwczovL3dvcmtlci50ZXN0L1wiLCB7XG4gICAgICBtZXRob2Q6IG9wdGlvbnMubWV0aG9kID8/IFwiUE9TVFwiLFxuICAgICAgaGVhZGVyczogeyBcIngtY29sbGVjdC1yZWNlaXB0LXdvcmtlclwiOiBvcHRpb25zLnNlY3JldCA/PyBTRUNSRVQgfSxcbiAgICAgIGJvZHk6IG9wdGlvbnMubWV0aG9kID09PSBcIkdFVFwiXG4gICAgICAgID8gdW5kZWZpbmVkXG4gICAgICAgIDogb3B0aW9ucy5yYXcgPz8gSlNPTi5zdHJpbmdpZnkoYm9keSksXG4gICAgfSksXG4gICk7XG4gIHJldHVybiB7IHN0YXR1czogci5zdGF0dXMsIGJvZHk6IGF3YWl0IHIuanNvbigpLCBjYWxscywgaGVhZGVyczogci5oZWFkZXJzIH07XG59XG5EZW5vLnRlc3QoXCJhY3R1YWwgSFRUUCBlbnRyeSBib3VuZGFyeSByZXR1cm5zIGV4YWN0IHJlY29yZGVkIFNRTCByZWNlaXB0IHdpdGhvdXQgcHJpdmF0ZSBwYXlsb2FkXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgaGFuZGxlciA9IGNyZWF0ZUV4Y2VwdGlvbldvcmtlckhhbmRsZXIoe1xuICAgIHNlY3JldDogKCkgPT4gU0VDUkVULFxuICAgIG5vdzogKCkgPT4gTk9XLFxuICAgIHJwYzogYXN5bmMgKCkgPT4gKHsgZGF0YTogcmVjb3JkZWQoKSwgZXJyb3I6IG51bGwgfSksXG4gIH0pO1xuICBjb25zdCBzZXJ2ZXIgPSBEZW5vLnNlcnZlKHtcbiAgICBob3N0bmFtZTogXCIxMjcuMC4wLjFcIixcbiAgICBwb3J0OiAwLFxuICAgIG9uTGlzdGVuOiAoKSA9PiB7fSxcbiAgfSwgaGFuZGxlcik7XG4gIHRyeSB7XG4gICAgY29uc3QgciA9IGF3YWl0IGZldGNoKGBodHRwOi8vMTI3LjAuMC4xOiR7c2VydmVyLmFkZHIucG9ydH0vYCwge1xuICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgIGhlYWRlcnM6IHsgXCJ4LWNvbGxlY3QtcmVjZWlwdC13b3JrZXJcIjogU0VDUkVUIH0sXG4gICAgICBib2R5OiBKU09OLnN0cmluZ2lmeShleGVjdXRlKCkpLFxuICAgIH0pO1xuICAgIGFzc2VydChcbiAgICAgIHIuc3RhdHVzID09PSAyMDAgJiZcbiAgICAgICAgSlNPTi5zdHJpbmdpZnkoYXdhaXQgci5qc29uKCkpID09PSBKU09OLnN0cmluZ2lmeShyZWNvcmRlZCgpKSxcbiAgICApO1xuICAgIGFzc2VydChyLmhlYWRlcnMuZ2V0KFwiY2FjaGUtY29udHJvbFwiKSA9PT0gXCJuby1zdG9yZVwiKTtcbiAgfSBmaW5hbGx5IHtcbiAgICBhd2FpdCBzZXJ2ZXIuc2h1dGRvd24oKTtcbiAgfVxufSk7XG5EZW5vLnRlc3QoXCJtZXRob2QgYW5kIHVuY29uZmlndXJlZCBjcmVkZW50aWFsIHJlZnVzZSBiZWZvcmUgUlBDXCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCB2IG9mIFtcbiAgICAgIGF3YWl0IGludm9rZShleGVjdXRlKCksIHt9LCB7IG1ldGhvZDogXCJHRVRcIiB9KSxcbiAgICAgIGF3YWl0IGludm9rZShleGVjdXRlKCksIHsgc2VjcmV0OiAoKSA9PiBcIlwiIH0pLFxuICAgICAgYXdhaXQgaW52b2tlKGV4ZWN1dGUoKSwgeyBzZWNyZXQ6ICgpID0+IFwieFwiLnJlcGVhdCgzMDApIH0pLFxuICAgIF1cbiAgKSB7XG4gICAgYXNzZXJ0KHYuc3RhdHVzID49IDQwMCAmJiB2LmNhbGxzLmxlbmd0aCA9PT0gMCk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwiZ2VuZXJhbCBpbnRlcm5hbCBzZWNyZXQgb3IgSldUIGNhbm5vdCBhdXRob3JpemUgZGVkaWNhdGVkIHdvcmtlclwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHYgPSBhd2FpdCBpbnZva2UoZXhlY3V0ZSgpLCB7fSwge1xuICAgIHNlY3JldDogXCJESUZGRVJFTlQtSU5URVJOQUwtU0VDUkVULVRIQVQtSVMtTE9OR1wiLFxuICB9KTtcbiAgYXNzZXJ0KFxuICAgIHYuc3RhdHVzID09PSA0MDEgJiYgdi5jYWxscy5sZW5ndGggPT09IDAgJiZcbiAgICAgIHYuYm9keS5lcnJvciA9PT0gXCJXT1JLRVJfQVVUSF9SRVFVSVJFRFwiLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJyZXF1ZXN0IGFsbG93bGlzdCByZWplY3RzIGFyYml0cmFyeSBhY3Rpb24gZGVzdGluYXRpb24gdGV4dCBxdW90YSBhbmQgZXh0cmEgZmllbGRcIiwgYXN5bmMgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IGJvZHkgb2YgW1xuICAgICAgeyAuLi5leGVjdXRlKCksIGFjdGlvbjogXCJzZW5kX3Ntc1wiIH0sXG4gICAgICB7IC4uLmV4ZWN1dGUoKSwgZGVzdGluYXRpb246IFwiKzI1MDc4ODEyMzQ1NlwiIH0sXG4gICAgICB7IC4uLmV4ZWN1dGUoKSwgdGV4dDogXCJIZWxsb1wiIH0sXG4gICAgICB7IC4uLmV4ZWN1dGUoKSwgc2Nhbl9saW1pdDogMTAwIH0sXG4gICAgICB7IC4uLmV4ZWN1dGUoKSwgcmVxdWVzdF9pZDogXCJiYWRcIiB9LFxuICAgICAgeyAuLi5leGVjdXRlKCksIGNvbnRyYWN0X3ZlcnNpb246IDIgfSxcbiAgICAgIHsgLi4uZXhlY3V0ZSgpLCBjb25maWd1cmF0aW9uX3JldmlzaW9uOiAxLjUgfSxcbiAgICBdXG4gICkge1xuICAgIGNvbnN0IHYgPSBhd2FpdCBpbnZva2UoYm9keSk7XG4gICAgYXNzZXJ0KHYuc3RhdHVzID09PSA0MDAgJiYgdi5jYWxscy5sZW5ndGggPT09IDApO1xuICB9XG59KTtcbkRlbm8udGVzdChcImV4cGlyZWQgb3IgZXhjZXNzaXZlIGV4ZWN1dGUgZGVhZGxpbmUgcmVmdXNlcyB3aXRob3V0IG11dGF0aW9uXCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCBleHBpcnkgb2YgW1xuICAgICAgc3RhbXAoLTEpLFxuICAgICAgc3RhbXAoMTIwMDAxKSxcbiAgICAgIFwiaW5maW5pdHlcIixcbiAgICAgIFwiMjAyNi0xMC0wMVQ5OTowMDowMFpcIixcbiAgICBdXG4gICkge1xuICAgIGFzc2VydCgoYXdhaXQgaW52b2tlKHsgLi4uZXhlY3V0ZSgpLCBleHBpcmVzX2F0OiBleHBpcnkgfSkpLnN0YXR1cyA9PT0gNDAwKTtcbiAgfVxufSk7XG5EZW5vLnRlc3QoXCJib3VuZGVkIHN0cmVhbWVkIGlucHV0IHJlamVjdHMgb3ZlcnNpemVkIGFuZCBtYWxmb3JtZWQgSlNPTiBiZWZvcmUgUlBDXCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCByYXcgb2YgW1xuICAgICAgXCJ7XCIsXG4gICAgICBKU09OLnN0cmluZ2lmeSh7IC4uLmV4ZWN1dGUoKSwgZXh0cmE6IFwieFwiLnJlcGVhdCgzMDAwKSB9KSxcbiAgICBdXG4gICkge1xuICAgIGNvbnN0IHYgPSBhd2FpdCBpbnZva2UobnVsbCwge30sIHsgcmF3IH0pO1xuICAgIGFzc2VydCh2LnN0YXR1cyA9PT0gNDAwICYmIHYuY2FsbHMubGVuZ3RoID09PSAwKTtcbiAgfVxufSk7XG5EZW5vLnRlc3QoXCJleGVjdXRlIHNlbmRzIG9ubHkgZXhhY3Qgb3JpZ2luYWwgam9iIHBhcmFtZXRlcnNcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCB2ID0gYXdhaXQgaW52b2tlKGV4ZWN1dGUoKSk7XG4gIGFzc2VydCh2LnN0YXR1cyA9PT0gMjAwICYmIHYuY2FsbHMubGVuZ3RoID09PSAxKTtcbiAgYXNzZXJ0KFxuICAgIEpTT04uc3RyaW5naWZ5KHYuY2FsbHNbMF0pID09PVxuICAgICAgSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICBuYW1lOiBcImV4ZWN1dGVfcmVjZWlwdF9leGNlcHRpb25fd29ya2VyX3YxXCIsXG4gICAgICAgIGFyZ3M6IHtcbiAgICAgICAgICBwX3JlcXVlc3RfaWQ6IElELFxuICAgICAgICAgIHBfY29uZmlndXJhdGlvbl9yZXZpc2lvbjogMixcbiAgICAgICAgICBwX2V4cGlyZXNfYXQ6IHN0YW1wKDkwMDAwKSxcbiAgICAgICAgfSxcbiAgICAgIH0pLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJhdXRob3JpdHkgcmVmdXNhbCBhbmQgb3JpZ2luYWwgY29uZmxpY3QgYXJlIGZpbml0ZSByZWRhY3RlZCByZWZ1c2Fsc1wiLCBhc3luYyAoKSA9PiB7XG4gIGZvciAoY29uc3QgW2NvZGUsIHN0YXR1c10gb2YgW1tcIjQyNTAxXCIsIDQwM10sIFtcIjIyMDIzXCIsIDQwOV1dIGFzIGNvbnN0KSB7XG4gICAgY29uc3QgdiA9IGF3YWl0IGludm9rZShleGVjdXRlKCksIHtcbiAgICAgIHJwYzogYXN5bmMgKCkgPT4gKHsgZGF0YTogbnVsbCwgZXJyb3I6IHsgY29kZSB9IH0pLFxuICAgIH0pO1xuICAgIGFzc2VydChcbiAgICAgIHYuc3RhdHVzID09PSBzdGF0dXMgJiYgdi5jYWxscy5sZW5ndGggPT09IDEgJiZcbiAgICAgICAgT2JqZWN0LmtleXModi5ib2R5KS5sZW5ndGggPT09IDIsXG4gICAgKTtcbiAgfVxufSk7XG5EZW5vLnRlc3QoXCJsb3N0IG11dGF0aW9uIHJlc3BvbnNlIHJlY29uY2lsZXMgcmVjb3JkZWQgcHJvb2Ygd2l0aG91dCByZXJ1bm5pbmcgZXhlY3V0ZVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHYgPSBhd2FpdCBpbnZva2UoZXhlY3V0ZSgpLCB7XG4gICAgcnBjOiBhc3luYyAobmFtZSkgPT4ge1xuICAgICAgaWYgKG5hbWUuc3RhcnRzV2l0aChcImV4ZWN1dGVfXCIpKSB7XG4gICAgICAgIHRocm93IEVycm9yKFwidHJhbnNwb3J0X3RpbWVvdXRfd2l0aF9zZW5zaXRpdmVfYm9keVwiKTtcbiAgICAgIH1cbiAgICAgIHJldHVybiB7IGRhdGE6IGxvb2t1cCgpLCBlcnJvcjogbnVsbCB9O1xuICAgIH0sXG4gIH0pO1xuICBhc3NlcnQoXG4gICAgdi5zdGF0dXMgPT09IDIwMCAmJiB2LmJvZHkucmVjZWlwdC5yZXF1ZXN0X2lkID09PSBJRCAmJlxuICAgICAgdi5jYWxscy5sZW5ndGggPT09IDIgJiYgdi5jYWxsc1sxXS5uYW1lLnN0YXJ0c1dpdGgoXCJnZXRfXCIpLFxuICApO1xuICBhc3NlcnQoIUpTT04uc3RyaW5naWZ5KHYuYm9keSkuaW5jbHVkZXMoXCJzZW5zaXRpdmVcIikpO1xufSk7XG5EZW5vLnRlc3QoXCJtaXNzaW5nIGJlZm9yZSBvcmlnaW5hbCBleHBpcnkgcHJlc2VydmVzIHVuY2VydGFpbiByZXNwb25zZSBhbmQgb3JpZ2luYWwgZGVhZGxpbmVcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCB2ID0gYXdhaXQgaW52b2tlKGV4ZWN1dGUoKSwge1xuICAgIHJwYzogYXN5bmMgKG5hbWUpID0+XG4gICAgICBuYW1lLnN0YXJ0c1dpdGgoXCJleGVjdXRlX1wiKVxuICAgICAgICA/IHsgZGF0YTogbnVsbCwgZXJyb3I6IHsgY29kZTogXCI1NzAxNFwiIH0gfVxuICAgICAgICA6IHsgZGF0YTogbG9va3VwKFwibm90X3JlY29yZGVkXCIpLCBlcnJvcjogbnVsbCB9LFxuICB9KTtcbiAgYXNzZXJ0KFxuICAgIHYuc3RhdHVzID09PSAyMDIgJiYgdi5ib2R5LnN0YXR1cyA9PT0gXCJub3RfcmVjb3JkZWRcIiAmJlxuICAgICAgdi5ib2R5LmV4cGlyZXNfYXQgPT09IHN0YW1wKDkwMDAwKSAmJiB2LmNhbGxzLmxlbmd0aCA9PT0gMixcbiAgKTtcbn0pO1xuRGVuby50ZXN0KFwicmVjb3JkZWQgcmVjb3ZlcnkgaXMgYm91bmQgdG8gdGhlIGV4YWN0IHJlcXVlc3RlZCBjb25maWd1cmF0aW9uIGFuZCBkZWFkbGluZVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGRpZmZlcmVudCA9IGxvb2t1cCgpO1xuICBkaWZmZXJlbnQucmVjZWlwdCEuY29uZmlndXJhdGlvbl9yZXZpc2lvbiA9IDM7XG4gIGNvbnN0IHYgPSBhd2FpdCBpbnZva2UoZXhlY3V0ZSgpLCB7XG4gICAgcnBjOiBhc3luYyAobmFtZSkgPT4ge1xuICAgICAgaWYgKG5hbWUuc3RhcnRzV2l0aChcImV4ZWN1dGVfXCIpKSB0aHJvdyBFcnJvcihcIm5ldHdvcmtfdGltZW91dFwiKTtcbiAgICAgIHJldHVybiB7IGRhdGE6IGRpZmZlcmVudCwgZXJyb3I6IG51bGwgfTtcbiAgICB9LFxuICB9KTtcbiAgYXNzZXJ0KFxuICAgIHYuc3RhdHVzID09PSA0MDkgJiYgdi5ib2R5LmVycm9yID09PSBcIldPUktFUl9PUklHSU5BTF9DT05GTElDVFwiICYmXG4gICAgICB2LmNhbGxzLmxlbmd0aCA9PT0gMixcbiAgKTtcbn0pO1xuRGVuby50ZXN0KFwiZ2xvYmFsIG92ZXJsYXAgcmV0dXJucyBleHBsaWNpdCBpbl9wcm9ncmVzcyB3aXRob3V0IGFkZGl0aW9uYWwgbXV0YXRpb25cIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCB2ID0gYXdhaXQgaW52b2tlKGV4ZWN1dGUoKSwge1xuICAgIHJwYzogYXN5bmMgKCkgPT4gKHtcbiAgICAgIGRhdGE6IHtcbiAgICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgICAgcmVxdWVzdF9pZDogSUQsXG4gICAgICAgIHN0YXR1czogXCJpbl9wcm9ncmVzc1wiLFxuICAgICAgICByZWNlaXB0OiBudWxsLFxuICAgICAgfSxcbiAgICAgIGVycm9yOiBudWxsLFxuICAgIH0pLFxuICB9KTtcbiAgYXNzZXJ0KHYuc3RhdHVzID09PSAyMDIgJiYgdi5ib2R5LnJlY2VpcHQgPT09IG51bGwgJiYgdi5jYWxscy5sZW5ndGggPT09IDEpO1xufSk7XG5EZW5vLnRlc3QoXCJ1bmF2YWlsYWJsZSBvcmlnaW5hbCBsb29rdXAgcmV0YWlucyB1bmNlcnRhaW50eSB3aXRoIG5vIHRoaXJkIGF0dGVtcHRcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCB2ID0gYXdhaXQgaW52b2tlKGV4ZWN1dGUoKSwge1xuICAgIHJwYzogYXN5bmMgKCkgPT4ge1xuICAgICAgdGhyb3cgRXJyb3IoXCJuZXR3b3JrX3RpbWVvdXRcIik7XG4gICAgfSxcbiAgfSk7XG4gIGFzc2VydChcbiAgICB2LnN0YXR1cyA9PT0gMjAyICYmIHYuYm9keS5lcnJvciA9PT0gXCJXT1JLRVJfT1VUQ09NRV9VTktOT1dOXCIgJiZcbiAgICAgIHYuY2FsbHMubGVuZ3RoID09PSAyLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJyZWNvbmNpbGUgY2FsbHMgb25seSByZWFkIGFuZCByZW1haW5zIHZhbGlkIGFmdGVyIGV4ZWN1dGUgZXhwaXJ5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgdiA9IGF3YWl0IGludm9rZSh7XG4gICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICBhY3Rpb246IFwicmVjb25jaWxlXCIsXG4gICAgcmVxdWVzdF9pZDogSUQsXG4gIH0sIHtcbiAgICBub3c6ICgpID0+IE5PVyArIDIwMDAwMCxcbiAgICBycGM6IGFzeW5jICgpID0+ICh7XG4gICAgICBkYXRhOiB7XG4gICAgICAgIC4uLmxvb2t1cCgpLFxuICAgICAgICBjaGVja2VkX2F0OiBzdGFtcCgyMDAwMDApLFxuICAgICAgICBzYW1wbGVfdmFsaWRfdW50aWw6IHN0YW1wKDI2MDAwMCksXG4gICAgICB9LFxuICAgICAgZXJyb3I6IG51bGwsXG4gICAgfSksXG4gIH0pO1xuICBhc3NlcnQoXG4gICAgdi5zdGF0dXMgPT09IDIwMCAmJiB2LmNhbGxzLmxlbmd0aCA9PT0gMSAmJlxuICAgICAgdi5jYWxsc1swXS5uYW1lID09PSBcImdldF9yZWNlaXB0X2V4Y2VwdGlvbl93b3JrZXJfcmVxdWVzdF92MVwiLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJzdGFsZSBvciBjb250cmFkaWN0b3J5IGxvb2t1cCBjYW5ub3QgcHJvdmUgYWJzZW5jZSBvciBleHBvc2UgcmF3IHJlc3BvbnNlXCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCBiYWQgb2YgW1xuICAgICAgeyAuLi5sb29rdXAoXCJub3RfcmVjb3JkZWRcIiksIHNhbXBsZV92YWxpZF91bnRpbDogc3RhbXAoLTEpIH0sXG4gICAgICB7IC4uLmxvb2t1cChcIm5vdF9yZWNvcmRlZFwiKSwgcmVjZWlwdDogcmVjZWlwdCgpIH0sXG4gICAgICB7IC4uLmxvb2t1cCgpLCBjaGVja2VkX2F0OiBzdGFtcCg3MDAwKSB9LFxuICAgICAgeyAuLi5sb29rdXAoKSwgcmVjaXBpZW50OiBcInByaXZhdGVcIiB9LFxuICAgIF1cbiAgKSB7XG4gICAgY29uc3QgdiA9IGF3YWl0IGludm9rZSh7XG4gICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgYWN0aW9uOiBcInJlY29uY2lsZVwiLFxuICAgICAgcmVxdWVzdF9pZDogSUQsXG4gICAgfSwgeyBycGM6IGFzeW5jICgpID0+ICh7IGRhdGE6IGJhZCwgZXJyb3I6IG51bGwgfSkgfSk7XG4gICAgYXNzZXJ0KFxuICAgICAgdi5zdGF0dXMgPT09IDUwMyAmJiB2LmJvZHkuZXJyb3IgPT09IFwiV09SS0VSX0xPT0tVUF9VTkFWQUlMQUJMRVwiICYmXG4gICAgICAgICFKU09OLnN0cmluZ2lmeSh2LmJvZHkpLmluY2x1ZGVzKFwicHJpdmF0ZVwiKSxcbiAgICApO1xuICB9XG59KTtcbkRlbm8udGVzdChcIm1pc21hdGNoZWQgb3JpZ2luYWwgb3Igbm9uZmluaXRlIG5lc3RlZCBjb3VudGVycyBjYW5ub3QgZmFicmljYXRlIHN1Y2Nlc3NcIiwgYXN5bmMgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IGNoYW5nZSBvZiBbKHI6IFJldHVyblR5cGU8dHlwZW9mIHJlY2VpcHQ+KSA9PiB7XG4gICAgICByLmNvbmZpZ3VyYXRpb25fcmV2aXNpb24gPSAzO1xuICAgIH0sIChyOiBSZXR1cm5UeXBlPHR5cGVvZiByZWNlaXB0PikgPT4ge1xuICAgICAgci5zY2FuLnByb2Nlc3NlZCA9IDI2O1xuICAgIH0sIChyOiBSZXR1cm5UeXBlPHR5cGVvZiByZWNlaXB0PikgPT4ge1xuICAgICAgci5zY2FuLnJlZnVzZWQgPSAyO1xuICAgIH0sIChyOiBSZXR1cm5UeXBlPHR5cGVvZiByZWNlaXB0PikgPT4ge1xuICAgICAgci5lc2NhbGF0aW9uLmRlbGl2ZXJlZCA9IDIxO1xuICAgIH0sIChyOiBSZXR1cm5UeXBlPHR5cGVvZiByZWNlaXB0PikgPT4ge1xuICAgICAgci5maW5hbmNpYWxfYWN0aW9uID0gdHJ1ZTtcbiAgICB9LCAocjogUmV0dXJuVHlwZTx0eXBlb2YgcmVjZWlwdD4pID0+IHtcbiAgICAgIHIuc2Nhbi5zb3VyY2Vfc2Nhbl9jb21wbGV0ZSA9IHRydWU7XG4gICAgfV1cbiAgKSB7XG4gICAgY29uc3QgciA9IHJlY2VpcHQoKTtcbiAgICBjaGFuZ2Uocik7XG4gICAgY29uc3QgdiA9IGF3YWl0IGludm9rZShleGVjdXRlKCksIHtcbiAgICAgIHJwYzogYXN5bmMgKG5hbWUpID0+XG4gICAgICAgIG5hbWUuc3RhcnRzV2l0aChcImV4ZWN1dGVfXCIpXG4gICAgICAgICAgPyB7IGRhdGE6IHsgLi4ucmVjb3JkZWQoKSwgcmVjZWlwdDogciB9LCBlcnJvcjogbnVsbCB9XG4gICAgICAgICAgOiB7IGRhdGE6IGxvb2t1cChcIm5vdF9yZWNvcmRlZFwiKSwgZXJyb3I6IG51bGwgfSxcbiAgICB9KTtcbiAgICBhc3NlcnQoXG4gICAgICB2LnN0YXR1cyA9PT0gMjAyICYmIHYuYm9keS5zdGF0dXMgPT09IFwibm90X3JlY29yZGVkXCIgJiZcbiAgICAgICAgdi5jYWxscy5sZW5ndGggPT09IDIsXG4gICAgKTtcbiAgfVxufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FDRSw0QkFBNEIsUUFFdkIsZUFBZTtBQUN0QixNQUFNLEtBQUs7QUFDWCxNQUFNLFNBQVM7QUFDZixNQUFNLE1BQU0sS0FBSyxLQUFLLENBQUM7QUFDdkIsTUFBTSxR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
// denoCacheMetadata=12610970328013746100,16076203627891967598