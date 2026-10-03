import {
  boundedBody,
  boundedJson,
  objectValue,
  PublicError,
  publicFailure,
  SHA256,
  uuid,
  zonedInstant,
} from "../_shared/production_contract.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  MAX_ROSTER_REQUEST_BYTES,
  readRosterSource,
  ROSTER_AI_CONSENT,
  ROSTER_PROMPT_VERSION,
  rosterCandidateJsonbBytes,
  rosterSession,
  rosterSha256,
  type RosterSource,
} from "../_shared/roster_provenance.ts";
import {
  parseRosterText,
  type RosterCandidate,
} from "../_shared/roster_import.ts";
import { buildRosterResponsesRequest } from "../_shared/openai_roster.ts";
import {
  MAX_ROSTER_PROVIDER_BYTES,
  rosterResponseCandidates,
} from "../_shared/roster_response_policy.ts";
import { decodeRosterSource } from "../_shared/roster_decoder.ts";
import { rosterBudgetReceipt } from "../_shared/roster_resource_budget.ts";

type Result = {
  data: unknown;
  error: { message?: string; code?: string } | null;
};
export type RosterHandlerDependencies = {
  authenticate(authorization: string | null): Promise<{ id: string }>;
  rpc(name: string, args: Record<string, unknown>): Promise<Result>;
  configuration(): {
    model: string;
    apiKey: string | undefined;
    decoderUrl?: string;
    decoderSecret?: string;
    decoderBuildSha256?: string;
  };
  fetch?: typeof fetch;
  decoderFetch?: typeof fetch;
};
const encoder = new TextEncoder();
const failureCodes = new Set([
  "roster_extraction_failed",
  "roster_extraction_timeout",
  "roster_extraction_refused",
  "roster_extraction_incomplete",
  "roster_provider_response_invalid",
  "roster_provider_response_too_large",
  "roster_preview_invalid",
  "roster_extraction_unavailable",
]);
function receiptError(): never {
  throw new PublicError("roster_receipt_invalid", 503);
}
function identifier(value: unknown): string {
  try {
    return uuid(value, "roster_receipt_invalid");
  } catch {
    return receiptError();
  }
}
function record(value: unknown): Record<string, unknown> {
  try {
    return objectValue(value);
  } catch {
    return receiptError();
  }
}
function exact(value: Record<string, unknown>, fields: string[]): void {
  if (
    Object.keys(value).length !== fields.length ||
    fields.some((key) => !(key in value))
  ) receiptError();
}
function digest(value: unknown): string {
  if (typeof value !== "string" || !SHA256.test(value)) receiptError();
  return value;
}
function expiry(value: unknown): void {
  let parsed: string | null;
  try {
    parsed = zonedInstant(value);
  } catch {
    receiptError();
  }
  if (parsed === null) receiptError();
  if (Date.parse(parsed) <= Date.now()) {
    throw new PublicError("roster_import_expired", 409);
  }
}
function providerIdentifier(value: unknown, max: number): string {
  if (
    typeof value !== "string" ||
    !new RegExp(`^[A-Za-z0-9][A-Za-z0-9._:/-]{0,${max - 1}}$`).test(value)
  ) throw new PublicError("roster_provider_response_invalid", 502);
  return value;
}
function previewReceipt(
  value: unknown,
  source: RosterSource,
  hash: string,
  importId: string,
  derivedHash: string | null,
  extractionId: unknown,
  expectedModel: string | null,
): Record<string, unknown> {
  const r = record(value);
  exact(r, [
    "contract_version",
    "ok",
    "import_id",
    "source_sha256",
    "source_kind",
    "source_receipt",
    "revision_id",
    "parent_revision_id",
    "revision_number",
    "reviewed_rows_sha256",
    "can_submit",
    "requires_human_review",
    "processing_method",
    "model",
    "rows",
    "row_count",
    "ready_count",
    "error_count",
    "normalized_rows",
    "expires_at",
  ]);
  if (
    r.contract_version !== 1 || r.ok !== true || r.import_id !== importId ||
    r.source_sha256 !== hash || r.source_kind !== source.kind ||
    r.parent_revision_id !== null || r.revision_number !== 1 ||
    r.can_submit !== false || r.requires_human_review !== true ||
    r.processing_method !==
      (source.ai ? "openai_structured_extraction" : "deterministic")
  ) receiptError();
  const provenance = record(r.source_receipt);
  exact(provenance, [
    "request_id",
    "source_size",
    "client_filename",
    "declared_mime",
    "detected_type",
    "derived_sha256",
    "derived_assurance",
    "extraction_id",
    "ai_consent",
    "consent_version",
    "parser_version",
    "schema_version",
  ]);
  if (
    provenance.request_id !== source.requestId ||
    provenance.source_size !== source.bytes.length ||
    provenance.client_filename !== source.filename ||
    provenance.declared_mime !== source.mime ||
    provenance.detected_type !== source.detected ||
    provenance.derived_sha256 !== derivedHash ||
    provenance.derived_assurance !==
      (source.kind === "xlsx" ? "client_derived_tsv" : null) ||
    provenance.extraction_id !== extractionId ||
    provenance.ai_consent !== source.ai ||
    provenance.consent_version !== (source.ai ? ROSTER_AI_CONSENT : null) ||
    provenance.parser_version !== "collect-roster-parser-v1" ||
    provenance.schema_version !== "collect-roster-rows-v1" ||
    r.model !== expectedModel
  ) receiptError();
  identifier(r.revision_id);
  digest(r.reviewed_rows_sha256);
  expiry(r.expires_at);
  if (source.ai) {
    try {
      providerIdentifier(r.model, 128);
    } catch {
      receiptError();
    }
  } else if (r.model !== null) receiptError();
  if (
    !Array.isArray(r.rows) || r.rows.length < 1 || r.rows.length > 500 ||
    !Array.isArray(r.normalized_rows)
  ) receiptError();
  let ready = 0;
  for (const value of r.rows) {
    const row = record(value);
    exact(row, [
      "source_row",
      "member_name",
      "momo_name",
      "momo_number",
      "confidence",
      "issues",
      "ready",
    ]);
    if (
      !Number.isSafeInteger(row.source_row) || Number(row.source_row) < 1 ||
      Number(row.source_row) > 2147483647 ||
      typeof row.confidence !== "number" || !Number.isFinite(row.confidence) ||
      row.confidence < 0 || row.confidence > 1 ||
      typeof row.ready !== "boolean" || !Array.isArray(row.issues) ||
      row.issues.length > 12 || row.issues.some((i) =>
        typeof i !== "string" || i.length > 256
      )
    ) receiptError();
    for (const key of ["member_name", "momo_name", "momo_number"]) {
      if (
        typeof row[key] !== "string" ||
        [...(row[key] as string)].length > (key === "momo_number" ? 32 : 480)
      ) receiptError();
    }
    if (row.ready) {
      ready++;
      if (row.issues.length) receiptError();
    }
  }
  if (
    r.row_count !== r.rows.length || r.ready_count !== ready ||
    r.error_count !== r.rows.length - ready ||
    r.normalized_rows.length !== ready
  ) receiptError();
  const readyRows = r.rows.filter((row) => row.ready);
  for (const [index, value] of r.normalized_rows.entries()) {
    const row = record(value);
    exact(row, ["member_name", "momo_name", "momo_number"]);
    for (const key of Object.keys(row)) {
      if (typeof row[key] !== "string" || row[key] !== readyRows[index][key]) {
        receiptError();
      }
    }
  }
  return r;
}
async function rpc(
  deps: RosterHandlerDependencies,
  name: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  let result: Result;
  try {
    result = await deps.rpc(name, args);
  } catch {
    throw new PublicError("roster_receipt_unavailable", 503);
  }
  if (result.error) {
    const code = result.error.message;
    if (code === "roster_import_limit") throw new PublicError(code, 429);
    if (code === "roster_resource_limit") throw new PublicError(code, 429);
    if (code === "roster_resource_in_progress") {
      throw new PublicError(code, 409);
    }
    // A received SQL invalid-input result proves that completion rolled back.
    if (
      name === "complete_roster_import_preview" && result.error.code === "22023"
    ) {
      throw new PublicError("roster_preview_invalid");
    }
    if (code === "roster_import_in_progress") throw new PublicError(code, 409);
    if (
      code === "roster_request_conflict" || code === "roster_import_expired"
    ) throw new PublicError(code, 409);
    if (result.error.code === "42501") {
      throw new PublicError("roster_import_forbidden", 403);
    }
    throw new PublicError("roster_receipt_unavailable", 503);
  }
  return result.data;
}
export function createRosterImportHandler(
  deps: RosterHandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405);
    }
    let sourceId: string | null = null,
      actorId: string | null = null,
      sessionId: string | null = null,
      completionAttempted = false,
      reservationId: string | null = null,
      budgetOutcome: "preview_ready" | "failed" | "ambiguous" = "failed";
    try {
      const authorization = request.headers.get("authorization");
      // Authenticating first is essential: decoded JWT fields are not proof.
      const user = await deps.authenticate(authorization);
      ({ actorId, sessionId } = rosterSession(authorization, user.id));
      const source = readRosterSource(
        await boundedJson(request, MAX_ROSTER_REQUEST_BYTES),
      );
      const hash = await rosterSha256(source.bytes);
      const derivedHash = source.derived
        ? await rosterSha256(source.derived)
        : null;
      const config = deps.configuration();
      let model: string | null = null;
      if (source.ai) {
        try {
          model = providerIdentifier(config.model, 128);
        } catch {
          throw new PublicError("roster_extraction_unavailable", 503);
        }
      }
      const budget = rosterBudgetReceipt(
        await rpc(deps, "reserve_roster_resources", {
          p_actor_id: actorId,
          p_session_id: sessionId,
          p_request_id: source.requestId,
          p_source_sha256: hash,
          p_source_kind: source.kind,
          p_source_bytes: source.bytes.length,
          p_derived_sha256: derivedHash,
        }),
        { requestId: source.requestId, actorId, sessionId, sourceHash: hash },
      );
      // A replay may return an existing immutable result, but never dispatch a
      // second decoder/provider attempt. Crashed leases cannot be reacquired.
      if (budget.state === "reserved") {
        reservationId = budget.reservation_id;
        if (["xlsx", "image", "pdf"].includes(source.kind)) {
          const decoded = await decodeRosterSource(
            source,
            hash,
            reservationId,
            {
              url: config.decoderUrl,
              secret: config.decoderSecret,
              buildSha256: config.decoderBuildSha256,
            },
            deps.decoderFetch,
          );
          const verified = record(
            await rpc(deps, "verify_roster_source_integrity", {
              p_reservation_id: reservationId,
              p_actor_id: actorId,
              p_session_id: sessionId,
              p_decoder_receipt_sha256: decoded.receipt_sha256,
              p_decoder_build_sha256: decoded.decoder_build_sha256,
              p_policy_version: decoded.policy_version,
              p_toolchain: decoded.toolchain,
              p_summary: {
                frames: decoded.frames,
                pages: decoded.pages,
                pixels: decoded.pixels,
                expanded_bytes: decoded.expanded_bytes,
              },
            }),
          );
          exact(verified, [
            "contract_version",
            "ok",
            "reservation_id",
            "source_sha256",
            "derived_sha256",
            "decoder_receipt_sha256",
            "verified",
          ]);
          if (
            verified.contract_version !== 1 || verified.ok !== true ||
            verified.reservation_id !== reservationId ||
            verified.source_sha256 !== hash ||
            verified.derived_sha256 !== derivedHash ||
            verified.decoder_receipt_sha256 !== decoded.receipt_sha256 ||
            verified.verified !== true
          ) receiptError();
        }
      }
      const registered = record(
        await rpc(deps, "create_roster_import_source", {
          p_actor_id: actorId,
          p_session_id: sessionId,
          p_request_id: source.requestId,
          p_source_kind: source.kind,
          p_original_sha256: hash,
          p_original_size: source.bytes.length,
          p_client_filename: source.filename,
          p_declared_mime: source.mime,
          p_detected_type: source.detected,
          p_derived_sha256: derivedHash,
          p_derived_size: source.derived?.length ?? null,
          p_ai_consent: source.ai,
          p_consent_version: source.ai ? ROSTER_AI_CONSENT : null,
          p_ai_metadata: source.ai
            ? {
              provider: "openai",
              model,
              prompt_version: ROSTER_PROMPT_VERSION,
            }
            : null,
        }),
      );
      exact(registered, [
        "contract_version",
        "ok",
        "request_id",
        "import_id",
        "source_sha256",
        "source_size",
        "source_kind",
        "extraction_id",
        "expires_at",
        "derived_sha256",
        "derived_assurance",
        "state",
        "replayed",
        "completed_preview",
        "error_code",
      ]);
      if (
        registered.contract_version !== 1 || registered.ok !== true ||
        registered.request_id !== source.requestId ||
        registered.source_sha256 !== hash ||
        registered.source_size !== source.bytes.length ||
        registered.source_kind !== source.kind ||
        registered.derived_sha256 !== derivedHash ||
        registered.derived_assurance !==
          (source.kind === "xlsx" ? "client_derived_tsv" : null) ||
        typeof registered.replayed !== "boolean"
      ) receiptError();
      const importId = identifier(registered.import_id);
      expiry(registered.expires_at);
      if (source.ai) identifier(registered.extraction_id);
      else if (registered.extraction_id !== null) receiptError();
      if (
        registered.state === "preview_ready" && registered.replayed === true &&
        registered.error_code === null
      ) {
        return jsonResponse(
          previewReceipt(
            registered.completed_preview,
            source,
            hash,
            importId,
            derivedHash,
            registered.extraction_id,
            model,
          ),
        );
      }
      if (
        registered.state === "failed" && registered.replayed === true &&
        registered.completed_preview === null &&
        failureCodes.has(String(registered.error_code))
      ) throw new PublicError(String(registered.error_code), 502);
      if (
        registered.state !== "awaiting_preview" ||
        registered.replayed !== false ||
        registered.completed_preview !== null || registered.error_code !== null
      ) receiptError();
      if (budget.state !== "reserved") receiptError();
      sourceId = importId;
      let candidates: RosterCandidate[],
        responseId: string | null = null,
        responseHash: string | null = null;
      if (source.ai) {
        if (!config.apiKey) {
          throw new PublicError("roster_extraction_unavailable", 503);
        }
        let response: Response;
        // Once a provider request can leave this process, an error does not
        // prove it was unbilled/stopped. Keep its active lease and full charge.
        budgetOutcome = "ambiguous";
        try {
          response = await (deps.fetch ?? fetch)(
            "https://api.openai.com/v1/responses",
            {
              method: "POST",
              headers: {
                authorization: `Bearer ${config.apiKey}`,
                "content-type": "application/json",
              },
              body: JSON.stringify(
                buildRosterResponsesRequest(
                  model!,
                  source.kind as "pdf" | "image",
                  source.filename!,
                  source.mime,
                  source.base64!,
                ),
              ),
              signal: AbortSignal.timeout(60_000),
              redirect: "error",
            },
          );
        } catch (error) {
          throw new PublicError(
            error instanceof DOMException &&
              ["TimeoutError", "AbortError"].includes(error.name)
              ? "roster_extraction_timeout"
              : "roster_extraction_failed",
            502,
          );
        }
        if (!response.ok) {
          try {
            await response.body?.cancel();
          } catch { /* No provider body is exposed. */ }
          throw new PublicError("roster_extraction_failed", 502);
        }
        let raw: string, data: unknown;
        try {
          raw = await boundedBody(response, MAX_ROSTER_PROVIDER_BYTES);
          data = JSON.parse(raw);
        } catch (error) {
          throw new PublicError(
            error instanceof PublicError && error.code === "payload_too_large"
              ? "roster_provider_response_too_large"
              : error instanceof DOMException &&
                  ["TimeoutError", "AbortError"].includes(error.name)
              ? "roster_extraction_timeout"
              : "roster_provider_response_invalid",
            502,
          );
        }
        candidates = rosterResponseCandidates(data);
        responseId = providerIdentifier(
          (data as Record<string, unknown>).id,
          256,
        );
        responseHash = await rosterSha256(encoder.encode(raw));
      } else {
        try {
          candidates = parseRosterText(source.content!);
          if (
            candidates.length > 500 ||
            candidates.some((row) =>
              row.source_row > 2147483647 ||
              [...row.member_name].length > 480 ||
              [...row.momo_name].length > 480 ||
              [...row.momo_number].length > 32 ||
              [row.member_name, row.momo_name, row.momo_number].some((value) =>
                value.includes("\u0000")
              )
            )
          ) throw new Error("Candidate limits exceeded");
        } catch {
          throw new PublicError("roster_preview_invalid");
        }
      }
      if (candidates.some((row) => row.source_row > 2147483647)) {
        throw new PublicError("roster_provider_response_invalid", 502);
      }
      if (rosterCandidateJsonbBytes(candidates) > 512_000) {
        throw new PublicError(
          source.ai
            ? "roster_provider_response_too_large"
            : "roster_preview_invalid",
          source.ai ? 502 : 400,
        );
      }
      completionAttempted = true;
      let completed: unknown;
      try {
        completed = await rpc(deps, "complete_roster_import_preview", {
          p_import_id: sourceId,
          p_actor_id: actorId,
          p_session_id: sessionId,
          p_candidates: candidates,
          p_processing_metadata: {
            processing_method: source.ai
              ? "openai_structured_extraction"
              : "deterministic",
            provider_response_sha256: responseHash,
            provider_response_id: responseId,
          },
        });
      } catch (error) {
        if (
          error instanceof PublicError &&
          error.code === "roster_preview_invalid"
        ) completionAttempted = false;
        throw error;
      }
      const validated = previewReceipt(
        completed,
        source,
        hash,
        sourceId,
        derivedHash,
        registered.extraction_id,
        model,
      );
      budgetOutcome = "preview_ready";
      return jsonResponse(validated);
    } catch (error) {
      if (sourceId && actorId && sessionId && !completionAttempted) {
        const code =
          error instanceof PublicError && failureCodes.has(error.code)
            ? error.code
            : "roster_extraction_failed";
        try {
          const failed = record(
            await rpc(deps, "fail_roster_import_preview", {
              p_import_id: sourceId,
              p_actor_id: actorId,
              p_session_id: sessionId,
              p_error_code: code,
            }),
          );
          exact(failed, [
            "contract_version",
            "ok",
            "import_id",
            "state",
            "error_code",
            "replayed",
          ]);
          if (
            failed.contract_version !== 1 || failed.ok !== true ||
            failed.import_id !== sourceId || failed.state !== "failed" ||
            failed.error_code !== code || typeof failed.replayed !== "boolean"
          ) receiptError();
        } catch {
          return jsonResponse({ error: "roster_receipt_unavailable" }, 503);
        }
      }
      const failure = publicFailure(error);
      return jsonResponse({ error: failure.error }, failure.status);
    } finally {
      if (reservationId && actorId && sessionId) {
        // Durable receipt outcomes remain authoritative even if this cleanup
        // ACK is lost. reserve_roster_resources repairs from immutable results.
        try {
          const finished = record(
            await rpc(deps, "finish_roster_resources", {
              p_reservation_id: reservationId,
              p_actor_id: actorId,
              p_session_id: sessionId,
              p_outcome: budgetOutcome,
            }),
          );
          exact(finished, [
            "contract_version",
            "ok",
            "reservation_id",
            "outcome",
            "charged",
          ]);
          if (
            finished.contract_version !== 1 || finished.ok !== true ||
            finished.reservation_id !== reservationId ||
            finished.outcome !== budgetOutcome || finished.charged !== true
          ) receiptError();
        } catch { /* Never retry decoder/provider or refund uncertain work. */ }
      }
    }
  };
}
