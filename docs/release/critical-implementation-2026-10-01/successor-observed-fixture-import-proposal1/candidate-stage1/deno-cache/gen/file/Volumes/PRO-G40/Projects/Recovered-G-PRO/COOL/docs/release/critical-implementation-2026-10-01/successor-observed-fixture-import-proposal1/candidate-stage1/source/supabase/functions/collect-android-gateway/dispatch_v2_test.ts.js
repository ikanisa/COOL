import { assertEquals } from "../_shared/test_assert.ts";
import { createGatewayHandler } from "./handler.ts";
const DEVICE = "aa750000-0000-4000-8000-000000000001";
const REQUEST = "aa750000-0000-4000-8000-000000000002";
const ATTEMPT = "aa750000-0000-4000-8000-000000000003";
const RECEIPT = "aa750000-0000-4000-8000-000000000004";
const RUN = "aa750000-0000-4000-8000-000000000005";
const CALLBACK = "aa750000-0000-4000-8000-000000000006";
const DELIVERY = "aa750000-0000-4000-8000-000000000007";
const TARGET = "aa750000-0000-4000-8000-000000000008";
const SECOND_SENT = "aa750000-0000-4000-8000-000000000009";
const SECOND_DELIVERY = "aa750000-0000-4000-8000-000000000010";
const NOW = Date.parse("2026-10-01T12:00:00Z");
const TIME = new Date(NOW).toISOString();
const EXPIRY = new Date(NOW + 30000).toISOString();
const ENCODER = new TextEncoder();
const b64 = (bytes)=>btoa(String.fromCharCode(...bytes));
async function sha(value) {
  const bytes = typeof value === "string" ? ENCODER.encode(value) : value;
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))), (byte)=>byte.toString(16).padStart(2, "0")).join("");
}
function der(raw) {
  const parts = [
    raw.slice(0, 32),
    raw.slice(32)
  ].map((part)=>{
    while(part.length > 1 && part[0] === 0)part = part.slice(1);
    if (part[0] & 128) part = Uint8Array.from([
      0,
      ...part
    ]);
    return Uint8Array.from([
      2,
      part.length,
      ...part
    ]);
  });
  return Uint8Array.from([
    48,
    parts[0].length + parts[1].length,
    ...parts[0],
    ...parts[1]
  ]);
}
function envelope(action, payload, patch = {}) {
  return {
    contract_version: 2,
    action,
    device_id: DEVICE,
    request_id: REQUEST,
    issued_at: TIME,
    payload,
    ...patch
  };
}
function arm(patch = {}) {
  return {
    attempt_id: ATTEMPT,
    fence_version: 7,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callbacks: [
      {
        segment_index: 0,
        sent_callback_id: CALLBACK,
        delivery_callback_id: DELIVERY
      }
    ],
    reservation_sha256: "d".repeat(64),
    ...patch
  };
}
function callback(patch = {}) {
  return {
    callback_id: CALLBACK,
    attempt_id: ATTEMPT,
    fence_version: 7,
    segment_index: 0,
    segment_count: 1,
    body_sha256: "b".repeat(64),
    destination_sha256: "c".repeat(64),
    callback_kind: "sent",
    result_code: -1,
    tp_status: null,
    occurred_at: TIME,
    ...patch
  };
}
async function grant(patch = {}) {
  const body = "BuriMunsi: Ubwizigame bwa 100 RWF bwanditswe.";
  const destination = "+250788000001";
  return {
    ok: true,
    code: "DISPATCH_GRANTED",
    device_id: DEVICE,
    request_id: REQUEST,
    attempt_id: ATTEMPT,
    receipt_id: RECEIPT,
    run_id: RUN,
    fence_version: 7,
    policy_revision: 8,
    issued_at: TIME,
    expires_at: EXPIRY,
    segment_count: 1,
    body,
    destination_e164: destination,
    body_sha256: await sha(body),
    destination_sha256: await sha(destination),
    sim_revision_sha256: "e".repeat(64),
    replay: false,
    ...patch
  };
}
function armed(patch = {}) {
  return {
    ok: true,
    code: "DISPATCH_ARMED",
    device_id: DEVICE,
    request_id: REQUEST,
    attempt_id: ATTEMPT,
    fence_version: 7,
    reservation_sha256: "d".repeat(64),
    armed_at: TIME,
    expires_at: EXPIRY,
    replay: false,
    carrier_proof: false,
    ...patch
  };
}
function observed(patch = {}) {
  return {
    callback_id: CALLBACK,
    recorded_at: TIME,
    replay: false,
    carrier_proof: false,
    state: "observed_sent",
    sent_observations: 1,
    delivery_observations: 0,
    conflicting_observations: false,
    ...patch
  };
}
function status(patch = {}) {
  return {
    attempt_id: ATTEMPT,
    fence_version: 7,
    state: "observed_sent",
    armed_at: TIME,
    segment_count: 1,
    sent_observations: 1,
    delivery_observations: 0,
    conflicting_observations: false,
    terminal_archive_ack: false,
    carrier_proof: false,
    ...patch
  };
}
function refusal(code = "ORIGINAL_REQUEST_RECORDED", patch = {}) {
  return {
    ok: false,
    code,
    device_id: DEVICE,
    request_id: REQUEST,
    replay: true,
    ...patch
  };
}
async function fixture(state = "active") {
  const pair = await crypto.subtle.generateKey({
    name: "ECDSA",
    namedCurve: "P-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  const keyId = await sha(spki);
  const calls = [];
  let result = refusal();
  let error = null;
  const deps = {
    now: ()=>NOW,
    timeoutMs: 50,
    rpc: (name, args)=>{
      calls.push({
        name,
        args
      });
      if (name === "gateway_device_key_v1") {
        return Promise.resolve({
          data: {
            device_id: DEVICE,
            state,
            public_key_spki_base64: b64(spki),
            key_sha256: keyId,
            installation_id: RUN,
            signing_certificate_sha256: "f".repeat(64)
          },
          error: null
        });
      }
      return Promise.resolve({
        data: result,
        error
      });
    }
  };
  async function signed(value, text = JSON.stringify(value)) {
    const bytes = ENCODER.encode(text);
    const signature = der(new Uint8Array(await crypto.subtle.sign({
      name: "ECDSA",
      hash: "SHA-256"
    }, pair.privateKey, bytes)));
    return new Request("https://gateway.test/collect-android-gateway", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Collect-Gateway-Key-Id": keyId,
        "X-Collect-Gateway-Signature": b64(signature)
      },
      body: bytes
    });
  }
  return {
    calls,
    deps,
    signed,
    handler: createGatewayHandler(deps),
    setResult: (data)=>result = data,
    setError: (value)=>error = value
  };
}
for (const [action, payload, rpc, result] of [
  [
    "dispatch_grant",
    {},
    "gateway_dispatch_grant_v2",
    await grant()
  ],
  [
    "arm_dispatch",
    arm(),
    "gateway_arm_dispatch_v2",
    armed()
  ],
  [
    "callback",
    callback(),
    "gateway_callback_v2",
    observed()
  ],
  [
    "attempt_status",
    {
      attempt_id: ATTEMPT,
      fence_version: 7
    },
    "gateway_attempt_status_v2",
    status()
  ],
  [
    "reconcile",
    {
      target_request_id: TARGET
    },
    "gateway_reconcile_v2",
    {
      target_request_id: TARGET,
      outcome: "unknown",
      recorded_action: null,
      recorded_result: null
    }
  ]
]){
  Deno.test("v2 real P-256 signature selects exactly " + rpc, async ()=>{
    const f = await fixture();
    f.setResult(result);
    const env = envelope(action, payload);
    const response = await f.handler(await f.signed(env));
    assertEquals(response.status, 200);
    assertEquals(f.calls.map((call)=>call.name), [
      "gateway_device_key_v1",
      rpc
    ]);
    assertEquals(Object.keys(f.calls[1].args).sort(), [
      "p_device_id",
      "p_payload",
      "p_request_id",
      "p_request_sha256"
    ]);
    assertEquals(f.calls[1].args.p_payload, payload);
    assertEquals(f.calls[1].args.p_request_sha256, await sha(JSON.stringify(env)));
    const parsed = await response.json();
    assertEquals(parsed.contract_version, 2);
    assertEquals(parsed.result, result);
    assertEquals(response.headers.get("cache-control"), "no-store");
  });
}
for (const [name, action, payload, patch] of [
  [
    "v2 heartbeat",
    "heartbeat",
    {},
    {}
  ],
  [
    "v1 arm",
    "arm_dispatch",
    arm(),
    {
      contract_version: 1
    }
  ],
  [
    "v1 status",
    "attempt_status",
    {
      attempt_id: ATTEMPT,
      fence_version: 7
    },
    {
      contract_version: 1
    }
  ],
  [
    "caller grant body",
    "dispatch_grant",
    {
      body: "private"
    },
    {}
  ],
  [
    "caller arm destination",
    "arm_dispatch",
    arm({
      destination_e164: "+250788000001"
    }),
    {}
  ],
  [
    "missing reservation",
    "arm_dispatch",
    {
      ...arm(),
      reservation_sha256: undefined
    },
    {}
  ],
  [
    "uppercase reservation hash",
    "arm_dispatch",
    arm({
      reservation_sha256: "A".repeat(64)
    }),
    {}
  ],
  [
    "zero fence",
    "arm_dispatch",
    arm({
      fence_version: 0
    }),
    {}
  ],
  [
    "fractional fence",
    "attempt_status",
    {
      attempt_id: ATTEMPT,
      fence_version: 0.5
    },
    {}
  ],
  [
    "status extra fields",
    "attempt_status",
    {
      attempt_id: ATTEMPT,
      fence_version: 7,
      body: "private"
    },
    {}
  ],
  [
    "empty callbacks",
    "arm_dispatch",
    arm({
      callbacks: []
    }),
    {}
  ],
  [
    "noncontiguous callbacks",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 1,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY
        }
      ]
    }),
    {}
  ],
  [
    "fractional segment index",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 0.1,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY
        }
      ]
    }),
    {}
  ],
  [
    "callback extra field",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY,
          body: "private"
        }
      ]
    }),
    {}
  ],
  [
    "same sent and delivery UUID",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: CALLBACK.toUpperCase()
        }
      ]
    }),
    {}
  ],
  [
    "callback UUID equals request",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 0,
          sent_callback_id: REQUEST.toUpperCase(),
          delivery_callback_id: DELIVERY
        }
      ]
    }),
    {}
  ],
  [
    "callback UUID equals attempt",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: ATTEMPT.toUpperCase()
        }
      ]
    }),
    {}
  ],
  [
    "duplicate cross-segment UUID",
    "arm_dispatch",
    arm({
      callbacks: [
        {
          segment_index: 0,
          sent_callback_id: CALLBACK,
          delivery_callback_id: DELIVERY
        },
        {
          segment_index: 1,
          sent_callback_id: SECOND_SENT,
          delivery_callback_id: CALLBACK.toUpperCase()
        }
      ]
    }),
    {}
  ],
  [
    "callback request UUID case reuse",
    "callback",
    callback({
      callback_id: REQUEST.toUpperCase()
    }),
    {}
  ]
]){
  Deno.test("v2 rejects " + name + " before key lookup", async ()=>{
    const f = await fixture();
    assertEquals((await f.handler(await f.signed(envelope(action, payload, patch)))).status, 400);
    assertEquals(f.calls.length, 0);
  });
}
Deno.test("v2 valid multipart plan binds distinct sent and delivery callback IDs", async ()=>{
  const f = await fixture();
  f.setResult(armed());
  const p = arm({
    callbacks: [
      {
        segment_index: 0,
        sent_callback_id: CALLBACK,
        delivery_callback_id: DELIVERY
      },
      {
        segment_index: 1,
        sent_callback_id: SECOND_SENT,
        delivery_callback_id: SECOND_DELIVERY
      }
    ]
  });
  assertEquals((await f.handler(await f.signed(envelope("arm_dispatch", p)))).status, 200);
  assertEquals(f.calls[1].args.p_payload, p);
});
Deno.test("v2 UUID normalization preserves signed bytes and exact identity binding", async ()=>{
  const f = await fixture();
  f.setResult(armed());
  const p = arm({
    attempt_id: ATTEMPT.toUpperCase()
  });
  const env = envelope("arm_dispatch", p, {
    device_id: DEVICE.toUpperCase(),
    request_id: REQUEST.toUpperCase()
  });
  assertEquals((await f.handler(await f.signed(env))).status, 200);
  assertEquals(f.calls[1].args.p_request_sha256, await sha(JSON.stringify(env)));
});
Deno.test("v2 signature covers version and exact payload bytes", async ()=>{
  const f = await fixture();
  const original = envelope("dispatch_grant", {});
  const request = await f.signed(original);
  const tampered = new Request(request.url, {
    method: "POST",
    headers: request.headers,
    body: JSON.stringify({
      ...original,
      contract_version: 1
    })
  });
  assertEquals((await f.handler(tampered)).status, 401);
  assertEquals(f.calls.map((call)=>call.name), [
    "gateway_device_key_v1"
  ]);
});
Deno.test("v2 duplicate arm nested JSON keys fail before signature RPC", async ()=>{
  const f = await fixture();
  const env = envelope("arm_dispatch", arm());
  const text = JSON.stringify(env).replace('"segment_index":0', '"segment_index":0,"segment_index":0');
  assertEquals((await f.handler(await f.signed(env, text))).status, 400);
  assertEquals(f.calls.length, 0);
});
for (const action of [
  "dispatch_grant",
  "arm_dispatch"
]){
  Deno.test("v2 revoked device refuses " + action + " before mutation", async ()=>{
    const f = await fixture("revoked");
    assertEquals((await f.handler(await f.signed(envelope(action, action === "dispatch_grant" ? {} : arm())))).status, 403);
    assertEquals(f.calls.map((call)=>call.name), [
      "gateway_device_key_v1"
    ]);
  });
}
for (const [action, payload, result] of [
  [
    "callback",
    callback(),
    observed()
  ],
  [
    "attempt_status",
    {
      attempt_id: ATTEMPT,
      fence_version: 7
    },
    status()
  ],
  [
    "reconcile",
    {
      target_request_id: TARGET
    },
    {
      target_request_id: TARGET,
      outcome: "unknown",
      recorded_action: null,
      recorded_result: null
    }
  ]
]){
  Deno.test("v2 revoked identity may reconcile earlier " + action + " evidence", async ()=>{
    const f = await fixture("revoked");
    f.setResult(result);
    assertEquals((await f.handler(await f.signed(envelope(action, payload)))).status, 200);
    f.setError({
      code: "42501"
    });
    assertEquals((await f.handler(await f.signed(envelope(action, payload)))).status, 403);
  });
}
for (const [name, patch] of [
  [
    "body digest mismatch",
    {
      body_sha256: "0".repeat(64)
    }
  ],
  [
    "destination digest mismatch",
    {
      destination_sha256: "0".repeat(64)
    }
  ],
  [
    "grant body mutation",
    {
      body: "A different canonical receipt"
    }
  ],
  [
    "foreign destination",
    {
      destination_e164: "+256788000001"
    }
  ],
  [
    "body beyond character limit",
    {
      body: "x".repeat(1001)
    }
  ],
  [
    "lease over thirty seconds",
    {
      expires_at: new Date(NOW + 30001).toISOString()
    }
  ],
  [
    "expired authority",
    {
      issued_at: new Date(NOW - 30001).toISOString(),
      expires_at: TIME
    }
  ],
  [
    "grant replay authority",
    {
      replay: true
    }
  ],
  [
    "wrong result request",
    {
      request_id: TARGET
    }
  ],
  [
    "extra private key",
    {
      private_key: "private"
    }
  ]
]){
  Deno.test("v2 malformed grant stays redacted: " + name, async ()=>{
    const f = await fixture();
    f.setResult(await grant(patch));
    const response = await f.handler(await f.signed(envelope("dispatch_grant", {})));
    assertEquals(response.status, 502);
    assertEquals(await response.text(), '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}');
  });
}
Deno.test("v2 grant hashes full UTF8 body including supplementary Unicode", async ()=>{
  const f = await fixture();
  const body = "😀".repeat(1000);
  f.setResult(await grant({
    body,
    body_sha256: await sha(body),
    segment_count: 10
  }));
  assertEquals((await f.handler(await f.signed(envelope("dispatch_grant", {})))).status, 200);
});
for (const [name, patch] of [
  [
    "arm replay authority",
    {
      replay: true
    }
  ],
  [
    "wrong arm attempt",
    {
      attempt_id: TARGET
    }
  ],
  [
    "wrong arm fence",
    {
      fence_version: 8
    }
  ],
  [
    "wrong reservation",
    {
      reservation_sha256: "0".repeat(64)
    }
  ],
  [
    "arm carrier delivery claim",
    {
      carrier_proof: true
    }
  ],
  [
    "arm recovered body",
    {
      body: "private"
    }
  ],
  [
    "arm lease over thirty seconds",
    {
      expires_at: new Date(NOW + 30001).toISOString()
    }
  ]
]){
  Deno.test("v2 malformed arm refuses " + name, async ()=>{
    const f = await fixture();
    f.setResult(armed(patch));
    assertEquals((await f.handler(await f.signed(envelope("arm_dispatch", arm())))).status, 502);
  });
}
for (const code of [
  "OPERATIONS_PAUSED",
  "NO_CURRENT_RUN",
  "DEVICE_NOT_READY",
  "NO_ELIGIBLE_RECEIPT",
  "QUOTA_EXHAUSTED",
  "ORIGINAL_REQUEST_RECORDED"
]){
  Deno.test("v2 exact bounded dispatch refusal accepts " + code, async ()=>{
    const f = await fixture();
    f.setResult(refusal(code));
    assertEquals((await f.handler(await f.signed(envelope("dispatch_grant", {})))).status, 200);
  });
}
for (const action of [
  "dispatch_grant",
  "arm_dispatch"
]){
  Deno.test("v2 original " + action + " lookup stays redacted and cannot recover authority", async ()=>{
    const f = await fixture();
    const p = {
      target_request_id: TARGET
    };
    const result = {
      target_request_id: TARGET,
      outcome: "recorded",
      recorded_action: action,
      recorded_result: refusal("ORIGINAL_REQUEST_RECORDED", {
        request_id: TARGET
      })
    };
    f.setResult(result);
    assertEquals((await f.handler(await f.signed(envelope("reconcile", p)))).status, 200);
    f.setResult({
      ...result,
      recorded_result: action === "dispatch_grant" ? await grant({
        request_id: TARGET
      }) : armed({
        request_id: TARGET
      })
    });
    const response = await f.handler(await f.signed(envelope("reconcile", p)));
    assertEquals(response.status, 502);
    assertEquals(await response.text(), '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}');
  });
}
Deno.test("v2 lookup accepts recorded callback and attempt status, rejects nested extras", async ()=>{
  const f = await fixture();
  for (const [action, result] of [
    [
      "callback",
      observed()
    ],
    [
      "attempt_status",
      status()
    ]
  ]){
    const base = {
      target_request_id: TARGET,
      outcome: "recorded",
      recorded_action: action,
      recorded_result: result
    };
    f.setResult(base);
    assertEquals((await f.handler(await f.signed(envelope("reconcile", {
      target_request_id: TARGET
    })))).status, 200);
    f.setResult({
      ...base,
      recorded_result: {
        ...result,
        body: "private"
      }
    });
    assertEquals((await f.handler(await f.signed(envelope("reconcile", {
      target_request_id: TARGET
    })))).status, 502);
  }
});
Deno.test("v2 sent success requires every planned observation and no conflicts", async ()=>{
  const f = await fixture();
  f.setResult(observed({
    sent_observations: 1
  }));
  const p = callback({
    segment_count: 2
  });
  assertEquals((await f.handler(await f.signed(envelope("callback", p)))).status, 502);
  f.setResult(observed({
    sent_observations: 2
  }));
  assertEquals((await f.handler(await f.signed(envelope("callback", p)))).status, 200);
  f.setResult(observed({
    sent_observations: 2,
    conflicting_observations: true
  }));
  assertEquals((await f.handler(await f.signed(envelope("callback", p)))).status, 502);
  f.setResult(observed({
    state: "uncertain",
    sent_observations: 1,
    conflicting_observations: true
  }));
  assertEquals((await f.handler(await f.signed(envelope("callback", p)))).status, 200);
});
Deno.test("v2 status binds exact attempt fence and forbids fabricated archive or delivery conclusions", async ()=>{
  const f = await fixture();
  const p = {
    attempt_id: ATTEMPT,
    fence_version: 7
  };
  for (const patch of [
    {
      attempt_id: TARGET
    },
    {
      fence_version: 8
    },
    {
      terminal_archive_ack: true
    },
    {
      carrier_proof: true
    },
    {
      segment_count: 2,
      sent_observations: 1
    },
    {
      delivery_observations: 2
    },
    {
      conflicting_observations: true
    }
  ]){
    f.setResult(status(patch));
    assertEquals((await f.handler(await f.signed(envelope("attempt_status", p)))).status, 502);
  }
  f.setResult(status({
    state: "granted",
    armed_at: null,
    sent_observations: 0
  }));
  assertEquals((await f.handler(await f.signed(envelope("attempt_status", p)))).status, 200);
});
Deno.test("v2 unknown service outcome preserves request and performs no automatic retry", async ()=>{
  const f = await fixture();
  const original = f.deps.rpc;
  f.deps.rpc = (name, args, signal)=>{
    if (name === "gateway_device_key_v1") return original(name, args, signal);
    f.calls.push({
      name,
      args
    });
    return new Promise(()=>{});
  };
  const response = await f.handler(await f.signed(envelope("arm_dispatch", arm())));
  assertEquals(response.status, 504);
  assertEquals(await response.text(), '{"ok":false,"code":"GATEWAY_OUTCOME_UNKNOWN"}');
  assertEquals(f.calls.map((call)=>call.name), [
    "gateway_device_key_v1",
    "gateway_arm_dispatch_v2"
  ]);
  assertEquals(f.calls[1].args.p_request_id, REQUEST);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5L2Rpc3BhdGNoX3YyX3Rlc3QudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHsgYXNzZXJ0RXF1YWxzIH0gZnJvbSBcIi4uL19zaGFyZWQvdGVzdF9hc3NlcnQudHNcIjtcbmltcG9ydCB7IGNyZWF0ZUdhdGV3YXlIYW5kbGVyLCB0eXBlIEdhdGV3YXlEZXBlbmRlbmNpZXMgfSBmcm9tIFwiLi9oYW5kbGVyLnRzXCI7XG5cbnR5cGUgSnNvbiA9IFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xuY29uc3QgREVWSUNFID0gXCJhYTc1MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIjtcbmNvbnN0IFJFUVVFU1QgPSBcImFhNzUwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMlwiO1xuY29uc3QgQVRURU1QVCA9IFwiYWE3NTAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAzXCI7XG5jb25zdCBSRUNFSVBUID0gXCJhYTc1MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDRcIjtcbmNvbnN0IFJVTiA9IFwiYWE3NTAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA1XCI7XG5jb25zdCBDQUxMQkFDSyA9IFwiYWE3NTAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA2XCI7XG5jb25zdCBERUxJVkVSWSA9IFwiYWE3NTAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA3XCI7XG5jb25zdCBUQVJHRVQgPSBcImFhNzUwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwOFwiO1xuY29uc3QgU0VDT05EX1NFTlQgPSBcImFhNzUwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwOVwiO1xuY29uc3QgU0VDT05EX0RFTElWRVJZID0gXCJhYTc1MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMTBcIjtcbmNvbnN0IE5PVyA9IERhdGUucGFyc2UoXCIyMDI2LTEwLTAxVDEyOjAwOjAwWlwiKTtcbmNvbnN0IFRJTUUgPSBuZXcgRGF0ZShOT1cpLnRvSVNPU3RyaW5nKCk7XG5jb25zdCBFWFBJUlkgPSBuZXcgRGF0ZShOT1cgKyAzMDAwMCkudG9JU09TdHJpbmcoKTtcbmNvbnN0IEVOQ09ERVIgPSBuZXcgVGV4dEVuY29kZXIoKTtcbmNvbnN0IGI2NCA9IChieXRlczogVWludDhBcnJheSkgPT4gYnRvYShTdHJpbmcuZnJvbUNoYXJDb2RlKC4uLmJ5dGVzKSk7XG5cbmFzeW5jIGZ1bmN0aW9uIHNoYSh2YWx1ZTogc3RyaW5nIHwgVWludDhBcnJheSk6IFByb21pc2U8c3RyaW5nPiB7XG4gIGNvbnN0IGJ5dGVzID0gdHlwZW9mIHZhbHVlID09PSBcInN0cmluZ1wiID8gRU5DT0RFUi5lbmNvZGUodmFsdWUpIDogdmFsdWU7XG4gIHJldHVybiBBcnJheS5mcm9tKFxuICAgIG5ldyBVaW50OEFycmF5KFxuICAgICAgYXdhaXQgY3J5cHRvLnN1YnRsZS5kaWdlc3QoXCJTSEEtMjU2XCIsIG5ldyBVaW50OEFycmF5KGJ5dGVzKSksXG4gICAgKSxcbiAgICAoYnl0ZSkgPT4gYnl0ZS50b1N0cmluZygxNikucGFkU3RhcnQoMiwgXCIwXCIpLFxuICApLmpvaW4oXCJcIik7XG59XG5mdW5jdGlvbiBkZXIocmF3OiBVaW50OEFycmF5KTogVWludDhBcnJheSB7XG4gIGNvbnN0IHBhcnRzID0gW3Jhdy5zbGljZSgwLCAzMiksIHJhdy5zbGljZSgzMildLm1hcCgocGFydCkgPT4ge1xuICAgIHdoaWxlIChwYXJ0Lmxlbmd0aCA+IDEgJiYgcGFydFswXSA9PT0gMCkgcGFydCA9IHBhcnQuc2xpY2UoMSk7XG4gICAgaWYgKHBhcnRbMF0gJiAxMjgpIHBhcnQgPSBVaW50OEFycmF5LmZyb20oWzAsIC4uLnBhcnRdKTtcbiAgICByZXR1cm4gVWludDhBcnJheS5mcm9tKFsyLCBwYXJ0Lmxlbmd0aCwgLi4ucGFydF0pO1xuICB9KTtcbiAgcmV0dXJuIFVpbnQ4QXJyYXkuZnJvbShbXG4gICAgNDgsXG4gICAgcGFydHNbMF0ubGVuZ3RoICsgcGFydHNbMV0ubGVuZ3RoLFxuICAgIC4uLnBhcnRzWzBdLFxuICAgIC4uLnBhcnRzWzFdLFxuICBdKTtcbn1cbmZ1bmN0aW9uIGVudmVsb3BlKGFjdGlvbjogc3RyaW5nLCBwYXlsb2FkOiB1bmtub3duLCBwYXRjaDogSnNvbiA9IHt9KTogSnNvbiB7XG4gIHJldHVybiB7XG4gICAgY29udHJhY3RfdmVyc2lvbjogMixcbiAgICBhY3Rpb24sXG4gICAgZGV2aWNlX2lkOiBERVZJQ0UsXG4gICAgcmVxdWVzdF9pZDogUkVRVUVTVCxcbiAgICBpc3N1ZWRfYXQ6IFRJTUUsXG4gICAgcGF5bG9hZCxcbiAgICAuLi5wYXRjaCxcbiAgfTtcbn1cbmZ1bmN0aW9uIGFybShwYXRjaDogSnNvbiA9IHt9KTogSnNvbiB7XG4gIHJldHVybiB7XG4gICAgYXR0ZW1wdF9pZDogQVRURU1QVCxcbiAgICBmZW5jZV92ZXJzaW9uOiA3LFxuICAgIGJvZHlfc2hhMjU2OiBcImJcIi5yZXBlYXQoNjQpLFxuICAgIGRlc3RpbmF0aW9uX3NoYTI1NjogXCJjXCIucmVwZWF0KDY0KSxcbiAgICBjYWxsYmFja3M6IFt7XG4gICAgICBzZWdtZW50X2luZGV4OiAwLFxuICAgICAgc2VudF9jYWxsYmFja19pZDogQ0FMTEJBQ0ssXG4gICAgICBkZWxpdmVyeV9jYWxsYmFja19pZDogREVMSVZFUlksXG4gICAgfV0sXG4gICAgcmVzZXJ2YXRpb25fc2hhMjU2OiBcImRcIi5yZXBlYXQoNjQpLFxuICAgIC4uLnBhdGNoLFxuICB9O1xufVxuZnVuY3Rpb24gY2FsbGJhY2socGF0Y2g6IEpzb24gPSB7fSk6IEpzb24ge1xuICByZXR1cm4ge1xuICAgIGNhbGxiYWNrX2lkOiBDQUxMQkFDSyxcbiAgICBhdHRlbXB0X2lkOiBBVFRFTVBULFxuICAgIGZlbmNlX3ZlcnNpb246IDcsXG4gICAgc2VnbWVudF9pbmRleDogMCxcbiAgICBzZWdtZW50X2NvdW50OiAxLFxuICAgIGJvZHlfc2hhMjU2OiBcImJcIi5yZXBlYXQoNjQpLFxuICAgIGRlc3RpbmF0aW9uX3NoYTI1NjogXCJjXCIucmVwZWF0KDY0KSxcbiAgICBjYWxsYmFja19raW5kOiBcInNlbnRcIixcbiAgICByZXN1bHRfY29kZTogLTEsXG4gICAgdHBfc3RhdHVzOiBudWxsLFxuICAgIG9jY3VycmVkX2F0OiBUSU1FLFxuICAgIC4uLnBhdGNoLFxuICB9O1xufVxuYXN5bmMgZnVuY3Rpb24gZ3JhbnQocGF0Y2g6IEpzb24gPSB7fSk6IFByb21pc2U8SnNvbj4ge1xuICBjb25zdCBib2R5ID0gXCJCdXJpTXVuc2k6IFVid2l6aWdhbWUgYndhIDEwMCBSV0YgYndhbmRpdHN3ZS5cIjtcbiAgY29uc3QgZGVzdGluYXRpb24gPSBcIisyNTA3ODgwMDAwMDFcIjtcbiAgcmV0dXJuIHtcbiAgICBvazogdHJ1ZSxcbiAgICBjb2RlOiBcIkRJU1BBVENIX0dSQU5URURcIixcbiAgICBkZXZpY2VfaWQ6IERFVklDRSxcbiAgICByZXF1ZXN0X2lkOiBSRVFVRVNULFxuICAgIGF0dGVtcHRfaWQ6IEFUVEVNUFQsXG4gICAgcmVjZWlwdF9pZDogUkVDRUlQVCxcbiAgICBydW5faWQ6IFJVTixcbiAgICBmZW5jZV92ZXJzaW9uOiA3LFxuICAgIHBvbGljeV9yZXZpc2lvbjogOCxcbiAgICBpc3N1ZWRfYXQ6IFRJTUUsXG4gICAgZXhwaXJlc19hdDogRVhQSVJZLFxuICAgIHNlZ21lbnRfY291bnQ6IDEsXG4gICAgYm9keSxcbiAgICBkZXN0aW5hdGlvbl9lMTY0OiBkZXN0aW5hdGlvbixcbiAgICBib2R5X3NoYTI1NjogYXdhaXQgc2hhKGJvZHkpLFxuICAgIGRlc3RpbmF0aW9uX3NoYTI1NjogYXdhaXQgc2hhKGRlc3RpbmF0aW9uKSxcbiAgICBzaW1fcmV2aXNpb25fc2hhMjU2OiBcImVcIi5yZXBlYXQoNjQpLFxuICAgIHJlcGxheTogZmFsc2UsXG4gICAgLi4ucGF0Y2gsXG4gIH07XG59XG5mdW5jdGlvbiBhcm1lZChwYXRjaDogSnNvbiA9IHt9KTogSnNvbiB7XG4gIHJldHVybiB7XG4gICAgb2s6IHRydWUsXG4gICAgY29kZTogXCJESVNQQVRDSF9BUk1FRFwiLFxuICAgIGRldmljZV9pZDogREVWSUNFLFxuICAgIHJlcXVlc3RfaWQ6IFJFUVVFU1QsXG4gICAgYXR0ZW1wdF9pZDogQVRURU1QVCxcbiAgICBmZW5jZV92ZXJzaW9uOiA3LFxuICAgIHJlc2VydmF0aW9uX3NoYTI1NjogXCJkXCIucmVwZWF0KDY0KSxcbiAgICBhcm1lZF9hdDogVElNRSxcbiAgICBleHBpcmVzX2F0OiBFWFBJUlksXG4gICAgcmVwbGF5OiBmYWxzZSxcbiAgICBjYXJyaWVyX3Byb29mOiBmYWxzZSxcbiAgICAuLi5wYXRjaCxcbiAgfTtcbn1cbmZ1bmN0aW9uIG9ic2VydmVkKHBhdGNoOiBKc29uID0ge30pOiBKc29uIHtcbiAgcmV0dXJuIHtcbiAgICBjYWxsYmFja19pZDogQ0FMTEJBQ0ssXG4gICAgcmVjb3JkZWRfYXQ6IFRJTUUsXG4gICAgcmVwbGF5OiBmYWxzZSxcbiAgICBjYXJyaWVyX3Byb29mOiBmYWxzZSxcbiAgICBzdGF0ZTogXCJvYnNlcnZlZF9zZW50XCIsXG4gICAgc2VudF9vYnNlcnZhdGlvbnM6IDEsXG4gICAgZGVsaXZlcnlfb2JzZXJ2YXRpb25zOiAwLFxuICAgIGNvbmZsaWN0aW5nX29ic2VydmF0aW9uczogZmFsc2UsXG4gICAgLi4ucGF0Y2gsXG4gIH07XG59XG5mdW5jdGlvbiBzdGF0dXMocGF0Y2g6IEpzb24gPSB7fSk6IEpzb24ge1xuICByZXR1cm4ge1xuICAgIGF0dGVtcHRfaWQ6IEFUVEVNUFQsXG4gICAgZmVuY2VfdmVyc2lvbjogNyxcbiAgICBzdGF0ZTogXCJvYnNlcnZlZF9zZW50XCIsXG4gICAgYXJtZWRfYXQ6IFRJTUUsXG4gICAgc2VnbWVudF9jb3VudDogMSxcbiAgICBzZW50X29ic2VydmF0aW9uczogMSxcbiAgICBkZWxpdmVyeV9vYnNlcnZhdGlvbnM6IDAsXG4gICAgY29uZmxpY3Rpbmdfb2JzZXJ2YXRpb25zOiBmYWxzZSxcbiAgICB0ZXJtaW5hbF9hcmNoaXZlX2FjazogZmFsc2UsXG4gICAgY2Fycmllcl9wcm9vZjogZmFsc2UsXG4gICAgLi4ucGF0Y2gsXG4gIH07XG59XG5mdW5jdGlvbiByZWZ1c2FsKGNvZGUgPSBcIk9SSUdJTkFMX1JFUVVFU1RfUkVDT1JERURcIiwgcGF0Y2g6IEpzb24gPSB7fSk6IEpzb24ge1xuICByZXR1cm4ge1xuICAgIG9rOiBmYWxzZSxcbiAgICBjb2RlLFxuICAgIGRldmljZV9pZDogREVWSUNFLFxuICAgIHJlcXVlc3RfaWQ6IFJFUVVFU1QsXG4gICAgcmVwbGF5OiB0cnVlLFxuICAgIC4uLnBhdGNoLFxuICB9O1xufVxuYXN5bmMgZnVuY3Rpb24gZml4dHVyZShzdGF0ZSA9IFwiYWN0aXZlXCIpIHtcbiAgY29uc3QgcGFpciA9IGF3YWl0IGNyeXB0by5zdWJ0bGUuZ2VuZXJhdGVLZXkoXG4gICAgeyBuYW1lOiBcIkVDRFNBXCIsIG5hbWVkQ3VydmU6IFwiUC0yNTZcIiB9LFxuICAgIHRydWUsXG4gICAgW1wic2lnblwiLCBcInZlcmlmeVwiXSxcbiAgKTtcbiAgY29uc3Qgc3BraSA9IG5ldyBVaW50OEFycmF5KFxuICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuZXhwb3J0S2V5KFwic3BraVwiLCBwYWlyLnB1YmxpY0tleSksXG4gICk7XG4gIGNvbnN0IGtleUlkID0gYXdhaXQgc2hhKHNwa2kpO1xuICBjb25zdCBjYWxsczogeyBuYW1lOiBzdHJpbmc7IGFyZ3M6IEpzb24gfVtdID0gW107XG4gIGxldCByZXN1bHQ6IHVua25vd24gPSByZWZ1c2FsKCk7XG4gIGxldCBlcnJvcjogeyBjb2RlPzogc3RyaW5nIH0gfCBudWxsID0gbnVsbDtcbiAgY29uc3QgZGVwczogR2F0ZXdheURlcGVuZGVuY2llcyA9IHtcbiAgICBub3c6ICgpID0+IE5PVyxcbiAgICB0aW1lb3V0TXM6IDUwLFxuICAgIHJwYzogKG5hbWUsIGFyZ3MpID0+IHtcbiAgICAgIGNhbGxzLnB1c2goeyBuYW1lLCBhcmdzIH0pO1xuICAgICAgaWYgKG5hbWUgPT09IFwiZ2F0ZXdheV9kZXZpY2Vfa2V5X3YxXCIpIHtcbiAgICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSh7XG4gICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgZGV2aWNlX2lkOiBERVZJQ0UsXG4gICAgICAgICAgICBzdGF0ZSxcbiAgICAgICAgICAgIHB1YmxpY19rZXlfc3BraV9iYXNlNjQ6IGI2NChzcGtpKSxcbiAgICAgICAgICAgIGtleV9zaGEyNTY6IGtleUlkLFxuICAgICAgICAgICAgaW5zdGFsbGF0aW9uX2lkOiBSVU4sXG4gICAgICAgICAgICBzaWduaW5nX2NlcnRpZmljYXRlX3NoYTI1NjogXCJmXCIucmVwZWF0KDY0KSxcbiAgICAgICAgICB9LFxuICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICB9KTtcbiAgICAgIH1cbiAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoeyBkYXRhOiByZXN1bHQsIGVycm9yIH0pO1xuICAgIH0sXG4gIH07XG4gIGFzeW5jIGZ1bmN0aW9uIHNpZ25lZCh2YWx1ZTogSnNvbiwgdGV4dCA9IEpTT04uc3RyaW5naWZ5KHZhbHVlKSkge1xuICAgIGNvbnN0IGJ5dGVzID0gRU5DT0RFUi5lbmNvZGUodGV4dCk7XG4gICAgY29uc3Qgc2lnbmF0dXJlID0gZGVyKFxuICAgICAgbmV3IFVpbnQ4QXJyYXkoXG4gICAgICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuc2lnbihcbiAgICAgICAgICB7IG5hbWU6IFwiRUNEU0FcIiwgaGFzaDogXCJTSEEtMjU2XCIgfSxcbiAgICAgICAgICBwYWlyLnByaXZhdGVLZXksXG4gICAgICAgICAgYnl0ZXMsXG4gICAgICAgICksXG4gICAgICApLFxuICAgICk7XG4gICAgcmV0dXJuIG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9nYXRld2F5LnRlc3QvY29sbGVjdC1hbmRyb2lkLWdhdGV3YXlcIiwge1xuICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgIGhlYWRlcnM6IHtcbiAgICAgICAgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICAgIFwiWC1Db2xsZWN0LUdhdGV3YXktS2V5LUlkXCI6IGtleUlkLFxuICAgICAgICBcIlgtQ29sbGVjdC1HYXRld2F5LVNpZ25hdHVyZVwiOiBiNjQoc2lnbmF0dXJlKSxcbiAgICAgIH0sXG4gICAgICBib2R5OiBieXRlcyxcbiAgICB9KTtcbiAgfVxuICByZXR1cm4ge1xuICAgIGNhbGxzLFxuICAgIGRlcHMsXG4gICAgc2lnbmVkLFxuICAgIGhhbmRsZXI6IGNyZWF0ZUdhdGV3YXlIYW5kbGVyKGRlcHMpLFxuICAgIHNldFJlc3VsdDogKGRhdGE6IHVua25vd24pID0+IHJlc3VsdCA9IGRhdGEsXG4gICAgc2V0RXJyb3I6ICh2YWx1ZTogeyBjb2RlPzogc3RyaW5nIH0gfCBudWxsKSA9PiBlcnJvciA9IHZhbHVlLFxuICB9O1xufVxuXG5mb3IgKFxuICBjb25zdCBbYWN0aW9uLCBwYXlsb2FkLCBycGMsIHJlc3VsdF0gb2YgW1xuICAgIFtcImRpc3BhdGNoX2dyYW50XCIsIHt9LCBcImdhdGV3YXlfZGlzcGF0Y2hfZ3JhbnRfdjJcIiwgYXdhaXQgZ3JhbnQoKV0sXG4gICAgW1wiYXJtX2Rpc3BhdGNoXCIsIGFybSgpLCBcImdhdGV3YXlfYXJtX2Rpc3BhdGNoX3YyXCIsIGFybWVkKCldLFxuICAgIFtcImNhbGxiYWNrXCIsIGNhbGxiYWNrKCksIFwiZ2F0ZXdheV9jYWxsYmFja192MlwiLCBvYnNlcnZlZCgpXSxcbiAgICBbXG4gICAgICBcImF0dGVtcHRfc3RhdHVzXCIsXG4gICAgICB7IGF0dGVtcHRfaWQ6IEFUVEVNUFQsIGZlbmNlX3ZlcnNpb246IDcgfSxcbiAgICAgIFwiZ2F0ZXdheV9hdHRlbXB0X3N0YXR1c192MlwiLFxuICAgICAgc3RhdHVzKCksXG4gICAgXSxcbiAgICBbXCJyZWNvbmNpbGVcIiwgeyB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VUIH0sIFwiZ2F0ZXdheV9yZWNvbmNpbGVfdjJcIiwge1xuICAgICAgdGFyZ2V0X3JlcXVlc3RfaWQ6IFRBUkdFVCxcbiAgICAgIG91dGNvbWU6IFwidW5rbm93blwiLFxuICAgICAgcmVjb3JkZWRfYWN0aW9uOiBudWxsLFxuICAgICAgcmVjb3JkZWRfcmVzdWx0OiBudWxsLFxuICAgIH1dLFxuICBdIGFzIGNvbnN0XG4pIHtcbiAgRGVuby50ZXN0KFwidjIgcmVhbCBQLTI1NiBzaWduYXR1cmUgc2VsZWN0cyBleGFjdGx5IFwiICsgcnBjLCBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgICBmLnNldFJlc3VsdChyZXN1bHQpO1xuICAgIGNvbnN0IGVudiA9IGVudmVsb3BlKGFjdGlvbiwgcGF5bG9hZCk7XG4gICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52KSk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgMjAwKTtcbiAgICBhc3NlcnRFcXVhbHMoZi5jYWxscy5tYXAoKGNhbGwpID0+IGNhbGwubmFtZSksIFtcbiAgICAgIFwiZ2F0ZXdheV9kZXZpY2Vfa2V5X3YxXCIsXG4gICAgICBycGMsXG4gICAgXSk7XG4gICAgYXNzZXJ0RXF1YWxzKE9iamVjdC5rZXlzKGYuY2FsbHNbMV0uYXJncykuc29ydCgpLCBbXG4gICAgICBcInBfZGV2aWNlX2lkXCIsXG4gICAgICBcInBfcGF5bG9hZFwiLFxuICAgICAgXCJwX3JlcXVlc3RfaWRcIixcbiAgICAgIFwicF9yZXF1ZXN0X3NoYTI1NlwiLFxuICAgIF0pO1xuICAgIGFzc2VydEVxdWFscyhmLmNhbGxzWzFdLmFyZ3MucF9wYXlsb2FkLCBwYXlsb2FkKTtcbiAgICBhc3NlcnRFcXVhbHMoXG4gICAgICBmLmNhbGxzWzFdLmFyZ3MucF9yZXF1ZXN0X3NoYTI1NixcbiAgICAgIGF3YWl0IHNoYShKU09OLnN0cmluZ2lmeShlbnYpKSxcbiAgICApO1xuICAgIGNvbnN0IHBhcnNlZCA9IGF3YWl0IHJlc3BvbnNlLmpzb24oKTtcbiAgICBhc3NlcnRFcXVhbHMocGFyc2VkLmNvbnRyYWN0X3ZlcnNpb24sIDIpO1xuICAgIGFzc2VydEVxdWFscyhwYXJzZWQucmVzdWx0LCByZXN1bHQpO1xuICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5oZWFkZXJzLmdldChcImNhY2hlLWNvbnRyb2xcIiksIFwibm8tc3RvcmVcIik7XG4gIH0pO1xufVxuXG5mb3IgKFxuICBjb25zdCBbbmFtZSwgYWN0aW9uLCBwYXlsb2FkLCBwYXRjaF0gb2YgW1xuICAgIFtcInYyIGhlYXJ0YmVhdFwiLCBcImhlYXJ0YmVhdFwiLCB7fSwge31dLFxuICAgIFtcInYxIGFybVwiLCBcImFybV9kaXNwYXRjaFwiLCBhcm0oKSwgeyBjb250cmFjdF92ZXJzaW9uOiAxIH1dLFxuICAgIFtcInYxIHN0YXR1c1wiLCBcImF0dGVtcHRfc3RhdHVzXCIsIHsgYXR0ZW1wdF9pZDogQVRURU1QVCwgZmVuY2VfdmVyc2lvbjogNyB9LCB7XG4gICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgIH1dLFxuICAgIFtcImNhbGxlciBncmFudCBib2R5XCIsIFwiZGlzcGF0Y2hfZ3JhbnRcIiwgeyBib2R5OiBcInByaXZhdGVcIiB9LCB7fV0sXG4gICAgW1xuICAgICAgXCJjYWxsZXIgYXJtIGRlc3RpbmF0aW9uXCIsXG4gICAgICBcImFybV9kaXNwYXRjaFwiLFxuICAgICAgYXJtKHsgZGVzdGluYXRpb25fZTE2NDogXCIrMjUwNzg4MDAwMDAxXCIgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcIm1pc3NpbmcgcmVzZXJ2YXRpb25cIiwgXCJhcm1fZGlzcGF0Y2hcIiwge1xuICAgICAgLi4uYXJtKCksXG4gICAgICByZXNlcnZhdGlvbl9zaGEyNTY6IHVuZGVmaW5lZCxcbiAgICB9LCB7fV0sXG4gICAgW1xuICAgICAgXCJ1cHBlcmNhc2UgcmVzZXJ2YXRpb24gaGFzaFwiLFxuICAgICAgXCJhcm1fZGlzcGF0Y2hcIixcbiAgICAgIGFybSh7IHJlc2VydmF0aW9uX3NoYTI1NjogXCJBXCIucmVwZWF0KDY0KSB9KSxcbiAgICAgIHt9LFxuICAgIF0sXG4gICAgW1wiemVybyBmZW5jZVwiLCBcImFybV9kaXNwYXRjaFwiLCBhcm0oeyBmZW5jZV92ZXJzaW9uOiAwIH0pLCB7fV0sXG4gICAgW1wiZnJhY3Rpb25hbCBmZW5jZVwiLCBcImF0dGVtcHRfc3RhdHVzXCIsIHtcbiAgICAgIGF0dGVtcHRfaWQ6IEFUVEVNUFQsXG4gICAgICBmZW5jZV92ZXJzaW9uOiAwLjUsXG4gICAgfSwge31dLFxuICAgIFtcInN0YXR1cyBleHRyYSBmaWVsZHNcIiwgXCJhdHRlbXB0X3N0YXR1c1wiLCB7XG4gICAgICBhdHRlbXB0X2lkOiBBVFRFTVBULFxuICAgICAgZmVuY2VfdmVyc2lvbjogNyxcbiAgICAgIGJvZHk6IFwicHJpdmF0ZVwiLFxuICAgIH0sIHt9XSxcbiAgICBbXCJlbXB0eSBjYWxsYmFja3NcIiwgXCJhcm1fZGlzcGF0Y2hcIiwgYXJtKHsgY2FsbGJhY2tzOiBbXSB9KSwge31dLFxuICAgIFtcbiAgICAgIFwibm9uY29udGlndW91cyBjYWxsYmFja3NcIixcbiAgICAgIFwiYXJtX2Rpc3BhdGNoXCIsXG4gICAgICBhcm0oe1xuICAgICAgICBjYWxsYmFja3M6IFt7XG4gICAgICAgICAgc2VnbWVudF9pbmRleDogMSxcbiAgICAgICAgICBzZW50X2NhbGxiYWNrX2lkOiBDQUxMQkFDSyxcbiAgICAgICAgICBkZWxpdmVyeV9jYWxsYmFja19pZDogREVMSVZFUlksXG4gICAgICAgIH1dLFxuICAgICAgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiZnJhY3Rpb25hbCBzZWdtZW50IGluZGV4XCIsXG4gICAgICBcImFybV9kaXNwYXRjaFwiLFxuICAgICAgYXJtKHtcbiAgICAgICAgY2FsbGJhY2tzOiBbe1xuICAgICAgICAgIHNlZ21lbnRfaW5kZXg6IDAuMSxcbiAgICAgICAgICBzZW50X2NhbGxiYWNrX2lkOiBDQUxMQkFDSyxcbiAgICAgICAgICBkZWxpdmVyeV9jYWxsYmFja19pZDogREVMSVZFUlksXG4gICAgICAgIH1dLFxuICAgICAgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiY2FsbGJhY2sgZXh0cmEgZmllbGRcIixcbiAgICAgIFwiYXJtX2Rpc3BhdGNoXCIsXG4gICAgICBhcm0oe1xuICAgICAgICBjYWxsYmFja3M6IFt7XG4gICAgICAgICAgc2VnbWVudF9pbmRleDogMCxcbiAgICAgICAgICBzZW50X2NhbGxiYWNrX2lkOiBDQUxMQkFDSyxcbiAgICAgICAgICBkZWxpdmVyeV9jYWxsYmFja19pZDogREVMSVZFUlksXG4gICAgICAgICAgYm9keTogXCJwcml2YXRlXCIsXG4gICAgICAgIH1dLFxuICAgICAgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwic2FtZSBzZW50IGFuZCBkZWxpdmVyeSBVVUlEXCIsXG4gICAgICBcImFybV9kaXNwYXRjaFwiLFxuICAgICAgYXJtKHtcbiAgICAgICAgY2FsbGJhY2tzOiBbe1xuICAgICAgICAgIHNlZ21lbnRfaW5kZXg6IDAsXG4gICAgICAgICAgc2VudF9jYWxsYmFja19pZDogQ0FMTEJBQ0ssXG4gICAgICAgICAgZGVsaXZlcnlfY2FsbGJhY2tfaWQ6IENBTExCQUNLLnRvVXBwZXJDYXNlKCksXG4gICAgICAgIH1dLFxuICAgICAgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiY2FsbGJhY2sgVVVJRCBlcXVhbHMgcmVxdWVzdFwiLFxuICAgICAgXCJhcm1fZGlzcGF0Y2hcIixcbiAgICAgIGFybSh7XG4gICAgICAgIGNhbGxiYWNrczogW3tcbiAgICAgICAgICBzZWdtZW50X2luZGV4OiAwLFxuICAgICAgICAgIHNlbnRfY2FsbGJhY2tfaWQ6IFJFUVVFU1QudG9VcHBlckNhc2UoKSxcbiAgICAgICAgICBkZWxpdmVyeV9jYWxsYmFja19pZDogREVMSVZFUlksXG4gICAgICAgIH1dLFxuICAgICAgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiY2FsbGJhY2sgVVVJRCBlcXVhbHMgYXR0ZW1wdFwiLFxuICAgICAgXCJhcm1fZGlzcGF0Y2hcIixcbiAgICAgIGFybSh7XG4gICAgICAgIGNhbGxiYWNrczogW3tcbiAgICAgICAgICBzZWdtZW50X2luZGV4OiAwLFxuICAgICAgICAgIHNlbnRfY2FsbGJhY2tfaWQ6IENBTExCQUNLLFxuICAgICAgICAgIGRlbGl2ZXJ5X2NhbGxiYWNrX2lkOiBBVFRFTVBULnRvVXBwZXJDYXNlKCksXG4gICAgICAgIH1dLFxuICAgICAgfSksXG4gICAgICB7fSxcbiAgICBdLFxuICAgIFtcbiAgICAgIFwiZHVwbGljYXRlIGNyb3NzLXNlZ21lbnQgVVVJRFwiLFxuICAgICAgXCJhcm1fZGlzcGF0Y2hcIixcbiAgICAgIGFybSh7XG4gICAgICAgIGNhbGxiYWNrczogW1xuICAgICAgICAgIHtcbiAgICAgICAgICAgIHNlZ21lbnRfaW5kZXg6IDAsXG4gICAgICAgICAgICBzZW50X2NhbGxiYWNrX2lkOiBDQUxMQkFDSyxcbiAgICAgICAgICAgIGRlbGl2ZXJ5X2NhbGxiYWNrX2lkOiBERUxJVkVSWSxcbiAgICAgICAgICB9LFxuICAgICAgICAgIHtcbiAgICAgICAgICAgIHNlZ21lbnRfaW5kZXg6IDEsXG4gICAgICAgICAgICBzZW50X2NhbGxiYWNrX2lkOiBTRUNPTkRfU0VOVCxcbiAgICAgICAgICAgIGRlbGl2ZXJ5X2NhbGxiYWNrX2lkOiBDQUxMQkFDSy50b1VwcGVyQ2FzZSgpLFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICB9KSxcbiAgICAgIHt9LFxuICAgIF0sXG4gICAgW1xuICAgICAgXCJjYWxsYmFjayByZXF1ZXN0IFVVSUQgY2FzZSByZXVzZVwiLFxuICAgICAgXCJjYWxsYmFja1wiLFxuICAgICAgY2FsbGJhY2soeyBjYWxsYmFja19pZDogUkVRVUVTVC50b1VwcGVyQ2FzZSgpIH0pLFxuICAgICAge30sXG4gICAgXSxcbiAgXSBhcyBjb25zdFxuKSB7XG4gIERlbm8udGVzdChcInYyIHJlamVjdHMgXCIgKyBuYW1lICsgXCIgYmVmb3JlIGtleSBsb29rdXBcIiwgYXN5bmMgKCkgPT4ge1xuICAgIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShhY3Rpb24sIHBheWxvYWQsIHBhdGNoKSkpKVxuICAgICAgICAuc3RhdHVzLFxuICAgICAgNDAwLFxuICAgICk7XG4gICAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLCAwKTtcbiAgfSk7XG59XG5cbkRlbm8udGVzdChcInYyIHZhbGlkIG11bHRpcGFydCBwbGFuIGJpbmRzIGRpc3RpbmN0IHNlbnQgYW5kIGRlbGl2ZXJ5IGNhbGxiYWNrIElEc1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGYuc2V0UmVzdWx0KGFybWVkKCkpO1xuICBjb25zdCBwID0gYXJtKHtcbiAgICBjYWxsYmFja3M6IFtcbiAgICAgIHtcbiAgICAgICAgc2VnbWVudF9pbmRleDogMCxcbiAgICAgICAgc2VudF9jYWxsYmFja19pZDogQ0FMTEJBQ0ssXG4gICAgICAgIGRlbGl2ZXJ5X2NhbGxiYWNrX2lkOiBERUxJVkVSWSxcbiAgICAgIH0sXG4gICAgICB7XG4gICAgICAgIHNlZ21lbnRfaW5kZXg6IDEsXG4gICAgICAgIHNlbnRfY2FsbGJhY2tfaWQ6IFNFQ09ORF9TRU5ULFxuICAgICAgICBkZWxpdmVyeV9jYWxsYmFja19pZDogU0VDT05EX0RFTElWRVJZLFxuICAgICAgfSxcbiAgICBdLFxuICB9KTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJhcm1fZGlzcGF0Y2hcIiwgcCkpKSkuc3RhdHVzLFxuICAgIDIwMCxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHNbMV0uYXJncy5wX3BheWxvYWQsIHApO1xufSk7XG5cbkRlbm8udGVzdChcInYyIFVVSUQgbm9ybWFsaXphdGlvbiBwcmVzZXJ2ZXMgc2lnbmVkIGJ5dGVzIGFuZCBleGFjdCBpZGVudGl0eSBiaW5kaW5nXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgZi5zZXRSZXN1bHQoYXJtZWQoKSk7XG4gIGNvbnN0IHAgPSBhcm0oeyBhdHRlbXB0X2lkOiBBVFRFTVBULnRvVXBwZXJDYXNlKCkgfSk7XG4gIGNvbnN0IGVudiA9IGVudmVsb3BlKFwiYXJtX2Rpc3BhdGNoXCIsIHAsIHtcbiAgICBkZXZpY2VfaWQ6IERFVklDRS50b1VwcGVyQ2FzZSgpLFxuICAgIHJlcXVlc3RfaWQ6IFJFUVVFU1QudG9VcHBlckNhc2UoKSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscygoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudikpKS5zdGF0dXMsIDIwMCk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBmLmNhbGxzWzFdLmFyZ3MucF9yZXF1ZXN0X3NoYTI1NixcbiAgICBhd2FpdCBzaGEoSlNPTi5zdHJpbmdpZnkoZW52KSksXG4gICk7XG59KTtcblxuRGVuby50ZXN0KFwidjIgc2lnbmF0dXJlIGNvdmVycyB2ZXJzaW9uIGFuZCBleGFjdCBwYXlsb2FkIGJ5dGVzXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3Qgb3JpZ2luYWwgPSBlbnZlbG9wZShcImRpc3BhdGNoX2dyYW50XCIsIHt9KTtcbiAgY29uc3QgcmVxdWVzdCA9IGF3YWl0IGYuc2lnbmVkKG9yaWdpbmFsKTtcbiAgY29uc3QgdGFtcGVyZWQgPSBuZXcgUmVxdWVzdChyZXF1ZXN0LnVybCwge1xuICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgaGVhZGVyczogcmVxdWVzdC5oZWFkZXJzLFxuICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHsgLi4ub3JpZ2luYWwsIGNvbnRyYWN0X3ZlcnNpb246IDEgfSksXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMoKGF3YWl0IGYuaGFuZGxlcih0YW1wZXJlZCkpLnN0YXR1cywgNDAxKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubWFwKChjYWxsKSA9PiBjYWxsLm5hbWUpLCBbXCJnYXRld2F5X2RldmljZV9rZXlfdjFcIl0pO1xufSk7XG5cbkRlbm8udGVzdChcInYyIGR1cGxpY2F0ZSBhcm0gbmVzdGVkIEpTT04ga2V5cyBmYWlsIGJlZm9yZSBzaWduYXR1cmUgUlBDXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3QgZW52ID0gZW52ZWxvcGUoXCJhcm1fZGlzcGF0Y2hcIiwgYXJtKCkpO1xuICBjb25zdCB0ZXh0ID0gSlNPTi5zdHJpbmdpZnkoZW52KS5yZXBsYWNlKFxuICAgICdcInNlZ21lbnRfaW5kZXhcIjowJyxcbiAgICAnXCJzZWdtZW50X2luZGV4XCI6MCxcInNlZ21lbnRfaW5kZXhcIjowJyxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52LCB0ZXh0KSkpLnN0YXR1cywgNDAwKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHMubGVuZ3RoLCAwKTtcbn0pO1xuXG5mb3IgKGNvbnN0IGFjdGlvbiBvZiBbXCJkaXNwYXRjaF9ncmFudFwiLCBcImFybV9kaXNwYXRjaFwiXSBhcyBjb25zdCkge1xuICBEZW5vLnRlc3QoXG4gICAgXCJ2MiByZXZva2VkIGRldmljZSByZWZ1c2VzIFwiICsgYWN0aW9uICsgXCIgYmVmb3JlIG11dGF0aW9uXCIsXG4gICAgYXN5bmMgKCkgPT4ge1xuICAgICAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoXCJyZXZva2VkXCIpO1xuICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICAoYXdhaXQgZi5oYW5kbGVyKFxuICAgICAgICAgIGF3YWl0IGYuc2lnbmVkKFxuICAgICAgICAgICAgZW52ZWxvcGUoYWN0aW9uLCBhY3Rpb24gPT09IFwiZGlzcGF0Y2hfZ3JhbnRcIiA/IHt9IDogYXJtKCkpLFxuICAgICAgICAgICksXG4gICAgICAgICkpLnN0YXR1cyxcbiAgICAgICAgNDAzLFxuICAgICAgKTtcbiAgICAgIGFzc2VydEVxdWFscyhmLmNhbGxzLm1hcCgoY2FsbCkgPT4gY2FsbC5uYW1lKSwgW1wiZ2F0ZXdheV9kZXZpY2Vfa2V5X3YxXCJdKTtcbiAgICB9LFxuICApO1xufVxuZm9yIChcbiAgY29uc3QgW2FjdGlvbiwgcGF5bG9hZCwgcmVzdWx0XSBvZiBbXG4gICAgW1wiY2FsbGJhY2tcIiwgY2FsbGJhY2soKSwgb2JzZXJ2ZWQoKV0sXG4gICAgW1wiYXR0ZW1wdF9zdGF0dXNcIiwgeyBhdHRlbXB0X2lkOiBBVFRFTVBULCBmZW5jZV92ZXJzaW9uOiA3IH0sIHN0YXR1cygpXSxcbiAgICBbXCJyZWNvbmNpbGVcIiwgeyB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VUIH0sIHtcbiAgICAgIHRhcmdldF9yZXF1ZXN0X2lkOiBUQVJHRVQsXG4gICAgICBvdXRjb21lOiBcInVua25vd25cIixcbiAgICAgIHJlY29yZGVkX2FjdGlvbjogbnVsbCxcbiAgICAgIHJlY29yZGVkX3Jlc3VsdDogbnVsbCxcbiAgICB9XSxcbiAgXSBhcyBjb25zdFxuKSB7XG4gIERlbm8udGVzdChcbiAgICBcInYyIHJldm9rZWQgaWRlbnRpdHkgbWF5IHJlY29uY2lsZSBlYXJsaWVyIFwiICsgYWN0aW9uICsgXCIgZXZpZGVuY2VcIixcbiAgICBhc3luYyAoKSA9PiB7XG4gICAgICBjb25zdCBmID0gYXdhaXQgZml4dHVyZShcInJldm9rZWRcIik7XG4gICAgICBmLnNldFJlc3VsdChyZXN1bHQpO1xuICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICAoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKGFjdGlvbiwgcGF5bG9hZCkpKSkuc3RhdHVzLFxuICAgICAgICAyMDAsXG4gICAgICApO1xuICAgICAgZi5zZXRFcnJvcih7IGNvZGU6IFwiNDI1MDFcIiB9KTtcbiAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShhY3Rpb24sIHBheWxvYWQpKSkpLnN0YXR1cyxcbiAgICAgICAgNDAzLFxuICAgICAgKTtcbiAgICB9LFxuICApO1xufVxuXG5mb3IgKFxuICBjb25zdCBbbmFtZSwgcGF0Y2hdIG9mIFtcbiAgICBbXCJib2R5IGRpZ2VzdCBtaXNtYXRjaFwiLCB7IGJvZHlfc2hhMjU2OiBcIjBcIi5yZXBlYXQoNjQpIH1dLFxuICAgIFtcImRlc3RpbmF0aW9uIGRpZ2VzdCBtaXNtYXRjaFwiLCB7IGRlc3RpbmF0aW9uX3NoYTI1NjogXCIwXCIucmVwZWF0KDY0KSB9XSxcbiAgICBbXCJncmFudCBib2R5IG11dGF0aW9uXCIsIHsgYm9keTogXCJBIGRpZmZlcmVudCBjYW5vbmljYWwgcmVjZWlwdFwiIH1dLFxuICAgIFtcImZvcmVpZ24gZGVzdGluYXRpb25cIiwgeyBkZXN0aW5hdGlvbl9lMTY0OiBcIisyNTY3ODgwMDAwMDFcIiB9XSxcbiAgICBbXCJib2R5IGJleW9uZCBjaGFyYWN0ZXIgbGltaXRcIiwgeyBib2R5OiBcInhcIi5yZXBlYXQoMTAwMSkgfV0sXG4gICAgW1wibGVhc2Ugb3ZlciB0aGlydHkgc2Vjb25kc1wiLCB7XG4gICAgICBleHBpcmVzX2F0OiBuZXcgRGF0ZShOT1cgKyAzMDAwMSkudG9JU09TdHJpbmcoKSxcbiAgICB9XSxcbiAgICBbXCJleHBpcmVkIGF1dGhvcml0eVwiLCB7XG4gICAgICBpc3N1ZWRfYXQ6IG5ldyBEYXRlKE5PVyAtIDMwMDAxKS50b0lTT1N0cmluZygpLFxuICAgICAgZXhwaXJlc19hdDogVElNRSxcbiAgICB9XSxcbiAgICBbXCJncmFudCByZXBsYXkgYXV0aG9yaXR5XCIsIHsgcmVwbGF5OiB0cnVlIH1dLFxuICAgIFtcIndyb25nIHJlc3VsdCByZXF1ZXN0XCIsIHsgcmVxdWVzdF9pZDogVEFSR0VUIH1dLFxuICAgIFtcImV4dHJhIHByaXZhdGUga2V5XCIsIHsgcHJpdmF0ZV9rZXk6IFwicHJpdmF0ZVwiIH1dLFxuICBdIGFzIGNvbnN0XG4pIHtcbiAgRGVuby50ZXN0KFwidjIgbWFsZm9ybWVkIGdyYW50IHN0YXlzIHJlZGFjdGVkOiBcIiArIG5hbWUsIGFzeW5jICgpID0+IHtcbiAgICBjb25zdCBmID0gYXdhaXQgZml4dHVyZSgpO1xuICAgIGYuc2V0UmVzdWx0KGF3YWl0IGdyYW50KHBhdGNoKSk7XG4gICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoXG4gICAgICBhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImRpc3BhdGNoX2dyYW50XCIsIHt9KSksXG4gICAgKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCA1MDIpO1xuICAgIGFzc2VydEVxdWFscyhcbiAgICAgIGF3YWl0IHJlc3BvbnNlLnRleHQoKSxcbiAgICAgICd7XCJva1wiOmZhbHNlLFwiY29kZVwiOlwiR0FURVdBWV9PVVRDT01FX1VOS05PV05cIn0nLFxuICAgICk7XG4gIH0pO1xufVxuXG5EZW5vLnRlc3QoXCJ2MiBncmFudCBoYXNoZXMgZnVsbCBVVEY4IGJvZHkgaW5jbHVkaW5nIHN1cHBsZW1lbnRhcnkgVW5pY29kZVwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGNvbnN0IGJvZHkgPSBcIvCfmIBcIi5yZXBlYXQoMTAwMCk7XG4gIGYuc2V0UmVzdWx0KFxuICAgIGF3YWl0IGdyYW50KHsgYm9keSwgYm9keV9zaGEyNTY6IGF3YWl0IHNoYShib2R5KSwgc2VnbWVudF9jb3VudDogMTAgfSksXG4gICk7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiZGlzcGF0Y2hfZ3JhbnRcIiwge30pKSkpLnN0YXR1cyxcbiAgICAyMDAsXG4gICk7XG59KTtcblxuZm9yIChcbiAgY29uc3QgW25hbWUsIHBhdGNoXSBvZiBbXG4gICAgW1wiYXJtIHJlcGxheSBhdXRob3JpdHlcIiwgeyByZXBsYXk6IHRydWUgfV0sXG4gICAgW1wid3JvbmcgYXJtIGF0dGVtcHRcIiwgeyBhdHRlbXB0X2lkOiBUQVJHRVQgfV0sXG4gICAgW1wid3JvbmcgYXJtIGZlbmNlXCIsIHsgZmVuY2VfdmVyc2lvbjogOCB9XSxcbiAgICBbXCJ3cm9uZyByZXNlcnZhdGlvblwiLCB7IHJlc2VydmF0aW9uX3NoYTI1NjogXCIwXCIucmVwZWF0KDY0KSB9XSxcbiAgICBbXCJhcm0gY2FycmllciBkZWxpdmVyeSBjbGFpbVwiLCB7IGNhcnJpZXJfcHJvb2Y6IHRydWUgfV0sXG4gICAgW1wiYXJtIHJlY292ZXJlZCBib2R5XCIsIHsgYm9keTogXCJwcml2YXRlXCIgfV0sXG4gICAgW1wiYXJtIGxlYXNlIG92ZXIgdGhpcnR5IHNlY29uZHNcIiwge1xuICAgICAgZXhwaXJlc19hdDogbmV3IERhdGUoTk9XICsgMzAwMDEpLnRvSVNPU3RyaW5nKCksXG4gICAgfV0sXG4gIF0gYXMgY29uc3Rcbikge1xuICBEZW5vLnRlc3QoXCJ2MiBtYWxmb3JtZWQgYXJtIHJlZnVzZXMgXCIgKyBuYW1lLCBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgICBmLnNldFJlc3VsdChhcm1lZChwYXRjaCkpO1xuICAgIGFzc2VydEVxdWFscyhcbiAgICAgIChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJhcm1fZGlzcGF0Y2hcIiwgYXJtKCkpKSkpLnN0YXR1cyxcbiAgICAgIDUwMixcbiAgICApO1xuICB9KTtcbn1cblxuZm9yIChcbiAgY29uc3QgY29kZSBvZiBbXG4gICAgXCJPUEVSQVRJT05TX1BBVVNFRFwiLFxuICAgIFwiTk9fQ1VSUkVOVF9SVU5cIixcbiAgICBcIkRFVklDRV9OT1RfUkVBRFlcIixcbiAgICBcIk5PX0VMSUdJQkxFX1JFQ0VJUFRcIixcbiAgICBcIlFVT1RBX0VYSEFVU1RFRFwiLFxuICAgIFwiT1JJR0lOQUxfUkVRVUVTVF9SRUNPUkRFRFwiLFxuICBdXG4pIHtcbiAgRGVuby50ZXN0KFwidjIgZXhhY3QgYm91bmRlZCBkaXNwYXRjaCByZWZ1c2FsIGFjY2VwdHMgXCIgKyBjb2RlLCBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgICBmLnNldFJlc3VsdChyZWZ1c2FsKGNvZGUpKTtcbiAgICBhc3NlcnRFcXVhbHMoXG4gICAgICAoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiZGlzcGF0Y2hfZ3JhbnRcIiwge30pKSkpLnN0YXR1cyxcbiAgICAgIDIwMCxcbiAgICApO1xuICB9KTtcbn1cblxuZm9yIChjb25zdCBhY3Rpb24gb2YgW1wiZGlzcGF0Y2hfZ3JhbnRcIiwgXCJhcm1fZGlzcGF0Y2hcIl0gYXMgY29uc3QpIHtcbiAgRGVuby50ZXN0KFxuICAgIFwidjIgb3JpZ2luYWwgXCIgKyBhY3Rpb24gK1xuICAgICAgXCIgbG9va3VwIHN0YXlzIHJlZGFjdGVkIGFuZCBjYW5ub3QgcmVjb3ZlciBhdXRob3JpdHlcIixcbiAgICBhc3luYyAoKSA9PiB7XG4gICAgICBjb25zdCBmID0gYXdhaXQgZml4dHVyZSgpO1xuICAgICAgY29uc3QgcCA9IHsgdGFyZ2V0X3JlcXVlc3RfaWQ6IFRBUkdFVCB9O1xuICAgICAgY29uc3QgcmVzdWx0ID0ge1xuICAgICAgICB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VULFxuICAgICAgICBvdXRjb21lOiBcInJlY29yZGVkXCIsXG4gICAgICAgIHJlY29yZGVkX2FjdGlvbjogYWN0aW9uLFxuICAgICAgICByZWNvcmRlZF9yZXN1bHQ6IHJlZnVzYWwoXCJPUklHSU5BTF9SRVFVRVNUX1JFQ09SREVEXCIsIHtcbiAgICAgICAgICByZXF1ZXN0X2lkOiBUQVJHRVQsXG4gICAgICAgIH0pLFxuICAgICAgfTtcbiAgICAgIGYuc2V0UmVzdWx0KHJlc3VsdCk7XG4gICAgICBhc3NlcnRFcXVhbHMoXG4gICAgICAgIChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIiwgcCkpKSkuc3RhdHVzLFxuICAgICAgICAyMDAsXG4gICAgICApO1xuICAgICAgZi5zZXRSZXN1bHQoe1xuICAgICAgICAuLi5yZXN1bHQsXG4gICAgICAgIHJlY29yZGVkX3Jlc3VsdDogYWN0aW9uID09PSBcImRpc3BhdGNoX2dyYW50XCJcbiAgICAgICAgICA/IGF3YWl0IGdyYW50KHsgcmVxdWVzdF9pZDogVEFSR0VUIH0pXG4gICAgICAgICAgOiBhcm1lZCh7IHJlcXVlc3RfaWQ6IFRBUkdFVCB9KSxcbiAgICAgIH0pO1xuICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIoXG4gICAgICAgIGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwicmVjb25jaWxlXCIsIHApKSxcbiAgICAgICk7XG4gICAgICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCA1MDIpO1xuICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICBhd2FpdCByZXNwb25zZS50ZXh0KCksXG4gICAgICAgICd7XCJva1wiOmZhbHNlLFwiY29kZVwiOlwiR0FURVdBWV9PVVRDT01FX1VOS05PV05cIn0nLFxuICAgICAgKTtcbiAgICB9LFxuICApO1xufVxuXG5EZW5vLnRlc3QoXCJ2MiBsb29rdXAgYWNjZXB0cyByZWNvcmRlZCBjYWxsYmFjayBhbmQgYXR0ZW1wdCBzdGF0dXMsIHJlamVjdHMgbmVzdGVkIGV4dHJhc1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGZvciAoXG4gICAgY29uc3QgW2FjdGlvbiwgcmVzdWx0XSBvZiBbW1wiY2FsbGJhY2tcIiwgb2JzZXJ2ZWQoKV0sIFtcbiAgICAgIFwiYXR0ZW1wdF9zdGF0dXNcIixcbiAgICAgIHN0YXR1cygpLFxuICAgIF1dIGFzIGNvbnN0XG4gICkge1xuICAgIGNvbnN0IGJhc2UgPSB7XG4gICAgICB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VULFxuICAgICAgb3V0Y29tZTogXCJyZWNvcmRlZFwiLFxuICAgICAgcmVjb3JkZWRfYWN0aW9uOiBhY3Rpb24sXG4gICAgICByZWNvcmRlZF9yZXN1bHQ6IHJlc3VsdCxcbiAgICB9O1xuICAgIGYuc2V0UmVzdWx0KGJhc2UpO1xuICAgIGFzc2VydEVxdWFscyhcbiAgICAgIChhd2FpdCBmLmhhbmRsZXIoXG4gICAgICAgIGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwicmVjb25jaWxlXCIsIHsgdGFyZ2V0X3JlcXVlc3RfaWQ6IFRBUkdFVCB9KSksXG4gICAgICApKS5zdGF0dXMsXG4gICAgICAyMDAsXG4gICAgKTtcbiAgICBmLnNldFJlc3VsdCh7IC4uLmJhc2UsIHJlY29yZGVkX3Jlc3VsdDogeyAuLi5yZXN1bHQsIGJvZHk6IFwicHJpdmF0ZVwiIH0gfSk7XG4gICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgKGF3YWl0IGYuaGFuZGxlcihcbiAgICAgICAgYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJyZWNvbmNpbGVcIiwgeyB0YXJnZXRfcmVxdWVzdF9pZDogVEFSR0VUIH0pKSxcbiAgICAgICkpLnN0YXR1cyxcbiAgICAgIDUwMixcbiAgICApO1xuICB9XG59KTtcblxuRGVuby50ZXN0KFwidjIgc2VudCBzdWNjZXNzIHJlcXVpcmVzIGV2ZXJ5IHBsYW5uZWQgb2JzZXJ2YXRpb24gYW5kIG5vIGNvbmZsaWN0c1wiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBhd2FpdCBmaXh0dXJlKCk7XG4gIGYuc2V0UmVzdWx0KG9ic2VydmVkKHsgc2VudF9vYnNlcnZhdGlvbnM6IDEgfSkpO1xuICBjb25zdCBwID0gY2FsbGJhY2soeyBzZWdtZW50X2NvdW50OiAyIH0pO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImNhbGxiYWNrXCIsIHApKSkpLnN0YXR1cyxcbiAgICA1MDIsXG4gICk7XG4gIGYuc2V0UmVzdWx0KG9ic2VydmVkKHsgc2VudF9vYnNlcnZhdGlvbnM6IDIgfSkpO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImNhbGxiYWNrXCIsIHApKSkpLnN0YXR1cyxcbiAgICAyMDAsXG4gICk7XG4gIGYuc2V0UmVzdWx0KFxuICAgIG9ic2VydmVkKHsgc2VudF9vYnNlcnZhdGlvbnM6IDIsIGNvbmZsaWN0aW5nX29ic2VydmF0aW9uczogdHJ1ZSB9KSxcbiAgKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBmLmhhbmRsZXIoYXdhaXQgZi5zaWduZWQoZW52ZWxvcGUoXCJjYWxsYmFja1wiLCBwKSkpKS5zdGF0dXMsXG4gICAgNTAyLFxuICApO1xuICBmLnNldFJlc3VsdChcbiAgICBvYnNlcnZlZCh7XG4gICAgICBzdGF0ZTogXCJ1bmNlcnRhaW5cIixcbiAgICAgIHNlbnRfb2JzZXJ2YXRpb25zOiAxLFxuICAgICAgY29uZmxpY3Rpbmdfb2JzZXJ2YXRpb25zOiB0cnVlLFxuICAgIH0pLFxuICApO1xuICBhc3NlcnRFcXVhbHMoXG4gICAgKGF3YWl0IGYuaGFuZGxlcihhd2FpdCBmLnNpZ25lZChlbnZlbG9wZShcImNhbGxiYWNrXCIsIHApKSkpLnN0YXR1cyxcbiAgICAyMDAsXG4gICk7XG59KTtcblxuRGVuby50ZXN0KFwidjIgc3RhdHVzIGJpbmRzIGV4YWN0IGF0dGVtcHQgZmVuY2UgYW5kIGZvcmJpZHMgZmFicmljYXRlZCBhcmNoaXZlIG9yIGRlbGl2ZXJ5IGNvbmNsdXNpb25zXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3QgcCA9IHsgYXR0ZW1wdF9pZDogQVRURU1QVCwgZmVuY2VfdmVyc2lvbjogNyB9O1xuICBmb3IgKFxuICAgIGNvbnN0IHBhdGNoIG9mIFtcbiAgICAgIHsgYXR0ZW1wdF9pZDogVEFSR0VUIH0sXG4gICAgICB7IGZlbmNlX3ZlcnNpb246IDggfSxcbiAgICAgIHsgdGVybWluYWxfYXJjaGl2ZV9hY2s6IHRydWUgfSxcbiAgICAgIHsgY2Fycmllcl9wcm9vZjogdHJ1ZSB9LFxuICAgICAgeyBzZWdtZW50X2NvdW50OiAyLCBzZW50X29ic2VydmF0aW9uczogMSB9LFxuICAgICAgeyBkZWxpdmVyeV9vYnNlcnZhdGlvbnM6IDIgfSxcbiAgICAgIHsgY29uZmxpY3Rpbmdfb2JzZXJ2YXRpb25zOiB0cnVlIH0sXG4gICAgXVxuICApIHtcbiAgICBmLnNldFJlc3VsdChzdGF0dXMocGF0Y2gpKTtcbiAgICBhc3NlcnRFcXVhbHMoXG4gICAgICAoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiYXR0ZW1wdF9zdGF0dXNcIiwgcCkpKSkuc3RhdHVzLFxuICAgICAgNTAyLFxuICAgICk7XG4gIH1cbiAgZi5zZXRSZXN1bHQoXG4gICAgc3RhdHVzKHsgc3RhdGU6IFwiZ3JhbnRlZFwiLCBhcm1lZF9hdDogbnVsbCwgc2VudF9vYnNlcnZhdGlvbnM6IDAgfSksXG4gICk7XG4gIGFzc2VydEVxdWFscyhcbiAgICAoYXdhaXQgZi5oYW5kbGVyKGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiYXR0ZW1wdF9zdGF0dXNcIiwgcCkpKSkuc3RhdHVzLFxuICAgIDIwMCxcbiAgKTtcbn0pO1xuXG5EZW5vLnRlc3QoXCJ2MiB1bmtub3duIHNlcnZpY2Ugb3V0Y29tZSBwcmVzZXJ2ZXMgcmVxdWVzdCBhbmQgcGVyZm9ybXMgbm8gYXV0b21hdGljIHJldHJ5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGF3YWl0IGZpeHR1cmUoKTtcbiAgY29uc3Qgb3JpZ2luYWwgPSBmLmRlcHMucnBjO1xuICBmLmRlcHMucnBjID0gKG5hbWUsIGFyZ3MsIHNpZ25hbCkgPT4ge1xuICAgIGlmIChuYW1lID09PSBcImdhdGV3YXlfZGV2aWNlX2tleV92MVwiKSByZXR1cm4gb3JpZ2luYWwobmFtZSwgYXJncywgc2lnbmFsKTtcbiAgICBmLmNhbGxzLnB1c2goeyBuYW1lLCBhcmdzIH0pO1xuICAgIHJldHVybiBuZXcgUHJvbWlzZSgoKSA9PiB7fSk7XG4gIH07XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKFxuICAgIGF3YWl0IGYuc2lnbmVkKGVudmVsb3BlKFwiYXJtX2Rpc3BhdGNoXCIsIGFybSgpKSksXG4gICk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDUwNCk7XG4gIGFzc2VydEVxdWFscyhcbiAgICBhd2FpdCByZXNwb25zZS50ZXh0KCksXG4gICAgJ3tcIm9rXCI6ZmFsc2UsXCJjb2RlXCI6XCJHQVRFV0FZX09VVENPTUVfVU5LTk9XTlwifScsXG4gICk7XG4gIGFzc2VydEVxdWFscyhmLmNhbGxzLm1hcCgoY2FsbCkgPT4gY2FsbC5uYW1lKSwgW1xuICAgIFwiZ2F0ZXdheV9kZXZpY2Vfa2V5X3YxXCIsXG4gICAgXCJnYXRld2F5X2FybV9kaXNwYXRjaF92MlwiLFxuICBdKTtcbiAgYXNzZXJ0RXF1YWxzKGYuY2FsbHNbMV0uYXJncy5wX3JlcXVlc3RfaWQsIFJFUVVFU1QpO1xufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxZQUFZLFFBQVEsNEJBQTRCO0FBQ3pELFNBQVMsb0JBQW9CLFFBQWtDLGVBQWU7QUFHOUUsTUFBTSxTQUFT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
// denoCacheMetadata=18095259167808486867,2105570011548062821