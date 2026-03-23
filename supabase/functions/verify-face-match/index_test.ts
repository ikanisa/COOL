import { mergeFaceMatchIdentityData } from "./index.ts";

function assertEquals(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

Deno.test("mergeFaceMatchIdentityData preserves OCR fields while applying face-match results", () => {
  const merged = mergeFaceMatchIdentityData(
    {
      provider: "gemini",
      document_type: "national_id",
      expiry_date: "2030-01-01",
      confidence: 0.94,
    },
    {
      confidence: 0.88,
      is_match: true,
      presentation_attack_detected: false,
    },
    "2026-03-23T12:00:00.000Z",
  );

  assertEquals(merged.provider, "gemini", "provider should be preserved");
  assertEquals(
    merged.document_type,
    "national_id",
    "document type should be preserved",
  );
  assertEquals(
    merged.face_match_status,
    "matched",
    "face match status should be set",
  );
  assertEquals(
    merged.liveness_detected,
    true,
    "liveness flag should be derived from presentation-attack detection",
  );
  assertEquals(
    merged.biometric_verified_at,
    "2026-03-23T12:00:00.000Z",
    "verification timestamp should be set",
  );
});
