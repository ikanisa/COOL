import { assertEquals } from "./test_assert.ts";
import { PublicError } from "./production_contract.ts";
import {
  integrityAdmissionError,
  integrityAdmissionReceipt,
  integrityResult,
} from "./integrity_admission.ts";

const binding = {
  actorId: "99570000-0000-4000-8000-000000000001",
  sessionId: "99570000-0000-4000-8000-000000000011",
  nonce: "99570000-0000-4000-8000-000000000031",
  action: "sms.ingest",
  requestHash: "a".repeat(64),
  tokenHash: "b".repeat(64),
};
const future = () => new Date(Date.now() + 120_000).toISOString();
const receipt = () => ({
  contract_version: 1,
  reservation_id: "99570000-0000-4000-8000-000000000041",
  actor_id: binding.actorId,
  session_id: binding.sessionId,
  nonce: binding.nonce,
  action: binding.action,
  request_hash: binding.requestHash,
  token_sha256: binding.tokenHash,
  state: "reserved",
  can_call: true,
  expires_at: future(),
  result: null,
});
const result = () => ({
  status: "pass",
  action: binding.action,
  request_hash: binding.requestHash,
  package_name: "app.cool.mobile",
  app_verdict: "PLAY_RECOGNIZED",
  device_verdicts: ["MEETS_DEVICE_INTEGRITY"],
  native_capability: "99570000-0000-4000-8000-000000000051",
  capability_expires_at: future(),
});
function denied(body: () => unknown, code: string, status: number) {
  try {
    body();
  } catch (e) {
    assertEquals(e instanceof PublicError, true);
    assertEquals((e as PublicError).code, code);
    assertEquals((e as PublicError).status, status);
    return;
  }
  throw new Error("Expected denial");
}
Deno.test("admission accepts only an exact server reservation and phase receipt", () => {
  const r = receipt();
  assertEquals(
    integrityAdmissionReceipt(r, binding, "reserved").reservationId,
    r.reservation_id,
  );
  for (const state of ["oauth_started", "decode_started"]) {
    assertEquals(
      integrityAdmissionReceipt({ ...r, state }, binding, state).reservationId,
      r.reservation_id,
    );
  }
});
Deno.test("admission rejects missing, expanded, malformed and expired receipts", () => {
  for (
    const value of [
      null,
      [],
      {},
      { ...receipt(), extra: true },
      { ...receipt(), expires_at: "2050-02-30T10:00:00Z" },
      { ...receipt(), expires_at: "2050-01-01" },
      { ...receipt(), expires_at: new Date(Date.now() - 1).toISOString() },
      { ...receipt(), result: {} },
      { ...receipt(), can_call: false },
      { ...receipt(), contract_version: 2 },
    ]
  ) {
    denied(
      () => integrityAdmissionReceipt(value, binding, "reserved"),
      "integrity_admission_invalid",
      503,
    );
  }
});
Deno.test("admission rejects actor, exact session, purpose, nonce, content and token substitution", () => {
  for (
    const field of [
      "actor_id",
      "session_id",
      "nonce",
      "action",
      "request_hash",
      "token_sha256",
      "reservation_id",
      "state",
    ]
  ) {
    denied(
      () =>
        integrityAdmissionReceipt(
          { ...receipt(), [field]: "substitution" },
          binding,
          "reserved",
        ),
      "integrity_admission_invalid",
      503,
    );
  }
});
Deno.test("completed reconciliation is bound and cannot grant transport permission", () => {
  const value = result();
  assertEquals(integrityResult(value, binding), value);
  assertEquals(
    integrityAdmissionReceipt(
      { ...receipt(), state: "completed", can_call: false, result: value },
      binding,
      "completed",
    ).result,
    value,
  );
  denied(
    () =>
      integrityAdmissionReceipt(
        { ...receipt(), state: "completed", can_call: true, result: value },
        binding,
        "completed",
      ),
    "integrity_admission_invalid",
    503,
  );
});
Deno.test("reconciled capability retains package, verdict, binding and validity requirements", () => {
  for (
    const value of [
      null,
      {},
      { ...result(), extra: true },
      { ...result(), action: "group.create" },
      { ...result(), request_hash: "c".repeat(64) },
      { ...result(), native_capability: "bad" },
      { ...result(), capability_expires_at: "invalid" },
      {
        ...result(),
        capability_expires_at: new Date(Date.now() - 1).toISOString(),
      },
      { ...result(), package_name: "other" },
      { ...result(), app_verdict: "UNEVALUATED" },
      { ...result(), device_verdicts: ["MEETS_BASIC_INTEGRITY"] },
      {
        ...result(),
        device_verdicts: Array(11).fill("MEETS_DEVICE_INTEGRITY"),
      },
    ]
  ) {
    denied(
      () => integrityResult(value, binding),
      "integrity_result_unavailable",
      409,
    );
  }
});
Deno.test("SQL errors expose stable public codes without private SQL or provider text", () => {
  for (
    const [code, expected, status] of [
      ["42501", "integrity_admission_forbidden", 403],
      ["22023", "invalid_integrity_request", 400],
      ["53300", "integrity_resource_limit", 429],
      ["55000", "integrity_reconciliation_required", 409],
      ["23505", "integrity_reconciliation_required", 409],
      ["PGRST202", "integrity_admission_unavailable", 503],
    ] as const
  ) {
    const error = integrityAdmissionError({
      code,
      message: "private SQL token",
    });
    assertEquals(error.code, expected);
    assertEquals(error.status, status);
  }
});
