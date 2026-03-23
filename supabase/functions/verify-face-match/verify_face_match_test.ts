import { mergeFaceMatchIdentityData } from "./index.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

Deno.test("mergeFaceMatchIdentityData preserves existing OCR fields", () => {
  const existingIdentity: Record<string, unknown> = {
    provider: "gemini",
    extracted_at: "2026-03-20T10:00:00.000Z",
    confidence: 0.95,
    gender: "M",
    nationality: "Rwandan",
    document_type: "national_id",
    issuing_country: "RW",
    expiry_date: "2030-01-01",
    requested_document_type: "national_id",
    has_back_image: true,
  };

  const matchResult = {
    confidence: 0.92,
    is_match: true,
    presentation_attack_detected: false,
  };

  const merged = mergeFaceMatchIdentityData(
    existingIdentity,
    matchResult,
    "2026-03-23T15:00:00.000Z",
  );

  // Face-match fields should be written
  assertEquals(
    merged.face_match_confidence,
    0.92,
    "face_match_confidence should be set",
  );
  assertEquals(
    merged.face_match_status,
    "matched",
    "face_match_status should be matched",
  );
  assertEquals(
    merged.liveness_detected,
    true,
    "liveness_detected should be true when no attack detected",
  );
  assertEquals(
    merged.biometric_verified_at,
    "2026-03-23T15:00:00.000Z",
    "biometric_verified_at should be set",
  );

  // OCR fields from prior extraction must survive the merge
  assertEquals(
    merged.provider as string,
    "gemini",
    "OCR provider should be preserved",
  );
  assertEquals(
    merged.extracted_at as string,
    "2026-03-20T10:00:00.000Z",
    "extracted_at should be preserved",
  );
  assertEquals(
    merged.confidence as number,
    0.95,
    "OCR confidence should be preserved (not overwritten by face-match confidence)",
  );
  assertEquals(merged.gender as string, "M", "gender should be preserved");
  assertEquals(
    merged.nationality as string,
    "Rwandan",
    "nationality should be preserved",
  );
  assertEquals(
    merged.document_type as string,
    "national_id",
    "document_type should be preserved",
  );
  assertEquals(
    merged.issuing_country as string,
    "RW",
    "issuing_country should be preserved",
  );
  assertEquals(
    merged.expiry_date as string,
    "2030-01-01",
    "expiry_date should be preserved",
  );
});

Deno.test("mergeFaceMatchIdentityData handles empty existing identity", () => {
  const merged = mergeFaceMatchIdentityData(
    {},
    { confidence: 0.5, is_match: false, presentation_attack_detected: true },
    "2026-03-23T16:00:00.000Z",
  );

  assertEquals(merged.face_match_status, "mismatch", "should set mismatch");
  assertEquals(merged.liveness_detected, false, "should detect attack");
  assertEquals(
    merged.biometric_verified_at,
    "2026-03-23T16:00:00.000Z",
    "should set timestamp",
  );
});

Deno.test("mergeFaceMatchIdentityData does not leak face-match confidence into OCR confidence", () => {
  const existing = { confidence: 0.88 };
  const merged = mergeFaceMatchIdentityData(
    existing,
    { confidence: 0.77, is_match: false, presentation_attack_detected: false },
    "2026-03-23T17:00:00.000Z",
  );

  // The spread puts existing first, so face_match_confidence is a separate key
  assertEquals(
    merged.confidence as number,
    0.88,
    "original confidence key should not be overwritten",
  );
  assertEquals(
    merged.face_match_confidence,
    0.77,
    "face-match confidence should be in its own key",
  );
});
