import { boundedBody, boundedJson, objectValue, PublicError, publicFailure, SHA256, uuid, zonedInstant } from "../_shared/production_contract.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { MAX_ROSTER_REQUEST_BYTES, readRosterSource, ROSTER_AI_CONSENT, ROSTER_PROMPT_VERSION, rosterCandidateJsonbBytes, rosterSession, rosterSha256 } from "../_shared/roster_provenance.ts";
import { parseRosterText } from "../_shared/roster_import.ts";
import { buildRosterResponsesRequest } from "../_shared/openai_roster.ts";
import { MAX_ROSTER_PROVIDER_BYTES, rosterResponseCandidates } from "../_shared/roster_response_policy.ts";
import { decodeRosterSource } from "../_shared/roster_decoder.ts";
import { rosterBudgetReceipt } from "../_shared/roster_resource_budget.ts";
import { assertRosterAiDispatchApproval, prepareRosterAiDispatchApproval, ROSTER_OPENAI_RESPONSES_ENDPOINT, snapshotRosterAiConfiguration } from "../_shared/roster_ai_dispatch_policy.ts";
const encoder = new TextEncoder();
const failureCodes = new Set([
  "roster_extraction_failed",
  "roster_extraction_timeout",
  "roster_extraction_refused",
  "roster_extraction_incomplete",
  "roster_provider_response_invalid",
  "roster_provider_response_too_large",
  "roster_preview_invalid",
  "roster_extraction_unavailable"
]);
function receiptError() {
  throw new PublicError("roster_receipt_invalid", 503);
}
function identifier(value) {
  try {
    return uuid(value, "roster_receipt_invalid");
  } catch  {
    return receiptError();
  }
}
function record(value) {
  try {
    return objectValue(value);
  } catch  {
    return receiptError();
  }
}
function exact(value, fields) {
  if (Object.keys(value).length !== fields.length || fields.some((key)=>!(key in value))) receiptError();
}
function digest(value) {
  if (typeof value !== "string" || !SHA256.test(value)) receiptError();
  return value;
}
function expiry(value) {
  let parsed;
  try {
    parsed = zonedInstant(value);
  } catch  {
    receiptError();
  }
  if (parsed === null) receiptError();
  if (Date.parse(parsed) <= Date.now()) {
    throw new PublicError("roster_import_expired", 409);
  }
}
function providerIdentifier(value, max) {
  if (typeof value !== "string" || !new RegExp(`^[A-Za-z0-9][A-Za-z0-9._:/-]{0,${max - 1}}$`).test(value)) throw new PublicError("roster_provider_response_invalid", 502);
  return value;
}
function previewReceipt(value, source, hash, importId, derivedHash, extractionId, expectedModel) {
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
    "expires_at"
  ]);
  if (r.contract_version !== 1 || r.ok !== true || r.import_id !== importId || r.source_sha256 !== hash || r.source_kind !== source.kind || r.parent_revision_id !== null || r.revision_number !== 1 || r.can_submit !== false || r.requires_human_review !== true || r.processing_method !== (source.ai ? "openai_structured_extraction" : "deterministic")) receiptError();
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
    "schema_version"
  ]);
  if (provenance.request_id !== source.requestId || provenance.source_size !== source.bytes.length || provenance.client_filename !== source.filename || provenance.declared_mime !== source.mime || provenance.detected_type !== source.detected || provenance.derived_sha256 !== derivedHash || provenance.derived_assurance !== (source.kind === "xlsx" ? "client_derived_tsv" : null) || provenance.extraction_id !== extractionId || provenance.ai_consent !== source.ai || provenance.consent_version !== (source.ai ? ROSTER_AI_CONSENT : null) || provenance.parser_version !== "collect-roster-parser-v1" || provenance.schema_version !== "collect-roster-rows-v1" || r.model !== expectedModel) receiptError();
  identifier(r.revision_id);
  digest(r.reviewed_rows_sha256);
  expiry(r.expires_at);
  if (source.ai) {
    try {
      providerIdentifier(r.model, 128);
    } catch  {
      receiptError();
    }
  } else if (r.model !== null) receiptError();
  if (!Array.isArray(r.rows) || r.rows.length < 1 || r.rows.length > 500 || !Array.isArray(r.normalized_rows)) receiptError();
  let ready = 0;
  for (const value of r.rows){
    const row = record(value);
    exact(row, [
      "source_row",
      "member_name",
      "momo_name",
      "momo_number",
      "confidence",
      "issues",
      "ready"
    ]);
    if (!Number.isSafeInteger(row.source_row) || Number(row.source_row) < 1 || Number(row.source_row) > 2147483647 || typeof row.confidence !== "number" || !Number.isFinite(row.confidence) || row.confidence < 0 || row.confidence > 1 || typeof row.ready !== "boolean" || !Array.isArray(row.issues) || row.issues.length > 12 || row.issues.some((i)=>typeof i !== "string" || i.length > 256)) receiptError();
    for (const key of [
      "member_name",
      "momo_name",
      "momo_number"
    ]){
      if (typeof row[key] !== "string" || [
        ...row[key]
      ].length > (key === "momo_number" ? 32 : 480)) receiptError();
    }
    if (row.ready) {
      ready++;
      if (row.issues.length) receiptError();
    }
  }
  if (r.row_count !== r.rows.length || r.ready_count !== ready || r.error_count !== r.rows.length - ready || r.normalized_rows.length !== ready) receiptError();
  const readyRows = r.rows.filter((row)=>row.ready);
  for (const [index, value] of r.normalized_rows.entries()){
    const row = record(value);
    exact(row, [
      "member_name",
      "momo_name",
      "momo_number"
    ]);
    for (const key of Object.keys(row)){
      if (typeof row[key] !== "string" || row[key] !== readyRows[index][key]) {
        receiptError();
      }
    }
  }
  return r;
}
async function rpc(deps, name, args) {
  let result;
  try {
    result = await deps.rpc(name, args);
  } catch  {
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
    if (name === "complete_roster_import_preview" && result.error.code === "22023") {
      throw new PublicError("roster_preview_invalid");
    }
    if (code === "roster_import_in_progress") throw new PublicError(code, 409);
    if (code === "roster_request_conflict" || code === "roster_import_expired") throw new PublicError(code, 409);
    if (result.error.code === "42501") {
      throw new PublicError("roster_import_forbidden", 403);
    }
    throw new PublicError("roster_receipt_unavailable", 503);
  }
  return result.data;
}
export function createRosterImportHandler(deps) {
  return async (request)=>{
    if (request.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders
      });
    }
    if (request.method !== "POST") {
      return jsonResponse({
        error: "method_not_allowed"
      }, 405);
    }
    let sourceId = null, actorId = null, sessionId = null, completionAttempted = false, reservationId = null, budgetOutcome = "failed";
    try {
      const authorization = request.headers.get("authorization");
      // Authenticating first is essential: decoded JWT fields are not proof.
      const user = await deps.authenticate(authorization);
      ({ actorId, sessionId } = rosterSession(authorization, user.id));
      const source = readRosterSource(await boundedJson(request, MAX_ROSTER_REQUEST_BYTES));
      const hash = await rosterSha256(source.bytes);
      const derivedHash = source.derived ? await rosterSha256(source.derived) : null;
      const config = snapshotRosterAiConfiguration(deps.configuration());
      let approval = null;
      let model = null;
      if (source.ai) {
        try {
          model = providerIdentifier(config.model, 128);
        } catch  {
          throw new PublicError("roster_extraction_unavailable", 503);
        }
        approval = await prepareRosterAiDispatchApproval(config);
        // Hash validation has settled. Fresh configuration and time are checked
        // synchronously before any reservation or external work can start.
        assertRosterAiDispatchApproval(config, approval, deps.configuration());
      }
      const budget = rosterBudgetReceipt(await rpc(deps, "reserve_roster_resources", {
        p_actor_id: actorId,
        p_session_id: sessionId,
        p_request_id: source.requestId,
        p_source_sha256: hash,
        p_source_kind: source.kind,
        p_source_bytes: source.bytes.length,
        p_derived_sha256: derivedHash
      }), {
        requestId: source.requestId,
        actorId,
        sessionId,
        sourceHash: hash
      });
      // A replay may return an existing immutable result, but never dispatch a
      // second decoder/provider attempt. Crashed leases cannot be reacquired.
      if (budget.state === "reserved") {
        reservationId = budget.reservation_id;
        if ([
          "xlsx",
          "image",
          "pdf"
        ].includes(source.kind)) {
          let approvalDenied = false;
          const decoderFetch = approval ? (input, init)=>{
            try {
              // decodeRosterSource has finished its awaited HMAC before this
              // actual fetch entry. No await follows the fresh check.
              assertRosterAiDispatchApproval(config, approval, deps.configuration());
            } catch (error) {
              approvalDenied = true;
              throw error;
            }
            return (deps.decoderFetch ?? fetch)(input, init);
          } : deps.decoderFetch;
          let decoded;
          try {
            decoded = await decodeRosterSource(source, hash, reservationId, {
              url: config.decoderUrl,
              secret: config.decoderSecret,
              buildSha256: config.decoderBuildSha256
            }, decoderFetch);
          } catch (error) {
            // The decoder adapter sanitizes fetch errors. Preserve a local
            // approval denial without changing genuine decoder error behavior.
            if (approvalDenied) {
              throw new PublicError("roster_extraction_unavailable", 503);
            }
            throw error;
          }
          const verified = record(await rpc(deps, "verify_roster_source_integrity", {
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
              expanded_bytes: decoded.expanded_bytes
            }
          }));
          exact(verified, [
            "contract_version",
            "ok",
            "reservation_id",
            "source_sha256",
            "derived_sha256",
            "decoder_receipt_sha256",
            "verified"
          ]);
          if (verified.contract_version !== 1 || verified.ok !== true || verified.reservation_id !== reservationId || verified.source_sha256 !== hash || verified.derived_sha256 !== derivedHash || verified.decoder_receipt_sha256 !== decoded.receipt_sha256 || verified.verified !== true) receiptError();
        }
      }
      const registered = record(await rpc(deps, "create_roster_import_source", {
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
        p_ai_metadata: source.ai ? {
          provider: "openai",
          model,
          prompt_version: ROSTER_PROMPT_VERSION
        } : null
      }));
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
        "error_code"
      ]);
      if (registered.contract_version !== 1 || registered.ok !== true || registered.request_id !== source.requestId || registered.source_sha256 !== hash || registered.source_size !== source.bytes.length || registered.source_kind !== source.kind || registered.derived_sha256 !== derivedHash || registered.derived_assurance !== (source.kind === "xlsx" ? "client_derived_tsv" : null) || typeof registered.replayed !== "boolean") receiptError();
      const importId = identifier(registered.import_id);
      expiry(registered.expires_at);
      if (source.ai) identifier(registered.extraction_id);
      else if (registered.extraction_id !== null) receiptError();
      if (registered.state === "preview_ready" && registered.replayed === true && registered.error_code === null) {
        return jsonResponse(previewReceipt(registered.completed_preview, source, hash, importId, derivedHash, registered.extraction_id, model));
      }
      if (registered.state === "failed" && registered.replayed === true && registered.completed_preview === null && failureCodes.has(String(registered.error_code))) throw new PublicError(String(registered.error_code), 502);
      if (registered.state !== "awaiting_preview" || registered.replayed !== false || registered.completed_preview !== null || registered.error_code !== null) receiptError();
      if (budget.state !== "reserved") receiptError();
      sourceId = importId;
      let candidates, responseId = null, responseHash = null;
      if (source.ai) {
        if (!config.apiKey) {
          throw new PublicError("roster_extraction_unavailable", 503);
        }
        const init = {
          method: "POST",
          headers: {
            authorization: `Bearer ${config.apiKey}`,
            "content-type": "application/json",
            "OpenAI-Organization": approval.organizationId,
            "OpenAI-Project": approval.projectId
          },
          body: JSON.stringify(buildRosterResponsesRequest(model, source.kind, source.filename, source.mime, source.base64)),
          signal: AbortSignal.timeout(60_000),
          redirect: "error"
        };
        // Source ACK and decoder awaits have settled. Recheck the same approval,
        // raw configuration and current window directly before the fetch.
        assertRosterAiDispatchApproval(config, approval, deps.configuration());
        let response;
        // Once a provider request can leave this process, an error does not
        // prove it was unbilled/stopped. Keep its active lease and full charge.
        budgetOutcome = "ambiguous";
        try {
          response = await (deps.fetch ?? fetch)(ROSTER_OPENAI_RESPONSES_ENDPOINT, init);
        } catch (error) {
          throw new PublicError(error instanceof DOMException && [
            "TimeoutError",
            "AbortError"
          ].includes(error.name) ? "roster_extraction_timeout" : "roster_extraction_failed", 502);
        }
        if (!response.ok) {
          try {
            await response.body?.cancel();
          } catch  {}
          throw new PublicError("roster_extraction_failed", 502);
        }
        let raw, data;
        try {
          raw = await boundedBody(response, MAX_ROSTER_PROVIDER_BYTES);
          data = JSON.parse(raw);
        } catch (error) {
          throw new PublicError(error instanceof PublicError && error.code === "payload_too_large" ? "roster_provider_response_too_large" : error instanceof DOMException && [
            "TimeoutError",
            "AbortError"
          ].includes(error.name) ? "roster_extraction_timeout" : "roster_provider_response_invalid", 502);
        }
        candidates = rosterResponseCandidates(data);
        responseId = providerIdentifier(data.id, 256);
        responseHash = await rosterSha256(encoder.encode(raw));
      } else {
        try {
          candidates = parseRosterText(source.content);
          if (candidates.length > 500 || candidates.some((row)=>row.source_row > 2147483647 || [
              ...row.member_name
            ].length > 480 || [
              ...row.momo_name
            ].length > 480 || [
              ...row.momo_number
            ].length > 32 || [
              row.member_name,
              row.momo_name,
              row.momo_number
            ].some((value)=>value.includes("\u0000")))) throw new Error("Candidate limits exceeded");
        } catch  {
          throw new PublicError("roster_preview_invalid");
        }
      }
      if (candidates.some((row)=>row.source_row > 2147483647)) {
        throw new PublicError("roster_provider_response_invalid", 502);
      }
      if (rosterCandidateJsonbBytes(candidates) > 512_000) {
        throw new PublicError(source.ai ? "roster_provider_response_too_large" : "roster_preview_invalid", source.ai ? 502 : 400);
      }
      completionAttempted = true;
      let completed;
      try {
        completed = await rpc(deps, "complete_roster_import_preview", {
          p_import_id: sourceId,
          p_actor_id: actorId,
          p_session_id: sessionId,
          p_candidates: candidates,
          p_processing_metadata: {
            processing_method: source.ai ? "openai_structured_extraction" : "deterministic",
            provider_response_sha256: responseHash,
            provider_response_id: responseId
          }
        });
      } catch (error) {
        if (error instanceof PublicError && error.code === "roster_preview_invalid") completionAttempted = false;
        throw error;
      }
      const validated = previewReceipt(completed, source, hash, sourceId, derivedHash, registered.extraction_id, model);
      budgetOutcome = "preview_ready";
      return jsonResponse(validated);
    } catch (error) {
      if (sourceId && actorId && sessionId && !completionAttempted) {
        const code = error instanceof PublicError && failureCodes.has(error.code) ? error.code : "roster_extraction_failed";
        try {
          const failed = record(await rpc(deps, "fail_roster_import_preview", {
            p_import_id: sourceId,
            p_actor_id: actorId,
            p_session_id: sessionId,
            p_error_code: code
          }));
          exact(failed, [
            "contract_version",
            "ok",
            "import_id",
            "state",
            "error_code",
            "replayed"
          ]);
          if (failed.contract_version !== 1 || failed.ok !== true || failed.import_id !== sourceId || failed.state !== "failed" || failed.error_code !== code || typeof failed.replayed !== "boolean") receiptError();
        } catch  {
          return jsonResponse({
            error: "roster_receipt_unavailable"
          }, 503);
        }
      }
      const failure = publicFailure(error);
      return jsonResponse({
        error: failure.error
      }, failure.status);
    } finally{
      if (reservationId && actorId && sessionId) {
        // Durable receipt outcomes remain authoritative even if this cleanup
        // ACK is lost. reserve_roster_resources repairs from immutable results.
        try {
          const finished = record(await rpc(deps, "finish_roster_resources", {
            p_reservation_id: reservationId,
            p_actor_id: actorId,
            p_session_id: sessionId,
            p_outcome: budgetOutcome
          }));
          exact(finished, [
            "contract_version",
            "ok",
            "reservation_id",
            "outcome",
            "charged"
          ]);
          if (finished.contract_version !== 1 || finished.ok !== true || finished.reservation_id !== reservationId || finished.outcome !== budgetOutcome || finished.charged !== true) receiptError();
        } catch  {}
      }
    }
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3ByZXBhcmUtcm9zdGVyLWltcG9ydC9oYW5kbGVyLnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7XG4gIGJvdW5kZWRCb2R5LFxuICBib3VuZGVkSnNvbixcbiAgb2JqZWN0VmFsdWUsXG4gIFB1YmxpY0Vycm9yLFxuICBwdWJsaWNGYWlsdXJlLFxuICBTSEEyNTYsXG4gIHV1aWQsXG4gIHpvbmVkSW5zdGFudCxcbn0gZnJvbSBcIi4uL19zaGFyZWQvcHJvZHVjdGlvbl9jb250cmFjdC50c1wiO1xuaW1wb3J0IHsgY29yc0hlYWRlcnMsIGpzb25SZXNwb25zZSB9IGZyb20gXCIuLi9fc2hhcmVkL2NvcnMudHNcIjtcbmltcG9ydCB7XG4gIE1BWF9ST1NURVJfUkVRVUVTVF9CWVRFUyxcbiAgcmVhZFJvc3RlclNvdXJjZSxcbiAgUk9TVEVSX0FJX0NPTlNFTlQsXG4gIFJPU1RFUl9QUk9NUFRfVkVSU0lPTixcbiAgcm9zdGVyQ2FuZGlkYXRlSnNvbmJCeXRlcyxcbiAgcm9zdGVyU2Vzc2lvbixcbiAgcm9zdGVyU2hhMjU2LFxuICB0eXBlIFJvc3RlclNvdXJjZSxcbn0gZnJvbSBcIi4uL19zaGFyZWQvcm9zdGVyX3Byb3ZlbmFuY2UudHNcIjtcbmltcG9ydCB7XG4gIHBhcnNlUm9zdGVyVGV4dCxcbiAgdHlwZSBSb3N0ZXJDYW5kaWRhdGUsXG59IGZyb20gXCIuLi9fc2hhcmVkL3Jvc3Rlcl9pbXBvcnQudHNcIjtcbmltcG9ydCB7IGJ1aWxkUm9zdGVyUmVzcG9uc2VzUmVxdWVzdCB9IGZyb20gXCIuLi9fc2hhcmVkL29wZW5haV9yb3N0ZXIudHNcIjtcbmltcG9ydCB7XG4gIE1BWF9ST1NURVJfUFJPVklERVJfQllURVMsXG4gIHJvc3RlclJlc3BvbnNlQ2FuZGlkYXRlcyxcbn0gZnJvbSBcIi4uL19zaGFyZWQvcm9zdGVyX3Jlc3BvbnNlX3BvbGljeS50c1wiO1xuaW1wb3J0IHsgZGVjb2RlUm9zdGVyU291cmNlIH0gZnJvbSBcIi4uL19zaGFyZWQvcm9zdGVyX2RlY29kZXIudHNcIjtcbmltcG9ydCB7IHJvc3RlckJ1ZGdldFJlY2VpcHQgfSBmcm9tIFwiLi4vX3NoYXJlZC9yb3N0ZXJfcmVzb3VyY2VfYnVkZ2V0LnRzXCI7XG5pbXBvcnQge1xuICBhc3NlcnRSb3N0ZXJBaURpc3BhdGNoQXBwcm92YWwsXG4gIHByZXBhcmVSb3N0ZXJBaURpc3BhdGNoQXBwcm92YWwsXG4gIFJPU1RFUl9PUEVOQUlfUkVTUE9OU0VTX0VORFBPSU5ULFxuICB0eXBlIFJvc3RlckFpQ29uZmlndXJhdGlvbixcbiAgdHlwZSBSb3N0ZXJBaURpc3BhdGNoQXBwcm92YWwsXG4gIHNuYXBzaG90Um9zdGVyQWlDb25maWd1cmF0aW9uLFxufSBmcm9tIFwiLi4vX3NoYXJlZC9yb3N0ZXJfYWlfZGlzcGF0Y2hfcG9saWN5LnRzXCI7XG5cbnR5cGUgUmVzdWx0ID0ge1xuICBkYXRhOiB1bmtub3duO1xuICBlcnJvcjogeyBtZXNzYWdlPzogc3RyaW5nOyBjb2RlPzogc3RyaW5nIH0gfCBudWxsO1xufTtcbmV4cG9ydCB0eXBlIFJvc3RlckhhbmRsZXJEZXBlbmRlbmNpZXMgPSB7XG4gIGF1dGhlbnRpY2F0ZShhdXRob3JpemF0aW9uOiBzdHJpbmcgfCBudWxsKTogUHJvbWlzZTx7IGlkOiBzdHJpbmcgfT47XG4gIHJwYyhuYW1lOiBzdHJpbmcsIGFyZ3M6IFJlY29yZDxzdHJpbmcsIHVua25vd24+KTogUHJvbWlzZTxSZXN1bHQ+O1xuICBjb25maWd1cmF0aW9uKCk6IFJvc3RlckFpQ29uZmlndXJhdGlvbjtcbiAgZmV0Y2g/OiB0eXBlb2YgZmV0Y2g7XG4gIGRlY29kZXJGZXRjaD86IHR5cGVvZiBmZXRjaDtcbn07XG5jb25zdCBlbmNvZGVyID0gbmV3IFRleHRFbmNvZGVyKCk7XG5jb25zdCBmYWlsdXJlQ29kZXMgPSBuZXcgU2V0KFtcbiAgXCJyb3N0ZXJfZXh0cmFjdGlvbl9mYWlsZWRcIixcbiAgXCJyb3N0ZXJfZXh0cmFjdGlvbl90aW1lb3V0XCIsXG4gIFwicm9zdGVyX2V4dHJhY3Rpb25fcmVmdXNlZFwiLFxuICBcInJvc3Rlcl9leHRyYWN0aW9uX2luY29tcGxldGVcIixcbiAgXCJyb3N0ZXJfcHJvdmlkZXJfcmVzcG9uc2VfaW52YWxpZFwiLFxuICBcInJvc3Rlcl9wcm92aWRlcl9yZXNwb25zZV90b29fbGFyZ2VcIixcbiAgXCJyb3N0ZXJfcHJldmlld19pbnZhbGlkXCIsXG4gIFwicm9zdGVyX2V4dHJhY3Rpb25fdW5hdmFpbGFibGVcIixcbl0pO1xuZnVuY3Rpb24gcmVjZWlwdEVycm9yKCk6IG5ldmVyIHtcbiAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX3JlY2VpcHRfaW52YWxpZFwiLCA1MDMpO1xufVxuZnVuY3Rpb24gaWRlbnRpZmllcih2YWx1ZTogdW5rbm93bik6IHN0cmluZyB7XG4gIHRyeSB7XG4gICAgcmV0dXJuIHV1aWQodmFsdWUsIFwicm9zdGVyX3JlY2VpcHRfaW52YWxpZFwiKTtcbiAgfSBjYXRjaCB7XG4gICAgcmV0dXJuIHJlY2VpcHRFcnJvcigpO1xuICB9XG59XG5mdW5jdGlvbiByZWNvcmQodmFsdWU6IHVua25vd24pOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiB7XG4gIHRyeSB7XG4gICAgcmV0dXJuIG9iamVjdFZhbHVlKHZhbHVlKTtcbiAgfSBjYXRjaCB7XG4gICAgcmV0dXJuIHJlY2VpcHRFcnJvcigpO1xuICB9XG59XG5mdW5jdGlvbiBleGFjdCh2YWx1ZTogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sIGZpZWxkczogc3RyaW5nW10pOiB2b2lkIHtcbiAgaWYgKFxuICAgIE9iamVjdC5rZXlzKHZhbHVlKS5sZW5ndGggIT09IGZpZWxkcy5sZW5ndGggfHxcbiAgICBmaWVsZHMuc29tZSgoa2V5KSA9PiAhKGtleSBpbiB2YWx1ZSkpXG4gICkgcmVjZWlwdEVycm9yKCk7XG59XG5mdW5jdGlvbiBkaWdlc3QodmFsdWU6IHVua25vd24pOiBzdHJpbmcge1xuICBpZiAodHlwZW9mIHZhbHVlICE9PSBcInN0cmluZ1wiIHx8ICFTSEEyNTYudGVzdCh2YWx1ZSkpIHJlY2VpcHRFcnJvcigpO1xuICByZXR1cm4gdmFsdWU7XG59XG5mdW5jdGlvbiBleHBpcnkodmFsdWU6IHVua25vd24pOiB2b2lkIHtcbiAgbGV0IHBhcnNlZDogc3RyaW5nIHwgbnVsbDtcbiAgdHJ5IHtcbiAgICBwYXJzZWQgPSB6b25lZEluc3RhbnQodmFsdWUpO1xuICB9IGNhdGNoIHtcbiAgICByZWNlaXB0RXJyb3IoKTtcbiAgfVxuICBpZiAocGFyc2VkID09PSBudWxsKSByZWNlaXB0RXJyb3IoKTtcbiAgaWYgKERhdGUucGFyc2UocGFyc2VkKSA8PSBEYXRlLm5vdygpKSB7XG4gICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX2ltcG9ydF9leHBpcmVkXCIsIDQwOSk7XG4gIH1cbn1cbmZ1bmN0aW9uIHByb3ZpZGVySWRlbnRpZmllcih2YWx1ZTogdW5rbm93biwgbWF4OiBudW1iZXIpOiBzdHJpbmcge1xuICBpZiAoXG4gICAgdHlwZW9mIHZhbHVlICE9PSBcInN0cmluZ1wiIHx8XG4gICAgIW5ldyBSZWdFeHAoYF5bQS1aYS16MC05XVtBLVphLXowLTkuXzovLV17MCwke21heCAtIDF9fSRgKS50ZXN0KHZhbHVlKVxuICApIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJvc3Rlcl9wcm92aWRlcl9yZXNwb25zZV9pbnZhbGlkXCIsIDUwMik7XG4gIHJldHVybiB2YWx1ZTtcbn1cbmZ1bmN0aW9uIHByZXZpZXdSZWNlaXB0KFxuICB2YWx1ZTogdW5rbm93bixcbiAgc291cmNlOiBSb3N0ZXJTb3VyY2UsXG4gIGhhc2g6IHN0cmluZyxcbiAgaW1wb3J0SWQ6IHN0cmluZyxcbiAgZGVyaXZlZEhhc2g6IHN0cmluZyB8IG51bGwsXG4gIGV4dHJhY3Rpb25JZDogdW5rbm93bixcbiAgZXhwZWN0ZWRNb2RlbDogc3RyaW5nIHwgbnVsbCxcbik6IFJlY29yZDxzdHJpbmcsIHVua25vd24+IHtcbiAgY29uc3QgciA9IHJlY29yZCh2YWx1ZSk7XG4gIGV4YWN0KHIsIFtcbiAgICBcImNvbnRyYWN0X3ZlcnNpb25cIixcbiAgICBcIm9rXCIsXG4gICAgXCJpbXBvcnRfaWRcIixcbiAgICBcInNvdXJjZV9zaGEyNTZcIixcbiAgICBcInNvdXJjZV9raW5kXCIsXG4gICAgXCJzb3VyY2VfcmVjZWlwdFwiLFxuICAgIFwicmV2aXNpb25faWRcIixcbiAgICBcInBhcmVudF9yZXZpc2lvbl9pZFwiLFxuICAgIFwicmV2aXNpb25fbnVtYmVyXCIsXG4gICAgXCJyZXZpZXdlZF9yb3dzX3NoYTI1NlwiLFxuICAgIFwiY2FuX3N1Ym1pdFwiLFxuICAgIFwicmVxdWlyZXNfaHVtYW5fcmV2aWV3XCIsXG4gICAgXCJwcm9jZXNzaW5nX21ldGhvZFwiLFxuICAgIFwibW9kZWxcIixcbiAgICBcInJvd3NcIixcbiAgICBcInJvd19jb3VudFwiLFxuICAgIFwicmVhZHlfY291bnRcIixcbiAgICBcImVycm9yX2NvdW50XCIsXG4gICAgXCJub3JtYWxpemVkX3Jvd3NcIixcbiAgICBcImV4cGlyZXNfYXRcIixcbiAgXSk7XG4gIGlmIChcbiAgICByLmNvbnRyYWN0X3ZlcnNpb24gIT09IDEgfHwgci5vayAhPT0gdHJ1ZSB8fCByLmltcG9ydF9pZCAhPT0gaW1wb3J0SWQgfHxcbiAgICByLnNvdXJjZV9zaGEyNTYgIT09IGhhc2ggfHwgci5zb3VyY2Vfa2luZCAhPT0gc291cmNlLmtpbmQgfHxcbiAgICByLnBhcmVudF9yZXZpc2lvbl9pZCAhPT0gbnVsbCB8fCByLnJldmlzaW9uX251bWJlciAhPT0gMSB8fFxuICAgIHIuY2FuX3N1Ym1pdCAhPT0gZmFsc2UgfHwgci5yZXF1aXJlc19odW1hbl9yZXZpZXcgIT09IHRydWUgfHxcbiAgICByLnByb2Nlc3NpbmdfbWV0aG9kICE9PVxuICAgICAgKHNvdXJjZS5haSA/IFwib3BlbmFpX3N0cnVjdHVyZWRfZXh0cmFjdGlvblwiIDogXCJkZXRlcm1pbmlzdGljXCIpXG4gICkgcmVjZWlwdEVycm9yKCk7XG4gIGNvbnN0IHByb3ZlbmFuY2UgPSByZWNvcmQoci5zb3VyY2VfcmVjZWlwdCk7XG4gIGV4YWN0KHByb3ZlbmFuY2UsIFtcbiAgICBcInJlcXVlc3RfaWRcIixcbiAgICBcInNvdXJjZV9zaXplXCIsXG4gICAgXCJjbGllbnRfZmlsZW5hbWVcIixcbiAgICBcImRlY2xhcmVkX21pbWVcIixcbiAgICBcImRldGVjdGVkX3R5cGVcIixcbiAgICBcImRlcml2ZWRfc2hhMjU2XCIsXG4gICAgXCJkZXJpdmVkX2Fzc3VyYW5jZVwiLFxuICAgIFwiZXh0cmFjdGlvbl9pZFwiLFxuICAgIFwiYWlfY29uc2VudFwiLFxuICAgIFwiY29uc2VudF92ZXJzaW9uXCIsXG4gICAgXCJwYXJzZXJfdmVyc2lvblwiLFxuICAgIFwic2NoZW1hX3ZlcnNpb25cIixcbiAgXSk7XG4gIGlmIChcbiAgICBwcm92ZW5hbmNlLnJlcXVlc3RfaWQgIT09IHNvdXJjZS5yZXF1ZXN0SWQgfHxcbiAgICBwcm92ZW5hbmNlLnNvdXJjZV9zaXplICE9PSBzb3VyY2UuYnl0ZXMubGVuZ3RoIHx8XG4gICAgcHJvdmVuYW5jZS5jbGllbnRfZmlsZW5hbWUgIT09IHNvdXJjZS5maWxlbmFtZSB8fFxuICAgIHByb3ZlbmFuY2UuZGVjbGFyZWRfbWltZSAhPT0gc291cmNlLm1pbWUgfHxcbiAgICBwcm92ZW5hbmNlLmRldGVjdGVkX3R5cGUgIT09IHNvdXJjZS5kZXRlY3RlZCB8fFxuICAgIHByb3ZlbmFuY2UuZGVyaXZlZF9zaGEyNTYgIT09IGRlcml2ZWRIYXNoIHx8XG4gICAgcHJvdmVuYW5jZS5kZXJpdmVkX2Fzc3VyYW5jZSAhPT1cbiAgICAgIChzb3VyY2Uua2luZCA9PT0gXCJ4bHN4XCIgPyBcImNsaWVudF9kZXJpdmVkX3RzdlwiIDogbnVsbCkgfHxcbiAgICBwcm92ZW5hbmNlLmV4dHJhY3Rpb25faWQgIT09IGV4dHJhY3Rpb25JZCB8fFxuICAgIHByb3ZlbmFuY2UuYWlfY29uc2VudCAhPT0gc291cmNlLmFpIHx8XG4gICAgcHJvdmVuYW5jZS5jb25zZW50X3ZlcnNpb24gIT09IChzb3VyY2UuYWkgPyBST1NURVJfQUlfQ09OU0VOVCA6IG51bGwpIHx8XG4gICAgcHJvdmVuYW5jZS5wYXJzZXJfdmVyc2lvbiAhPT0gXCJjb2xsZWN0LXJvc3Rlci1wYXJzZXItdjFcIiB8fFxuICAgIHByb3ZlbmFuY2Uuc2NoZW1hX3ZlcnNpb24gIT09IFwiY29sbGVjdC1yb3N0ZXItcm93cy12MVwiIHx8XG4gICAgci5tb2RlbCAhPT0gZXhwZWN0ZWRNb2RlbFxuICApIHJlY2VpcHRFcnJvcigpO1xuICBpZGVudGlmaWVyKHIucmV2aXNpb25faWQpO1xuICBkaWdlc3Qoci5yZXZpZXdlZF9yb3dzX3NoYTI1Nik7XG4gIGV4cGlyeShyLmV4cGlyZXNfYXQpO1xuICBpZiAoc291cmNlLmFpKSB7XG4gICAgdHJ5IHtcbiAgICAgIHByb3ZpZGVySWRlbnRpZmllcihyLm1vZGVsLCAxMjgpO1xuICAgIH0gY2F0Y2gge1xuICAgICAgcmVjZWlwdEVycm9yKCk7XG4gICAgfVxuICB9IGVsc2UgaWYgKHIubW9kZWwgIT09IG51bGwpIHJlY2VpcHRFcnJvcigpO1xuICBpZiAoXG4gICAgIUFycmF5LmlzQXJyYXkoci5yb3dzKSB8fCByLnJvd3MubGVuZ3RoIDwgMSB8fCByLnJvd3MubGVuZ3RoID4gNTAwIHx8XG4gICAgIUFycmF5LmlzQXJyYXkoci5ub3JtYWxpemVkX3Jvd3MpXG4gICkgcmVjZWlwdEVycm9yKCk7XG4gIGxldCByZWFkeSA9IDA7XG4gIGZvciAoY29uc3QgdmFsdWUgb2Ygci5yb3dzKSB7XG4gICAgY29uc3Qgcm93ID0gcmVjb3JkKHZhbHVlKTtcbiAgICBleGFjdChyb3csIFtcbiAgICAgIFwic291cmNlX3Jvd1wiLFxuICAgICAgXCJtZW1iZXJfbmFtZVwiLFxuICAgICAgXCJtb21vX25hbWVcIixcbiAgICAgIFwibW9tb19udW1iZXJcIixcbiAgICAgIFwiY29uZmlkZW5jZVwiLFxuICAgICAgXCJpc3N1ZXNcIixcbiAgICAgIFwicmVhZHlcIixcbiAgICBdKTtcbiAgICBpZiAoXG4gICAgICAhTnVtYmVyLmlzU2FmZUludGVnZXIocm93LnNvdXJjZV9yb3cpIHx8IE51bWJlcihyb3cuc291cmNlX3JvdykgPCAxIHx8XG4gICAgICBOdW1iZXIocm93LnNvdXJjZV9yb3cpID4gMjE0NzQ4MzY0NyB8fFxuICAgICAgdHlwZW9mIHJvdy5jb25maWRlbmNlICE9PSBcIm51bWJlclwiIHx8ICFOdW1iZXIuaXNGaW5pdGUocm93LmNvbmZpZGVuY2UpIHx8XG4gICAgICByb3cuY29uZmlkZW5jZSA8IDAgfHwgcm93LmNvbmZpZGVuY2UgPiAxIHx8XG4gICAgICB0eXBlb2Ygcm93LnJlYWR5ICE9PSBcImJvb2xlYW5cIiB8fCAhQXJyYXkuaXNBcnJheShyb3cuaXNzdWVzKSB8fFxuICAgICAgcm93Lmlzc3Vlcy5sZW5ndGggPiAxMiB8fCByb3cuaXNzdWVzLnNvbWUoKGkpID0+XG4gICAgICAgIHR5cGVvZiBpICE9PSBcInN0cmluZ1wiIHx8IGkubGVuZ3RoID4gMjU2XG4gICAgICApXG4gICAgKSByZWNlaXB0RXJyb3IoKTtcbiAgICBmb3IgKGNvbnN0IGtleSBvZiBbXCJtZW1iZXJfbmFtZVwiLCBcIm1vbW9fbmFtZVwiLCBcIm1vbW9fbnVtYmVyXCJdKSB7XG4gICAgICBpZiAoXG4gICAgICAgIHR5cGVvZiByb3dba2V5XSAhPT0gXCJzdHJpbmdcIiB8fFxuICAgICAgICBbLi4uKHJvd1trZXldIGFzIHN0cmluZyldLmxlbmd0aCA+IChrZXkgPT09IFwibW9tb19udW1iZXJcIiA/IDMyIDogNDgwKVxuICAgICAgKSByZWNlaXB0RXJyb3IoKTtcbiAgICB9XG4gICAgaWYgKHJvdy5yZWFkeSkge1xuICAgICAgcmVhZHkrKztcbiAgICAgIGlmIChyb3cuaXNzdWVzLmxlbmd0aCkgcmVjZWlwdEVycm9yKCk7XG4gICAgfVxuICB9XG4gIGlmIChcbiAgICByLnJvd19jb3VudCAhPT0gci5yb3dzLmxlbmd0aCB8fCByLnJlYWR5X2NvdW50ICE9PSByZWFkeSB8fFxuICAgIHIuZXJyb3JfY291bnQgIT09IHIucm93cy5sZW5ndGggLSByZWFkeSB8fFxuICAgIHIubm9ybWFsaXplZF9yb3dzLmxlbmd0aCAhPT0gcmVhZHlcbiAgKSByZWNlaXB0RXJyb3IoKTtcbiAgY29uc3QgcmVhZHlSb3dzID0gci5yb3dzLmZpbHRlcigocm93KSA9PiByb3cucmVhZHkpO1xuICBmb3IgKGNvbnN0IFtpbmRleCwgdmFsdWVdIG9mIHIubm9ybWFsaXplZF9yb3dzLmVudHJpZXMoKSkge1xuICAgIGNvbnN0IHJvdyA9IHJlY29yZCh2YWx1ZSk7XG4gICAgZXhhY3Qocm93LCBbXCJtZW1iZXJfbmFtZVwiLCBcIm1vbW9fbmFtZVwiLCBcIm1vbW9fbnVtYmVyXCJdKTtcbiAgICBmb3IgKGNvbnN0IGtleSBvZiBPYmplY3Qua2V5cyhyb3cpKSB7XG4gICAgICBpZiAodHlwZW9mIHJvd1trZXldICE9PSBcInN0cmluZ1wiIHx8IHJvd1trZXldICE9PSByZWFkeVJvd3NbaW5kZXhdW2tleV0pIHtcbiAgICAgICAgcmVjZWlwdEVycm9yKCk7XG4gICAgICB9XG4gICAgfVxuICB9XG4gIHJldHVybiByO1xufVxuYXN5bmMgZnVuY3Rpb24gcnBjKFxuICBkZXBzOiBSb3N0ZXJIYW5kbGVyRGVwZW5kZW5jaWVzLFxuICBuYW1lOiBzdHJpbmcsXG4gIGFyZ3M6IFJlY29yZDxzdHJpbmcsIHVua25vd24+LFxuKTogUHJvbWlzZTx1bmtub3duPiB7XG4gIGxldCByZXN1bHQ6IFJlc3VsdDtcbiAgdHJ5IHtcbiAgICByZXN1bHQgPSBhd2FpdCBkZXBzLnJwYyhuYW1lLCBhcmdzKTtcbiAgfSBjYXRjaCB7XG4gICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX3JlY2VpcHRfdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgfVxuICBpZiAocmVzdWx0LmVycm9yKSB7XG4gICAgY29uc3QgY29kZSA9IHJlc3VsdC5lcnJvci5tZXNzYWdlO1xuICAgIGlmIChjb2RlID09PSBcInJvc3Rlcl9pbXBvcnRfbGltaXRcIikgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKGNvZGUsIDQyOSk7XG4gICAgaWYgKGNvZGUgPT09IFwicm9zdGVyX3Jlc291cmNlX2xpbWl0XCIpIHRocm93IG5ldyBQdWJsaWNFcnJvcihjb2RlLCA0MjkpO1xuICAgIGlmIChjb2RlID09PSBcInJvc3Rlcl9yZXNvdXJjZV9pbl9wcm9ncmVzc1wiKSB7XG4gICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoY29kZSwgNDA5KTtcbiAgICB9XG4gICAgLy8gQSByZWNlaXZlZCBTUUwgaW52YWxpZC1pbnB1dCByZXN1bHQgcHJvdmVzIHRoYXQgY29tcGxldGlvbiByb2xsZWQgYmFjay5cbiAgICBpZiAoXG4gICAgICBuYW1lID09PSBcImNvbXBsZXRlX3Jvc3Rlcl9pbXBvcnRfcHJldmlld1wiICYmIHJlc3VsdC5lcnJvci5jb2RlID09PSBcIjIyMDIzXCJcbiAgICApIHtcbiAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJvc3Rlcl9wcmV2aWV3X2ludmFsaWRcIik7XG4gICAgfVxuICAgIGlmIChjb2RlID09PSBcInJvc3Rlcl9pbXBvcnRfaW5fcHJvZ3Jlc3NcIikgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKGNvZGUsIDQwOSk7XG4gICAgaWYgKFxuICAgICAgY29kZSA9PT0gXCJyb3N0ZXJfcmVxdWVzdF9jb25mbGljdFwiIHx8IGNvZGUgPT09IFwicm9zdGVyX2ltcG9ydF9leHBpcmVkXCJcbiAgICApIHRocm93IG5ldyBQdWJsaWNFcnJvcihjb2RlLCA0MDkpO1xuICAgIGlmIChyZXN1bHQuZXJyb3IuY29kZSA9PT0gXCI0MjUwMVwiKSB7XG4gICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyb3N0ZXJfaW1wb3J0X2ZvcmJpZGRlblwiLCA0MDMpO1xuICAgIH1cbiAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyb3N0ZXJfcmVjZWlwdF91bmF2YWlsYWJsZVwiLCA1MDMpO1xuICB9XG4gIHJldHVybiByZXN1bHQuZGF0YTtcbn1cbmV4cG9ydCBmdW5jdGlvbiBjcmVhdGVSb3N0ZXJJbXBvcnRIYW5kbGVyKFxuICBkZXBzOiBSb3N0ZXJIYW5kbGVyRGVwZW5kZW5jaWVzLFxuKTogKHJlcXVlc3Q6IFJlcXVlc3QpID0+IFByb21pc2U8UmVzcG9uc2U+IHtcbiAgcmV0dXJuIGFzeW5jIChyZXF1ZXN0KSA9PiB7XG4gICAgaWYgKHJlcXVlc3QubWV0aG9kID09PSBcIk9QVElPTlNcIikge1xuICAgICAgcmV0dXJuIG5ldyBSZXNwb25zZShcIm9rXCIsIHsgaGVhZGVyczogY29yc0hlYWRlcnMgfSk7XG4gICAgfVxuICAgIGlmIChyZXF1ZXN0Lm1ldGhvZCAhPT0gXCJQT1NUXCIpIHtcbiAgICAgIHJldHVybiBqc29uUmVzcG9uc2UoeyBlcnJvcjogXCJtZXRob2Rfbm90X2FsbG93ZWRcIiB9LCA0MDUpO1xuICAgIH1cbiAgICBsZXQgc291cmNlSWQ6IHN0cmluZyB8IG51bGwgPSBudWxsLFxuICAgICAgYWN0b3JJZDogc3RyaW5nIHwgbnVsbCA9IG51bGwsXG4gICAgICBzZXNzaW9uSWQ6IHN0cmluZyB8IG51bGwgPSBudWxsLFxuICAgICAgY29tcGxldGlvbkF0dGVtcHRlZCA9IGZhbHNlLFxuICAgICAgcmVzZXJ2YXRpb25JZDogc3RyaW5nIHwgbnVsbCA9IG51bGwsXG4gICAgICBidWRnZXRPdXRjb21lOiBcInByZXZpZXdfcmVhZHlcIiB8IFwiZmFpbGVkXCIgfCBcImFtYmlndW91c1wiID0gXCJmYWlsZWRcIjtcbiAgICB0cnkge1xuICAgICAgY29uc3QgYXV0aG9yaXphdGlvbiA9IHJlcXVlc3QuaGVhZGVycy5nZXQoXCJhdXRob3JpemF0aW9uXCIpO1xuICAgICAgLy8gQXV0aGVudGljYXRpbmcgZmlyc3QgaXMgZXNzZW50aWFsOiBkZWNvZGVkIEpXVCBmaWVsZHMgYXJlIG5vdCBwcm9vZi5cbiAgICAgIGNvbnN0IHVzZXIgPSBhd2FpdCBkZXBzLmF1dGhlbnRpY2F0ZShhdXRob3JpemF0aW9uKTtcbiAgICAgICh7IGFjdG9ySWQsIHNlc3Npb25JZCB9ID0gcm9zdGVyU2Vzc2lvbihhdXRob3JpemF0aW9uLCB1c2VyLmlkKSk7XG4gICAgICBjb25zdCBzb3VyY2UgPSByZWFkUm9zdGVyU291cmNlKFxuICAgICAgICBhd2FpdCBib3VuZGVkSnNvbihyZXF1ZXN0LCBNQVhfUk9TVEVSX1JFUVVFU1RfQllURVMpLFxuICAgICAgKTtcbiAgICAgIGNvbnN0IGhhc2ggPSBhd2FpdCByb3N0ZXJTaGEyNTYoc291cmNlLmJ5dGVzKTtcbiAgICAgIGNvbnN0IGRlcml2ZWRIYXNoID0gc291cmNlLmRlcml2ZWRcbiAgICAgICAgPyBhd2FpdCByb3N0ZXJTaGEyNTYoc291cmNlLmRlcml2ZWQpXG4gICAgICAgIDogbnVsbDtcbiAgICAgIGNvbnN0IGNvbmZpZyA9IHNuYXBzaG90Um9zdGVyQWlDb25maWd1cmF0aW9uKGRlcHMuY29uZmlndXJhdGlvbigpKTtcbiAgICAgIGxldCBhcHByb3ZhbDogUm9zdGVyQWlEaXNwYXRjaEFwcHJvdmFsIHwgbnVsbCA9IG51bGw7XG4gICAgICBsZXQgbW9kZWw6IHN0cmluZyB8IG51bGwgPSBudWxsO1xuICAgICAgaWYgKHNvdXJjZS5haSkge1xuICAgICAgICB0cnkge1xuICAgICAgICAgIG1vZGVsID0gcHJvdmlkZXJJZGVudGlmaWVyKGNvbmZpZy5tb2RlbCwgMTI4KTtcbiAgICAgICAgfSBjYXRjaCB7XG4gICAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX2V4dHJhY3Rpb25fdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgICAgICAgfVxuICAgICAgICBhcHByb3ZhbCA9IGF3YWl0IHByZXBhcmVSb3N0ZXJBaURpc3BhdGNoQXBwcm92YWwoY29uZmlnKTtcbiAgICAgICAgLy8gSGFzaCB2YWxpZGF0aW9uIGhhcyBzZXR0bGVkLiBGcmVzaCBjb25maWd1cmF0aW9uIGFuZCB0aW1lIGFyZSBjaGVja2VkXG4gICAgICAgIC8vIHN5bmNocm9ub3VzbHkgYmVmb3JlIGFueSByZXNlcnZhdGlvbiBvciBleHRlcm5hbCB3b3JrIGNhbiBzdGFydC5cbiAgICAgICAgYXNzZXJ0Um9zdGVyQWlEaXNwYXRjaEFwcHJvdmFsKGNvbmZpZywgYXBwcm92YWwsIGRlcHMuY29uZmlndXJhdGlvbigpKTtcbiAgICAgIH1cbiAgICAgIGNvbnN0IGJ1ZGdldCA9IHJvc3RlckJ1ZGdldFJlY2VpcHQoXG4gICAgICAgIGF3YWl0IHJwYyhkZXBzLCBcInJlc2VydmVfcm9zdGVyX3Jlc291cmNlc1wiLCB7XG4gICAgICAgICAgcF9hY3Rvcl9pZDogYWN0b3JJZCxcbiAgICAgICAgICBwX3Nlc3Npb25faWQ6IHNlc3Npb25JZCxcbiAgICAgICAgICBwX3JlcXVlc3RfaWQ6IHNvdXJjZS5yZXF1ZXN0SWQsXG4gICAgICAgICAgcF9zb3VyY2Vfc2hhMjU2OiBoYXNoLFxuICAgICAgICAgIHBfc291cmNlX2tpbmQ6IHNvdXJjZS5raW5kLFxuICAgICAgICAgIHBfc291cmNlX2J5dGVzOiBzb3VyY2UuYnl0ZXMubGVuZ3RoLFxuICAgICAgICAgIHBfZGVyaXZlZF9zaGEyNTY6IGRlcml2ZWRIYXNoLFxuICAgICAgICB9KSxcbiAgICAgICAgeyByZXF1ZXN0SWQ6IHNvdXJjZS5yZXF1ZXN0SWQsIGFjdG9ySWQsIHNlc3Npb25JZCwgc291cmNlSGFzaDogaGFzaCB9LFxuICAgICAgKTtcbiAgICAgIC8vIEEgcmVwbGF5IG1heSByZXR1cm4gYW4gZXhpc3RpbmcgaW1tdXRhYmxlIHJlc3VsdCwgYnV0IG5ldmVyIGRpc3BhdGNoIGFcbiAgICAgIC8vIHNlY29uZCBkZWNvZGVyL3Byb3ZpZGVyIGF0dGVtcHQuIENyYXNoZWQgbGVhc2VzIGNhbm5vdCBiZSByZWFjcXVpcmVkLlxuICAgICAgaWYgKGJ1ZGdldC5zdGF0ZSA9PT0gXCJyZXNlcnZlZFwiKSB7XG4gICAgICAgIHJlc2VydmF0aW9uSWQgPSBidWRnZXQucmVzZXJ2YXRpb25faWQ7XG4gICAgICAgIGlmIChbXCJ4bHN4XCIsIFwiaW1hZ2VcIiwgXCJwZGZcIl0uaW5jbHVkZXMoc291cmNlLmtpbmQpKSB7XG4gICAgICAgICAgbGV0IGFwcHJvdmFsRGVuaWVkID0gZmFsc2U7XG4gICAgICAgICAgY29uc3QgZGVjb2RlckZldGNoOiB0eXBlb2YgZmV0Y2ggfCB1bmRlZmluZWQgPSBhcHByb3ZhbFxuICAgICAgICAgICAgPyAoaW5wdXQsIGluaXQpID0+IHtcbiAgICAgICAgICAgICAgdHJ5IHtcbiAgICAgICAgICAgICAgICAvLyBkZWNvZGVSb3N0ZXJTb3VyY2UgaGFzIGZpbmlzaGVkIGl0cyBhd2FpdGVkIEhNQUMgYmVmb3JlIHRoaXNcbiAgICAgICAgICAgICAgICAvLyBhY3R1YWwgZmV0Y2ggZW50cnkuIE5vIGF3YWl0IGZvbGxvd3MgdGhlIGZyZXNoIGNoZWNrLlxuICAgICAgICAgICAgICAgIGFzc2VydFJvc3RlckFpRGlzcGF0Y2hBcHByb3ZhbChcbiAgICAgICAgICAgICAgICAgIGNvbmZpZyxcbiAgICAgICAgICAgICAgICAgIGFwcHJvdmFsISxcbiAgICAgICAgICAgICAgICAgIGRlcHMuY29uZmlndXJhdGlvbigpLFxuICAgICAgICAgICAgICAgICk7XG4gICAgICAgICAgICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICAgICAgICAgICAgYXBwcm92YWxEZW5pZWQgPSB0cnVlO1xuICAgICAgICAgICAgICAgIHRocm93IGVycm9yO1xuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgIHJldHVybiAoZGVwcy5kZWNvZGVyRmV0Y2ggPz8gZmV0Y2gpKGlucHV0LCBpbml0KTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIDogZGVwcy5kZWNvZGVyRmV0Y2g7XG4gICAgICAgICAgbGV0IGRlY29kZWQ6IEF3YWl0ZWQ8UmV0dXJuVHlwZTx0eXBlb2YgZGVjb2RlUm9zdGVyU291cmNlPj47XG4gICAgICAgICAgdHJ5IHtcbiAgICAgICAgICAgIGRlY29kZWQgPSBhd2FpdCBkZWNvZGVSb3N0ZXJTb3VyY2UoXG4gICAgICAgICAgICAgIHNvdXJjZSxcbiAgICAgICAgICAgICAgaGFzaCxcbiAgICAgICAgICAgICAgcmVzZXJ2YXRpb25JZCxcbiAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgIHVybDogY29uZmlnLmRlY29kZXJVcmwsXG4gICAgICAgICAgICAgICAgc2VjcmV0OiBjb25maWcuZGVjb2RlclNlY3JldCxcbiAgICAgICAgICAgICAgICBidWlsZFNoYTI1NjogY29uZmlnLmRlY29kZXJCdWlsZFNoYTI1NixcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgZGVjb2RlckZldGNoLFxuICAgICAgICAgICAgKTtcbiAgICAgICAgICB9IGNhdGNoIChlcnJvcikge1xuICAgICAgICAgICAgLy8gVGhlIGRlY29kZXIgYWRhcHRlciBzYW5pdGl6ZXMgZmV0Y2ggZXJyb3JzLiBQcmVzZXJ2ZSBhIGxvY2FsXG4gICAgICAgICAgICAvLyBhcHByb3ZhbCBkZW5pYWwgd2l0aG91dCBjaGFuZ2luZyBnZW51aW5lIGRlY29kZXIgZXJyb3IgYmVoYXZpb3IuXG4gICAgICAgICAgICBpZiAoYXBwcm92YWxEZW5pZWQpIHtcbiAgICAgICAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX2V4dHJhY3Rpb25fdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHRocm93IGVycm9yO1xuICAgICAgICAgIH1cbiAgICAgICAgICBjb25zdCB2ZXJpZmllZCA9IHJlY29yZChcbiAgICAgICAgICAgIGF3YWl0IHJwYyhkZXBzLCBcInZlcmlmeV9yb3N0ZXJfc291cmNlX2ludGVncml0eVwiLCB7XG4gICAgICAgICAgICAgIHBfcmVzZXJ2YXRpb25faWQ6IHJlc2VydmF0aW9uSWQsXG4gICAgICAgICAgICAgIHBfYWN0b3JfaWQ6IGFjdG9ySWQsXG4gICAgICAgICAgICAgIHBfc2Vzc2lvbl9pZDogc2Vzc2lvbklkLFxuICAgICAgICAgICAgICBwX2RlY29kZXJfcmVjZWlwdF9zaGEyNTY6IGRlY29kZWQucmVjZWlwdF9zaGEyNTYsXG4gICAgICAgICAgICAgIHBfZGVjb2Rlcl9idWlsZF9zaGEyNTY6IGRlY29kZWQuZGVjb2Rlcl9idWlsZF9zaGEyNTYsXG4gICAgICAgICAgICAgIHBfcG9saWN5X3ZlcnNpb246IGRlY29kZWQucG9saWN5X3ZlcnNpb24sXG4gICAgICAgICAgICAgIHBfdG9vbGNoYWluOiBkZWNvZGVkLnRvb2xjaGFpbixcbiAgICAgICAgICAgICAgcF9zdW1tYXJ5OiB7XG4gICAgICAgICAgICAgICAgZnJhbWVzOiBkZWNvZGVkLmZyYW1lcyxcbiAgICAgICAgICAgICAgICBwYWdlczogZGVjb2RlZC5wYWdlcyxcbiAgICAgICAgICAgICAgICBwaXhlbHM6IGRlY29kZWQucGl4ZWxzLFxuICAgICAgICAgICAgICAgIGV4cGFuZGVkX2J5dGVzOiBkZWNvZGVkLmV4cGFuZGVkX2J5dGVzLFxuICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgfSksXG4gICAgICAgICAgKTtcbiAgICAgICAgICBleGFjdCh2ZXJpZmllZCwgW1xuICAgICAgICAgICAgXCJjb250cmFjdF92ZXJzaW9uXCIsXG4gICAgICAgICAgICBcIm9rXCIsXG4gICAgICAgICAgICBcInJlc2VydmF0aW9uX2lkXCIsXG4gICAgICAgICAgICBcInNvdXJjZV9zaGEyNTZcIixcbiAgICAgICAgICAgIFwiZGVyaXZlZF9zaGEyNTZcIixcbiAgICAgICAgICAgIFwiZGVjb2Rlcl9yZWNlaXB0X3NoYTI1NlwiLFxuICAgICAgICAgICAgXCJ2ZXJpZmllZFwiLFxuICAgICAgICAgIF0pO1xuICAgICAgICAgIGlmIChcbiAgICAgICAgICAgIHZlcmlmaWVkLmNvbnRyYWN0X3ZlcnNpb24gIT09IDEgfHwgdmVyaWZpZWQub2sgIT09IHRydWUgfHxcbiAgICAgICAgICAgIHZlcmlmaWVkLnJlc2VydmF0aW9uX2lkICE9PSByZXNlcnZhdGlvbklkIHx8XG4gICAgICAgICAgICB2ZXJpZmllZC5zb3VyY2Vfc2hhMjU2ICE9PSBoYXNoIHx8XG4gICAgICAgICAgICB2ZXJpZmllZC5kZXJpdmVkX3NoYTI1NiAhPT0gZGVyaXZlZEhhc2ggfHxcbiAgICAgICAgICAgIHZlcmlmaWVkLmRlY29kZXJfcmVjZWlwdF9zaGEyNTYgIT09IGRlY29kZWQucmVjZWlwdF9zaGEyNTYgfHxcbiAgICAgICAgICAgIHZlcmlmaWVkLnZlcmlmaWVkICE9PSB0cnVlXG4gICAgICAgICAgKSByZWNlaXB0RXJyb3IoKTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgICAgY29uc3QgcmVnaXN0ZXJlZCA9IHJlY29yZChcbiAgICAgICAgYXdhaXQgcnBjKGRlcHMsIFwiY3JlYXRlX3Jvc3Rlcl9pbXBvcnRfc291cmNlXCIsIHtcbiAgICAgICAgICBwX2FjdG9yX2lkOiBhY3RvcklkLFxuICAgICAgICAgIHBfc2Vzc2lvbl9pZDogc2Vzc2lvbklkLFxuICAgICAgICAgIHBfcmVxdWVzdF9pZDogc291cmNlLnJlcXVlc3RJZCxcbiAgICAgICAgICBwX3NvdXJjZV9raW5kOiBzb3VyY2Uua2luZCxcbiAgICAgICAgICBwX29yaWdpbmFsX3NoYTI1NjogaGFzaCxcbiAgICAgICAgICBwX29yaWdpbmFsX3NpemU6IHNvdXJjZS5ieXRlcy5sZW5ndGgsXG4gICAgICAgICAgcF9jbGllbnRfZmlsZW5hbWU6IHNvdXJjZS5maWxlbmFtZSxcbiAgICAgICAgICBwX2RlY2xhcmVkX21pbWU6IHNvdXJjZS5taW1lLFxuICAgICAgICAgIHBfZGV0ZWN0ZWRfdHlwZTogc291cmNlLmRldGVjdGVkLFxuICAgICAgICAgIHBfZGVyaXZlZF9zaGEyNTY6IGRlcml2ZWRIYXNoLFxuICAgICAgICAgIHBfZGVyaXZlZF9zaXplOiBzb3VyY2UuZGVyaXZlZD8ubGVuZ3RoID8/IG51bGwsXG4gICAgICAgICAgcF9haV9jb25zZW50OiBzb3VyY2UuYWksXG4gICAgICAgICAgcF9jb25zZW50X3ZlcnNpb246IHNvdXJjZS5haSA/IFJPU1RFUl9BSV9DT05TRU5UIDogbnVsbCxcbiAgICAgICAgICBwX2FpX21ldGFkYXRhOiBzb3VyY2UuYWlcbiAgICAgICAgICAgID8ge1xuICAgICAgICAgICAgICBwcm92aWRlcjogXCJvcGVuYWlcIixcbiAgICAgICAgICAgICAgbW9kZWwsXG4gICAgICAgICAgICAgIHByb21wdF92ZXJzaW9uOiBST1NURVJfUFJPTVBUX1ZFUlNJT04sXG4gICAgICAgICAgICB9XG4gICAgICAgICAgICA6IG51bGwsXG4gICAgICAgIH0pLFxuICAgICAgKTtcbiAgICAgIGV4YWN0KHJlZ2lzdGVyZWQsIFtcbiAgICAgICAgXCJjb250cmFjdF92ZXJzaW9uXCIsXG4gICAgICAgIFwib2tcIixcbiAgICAgICAgXCJyZXF1ZXN0X2lkXCIsXG4gICAgICAgIFwiaW1wb3J0X2lkXCIsXG4gICAgICAgIFwic291cmNlX3NoYTI1NlwiLFxuICAgICAgICBcInNvdXJjZV9zaXplXCIsXG4gICAgICAgIFwic291cmNlX2tpbmRcIixcbiAgICAgICAgXCJleHRyYWN0aW9uX2lkXCIsXG4gICAgICAgIFwiZXhwaXJlc19hdFwiLFxuICAgICAgICBcImRlcml2ZWRfc2hhMjU2XCIsXG4gICAgICAgIFwiZGVyaXZlZF9hc3N1cmFuY2VcIixcbiAgICAgICAgXCJzdGF0ZVwiLFxuICAgICAgICBcInJlcGxheWVkXCIsXG4gICAgICAgIFwiY29tcGxldGVkX3ByZXZpZXdcIixcbiAgICAgICAgXCJlcnJvcl9jb2RlXCIsXG4gICAgICBdKTtcbiAgICAgIGlmIChcbiAgICAgICAgcmVnaXN0ZXJlZC5jb250cmFjdF92ZXJzaW9uICE9PSAxIHx8IHJlZ2lzdGVyZWQub2sgIT09IHRydWUgfHxcbiAgICAgICAgcmVnaXN0ZXJlZC5yZXF1ZXN0X2lkICE9PSBzb3VyY2UucmVxdWVzdElkIHx8XG4gICAgICAgIHJlZ2lzdGVyZWQuc291cmNlX3NoYTI1NiAhPT0gaGFzaCB8fFxuICAgICAgICByZWdpc3RlcmVkLnNvdXJjZV9zaXplICE9PSBzb3VyY2UuYnl0ZXMubGVuZ3RoIHx8XG4gICAgICAgIHJlZ2lzdGVyZWQuc291cmNlX2tpbmQgIT09IHNvdXJjZS5raW5kIHx8XG4gICAgICAgIHJlZ2lzdGVyZWQuZGVyaXZlZF9zaGEyNTYgIT09IGRlcml2ZWRIYXNoIHx8XG4gICAgICAgIHJlZ2lzdGVyZWQuZGVyaXZlZF9hc3N1cmFuY2UgIT09XG4gICAgICAgICAgKHNvdXJjZS5raW5kID09PSBcInhsc3hcIiA/IFwiY2xpZW50X2Rlcml2ZWRfdHN2XCIgOiBudWxsKSB8fFxuICAgICAgICB0eXBlb2YgcmVnaXN0ZXJlZC5yZXBsYXllZCAhPT0gXCJib29sZWFuXCJcbiAgICAgICkgcmVjZWlwdEVycm9yKCk7XG4gICAgICBjb25zdCBpbXBvcnRJZCA9IGlkZW50aWZpZXIocmVnaXN0ZXJlZC5pbXBvcnRfaWQpO1xuICAgICAgZXhwaXJ5KHJlZ2lzdGVyZWQuZXhwaXJlc19hdCk7XG4gICAgICBpZiAoc291cmNlLmFpKSBpZGVudGlmaWVyKHJlZ2lzdGVyZWQuZXh0cmFjdGlvbl9pZCk7XG4gICAgICBlbHNlIGlmIChyZWdpc3RlcmVkLmV4dHJhY3Rpb25faWQgIT09IG51bGwpIHJlY2VpcHRFcnJvcigpO1xuICAgICAgaWYgKFxuICAgICAgICByZWdpc3RlcmVkLnN0YXRlID09PSBcInByZXZpZXdfcmVhZHlcIiAmJiByZWdpc3RlcmVkLnJlcGxheWVkID09PSB0cnVlICYmXG4gICAgICAgIHJlZ2lzdGVyZWQuZXJyb3JfY29kZSA9PT0gbnVsbFxuICAgICAgKSB7XG4gICAgICAgIHJldHVybiBqc29uUmVzcG9uc2UoXG4gICAgICAgICAgcHJldmlld1JlY2VpcHQoXG4gICAgICAgICAgICByZWdpc3RlcmVkLmNvbXBsZXRlZF9wcmV2aWV3LFxuICAgICAgICAgICAgc291cmNlLFxuICAgICAgICAgICAgaGFzaCxcbiAgICAgICAgICAgIGltcG9ydElkLFxuICAgICAgICAgICAgZGVyaXZlZEhhc2gsXG4gICAgICAgICAgICByZWdpc3RlcmVkLmV4dHJhY3Rpb25faWQsXG4gICAgICAgICAgICBtb2RlbCxcbiAgICAgICAgICApLFxuICAgICAgICApO1xuICAgICAgfVxuICAgICAgaWYgKFxuICAgICAgICByZWdpc3RlcmVkLnN0YXRlID09PSBcImZhaWxlZFwiICYmIHJlZ2lzdGVyZWQucmVwbGF5ZWQgPT09IHRydWUgJiZcbiAgICAgICAgcmVnaXN0ZXJlZC5jb21wbGV0ZWRfcHJldmlldyA9PT0gbnVsbCAmJlxuICAgICAgICBmYWlsdXJlQ29kZXMuaGFzKFN0cmluZyhyZWdpc3RlcmVkLmVycm9yX2NvZGUpKVxuICAgICAgKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoU3RyaW5nKHJlZ2lzdGVyZWQuZXJyb3JfY29kZSksIDUwMik7XG4gICAgICBpZiAoXG4gICAgICAgIHJlZ2lzdGVyZWQuc3RhdGUgIT09IFwiYXdhaXRpbmdfcHJldmlld1wiIHx8XG4gICAgICAgIHJlZ2lzdGVyZWQucmVwbGF5ZWQgIT09IGZhbHNlIHx8XG4gICAgICAgIHJlZ2lzdGVyZWQuY29tcGxldGVkX3ByZXZpZXcgIT09IG51bGwgfHwgcmVnaXN0ZXJlZC5lcnJvcl9jb2RlICE9PSBudWxsXG4gICAgICApIHJlY2VpcHRFcnJvcigpO1xuICAgICAgaWYgKGJ1ZGdldC5zdGF0ZSAhPT0gXCJyZXNlcnZlZFwiKSByZWNlaXB0RXJyb3IoKTtcbiAgICAgIHNvdXJjZUlkID0gaW1wb3J0SWQ7XG4gICAgICBsZXQgY2FuZGlkYXRlczogUm9zdGVyQ2FuZGlkYXRlW10sXG4gICAgICAgIHJlc3BvbnNlSWQ6IHN0cmluZyB8IG51bGwgPSBudWxsLFxuICAgICAgICByZXNwb25zZUhhc2g6IHN0cmluZyB8IG51bGwgPSBudWxsO1xuICAgICAgaWYgKHNvdXJjZS5haSkge1xuICAgICAgICBpZiAoIWNvbmZpZy5hcGlLZXkpIHtcbiAgICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyb3N0ZXJfZXh0cmFjdGlvbl91bmF2YWlsYWJsZVwiLCA1MDMpO1xuICAgICAgICB9XG4gICAgICAgIGNvbnN0IGluaXQ6IFJlcXVlc3RJbml0ID0ge1xuICAgICAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICAgICAgaGVhZGVyczoge1xuICAgICAgICAgICAgYXV0aG9yaXphdGlvbjogYEJlYXJlciAke2NvbmZpZy5hcGlLZXl9YCxcbiAgICAgICAgICAgIFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICAgICAgXCJPcGVuQUktT3JnYW5pemF0aW9uXCI6IGFwcHJvdmFsIS5vcmdhbml6YXRpb25JZCxcbiAgICAgICAgICAgIFwiT3BlbkFJLVByb2plY3RcIjogYXBwcm92YWwhLnByb2plY3RJZCxcbiAgICAgICAgICB9LFxuICAgICAgICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KFxuICAgICAgICAgICAgYnVpbGRSb3N0ZXJSZXNwb25zZXNSZXF1ZXN0KFxuICAgICAgICAgICAgICBtb2RlbCEsXG4gICAgICAgICAgICAgIHNvdXJjZS5raW5kIGFzIFwicGRmXCIgfCBcImltYWdlXCIsXG4gICAgICAgICAgICAgIHNvdXJjZS5maWxlbmFtZSEsXG4gICAgICAgICAgICAgIHNvdXJjZS5taW1lLFxuICAgICAgICAgICAgICBzb3VyY2UuYmFzZTY0ISxcbiAgICAgICAgICAgICksXG4gICAgICAgICAgKSxcbiAgICAgICAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoNjBfMDAwKSxcbiAgICAgICAgICByZWRpcmVjdDogXCJlcnJvclwiLFxuICAgICAgICB9O1xuICAgICAgICAvLyBTb3VyY2UgQUNLIGFuZCBkZWNvZGVyIGF3YWl0cyBoYXZlIHNldHRsZWQuIFJlY2hlY2sgdGhlIHNhbWUgYXBwcm92YWwsXG4gICAgICAgIC8vIHJhdyBjb25maWd1cmF0aW9uIGFuZCBjdXJyZW50IHdpbmRvdyBkaXJlY3RseSBiZWZvcmUgdGhlIGZldGNoLlxuICAgICAgICBhc3NlcnRSb3N0ZXJBaURpc3BhdGNoQXBwcm92YWwoY29uZmlnLCBhcHByb3ZhbCEsIGRlcHMuY29uZmlndXJhdGlvbigpKTtcbiAgICAgICAgbGV0IHJlc3BvbnNlOiBSZXNwb25zZTtcbiAgICAgICAgLy8gT25jZSBhIHByb3ZpZGVyIHJlcXVlc3QgY2FuIGxlYXZlIHRoaXMgcHJvY2VzcywgYW4gZXJyb3IgZG9lcyBub3RcbiAgICAgICAgLy8gcHJvdmUgaXQgd2FzIHVuYmlsbGVkL3N0b3BwZWQuIEtlZXAgaXRzIGFjdGl2ZSBsZWFzZSBhbmQgZnVsbCBjaGFyZ2UuXG4gICAgICAgIGJ1ZGdldE91dGNvbWUgPSBcImFtYmlndW91c1wiO1xuICAgICAgICB0cnkge1xuICAgICAgICAgIHJlc3BvbnNlID0gYXdhaXQgKGRlcHMuZmV0Y2ggPz8gZmV0Y2gpKFxuICAgICAgICAgICAgUk9TVEVSX09QRU5BSV9SRVNQT05TRVNfRU5EUE9JTlQsXG4gICAgICAgICAgICBpbml0LFxuICAgICAgICAgICk7XG4gICAgICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFxuICAgICAgICAgICAgZXJyb3IgaW5zdGFuY2VvZiBET01FeGNlcHRpb24gJiZcbiAgICAgICAgICAgICAgW1wiVGltZW91dEVycm9yXCIsIFwiQWJvcnRFcnJvclwiXS5pbmNsdWRlcyhlcnJvci5uYW1lKVxuICAgICAgICAgICAgICA/IFwicm9zdGVyX2V4dHJhY3Rpb25fdGltZW91dFwiXG4gICAgICAgICAgICAgIDogXCJyb3N0ZXJfZXh0cmFjdGlvbl9mYWlsZWRcIixcbiAgICAgICAgICAgIDUwMixcbiAgICAgICAgICApO1xuICAgICAgICB9XG4gICAgICAgIGlmICghcmVzcG9uc2Uub2spIHtcbiAgICAgICAgICB0cnkge1xuICAgICAgICAgICAgYXdhaXQgcmVzcG9uc2UuYm9keT8uY2FuY2VsKCk7XG4gICAgICAgICAgfSBjYXRjaCB7IC8qIE5vIHByb3ZpZGVyIGJvZHkgaXMgZXhwb3NlZC4gKi8gfVxuICAgICAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJvc3Rlcl9leHRyYWN0aW9uX2ZhaWxlZFwiLCA1MDIpO1xuICAgICAgICB9XG4gICAgICAgIGxldCByYXc6IHN0cmluZywgZGF0YTogdW5rbm93bjtcbiAgICAgICAgdHJ5IHtcbiAgICAgICAgICByYXcgPSBhd2FpdCBib3VuZGVkQm9keShyZXNwb25zZSwgTUFYX1JPU1RFUl9QUk9WSURFUl9CWVRFUyk7XG4gICAgICAgICAgZGF0YSA9IEpTT04ucGFyc2UocmF3KTtcbiAgICAgICAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXG4gICAgICAgICAgICBlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yICYmIGVycm9yLmNvZGUgPT09IFwicGF5bG9hZF90b29fbGFyZ2VcIlxuICAgICAgICAgICAgICA/IFwicm9zdGVyX3Byb3ZpZGVyX3Jlc3BvbnNlX3Rvb19sYXJnZVwiXG4gICAgICAgICAgICAgIDogZXJyb3IgaW5zdGFuY2VvZiBET01FeGNlcHRpb24gJiZcbiAgICAgICAgICAgICAgICAgIFtcIlRpbWVvdXRFcnJvclwiLCBcIkFib3J0RXJyb3JcIl0uaW5jbHVkZXMoZXJyb3IubmFtZSlcbiAgICAgICAgICAgICAgPyBcInJvc3Rlcl9leHRyYWN0aW9uX3RpbWVvdXRcIlxuICAgICAgICAgICAgICA6IFwicm9zdGVyX3Byb3ZpZGVyX3Jlc3BvbnNlX2ludmFsaWRcIixcbiAgICAgICAgICAgIDUwMixcbiAgICAgICAgICApO1xuICAgICAgICB9XG4gICAgICAgIGNhbmRpZGF0ZXMgPSByb3N0ZXJSZXNwb25zZUNhbmRpZGF0ZXMoZGF0YSk7XG4gICAgICAgIHJlc3BvbnNlSWQgPSBwcm92aWRlcklkZW50aWZpZXIoXG4gICAgICAgICAgKGRhdGEgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pLmlkLFxuICAgICAgICAgIDI1NixcbiAgICAgICAgKTtcbiAgICAgICAgcmVzcG9uc2VIYXNoID0gYXdhaXQgcm9zdGVyU2hhMjU2KGVuY29kZXIuZW5jb2RlKHJhdykpO1xuICAgICAgfSBlbHNlIHtcbiAgICAgICAgdHJ5IHtcbiAgICAgICAgICBjYW5kaWRhdGVzID0gcGFyc2VSb3N0ZXJUZXh0KHNvdXJjZS5jb250ZW50ISk7XG4gICAgICAgICAgaWYgKFxuICAgICAgICAgICAgY2FuZGlkYXRlcy5sZW5ndGggPiA1MDAgfHxcbiAgICAgICAgICAgIGNhbmRpZGF0ZXMuc29tZSgocm93KSA9PlxuICAgICAgICAgICAgICByb3cuc291cmNlX3JvdyA+IDIxNDc0ODM2NDcgfHxcbiAgICAgICAgICAgICAgWy4uLnJvdy5tZW1iZXJfbmFtZV0ubGVuZ3RoID4gNDgwIHx8XG4gICAgICAgICAgICAgIFsuLi5yb3cubW9tb19uYW1lXS5sZW5ndGggPiA0ODAgfHxcbiAgICAgICAgICAgICAgWy4uLnJvdy5tb21vX251bWJlcl0ubGVuZ3RoID4gMzIgfHxcbiAgICAgICAgICAgICAgW3Jvdy5tZW1iZXJfbmFtZSwgcm93Lm1vbW9fbmFtZSwgcm93Lm1vbW9fbnVtYmVyXS5zb21lKCh2YWx1ZSkgPT5cbiAgICAgICAgICAgICAgICB2YWx1ZS5pbmNsdWRlcyhcIlxcdTAwMDBcIilcbiAgICAgICAgICAgICAgKVxuICAgICAgICAgICAgKVxuICAgICAgICAgICkgdGhyb3cgbmV3IEVycm9yKFwiQ2FuZGlkYXRlIGxpbWl0cyBleGNlZWRlZFwiKTtcbiAgICAgICAgfSBjYXRjaCB7XG4gICAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX3ByZXZpZXdfaW52YWxpZFwiKTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgICAgaWYgKGNhbmRpZGF0ZXMuc29tZSgocm93KSA9PiByb3cuc291cmNlX3JvdyA+IDIxNDc0ODM2NDcpKSB7XG4gICAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJvc3Rlcl9wcm92aWRlcl9yZXNwb25zZV9pbnZhbGlkXCIsIDUwMik7XG4gICAgICB9XG4gICAgICBpZiAocm9zdGVyQ2FuZGlkYXRlSnNvbmJCeXRlcyhjYW5kaWRhdGVzKSA+IDUxMl8wMDApIHtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFxuICAgICAgICAgIHNvdXJjZS5haVxuICAgICAgICAgICAgPyBcInJvc3Rlcl9wcm92aWRlcl9yZXNwb25zZV90b29fbGFyZ2VcIlxuICAgICAgICAgICAgOiBcInJvc3Rlcl9wcmV2aWV3X2ludmFsaWRcIixcbiAgICAgICAgICBzb3VyY2UuYWkgPyA1MDIgOiA0MDAsXG4gICAgICAgICk7XG4gICAgICB9XG4gICAgICBjb21wbGV0aW9uQXR0ZW1wdGVkID0gdHJ1ZTtcbiAgICAgIGxldCBjb21wbGV0ZWQ6IHVua25vd247XG4gICAgICB0cnkge1xuICAgICAgICBjb21wbGV0ZWQgPSBhd2FpdCBycGMoZGVwcywgXCJjb21wbGV0ZV9yb3N0ZXJfaW1wb3J0X3ByZXZpZXdcIiwge1xuICAgICAgICAgIHBfaW1wb3J0X2lkOiBzb3VyY2VJZCxcbiAgICAgICAgICBwX2FjdG9yX2lkOiBhY3RvcklkLFxuICAgICAgICAgIHBfc2Vzc2lvbl9pZDogc2Vzc2lvbklkLFxuICAgICAgICAgIHBfY2FuZGlkYXRlczogY2FuZGlkYXRlcyxcbiAgICAgICAgICBwX3Byb2Nlc3NpbmdfbWV0YWRhdGE6IHtcbiAgICAgICAgICAgIHByb2Nlc3NpbmdfbWV0aG9kOiBzb3VyY2UuYWlcbiAgICAgICAgICAgICAgPyBcIm9wZW5haV9zdHJ1Y3R1cmVkX2V4dHJhY3Rpb25cIlxuICAgICAgICAgICAgICA6IFwiZGV0ZXJtaW5pc3RpY1wiLFxuICAgICAgICAgICAgcHJvdmlkZXJfcmVzcG9uc2Vfc2hhMjU2OiByZXNwb25zZUhhc2gsXG4gICAgICAgICAgICBwcm92aWRlcl9yZXNwb25zZV9pZDogcmVzcG9uc2VJZCxcbiAgICAgICAgICB9LFxuICAgICAgICB9KTtcbiAgICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICAgIGlmIChcbiAgICAgICAgICBlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yICYmXG4gICAgICAgICAgZXJyb3IuY29kZSA9PT0gXCJyb3N0ZXJfcHJldmlld19pbnZhbGlkXCJcbiAgICAgICAgKSBjb21wbGV0aW9uQXR0ZW1wdGVkID0gZmFsc2U7XG4gICAgICAgIHRocm93IGVycm9yO1xuICAgICAgfVxuICAgICAgY29uc3QgdmFsaWRhdGVkID0gcHJldmlld1JlY2VpcHQoXG4gICAgICAgIGNvbXBsZXRlZCxcbiAgICAgICAgc291cmNlLFxuICAgICAgICBoYXNoLFxuICAgICAgICBzb3VyY2VJZCxcbiAgICAgICAgZGVyaXZlZEhhc2gsXG4gICAgICAgIHJlZ2lzdGVyZWQuZXh0cmFjdGlvbl9pZCxcbiAgICAgICAgbW9kZWwsXG4gICAgICApO1xuICAgICAgYnVkZ2V0T3V0Y29tZSA9IFwicHJldmlld19yZWFkeVwiO1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh2YWxpZGF0ZWQpO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICBpZiAoc291cmNlSWQgJiYgYWN0b3JJZCAmJiBzZXNzaW9uSWQgJiYgIWNvbXBsZXRpb25BdHRlbXB0ZWQpIHtcbiAgICAgICAgY29uc3QgY29kZSA9XG4gICAgICAgICAgZXJyb3IgaW5zdGFuY2VvZiBQdWJsaWNFcnJvciAmJiBmYWlsdXJlQ29kZXMuaGFzKGVycm9yLmNvZGUpXG4gICAgICAgICAgICA/IGVycm9yLmNvZGVcbiAgICAgICAgICAgIDogXCJyb3N0ZXJfZXh0cmFjdGlvbl9mYWlsZWRcIjtcbiAgICAgICAgdHJ5IHtcbiAgICAgICAgICBjb25zdCBmYWlsZWQgPSByZWNvcmQoXG4gICAgICAgICAgICBhd2FpdCBycGMoZGVwcywgXCJmYWlsX3Jvc3Rlcl9pbXBvcnRfcHJldmlld1wiLCB7XG4gICAgICAgICAgICAgIHBfaW1wb3J0X2lkOiBzb3VyY2VJZCxcbiAgICAgICAgICAgICAgcF9hY3Rvcl9pZDogYWN0b3JJZCxcbiAgICAgICAgICAgICAgcF9zZXNzaW9uX2lkOiBzZXNzaW9uSWQsXG4gICAgICAgICAgICAgIHBfZXJyb3JfY29kZTogY29kZSxcbiAgICAgICAgICAgIH0pLFxuICAgICAgICAgICk7XG4gICAgICAgICAgZXhhY3QoZmFpbGVkLCBbXG4gICAgICAgICAgICBcImNvbnRyYWN0X3ZlcnNpb25cIixcbiAgICAgICAgICAgIFwib2tcIixcbiAgICAgICAgICAgIFwiaW1wb3J0X2lkXCIsXG4gICAgICAgICAgICBcInN0YXRlXCIsXG4gICAgICAgICAgICBcImVycm9yX2NvZGVcIixcbiAgICAgICAgICAgIFwicmVwbGF5ZWRcIixcbiAgICAgICAgICBdKTtcbiAgICAgICAgICBpZiAoXG4gICAgICAgICAgICBmYWlsZWQuY29udHJhY3RfdmVyc2lvbiAhPT0gMSB8fCBmYWlsZWQub2sgIT09IHRydWUgfHxcbiAgICAgICAgICAgIGZhaWxlZC5pbXBvcnRfaWQgIT09IHNvdXJjZUlkIHx8IGZhaWxlZC5zdGF0ZSAhPT0gXCJmYWlsZWRcIiB8fFxuICAgICAgICAgICAgZmFpbGVkLmVycm9yX2NvZGUgIT09IGNvZGUgfHwgdHlwZW9mIGZhaWxlZC5yZXBsYXllZCAhPT0gXCJib29sZWFuXCJcbiAgICAgICAgICApIHJlY2VpcHRFcnJvcigpO1xuICAgICAgICB9IGNhdGNoIHtcbiAgICAgICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IFwicm9zdGVyX3JlY2VpcHRfdW5hdmFpbGFibGVcIiB9LCA1MDMpO1xuICAgICAgICB9XG4gICAgICB9XG4gICAgICBjb25zdCBmYWlsdXJlID0gcHVibGljRmFpbHVyZShlcnJvcik7XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IGZhaWx1cmUuZXJyb3IgfSwgZmFpbHVyZS5zdGF0dXMpO1xuICAgIH0gZmluYWxseSB7XG4gICAgICBpZiAocmVzZXJ2YXRpb25JZCAmJiBhY3RvcklkICYmIHNlc3Npb25JZCkge1xuICAgICAgICAvLyBEdXJhYmxlIHJlY2VpcHQgb3V0Y29tZXMgcmVtYWluIGF1dGhvcml0YXRpdmUgZXZlbiBpZiB0aGlzIGNsZWFudXBcbiAgICAgICAgLy8gQUNLIGlzIGxvc3QuIHJlc2VydmVfcm9zdGVyX3Jlc291cmNlcyByZXBhaXJzIGZyb20gaW1tdXRhYmxlIHJlc3VsdHMuXG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgY29uc3QgZmluaXNoZWQgPSByZWNvcmQoXG4gICAgICAgICAgICBhd2FpdCBycGMoZGVwcywgXCJmaW5pc2hfcm9zdGVyX3Jlc291cmNlc1wiLCB7XG4gICAgICAgICAgICAgIHBfcmVzZXJ2YXRpb25faWQ6IHJlc2VydmF0aW9uSWQsXG4gICAgICAgICAgICAgIHBfYWN0b3JfaWQ6IGFjdG9ySWQsXG4gICAgICAgICAgICAgIHBfc2Vzc2lvbl9pZDogc2Vzc2lvbklkLFxuICAgICAgICAgICAgICBwX291dGNvbWU6IGJ1ZGdldE91dGNvbWUsXG4gICAgICAgICAgICB9KSxcbiAgICAgICAgICApO1xuICAgICAgICAgIGV4YWN0KGZpbmlzaGVkLCBbXG4gICAgICAgICAgICBcImNvbnRyYWN0X3ZlcnNpb25cIixcbiAgICAgICAgICAgIFwib2tcIixcbiAgICAgICAgICAgIFwicmVzZXJ2YXRpb25faWRcIixcbiAgICAgICAgICAgIFwib3V0Y29tZVwiLFxuICAgICAgICAgICAgXCJjaGFyZ2VkXCIsXG4gICAgICAgICAgXSk7XG4gICAgICAgICAgaWYgKFxuICAgICAgICAgICAgZmluaXNoZWQuY29udHJhY3RfdmVyc2lvbiAhPT0gMSB8fCBmaW5pc2hlZC5vayAhPT0gdHJ1ZSB8fFxuICAgICAgICAgICAgZmluaXNoZWQucmVzZXJ2YXRpb25faWQgIT09IHJlc2VydmF0aW9uSWQgfHxcbiAgICAgICAgICAgIGZpbmlzaGVkLm91dGNvbWUgIT09IGJ1ZGdldE91dGNvbWUgfHwgZmluaXNoZWQuY2hhcmdlZCAhPT0gdHJ1ZVxuICAgICAgICAgICkgcmVjZWlwdEVycm9yKCk7XG4gICAgICAgIH0gY2F0Y2ggeyAvKiBOZXZlciByZXRyeSBkZWNvZGVyL3Byb3ZpZGVyIG9yIHJlZnVuZCB1bmNlcnRhaW4gd29yay4gKi8gfVxuICAgICAgfVxuICAgIH1cbiAgfTtcbn1cbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUNFLFdBQVcsRUFDWCxXQUFXLEVBQ1gsV0FBVyxFQUNYLFdBQVcsRUFDWCxhQUFhLEVBQ2IsTUFBTSxFQUNOLElBQUksRUFDSixZQUFZLFFBQ1Asb0NBQW9DO0FBQzNDLFNBQVMsV0FBVyxFQUFFLFlBQVksUUFBUSxxQkFBcUI7QUFDL0QsU0FDRSx3QkFBd0IsRUFDeEIsZ0JBQWdCLEVBQ2hCLGlCQUFpQixFQUNqQixxQkFBcUIsRUFDckIseUJBQXlCLEVBQ3pCLGFBQWEsRUFDYixZQUFZLFFBRVAsa0NBQWtDO0FBQ3pDLFNBQ0UsZUFBZSxRQUVWLDhCQUE4QjtBQUNyQyxTQUFTLDJCQUEyQixRQUFRLDhCQUE4QjtBQUMxRSxTQUNFLHlCQUF5QixFQUN6Qix3QkFBd0IsUUFDbkIsdUNBQXVDO0FBQzlDLFNBQVMsa0JBQWtCLFFBQVEsK0JBQStCO0FBQ2xFLFNBQVMsbUJBQW1CLFFBQVEsdUNBQXVDO0FBQzNFLFNBQ0UsOEJBQThCLEVBQzlCLCtCQUErQixFQUMvQixnQ0FBZ0MsRUFHaEMsNkJBQTZCLFFBQ3hCLDBDQUEwQztBQWFqRCxNQUFNLFVBQVUsSUFBSTtBQUNwQixNQUFNLGVBQWUsSUFBSSxJQUFJO0VBQzNCO0VBQ0E7RUFDQTtFQUNBO0VBQ0E7RUFDQTtFQUNBO0VBQ0E7Q0FDRDtBQUNELFNBQVM7RUFDUCxNQUFNLElBQUksWUFBWSwwQkFBMEI7QUFDbEQ7QUFDQSxTQUFTLFdBQVcsS0FBYztFQUNoQyxJQUFJO0lBQ0YsT0FBTyxLQUFLLE9BQU87RUFDckIsRUFBRSxPQUFNO0lBQ04sT0FBTztFQUNUO0FBQ0Y7QUFDQSxTQUFTLE9BQU8sS0FBYztFQUM1QixJQUFJO0lBQ0YsT0FBTyxZQUFZO0VBQ3JCLEVBQUUsT0FBTTtJQUNOLE9BQU87RUFDVDtBQUNGO0FBQ0EsU0FBUyxNQUFNLEtBQThCLEVBQUUsTUFBZ0I7RUFDN0QsSUFDRSxPQUFPLElBQUksQ0FBQyxPQUFPLE1BQU0sS0FBSyxPQUFPLE1BQU0sSUFDM0MsT0FBTyxJQUFJLENBQUMsQ0FBQyxNQUFRLENBQUMsQ0FBQyxPQUFPLEtBQUssSUFDbkM7QUFDSjtBQUNBLFNBQVMsT0FBTyxLQUFjO0VBQzVCLElBQUksT0FBTyxVQUFVLFlBQVksQ0FBQyxPQUFPLElBQUksQ0FBQyxRQUFRO0VBQ3RELE9BQU87QUFDVDtBQUNBLFNBQVMsT0FBTyxLQUFjO0VBQzVCLElBQUk7RUFDSixJQUFJO0lBQ0YsU0FBUyxhQUFhO0VBQ3hCLEVBQUUsT0FBTTtJQUNOO0VBQ0Y7RUFDQSxJQUFJLFdBQVcsTUFBTTtFQUNyQixJQUFJLEtBQUssS0FBSyxDQUFDLFdBQVcsS0FBSyxHQUFHLElBQUk7SUFDcEMsTUFBTSxJQUFJLFlBQVkseUJBQXlCO0VBQ2pEO0FBQ0Y7QUFDQSxTQUFTLG1CQUFtQixLQUFjLEVBQUUsR0FBVztFQUNyRCxJQUNFLE9BQU8sVUFBVSxZQUNqQixDQUFDLElBQUksT0FBTyxDQUFDLCtCQUErQixFQUFFLE1BQU0sRUFBRSxFQUFFLENBQUMsRUFBRSxJQUFJLENBQUMsUUFDaEUsTUFBTSxJQUFJLFlBQVksb0NBQW9DO0VBQzVELE9BQU87QUFDVDtBQUNBLFNBQVMsZUFDUCxLQUFjLEVBQ2QsTUFBb0IsRUFDcEIsSUFBWSxFQUNaLFFBQWdCLEVBQ2hCLFdBQTBCLEVBQzFCLFlBQXFCLEVBQ3JCLGFBQTRCO0VBRTVCLE1BQU0sSUFBSSxPQUFPO0VBQ2pCLE1BQU0sR0FBRztJQUNQO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7R0FDRDtFQUNELElBQ0UsRUFBRSxnQkFBZ0IsS0FBSyxLQUFLLEVBQUUsRUFBRSxLQUFLLFFBQVEsRUFBRSxTQUFTLEtBQUssWUFDN0QsRUFBRSxhQUFhLEtBQUssUUFBUSxFQUFFLFdBQVcsS0FBSyxPQUFPLElBQUksSUFDekQsRUFBRSxrQkFBa0IsS0FBSyxRQUFRLEVBQUUsZUFBZSxLQUFLLEtBQ3ZELEVBQUUsVUFBVSxLQUFLLFNBQVMsRUFBRSxxQkFBcUIsS0FBSyxRQUN0RCxFQUFFLGlCQUFpQixLQUNqQixDQUFDLE9BQU8sRUFBRSxHQUFHLGlDQUFpQyxlQUFlLEdBQy9EO0VBQ0YsTUFBTSxhQUFhLE9BQU8sRUFBRSxjQUFjO0VBQzFDLE1BQU0sWUFBWTtJQUNoQjtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7R0FDRDtFQUNELElBQ0UsV0FBVyxVQUFVLEtBQUssT0FBTyxTQUFTLElBQzFDLFdBQVcsV0FBVyxLQUFLLE9BQU8sS0FBSyxDQUFDLE1BQU0sSUFDOUMsV0FBVyxlQUFlLEtBQUssT0FBTyxRQUFRLElBQzlDLFdBQVcsYUFBYSxLQUFLLE9BQU8sSUFBSSxJQUN4QyxXQUFXLGFBQWEsS0FBSyxPQUFPLFFBQVEsSUFDNUMsV0FBVyxjQUFjLEtBQUssZUFDOUIsV0FBVyxpQkFBaUIsS0FDMUIsQ0FBQyxPQUFPLElBQUksS0FBSyxTQUFTLHVCQUF1QixJQUFJLEtBQ3ZELFdBQVcsYUFBYSxLQUFLLGdCQUM3QixXQUFXLFVBQVUsS0FBSyxPQUFPLEVBQUUsSUFDbkMsV0FBVyxlQUFlLEtBQUssQ0FBQyxPQUFPLEVBQUUsR0FBRyxvQkFBb0IsSUFBSSxLQUNwRSxXQUFXLGNBQWMsS0FBSyw4QkFDOUIsV0FBVyxjQUFjLEtBQUssNEJBQzlCLEVBQUUsS0FBSyxLQUFLLGVBQ1o7RUFDRixXQUFXLEVBQUUsV0FBVztFQUN4QixPQUFPLEVBQUUsb0JBQW9CO0VBQzdCLE9BQU8sRUFBRSxVQUFVO0VBQ25CLElBQUksT0FBTyxFQUFFLEVBQUU7SUFDYixJQUFJO01BQ0YsbUJBQW1CLEVBQUUsS0FBSyxFQUFFO0lBQzlCLEVBQUUsT0FBTTtNQUNOO0lBQ0Y7RUFDRixPQUFPLElBQUksRUFBRSxLQUFLLEtBQUssTUFBTTtFQUM3QixJQUNFLENBQUMsTUFBTSxPQUFPLENBQUMsRUFBRSxJQUFJLEtBQUssRUFBRSxJQUFJLENBQUMsTUFBTSxHQUFHLEtBQUssRUFBRSxJQUFJLENBQUMsTUFBTSxHQUFHLE9BQy9ELENBQUMsTUFBTSxPQUFPLENBQUMsRUFBRSxlQUFlLEdBQ2hDO0VBQ0YsSUFBSSxRQUFRO0VBQ1osS0FBSyxNQUFNLFNBQVMsRUFBRSxJQUFJLENBQUU7SUFDMUIsTUFBTSxNQUFNLE9BQU87SUFDbkIsTUFBTSxLQUFLO01BQ1Q7TUFDQTtNQUNBO01BQ0E7TUFDQTtNQUNBO01BQ0E7S0FDRDtJQUNELElBQ0UsQ0FBQyxPQUFPLGFBQWEsQ0FBQyxJQUFJLFVBQVUsS0FBSyxPQUFPLElBQUksVUFBVSxJQUFJLEtBQ2xFLE9BQU8sSUFBSSxVQUFVLElBQUksY0FDekIsT0FBTyxJQUFJLFVBQVUsS0FBSyxZQUFZLENBQUMsT0FBTyxRQUFRLENBQUMsSUFBSSxVQUFVLEtBQ3JFLElBQUksVUFBVSxHQUFHLEtBQUssSUFBSSxVQUFVLEdBQUcsS0FDdkMsT0FBTyxJQUFJLEtBQUssS0FBSyxhQUFhLENBQUMsTUFBTSxPQUFPLENBQUMsSUFBSSxNQUFNLEtBQzNELElBQUksTUFBTSxDQUFDLE1BQU0sR0FBRyxNQUFNLElBQUksTUFBTSxDQUFDLElBQUksQ0FBQyxDQUFDLElBQ3pDLE9BQU8sTUFBTSxZQUFZLEVBQUUsTUFBTSxHQUFHLE1BRXRDO0lBQ0YsS0FBSyxNQUFNLE9BQU87TUFBQztNQUFlO01BQWE7S0FBYyxDQUFFO01BQzdELElBQ0UsT0FBTyxHQUFHLENBQUMsSUFBSSxLQUFLLFlBQ3BCO1dBQUssR0FBRyxDQUFDLElBQUk7T0FBWSxDQUFDLE1BQU0sR0FBRyxDQUFDLFFBQVEsZ0JBQWdCLEtBQUssR0FBRyxHQUNwRTtJQUNKO0lBQ0EsSUFBSSxJQUFJLEtBQUssRUFBRTtNQUNiO01BQ0EsSUFBSSxJQUFJLE1BQU0sQ0FBQyxNQUFNLEVBQUU7SUFDekI7RUFDRjtFQUNBLElBQ0UsRUFBRSxTQUFTLEtBQUssRUFBRSxJQUFJLENBQUMsTUFBTSxJQUFJLEVBQUUsV0FBVyxLQUFLLFNBQ25ELEVBQUUsV0FBVyxLQUFLLEVBQUUsSUFBSSxDQUFDLE1BQU0sR0FBRyxTQUNsQyxFQUFFLGVBQWUsQ0FBQyxNQUFNLEtBQUssT0FDN0I7RUFDRixNQUFNLFlBQVksRUFBRSxJQUFJLENBQUMsTUFBTSxDQUFDLENBQUMsTUFBUSxJQUFJLEtBQUs7RUFDbEQsS0FBSyxNQUFNLENBQUMsT0FBTyxNQUFNLElBQUksRUFBRSxlQUFlLENBQUMsT0FBTyxHQUFJO0lBQ3hELE1BQU0sTUFBTSxPQUFPO0lBQ25CLE1BQU0sS0FBSztNQUFDO01BQWU7TUFBYTtLQUFjO0lBQ3RELEtBQUssTUFBTSxPQUFPLE9BQU8sSUFBSSxDQUFDLEtBQU07TUFDbEMsSUFBSSxPQUFPLEdBQUcsQ0FBQyxJQUFJLEtBQUssWUFBWSxHQUFHLENBQUMsSUFBSSxLQUFLLFNBQVMsQ0FBQyxNQUFNLENBQUMsSUFBSSxFQUFFO1FBQ3RFO01BQ0Y7SUFDRjtFQUNGO0VBQ0EsT0FBTztBQUNUO0FBQ0EsZUFBZSxJQUNiLElBQStCLEVBQy9CLElBQVksRUFDWixJQUE2QjtFQUU3QixJQUFJO0VBQ0osSUFBSTtJQUNGLFNBQVMsTUFBTSxLQUFLLEdBQUcsQ0FBQyxNQUFNO0VBQ2hDLEVBQUUsT0FBTTtJQUNOLE1BQU0sSUFBSSxZQUFZLDhCQUE4QjtFQUN0RDtFQUNBLElBQUksT0FBTyxLQUFLLEVBQUU7SUFDaEIsTUFBTSxPQUFPLE9BQU8sS0FBSyxDQUFDLE9BQU87SUFDakMsSUFBSSxTQUFTLHVCQUF1QixNQUFNLElBQUksWUFBWSxNQUFNO0lBQ2hFLElBQUksU0FBUyx5QkFBeUIsTUFBTSxJQUFJLFlBQVksTUFBTTtJQUNsRSxJQUFJLFNBQVMsK0JBQStCO01BQzFDLE1BQU0sSUFBSSxZQUFZLE1BQU07SUFDOUI7SUFDQSwwRUFBMEU7SUFDMUUsSUFDRSxTQUFTLG9DQUFvQyxPQUFPLEtBQUssQ0FBQyxJQUFJLEtBQUssU0FDbkU7TUFDQSxNQUFNLElBQUksWUFBWTtJQUN4QjtJQUNBLElBQUksU0FBUyw2QkFBNkIsTUFBTSxJQUFJLFlBQVksTUFBTTtJQUN0RSxJQUNFLFNBQVMsNkJBQTZCLFNBQVMseUJBQy9DLE1BQU0sSUFBSSxZQUFZLE1BQU07SUFDOUIsSUFBSSxPQUFPLEtBQUssQ0FBQyxJQUFJLEtBQUssU0FBUztNQUNqQyxNQUFNLElBQUksWUFBWSwyQkFBMkI7SUFDbkQ7SUFDQSxNQUFNLElBQUksWUFBWSw4QkFBOEI7RUFDdEQ7RUFDQSxPQUFPLE9BQU8sSUFBSTtBQUNwQjtBQUNBLE9BQU8sU0FBUywwQkFDZCxJQUErQjtFQUUvQixPQUFPLE9BQU87SUFDWixJQUFJLFFBQVEsTUFBTSxLQUFLLFdBQVc7TUFDaEMsT0FBTyxJQUFJLFNBQVMsTUFBTTtRQUFFLFNBQVM7TUFBWTtJQUNuRDtJQUNBLElBQUksUUFBUSxNQUFNLEtBQUssUUFBUTtNQUM3QixPQUFPLGFBQWE7UUFBRSxPQUFPO01BQXFCLEdBQUc7SUFDdkQ7SUFDQSxJQUFJLFdBQTBCLE1BQzVCLFVBQXlCLE1BQ3pCLFlBQTJCLE1BQzNCLHNCQUFzQixPQUN0QixnQkFBK0IsTUFDL0IsZ0JBQTBEO0lBQzVELElBQUk7TUFDRixNQUFNLGdCQUFnQixRQUFRLE9BQU8sQ0FBQyxHQUFHLENBQUM7TUFDMUMsdUVBQXVFO01BQ3ZFLE1BQU0sT0FBTyxNQUFNLEtBQUssWUFBWSxDQUFDO01BQ3JDLENBQUMsRUFBRSxPQUFPLEVBQUUsU0FBUyxFQUFFLEdBQUcsY0FBYyxlQUFlLEtBQUssRUFBRSxDQUFDO01BQy9ELE1BQU0sU0FBUyxpQkFDYixNQUFNLFlBQVksU0FBUztNQUU3QixNQUFNLE9BQU8sTUFBTSxhQUFhLE9BQU8sS0FBSztNQUM1QyxNQUFNLGNBQWMsT0FBTyxPQUFPLEdBQzlCLE1BQU0sYUFBYSxPQUFPLE9BQU8sSUFDakM7TUFDSixNQUFNLFNBQVMsOEJBQThCLEtBQUssYUFBYTtNQUMvRCxJQUFJLFdBQTRDO01BQ2hELElBQUksUUFBdUI7TUFDM0IsSUFBSSxPQUFPLEVBQUUsRUFBRTtRQUNiLElBQUk7VUFDRixRQUFRLG1CQUFtQixPQUFPLEtBQUssRUFBRTtRQUMzQyxFQUFFLE9BQU07VUFDTixNQUFNLElBQUksWUFBWSxpQ0FBaUM7UUFDekQ7UUFDQSxXQUFXLE1BQU0sZ0NBQWdDO1FBQ2pELHdFQUF3RTtRQUN4RSxtRUFBbUU7UUFDbkUsK0JBQStCLFFBQVEsVUFBVSxLQUFLLGFBQWE7TUFDckU7TUFDQSxNQUFNLFNBQVMsb0JBQ2IsTUFBTSxJQUFJLE1BQU0sNEJBQTRCO1FBQzFDLFlBQVk7UUFDWixjQUFjO1FBQ2QsY0FBYyxPQUFPLFNBQVM7UUFDOUIsaUJBQWlCO1FBQ2pCLGVBQWUsT0FBTyxJQUFJO1FBQzFCLGdCQUFnQixPQUFPLEtBQUssQ0FBQyxNQUFNO1FBQ25DLGtCQUFrQjtNQUNwQixJQUNBO1FBQUUsV0FBVyxPQUFPLFNBQVM7UUFBRTtRQUFTO1FBQVcsWUFBWTtNQUFLO01BRXRFLHlFQUF5RTtNQUN6RSx3RUFBd0U7TUFDeEUsSUFBSSxPQUFPLEtBQUssS0FBSyxZQUFZO1FBQy9CLGdCQUFnQixPQUFPLGNBQWM7UUFDckMsSUFBSTtVQUFDO1VBQVE7VUFBUztTQUFNLENBQUMsUUFBUSxDQUFDLE9BQU8sSUFBSSxHQUFHO1VBQ2xELElBQUksaUJBQWlCO1VBQ3JCLE1BQU0sZUFBeUMsV0FDM0MsQ0FBQyxPQUFPO1lBQ1IsSUFBSTtjQUNGLCtEQUErRDtjQUMvRCx3REFBd0Q7Y0FDeEQsK0JBQ0UsUUFDQSxVQUNBLEtBQUssYUFBYTtZQUV0QixFQUFFLE9BQU8sT0FBTztjQUNkLGlCQUFpQjtjQUNqQixNQUFNO1lBQ1I7WUFDQSxPQUFPLENBQUMsS0FBSyxZQUFZLElBQUksS0FBSyxFQUFFLE9BQU87VUFDN0MsSUFDRSxLQUFLLFlBQVk7VUFDckIsSUFBSTtVQUNKLElBQUk7WUFDRixVQUFVLE1BQU0sbUJBQ2QsUUFDQSxNQUNBLGVBQ0E7Y0FDRSxLQUFLLE9BQU8sVUFBVTtjQUN0QixRQUFRLE9BQU8sYUFBYTtjQUM1QixhQUFhLE9BQU8sa0JBQWtCO1lBQ3hDLEdBQ0E7VUFFSixFQUFFLE9BQU8sT0FBTztZQUNkLCtEQUErRDtZQUMvRCxtRUFBbUU7WUFDbkUsSUFBSSxnQkFBZ0I7Y0FDbEIsTUFBTSxJQUFJLFlBQVksaUNBQWlDO1lBQ3pEO1lBQ0EsTUFBTTtVQUNSO1VBQ0EsTUFBTSxXQUFXLE9BQ2YsTUFBTSxJQUFJLE1BQU0sa0NBQWtDO1lBQ2hELGtCQUFrQjtZQUNsQixZQUFZO1lBQ1osY0FBYztZQUNkLDBCQUEwQixRQUFRLGNBQWM7WUFDaEQsd0JBQXdCLFFBQVEsb0JBQW9CO1lBQ3BELGtCQUFrQixRQUFRLGNBQWM7WUFDeEMsYUFBYSxRQUFRLFNBQVM7WUFDOUIsV0FBVztjQUNULFFBQVEsUUFBUSxNQUFNO2NBQ3RCLE9BQU8sUUFBUSxLQUFLO2NBQ3BCLFFBQVEsUUFBUSxNQUFNO2NBQ3RCLGdCQUFnQixRQUFRLGNBQWM7WUFDeEM7VUFDRjtVQUVGLE1BQU0sVUFBVTtZQUNkO1lBQ0E7WUFDQTtZQUNBO1lBQ0E7WUFDQTtZQUNBO1dBQ0Q7VUFDRCxJQUNFLFNBQVMsZ0JBQWdCLEtBQUssS0FBSyxTQUFTLEVBQUUsS0FBSyxRQUNuRCxTQUFTLGNBQWMsS0FBSyxpQkFDNUIsU0FBUyxhQUFhLEtBQUssUUFDM0IsU0FBUyxjQUFjLEtBQUssZUFDNUIsU0FBUyxzQkFBc0IsS0FBSyxRQUFRLGNBQWMsSUFDMUQsU0FBUyxRQUFRLEtBQUssTUFDdEI7UUFDSjtNQUNGO01BQ0EsTUFBTSxhQUFhLE9BQ2pCLE1BQU0sSUFBSSxNQUFNLCtCQUErQjtRQUM3QyxZQUFZO1FBQ1osY0FBYztRQUNkLGNBQWMsT0FBTyxTQUFTO1FBQzlCLGVBQWUsT0FBTyxJQUFJO1FBQzFCLG1CQUFtQjtRQUNuQixpQkFBaUIsT0FBTyxLQUFLLENBQUMsTUFBTTtRQUNwQyxtQkFBbUIsT0FBTyxRQUFRO1FBQ2xDLGlCQUFpQixPQUFPLElBQUk7UUFDNUIsaUJBQWlCLE9BQU8sUUFBUTtRQUNoQyxrQkFBa0I7UUFDbEIsZ0JBQWdCLE9BQU8sT0FBTyxFQUFFLFVBQVU7UUFDMUMsY0FBYyxPQUFPLEVBQUU7UUFDdkIsbUJBQW1CLE9BQU8sRUFBRSxHQUFHLG9CQUFvQjtRQUNuRCxlQUFlLE9BQU8sRUFBRSxHQUNwQjtVQUNBLFVBQVU7VUFDVjtVQUNBLGdCQUFnQjtRQUNsQixJQUNFO01BQ047TUFFRixNQUFNLFlBQVk7UUFDaEI7UUFDQTtRQUNBO1FBQ0E7UUFDQTtRQUNBO1FBQ0E7UUFDQTtRQUNBO1FBQ0E7UUFDQTtRQUNBO1FBQ0E7UUFDQTtRQUNBO09BQ0Q7TUFDRCxJQUNFLFdBQVcsZ0JBQWdCLEtBQUssS0FBSyxXQUFXLEVBQUUsS0FBSyxRQUN2RCxXQUFXLFVBQVUsS0FBSyxPQUFPLFNBQVMsSUFDMUMsV0FBVyxhQUFhLEtBQUssUUFDN0IsV0FBVyxXQUFXLEtBQUssT0FBTyxLQUFLLENBQUMsTUFBTSxJQUM5QyxXQUFXLFdBQVcsS0FBSyxPQUFPLElBQUksSUFDdEMsV0FBVyxjQUFjLEtBQUssZUFDOUIsV0FBVyxpQkFBaUIsS0FDMUIsQ0FBQyxPQUFPLElBQUksS0FBSyxTQUFTLHVCQUF1QixJQUFJLEtBQ3ZELE9BQU8sV0FBVyxRQUFRLEtBQUssV0FDL0I7TUFDRixNQUFNLFdBQVcsV0FBVyxXQUFXLFNBQVM7TUFDaEQsT0FBTyxXQUFXLFVBQVU7TUFDNUIsSUFBSSxPQUFPLEVBQUUsRUFBRSxXQUFXLFdBQVcsYUFBYTtXQUM3QyxJQUFJLFdBQVcsYUFBYSxLQUFLLE1BQU07TUFDNUMsSUFDRSxXQUFXLEtBQUssS0FBSyxtQkFBbUIsV0FBVyxRQUFRLEtBQUssUUFDaEUsV0FBVyxVQUFVLEtBQUssTUFDMUI7UUFDQSxPQUFPLGFBQ0wsZUFDRSxXQUFXLGlCQUFpQixFQUM1QixRQUNBLE1BQ0EsVUFDQSxhQUNBLFdBQVcsYUFBYSxFQUN4QjtNQUdOO01BQ0EsSUFDRSxXQUFXLEtBQUssS0FBSyxZQUFZLFdBQVcsUUFBUSxLQUFLLFFBQ3pELFdBQVcsaUJBQWlCLEtBQUssUUFDakMsYUFBYSxHQUFHLENBQUMsT0FBTyxXQUFXLFVBQVUsSUFDN0MsTUFBTSxJQUFJLFlBQVksT0FBTyxXQUFXLFVBQVUsR0FBRztNQUN2RCxJQUNFLFdBQVcsS0FBSyxLQUFLLHNCQUNyQixXQUFXLFFBQVEsS0FBSyxTQUN4QixXQUFXLGlCQUFpQixLQUFLLFFBQVEsV0FBVyxVQUFVLEtBQUssTUFDbkU7TUFDRixJQUFJLE9BQU8sS0FBSyxLQUFLLFlBQVk7TUFDakMsV0FBVztNQUNYLElBQUksWUFDRixhQUE0QixNQUM1QixlQUE4QjtNQUNoQyxJQUFJLE9BQU8sRUFBRSxFQUFFO1FBQ2IsSUFBSSxDQUFDLE9BQU8sTUFBTSxFQUFFO1VBQ2xCLE1BQU0sSUFBSSxZQUFZLGlDQUFpQztRQUN6RDtRQUNBLE1BQU0sT0FBb0I7VUFDeEIsUUFBUTtVQUNSLFNBQVM7WUFDUCxlQUFlLENBQUMsT0FBTyxFQUFFLE9BQU8sTUFBTSxFQUFFO1lBQ3hDLGdCQUFnQjtZQUNoQix1QkFBdUIsU0FBVSxjQUFjO1lBQy9DLGtCQUFrQixTQUFVLFNBQVM7VUFDdkM7VUFDQSxNQUFNLEtBQUssU0FBUyxDQUNsQiw0QkFDRSxPQUNBLE9BQU8sSUFBSSxFQUNYLE9BQU8sUUFBUSxFQUNmLE9BQU8sSUFBSSxFQUNYLE9BQU8sTUFBTTtVQUdqQixRQUFRLFlBQVksT0FBTyxDQUFDO1VBQzVCLFVBQVU7UUFDWjtRQUNBLHlFQUF5RTtRQUN6RSxrRUFBa0U7UUFDbEUsK0JBQStCLFFBQVEsVUFBVyxLQUFLLGFBQWE7UUFDcEUsSUFBSTtRQUNKLG9FQUFvRTtRQUNwRSx3RUFBd0U7UUFDeEUsZ0JBQWdCO1FBQ2hCLElBQUk7VUFDRixXQUFXLE1BQU0sQ0FBQyxLQUFLLEtBQUssSUFBSSxLQUFLLEVBQ25DLGtDQUNBO1FBRUosRUFBRSxPQUFPLE9BQU87VUFDZCxNQUFNLElBQUksWUFDUixpQkFBaUIsZ0JBQ2Y7WUFBQztZQUFnQjtXQUFhLENBQUMsUUFBUSxDQUFDLE1BQU0sSUFBSSxJQUNoRCw4QkFDQSw0QkFDSjtRQUVKO1FBQ0EsSUFBSSxDQUFDLFNBQVMsRUFBRSxFQUFFO1VBQ2hCLElBQUk7WUFDRixNQUFNLFNBQVMsSUFBSSxFQUFFO1VBQ3ZCLEVBQUUsT0FBTSxDQUFxQztVQUM3QyxNQUFNLElBQUksWUFBWSw0QkFBNEI7UUFDcEQ7UUFDQSxJQUFJLEtBQWE7UUFDakIsSUFBSTtVQUNGLE1BQU0sTUFBTSxZQUFZLFVBQVU7VUFDbEMsT0FBTyxLQUFLLEtBQUssQ0FBQztRQUNwQixFQUFFLE9BQU8sT0FBTztVQUNkLE1BQU0sSUFBSSxZQUNSLGlCQUFpQixlQUFlLE1BQU0sSUFBSSxLQUFLLHNCQUMzQyx1Q0FDQSxpQkFBaUIsZ0JBQ2Y7WUFBQztZQUFnQjtXQUFhLENBQUMsUUFBUSxDQUFDLE1BQU0sSUFBSSxJQUNwRCw4QkFDQSxvQ0FDSjtRQUVKO1FBQ0EsYUFBYSx5QkFBeUI7UUFDdEMsYUFBYSxtQkFDWCxBQUFDLEtBQWlDLEVBQUUsRUFDcEM7UUFFRixlQUFlLE1BQU0sYUFBYSxRQUFRLE1BQU0sQ0FBQztNQUNuRCxPQUFPO1FBQ0wsSUFBSTtVQUNGLGFBQWEsZ0JBQWdCLE9BQU8sT0FBTztVQUMzQyxJQUNFLFdBQVcsTUFBTSxHQUFHLE9BQ3BCLFdBQVcsSUFBSSxDQUFDLENBQUMsTUFDZixJQUFJLFVBQVUsR0FBRyxjQUNqQjtpQkFBSSxJQUFJLFdBQVc7YUFBQyxDQUFDLE1BQU0sR0FBRyxPQUM5QjtpQkFBSSxJQUFJLFNBQVM7YUFBQyxDQUFDLE1BQU0sR0FBRyxPQUM1QjtpQkFBSSxJQUFJLFdBQVc7YUFBQyxDQUFDLE1BQU0sR0FBRyxNQUM5QjtjQUFDLElBQUksV0FBVztjQUFFLElBQUksU0FBUztjQUFFLElBQUksV0FBVzthQUFDLENBQUMsSUFBSSxDQUFDLENBQUMsUUFDdEQsTUFBTSxRQUFRLENBQUMsYUFHbkIsTUFBTSxJQUFJLE1BQU07UUFDcEIsRUFBRSxPQUFNO1VBQ04sTUFBTSxJQUFJLFlBQVk7UUFDeEI7TUFDRjtNQUNBLElBQUksV0FBVyxJQUFJLENBQUMsQ0FBQyxNQUFRLElBQUksVUFBVSxHQUFHLGFBQWE7UUFDekQsTUFBTSxJQUFJLFlBQVksb0NBQW9DO01BQzVEO01BQ0EsSUFBSSwwQkFBMEIsY0FBYyxTQUFTO1FBQ25ELE1BQU0sSUFBSSxZQUNSLE9BQU8sRUFBRSxHQUNMLHVDQUNBLDBCQUNKLE9BQU8sRUFBRSxHQUFHLE1BQU07TUFFdEI7TUFDQSxzQkFBc0I7TUFDdEIsSUFBSTtNQUNKLElBQUk7UUFDRixZQUFZLE1BQU0sSUFBSSxNQUFNLGtDQUFrQztVQUM1RCxhQUFhO1VBQ2IsWUFBWTtVQUNaLGNBQWM7VUFDZCxjQUFjO1VBQ2QsdUJBQXVCO1lBQ3JCLG1CQUFtQixPQUFPLEVBQUUsR0FDeEIsaUNBQ0E7WUFDSiwwQkFBMEI7WUFDMUIsc0JBQXNCO1VBQ3hCO1FBQ0Y7TUFDRixFQUFFLE9BQU8sT0FBTztRQUNkLElBQ0UsaUJBQWlCLGVBQ2pCLE1BQU0sSUFBSSxLQUFLLDBCQUNmLHNCQUFzQjtRQUN4QixNQUFNO01BQ1I7TUFDQSxNQUFNLFlBQVksZUFDaEIsV0FDQSxRQUNBLE1BQ0EsVUFDQSxhQUNBLFdBQVcsYUFBYSxFQUN4QjtNQUVGLGdCQUFnQjtNQUNoQixPQUFPLGFBQWE7SUFDdEIsRUFBRSxPQUFPLE9BQU87TUFDZCxJQUFJLFlBQVksV0FBVyxhQUFhLENBQUMscUJBQXFCO1FBQzVELE1BQU0sT0FDSixpQkFBaUIsZUFBZSxhQUFhLEdBQUcsQ0FBQyxNQUFNLElBQUksSUFDdkQsTUFBTSxJQUFJLEdBQ1Y7UUFDTixJQUFJO1VBQ0YsTUFBTSxTQUFTLE9BQ2IsTUFBTSxJQUFJLE1BQU0sOEJBQThCO1lBQzVDLGFBQWE7WUFDYixZQUFZO1lBQ1osY0FBYztZQUNkLGNBQWM7VUFDaEI7VUFFRixNQUFNLFFBQVE7WUFDWjtZQUNBO1lBQ0E7WUFDQTtZQUNBO1lBQ0E7V0FDRDtVQUNELElBQ0UsT0FBTyxnQkFBZ0IsS0FBSyxLQUFLLE9BQU8sRUFBRSxLQUFLLFFBQy9DLE9BQU8sU0FBUyxLQUFLLFlBQVksT0FBTyxLQUFLLEtBQUssWUFDbEQsT0FBTyxVQUFVLEtBQUssUUFBUSxPQUFPLE9BQU8sUUFBUSxLQUFLLFdBQ3pEO1FBQ0osRUFBRSxPQUFNO1VBQ04sT0FBTyxhQUFhO1lBQUUsT0FBTztVQUE2QixHQUFHO1FBQy9EO01BQ0Y7TUFDQSxNQUFNLFVBQVUsY0FBYztNQUM5QixPQUFPLGFBQWE7UUFBRSxPQUFPLFFBQVEsS0FBSztNQUFDLEdBQUcsUUFBUSxNQUFNO0lBQzlELFNBQVU7TUFDUixJQUFJLGlCQUFpQixXQUFXLFdBQVc7UUFDekMscUVBQXFFO1FBQ3JFLHdFQUF3RTtRQUN4RSxJQUFJO1VBQ0YsTUFBTSxXQUFXLE9BQ2YsTUFBTSxJQUFJLE1BQU0sMkJBQTJCO1lBQ3pDLGtCQUFrQjtZQUNsQixZQUFZO1lBQ1osY0FBYztZQUNkLFdBQVc7VUFDYjtVQUVGLE1BQU0sVUFBVTtZQUNkO1lBQ0E7WUFDQTtZQUNBO1lBQ0E7V0FDRDtVQUNELElBQ0UsU0FBUyxnQkFBZ0IsS0FBSyxLQUFLLFNBQVMsRUFBRSxLQUFLLFFBQ25ELFNBQVMsY0FBYyxLQUFLLGlCQUM1QixTQUFTLE9BQU8sS0FBSyxpQkFBaUIsU0FBUyxPQUFPLEtBQUssTUFDM0Q7UUFDSixFQUFFLE9BQU0sQ0FBK0Q7TUFDekU7SUFDRjtFQUNGO0FBQ0YifQ==
// denoCacheMetadata=2069453081900436383,5939893586263084621