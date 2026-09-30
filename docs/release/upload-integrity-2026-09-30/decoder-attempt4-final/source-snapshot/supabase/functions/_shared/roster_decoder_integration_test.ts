import { assertEquals } from "./test_assert.ts";
import { PublicError } from "./production_contract.ts";
import { decodeRosterSource } from "./roster_decoder.ts";
import { readRosterSource, rosterSha256 } from "./roster_provenance.ts";
import { createRosterImportHandler } from "../prepare-roster-import/handler.ts";

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
