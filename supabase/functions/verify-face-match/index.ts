export type FaceMatchResult = {
  confidence: number;
  is_match: boolean;
  presentation_attack_detected: boolean;
};

export function mergeFaceMatchIdentityData(
  existingIdentity: Record<string, unknown>,
  matchResult: FaceMatchResult,
  verifiedAt: string,
): Record<string, unknown> {
  return {
    ...existingIdentity,
    face_match_confidence: matchResult.confidence,
    face_match_status: matchResult.is_match ? "matched" : "mismatch",
    liveness_detected: !matchResult.presentation_attack_detected,
    biometric_verified_at: verifiedAt,
  };
}
