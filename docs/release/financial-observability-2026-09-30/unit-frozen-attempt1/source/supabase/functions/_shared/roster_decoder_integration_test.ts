import { assertEquals } from "./test_assert.ts";
import { PublicError } from "./production_contract.ts";
import { decodeRosterSource } from "./roster_decoder.ts";
import { readRosterSource, rosterSha256 } from "./roster_provenance.ts";
import { createRosterImportHandler } from "../prepare-roster-import/handler.ts";
import { normalizeRosterCandidates } from "./roster_import.ts";

const endpoint = Deno.env.get("ROSTER_DECODER_TEST_URL");
const secret = Deno.env.get("ROSTER_DECODER_TEST_SECRET");
const buildSha256 = Deno.env.get("ROSTER_DECODER_TEST_BUILD_SHA256");
const fixtures = Deno.env.get("ROSTER_DECODER_TEST_FIXTURES");
const enabled = !!endpoint && !!secret && !!fixtures;
function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
async function source(
  path: string,
  kind: "image" | "pdf" | "xlsx",
  mime: string,
  content?: string,
) {
  const bytes = await Deno.readFile(`${fixtures}/${path}`);
  return readRosterSource({
    contract_version: 1,
    request_id: crypto.randomUUID(),
    source_type: kind,
    filename: path,
    mime_type: mime,
    content_base64: base64(bytes),
    ...(kind === "xlsx"
      ? { derived_content: content }
      : { ai_consent: true, consent_version: "roster-ai-extraction-v1" }),
  });
}
const tsv =
  "Member name\tMoMo name\tMoMo number\nÉlodie Niyonzima\tÉLODIE NIYONZIMA\t0789969001\nAline Uwase\tALINE UWASE\t0789969002";
