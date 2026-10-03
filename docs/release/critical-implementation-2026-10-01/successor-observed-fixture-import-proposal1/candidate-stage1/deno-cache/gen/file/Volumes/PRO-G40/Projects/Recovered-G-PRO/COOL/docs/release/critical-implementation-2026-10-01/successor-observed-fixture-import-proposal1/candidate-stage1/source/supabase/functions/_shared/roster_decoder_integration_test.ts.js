import { assertEquals } from "./test_assert.ts";
import { PublicError } from "./production_contract.ts";
import { decodeRosterSource } from "./roster_decoder.ts";
import { readRosterSource, rosterSha256 } from "./roster_provenance.ts";
import { createRosterImportHandler } from "../prepare-roster-import/handler.ts";
import { normalizeRosterCandidates } from "./roster_import.ts";
import { syntheticRosterAiApproval } from "./roster_ai_dispatch_test_fixture.ts";
const endpoint = Deno.env.get("ROSTER_DECODER_TEST_URL");
const secret = Deno.env.get("ROSTER_DECODER_TEST_SECRET");
const buildSha256 = Deno.env.get("ROSTER_DECODER_TEST_BUILD_SHA256");
const fixtures = Deno.env.get("ROSTER_DECODER_TEST_FIXTURES");
const enabled = !!endpoint && !!secret && !!fixtures;
function base64(bytes) {
  let binary = "";
  for (const byte of bytes)binary += String.fromCharCode(byte);
  return btoa(binary);
}
async function source(path, kind, mime, content) {
  const bytes = await Deno.readFile(`${fixtures}/${path}`);
  return readRosterSource({
    contract_version: 1,
    request_id: crypto.randomUUID(),
    source_type: kind,
    filename: path,
    mime_type: mime,
    content_base64: base64(bytes),
    ...kind === "xlsx" ? {
      derived_content: content
    } : {
      ai_consent: true,
      consent_version: "roster-ai-extraction-v1"
    }
  });
}
const tsv = "Member name\tMoMo name\tMoMo number\nÉlodie Niyonzima\tÉLODIE NIYONZIMA\t0789969001\nAline Uwase\tALINE UWASE\t0789969002";
for (const [path, kind, mime] of [
  [
    "scanned-multilingual.png",
    "image",
    "image/png"
  ],
  [
    "scanned-multilingual.jpg",
    "image",
    "image/jpeg"
  ],
  [
    "scanned-multilingual.webp",
    "image",
    "image/webp"
  ],
  [
    "scanned-multilingual.pdf",
    "pdf",
    "application/pdf"
  ],
  [
    "multilingual.xlsx",
    "xlsx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  ]
]){
  Deno.test({
    name: `Actual signed Linux decoder accepts ${path} and validates exact binding`,
    ignore: !enabled,
    fn: async ()=>{
      const input = await source(path, kind, mime, tsv);
      const decoded = await decodeRosterSource(input, await rosterSha256(input.bytes), crypto.randomUUID(), {
        url: endpoint,
        secret,
        buildSha256
      });
      assertEquals(decoded.source_size, input.bytes.length);
      assertEquals(decoded.derived_content, kind === "xlsx" ? tsv : null);
    }
  });
}
Deno.test({
  name: "Actual workbook bytes reject a substituted client TSV",
  ignore: !enabled,
  fn: async ()=>{
    const input = await source("multilingual.xlsx", "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", tsv.replace("0789969001", "0789969999"));
    try {
      await decodeRosterSource(input, await rosterSha256(input.bytes), crypto.randomUUID(), {
        url: endpoint,
        secret,
        buildSha256
      });
      throw new Error("Substitution accepted");
    } catch (error) {
      assertEquals(error instanceof PublicError && error.code, "roster_xlsx_derived_mismatch");
    }
  }
});
// Actual Linux codec + signed HTTP + unmodified upload handler. Auth/SQL/provider
// acknowledgements are recording fixtures; real SQL is tested separately by the
// guarded146 packet, and these tests never reach a provider or hosted service.
function fixturePromise(body) {
  try {
    return Promise.resolve(body());
  } catch (error) {
    return Promise.reject(error);
  }
}
async function integratedHandler(input) {
  const actor = "99690000-0000-4000-8000-000000000001";
  const session = "99690000-0000-4000-8000-000000000011";
  const reservation = crypto.randomUUID(), importId = crypto.randomUUID();
  const extractionId = input.ai ? crypto.randomUUID() : null;
  const calls = [];
  const hash = await rosterSha256(input.bytes);
  const derivedHash = input.derived ? await rosterSha256(input.derived) : null;
  let registered = false;
  const approval = input.ai ? await syntheticRosterAiApproval("synthetic-model", endpoint, buildSha256) : {};
  const handler = createRosterImportHandler({
    authenticate: ()=>fixturePromise(()=>({
          id: actor
        })),
    configuration: ()=>({
        ...approval,
        model: "synthetic-model",
        apiKey: "synthetic-never-transmitted",
        decoderUrl: endpoint,
        decoderSecret: secret,
        decoderBuildSha256: buildSha256
      }),
    fetch: (url, init)=>fixturePromise(()=>{
        calls.push("synthetic_provider");
        const headers = new Headers(init?.headers);
        assertEquals(headers.get("OpenAI-Organization"), "org_synthetic");
        assertEquals(headers.get("OpenAI-Project"), "proj_synthetic");
        assertEquals(url, "https://api.openai.com/v1/responses");
        assertEquals(registered, true);
        return new Response(JSON.stringify({
          id: "resp_synthetic_fixture",
          object: "response",
          status: "completed",
          error: null,
          incomplete_details: null,
          output: [
            {
              id: "msg_synthetic_fixture",
              type: "message",
              role: "assistant",
              status: "completed",
              content: [
                {
                  type: "output_text",
                  annotations: [],
                  text: JSON.stringify({
                    rows: [
                      {
                        source_row: 1,
                        member_name: "Élodie Niyonzima",
                        momo_name: "ÉLODIE NIYONZIMA",
                        momo_number: "0789969001",
                        confidence: 1
                      },
                      {
                        source_row: 2,
                        member_name: "Aline Uwase",
                        momo_name: "ALINE UWASE",
                        momo_number: "0789969002",
                        confidence: 1
                      }
                    ]
                  })
                }
              ]
            }
          ]
        }));
      }),
    rpc: (name, args)=>fixturePromise(()=>{
        calls.push(name);
        if (name === "reserve_roster_resources") {
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              reservation_id: reservation,
              request_id: input.requestId,
              actor_id: actor,
              session_id: session,
              source_sha256: hash,
              state: "reserved",
              replayed: false,
              expires_at: "2099-01-01T00:00:00Z"
            }
          };
        }
        if (name === "verify_roster_source_integrity") {
          assertEquals(args.p_decoder_build_sha256, buildSha256);
          assertEquals(typeof args.p_decoder_receipt_sha256, "string");
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              reservation_id: reservation,
              source_sha256: hash,
              derived_sha256: derivedHash,
              decoder_receipt_sha256: args.p_decoder_receipt_sha256,
              verified: true
            }
          };
        }
        if (name === "create_roster_import_source") {
          assertEquals(calls.slice(0, 3), [
            "reserve_roster_resources",
            "verify_roster_source_integrity",
            "create_roster_import_source"
          ]);
          registered = true;
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              request_id: input.requestId,
              import_id: importId,
              source_sha256: hash,
              source_size: input.bytes.length,
              source_kind: input.kind,
              extraction_id: extractionId,
              expires_at: "2099-01-01T00:00:00Z",
              derived_sha256: derivedHash,
              derived_assurance: input.kind === "xlsx" ? "client_derived_tsv" : null,
              state: "awaiting_preview",
              replayed: false,
              completed_preview: null,
              error_code: null
            }
          };
        }
        if (name === "finish_roster_resources") {
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              reservation_id: reservation,
              outcome: args.p_outcome,
              charged: true
            }
          };
        }
        assertEquals(name, "complete_roster_import_preview");
        return {
          error: null,
          data: {
            contract_version: 1,
            ok: true,
            import_id: importId,
            source_sha256: hash,
            source_kind: input.kind,
            source_receipt: {
              request_id: input.requestId,
              source_size: input.bytes.length,
              client_filename: input.filename,
              declared_mime: input.mime,
              detected_type: input.detected,
              derived_sha256: derivedHash,
              derived_assurance: input.kind === "xlsx" ? "client_derived_tsv" : null,
              extraction_id: extractionId,
              ai_consent: input.ai,
              consent_version: input.ai ? "roster-ai-extraction-v1" : null,
              parser_version: "collect-roster-parser-v1",
              schema_version: "collect-roster-rows-v1"
            },
            revision_id: crypto.randomUUID(),
            parent_revision_id: null,
            revision_number: 1,
            reviewed_rows_sha256: "a".repeat(64),
            ...normalizeRosterCandidates(args.p_candidates),
            can_submit: false,
            requires_human_review: true,
            processing_method: input.ai ? "openai_structured_extraction" : "deterministic",
            model: input.ai ? "synthetic-model" : null,
            expires_at: "2099-01-01T00:00:00Z"
          }
        };
      })
  });
  const claims = base64(new TextEncoder().encode(JSON.stringify({
    sub: actor,
    session_id: session,
    role: "authenticated"
  }))).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
  const response = await handler(new Request("http://local.test/prepare-roster-import", {
    method: "POST",
    headers: {
      authorization: `Bearer e30.${claims}.synthetic`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      contract_version: 1,
      request_id: input.requestId,
      source_type: input.kind,
      filename: input.filename,
      mime_type: input.mime,
      content_base64: input.base64,
      ...input.ai ? {
        ai_consent: true,
        consent_version: "roster-ai-extraction-v1"
      } : {
        derived_content: input.content
      }
    })
  }));
  return {
    response,
    calls
  };
}
for (const [path, kind, mime] of [
  [
    "scanned-multilingual.png",
    "image",
    "image/png"
  ],
  [
    "scanned-multilingual.jpg",
    "image",
    "image/jpeg"
  ],
  [
    "scanned-multilingual.webp",
    "image",
    "image/webp"
  ],
  [
    "scanned-multilingual.pdf",
    "pdf",
    "application/pdf"
  ],
  [
    "multilingual.xlsx",
    "xlsx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  ]
]){
  Deno.test({
    name: `Actual decoder and upload handler complete reviewed preview for ${path}`,
    ignore: !enabled,
    fn: async ()=>{
      const input = await source(path, kind, mime, tsv), result = await integratedHandler(input);
      assertEquals(result.response.status, 200);
      const body = await result.response.json();
      assertEquals(body.ready_count, 2);
      assertEquals(body.can_submit, false);
      assertEquals(body.requires_human_review, true);
      assertEquals(body.source_sha256, await rosterSha256(input.bytes));
      assertEquals(body.source_receipt.derived_sha256, input.derived ? await rosterSha256(input.derived) : null);
      assertEquals(result.calls, [
        "reserve_roster_resources",
        "verify_roster_source_integrity",
        "create_roster_import_source",
        ...input.ai ? [
          "synthetic_provider"
        ] : [],
        "complete_roster_import_preview",
        "finish_roster_resources"
      ]);
    }
  });
}
Deno.test({
  name: "Actual workbook substitution cannot reach source registration or provider through the upload handler",
  ignore: !enabled,
  fn: async ()=>{
    const input = await source("multilingual.xlsx", "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", tsv.replace("0789969001", "0789969999"));
    const { response, calls } = await integratedHandler(input);
    assertEquals(response.status, 422);
    assertEquals(await response.json(), {
      error: "roster_xlsx_derived_mismatch"
    });
    assertEquals(calls, [
      "reserve_roster_resources",
      "finish_roster_resources"
    ]);
  }
});
Deno.test({
  name: "Actual decoder HMAC rejects another signing secret",
  ignore: !enabled,
  fn: async ()=>{
    const input = await source("scanned-multilingual.png", "image", "image/png");
    try {
      await decodeRosterSource(input, await rosterSha256(input.bytes), crypto.randomUUID(), {
        url: endpoint,
        secret: "another-synthetic-signing-secret-with-32-bytes",
        buildSha256
      });
      throw new Error("Wrong key accepted");
    } catch (error) {
      assertEquals(error instanceof PublicError && error.code, "roster_decoder_unavailable");
    }
  }
});
Deno.test({
  name: "Actual rejected worksheet prevents source creation and provider transmission",
  ignore: !enabled,
  fn: async ()=>{
    const actor = "99690000-0000-4000-8000-000000000001", session = "99690000-0000-4000-8000-000000000011";
    const input = await source("formula.xlsx", "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", tsv);
    const reservation = crypto.randomUUID(), calls = [];
    const handler = createRosterImportHandler({
      authenticate: ()=>fixturePromise(()=>({
            id: actor
          })),
      configuration: ()=>({
          model: "synthetic-model",
          apiKey: "synthetic-never-used",
          decoderUrl: endpoint,
          decoderSecret: secret,
          decoderBuildSha256: buildSha256
        }),
      fetch: ()=>fixturePromise(()=>{
          calls.push("provider");
          throw new Error("Forbidden provider dispatch");
        }),
      rpc: (name, args)=>fixturePromise(()=>{
          calls.push(name);
          if (name === "reserve_roster_resources") {
            return {
              error: null,
              data: {
                contract_version: 1,
                ok: true,
                reservation_id: reservation,
                request_id: input.requestId,
                actor_id: actor,
                session_id: session,
                source_sha256: args.p_source_sha256,
                state: "reserved",
                replayed: false,
                expires_at: new Date(Date.now() + 180000).toISOString()
              }
            };
          }
          if (name === "finish_roster_resources") {
            return {
              error: null,
              data: {
                contract_version: 1,
                ok: true,
                reservation_id: reservation,
                outcome: args.p_outcome,
                charged: true
              }
            };
          }
          throw new Error("Unverified source reached durable create");
        })
    });
    const claims = base64(new TextEncoder().encode(JSON.stringify({
      sub: actor,
      session_id: session,
      role: "authenticated"
    }))).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
    const response = await handler(new Request("http://local.test/prepare-roster-import", {
      method: "POST",
      headers: {
        authorization: `Bearer e30.${claims}.synthetic`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        contract_version: 1,
        request_id: input.requestId,
        source_type: "xlsx",
        filename: "formula.xlsx",
        mime_type: input.mime,
        content_base64: input.base64,
        derived_content: tsv
      })
    }));
    assertEquals(response.status, 422);
    assertEquals(await response.json(), {
      error: "roster_xlsx_formula"
    });
    assertEquals(calls, [
      "reserve_roster_resources",
      "finish_roster_resources"
    ]);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2RlY29kZXJfaW50ZWdyYXRpb25fdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBhc3NlcnRFcXVhbHMgfSBmcm9tIFwiLi90ZXN0X2Fzc2VydC50c1wiO1xuaW1wb3J0IHsgUHVibGljRXJyb3IgfSBmcm9tIFwiLi9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5pbXBvcnQgeyBkZWNvZGVSb3N0ZXJTb3VyY2UgfSBmcm9tIFwiLi9yb3N0ZXJfZGVjb2Rlci50c1wiO1xuaW1wb3J0IHsgcmVhZFJvc3RlclNvdXJjZSwgcm9zdGVyU2hhMjU2IH0gZnJvbSBcIi4vcm9zdGVyX3Byb3ZlbmFuY2UudHNcIjtcbmltcG9ydCB7IGNyZWF0ZVJvc3RlckltcG9ydEhhbmRsZXIgfSBmcm9tIFwiLi4vcHJlcGFyZS1yb3N0ZXItaW1wb3J0L2hhbmRsZXIudHNcIjtcbmltcG9ydCB7IG5vcm1hbGl6ZVJvc3RlckNhbmRpZGF0ZXMgfSBmcm9tIFwiLi9yb3N0ZXJfaW1wb3J0LnRzXCI7XG5pbXBvcnQgeyBzeW50aGV0aWNSb3N0ZXJBaUFwcHJvdmFsIH0gZnJvbSBcIi4vcm9zdGVyX2FpX2Rpc3BhdGNoX3Rlc3RfZml4dHVyZS50c1wiO1xuXG5jb25zdCBlbmRwb2ludCA9IERlbm8uZW52LmdldChcIlJPU1RFUl9ERUNPREVSX1RFU1RfVVJMXCIpO1xuY29uc3Qgc2VjcmV0ID0gRGVuby5lbnYuZ2V0KFwiUk9TVEVSX0RFQ09ERVJfVEVTVF9TRUNSRVRcIik7XG5jb25zdCBidWlsZFNoYTI1NiA9IERlbm8uZW52LmdldChcIlJPU1RFUl9ERUNPREVSX1RFU1RfQlVJTERfU0hBMjU2XCIpO1xuY29uc3QgZml4dHVyZXMgPSBEZW5vLmVudi5nZXQoXCJST1NURVJfREVDT0RFUl9URVNUX0ZJWFRVUkVTXCIpO1xuY29uc3QgZW5hYmxlZCA9ICEhZW5kcG9pbnQgJiYgISFzZWNyZXQgJiYgISFmaXh0dXJlcztcbmZ1bmN0aW9uIGJhc2U2NChieXRlczogVWludDhBcnJheSk6IHN0cmluZyB7XG4gIGxldCBiaW5hcnkgPSBcIlwiO1xuICBmb3IgKGNvbnN0IGJ5dGUgb2YgYnl0ZXMpIGJpbmFyeSArPSBTdHJpbmcuZnJvbUNoYXJDb2RlKGJ5dGUpO1xuICByZXR1cm4gYnRvYShiaW5hcnkpO1xufVxuYXN5bmMgZnVuY3Rpb24gc291cmNlKFxuICBwYXRoOiBzdHJpbmcsXG4gIGtpbmQ6IFwiaW1hZ2VcIiB8IFwicGRmXCIgfCBcInhsc3hcIixcbiAgbWltZTogc3RyaW5nLFxuICBjb250ZW50Pzogc3RyaW5nLFxuKSB7XG4gIGNvbnN0IGJ5dGVzID0gYXdhaXQgRGVuby5yZWFkRmlsZShgJHtmaXh0dXJlc30vJHtwYXRofWApO1xuICByZXR1cm4gcmVhZFJvc3RlclNvdXJjZSh7XG4gICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICByZXF1ZXN0X2lkOiBjcnlwdG8ucmFuZG9tVVVJRCgpLFxuICAgIHNvdXJjZV90eXBlOiBraW5kLFxuICAgIGZpbGVuYW1lOiBwYXRoLFxuICAgIG1pbWVfdHlwZTogbWltZSxcbiAgICBjb250ZW50X2Jhc2U2NDogYmFzZTY0KGJ5dGVzKSxcbiAgICAuLi4oa2luZCA9PT0gXCJ4bHN4XCJcbiAgICAgID8geyBkZXJpdmVkX2NvbnRlbnQ6IGNvbnRlbnQgfVxuICAgICAgOiB7IGFpX2NvbnNlbnQ6IHRydWUsIGNvbnNlbnRfdmVyc2lvbjogXCJyb3N0ZXItYWktZXh0cmFjdGlvbi12MVwiIH0pLFxuICB9KTtcbn1cbmNvbnN0IHRzdiA9XG4gIFwiTWVtYmVyIG5hbWVcXHRNb01vIG5hbWVcXHRNb01vIG51bWJlclxcbsOJbG9kaWUgTml5b256aW1hXFx0w4lMT0RJRSBOSVlPTlpJTUFcXHQwNzg5OTY5MDAxXFxuQWxpbmUgVXdhc2VcXHRBTElORSBVV0FTRVxcdDA3ODk5NjkwMDJcIjtcbmZvciAoXG4gIGNvbnN0IFtwYXRoLCBraW5kLCBtaW1lXSBvZiBbXG4gICAgW1wic2Nhbm5lZC1tdWx0aWxpbmd1YWwucG5nXCIsIFwiaW1hZ2VcIiwgXCJpbWFnZS9wbmdcIl0sXG4gICAgW1wic2Nhbm5lZC1tdWx0aWxpbmd1YWwuanBnXCIsIFwiaW1hZ2VcIiwgXCJpbWFnZS9qcGVnXCJdLFxuICAgIFtcInNjYW5uZWQtbXVsdGlsaW5ndWFsLndlYnBcIiwgXCJpbWFnZVwiLCBcImltYWdlL3dlYnBcIl0sXG4gICAgW1wic2Nhbm5lZC1tdWx0aWxpbmd1YWwucGRmXCIsIFwicGRmXCIsIFwiYXBwbGljYXRpb24vcGRmXCJdLFxuICAgIFtcbiAgICAgIFwibXVsdGlsaW5ndWFsLnhsc3hcIixcbiAgICAgIFwieGxzeFwiLFxuICAgICAgXCJhcHBsaWNhdGlvbi92bmQub3BlbnhtbGZvcm1hdHMtb2ZmaWNlZG9jdW1lbnQuc3ByZWFkc2hlZXRtbC5zaGVldFwiLFxuICAgIF0sXG4gIF0gYXMgY29uc3Rcbikge1xuICBEZW5vLnRlc3Qoe1xuICAgIG5hbWU6XG4gICAgICBgQWN0dWFsIHNpZ25lZCBMaW51eCBkZWNvZGVyIGFjY2VwdHMgJHtwYXRofSBhbmQgdmFsaWRhdGVzIGV4YWN0IGJpbmRpbmdgLFxuICAgIGlnbm9yZTogIWVuYWJsZWQsXG4gICAgZm46IGFzeW5jICgpID0+IHtcbiAgICAgIGNvbnN0IGlucHV0ID0gYXdhaXQgc291cmNlKHBhdGgsIGtpbmQsIG1pbWUsIHRzdik7XG4gICAgICBjb25zdCBkZWNvZGVkID0gYXdhaXQgZGVjb2RlUm9zdGVyU291cmNlKFxuICAgICAgICBpbnB1dCxcbiAgICAgICAgYXdhaXQgcm9zdGVyU2hhMjU2KGlucHV0LmJ5dGVzKSxcbiAgICAgICAgY3J5cHRvLnJhbmRvbVVVSUQoKSxcbiAgICAgICAgeyB1cmw6IGVuZHBvaW50LCBzZWNyZXQsIGJ1aWxkU2hhMjU2IH0sXG4gICAgICApO1xuICAgICAgYXNzZXJ0RXF1YWxzKGRlY29kZWQuc291cmNlX3NpemUsIGlucHV0LmJ5dGVzLmxlbmd0aCk7XG4gICAgICBhc3NlcnRFcXVhbHMoZGVjb2RlZC5kZXJpdmVkX2NvbnRlbnQsIGtpbmQgPT09IFwieGxzeFwiID8gdHN2IDogbnVsbCk7XG4gICAgfSxcbiAgfSk7XG59XG5EZW5vLnRlc3Qoe1xuICBuYW1lOiBcIkFjdHVhbCB3b3JrYm9vayBieXRlcyByZWplY3QgYSBzdWJzdGl0dXRlZCBjbGllbnQgVFNWXCIsXG4gIGlnbm9yZTogIWVuYWJsZWQsXG4gIGZuOiBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgaW5wdXQgPSBhd2FpdCBzb3VyY2UoXG4gICAgICBcIm11bHRpbGluZ3VhbC54bHN4XCIsXG4gICAgICBcInhsc3hcIixcbiAgICAgIFwiYXBwbGljYXRpb24vdm5kLm9wZW54bWxmb3JtYXRzLW9mZmljZWRvY3VtZW50LnNwcmVhZHNoZWV0bWwuc2hlZXRcIixcbiAgICAgIHRzdi5yZXBsYWNlKFwiMDc4OTk2OTAwMVwiLCBcIjA3ODk5Njk5OTlcIiksXG4gICAgKTtcbiAgICB0cnkge1xuICAgICAgYXdhaXQgZGVjb2RlUm9zdGVyU291cmNlKFxuICAgICAgICBpbnB1dCxcbiAgICAgICAgYXdhaXQgcm9zdGVyU2hhMjU2KGlucHV0LmJ5dGVzKSxcbiAgICAgICAgY3J5cHRvLnJhbmRvbVVVSUQoKSxcbiAgICAgICAgeyB1cmw6IGVuZHBvaW50LCBzZWNyZXQsIGJ1aWxkU2hhMjU2IH0sXG4gICAgICApO1xuICAgICAgdGhyb3cgbmV3IEVycm9yKFwiU3Vic3RpdHV0aW9uIGFjY2VwdGVkXCIpO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICBhc3NlcnRFcXVhbHMoXG4gICAgICAgIGVycm9yIGluc3RhbmNlb2YgUHVibGljRXJyb3IgJiYgZXJyb3IuY29kZSxcbiAgICAgICAgXCJyb3N0ZXJfeGxzeF9kZXJpdmVkX21pc21hdGNoXCIsXG4gICAgICApO1xuICAgIH1cbiAgfSxcbn0pO1xuXG4vLyBBY3R1YWwgTGludXggY29kZWMgKyBzaWduZWQgSFRUUCArIHVubW9kaWZpZWQgdXBsb2FkIGhhbmRsZXIuIEF1dGgvU1FML3Byb3ZpZGVyXG4vLyBhY2tub3dsZWRnZW1lbnRzIGFyZSByZWNvcmRpbmcgZml4dHVyZXM7IHJlYWwgU1FMIGlzIHRlc3RlZCBzZXBhcmF0ZWx5IGJ5IHRoZVxuLy8gZ3VhcmRlZDE0NiBwYWNrZXQsIGFuZCB0aGVzZSB0ZXN0cyBuZXZlciByZWFjaCBhIHByb3ZpZGVyIG9yIGhvc3RlZCBzZXJ2aWNlLlxuZnVuY3Rpb24gZml4dHVyZVByb21pc2U8VD4oYm9keTogKCkgPT4gVCk6IFByb21pc2U8VD4ge1xuICB0cnkge1xuICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoYm9keSgpKTtcbiAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICByZXR1cm4gUHJvbWlzZS5yZWplY3QoZXJyb3IpO1xuICB9XG59XG5hc3luYyBmdW5jdGlvbiBpbnRlZ3JhdGVkSGFuZGxlcihpbnB1dDogQXdhaXRlZDxSZXR1cm5UeXBlPHR5cGVvZiBzb3VyY2U+Pikge1xuICBjb25zdCBhY3RvciA9IFwiOTk2OTAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxXCI7XG4gIGNvbnN0IHNlc3Npb24gPSBcIjk5NjkwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAxMVwiO1xuICBjb25zdCByZXNlcnZhdGlvbiA9IGNyeXB0by5yYW5kb21VVUlEKCksIGltcG9ydElkID0gY3J5cHRvLnJhbmRvbVVVSUQoKTtcbiAgY29uc3QgZXh0cmFjdGlvbklkID0gaW5wdXQuYWkgPyBjcnlwdG8ucmFuZG9tVVVJRCgpIDogbnVsbDtcbiAgY29uc3QgY2FsbHM6IHN0cmluZ1tdID0gW107XG4gIGNvbnN0IGhhc2ggPSBhd2FpdCByb3N0ZXJTaGEyNTYoaW5wdXQuYnl0ZXMpO1xuICBjb25zdCBkZXJpdmVkSGFzaCA9IGlucHV0LmRlcml2ZWQgPyBhd2FpdCByb3N0ZXJTaGEyNTYoaW5wdXQuZGVyaXZlZCkgOiBudWxsO1xuICBsZXQgcmVnaXN0ZXJlZCA9IGZhbHNlO1xuICBjb25zdCBhcHByb3ZhbCA9IGlucHV0LmFpXG4gICAgPyBhd2FpdCBzeW50aGV0aWNSb3N0ZXJBaUFwcHJvdmFsKFwic3ludGhldGljLW1vZGVsXCIsIGVuZHBvaW50LCBidWlsZFNoYTI1NilcbiAgICA6IHt9O1xuICBjb25zdCBoYW5kbGVyID0gY3JlYXRlUm9zdGVySW1wb3J0SGFuZGxlcih7XG4gICAgYXV0aGVudGljYXRlOiAoKSA9PiBmaXh0dXJlUHJvbWlzZSgoKSA9PiAoeyBpZDogYWN0b3IgfSkpLFxuICAgIGNvbmZpZ3VyYXRpb246ICgpID0+ICh7XG4gICAgICAuLi5hcHByb3ZhbCxcbiAgICAgIG1vZGVsOiBcInN5bnRoZXRpYy1tb2RlbFwiLFxuICAgICAgYXBpS2V5OiBcInN5bnRoZXRpYy1uZXZlci10cmFuc21pdHRlZFwiLFxuICAgICAgZGVjb2RlclVybDogZW5kcG9pbnQsXG4gICAgICBkZWNvZGVyU2VjcmV0OiBzZWNyZXQsXG4gICAgICBkZWNvZGVyQnVpbGRTaGEyNTY6IGJ1aWxkU2hhMjU2LFxuICAgIH0pLFxuICAgIGZldGNoOiAodXJsLCBpbml0KSA9PlxuICAgICAgZml4dHVyZVByb21pc2UoKCkgPT4ge1xuICAgICAgICBjYWxscy5wdXNoKFwic3ludGhldGljX3Byb3ZpZGVyXCIpO1xuICAgICAgICBjb25zdCBoZWFkZXJzID0gbmV3IEhlYWRlcnMoaW5pdD8uaGVhZGVycyk7XG4gICAgICAgIGFzc2VydEVxdWFscyhoZWFkZXJzLmdldChcIk9wZW5BSS1Pcmdhbml6YXRpb25cIiksIFwib3JnX3N5bnRoZXRpY1wiKTtcbiAgICAgICAgYXNzZXJ0RXF1YWxzKGhlYWRlcnMuZ2V0KFwiT3BlbkFJLVByb2plY3RcIiksIFwicHJval9zeW50aGV0aWNcIik7XG4gICAgICAgIGFzc2VydEVxdWFscyh1cmwsIFwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MS9yZXNwb25zZXNcIik7XG4gICAgICAgIGFzc2VydEVxdWFscyhyZWdpc3RlcmVkLCB0cnVlKTtcbiAgICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZShKU09OLnN0cmluZ2lmeSh7XG4gICAgICAgICAgaWQ6IFwicmVzcF9zeW50aGV0aWNfZml4dHVyZVwiLFxuICAgICAgICAgIG9iamVjdDogXCJyZXNwb25zZVwiLFxuICAgICAgICAgIHN0YXR1czogXCJjb21wbGV0ZWRcIixcbiAgICAgICAgICBlcnJvcjogbnVsbCxcbiAgICAgICAgICBpbmNvbXBsZXRlX2RldGFpbHM6IG51bGwsXG4gICAgICAgICAgb3V0cHV0OiBbe1xuICAgICAgICAgICAgaWQ6IFwibXNnX3N5bnRoZXRpY19maXh0dXJlXCIsXG4gICAgICAgICAgICB0eXBlOiBcIm1lc3NhZ2VcIixcbiAgICAgICAgICAgIHJvbGU6IFwiYXNzaXN0YW50XCIsXG4gICAgICAgICAgICBzdGF0dXM6IFwiY29tcGxldGVkXCIsXG4gICAgICAgICAgICBjb250ZW50OiBbe1xuICAgICAgICAgICAgICB0eXBlOiBcIm91dHB1dF90ZXh0XCIsXG4gICAgICAgICAgICAgIGFubm90YXRpb25zOiBbXSxcbiAgICAgICAgICAgICAgdGV4dDogSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICAgICAgICAgIHJvd3M6IFtcbiAgICAgICAgICAgICAgICAgIHtcbiAgICAgICAgICAgICAgICAgICAgc291cmNlX3JvdzogMSxcbiAgICAgICAgICAgICAgICAgICAgbWVtYmVyX25hbWU6IFwiw4lsb2RpZSBOaXlvbnppbWFcIixcbiAgICAgICAgICAgICAgICAgICAgbW9tb19uYW1lOiBcIsOJTE9ESUUgTklZT05aSU1BXCIsXG4gICAgICAgICAgICAgICAgICAgIG1vbW9fbnVtYmVyOiBcIjA3ODk5NjkwMDFcIixcbiAgICAgICAgICAgICAgICAgICAgY29uZmlkZW5jZTogMSxcbiAgICAgICAgICAgICAgICAgIH0sXG4gICAgICAgICAgICAgICAgICB7XG4gICAgICAgICAgICAgICAgICAgIHNvdXJjZV9yb3c6IDIsXG4gICAgICAgICAgICAgICAgICAgIG1lbWJlcl9uYW1lOiBcIkFsaW5lIFV3YXNlXCIsXG4gICAgICAgICAgICAgICAgICAgIG1vbW9fbmFtZTogXCJBTElORSBVV0FTRVwiLFxuICAgICAgICAgICAgICAgICAgICBtb21vX251bWJlcjogXCIwNzg5OTY5MDAyXCIsXG4gICAgICAgICAgICAgICAgICAgIGNvbmZpZGVuY2U6IDEsXG4gICAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICAgIH0pLFxuICAgICAgICAgICAgfV0sXG4gICAgICAgICAgfV0sXG4gICAgICAgIH0pKTtcbiAgICAgIH0pLFxuICAgIHJwYzogKG5hbWUsIGFyZ3MpID0+XG4gICAgICBmaXh0dXJlUHJvbWlzZSgoKSA9PiB7XG4gICAgICAgIGNhbGxzLnB1c2gobmFtZSk7XG4gICAgICAgIGlmIChuYW1lID09PSBcInJlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiKSB7XG4gICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgICAgICAgICBvazogdHJ1ZSxcbiAgICAgICAgICAgICAgcmVzZXJ2YXRpb25faWQ6IHJlc2VydmF0aW9uLFxuICAgICAgICAgICAgICByZXF1ZXN0X2lkOiBpbnB1dC5yZXF1ZXN0SWQsXG4gICAgICAgICAgICAgIGFjdG9yX2lkOiBhY3RvcixcbiAgICAgICAgICAgICAgc2Vzc2lvbl9pZDogc2Vzc2lvbixcbiAgICAgICAgICAgICAgc291cmNlX3NoYTI1NjogaGFzaCxcbiAgICAgICAgICAgICAgc3RhdGU6IFwicmVzZXJ2ZWRcIixcbiAgICAgICAgICAgICAgcmVwbGF5ZWQ6IGZhbHNlLFxuICAgICAgICAgICAgICBleHBpcmVzX2F0OiBcIjIwOTktMDEtMDFUMDA6MDA6MDBaXCIsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIH07XG4gICAgICAgIH1cbiAgICAgICAgaWYgKG5hbWUgPT09IFwidmVyaWZ5X3Jvc3Rlcl9zb3VyY2VfaW50ZWdyaXR5XCIpIHtcbiAgICAgICAgICBhc3NlcnRFcXVhbHMoYXJncy5wX2RlY29kZXJfYnVpbGRfc2hhMjU2LCBidWlsZFNoYTI1Nik7XG4gICAgICAgICAgYXNzZXJ0RXF1YWxzKHR5cGVvZiBhcmdzLnBfZGVjb2Rlcl9yZWNlaXB0X3NoYTI1NiwgXCJzdHJpbmdcIik7XG4gICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICAgICAgZGF0YToge1xuICAgICAgICAgICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgICAgICAgICBvazogdHJ1ZSxcbiAgICAgICAgICAgICAgcmVzZXJ2YXRpb25faWQ6IHJlc2VydmF0aW9uLFxuICAgICAgICAgICAgICBzb3VyY2Vfc2hhMjU2OiBoYXNoLFxuICAgICAgICAgICAgICBkZXJpdmVkX3NoYTI1NjogZGVyaXZlZEhhc2gsXG4gICAgICAgICAgICAgIGRlY29kZXJfcmVjZWlwdF9zaGEyNTY6IGFyZ3MucF9kZWNvZGVyX3JlY2VpcHRfc2hhMjU2LFxuICAgICAgICAgICAgICB2ZXJpZmllZDogdHJ1ZSxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgfTtcbiAgICAgICAgfVxuICAgICAgICBpZiAobmFtZSA9PT0gXCJjcmVhdGVfcm9zdGVyX2ltcG9ydF9zb3VyY2VcIikge1xuICAgICAgICAgIGFzc2VydEVxdWFscyhjYWxscy5zbGljZSgwLCAzKSwgW1xuICAgICAgICAgICAgXCJyZXNlcnZlX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgICAgICAgIFwidmVyaWZ5X3Jvc3Rlcl9zb3VyY2VfaW50ZWdyaXR5XCIsXG4gICAgICAgICAgICBcImNyZWF0ZV9yb3N0ZXJfaW1wb3J0X3NvdXJjZVwiLFxuICAgICAgICAgIF0pO1xuICAgICAgICAgIHJlZ2lzdGVyZWQgPSB0cnVlO1xuICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICBlcnJvcjogbnVsbCxcbiAgICAgICAgICAgIGRhdGE6IHtcbiAgICAgICAgICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgICAgICAgICAgb2s6IHRydWUsXG4gICAgICAgICAgICAgIHJlcXVlc3RfaWQ6IGlucHV0LnJlcXVlc3RJZCxcbiAgICAgICAgICAgICAgaW1wb3J0X2lkOiBpbXBvcnRJZCxcbiAgICAgICAgICAgICAgc291cmNlX3NoYTI1NjogaGFzaCxcbiAgICAgICAgICAgICAgc291cmNlX3NpemU6IGlucHV0LmJ5dGVzLmxlbmd0aCxcbiAgICAgICAgICAgICAgc291cmNlX2tpbmQ6IGlucHV0LmtpbmQsXG4gICAgICAgICAgICAgIGV4dHJhY3Rpb25faWQ6IGV4dHJhY3Rpb25JZCxcbiAgICAgICAgICAgICAgZXhwaXJlc19hdDogXCIyMDk5LTAxLTAxVDAwOjAwOjAwWlwiLFxuICAgICAgICAgICAgICBkZXJpdmVkX3NoYTI1NjogZGVyaXZlZEhhc2gsXG4gICAgICAgICAgICAgIGRlcml2ZWRfYXNzdXJhbmNlOiBpbnB1dC5raW5kID09PSBcInhsc3hcIlxuICAgICAgICAgICAgICAgID8gXCJjbGllbnRfZGVyaXZlZF90c3ZcIlxuICAgICAgICAgICAgICAgIDogbnVsbCxcbiAgICAgICAgICAgICAgc3RhdGU6IFwiYXdhaXRpbmdfcHJldmlld1wiLFxuICAgICAgICAgICAgICByZXBsYXllZDogZmFsc2UsXG4gICAgICAgICAgICAgIGNvbXBsZXRlZF9wcmV2aWV3OiBudWxsLFxuICAgICAgICAgICAgICBlcnJvcl9jb2RlOiBudWxsLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICB9O1xuICAgICAgICB9XG4gICAgICAgIGlmIChuYW1lID09PSBcImZpbmlzaF9yb3N0ZXJfcmVzb3VyY2VzXCIpIHtcbiAgICAgICAgICByZXR1cm4ge1xuICAgICAgICAgICAgZXJyb3I6IG51bGwsXG4gICAgICAgICAgICBkYXRhOiB7XG4gICAgICAgICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gICAgICAgICAgICAgIG9rOiB0cnVlLFxuICAgICAgICAgICAgICByZXNlcnZhdGlvbl9pZDogcmVzZXJ2YXRpb24sXG4gICAgICAgICAgICAgIG91dGNvbWU6IGFyZ3MucF9vdXRjb21lLFxuICAgICAgICAgICAgICBjaGFyZ2VkOiB0cnVlLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICB9O1xuICAgICAgICB9XG4gICAgICAgIGFzc2VydEVxdWFscyhuYW1lLCBcImNvbXBsZXRlX3Jvc3Rlcl9pbXBvcnRfcHJldmlld1wiKTtcbiAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICBlcnJvcjogbnVsbCxcbiAgICAgICAgICBkYXRhOiB7XG4gICAgICAgICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgICAgICAgb2s6IHRydWUsXG4gICAgICAgICAgICBpbXBvcnRfaWQ6IGltcG9ydElkLFxuICAgICAgICAgICAgc291cmNlX3NoYTI1NjogaGFzaCxcbiAgICAgICAgICAgIHNvdXJjZV9raW5kOiBpbnB1dC5raW5kLFxuICAgICAgICAgICAgc291cmNlX3JlY2VpcHQ6IHtcbiAgICAgICAgICAgICAgcmVxdWVzdF9pZDogaW5wdXQucmVxdWVzdElkLFxuICAgICAgICAgICAgICBzb3VyY2Vfc2l6ZTogaW5wdXQuYnl0ZXMubGVuZ3RoLFxuICAgICAgICAgICAgICBjbGllbnRfZmlsZW5hbWU6IGlucHV0LmZpbGVuYW1lLFxuICAgICAgICAgICAgICBkZWNsYXJlZF9taW1lOiBpbnB1dC5taW1lLFxuICAgICAgICAgICAgICBkZXRlY3RlZF90eXBlOiBpbnB1dC5kZXRlY3RlZCxcbiAgICAgICAgICAgICAgZGVyaXZlZF9zaGEyNTY6IGRlcml2ZWRIYXNoLFxuICAgICAgICAgICAgICBkZXJpdmVkX2Fzc3VyYW5jZTogaW5wdXQua2luZCA9PT0gXCJ4bHN4XCJcbiAgICAgICAgICAgICAgICA/IFwiY2xpZW50X2Rlcml2ZWRfdHN2XCJcbiAgICAgICAgICAgICAgICA6IG51bGwsXG4gICAgICAgICAgICAgIGV4dHJhY3Rpb25faWQ6IGV4dHJhY3Rpb25JZCxcbiAgICAgICAgICAgICAgYWlfY29uc2VudDogaW5wdXQuYWksXG4gICAgICAgICAgICAgIGNvbnNlbnRfdmVyc2lvbjogaW5wdXQuYWkgPyBcInJvc3Rlci1haS1leHRyYWN0aW9uLXYxXCIgOiBudWxsLFxuICAgICAgICAgICAgICBwYXJzZXJfdmVyc2lvbjogXCJjb2xsZWN0LXJvc3Rlci1wYXJzZXItdjFcIixcbiAgICAgICAgICAgICAgc2NoZW1hX3ZlcnNpb246IFwiY29sbGVjdC1yb3N0ZXItcm93cy12MVwiLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIHJldmlzaW9uX2lkOiBjcnlwdG8ucmFuZG9tVVVJRCgpLFxuICAgICAgICAgICAgcGFyZW50X3JldmlzaW9uX2lkOiBudWxsLFxuICAgICAgICAgICAgcmV2aXNpb25fbnVtYmVyOiAxLFxuICAgICAgICAgICAgcmV2aWV3ZWRfcm93c19zaGEyNTY6IFwiYVwiLnJlcGVhdCg2NCksXG4gICAgICAgICAgICAuLi5ub3JtYWxpemVSb3N0ZXJDYW5kaWRhdGVzKFxuICAgICAgICAgICAgICBhcmdzLnBfY2FuZGlkYXRlcyBhcyBQYXJhbWV0ZXJzPFxuICAgICAgICAgICAgICAgIHR5cGVvZiBub3JtYWxpemVSb3N0ZXJDYW5kaWRhdGVzXG4gICAgICAgICAgICAgID5bMF0sXG4gICAgICAgICAgICApLFxuICAgICAgICAgICAgY2FuX3N1Ym1pdDogZmFsc2UsXG4gICAgICAgICAgICByZXF1aXJlc19odW1hbl9yZXZpZXc6IHRydWUsXG4gICAgICAgICAgICBwcm9jZXNzaW5nX21ldGhvZDogaW5wdXQuYWlcbiAgICAgICAgICAgICAgPyBcIm9wZW5haV9zdHJ1Y3R1cmVkX2V4dHJhY3Rpb25cIlxuICAgICAgICAgICAgICA6IFwiZGV0ZXJtaW5pc3RpY1wiLFxuICAgICAgICAgICAgbW9kZWw6IGlucHV0LmFpID8gXCJzeW50aGV0aWMtbW9kZWxcIiA6IG51bGwsXG4gICAgICAgICAgICBleHBpcmVzX2F0OiBcIjIwOTktMDEtMDFUMDA6MDA6MDBaXCIsXG4gICAgICAgICAgfSxcbiAgICAgICAgfTtcbiAgICAgIH0pLFxuICB9KTtcbiAgY29uc3QgY2xhaW1zID0gYmFzZTY0KFxuICAgIG5ldyBUZXh0RW5jb2RlcigpLmVuY29kZShcbiAgICAgIEpTT04uc3RyaW5naWZ5KHtcbiAgICAgICAgc3ViOiBhY3RvcixcbiAgICAgICAgc2Vzc2lvbl9pZDogc2Vzc2lvbixcbiAgICAgICAgcm9sZTogXCJhdXRoZW50aWNhdGVkXCIsXG4gICAgICB9KSxcbiAgICApLFxuICApLnJlcGxhY2VBbGwoXCI9XCIsIFwiXCIpLnJlcGxhY2VBbGwoXCIrXCIsIFwiLVwiKS5yZXBsYWNlQWxsKFwiL1wiLCBcIl9cIik7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgaGFuZGxlcihcbiAgICBuZXcgUmVxdWVzdChcImh0dHA6Ly9sb2NhbC50ZXN0L3ByZXBhcmUtcm9zdGVyLWltcG9ydFwiLCB7XG4gICAgICBtZXRob2Q6IFwiUE9TVFwiLFxuICAgICAgaGVhZGVyczoge1xuICAgICAgICBhdXRob3JpemF0aW9uOiBgQmVhcmVyIGUzMC4ke2NsYWltc30uc3ludGhldGljYCxcbiAgICAgICAgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICB9LFxuICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgICByZXF1ZXN0X2lkOiBpbnB1dC5yZXF1ZXN0SWQsXG4gICAgICAgIHNvdXJjZV90eXBlOiBpbnB1dC5raW5kLFxuICAgICAgICBmaWxlbmFtZTogaW5wdXQuZmlsZW5hbWUsXG4gICAgICAgIG1pbWVfdHlwZTogaW5wdXQubWltZSxcbiAgICAgICAgY29udGVudF9iYXNlNjQ6IGlucHV0LmJhc2U2NCxcbiAgICAgICAgLi4uKGlucHV0LmFpXG4gICAgICAgICAgPyB7IGFpX2NvbnNlbnQ6IHRydWUsIGNvbnNlbnRfdmVyc2lvbjogXCJyb3N0ZXItYWktZXh0cmFjdGlvbi12MVwiIH1cbiAgICAgICAgICA6IHsgZGVyaXZlZF9jb250ZW50OiBpbnB1dC5jb250ZW50IH0pLFxuICAgICAgfSksXG4gICAgfSksXG4gICk7XG4gIHJldHVybiB7IHJlc3BvbnNlLCBjYWxscyB9O1xufVxuZm9yIChcbiAgY29uc3QgW3BhdGgsIGtpbmQsIG1pbWVdIG9mIFtcbiAgICBbXCJzY2FubmVkLW11bHRpbGluZ3VhbC5wbmdcIiwgXCJpbWFnZVwiLCBcImltYWdlL3BuZ1wiXSxcbiAgICBbXCJzY2FubmVkLW11bHRpbGluZ3VhbC5qcGdcIiwgXCJpbWFnZVwiLCBcImltYWdlL2pwZWdcIl0sXG4gICAgW1wic2Nhbm5lZC1tdWx0aWxpbmd1YWwud2VicFwiLCBcImltYWdlXCIsIFwiaW1hZ2Uvd2VicFwiXSxcbiAgICBbXCJzY2FubmVkLW11bHRpbGluZ3VhbC5wZGZcIiwgXCJwZGZcIiwgXCJhcHBsaWNhdGlvbi9wZGZcIl0sXG4gICAgW1xuICAgICAgXCJtdWx0aWxpbmd1YWwueGxzeFwiLFxuICAgICAgXCJ4bHN4XCIsXG4gICAgICBcImFwcGxpY2F0aW9uL3ZuZC5vcGVueG1sZm9ybWF0cy1vZmZpY2Vkb2N1bWVudC5zcHJlYWRzaGVldG1sLnNoZWV0XCIsXG4gICAgXSxcbiAgXSBhcyBjb25zdFxuKSB7XG4gIERlbm8udGVzdCh7XG4gICAgbmFtZTpcbiAgICAgIGBBY3R1YWwgZGVjb2RlciBhbmQgdXBsb2FkIGhhbmRsZXIgY29tcGxldGUgcmV2aWV3ZWQgcHJldmlldyBmb3IgJHtwYXRofWAsXG4gICAgaWdub3JlOiAhZW5hYmxlZCxcbiAgICBmbjogYXN5bmMgKCkgPT4ge1xuICAgICAgY29uc3QgaW5wdXQgPSBhd2FpdCBzb3VyY2UocGF0aCwga2luZCwgbWltZSwgdHN2KSxcbiAgICAgICAgcmVzdWx0ID0gYXdhaXQgaW50ZWdyYXRlZEhhbmRsZXIoaW5wdXQpO1xuICAgICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5yZXNwb25zZS5zdGF0dXMsIDIwMCk7XG4gICAgICBjb25zdCBib2R5ID0gYXdhaXQgcmVzdWx0LnJlc3BvbnNlLmpzb24oKTtcbiAgICAgIGFzc2VydEVxdWFscyhib2R5LnJlYWR5X2NvdW50LCAyKTtcbiAgICAgIGFzc2VydEVxdWFscyhib2R5LmNhbl9zdWJtaXQsIGZhbHNlKTtcbiAgICAgIGFzc2VydEVxdWFscyhib2R5LnJlcXVpcmVzX2h1bWFuX3JldmlldywgdHJ1ZSk7XG4gICAgICBhc3NlcnRFcXVhbHMoYm9keS5zb3VyY2Vfc2hhMjU2LCBhd2FpdCByb3N0ZXJTaGEyNTYoaW5wdXQuYnl0ZXMpKTtcbiAgICAgIGFzc2VydEVxdWFscyhcbiAgICAgICAgYm9keS5zb3VyY2VfcmVjZWlwdC5kZXJpdmVkX3NoYTI1NixcbiAgICAgICAgaW5wdXQuZGVyaXZlZCA/IGF3YWl0IHJvc3RlclNoYTI1NihpbnB1dC5kZXJpdmVkKSA6IG51bGwsXG4gICAgICApO1xuICAgICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5jYWxscywgW1xuICAgICAgICBcInJlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgICBcInZlcmlmeV9yb3N0ZXJfc291cmNlX2ludGVncml0eVwiLFxuICAgICAgICBcImNyZWF0ZV9yb3N0ZXJfaW1wb3J0X3NvdXJjZVwiLFxuICAgICAgICAuLi4oaW5wdXQuYWkgPyBbXCJzeW50aGV0aWNfcHJvdmlkZXJcIl0gOiBbXSksXG4gICAgICAgIFwiY29tcGxldGVfcm9zdGVyX2ltcG9ydF9wcmV2aWV3XCIsXG4gICAgICAgIFwiZmluaXNoX3Jvc3Rlcl9yZXNvdXJjZXNcIixcbiAgICAgIF0pO1xuICAgIH0sXG4gIH0pO1xufVxuRGVuby50ZXN0KHtcbiAgbmFtZTpcbiAgICBcIkFjdHVhbCB3b3JrYm9vayBzdWJzdGl0dXRpb24gY2Fubm90IHJlYWNoIHNvdXJjZSByZWdpc3RyYXRpb24gb3IgcHJvdmlkZXIgdGhyb3VnaCB0aGUgdXBsb2FkIGhhbmRsZXJcIixcbiAgaWdub3JlOiAhZW5hYmxlZCxcbiAgZm46IGFzeW5jICgpID0+IHtcbiAgICBjb25zdCBpbnB1dCA9IGF3YWl0IHNvdXJjZShcbiAgICAgIFwibXVsdGlsaW5ndWFsLnhsc3hcIixcbiAgICAgIFwieGxzeFwiLFxuICAgICAgXCJhcHBsaWNhdGlvbi92bmQub3BlbnhtbGZvcm1hdHMtb2ZmaWNlZG9jdW1lbnQuc3ByZWFkc2hlZXRtbC5zaGVldFwiLFxuICAgICAgdHN2LnJlcGxhY2UoXCIwNzg5OTY5MDAxXCIsIFwiMDc4OTk2OTk5OVwiKSxcbiAgICApO1xuICAgIGNvbnN0IHsgcmVzcG9uc2UsIGNhbGxzIH0gPSBhd2FpdCBpbnRlZ3JhdGVkSGFuZGxlcihpbnB1dCk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgNDIyKTtcbiAgICBhc3NlcnRFcXVhbHMoYXdhaXQgcmVzcG9uc2UuanNvbigpLCB7XG4gICAgICBlcnJvcjogXCJyb3N0ZXJfeGxzeF9kZXJpdmVkX21pc21hdGNoXCIsXG4gICAgfSk7XG4gICAgYXNzZXJ0RXF1YWxzKGNhbGxzLCBbXG4gICAgICBcInJlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgXCJmaW5pc2hfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgIF0pO1xuICB9LFxufSk7XG5EZW5vLnRlc3Qoe1xuICBuYW1lOiBcIkFjdHVhbCBkZWNvZGVyIEhNQUMgcmVqZWN0cyBhbm90aGVyIHNpZ25pbmcgc2VjcmV0XCIsXG4gIGlnbm9yZTogIWVuYWJsZWQsXG4gIGZuOiBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgaW5wdXQgPSBhd2FpdCBzb3VyY2UoXG4gICAgICBcInNjYW5uZWQtbXVsdGlsaW5ndWFsLnBuZ1wiLFxuICAgICAgXCJpbWFnZVwiLFxuICAgICAgXCJpbWFnZS9wbmdcIixcbiAgICApO1xuICAgIHRyeSB7XG4gICAgICBhd2FpdCBkZWNvZGVSb3N0ZXJTb3VyY2UoXG4gICAgICAgIGlucHV0LFxuICAgICAgICBhd2FpdCByb3N0ZXJTaGEyNTYoaW5wdXQuYnl0ZXMpLFxuICAgICAgICBjcnlwdG8ucmFuZG9tVVVJRCgpLFxuICAgICAgICB7XG4gICAgICAgICAgdXJsOiBlbmRwb2ludCxcbiAgICAgICAgICBzZWNyZXQ6IFwiYW5vdGhlci1zeW50aGV0aWMtc2lnbmluZy1zZWNyZXQtd2l0aC0zMi1ieXRlc1wiLFxuICAgICAgICAgIGJ1aWxkU2hhMjU2LFxuICAgICAgICB9LFxuICAgICAgKTtcbiAgICAgIHRocm93IG5ldyBFcnJvcihcIldyb25nIGtleSBhY2NlcHRlZFwiKTtcbiAgICB9IGNhdGNoIChlcnJvcikge1xuICAgICAgYXNzZXJ0RXF1YWxzKFxuICAgICAgICBlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yICYmIGVycm9yLmNvZGUsXG4gICAgICAgIFwicm9zdGVyX2RlY29kZXJfdW5hdmFpbGFibGVcIixcbiAgICAgICk7XG4gICAgfVxuICB9LFxufSk7XG5EZW5vLnRlc3Qoe1xuICBuYW1lOlxuICAgIFwiQWN0dWFsIHJlamVjdGVkIHdvcmtzaGVldCBwcmV2ZW50cyBzb3VyY2UgY3JlYXRpb24gYW5kIHByb3ZpZGVyIHRyYW5zbWlzc2lvblwiLFxuICBpZ25vcmU6ICFlbmFibGVkLFxuICBmbjogYXN5bmMgKCkgPT4ge1xuICAgIGNvbnN0IGFjdG9yID0gXCI5OTY5MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIixcbiAgICAgIHNlc3Npb24gPSBcIjk5NjkwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAxMVwiO1xuICAgIGNvbnN0IGlucHV0ID0gYXdhaXQgc291cmNlKFxuICAgICAgXCJmb3JtdWxhLnhsc3hcIixcbiAgICAgIFwieGxzeFwiLFxuICAgICAgXCJhcHBsaWNhdGlvbi92bmQub3BlbnhtbGZvcm1hdHMtb2ZmaWNlZG9jdW1lbnQuc3ByZWFkc2hlZXRtbC5zaGVldFwiLFxuICAgICAgdHN2LFxuICAgICk7XG4gICAgY29uc3QgcmVzZXJ2YXRpb24gPSBjcnlwdG8ucmFuZG9tVVVJRCgpLCBjYWxsczogc3RyaW5nW10gPSBbXTtcbiAgICBjb25zdCBoYW5kbGVyID0gY3JlYXRlUm9zdGVySW1wb3J0SGFuZGxlcih7XG4gICAgICBhdXRoZW50aWNhdGU6ICgpID0+IGZpeHR1cmVQcm9taXNlKCgpID0+ICh7IGlkOiBhY3RvciB9KSksXG4gICAgICBjb25maWd1cmF0aW9uOiAoKSA9PiAoe1xuICAgICAgICBtb2RlbDogXCJzeW50aGV0aWMtbW9kZWxcIixcbiAgICAgICAgYXBpS2V5OiBcInN5bnRoZXRpYy1uZXZlci11c2VkXCIsXG4gICAgICAgIGRlY29kZXJVcmw6IGVuZHBvaW50LFxuICAgICAgICBkZWNvZGVyU2VjcmV0OiBzZWNyZXQsXG4gICAgICAgIGRlY29kZXJCdWlsZFNoYTI1NjogYnVpbGRTaGEyNTYsXG4gICAgICB9KSxcbiAgICAgIGZldGNoOiAoKSA9PlxuICAgICAgICBmaXh0dXJlUHJvbWlzZSgoKSA9PiB7XG4gICAgICAgICAgY2FsbHMucHVzaChcInByb3ZpZGVyXCIpO1xuICAgICAgICAgIHRocm93IG5ldyBFcnJvcihcIkZvcmJpZGRlbiBwcm92aWRlciBkaXNwYXRjaFwiKTtcbiAgICAgICAgfSksXG4gICAgICBycGM6IChuYW1lLCBhcmdzKSA9PlxuICAgICAgICBmaXh0dXJlUHJvbWlzZSgoKSA9PiB7XG4gICAgICAgICAgY2FsbHMucHVzaChuYW1lKTtcbiAgICAgICAgICBpZiAobmFtZSA9PT0gXCJyZXNlcnZlX3Jvc3Rlcl9yZXNvdXJjZXNcIikge1xuICAgICAgICAgICAgcmV0dXJuIHtcbiAgICAgICAgICAgICAgZXJyb3I6IG51bGwsXG4gICAgICAgICAgICAgIGRhdGE6IHtcbiAgICAgICAgICAgICAgICBjb250cmFjdF92ZXJzaW9uOiAxLFxuICAgICAgICAgICAgICAgIG9rOiB0cnVlLFxuICAgICAgICAgICAgICAgIHJlc2VydmF0aW9uX2lkOiByZXNlcnZhdGlvbixcbiAgICAgICAgICAgICAgICByZXF1ZXN0X2lkOiBpbnB1dC5yZXF1ZXN0SWQsXG4gICAgICAgICAgICAgICAgYWN0b3JfaWQ6IGFjdG9yLFxuICAgICAgICAgICAgICAgIHNlc3Npb25faWQ6IHNlc3Npb24sXG4gICAgICAgICAgICAgICAgc291cmNlX3NoYTI1NjogYXJncy5wX3NvdXJjZV9zaGEyNTYsXG4gICAgICAgICAgICAgICAgc3RhdGU6IFwicmVzZXJ2ZWRcIixcbiAgICAgICAgICAgICAgICByZXBsYXllZDogZmFsc2UsXG4gICAgICAgICAgICAgICAgZXhwaXJlc19hdDogbmV3IERhdGUoRGF0ZS5ub3coKSArIDE4MDAwMCkudG9JU09TdHJpbmcoKSxcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIH07XG4gICAgICAgICAgfVxuICAgICAgICAgIGlmIChuYW1lID09PSBcImZpbmlzaF9yb3N0ZXJfcmVzb3VyY2VzXCIpIHtcbiAgICAgICAgICAgIHJldHVybiB7XG4gICAgICAgICAgICAgIGVycm9yOiBudWxsLFxuICAgICAgICAgICAgICBkYXRhOiB7XG4gICAgICAgICAgICAgICAgY29udHJhY3RfdmVyc2lvbjogMSxcbiAgICAgICAgICAgICAgICBvazogdHJ1ZSxcbiAgICAgICAgICAgICAgICByZXNlcnZhdGlvbl9pZDogcmVzZXJ2YXRpb24sXG4gICAgICAgICAgICAgICAgb3V0Y29tZTogYXJncy5wX291dGNvbWUsXG4gICAgICAgICAgICAgICAgY2hhcmdlZDogdHJ1ZSxcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIH07XG4gICAgICAgICAgfVxuICAgICAgICAgIHRocm93IG5ldyBFcnJvcihcIlVudmVyaWZpZWQgc291cmNlIHJlYWNoZWQgZHVyYWJsZSBjcmVhdGVcIik7XG4gICAgICAgIH0pLFxuICAgIH0pO1xuICAgIGNvbnN0IGNsYWltcyA9IGJhc2U2NChcbiAgICAgIG5ldyBUZXh0RW5jb2RlcigpLmVuY29kZShcbiAgICAgICAgSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICAgIHN1YjogYWN0b3IsXG4gICAgICAgICAgc2Vzc2lvbl9pZDogc2Vzc2lvbixcbiAgICAgICAgICByb2xlOiBcImF1dGhlbnRpY2F0ZWRcIixcbiAgICAgICAgfSksXG4gICAgICApLFxuICAgICkucmVwbGFjZUFsbChcIj1cIiwgXCJcIikucmVwbGFjZUFsbChcIitcIiwgXCItXCIpLnJlcGxhY2VBbGwoXCIvXCIsIFwiX1wiKTtcbiAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGhhbmRsZXIoXG4gICAgICBuZXcgUmVxdWVzdChcImh0dHA6Ly9sb2NhbC50ZXN0L3ByZXBhcmUtcm9zdGVyLWltcG9ydFwiLCB7XG4gICAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICAgIGhlYWRlcnM6IHtcbiAgICAgICAgICBhdXRob3JpemF0aW9uOiBgQmVhcmVyIGUzMC4ke2NsYWltc30uc3ludGhldGljYCxcbiAgICAgICAgICBcImNvbnRlbnQtdHlwZVwiOiBcImFwcGxpY2F0aW9uL2pzb25cIixcbiAgICAgICAgfSxcbiAgICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICAgIGNvbnRyYWN0X3ZlcnNpb246IDEsXG4gICAgICAgICAgcmVxdWVzdF9pZDogaW5wdXQucmVxdWVzdElkLFxuICAgICAgICAgIHNvdXJjZV90eXBlOiBcInhsc3hcIixcbiAgICAgICAgICBmaWxlbmFtZTogXCJmb3JtdWxhLnhsc3hcIixcbiAgICAgICAgICBtaW1lX3R5cGU6IGlucHV0Lm1pbWUsXG4gICAgICAgICAgY29udGVudF9iYXNlNjQ6IGlucHV0LmJhc2U2NCxcbiAgICAgICAgICBkZXJpdmVkX2NvbnRlbnQ6IHRzdixcbiAgICAgICAgfSksXG4gICAgICB9KSxcbiAgICApO1xuICAgIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDQyMik7XG4gICAgYXNzZXJ0RXF1YWxzKGF3YWl0IHJlc3BvbnNlLmpzb24oKSwgeyBlcnJvcjogXCJyb3N0ZXJfeGxzeF9mb3JtdWxhXCIgfSk7XG4gICAgYXNzZXJ0RXF1YWxzKGNhbGxzLCBbXG4gICAgICBcInJlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgICAgXCJmaW5pc2hfcm9zdGVyX3Jlc291cmNlc1wiLFxuICAgIF0pO1xuICB9LFxufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxZQUFZLFFBQVEsbUJBQW1CO0FBQ2hELFNBQVMsV0FBVyxRQUFRLDJCQUEyQjtBQUN2RCxTQUFTLGtCQUFrQixRQUFRLHNCQUFzQjtBQUN6RCxTQUFTLGdCQUFnQixFQUFFLFlBQVksUUFBUSx5QkFBeUI7QUFDeEUsU0FBUyx5QkFBeUIsUUFBUSxzQ0FBc0M7QUFDaEYsU0FBUyx5QkFBeUIsUUFBUSxxQkFBcUI7QUFDL0QsU0FBUyx5QkFBeUIsUUFBUSx1Q0FBdUM7QUFFakYsTUFBTSxXQUFXLEtBQUssR0FBRyxDQUFDLEdBQUcsQ0FBQztBQUM5QixNQUFNLFNBQVMsS0FBSyxHQUFHLENBQUMsR0FBRyxDQUFDO0FBQzVCLE1BQU0sY0FBYyxLQUFLLEdBQUcsQ0FBQyxHQUFHLENBQUM7QUFDakMsTUFBTSxXQUFXLEtBQUssR0FBRyxDQUFDLEdBQUcsQ0FBQztBQUM5QixNQUFNLFVBQVUsQ0FBQyxDQUFDLFlBQVksQ0FBQyxDQUFDLFVBQVUsQ0FBQyxDQUFDO0FBQzVDLFNBQVMsT0FBTyxLQUFpQjtFQUMvQixJQUFJLFNBQVM7RUFDYixLQUFLLE1BQU0sUUFBUSxNQUFPLFVBQVUsT0FBTyxZQUFZLENBQUM7RUFDeEQsT0FBTyxLQUFLO0FBQ2Q7QUFDQSxlQUFlLE9BQ2IsSUFBWSxFQUNaLElBQThCLEVBQzlCLElBQVksRUFDWixPQUFn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
// denoCacheMetadata=16065381757057742999,3630437342758454667