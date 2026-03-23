function readTrimmedString(
  value: unknown,
  maxLength: number,
): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  return trimmed.slice(0, maxLength);
}

export function normalizeBiopayLivenessMetadata(
  input: unknown,
): Record<string, unknown> | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return null;
  }

  const source = input as Record<string, unknown>;
  const metadata: Record<string, unknown> = {};
  const version = readTrimmedString(source["version"], 64);
  const mode = readTrimmedString(source["mode"], 32);
  const result = readTrimmedString(source["result"], 32);
  const completedAt = readTrimmedString(source["completed_at"], 64);

  if (version) {
    metadata.version = version;
  }
  if (mode) {
    metadata.mode = mode;
  }
  if (result) {
    metadata.result = result;
  }
  if (completedAt) {
    metadata.completed_at = completedAt;
  }

  const steps = source["completed_steps"];
  if (Array.isArray(steps)) {
    const completedSteps = steps
      .filter((entry): entry is string => typeof entry === "string")
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0)
      .slice(0, 6);
    if (completedSteps.length > 0) {
      metadata.completed_steps = completedSteps;
    }
  }

  const framesEvaluated = source["frames_evaluated"];
  if (typeof framesEvaluated === "number" && Number.isFinite(framesEvaluated)) {
    metadata.frames_evaluated = Math.max(0, Math.trunc(framesEvaluated));
  }

  const maxAbsHeadYaw = source["max_abs_head_yaw"];
  if (typeof maxAbsHeadYaw === "number" && Number.isFinite(maxAbsHeadYaw)) {
    metadata.max_abs_head_yaw = Number(maxAbsHeadYaw.toFixed(2));
  }

  const blinkDetected = source["blink_detected"];
  if (typeof blinkDetected === "boolean") {
    metadata.blink_detected = blinkDetected;
  }

  return Object.keys(metadata).length === 0 ? null : metadata;
}