for (
  const [path, kind, mime] of [
    ["scanned-multilingual.png", "image", "image/png"],
    ["scanned-multilingual.jpg", "image", "image/jpeg"],
    ["scanned-multilingual.webp", "image", "image/webp"],
    ["scanned-multilingual.pdf", "pdf", "application/pdf"],
    [
      "multilingual.xlsx",
      "xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ],
  ] as const
) {
  Deno.test({
    name:
      `Actual signed Linux decoder accepts ${path} and validates exact binding`,
    ignore: !enabled,
    fn: async () => {
      const input = await source(path, kind, mime, tsv);
      const decoded = await decodeRosterSource(
        input,
        await rosterSha256(input.bytes),
        crypto.randomUUID(),
        { url: endpoint, secret, buildSha256 },
      );
      assertEquals(decoded.source_size, input.bytes.length);
      assertEquals(decoded.derived_content, kind === "xlsx" ? tsv : null);
    },
  });
}
Deno.test({
  name: "Actual workbook bytes reject a substituted client TSV",
  ignore: !enabled,
  fn: async () => {
    const input = await source(
      "multilingual.xlsx",
      "xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      tsv.replace("0789969001", "0789969999"),
    );
    try {
      await decodeRosterSource(
        input,
        await rosterSha256(input.bytes),
        crypto.randomUUID(),
        { url: endpoint, secret, buildSha256 },
      );
      throw new Error("Substitution accepted");
    } catch (error) {
      assertEquals(
        error instanceof PublicError && error.code,
        "roster_xlsx_derived_mismatch",
      );
    }
  },
});

// Actual Linux codec + signed HTTP + unmodified upload handler. Auth/SQL/provider
// acknowledgements are recording fixtures; real SQL is tested separately by the
// guarded146 packet, and these tests never reach a provider or hosted service.
async function integratedHandler(input: Awaited<ReturnType<typeof source>>) {
  const actor = "99690000-0000-4000-8000-000000000001";
  const session = "99690000-0000-4000-8000-000000000011";
  const reservation = crypto.randomUUID(), importId = crypto.randomUUID();
  const extractionId = input.ai ? crypto.randomUUID() : null;
  const calls: string[] = [];
  const hash = await rosterSha256(input.bytes);
  const derivedHash = input.derived ? await rosterSha256(input.derived) : null;
  let registered = false;
  const handler = createRosterImportHandler({
    authenticate: async () => ({ id: actor }),
    configuration: () => ({
      model: "synthetic-model",
      apiKey: "synthetic-never-transmitted",
      decoderUrl: endpoint,
      decoderSecret: secret,
      decoderBuildSha256: buildSha256,
    }),
    fetch: async (url) => {
      calls.push("synthetic_provider");
      assertEquals(url, "https://api.openai.com/v1/responses");
      assertEquals(registered, true);
      return new Response(JSON.stringify({
        id: "resp_synthetic_fixture",
        object: "response",
        status: "completed",
        error: null,
        incomplete_details: null,
        output: [{
          id: "msg_synthetic_fixture",
          type: "message",
          role: "assistant",
          status: "completed",
          content: [{
            type: "output_text",
            annotations: [],
            text: JSON.stringify({
              rows: [
                {
                  source_row: 1,
                  member_name: "Élodie Niyonzima",
                  momo_name: "ÉLODIE NIYONZIMA",
                  momo_number: "0789969001",
                  confidence: 1,
                },
                {
                  source_row: 2,
                  member_name: "Aline Uwase",
                  momo_name: "ALINE UWASE",
                  momo_number: "0789969002",
                  confidence: 1,
                },
              ],
            }),
          }],
        }],
      }));
    },
    rpc: async (name, args) => {
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
            expires_at: "2099-01-01T00:00:00Z",
          },
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
            verified: true,
          },
        };
      }
      if (name === "create_roster_import_source") {
        assertEquals(calls.slice(0, 3), [
          "reserve_roster_resources",
          "verify_roster_source_integrity",
          "create_roster_import_source",
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
            derived_assurance: input.kind === "xlsx"
              ? "client_derived_tsv"
              : null,
            state: "awaiting_preview",
            replayed: false,
            completed_preview: null,
            error_code: null,
          },
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
            charged: true,
          },
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
            derived_assurance: input.kind === "xlsx"
              ? "client_derived_tsv"
              : null,
            extraction_id: extractionId,
            ai_consent: input.ai,
            consent_version: input.ai ? "roster-ai-extraction-v1" : null,
            parser_version: "collect-roster-parser-v1",
            schema_version: "collect-roster-rows-v1",
          },
          revision_id: crypto.randomUUID(),
          parent_revision_id: null,
          revision_number: 1,
          reviewed_rows_sha256: "a".repeat(64),
          ...normalizeRosterCandidates(
            args.p_candidates as Parameters<
              typeof normalizeRosterCandidates
            >[0],
          ),
          can_submit: false,
          requires_human_review: true,
          processing_method: input.ai
            ? "openai_structured_extraction"
            : "deterministic",
          model: input.ai ? "synthetic-model" : null,
          expires_at: "2099-01-01T00:00:00Z",
        },
      };
    },
  });
  const claims = base64(
    new TextEncoder().encode(
      JSON.stringify({
        sub: actor,
        session_id: session,
        role: "authenticated",
      }),
    ),
  ).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
  const response = await handler(
    new Request("http://local.test/prepare-roster-import", {
      method: "POST",
      headers: {
        authorization: `Bearer e30.${claims}.synthetic`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        contract_version: 1,
        request_id: input.requestId,
        source_type: input.kind,
        filename: input.filename,
        mime_type: input.mime,
        content_base64: input.base64,
        ...(input.ai
          ? { ai_consent: true, consent_version: "roster-ai-extraction-v1" }
          : { derived_content: input.content }),
      }),
    }),
  );
  return { response, calls };
}
for (
  const [path, kind, mime] of [
    ["scanned-multilingual.png", "image", "image/png"],
    ["scanned-multilingual.jpg", "image", "image/jpeg"],
    ["scanned-multilingual.webp", "image", "image/webp"],
    ["scanned-multilingual.pdf", "pdf", "application/pdf"],
    [
      "multilingual.xlsx",
      "xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ],
  ] as const
) {
  Deno.test({
    name:
      `Actual decoder and upload handler complete reviewed preview for ${path}`,
    ignore: !enabled,
    fn: async () => {
      const input = await source(path, kind, mime, tsv),
        result = await integratedHandler(input);
      assertEquals(result.response.status, 200);
      const body = await result.response.json();
      assertEquals(body.ready_count, 2);
      assertEquals(body.can_submit, false);
      assertEquals(body.requires_human_review, true);
      assertEquals(body.source_sha256, await rosterSha256(input.bytes));
      assertEquals(
        body.source_receipt.derived_sha256,
        input.derived ? await rosterSha256(input.derived) : null,
      );
      assertEquals(result.calls, [
        "reserve_roster_resources",
        "verify_roster_source_integrity",
        "create_roster_import_source",
        ...(input.ai ? ["synthetic_provider"] : []),
        "complete_roster_import_preview",
        "finish_roster_resources",
      ]);
    },
  });
}
Deno.test({
  name:
    "Actual workbook substitution cannot reach source registration or provider through the upload handler",
  ignore: !enabled,
  fn: async () => {
    const input = await source(
      "multilingual.xlsx",
      "xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      tsv.replace("0789969001", "0789969999"),
    );
    const { response, calls } = await integratedHandler(input);
    assertEquals(response.status, 422);
    assertEquals(await response.json(), {
      error: "roster_xlsx_derived_mismatch",
    });
    assertEquals(calls, [
      "reserve_roster_resources",
      "finish_roster_resources",
    ]);
  },
});
Deno.test({
  name: "Actual decoder HMAC rejects another signing secret",
  ignore: !enabled,
  fn: async () => {
    const input = await source(
      "scanned-multilingual.png",
      "image",
      "image/png",
    );
    try {
      await decodeRosterSource(
        input,
        await rosterSha256(input.bytes),
        crypto.randomUUID(),
        {
          url: endpoint,
          secret: "another-synthetic-signing-secret-with-32-bytes",
          buildSha256,
        },
      );
      throw new Error("Wrong key accepted");
    } catch (error) {
      assertEquals(
        error instanceof PublicError && error.code,
        "roster_decoder_unavailable",
      );
    }
  },
});
Deno.test({
  name:
    "Actual rejected worksheet prevents source creation and provider transmission",
  ignore: !enabled,
  fn: async () => {
    const actor = "99690000-0000-4000-8000-000000000001",
      session = "99690000-0000-4000-8000-000000000011";
    const input = await source(
      "formula.xlsx",
      "xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      tsv,
    );
    const reservation = crypto.randomUUID(), calls: string[] = [];
    const handler = createRosterImportHandler({
      authenticate: async () => ({ id: actor }),
      configuration: () => ({
        model: "synthetic-model",
        apiKey: "synthetic-never-used",
        decoderUrl: endpoint,
        decoderSecret: secret,
        decoderBuildSha256: buildSha256,
      }),
      fetch: async () => {
        calls.push("provider");
        throw new Error("Forbidden provider dispatch");
      },
      rpc: async (name, args) => {
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
              expires_at: new Date(Date.now() + 180000).toISOString(),
            },
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
              charged: true,
            },
          };
        }
        throw new Error("Unverified source reached durable create");
      },
    });
    const claims = base64(
      new TextEncoder().encode(
        JSON.stringify({
          sub: actor,
          session_id: session,
          role: "authenticated",
        }),
      ),
    ).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
    const response = await handler(
      new Request("http://local.test/prepare-roster-import", {
        method: "POST",
        headers: {
          authorization: `Bearer e30.${claims}.synthetic`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          contract_version: 1,
          request_id: input.requestId,
          source_type: "xlsx",
          filename: "formula.xlsx",
          mime_type: input.mime,
          content_base64: input.base64,
          derived_content: tsv,
        }),
      }),
    );
    assertEquals(response.status, 422);
    assertEquals(await response.json(), { error: "roster_xlsx_formula" });
    assertEquals(calls, [
      "reserve_roster_resources",
      "finish_roster_resources",
    ]);
  },
});
