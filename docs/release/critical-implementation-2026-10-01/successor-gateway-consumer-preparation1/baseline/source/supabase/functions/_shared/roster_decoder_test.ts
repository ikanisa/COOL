import { assertEquals } from "./test_assert.ts";
import { decodeRosterSource } from "./roster_decoder.ts";
import { PublicError } from "./production_contract.ts";
import { readRosterSource, rosterSha256 } from "./roster_provenance.ts";
import { rosterBudgetReceipt } from "./roster_resource_budget.ts";
const encoder = new TextEncoder(),
  secret = "synthetic-decoder-test-key-with-32-bytes",
  build = "d".repeat(64);
const requestId = "99700000-0000-4000-8000-000000000101",
  reservationId = "99700000-0000-4000-8000-000000000102";
const source = readRosterSource({
  contract_version: 1,
  request_id: requestId,
  source_type: "image",
  filename: "unit.png",
  mime_type: "image/png",
  content_base64:
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=",
  ai_consent: true,
  consent_version: "roster-ai-extraction-v1",
});
function fake(patch: Record<string, unknown>, tamper = false): typeof fetch {
  return async (_url, init) => {
    const input = JSON.parse(String(init?.body));
    const payload = JSON.stringify({
      contract_version: 1,
      ok: true,
      request_id: input.request_id,
      reservation_id: input.reservation_id,
      nonce: input.nonce,
      issued_at: Math.floor(Date.now() / 1000),
      kind: input.kind,
      mime: input.mime,
      policy_version: "collect-roster-decoder-v1",
      decoder_build_sha256: build,
      toolchain: {
        python: "3.12",
        pillow: "12.3.0",
        pypdfium2: "5.2.0",
        pypdf: "6.19.0",
        openpyxl: "3.1.5",
        defusedxml: "0.7.1",
      },
      source_sha256: input.source_sha256,
      source_size: source.bytes.length,
      derived_sha256: null,
      derived_content: null,
      frames: 1,
      pages: 0,
      pixels: 6,
      expanded_bytes: 24,
      ...patch,
    });
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = [
      ...new Uint8Array(
        await crypto.subtle.sign("HMAC", key, encoder.encode(payload)),
      ),
    ].map((v) => v.toString(16).padStart(2, "0")).join("");
    return new Response(
      JSON.stringify({
        payload,
        signature: tamper ? "0".repeat(64) : signature,
      }),
    );
  };
}
for (
  const [name, patch] of Object.entries({
    wrong_source: { source_sha256: "a".repeat(64) },
    wrong_request: { request_id: reservationId },
    wrong_reservation: { reservation_id: requestId },
    replayed_nonce: { nonce: reservationId },
    stale_signature: { issued_at: 1 },
    wrong_policy: { policy_version: "client-claimed-safe" },
    wrong_build: { decoder_build_sha256: "e".repeat(64) },
    wrong_toolchain: { toolchain: { python: "3.12" } },
    old_pillow: {
      toolchain: {
        python: "3.12",
        pillow: "12.0.0",
        pypdfium2: "5.2.0",
        pypdf: "6.19.0",
        openpyxl: "3.1.5",
        defusedxml: "0.7.1",
      },
    },
    old_pypdf: {
      toolchain: {
        python: "3.12",
        pillow: "12.3.0",
        pypdfium2: "5.2.0",
        pypdf: "6.7.0",
        openpyxl: "3.1.5",
        defusedxml: "0.7.1",
      },
    },
    wrong_size: { source_size: 1 },
    extra_key: { approved: true },
    frames_exceeded: { frames: 21 },
    pixels_exceeded: { pixels: 40000001 },
    negative_expansion: { expanded_bytes: -1 },
    unexpected_derived: {
      derived_content: "fake",
      derived_sha256: "a".repeat(64),
    },
  })
) {
  Deno.test(`decoder receipt rejects ${name} despite a valid synthetic HMAC`, async () => {
    try {
      await decodeRosterSource(
        source,
        await rosterSha256(source.bytes),
        reservationId,
        { url: "http://localhost/decode", secret, buildSha256: build },
        fake(patch),
      );
      throw new Error("Invalid receipt accepted");
    } catch (error) {
      assertEquals(
        error instanceof PublicError && error.code,
        "roster_decoder_receipt_invalid",
      );
    }
  });
}
Deno.test("decoder receipt rejects tampered signature", async () => {
  try {
    await decodeRosterSource(
      source,
      await rosterSha256(source.bytes),
      reservationId,
      { url: "http://localhost/decode", secret, buildSha256: build },
      fake({}, true),
    );
    throw new Error("Tampered signature accepted");
  } catch (error) {
    assertEquals(
      error instanceof PublicError && error.code,
      "roster_decoder_receipt_invalid",
    );
  }
});
const expected = {
  requestId,
  actorId: "99700000-0000-4000-8000-000000000001",
  sessionId: "99700000-0000-4000-8000-000000000011",
  sourceHash: "a".repeat(64),
};
const receipt = {
  contract_version: 1,
  ok: true,
  reservation_id: reservationId,
  request_id: expected.requestId,
  actor_id: expected.actorId,
  session_id: expected.sessionId,
  source_sha256: expected.sourceHash,
  state: "reserved",
  replayed: false,
  expires_at: "2099-01-01T00:00:00Z",
};
for (
  const patch of [
    { actor_id: reservationId },
    { session_id: reservationId },
    { source_sha256: "b".repeat(64) },
    { reservation_id: "bad" },
    { state: "active" },
    { expires_at: "January 1, 2099" },
    { ok: 1 },
    { extra: true },
  ]
) {
  Deno.test(`resource acknowledgement rejects ${JSON.stringify(patch)}`, () => {
    try {
      rosterBudgetReceipt({ ...receipt, ...patch }, expected);
      throw new Error("Invalid budget ACK accepted");
    } catch (error) {
      assertEquals(
        error instanceof PublicError && error.code,
        "roster_budget_receipt_invalid",
      );
      assertEquals((error as PublicError).status, 503);
    }
  });
}
Deno.test("replayed or expired active budget never releases provider work", () => {
  for (
    const patch of [{ replayed: true }, { expires_at: "2000-01-01T00:00:00Z" }]
  ) {
    try {
      rosterBudgetReceipt({ ...receipt, ...patch }, expected);
      throw new Error("In-progress reservation accepted");
    } catch (error) {
      assertEquals(
        error instanceof PublicError && error.code,
        "roster_resource_in_progress",
      );
    }
  }
});
