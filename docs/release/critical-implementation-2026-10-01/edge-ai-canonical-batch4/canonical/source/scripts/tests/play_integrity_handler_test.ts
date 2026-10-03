/** Real handler, Auth client and PostgREST transport; synthetic strict fetch
 * doubles only. No --allow-net and no provider/hosted credentials or calls. */
import { assertEquals } from "../../supabase/functions/_shared/test_assert.ts";
import {
  sha256Hex,
  smsIntegrityRequestHash,
} from "../../supabase/functions/_shared/play_integrity_binding.ts";

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
  "PLAY_INTEGRITY_CERTIFICATE_SHA256",
];
function jwt(claims: Record<string, unknown>) {
  return "Bearer e30." +
    btoa(JSON.stringify(claims)).replaceAll("+", "-").replaceAll("/", "_")
      .replaceAll("=", "") +
    ".synthetic";
}
const authorization = jwt({
  sub: actor,
  session_id: session,
  role: "authenticated",
});
const oauth = "https://oauth2.googleapis.com/token";
const decode =
  "https://playintegrity.googleapis.com/v1/app.cool.mobile:decodeIntegrityToken";

Deno.test("Integrity admission real-handler transport contract (offline strict doubles)", async (t) => {
  const originals = envNames.map((name) => Deno.env.get(name));
  const originalFetch = globalThis.fetch, originalServe = Deno.serve;
  // Actual Supabase Auth clients install auto-refresh timers. Release only
  // timers created by this isolated fixture; keep Deno leak checks enabled.
  const originalInterval = globalThis.setInterval;
  const intervals: number[] = [];
  globalThis.setInterval = ((...args: Parameters<typeof setInterval>) => {
    const id = originalInterval(...args);
    intervals.push(id);
    return id;
  }) as typeof setInterval;
  let handler: (req: Request) => Promise<Response> = () => {
    throw new Error("handler missing");
  };
  const keys = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const keyBytes = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const pem = "-----BEGIN PRIVATE KEY-----\n" +
    btoa(String.fromCharCode(...keyBytes)) + "\n-----END PRIVATE KEY-----";
  const account = JSON.stringify({
    client_email: "synthetic@example.test",
    private_key: pem,
    token_uri: "https://forbidden.invalid",
  });
  const values = [
    "https://backend.invalid",
    "synthetic-anon",
    "synthetic-service",
    account,
    "",
    "23",
    "CERT",
  ];
  envNames.forEach((name, i) => Deno.env.set(name, values[i]));
  Object.defineProperty(Deno, "serve", {
    value: (fn: typeof handler) => {
      handler = fn;
    },
    configurable: true,
    writable: true,
  });
  try {
    await import("../../supabase/functions/verify-play-integrity/index.ts");
    const setup = async (options: Record<string, unknown> = {}) => {
      const sms = {
        subjectId: actor,
        nonce,
        receiverMomoNumberHash: receiver,
        clientEnvelopeId: "99570000-0000-4000-8000-000000000061",
        rawSender: "M-Money",
        rawBodySha256: "b".repeat(64),
        receivedAtDevice: null,
      };
      const requestHash = await smsIntegrityRequestHash(sms);
      const payload: Record<string, unknown> = {
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
          received_at_device: null,
        },
      };
      let oauthStarted = false,
        decodeStarted = false,
        completed = options.completed === true,
        terminal = false;
      const calls: Array<{ url: string; params?: Record<string, unknown> }> =
        [];
      const capabilityExpiresAt = new Date(Date.now() + 240000).toISOString();
      const result = () => ({
        status: "pass",
        action: payload.action,
        request_hash: payload.request_hash,
        package_name: "app.cool.mobile",
        app_verdict: "PLAY_RECOGNIZED",
        device_verdicts: ["MEETS_DEVICE_INTEGRITY"],
        native_capability: capability,
        capability_expires_at: capabilityExpiresAt,
      });
      const receipt = async (state: string) => ({
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
        result: state === "completed" ? result() : null,
      });
      const failure = (code: string) =>
        new Response(
          JSON.stringify({ code, message: "private SQL and token details" }),
          { status: 400, headers: { "content-type": "application/json" } },
        );
      globalThis.fetch = async (input, init) => {
        const url = typeof input === "string"
          ? input
          : input instanceof URL
          ? input.href
          : input.url;
        const headers = new Headers(
          init?.headers ??
            (input instanceof Request ? input.headers : undefined),
        );
        if (url === "https://backend.invalid/auth/v1/user") {
          calls.push({ url });
          assertEquals(headers.get("apikey"), "synthetic-anon");
          if (options.authDenied) {
            return new Response('{"msg":"denied"}', { status: 401 });
          }
          return new Response(
            JSON.stringify({
              id: actor,
              aud: "authenticated",
              role: "authenticated",
              email: "synthetic@example.test",
            }),
            { headers: { "content-type": "application/json" } },
          );
        }
        if (url.startsWith("https://backend.invalid/rest/v1/rpc/")) {
          assertEquals(headers.get("apikey"), "synthetic-service");
          if (!init?.signal) throw new Error("RPC lacks bounded abort signal");
          const params = JSON.parse(String(init.body)) as Record<
            string,
            unknown
          >;
          calls.push({ url, params });
          assertEquals(params.p_actor_id, actor);
          assertEquals(params.p_session_id, session);
          const name = url.split("/").at(-1);
          let value: unknown;
          if (name === "reserve_play_integrity_admission_v1") {
            assertEquals(
              params.p_token_sha256,
              await sha256Hex(String(payload.integrity_token)),
            );
            assertEquals(params.p_request_hash, payload.request_hash);
            if (options.reserveError) {
              return failure(String(options.reserveError));
            }
            if (terminal || (!completed && oauthStarted)) {
              return failure("55000");
            }
            value = await receipt(completed ? "completed" : "reserved");
            if (options.forgedReceipt) {
              value = { ...(value as object), session_id: capability };
            }
          } else if (name === "begin_play_integrity_admission_v1") {
            assertEquals(params.p_reservation_id, reservation);
            if (
              options.beginError ||
              (options.decodeDenied && params.p_phase === "decode")
            ) return failure("42501");
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
              return new Response(
                '{"code":"PGRST999","message":"lost acknowledgement"}',
                { status: 503 },
              );
            }
            value = result();
          } else if (name === "finish_play_integrity_admission_v1") {
            assertEquals(
              ["ambiguous", "rejected"].includes(String(params.p_outcome)),
              true,
            );
            if (!completed) terminal = true;
            value = {
              ok: true,
              state: completed ? "completed" : params.p_outcome,
            };
          } else throw new Error("Unexpected RPC " + name);
          return new Response(JSON.stringify(value), {
            headers: { "content-type": "application/json" },
          });
        }
        if (url === oauth || url === decode) {
          calls.push({ url });
          assertEquals(init?.redirect, "error");
          assertEquals(Boolean(init?.signal), true);
          assertEquals(oauthStarted, true);
          if (url === oauth) {
            const form = new URLSearchParams(String(init?.body));
            assertEquals(
              form.get("grant_type"),
              "urn:ietf:params:oauth:grant-type:jwt-bearer",
            );
            const claim = JSON.parse(
              atob(
                String(form.get("assertion")).split(".")[1].replaceAll("-", "+")
                  .replaceAll("_", "/"),
              ),
            );
            assertEquals(claim.aud, oauth);
            assertEquals(
              claim.scope,
              "https://www.googleapis.com/auth/playintegrity",
            );
            if (options.oauthFailure) {
              return new Response('{"error":"private provider failure"}', {
                status: 429,
              });
            }
            return new Response('{"access_token":"synthetic-access"}');
          }
          assertEquals(decodeStarted, true);
          assertEquals(headers.get("authorization"), "Bearer synthetic-access");
          assertEquals(
            JSON.parse(String(init?.body)).integrityToken,
            payload.integrity_token,
          );
          if (options.timeout) {
            throw new DOMException("synthetic abort", "AbortError");
          }
          if (options.decodeFailure) {
            return new Response('{"private":"provider body"}', { status: 429 });
          }
          if (options.malformedProvider) {
            return new Response('{"tokenPayloadExternal":null}');
          }
          return new Response(JSON.stringify({
            tokenPayloadExternal: {
              requestDetails: {
                requestPackageName: "app.cool.mobile",
                requestHash: payload.request_hash,
                timestampMillis: String(Date.now()),
              },
              appIntegrity: {
                packageName: "app.cool.mobile",
                appRecognitionVerdict: "PLAY_RECOGNIZED",
                versionCode: options.oldVersion ? "22" : "23",
                certificateSha256Digest: [
                  options.badCertificate ? "OTHER" : "CERT",
                ],
              },
              accountDetails: {
                appLicensingVerdict: options.unlicensed
                  ? "UNLICENSED"
                  : "LICENSED",
              },
              deviceIntegrity: {
                deviceRecognitionVerdict: [
                  options.weakDevice
                    ? "MEETS_BASIC_INTEGRITY"
                    : "MEETS_DEVICE_INTEGRITY",
                ],
              },
            },
          }));
        }
        throw new Error("Network URL outside strict mock " + url);
      };
      const send = (
        auth: string | null = authorization,
        body: unknown = payload,
      ) =>
        handler(
          new Request("https://edge.invalid/verify-play-integrity", {
            method: "POST",
            headers: {
              "content-type": "application/json",
              ...(auth ? { authorization: auth } : {}),
            },
            body: JSON.stringify(body),
          }),
        );
      return {
        payload,
        calls,
        send,
        result,
        google: () => calls.filter((c) => c.url === oauth || c.url === decode),
        rpcs: () => calls.filter((c) => c.params),
      };
    };
    for (
      const [label, auth, options] of [
        ["missing bearer", null, {}],
        ["Auth denies supplied bearer", authorization, { authDenied: true }],
        ["missing session", jwt({ sub: actor, role: "authenticated" }), {}],
        [
          "subject substitution",
          jwt({ sub: capability, session_id: session, role: "authenticated" }),
          {},
        ],
        [
          "service claim",
          jwt({ sub: actor, session_id: session, role: "service_role" }),
          {},
        ],
      ] as const
    ) {
      await t.step(
        label + " denies before Google and service RPC",
        async () => {
          const d = await setup(options);
          const response = await d.send(auth);
          assertEquals(response.status, 401);
          assertEquals(d.google().length, 0);
          assertEquals(d.rpcs().length, 0);
        },
      );
    }
    for (
      const [label, mutation, status] of [
        ["oversized request", { padding: "x".repeat(33000) }, 413],
        ["binding mismatch", { request_hash: "c".repeat(64) }, 400],
        ["malformed nonce", { nonce: "not-a-uuid" }, 400],
        ["incorrect subject", { subject_id: capability }, 400],
        ["permission missing", { sms_permission_granted: false }, 400],
      ] as const
    ) {
      await t.step(label + " denies before admission or Google", async () => {
        const d = await setup();
        const response = await d.send(authorization, {
          ...d.payload,
          ...mutation,
        });
        assertEquals(response.status, status);
        assertEquals(d.google().length, 0);
        assertEquals(d.rpcs().length, 0);
      });
    }
    for (
      const [label, code, status] of [
        ["per-actor quota", "53300", 429],
        ["global quota", "53300", 429],
        ["stale or revoked session", "42501", 403],
        ["malformed SQL binding", "22023", 400],
        ["replayed or uncertain request", "55000", 409],
        ["missing migration RPC", "PGRST202", 503],
      ] as const
    ) {
      await t.step(label + " produces stable pre-Google denial", async () => {
        const d = await setup({ reserveError: code });
        const response = await d.send();
        assertEquals(response.status, status);
        assertEquals(d.google().length, 0);
        assertEquals((await response.text()).includes("private"), false);
      });
    }
    await t.step(
      "forged reservation receipt cannot authorize external work",
      async () => {
        const d = await setup({ forgedReceipt: true });
        const response = await d.send();
        assertEquals(response.status, 503);
        assertEquals(d.google().length, 0);
      },
    );
    await t.step(
      "OAuth admission rejection makes zero provider calls",
      async () => {
        const d = await setup({ beginError: true });
        assertEquals((await d.send()).status, 403);
        assertEquals(d.google().length, 0);
      },
    );
    await t.step(
      "revocation between OAuth and decode blocks decode",
      async () => {
        const d = await setup({ decodeDenied: true });
        assertEquals((await d.send()).status, 403);
        assertEquals(d.google().map((c) => c.url), [oauth]);
      },
    );
    await t.step(
      "normal authorized workflow performs only two admitted fixed Google calls",
      async () => {
        const d = await setup();
        const response = await d.send();
        assertEquals(response.status, 200);
        assertEquals(await response.json(), d.result());
        assertEquals(d.google().map((c) => c.url), [oauth, decode]);
        assertEquals(d.rpcs().map((c) => c.url.split("/").at(-1)), [
          "reserve_play_integrity_admission_v1",
          "begin_play_integrity_admission_v1",
          "begin_play_integrity_admission_v1",
          "complete_play_integrity_admission_v1",
        ]);
      },
    );
    await t.step(
      "completed exact-action reconciliation returns capability without re-decoding",
      async () => {
        const d = await setup({ completed: true });
        const response = await d.send();
        assertEquals(response.status, 200);
        assertEquals(await response.json(), d.result());
        assertEquals(d.google().length, 0);
      },
    );
    for (
      const option of [
        "unlicensed",
        "oldVersion",
        "badCertificate",
        "weakDevice",
      ]
    ) {
      await t.step(
        option + " remains rejected after admission without mint",
        async () => {
          const d = await setup({ [option]: true });
          assertEquals((await d.send()).status, 403);
          assertEquals(
            d.rpcs().some((c) =>
              c.url.endsWith("complete_play_integrity_admission_v1")
            ),
            false,
          );
          assertEquals(d.rpcs().at(-1)?.params?.p_outcome, "rejected");
        },
      );
    }
    for (
      const option of [
        "oauthFailure",
        "decodeFailure",
        "timeout",
        "malformedProvider",
      ]
    ) {
      await t.step(
        option +
          " retains terminal/unknown evidence and never auto-retries token",
        async () => {
          const d = await setup({ [option]: true });
          const response = await d.send();
          assertEquals(response.status >= 400, true);
          assertEquals((await response.text()).includes("private"), false);
          const count = d.google().length;
          assertEquals(count, option === "oauthFailure" ? 1 : 2);
          assertEquals((await d.send()).status, 409);
          assertEquals(d.google().length, count);
          assertEquals(
            d.rpcs().some((c) =>
              c.url.endsWith("complete_play_integrity_admission_v1")
            ),
            false,
          );
        },
      );
    }
    await t.step(
      "uncertain successful completion reconciles original capability without second Google decode",
      async () => {
        const d = await setup({ lostCompletionAck: true });
        assertEquals((await d.send()).status, 503);
        const response = await d.send();
        assertEquals(response.status, 200);
        assertEquals(await response.json(), d.result());
        assertEquals(d.google().length, 2);
      },
    );
    await t.step("post-provider revocation cannot mint", async () => {
      const d = await setup({ completeDenied: true });
      assertEquals((await d.send()).status, 403);
      assertEquals(d.google().length, 2);
      assertEquals(d.rpcs().at(-1)?.params?.p_outcome, "ambiguous");
    });
    await t.step(
      "missing or malformed configuration fails before reservation and Google",
      async () => {
        for (
          const value of [
            "",
            "malformed",
            JSON.stringify({ client_email: null }),
          ]
        ) {
          const d = await setup();
          Deno.env.set("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON", value);
          const response = await d.send();
          assertEquals(response.status, 503);
          assertEquals(d.google().length, 0);
          assertEquals(d.rpcs().length, 0);
        }
        Deno.env.set("PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON", account);
      },
    );
  } finally {
    intervals.forEach((id) => clearInterval(id));
    globalThis.setInterval = originalInterval;
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", {
      value: originalServe,
      configurable: true,
      writable: true,
    });
    envNames.forEach((name, i) =>
      originals[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, originals[i]!)
    );
  }
});
