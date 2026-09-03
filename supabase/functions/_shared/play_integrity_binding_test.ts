import { assertEquals } from "./test_assert.ts";
import {
  smsCapabilityPayload,
  type SmsIntegrityRequest,
  smsIntegrityRequestHash,
} from "./play_integrity_binding.ts";

const fixture: SmsIntegrityRequest = {
  subjectId: "97000000-0000-4000-8000-000000000001",
  nonce: "97000000-0000-4000-8000-000000000099",
  receiverMomoNumberHash:
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  clientEnvelopeId: "97000000-0000-4000-8000-000000000111",
  rawSender: "M-Money",
  rawBodySha256:
    "87f6ffa8da00a032866e1dc0aa34cf23973850f625ae0be3adada5f6a255d7f4",
  receivedAtDevice: "2026-09-03T10:00:00.000Z",
};

Deno.test("SMS Play Integrity hash matches the native client contract", async () => {
  assertEquals(
    await smsIntegrityRequestHash(fixture),
    "16f277bbeb637cf8bb8da6a4a90e98451232d996278497444437329fa3c1b26b",
  );
  assertEquals(smsCapabilityPayload(fixture), {
    receiver_momo_number_hash: fixture.receiverMomoNumberHash,
    client_envelope_id: fixture.clientEnvelopeId,
    raw_sender: fixture.rawSender,
    raw_body_sha256: fixture.rawBodySha256,
    received_at_device: fixture.receivedAtDevice,
  });
});

Deno.test("SMS Play Integrity hash changes when provider evidence changes", async () => {
  const original = await smsIntegrityRequestHash(fixture);
  assertEquals(
    await smsIntegrityRequestHash({ ...fixture, rawSender: "Unknown" }) ===
      original,
    false,
  );
  assertEquals(
    await smsIntegrityRequestHash({
      ...fixture,
      rawBodySha256: "b".repeat(64),
    }) === original,
    false,
  );
  assertEquals(
    await smsIntegrityRequestHash({
      ...fixture,
      clientEnvelopeId: "97000000-0000-4000-8000-000000000112",
    }) === original,
    false,
  );
});
