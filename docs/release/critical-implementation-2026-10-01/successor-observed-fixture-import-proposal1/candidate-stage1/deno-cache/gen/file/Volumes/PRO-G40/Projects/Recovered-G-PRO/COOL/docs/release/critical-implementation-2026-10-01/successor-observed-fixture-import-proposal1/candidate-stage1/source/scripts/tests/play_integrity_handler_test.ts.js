/** Real handler, Auth client and PostgREST transport; synthetic strict fetch
 * doubles only. No --allow-net and no provider/hosted credentials or calls. */ import { assertEquals } from "../../supabase/functions/_shared/test_assert.ts";
import { sha256Hex, smsIntegrityRequestHash } from "../../supabase/functions/_shared/play_integrity_binding.ts";
const actor = "99570000-0000-4000-8000-000000000001";
const session = "99570000-0000-4000-8000-000000000011";
const nonce = "99570000-0000-4000-8000-000000000031";
const reservation = "99570000-0000-4000-8000-000000000041";
const capability = "99570000-0000-4000-8000-000000000051";
const receiver = "a".repeat(64);
const envNames = [
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON",
  "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
  "PLAY_INTEGRITY_MIN_VERSION_CODE",
  "PLAY_INTEGRITY_CERTIFICATE_SHA256"
];
function jwt(claims) {
  return "Bearer e30." + btoa(JSON.stringify(claims)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "") + ".synthetic";
}
const authorization = jwt({
  sub: actor,
  session_id: session,
  role: "authenticated"
});
const oauth = "https://oauth2.googleapis.com/token";
const decode = "https://playintegrity.googleapis.com/v1/app.cool.mobile:decodeIntegrityToken";
Deno.test("Integrity admission real-handler transport contract (offline strict doubles)", async (t)=>{
  const originals = envNames.map((name)=>Deno.env.get(name));
  const originalFetch = globalThis.fetch, originalServe = Deno.serve;
  // Actual Supabase Auth clients install auto-refresh timers. Release only
  // timers created by this isolated fixture; keep Deno leak checks enabled.
  const originalInterval = globalThis.setInterval;
  const intervals = [];
  globalThis.setInterval = (...args)=>{
    const id = originalInterval(...args);
    intervals.push(id);
    return id;
  };
  let handler = ()=>{
    throw new Error("handler missing");
  };
  const keys = await crypto.subtle.generateKey({
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([
      1,
      0,
      1
    ]),
    hash: "SHA-256"
  }, true, [
    "sign",
    "verify"
  ]);
  const keyBytes = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey));
  const pem = "-----BEGIN PRIVATE KEY-----\n" + btoa(String.fromCharCode(...keyBytes)) + "\n-----END PRIVATE KEY-----";
  const account = JSON.stringify({
    client_email: "synthetic@example.test",
    private_key: pem,
    token_uri: "https://forbidden.invalid"
  });
  const values = [
    "https://backend.invalid",
    "synthetic-anon",
    "synthetic-service",
    account,
    "",
    "23",
    "CERT"
  ];
  envNames.forEach((name, i)=>Deno.env.set(name, values[i]));
  Object.defineProperty(Deno, "serve", {
    value: (fn)=>{
      handler = fn;
    },
    configurable: true,
    writable: true
  });
  try {
    await import("../../supabase/functions/verify-play-integrity/index.ts");
    const setup = async (options = {})=>{
      const sms = {
        subjectId: actor,
        nonce,
        receiverMomoNumberHash: receiver,
        clientEnvelopeId: "99570000-0000-4000-8000-000000000061",
        rawSender: "M-Money",
        rawBodySha256: "b".repeat(64),
        receivedAtDevice: null
      };
      const requestHash = await smsIntegrityRequestHash(sms);
      const payload = {
        action: "sms.ingest",
        subject_id: actor,
        nonce,
        sms_permission_granted: true,
        sms_access_enabled: true,
        request_hash: requestHash,
        receiver_momo_number_hash: receiver,
        integrity_token: "synthetic-integrity-token",
        sms_request: {
          client_envelope_id: sms.clientEnvelopeId,
          raw_sender: sms.rawSender,
          raw_body_sha256: sms.rawBodySha256,
          received_at_device: null
        }
      };
      let oauthStarted = false, decodeStarted = false, completed = options.completed === true, terminal = false;
      const calls = [];
      const capabilityExpiresAt = new Date(Date.now() + 240000).toISOString();
      const result = ()=>({
          status: "pass",
          action: payload.action,
          request_hash: payload.request_hash,
          package_name: "app.cool.mobile",
          app_verdict: "PLAY_RECOGNIZED",
          device_verdicts: [
            "MEETS_DEVICE_INTEGRITY"
          ],
          native_capability: capability,
          capability_expires_at: capabilityExpiresAt
        });
      const receipt = async (state)=>({
          contract_version: 1,
          reservation_id: reservation,
          actor_id: actor,
          session_id: session,
          nonce,
          action: payload.action,
          request_hash: payload.request_hash,
          token_sha256: await sha256Hex(String(payload.integrity_token)),
          state,
          can_call: state !== "completed",
          expires_at: new Date(Date.now() + 180000).toISOString(),
          result: state === "completed" ? result() : null
        });
      const failure = (code)=>new Response(JSON.stringify({
          code,
          message: "private SQL and token details"
        }), {
          status: 400,
          headers: {
            "content-type": "application/json"
          }
        });
      globalThis.fetch = async (input, init)=>{
        const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
        const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
        if (url === "https://backend.invalid/auth/v1/user") {
          calls.push({
            url
          });
          assertEquals(headers.get("apikey"), "synthetic-anon");
          if (options.authDenied) {
            return new Response('{"msg":"denied"}', {
              status: 401
            });
          }
          return new Response(JSON.stringify({
            id: actor,
            aud: "authenticated",
            role: "authenticated",
            email: "synthetic@example.test"
          }), {
            headers: {
              "content-type": "application/json"
            }
          });
        }
        if (url.startsWith("https://backend.invalid/rest/v1/rpc/")) {
          assertEquals(headers.get("apikey"), "synthetic-service");
          if (!init?.signal) throw new Error("RPC lacks bounded abort signal");
          const params = JSON.parse(String(init.body));
          calls.push({
            url,
            params
          });
          assertEquals(params.p_actor_id, actor);
          assertEquals(params.p_session_id, session);
          const name = url.split("/").at(-1);
          let value;
          if (name === "reserve_play_integrity_admission_v1") {
            assertEquals(params.p_token_sha256, await sha256Hex(String(payload.integrity_token)));
            assertEquals(params.p_request_hash, payload.request_hash);
            if (options.reserveError) {
              return failure(String(options.reserveError));
            }
            if (terminal || !completed && oauthStarted) {
              return failure("55000");
            }
            value = await receipt(completed ? "completed" : "reserved");
            if (options.forgedReceipt) {
              value = {
                ...value,
                session_id: capability
              };
            }
          } else if (name === "begin_play_integrity_admission_v1") {
            assertEquals(params.p_reservation_id, reservation);
            if (options.beginError || options.decodeDenied && params.p_phase === "decode") return failure("42501");
            if (params.p_phase === "oauth") {
              if (oauthStarted) return failure("55000");
              oauthStarted = true;
            } else {
              assertEquals(params.p_phase, "decode");
              assertEquals(oauthStarted, true);
              if (decodeStarted) return failure("55000");
              decodeStarted = true;
            }
            value = await receipt(params.p_phase + "_started");
          } else if (name === "complete_play_integrity_admission_v1") {
            assertEquals(oauthStarted, true);
            assertEquals(decodeStarted, true);
            assertEquals(params.p_provider_status, 200);
            assertEquals(Number.isInteger(params.p_decode_duration_ms), true);
            if (options.completeDenied) return failure("42501");
            completed = true;
            if (options.lostCompletionAck) {
              return new Response('{"code":"PGRST999","message":"lost acknowledgement"}', {
                status: 503
              });
            }
            value = result();
          } else if (name === "finish_play_integrity_admission_v1") {
            assertEquals([
              "ambiguous",
              "rejected"
            ].includes(String(params.p_outcome)), true);
            if (!completed) terminal = true;
            value = {
              ok: true,
              state: completed ? "completed" : params.p_outcome
            };
          } else throw new Error("Unexpected RPC " + name);
          return new Response(JSON.stringify(value), {
            headers: {
              "content-type": "application/json"
            }
          });
        }
        if (url === oauth || url === decode) {
          calls.push({
            url
          });
          assertEquals(init?.redirect, "error");
          assertEquals(Boolean(init?.signal), true);
          assertEquals(oauthStarted, true);
          if (url === oauth) {
            const form = new URLSearchParams(String(init?.body));
            assertEquals(form.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
            const claim = JSON.parse(atob(String(form.get("assertion")).split(".")[1].replaceAll("-", "+").replaceAll("_", "/")));
            assertEquals(claim.aud, oauth);
            assertEquals(claim.scope, "https://www.googleapis.com/auth/playintegrity");
            if (options.oauthFailure) {
              return new Response('{"error":"private provider failure"}', {
                status: 429
              });
            }
            return new Response('{"access_token":"synthetic-access"}');
          }
          assertEquals(decodeStarted, true);
          assertEquals(headers.get("authorization"), "Bearer synthetic-access");
          assertEquals(JSON.parse(String(init?.body)).integrityToken, payload.integrity_token);
          if (options.timeout) {
            throw new DOMException("synthetic abort", "AbortError");
          }
          if (options.decodeFailure) {
            return new Response('{"private":"provider body"}', {
              status: 429
            });
          }
          if (options.malformedProvider) {
            return new Response('{"tokenPayloadExternal":null}');
          }
          return new Response(JSON.stringify({
            tokenPayloadExternal: {
              requestDetails: {
                requestPackageName: "app.cool.mobile",
                requestHash: payload.request_hash,
                timestampMillis: String(Date.now())
              },
              appIntegrity: {
                packageName: "app.cool.mobile",
                appRecognitionVerdict: "PLAY_RECOGNIZED",
                versionCode: options.oldVersion ? "22" : "23",
                certificateSha256Digest: [
                  options.badCertificate ? "OTHER" : "CERT"
                ]
              },
              accountDetails: {
                appLicensingVerdict: options.unlicensed ? "UNLICENSED" : "LICENSED"
              },
              deviceIntegrity: {
                deviceRecognitionVerdict: [
                  options.weakDevice ? "MEETS_BASIC_INTEGRITY" : "MEETS_DEVICE_INTEGRITY"
                ]
              }
            }
          }));
        }
        throw new Error("Network URL outside strict mock " + url);
      };
      const send = (auth = authorization, body = payload)=>handler(new Request("https://edge.invalid/verify-play-integrity", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            ...auth ? {
              authorization: auth
            } : {}
          },
          body: JSON.stringify(body)
        }));
      return {
        payload,
        calls,
        send,
        result,
        google: ()=>calls.filter((c)=>c.url === oauth || c.url === decode),
        rpcs: ()=>calls.filter((c)=>c.params)
      };
    };
    for (const [label, auth, options] of [
      [
        "missing bearer",
        null,
        {}
      ],
      [
        "Auth denies supplied bearer",
        authorization,
        {
          authDenied: true
        }
      ],
      [
        "missing session",
        jwt({
          sub: actor,
          role: "authenticated"
        }),
        {}
      ],
      [
        "subject substitution",
        jwt({
          sub: capability,
          session_id: session,
          role: "authenticated"
        }),
        {}
      ],
      [
        "service claim",
        jwt({
          sub: actor,
          session_id: session,
          role: "service_role"
        }),
        {}
      ]
    ]){
      await t.step(label + " denies before Google and service RPC", async ()=>{
        const d = await setup(options);
        const response = await d.send(auth);
        assertEquals(response.status, 401);
        assertEquals(d.google().length, 0);
        assertEquals(d.rpcs().length, 0);
      });
    }
    for (const [label, mutation, status] of [
      [
        "oversized request",
        {
          padding: "x".repeat(33000)
        },
        413
      ],
      [
        "binding mismatch",
        {
          request_hash: "c".repeat(64)
        },
        400
      ],
      [
        "malformed nonce",
        {
          nonce: "not-a-uuid"
        },
        400
      ],
      [
        "incorrect subject",
        {
          subject_id: capability
        },
        400
      ],
      [
        "permission missing",
        {
          sms_permission_granted: false
        },
        400
      ]
    ]){
      await t.step(label + " denies before admission or Google", async ()=>{
        const d = await setup();
        const response = await d.send(authorization, {
          ...d.payload,
          ...mutation
        });
        assertEquals(response.status, status);
        assertEquals(d.google().length, 0);
        assertEquals(d.rpcs().length, 0);
      });
    }
    for (const [label, code, status] of [
      [
        "per-actor quota",
        "53300",
        429
      ],
      [
        "global quota",
        "53300",
        429
      ],
      [
        "stale or revoked session",
        "42501",
        403
      ],
      [
        "malformed SQL binding",
        "22023",
        400
      ],
      [
        "replayed or uncertain request",
        "55000",
        409
      ],
      [
        "missing migration RPC",
        "PGRST202",
        503
      ]
    ]){
      await t.step(label + " produces stable pre-Google denial", async ()=>{
        const d = await setup({
          reserveError: code
        });
        const response = await d.send();
        assertEquals(response.status, status);
        assertEquals(d.google().length, 0);
        assertEquals((await response.text()).includes("private"), false);
      });
    }
    await t.step("forged reservation receipt cannot authorize external work", async ()=>{
      const d = await setup({
        forgedReceipt: true
      });
      const response = await d.send();
      assertEquals(response.status, 503);
      assertEquals(d.google().length, 0);
    });
    await t.step("OAuth admission rejection makes zero provider calls", async ()=>{
      const d = await setup({
        beginError: true
      });
      assertEquals((await d.send()).status, 403);
      assertEquals(d.google().length, 0);
    });
    await t.step("revocation between OAuth and decode blocks decode", async ()=>{
      const d = await setup({
        decodeDenied: true
      });
      assertEquals((await d.send()).status, 403);
      assertEquals(d.google().map((c)=>c.url), [
        oauth
      ]);
    });
    await t.step("normal authorized workflow performs only two admitted fixed Google calls", async ()=>{
      const d = await setup();
      const response = await d.send();
      assertEquals(response.status, 200);
      assertEquals(await response.json(), d.result());
      assertEquals(d.google().map((c)=>c.url), [
        oauth,
        decode
      ]);
      assertEquals(d.rpcs().map((c)=>c.url.split("/").at(-1)), [
        "reserve_play_integrity_admission_v1",
        "begin_play_integrity_admission_v1",
        "begin_play_integrity_admission_v1",
        "complete_play_integrity_admission_v1"
      ]);
    });
    await t.step("completed exact-action reconciliation returns capability without re-decoding", async ()=>{
      const d = await setup({
        completed: true
      });
      const response = await d.send();
      assertEquals(response.status, 200);
      assertEquals(await response.json(), d.result());
      assertEquals(d.google().length, 0);
    });
    for (const option of [
      "unlicensed",
      "oldVersion",
      "badCertificate",
      "weakDevice"
    ]){
      await t.step(option + " remains rejected after admission without mint", async ()=>{
        const d = await setup({
          [option]: true
        });
        assertEquals((await d.send()).status, 403);
        assertEquals(d.rpcs().some((c)=>c.url.endsWith("complete_play_integrity_admission_v1")), false);
        assertEquals(d.rpcs().at(-1)?.params?.p_outcome, "rejected");
      });
    }
    for (const option of [
      "oauthFailure",
      "decodeFailure",
      "timeout",
      "malformedProvider"
    ]){
      await t.step(option + " retains terminal/unknown evidence and never auto-retries token", async ()=>{
        const d = await setup({
          [option]: true
        });
        const response = await d.send();
        assertEquals(response.status >= 400, true);
        assertEquals((await response.text()).includes("private"), false);
        const count = d.google().length;
        assertEquals(count, option === "oauthFailure" ? 1 : 2);
        assertEquals((await d.send()).status, 409);
        assertEquals(d.google().length, count);
        assertEquals(d.rpcs().some((c)=>c.url.endsWith("complete_play_integrity_admission_v1")), false);
      });
    }
    await t.step("uncertain successful completion reconciles original capability without second Google decode", async ()=>{
      const d = await setup({
        lostCompletionAck: true
      });
      assertEquals((await d.send()).status, 503);
      const response = await d.send();
      assertEquals(response.status, 200);
      assertEquals(await response.json(), d.result());
      assertEquals(d.google().length, 2);
    });
    await t.step("post-provider revocation cannot mint", async ()=>{
      const d = await setup({
        completeDenied: true
      });
      assertEquals((await d.send()).status, 403);
      assertEquals(d.google().length, 2);
      assertEquals(d.rpcs().at(-1)?.params?.p_outcome, "ambiguous");
    });
    await t.step("missing or malformed configuration fails before reservation and Google", async ()=>{
      for (const value of [
        "",
        "malformed",
        JSON.stringify({
          client_email: null
        })
      ]){
        const d = await setup();
        Deno.env.set("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON", value);
        const response = await d.send();
        assertEquals(response.status, 503);
        assertEquals(d.google().length, 0);
        assertEquals(d.rpcs().length, 0);
      }
      Deno.env.set("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON", account);
    });
  } finally{
    intervals.forEach((id)=>clearInterval(id));
    globalThis.setInterval = originalInterval;
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", {
      value: originalServe,
      configurable: true,
      writable: true
    });
    envNames.forEach((name, i)=>originals[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, originals[i]));
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc2NyaXB0cy90ZXN0cy9wbGF5X2ludGVncml0eV9oYW5kbGVyX3Rlc3QudHMiXSwic291cmNlc0NvbnRlbnQiOlsiLyoqIFJlYWwgaGFuZGxlciwgQXV0aCBjbGllbnQgYW5kIFBvc3RnUkVTVCB0cmFuc3BvcnQ7IHN5bnRoZXRpYyBzdHJpY3QgZmV0Y2hcbiAqIGRvdWJsZXMgb25seS4gTm8gLS1hbGxvdy1uZXQgYW5kIG5vIHByb3ZpZGVyL2hvc3RlZCBjcmVkZW50aWFscyBvciBjYWxscy4gKi9cbmltcG9ydCB7IGFzc2VydEVxdWFscyB9IGZyb20gXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvX3NoYXJlZC90ZXN0X2Fzc2VydC50c1wiO1xuaW1wb3J0IHtcbiAgc2hhMjU2SGV4LFxuICBzbXNJbnRlZ3JpdHlSZXF1ZXN0SGFzaCxcbn0gZnJvbSBcIi4uLy4uL3N1cGFiYXNlL2Z1bmN0aW9ucy9fc2hhcmVkL3BsYXlfaW50ZWdyaXR5X2JpbmRpbmcudHNcIjtcblxuY29uc3QgYWN0b3IgPSBcIjk5NTcwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMVwiO1xuY29uc3Qgc2Vzc2lvbiA9IFwiOTk1NzAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDExXCI7XG5jb25zdCBub25jZSA9IFwiOTk1NzAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDMxXCI7XG5jb25zdCByZXNlcnZhdGlvbiA9IFwiOTk1NzAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDQxXCI7XG5jb25zdCBjYXBhYmlsaXR5ID0gXCI5OTU3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwNTFcIjtcbmNvbnN0IHJlY2VpdmVyID0gXCJhXCIucmVwZWF0KDY0KTtcbmNvbnN0IGVudk5hbWVzID0gW1xuICBcIlNVUEFCQVNFX1VSTFwiLFxuICBcIlNVUEFCQVNFX0FOT05fS0VZXCIsXG4gIFwiU1VQQUJBU0VfU0VSVklDRV9ST0xFX0tFWVwiLFxuICBcIlBMQVlfSU5URUdSSVRZX1NFUlZJQ0VfQUNDT1VOVF9KU09OXCIsXG4gIFwiR09PR0xFX1BMQVlfU0VSVklDRV9BQ0NPVU5UX0pTT05cIixcbiAgXCJQTEFZX0lOVEVHUklUWV9NSU5fVkVSU0lPTl9DT0RFXCIsXG4gIFwiUExBWV9JTlRFR1JJVFlfQ0VSVElGSUNBVEVfU0hBMjU2XCIsXG5dO1xuZnVuY3Rpb24gand0KGNsYWltczogUmVjb3JkPHN0cmluZywgdW5rbm93bj4pIHtcbiAgcmV0dXJuIFwiQmVhcmVyIGUzMC5cIiArXG4gICAgYnRvYShKU09OLnN0cmluZ2lmeShjbGFpbXMpKS5yZXBsYWNlQWxsKFwiK1wiLCBcIi1cIikucmVwbGFjZUFsbChcIi9cIiwgXCJfXCIpXG4gICAgICAucmVwbGFjZUFsbChcIj1cIiwgXCJcIikgK1xuICAgIFwiLnN5bnRoZXRpY1wiO1xufVxuY29uc3QgYXV0aG9yaXphdGlvbiA9IGp3dCh7XG4gIHN1YjogYWN0b3IsXG4gIHNlc3Npb25faWQ6IHNlc3Npb24sXG4gIHJvbGU6IFwiYXV0aGVudGljYXRlZFwiLFxufSk7XG5jb25zdCBvYXV0aCA9IFwiaHR0cHM6Ly9vYXV0aDIuZ29vZ2xlYXBpcy5jb20vdG9rZW5cIjtcbmNvbnN0IGRlY29kZSA9XG4gIFwiaHR0cHM6Ly9wbGF5aW50ZWdyaXR5Lmdvb2dsZWFwaXMuY29tL3YxL2FwcC5jb29sLm1vYmlsZTpkZWNvZGVJbnRlZ3JpdHlUb2tlblwiO1xuXG5EZW5vLnRlc3QoXCJJbnRlZ3JpdHkgYWRtaXNzaW9uIHJlYWwtaGFuZGxlciB0cmFuc3BvcnQgY29udHJhY3QgKG9mZmxpbmUgc3RyaWN0IGRvdWJsZXMpXCIsIGFzeW5jICh0KSA9PiB7XG4gIGNvbnN0IG9yaWdpbmFscyA9IGVudk5hbWVzLm1hcCgobmFtZSkgPT4gRGVuby5lbnYuZ2V0KG5hbWUpKTtcbiAgY29uc3Qgb3JpZ2luYWxGZXRjaCA9IGdsb2JhbFRoaXMuZmV0Y2gsIG9yaWdpbmFsU2VydmUgPSBEZW5vLnNlcnZlO1xuICAvLyBBY3R1YWwgU3VwYWJhc2UgQXV0aCBjbGllbnRzIGluc3RhbGwgYXV0by1yZWZyZXNoIHRpbWVycy4gUmVsZWFzZSBvbmx5XG4gIC8vIHRpbWVycyBjcmVhdGVkIGJ5IHRoaXMgaXNvbGF0ZWQgZml4dHVyZTsga2VlcCBEZW5vIGxlYWsgY2hlY2tzIGVuYWJsZWQuXG4gIGNvbnN0IG9yaWdpbmFsSW50ZXJ2YWwgPSBnbG9iYWxUaGlzLnNldEludGVydmFsO1xuICBjb25zdCBpbnRlcnZhbHM6IG51bWJlcltdID0gW107XG4gIGdsb2JhbFRoaXMuc2V0SW50ZXJ2YWwgPSAoKC4uLmFyZ3M6IFBhcmFtZXRlcnM8dHlwZW9mIHNldEludGVydmFsPikgPT4ge1xuICAgIGNvbnN0IGlkID0gb3JpZ2luYWxJbnRlcnZhbCguLi5hcmdzKTtcbiAgICBpbnRlcnZhbHMucHVzaChpZCk7XG4gICAgcmV0dXJuIGlkO1xuICB9KSBhcyB0eXBlb2Ygc2V0SW50ZXJ2YWw7XG4gIGxldCBoYW5kbGVyOiAocmVxOiBSZXF1ZXN0KSA9PiBQcm9taXNlPFJlc3BvbnNlPiA9ICgpID0+IHtcbiAgICB0aHJvdyBuZXcgRXJyb3IoXCJoYW5kbGVyIG1pc3NpbmdcIik7XG4gIH07XG4gIGNvbnN0IGtleXMgPSBhd2FpdCBjcnlwdG8uc3VidGxlLmdlbmVyYXRlS2V5KFxuICAgIHtcbiAgICAgIG5hbWU6IFwiUlNBU1NBLVBLQ1MxLXYxXzVcIixcbiAgICAgIG1vZHVsdXNMZW5ndGg6IDIwNDgsXG4gICAgICBwdWJsaWNFeHBvbmVudDogbmV3IFVpbnQ4QXJyYXkoWzEsIDAsIDFdKSxcbiAgICAgIGhhc2g6IFwiU0hBLTI1NlwiLFxuICAgIH0sXG4gICAgdHJ1ZSxcbiAgICBbXCJzaWduXCIsIFwidmVyaWZ5XCJdLFxuICApO1xuICBjb25zdCBrZXlCeXRlcyA9IG5ldyBVaW50OEFycmF5KFxuICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuZXhwb3J0S2V5KFwicGtjczhcIiwga2V5cy5wcml2YXRlS2V5KSxcbiAgKTtcbiAgY29uc3QgcGVtID0gXCItLS0tLUJFR0lOIFBSSVZBVEUgS0VZLS0tLS1cXG5cIiArXG4gICAgYnRvYShTdHJpbmcuZnJvbUNoYXJDb2RlKC4uLmtleUJ5dGVzKSkgKyBcIlxcbi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS1cIjtcbiAgY29uc3QgYWNjb3VudCA9IEpTT04uc3RyaW5naWZ5KHtcbiAgICBjbGllbnRfZW1haWw6IFwic3ludGhldGljQGV4YW1wbGUudGVzdFwiLFxuICAgIHByaXZhdGVfa2V5OiBwZW0sXG4gICAgdG9rZW5fdXJpOiBcImh0dHBzOi8vZm9yYmlkZGVuLmludmFsaWRcIixcbiAgfSk7XG4gIGNvbnN0IHZhbHVlcyA9IFtcbiAgICBcImh0dHBzOi8vYmFja2VuZC5pbnZhbGlkXCIsXG4gICAgXCJzeW50aGV0aWMtYW5vblwiLFxuICAgIFwic3ludGhldGljLXNlcnZpY2VcIixcbiAgICBhY2NvdW50LFxuICAgIFwiXCIsXG4gICAgXCIyM1wiLFxuICAgIFwiQ0VSVFwiLFxuICBdO1xuICBlbnZOYW1lcy5mb3JFYWNoKChuYW1lLCBpKSA9PiBEZW5vLmVudi5zZXQobmFtZSwgdmFsdWVzW2ldKSk7XG4gIE9iamVjdC5kZWZpbmVQcm9wZXJ0eShEZW5vLCBcInNlcnZlXCIsIHtcbiAgICB2YWx1ZTogKGZuOiB0eXBlb2YgaGFuZGxlcikgPT4ge1xuICAgICAgaGFuZGxlciA9IGZuO1xuICAgIH0sXG4gICAgY29uZmlndXJhYmxlOiB0cnVlLFxuICAgIHdyaXRhYmxlOiB0cnVlLFxuICB9KTtcbiAgdHJ5IHtcbiAgICBhd2FpdCBpbXBvcnQoXCIuLi8uLi9zdXBhYmFzZS9mdW5jdGlvbnMvdmVyaWZ5LXBsYXktaW50ZWdyaXR5L2luZGV4LnRzXCIpO1xuICAgIGNvbnN0IHNldHVwID0gYXN5bmMgKG9wdGlvbnM6IFJlY29yZDxzdHJpbmcsIHVua25vd24+ID0ge30pID0+IHtcbiAgICAgIGNvbnN0IHNtcyA9IHtcbiAgICAgICAgc3ViamVjdElkOiBhY3RvcixcbiAgICAgICAgbm9uY2UsXG4gICAgICAgIHJlY2VpdmVyTW9tb051bWJlckhhc2g6IHJlY2VpdmVyLFxuICAgICAgICBjbGllbnRFbnZlbG9wZUlkOiBcIjk5NTcwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDA2MVwiLFxuICAgICAgICByYXdTZW5kZXI6IFwiTS1Nb25leVwiLFxuICAgICAgICByYXdCb2R5U2hhMjU2OiBcImJcIi5yZXBlYXQoNjQpLFxuICAgICAgICByZWNlaXZlZEF0RGV2aWNlOiBudWxsLFxuICAgICAgfTtcbiAgICAgIGNvbnN0IHJlcXVlc3RIYXNoID0gYXdhaXQgc21zSW50ZWdyaXR5UmVxdWVzdEhhc2goc21zKTtcbiAgICAgIGNvbnN0IHBheWxvYWQ6IFJlY29yZDxzdHJpbmcsIHVua25vd24+ID0ge1xuICAgICAgICBhY3Rpb246IFwic21zLmluZ2VzdFwiLFxuICAgICAgICBzdWJqZWN0X2lkOiBhY3RvcixcbiAgICAgICAgbm9uY2UsXG4gICAgICAgIHNtc19wZXJtaXNzaW9uX2dyYW50ZWQ6IHRydWUsXG4gICAgICAgIHNtc19hY2Nlc3NfZW5hYmxlZDogdHJ1ZSxcbiAgICAgICAgcmVxdWVzdF9oYXNoOiByZXF1ZXN0SGFzaCxcbiAgICAgICAgcmVjZWl2ZXJfbW9tb19udW1iZXJfaGFzaDogcmVjZWl2ZXIsXG4gICAgICAgIGludGVncml0eV90b2tlbjogXCJzeW50aGV0aWMtaW50ZWdyaXR5LXRva2VuXCIsXG4gICAgICAgIHNtc19yZXF1ZXN0OiB7XG4gICAgICAgICAgY2xpZW50X2VudmVsb3BlX2lkOiBzbXMuY2xpZW50RW52ZWxvcGVJZCxcbiAgICAgICAgICByYXdfc2VuZGVyOiBzbXMucmF3U2VuZGVyLFxuICAgICAgICAgIHJhd19ib2R5X3NoYTI1Njogc21zLnJhd0JvZHlTaGEyNTYsXG4gICAgICAgICAgcmVjZWl2ZWRfYXRfZGV2aWNlOiBudWxsLFxuICAgICAgICB9LFxuICAgICAgfTtcbiAgICAgIGxldCBvYXV0aFN0YXJ0ZWQgPSBmYWxzZSxcbiAgICAgICAgZGVjb2RlU3RhcnRlZCA9IGZhbHNlLFxuICAgICAgICBjb21wbGV0ZWQgPSBvcHRpb25zLmNvbXBsZXRlZCA9PT0gdHJ1ZSxcbiAgICAgICAgdGVybWluYWwgPSBmYWxzZTtcbiAgICAgIGNvbnN0IGNhbGxzOiBBcnJheTx7IHVybDogc3RyaW5nOyBwYXJhbXM/OiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiB9PiA9XG4gICAgICAgIFtdO1xuICAgICAgY29uc3QgY2FwYWJpbGl0eUV4cGlyZXNBdCA9IG5ldyBEYXRlKERhdGUubm93KCkgKyAyNDAwMDApLnRvSVNPU3RyaW5nKCk7XG4gICAgICBjb25zdCByZXN1bHQgPSAoKSA9PiAoe1xuICAgICAgICBzdGF0dXM6IFwicGFzc1wiLFxuICAgICAgICBhY3Rpb246IHBheWxvYWQuYWN0aW9uLFxuICAgICAgICByZXF1ZXN0X2hhc2g6IHBheWxvYWQucmVxdWVzdF9oYXNoLFxuICAgICAgICBwYWNrYWdlX25hbWU6IFwiYXBwLmNvb2wubW9iaWxlXCIsXG4gICAgICAgIGFwcF92ZXJkaWN0OiBcIlBMQVlfUkVDT0dOSVpFRFwiLFxuICAgICAgICBkZXZpY2VfdmVyZGljdHM6IFtcIk1FRVRTX0RFVklDRV9JTlRFR1JJVFlcIl0sXG4gICAgICAgIG5hdGl2ZV9jYXBhYmlsaXR5OiBjYXBhYmlsaXR5LFxuICAgICAgICBjYXBhYmlsaXR5X2V4cGlyZXNfYXQ6IGNhcGFiaWxpdHlFeHBpcmVzQXQsXG4gICAgICB9KTtcbiAgICAgIGNvbnN0IHJlY2VpcHQgPSBhc3luYyAoc3RhdGU6IHN0cmluZykgPT4gKHtcbiAgICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgICAgcmVzZXJ2YXRpb25faWQ6IHJlc2VydmF0aW9uLFxuICAgICAgICBhY3Rvcl9pZDogYWN0b3IsXG4gICAgICAgIHNlc3Npb25faWQ6IHNlc3Npb24sXG4gICAgICAgIG5vbmNlLFxuICAgICAgICBhY3Rpb246IHBheWxvYWQuYWN0aW9uLFxuICAgICAgICByZXF1ZXN0X2hhc2g6IHBheWxvYWQucmVxdWVzdF9oYXNoLFxuICAgICAgICB0b2tlbl9zaGEyNTY6IGF3YWl0IHNoYTI1NkhleChTdHJpbmcocGF5bG9hZC5pbnRlZ3JpdHlfdG9rZW4pKSxcbiAgICAgICAgc3RhdGUsXG4gICAgICAgIGNhbl9jYWxsOiBzdGF0ZSAhPT0gXCJjb21wbGV0ZWRcIixcbiAgICAgICAgZXhwaXJlc19hdDogbmV3IERhdGUoRGF0ZS5ub3coKSArIDE4MDAwMCkudG9JU09TdHJpbmcoKSxcbiAgICAgICAgcmVzdWx0OiBzdGF0ZSA9PT0gXCJjb21wbGV0ZWRcIiA/IHJlc3VsdCgpIDogbnVsbCxcbiAgICAgIH0pO1xuICAgICAgY29uc3QgZmFpbHVyZSA9IChjb2RlOiBzdHJpbmcpID0+XG4gICAgICAgIG5ldyBSZXNwb25zZShcbiAgICAgICAgICBKU09OLnN0cmluZ2lmeSh7IGNvZGUsIG1lc3NhZ2U6IFwicHJpdmF0ZSBTUUwgYW5kIHRva2VuIGRldGFpbHNcIiB9KSxcbiAgICAgICAgICB7IHN0YXR1czogNDAwLCBoZWFkZXJzOiB7IFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiIH0gfSxcbiAgICAgICAgKTtcbiAgICAgIGdsb2JhbFRoaXMuZmV0Y2ggPSBhc3luYyAoaW5wdXQsIGluaXQpID0+IHtcbiAgICAgICAgY29uc3QgdXJsID0gdHlwZW9mIGlucHV0ID09PSBcInN0cmluZ1wiXG4gICAgICAgICAgPyBpbnB1dFxuICAgICAgICAgIDogaW5wdXQgaW5zdGFuY2VvZiBVUkxcbiAgICAgICAgICA/IGlucHV0LmhyZWZcbiAgICAgICAgICA6IGlucHV0LnVybDtcbiAgICAgICAgY29uc3QgaGVhZGVycyA9IG5ldyBIZWFkZXJzKFxuICAgICAgICAgIGluaXQ/LmhlYWRlcnMgPz9cbiAgICAgICAgICAgIChpbnB1dCBpbnN0YW5jZW9mIFJlcXVlc3QgPyBpbnB1dC5oZWFkZXJzIDogdW5kZWZpbmVkKSxcbiAgICAgICAgKTtcbiAgICAgICAgaWYgKHVybCA9PT0gXCJodHRwczovL2JhY2tlbmQuaW52YWxpZC9hdXRoL3YxL3VzZXJcIikge1xuICAgICAgICAgIGNhbGxzLnB1c2goeyB1cmwgfSk7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKGhlYWRlcnMuZ2V0KFwiYXBpa2V5XCIpLCBcInN5bnRoZXRpYy1hbm9uXCIpO1xuICAgICAgICAgIGlmIChvcHRpb25zLmF1dGhEZW5pZWQpIHtcbiAgICAgICAgICAgIHJldHVybiBuZXcgUmVzcG9uc2UoJ3tcIm1zZ1wiOlwiZGVuaWVkXCJ9JywgeyBzdGF0dXM6IDQwMSB9KTtcbiAgICAgICAgICB9XG4gICAgICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZShcbiAgICAgICAgICAgIEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgICAgICAgaWQ6IGFjdG9yLFxuICAgICAgICAgICAgICBhdWQ6IFwiYXV0aGVudGljYXRlZFwiLFxuICAgICAgICAgICAgICByb2xlOiBcImF1dGhlbnRpY2F0ZWRcIixcbiAgICAgICAgICAgICAgZW1haWw6IFwic3ludGhldGljQGV4YW1wbGUudGVzdFwiLFxuICAgICAgICAgICAgfSksXG4gICAgICAgICAgICB7IGhlYWRlcnM6IHsgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIgfSB9LFxuICAgICAgICAgICk7XG4gICAgICAgIH1cbiAgICAgICAgaWYgKHVybC5zdGFydHNXaXRoKFwiaHR0cHM6Ly9iYWNrZW5kLmludmFsaWQvcmVzdC92MS9ycGMvXCIpKSB7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKGhlYWRlcnMuZ2V0KFwiYXBpa2V5XCIpLCBcInN5bnRoZXRpYy1zZXJ2aWNlXCIpO1xuICAgICAgICAgIGlmICghaW5pdD8uc2lnbmFsKSB0aHJvdyBuZXcgRXJyb3IoXCJSUEMgbGFja3MgYm91bmRlZCBhYm9ydCBzaWduYWxcIik7XG4gICAgICAgICAgY29uc3QgcGFyYW1zID0gSlNPTi5wYXJzZShTdHJpbmcoaW5pdC5ib2R5KSkgYXMgUmVjb3JkPFxuICAgICAgICAgICAgc3RyaW5nLFxuICAgICAgICAgICAgdW5rbm93blxuICAgICAgICAgID47XG4gICAgICAgICAgY2FsbHMucHVzaCh7IHVybCwgcGFyYW1zIH0pO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhwYXJhbXMucF9hY3Rvcl9pZCwgYWN0b3IpO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhwYXJhbXMucF9zZXNzaW9uX2lkLCBzZXNzaW9uKTtcbiAgICAgICAgICBjb25zdCBuYW1lID0gdXJsLnNwbGl0KFwiL1wiKS5hdCgtMSk7XG4gICAgICAgICAgbGV0IHZhbHVlOiB1bmtub3duO1xuICAgICAgICAgIGlmIChuYW1lID09PSBcInJlc2VydmVfcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIpIHtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgICAgICAgcGFyYW1zLnBfdG9rZW5fc2hhMjU2LFxuICAgICAgICAgICAgICBhd2FpdCBzaGEyNTZIZXgoU3RyaW5nKHBheWxvYWQuaW50ZWdyaXR5X3Rva2VuKSksXG4gICAgICAgICAgICApO1xuICAgICAgICAgICAgYXNzZXJ0RXF1YWxzKHBhcmFtcy5wX3JlcXVlc3RfaGFzaCwgcGF5bG9hZC5yZXF1ZXN0X2hhc2gpO1xuICAgICAgICAgICAgaWYgKG9wdGlvbnMucmVzZXJ2ZUVycm9yKSB7XG4gICAgICAgICAgICAgIHJldHVybiBmYWlsdXJlKFN0cmluZyhvcHRpb25zLnJlc2VydmVFcnJvcikpO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgaWYgKHRlcm1pbmFsIHx8ICghY29tcGxldGVkICYmIG9hdXRoU3RhcnRlZCkpIHtcbiAgICAgICAgICAgICAgcmV0dXJuIGZhaWx1cmUoXCI1NTAwMFwiKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHZhbHVlID0gYXdhaXQgcmVjZWlwdChjb21wbGV0ZWQgPyBcImNvbXBsZXRlZFwiIDogXCJyZXNlcnZlZFwiKTtcbiAgICAgICAgICAgIGlmIChvcHRpb25zLmZvcmdlZFJlY2VpcHQpIHtcbiAgICAgICAgICAgICAgdmFsdWUgPSB7IC4uLih2YWx1ZSBhcyBvYmplY3QpLCBzZXNzaW9uX2lkOiBjYXBhYmlsaXR5IH07XG4gICAgICAgICAgICB9XG4gICAgICAgICAgfSBlbHNlIGlmIChuYW1lID09PSBcImJlZ2luX3BsYXlfaW50ZWdyaXR5X2FkbWlzc2lvbl92MVwiKSB7XG4gICAgICAgICAgICBhc3NlcnRFcXVhbHMocGFyYW1zLnBfcmVzZXJ2YXRpb25faWQsIHJlc2VydmF0aW9uKTtcbiAgICAgICAgICAgIGlmIChcbiAgICAgICAgICAgICAgb3B0aW9ucy5iZWdpbkVycm9yIHx8XG4gICAgICAgICAgICAgIChvcHRpb25zLmRlY29kZURlbmllZCAmJiBwYXJhbXMucF9waGFzZSA9PT0gXCJkZWNvZGVcIilcbiAgICAgICAgICAgICkgcmV0dXJuIGZhaWx1cmUoXCI0MjUwMVwiKTtcbiAgICAgICAgICAgIGlmIChwYXJhbXMucF9waGFzZSA9PT0gXCJvYXV0aFwiKSB7XG4gICAgICAgICAgICAgIGlmIChvYXV0aFN0YXJ0ZWQpIHJldHVybiBmYWlsdXJlKFwiNTUwMDBcIik7XG4gICAgICAgICAgICAgIG9hdXRoU3RhcnRlZCA9IHRydWU7XG4gICAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgICBhc3NlcnRFcXVhbHMocGFyYW1zLnBfcGhhc2UsIFwiZGVjb2RlXCIpO1xuICAgICAgICAgICAgICBhc3NlcnRFcXVhbHMob2F1dGhTdGFydGVkLCB0cnVlKTtcbiAgICAgICAgICAgICAgaWYgKGRlY29kZVN0YXJ0ZWQpIHJldHVybiBmYWlsdXJlKFwiNTUwMDBcIik7XG4gICAgICAgICAgICAgIGRlY29kZVN0YXJ0ZWQgPSB0cnVlO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgdmFsdWUgPSBhd2FpdCByZWNlaXB0KHBhcmFtcy5wX3BoYXNlICsgXCJfc3RhcnRlZFwiKTtcbiAgICAgICAgICB9IGVsc2UgaWYgKG5hbWUgPT09IFwiY29tcGxldGVfcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIpIHtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhvYXV0aFN0YXJ0ZWQsIHRydWUpO1xuICAgICAgICAgICAgYXNzZXJ0RXF1YWxzKGRlY29kZVN0YXJ0ZWQsIHRydWUpO1xuICAgICAgICAgICAgYXNzZXJ0RXF1YWxzKHBhcmFtcy5wX3Byb3ZpZGVyX3N0YXR1cywgMjAwKTtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhOdW1iZXIuaXNJbnRlZ2VyKHBhcmFtcy5wX2RlY29kZV9kdXJhdGlvbl9tcyksIHRydWUpO1xuICAgICAgICAgICAgaWYgKG9wdGlvbnMuY29tcGxldGVEZW5pZWQpIHJldHVybiBmYWlsdXJlKFwiNDI1MDFcIik7XG4gICAgICAgICAgICBjb21wbGV0ZWQgPSB0cnVlO1xuICAgICAgICAgICAgaWYgKG9wdGlvbnMubG9zdENvbXBsZXRpb25BY2spIHtcbiAgICAgICAgICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZShcbiAgICAgICAgICAgICAgICAne1wiY29kZVwiOlwiUEdSU1Q5OTlcIixcIm1lc3NhZ2VcIjpcImxvc3QgYWNrbm93bGVkZ2VtZW50XCJ9JyxcbiAgICAgICAgICAgICAgICB7IHN0YXR1czogNTAzIH0sXG4gICAgICAgICAgICAgICk7XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICB2YWx1ZSA9IHJlc3VsdCgpO1xuICAgICAgICAgIH0gZWxzZSBpZiAobmFtZSA9PT0gXCJmaW5pc2hfcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIpIHtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgICAgICAgW1wiYW1iaWd1b3VzXCIsIFwicmVqZWN0ZWRcIl0uaW5jbHVkZXMoU3RyaW5nKHBhcmFtcy5wX291dGNvbWUpKSxcbiAgICAgICAgICAgICAgdHJ1ZSxcbiAgICAgICAgICAgICk7XG4gICAgICAgICAgICBpZiAoIWNvbXBsZXRlZCkgdGVybWluYWwgPSB0cnVlO1xuICAgICAgICAgICAgdmFsdWUgPSB7XG4gICAgICAgICAgICAgIG9rOiB0cnVlLFxuICAgICAgICAgICAgICBzdGF0ZTogY29tcGxldGVkID8gXCJjb21wbGV0ZWRcIiA6IHBhcmFtcy5wX291dGNvbWUsXG4gICAgICAgICAgICB9O1xuICAgICAgICAgIH0gZWxzZSB0aHJvdyBuZXcgRXJyb3IoXCJVbmV4cGVjdGVkIFJQQyBcIiArIG5hbWUpO1xuICAgICAgICAgIHJldHVybiBuZXcgUmVzcG9uc2UoSlNPTi5zdHJpbmdpZnkodmFsdWUpLCB7XG4gICAgICAgICAgICBoZWFkZXJzOiB7IFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiIH0sXG4gICAgICAgICAgfSk7XG4gICAgICAgIH1cbiAgICAgICAgaWYgKHVybCA9PT0gb2F1dGggfHwgdXJsID09PSBkZWNvZGUpIHtcbiAgICAgICAgICBjYWxscy5wdXNoKHsgdXJsIH0pO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhpbml0Py5yZWRpcmVjdCwgXCJlcnJvclwiKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoQm9vbGVhbihpbml0Py5zaWduYWwpLCB0cnVlKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMob2F1dGhTdGFydGVkLCB0cnVlKTtcbiAgICAgICAgICBpZiAodXJsID09PSBvYXV0aCkge1xuICAgICAgICAgICAgY29uc3QgZm9ybSA9IG5ldyBVUkxTZWFyY2hQYXJhbXMoU3RyaW5nKGluaXQ/LmJvZHkpKTtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgICAgICAgZm9ybS5nZXQoXCJncmFudF90eXBlXCIpLFxuICAgICAgICAgICAgICBcInVybjppZXRmOnBhcmFtczpvYXV0aDpncmFudC10eXBlOmp3dC1iZWFyZXJcIixcbiAgICAgICAgICAgICk7XG4gICAgICAgICAgICBjb25zdCBjbGFpbSA9IEpTT04ucGFyc2UoXG4gICAgICAgICAgICAgIGF0b2IoXG4gICAgICAgICAgICAgICAgU3RyaW5nKGZvcm0uZ2V0KFwiYXNzZXJ0aW9uXCIpKS5zcGxpdChcIi5cIilbMV0ucmVwbGFjZUFsbChcIi1cIiwgXCIrXCIpXG4gICAgICAgICAgICAgICAgICAucmVwbGFjZUFsbChcIl9cIiwgXCIvXCIpLFxuICAgICAgICAgICAgICApLFxuICAgICAgICAgICAgKTtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhjbGFpbS5hdWQsIG9hdXRoKTtcbiAgICAgICAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgICAgICAgY2xhaW0uc2NvcGUsXG4gICAgICAgICAgICAgIFwiaHR0cHM6Ly93d3cuZ29vZ2xlYXBpcy5jb20vYXV0aC9wbGF5aW50ZWdyaXR5XCIsXG4gICAgICAgICAgICApO1xuICAgICAgICAgICAgaWYgKG9wdGlvbnMub2F1dGhGYWlsdXJlKSB7XG4gICAgICAgICAgICAgIHJldHVybiBuZXcgUmVzcG9uc2UoJ3tcImVycm9yXCI6XCJwcml2YXRlIHByb3ZpZGVyIGZhaWx1cmVcIn0nLCB7XG4gICAgICAgICAgICAgICAgc3RhdHVzOiA0MjksXG4gICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZSgne1wiYWNjZXNzX3Rva2VuXCI6XCJzeW50aGV0aWMtYWNjZXNzXCJ9Jyk7XG4gICAgICAgICAgfVxuICAgICAgICAgIGFzc2VydEVxdWFscyhkZWNvZGVTdGFydGVkLCB0cnVlKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoaGVhZGVycy5nZXQoXCJhdXRob3JpemF0aW9uXCIpLCBcIkJlYXJlciBzeW50aGV0aWMtYWNjZXNzXCIpO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgICAgIEpTT04ucGFyc2UoU3RyaW5nKGluaXQ/LmJvZHkpKS5pbnRlZ3JpdHlUb2tlbixcbiAgICAgICAgICAgIHBheWxvYWQuaW50ZWdyaXR5X3Rva2VuLFxuICAgICAgICAgICk7XG4gICAgICAgICAgaWYgKG9wdGlvbnMudGltZW91dCkge1xuICAgICAgICAgICAgdGhyb3cgbmV3IERPTUV4Y2VwdGlvbihcInN5bnRoZXRpYyBhYm9ydFwiLCBcIkFib3J0RXJyb3JcIik7XG4gICAgICAgICAgfVxuICAgICAgICAgIGlmIChvcHRpb25zLmRlY29kZUZhaWx1cmUpIHtcbiAgICAgICAgICAgIHJldHVybiBuZXcgUmVzcG9uc2UoJ3tcInByaXZhdGVcIjpcInByb3ZpZGVyIGJvZHlcIn0nLCB7IHN0YXR1czogNDI5IH0pO1xuICAgICAgICAgIH1cbiAgICAgICAgICBpZiAob3B0aW9ucy5tYWxmb3JtZWRQcm92aWRlcikge1xuICAgICAgICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZSgne1widG9rZW5QYXlsb2FkRXh0ZXJuYWxcIjpudWxsfScpO1xuICAgICAgICAgIH1cbiAgICAgICAgICByZXR1cm4gbmV3IFJlc3BvbnNlKEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgICAgIHRva2VuUGF5bG9hZEV4dGVybmFsOiB7XG4gICAgICAgICAgICAgIHJlcXVlc3REZXRhaWxzOiB7XG4gICAgICAgICAgICAgICAgcmVxdWVzdFBhY2thZ2VOYW1lOiBcImFwcC5jb29sLm1vYmlsZVwiLFxuICAgICAgICAgICAgICAgIHJlcXVlc3RIYXNoOiBwYXlsb2FkLnJlcXVlc3RfaGFzaCxcbiAgICAgICAgICAgICAgICB0aW1lc3RhbXBNaWxsaXM6IFN0cmluZyhEYXRlLm5vdygpKSxcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgYXBwSW50ZWdyaXR5OiB7XG4gICAgICAgICAgICAgICAgcGFja2FnZU5hbWU6IFwiYXBwLmNvb2wubW9iaWxlXCIsXG4gICAgICAgICAgICAgICAgYXBwUmVjb2duaXRpb25WZXJkaWN0OiBcIlBMQVlfUkVDT0dOSVpFRFwiLFxuICAgICAgICAgICAgICAgIHZlcnNpb25Db2RlOiBvcHRpb25zLm9sZFZlcnNpb24gPyBcIjIyXCIgOiBcIjIzXCIsXG4gICAgICAgICAgICAgICAgY2VydGlmaWNhdGVTaGEyNTZEaWdlc3Q6IFtcbiAgICAgICAgICAgICAgICAgIG9wdGlvbnMuYmFkQ2VydGlmaWNhdGUgPyBcIk9USEVSXCIgOiBcIkNFUlRcIixcbiAgICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICBhY2NvdW50RGV0YWlsczoge1xuICAgICAgICAgICAgICAgIGFwcExpY2Vuc2luZ1ZlcmRpY3Q6IG9wdGlvbnMudW5saWNlbnNlZFxuICAgICAgICAgICAgICAgICAgPyBcIlVOTElDRU5TRURcIlxuICAgICAgICAgICAgICAgICAgOiBcIkxJQ0VOU0VEXCIsXG4gICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgIGRldmljZUludGVncml0eToge1xuICAgICAgICAgICAgICAgIGRldmljZVJlY29nbml0aW9uVmVyZGljdDogW1xuICAgICAgICAgICAgICAgICAgb3B0aW9ucy53ZWFrRGV2aWNlXG4gICAgICAgICAgICAgICAgICAgID8gXCJNRUVUU19CQVNJQ19JTlRFR1JJVFlcIlxuICAgICAgICAgICAgICAgICAgICA6IFwiTUVFVFNfREVWSUNFX0lOVEVHUklUWVwiLFxuICAgICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIH0pKTtcbiAgICAgICAgfVxuICAgICAgICB0aHJvdyBuZXcgRXJyb3IoXCJOZXR3b3JrIFVSTCBvdXRzaWRlIHN0cmljdCBtb2NrIFwiICsgdXJsKTtcbiAgICAgIH07XG4gICAgICBjb25zdCBzZW5kID0gKFxuICAgICAgICBhdXRoOiBzdHJpbmcgfCBudWxsID0gYXV0aG9yaXphdGlvbixcbiAgICAgICAgYm9keTogdW5rbm93biA9IHBheWxvYWQsXG4gICAgICApID0+XG4gICAgICAgIGhhbmRsZXIoXG4gICAgICAgICAgbmV3IFJlcXVlc3QoXCJodHRwczovL2VkZ2UuaW52YWxpZC92ZXJpZnktcGxheS1pbnRlZ3JpdHlcIiwge1xuICAgICAgICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgICAgICAgIGhlYWRlcnM6IHtcbiAgICAgICAgICAgICAgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICAgICAgICAgIC4uLihhdXRoID8geyBhdXRob3JpemF0aW9uOiBhdXRoIH0gOiB7fSksXG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoYm9keSksXG4gICAgICAgICAgfSksXG4gICAgICAgICk7XG4gICAgICByZXR1cm4ge1xuICAgICAgICBwYXlsb2FkLFxuICAgICAgICBjYWxscyxcbiAgICAgICAgc2VuZCxcbiAgICAgICAgcmVzdWx0LFxuICAgICAgICBnb29nbGU6ICgpID0+IGNhbGxzLmZpbHRlcigoYykgPT4gYy51cmwgPT09IG9hdXRoIHx8IGMudXJsID09PSBkZWNvZGUpLFxuICAgICAgICBycGNzOiAoKSA9PiBjYWxscy5maWx0ZXIoKGMpID0+IGMucGFyYW1zKSxcbiAgICAgIH07XG4gICAgfTtcbiAgICBmb3IgKFxuICAgICAgY29uc3QgW2xhYmVsLCBhdXRoLCBvcHRpb25zXSBvZiBbXG4gICAgICAgIFtcIm1pc3NpbmcgYmVhcmVyXCIsIG51bGwsIHt9XSxcbiAgICAgICAgW1wiQXV0aCBkZW5pZXMgc3VwcGxpZWQgYmVhcmVyXCIsIGF1dGhvcml6YXRpb24sIHsgYXV0aERlbmllZDogdHJ1ZSB9XSxcbiAgICAgICAgW1wibWlzc2luZyBzZXNzaW9uXCIsIGp3dCh7IHN1YjogYWN0b3IsIHJvbGU6IFwiYXV0aGVudGljYXRlZFwiIH0pLCB7fV0sXG4gICAgICAgIFtcbiAgICAgICAgICBcInN1YmplY3Qgc3Vic3RpdHV0aW9uXCIsXG4gICAgICAgICAgand0KHsgc3ViOiBjYXBhYmlsaXR5LCBzZXNzaW9uX2lkOiBzZXNzaW9uLCByb2xlOiBcImF1dGhlbnRpY2F0ZWRcIiB9KSxcbiAgICAgICAgICB7fSxcbiAgICAgICAgXSxcbiAgICAgICAgW1xuICAgICAgICAgIFwic2VydmljZSBjbGFpbVwiLFxuICAgICAgICAgIGp3dCh7IHN1YjogYWN0b3IsIHNlc3Npb25faWQ6IHNlc3Npb24sIHJvbGU6IFwic2VydmljZV9yb2xlXCIgfSksXG4gICAgICAgICAge30sXG4gICAgICAgIF0sXG4gICAgICBdIGFzIGNvbnN0XG4gICAgKSB7XG4gICAgICBhd2FpdCB0LnN0ZXAoXG4gICAgICAgIGxhYmVsICsgXCIgZGVuaWVzIGJlZm9yZSBHb29nbGUgYW5kIHNlcnZpY2UgUlBDXCIsXG4gICAgICAgIGFzeW5jICgpID0+IHtcbiAgICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAob3B0aW9ucyk7XG4gICAgICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBkLnNlbmQoYXV0aCk7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgNDAxKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoZC5nb29nbGUoKS5sZW5ndGgsIDApO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhkLnJwY3MoKS5sZW5ndGgsIDApO1xuICAgICAgICB9LFxuICAgICAgKTtcbiAgICB9XG4gICAgZm9yIChcbiAgICAgIGNvbnN0IFtsYWJlbCwgbXV0YXRpb24sIHN0YXR1c10gb2YgW1xuICAgICAgICBbXCJvdmVyc2l6ZWQgcmVxdWVzdFwiLCB7IHBhZGRpbmc6IFwieFwiLnJlcGVhdCgzMzAwMCkgfSwgNDEzXSxcbiAgICAgICAgW1wiYmluZGluZyBtaXNtYXRjaFwiLCB7IHJlcXVlc3RfaGFzaDogXCJjXCIucmVwZWF0KDY0KSB9LCA0MDBdLFxuICAgICAgICBbXCJtYWxmb3JtZWQgbm9uY2VcIiwgeyBub25jZTogXCJub3QtYS11dWlkXCIgfSwgNDAwXSxcbiAgICAgICAgW1wiaW5jb3JyZWN0IHN1YmplY3RcIiwgeyBzdWJqZWN0X2lkOiBjYXBhYmlsaXR5IH0sIDQwMF0sXG4gICAgICAgIFtcInBlcm1pc3Npb24gbWlzc2luZ1wiLCB7IHNtc19wZXJtaXNzaW9uX2dyYW50ZWQ6IGZhbHNlIH0sIDQwMF0sXG4gICAgICBdIGFzIGNvbnN0XG4gICAgKSB7XG4gICAgICBhd2FpdCB0LnN0ZXAobGFiZWwgKyBcIiBkZW5pZXMgYmVmb3JlIGFkbWlzc2lvbiBvciBHb29nbGVcIiwgYXN5bmMgKCkgPT4ge1xuICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoKTtcbiAgICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBkLnNlbmQoYXV0aG9yaXphdGlvbiwge1xuICAgICAgICAgIC4uLmQucGF5bG9hZCxcbiAgICAgICAgICAuLi5tdXRhdGlvbixcbiAgICAgICAgfSk7XG4gICAgICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIHN0YXR1cyk7XG4gICAgICAgIGFzc2VydEVxdWFscyhkLmdvb2dsZSgpLmxlbmd0aCwgMCk7XG4gICAgICAgIGFzc2VydEVxdWFscyhkLnJwY3MoKS5sZW5ndGgsIDApO1xuICAgICAgfSk7XG4gICAgfVxuICAgIGZvciAoXG4gICAgICBjb25zdCBbbGFiZWwsIGNvZGUsIHN0YXR1c10gb2YgW1xuICAgICAgICBbXCJwZXItYWN0b3IgcXVvdGFcIiwgXCI1MzMwMFwiLCA0MjldLFxuICAgICAgICBbXCJnbG9iYWwgcXVvdGFcIiwgXCI1MzMwMFwiLCA0MjldLFxuICAgICAgICBbXCJzdGFsZSBvciByZXZva2VkIHNlc3Npb25cIiwgXCI0MjUwMVwiLCA0MDNdLFxuICAgICAgICBbXCJtYWxmb3JtZWQgU1FMIGJpbmRpbmdcIiwgXCIyMjAyM1wiLCA0MDBdLFxuICAgICAgICBbXCJyZXBsYXllZCBvciB1bmNlcnRhaW4gcmVxdWVzdFwiLCBcIjU1MDAwXCIsIDQwOV0sXG4gICAgICAgIFtcIm1pc3NpbmcgbWlncmF0aW9uIFJQQ1wiLCBcIlBHUlNUMjAyXCIsIDUwM10sXG4gICAgICBdIGFzIGNvbnN0XG4gICAgKSB7XG4gICAgICBhd2FpdCB0LnN0ZXAobGFiZWwgKyBcIiBwcm9kdWNlcyBzdGFibGUgcHJlLUdvb2dsZSBkZW5pYWxcIiwgYXN5bmMgKCkgPT4ge1xuICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoeyByZXNlcnZlRXJyb3I6IGNvZGUgfSk7XG4gICAgICAgIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZC5zZW5kKCk7XG4gICAgICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIHN0YXR1cyk7XG4gICAgICAgIGFzc2VydEVxdWFscyhkLmdvb2dsZSgpLmxlbmd0aCwgMCk7XG4gICAgICAgIGFzc2VydEVxdWFscygoYXdhaXQgcmVzcG9uc2UudGV4dCgpKS5pbmNsdWRlcyhcInByaXZhdGVcIiksIGZhbHNlKTtcbiAgICAgIH0pO1xuICAgIH1cbiAgICBhd2FpdCB0LnN0ZXAoXG4gICAgICBcImZvcmdlZCByZXNlcnZhdGlvbiByZWNlaXB0IGNhbm5vdCBhdXRob3JpemUgZXh0ZXJuYWwgd29ya1wiLFxuICAgICAgYXN5bmMgKCkgPT4ge1xuICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoeyBmb3JnZWRSZWNlaXB0OiB0cnVlIH0pO1xuICAgICAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGQuc2VuZCgpO1xuICAgICAgICBhc3NlcnRFcXVhbHMocmVzcG9uc2Uuc3RhdHVzLCA1MDMpO1xuICAgICAgICBhc3NlcnRFcXVhbHMoZC5nb29nbGUoKS5sZW5ndGgsIDApO1xuICAgICAgfSxcbiAgICApO1xuICAgIGF3YWl0IHQuc3RlcChcbiAgICAgIFwiT0F1dGggYWRtaXNzaW9uIHJlamVjdGlvbiBtYWtlcyB6ZXJvIHByb3ZpZGVyIGNhbGxzXCIsXG4gICAgICBhc3luYyAoKSA9PiB7XG4gICAgICAgIGNvbnN0IGQgPSBhd2FpdCBzZXR1cCh7IGJlZ2luRXJyb3I6IHRydWUgfSk7XG4gICAgICAgIGFzc2VydEVxdWFscygoYXdhaXQgZC5zZW5kKCkpLnN0YXR1cywgNDAzKTtcbiAgICAgICAgYXNzZXJ0RXF1YWxzKGQuZ29vZ2xlKCkubGVuZ3RoLCAwKTtcbiAgICAgIH0sXG4gICAgKTtcbiAgICBhd2FpdCB0LnN0ZXAoXG4gICAgICBcInJldm9jYXRpb24gYmV0d2VlbiBPQXV0aCBhbmQgZGVjb2RlIGJsb2NrcyBkZWNvZGVcIixcbiAgICAgIGFzeW5jICgpID0+IHtcbiAgICAgICAgY29uc3QgZCA9IGF3YWl0IHNldHVwKHsgZGVjb2RlRGVuaWVkOiB0cnVlIH0pO1xuICAgICAgICBhc3NlcnRFcXVhbHMoKGF3YWl0IGQuc2VuZCgpKS5zdGF0dXMsIDQwMyk7XG4gICAgICAgIGFzc2VydEVxdWFscyhkLmdvb2dsZSgpLm1hcCgoYykgPT4gYy51cmwpLCBbb2F1dGhdKTtcbiAgICAgIH0sXG4gICAgKTtcbiAgICBhd2FpdCB0LnN0ZXAoXG4gICAgICBcIm5vcm1hbCBhdXRob3JpemVkIHdvcmtmbG93IHBlcmZvcm1zIG9ubHkgdHdvIGFkbWl0dGVkIGZpeGVkIEdvb2dsZSBjYWxsc1wiLFxuICAgICAgYXN5bmMgKCkgPT4ge1xuICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoKTtcbiAgICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBkLnNlbmQoKTtcbiAgICAgICAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgMjAwKTtcbiAgICAgICAgYXNzZXJ0RXF1YWxzKGF3YWl0IHJlc3BvbnNlLmpzb24oKSwgZC5yZXN1bHQoKSk7XG4gICAgICAgIGFzc2VydEVxdWFscyhkLmdvb2dsZSgpLm1hcCgoYykgPT4gYy51cmwpLCBbb2F1dGgsIGRlY29kZV0pO1xuICAgICAgICBhc3NlcnRFcXVhbHMoZC5ycGNzKCkubWFwKChjKSA9PiBjLnVybC5zcGxpdChcIi9cIikuYXQoLTEpKSwgW1xuICAgICAgICAgIFwicmVzZXJ2ZV9wbGF5X2ludGVncml0eV9hZG1pc3Npb25fdjFcIixcbiAgICAgICAgICBcImJlZ2luX3BsYXlfaW50ZWdyaXR5X2FkbWlzc2lvbl92MVwiLFxuICAgICAgICAgIFwiYmVnaW5fcGxheV9pbnRlZ3JpdHlfYWRtaXNzaW9uX3YxXCIsXG4gICAgICAgICAgXCJjb21wbGV0ZV9wbGF5X2ludGVncml0eV9hZG1pc3Npb25fdjFcIixcbiAgICAgICAgXSk7XG4gICAgICB9LFxuICAgICk7XG4gICAgYXdhaXQgdC5zdGVwKFxuICAgICAgXCJjb21wbGV0ZWQgZXhhY3QtYWN0aW9uIHJlY29uY2lsaWF0aW9uIHJldHVybnMgY2FwYWJpbGl0eSB3aXRob3V0IHJlLWRlY29kaW5nXCIsXG4gICAgICBhc3luYyAoKSA9PiB7XG4gICAgICAgIGNvbnN0IGQgPSBhd2FpdCBzZXR1cCh7IGNvbXBsZXRlZDogdHJ1ZSB9KTtcbiAgICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBkLnNlbmQoKTtcbiAgICAgICAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgMjAwKTtcbiAgICAgICAgYXNzZXJ0RXF1YWxzKGF3YWl0IHJlc3BvbnNlLmpzb24oKSwgZC5yZXN1bHQoKSk7XG4gICAgICAgIGFzc2VydEVxdWFscyhkLmdvb2dsZSgpLmxlbmd0aCwgMCk7XG4gICAgICB9LFxuICAgICk7XG4gICAgZm9yIChcbiAgICAgIGNvbnN0IG9wdGlvbiBvZiBbXG4gICAgICAgIFwidW5saWNlbnNlZFwiLFxuICAgICAgICBcIm9sZFZlcnNpb25cIixcbiAgICAgICAgXCJiYWRDZXJ0aWZpY2F0ZVwiLFxuICAgICAgICBcIndlYWtEZXZpY2VcIixcbiAgICAgIF1cbiAgICApIHtcbiAgICAgIGF3YWl0IHQuc3RlcChcbiAgICAgICAgb3B0aW9uICsgXCIgcmVtYWlucyByZWplY3RlZCBhZnRlciBhZG1pc3Npb24gd2l0aG91dCBtaW50XCIsXG4gICAgICAgIGFzeW5jICgpID0+IHtcbiAgICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoeyBbb3B0aW9uXTogdHJ1ZSB9KTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoKGF3YWl0IGQuc2VuZCgpKS5zdGF0dXMsIDQwMyk7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICAgICAgZC5ycGNzKCkuc29tZSgoYykgPT5cbiAgICAgICAgICAgICAgYy51cmwuZW5kc1dpdGgoXCJjb21wbGV0ZV9wbGF5X2ludGVncml0eV9hZG1pc3Npb25fdjFcIilcbiAgICAgICAgICAgICksXG4gICAgICAgICAgICBmYWxzZSxcbiAgICAgICAgICApO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhkLnJwY3MoKS5hdCgtMSk/LnBhcmFtcz8ucF9vdXRjb21lLCBcInJlamVjdGVkXCIpO1xuICAgICAgICB9LFxuICAgICAgKTtcbiAgICB9XG4gICAgZm9yIChcbiAgICAgIGNvbnN0IG9wdGlvbiBvZiBbXG4gICAgICAgIFwib2F1dGhGYWlsdXJlXCIsXG4gICAgICAgIFwiZGVjb2RlRmFpbHVyZVwiLFxuICAgICAgICBcInRpbWVvdXRcIixcbiAgICAgICAgXCJtYWxmb3JtZWRQcm92aWRlclwiLFxuICAgICAgXVxuICAgICkge1xuICAgICAgYXdhaXQgdC5zdGVwKFxuICAgICAgICBvcHRpb24gK1xuICAgICAgICAgIFwiIHJldGFpbnMgdGVybWluYWwvdW5rbm93biBldmlkZW5jZSBhbmQgbmV2ZXIgYXV0by1yZXRyaWVzIHRva2VuXCIsXG4gICAgICAgIGFzeW5jICgpID0+IHtcbiAgICAgICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoeyBbb3B0aW9uXTogdHJ1ZSB9KTtcbiAgICAgICAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGQuc2VuZCgpO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMgPj0gNDAwLCB0cnVlKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoKGF3YWl0IHJlc3BvbnNlLnRleHQoKSkuaW5jbHVkZXMoXCJwcml2YXRlXCIpLCBmYWxzZSk7XG4gICAgICAgICAgY29uc3QgY291bnQgPSBkLmdvb2dsZSgpLmxlbmd0aDtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoY291bnQsIG9wdGlvbiA9PT0gXCJvYXV0aEZhaWx1cmVcIiA/IDEgOiAyKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoKGF3YWl0IGQuc2VuZCgpKS5zdGF0dXMsIDQwOSk7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKGQuZ29vZ2xlKCkubGVuZ3RoLCBjb3VudCk7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICAgICAgZC5ycGNzKCkuc29tZSgoYykgPT5cbiAgICAgICAgICAgICAgYy51cmwuZW5kc1dpdGgoXCJjb21wbGV0ZV9wbGF5X2ludGVncml0eV9hZG1pc3Npb25fdjFcIilcbiAgICAgICAgICAgICksXG4gICAgICAgICAgICBmYWxzZSxcbiAgICAgICAgICApO1xuICAgICAgICB9LFxuICAgICAgKTtcbiAgICB9XG4gICAgYXdhaXQgdC5zdGVwKFxuICAgICAgXCJ1bmNlcnRhaW4gc3VjY2Vzc2Z1bCBjb21wbGV0aW9uIHJlY29uY2lsZXMgb3JpZ2luYWwgY2FwYWJpbGl0eSB3aXRob3V0IHNlY29uZCBHb29nbGUgZGVjb2RlXCIsXG4gICAgICBhc3luYyAoKSA9PiB7XG4gICAgICAgIGNvbnN0IGQgPSBhd2FpdCBzZXR1cCh7IGxvc3RDb21wbGV0aW9uQWNrOiB0cnVlIH0pO1xuICAgICAgICBhc3NlcnRFcXVhbHMoKGF3YWl0IGQuc2VuZCgpKS5zdGF0dXMsIDUwMyk7XG4gICAgICAgIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZC5zZW5kKCk7XG4gICAgICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDIwMCk7XG4gICAgICAgIGFzc2VydEVxdWFscyhhd2FpdCByZXNwb25zZS5qc29uKCksIGQucmVzdWx0KCkpO1xuICAgICAgICBhc3NlcnRFcXVhbHMoZC5nb29nbGUoKS5sZW5ndGgsIDIpO1xuICAgICAgfSxcbiAgICApO1xuICAgIGF3YWl0IHQuc3RlcChcInBvc3QtcHJvdmlkZXIgcmV2b2NhdGlvbiBjYW5ub3QgbWludFwiLCBhc3luYyAoKSA9PiB7XG4gICAgICBjb25zdCBkID0gYXdhaXQgc2V0dXAoeyBjb21wbGV0ZURlbmllZDogdHJ1ZSB9KTtcbiAgICAgIGFzc2VydEVxdWFscygoYXdhaXQgZC5zZW5kKCkpLnN0YXR1cywgNDAzKTtcbiAgICAgIGFzc2VydEVxdWFscyhkLmdvb2dsZSgpLmxlbmd0aCwgMik7XG4gICAgICBhc3NlcnRFcXVhbHMoZC5ycGNzKCkuYXQoLTEpPy5wYXJhbXM/LnBfb3V0Y29tZSwgXCJhbWJpZ3VvdXNcIik7XG4gICAgfSk7XG4gICAgYXdhaXQgdC5zdGVwKFxuICAgICAgXCJtaXNzaW5nIG9yIG1hbGZvcm1lZCBjb25maWd1cmF0aW9uIGZhaWxzIGJlZm9yZSByZXNlcnZhdGlvbiBhbmQgR29vZ2xlXCIsXG4gICAgICBhc3luYyAoKSA9PiB7XG4gICAgICAgIGZvciAoXG4gICAgICAgICAgY29uc3QgdmFsdWUgb2YgW1xuICAgICAgICAgICAgXCJcIixcbiAgICAgICAgICAgIFwibWFsZm9ybWVkXCIsXG4gICAgICAgICAgICBKU09OLnN0cmluZ2lmeSh7IGNsaWVudF9lbWFpbDogbnVsbCB9KSxcbiAgICAgICAgICBdXG4gICAgICAgICkge1xuICAgICAgICAgIGNvbnN0IGQgPSBhd2FpdCBzZXR1cCgpO1xuICAgICAgICAgIERlbm8uZW52LnNldChcIlBMQVlfSU5URUdSSVRZX1NFUlZJQ0VfQUNDT1VOVF9KU09OXCIsIHZhbHVlKTtcbiAgICAgICAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGQuc2VuZCgpO1xuICAgICAgICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDUwMyk7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKGQuZ29vZ2xlKCkubGVuZ3RoLCAwKTtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoZC5ycGNzKCkubGVuZ3RoLCAwKTtcbiAgICAgICAgfVxuICAgICAgICBEZW5vLmVudi5zZXQoXCJQTEFZX0lOVEVHUklUWV9TRVJWSUNFX0FDQ09VTlRfSlNPTlwiLCBhY2NvdW50KTtcbiAgICAgIH0sXG4gICAgKTtcbiAgfSBmaW5hbGx5IHtcbiAgICBpbnRlcnZhbHMuZm9yRWFjaCgoaWQpID0+IGNsZWFySW50ZXJ2YWwoaWQpKTtcbiAgICBnbG9iYWxUaGlzLnNldEludGVydmFsID0gb3JpZ2luYWxJbnRlcnZhbDtcbiAgICBnbG9iYWxUaGlzLmZldGNoID0gb3JpZ2luYWxGZXRjaDtcbiAgICBPYmplY3QuZGVmaW5lUHJvcGVydHkoRGVubywgXCJzZXJ2ZVwiLCB7XG4gICAgICB2YWx1ZTogb3JpZ2luYWxTZXJ2ZSxcbiAgICAgIGNvbmZpZ3VyYWJsZTogdHJ1ZSxcbiAgICAgIHdyaXRhYmxlOiB0cnVlLFxuICAgIH0pO1xuICAgIGVudk5hbWVzLmZvckVhY2goKG5hbWUsIGkpID0+XG4gICAgICBvcmlnaW5hbHNbaV0gPT09IHVuZGVmaW5lZFxuICAgICAgICA/IERlbm8uZW52LmRlbGV0ZShuYW1lKVxuICAgICAgICA6IERlbm8uZW52LnNldChuYW1lLCBvcmlnaW5hbHNbaV0hKVxuICAgICk7XG4gIH1cbn0pO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBOzZFQUM2RSxHQUM3RSxTQUFTLFlBQVksUUFBUSxrREFBa0Q7QUFDL0UsU0FDRSxTQUFTLEVBQ1QsdUJBQXVCLFFBQ2xCLDZEQUE2RDtBQUVwRSxNQUFNLFFBQVE7QUFDZCxNQUFNLFVBQVU7QUFDaEIsTUFBTSxRQUFRO0FBQ2QsTUFBTSxjQUFjO0FBQ3BCLE1BQU0sYUFBYTtBQUNuQixNQUFNLFdBQVcsSUFBSSxNQUFNLENBQUM7QUFDNUIsTUFBTSxXQUFXO0VBQ2Y7RUFDQTtFQUNBO0VBQ0E7RUFDQTtFQUNBO0VBQ0E7Q0FDRDtBQUNELFNBQVMsSUFBSSxNQUErQjtFQUMxQyxPQUFPLGdCQUNMLEtBQUssS0FBSyxTQUFTLENBQUMsU0FBUyxV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
// denoCacheMetadata=17348517213468240135,16962844790910713748