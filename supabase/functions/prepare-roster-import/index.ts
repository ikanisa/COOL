import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import {
  normalizeRosterCandidates,
  parseRosterText,
  type RosterImportSource,
} from "../_shared/roster_import.ts";
import {
  type AiRosterSource,
  buildRosterResponsesRequest,
  previewOpenAiRoster,
} from "../_shared/openai_roster.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

const deterministicSourceTypes = new Set<RosterImportSource>(["text", "csv"]);
const aiSourceTypes = new Set<AiRosterSource>(["pdf", "image"]);
const allowedMimeTypes = new Map([
  ["application/pdf", "pdf"],
  ["image/jpeg", "image"],
  ["image/png", "image"],
  ["image/webp", "image"],
]);
const maxAiFileBytes = 5 * 1024 * 1024;

function requiredText(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${field} is required`);
  }
  const clean = value.trim();
  if (clean.length > maxLength) {
    throw new Error(`${field} exceeds the accepted limit`);
  }
  return clean;
}

function decodeRosterFile(value: unknown): Uint8Array {
  const encoded = requiredText(value, "content_base64", 7_000_000);
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded) || encoded.length % 4 !== 0) {
    throw new Error("Roster file is not valid base64");
  }
  let binary: string;
  try {
    binary = atob(encoded);
  } catch {
    throw new Error("Roster file is not valid base64");
  }
  if (binary.length > maxAiFileBytes) {
    throw new Error("Roster file exceeds the 5 MB extraction limit");
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const stableBytes = new Uint8Array(bytes.length);
  stableBytes.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", stableBytes.buffer);
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  try {
    const { supabase } = await requireUser(
      request.headers.get("authorization"),
    );
    const { data: identity, error: identityError } = await supabase.rpc(
      "admin_current_user",
    );
    if (identityError) throw identityError;
    const permissions = typeof identity === "object" && identity != null &&
        Array.isArray((identity as Record<string, unknown>).permissions)
      ? (identity as Record<string, unknown>).permissions as unknown[]
      : [];
    if (
      !permissions.includes("collections.moderate") ||
      !permissions.includes("users.read")
    ) {
      return jsonResponse({ error: "Admin roster permission required" }, 403);
    }
    const { data: flag, error: flagError } = await serviceClient()
      .from("feature_flags")
      .select("enabled")
      .eq("key", "hybrid_member_onboarding")
      .maybeSingle();
    if (flagError) throw flagError;
    if (flag?.enabled !== true) {
      return jsonResponse({ error: "Hybrid onboarding is disabled" }, 409);
    }
    const payload = await request.json() as Record<string, unknown>;
    const sourceType = requiredText(
      payload.source_type,
      "source_type",
      12,
    );
    if (
      !deterministicSourceTypes.has(sourceType as RosterImportSource) &&
      !aiSourceTypes.has(sourceType as AiRosterSource)
    ) {
      throw new Error("Unsupported roster source type");
    }

    if (deterministicSourceTypes.has(sourceType as RosterImportSource)) {
      const content = requiredText(payload.content, "content", 512_000);
      const preview = normalizeRosterCandidates(parseRosterText(content));
      return jsonResponse({
        ok: true,
        processing_method: "deterministic",
        requires_human_review: false,
        model: null,
        ...preview,
      });
    }

    if (payload.ai_consent !== true) {
      throw new Error("Explicit AI extraction consent is required");
    }
    const filename = requiredText(payload.filename, "filename", 160);
    if (!/^[A-Za-z0-9][A-Za-z0-9._ -]{0,159}$/.test(filename)) {
      throw new Error("Roster filename contains unsupported characters");
    }
    const mimeType = requiredText(payload.mime_type, "mime_type", 64)
      .toLowerCase();
    const expectedType = allowedMimeTypes.get(mimeType);
    if (expectedType !== sourceType) {
      throw new Error("Roster file type does not match its MIME type");
    }
    const fileBytes = decodeRosterFile(payload.content_base64);
    if (fileBytes.length === 0) throw new Error("Roster file is empty");
    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    if (!apiKey) throw new Error("OpenAI roster extraction is not configured");
    const model = Deno.env.get("OPENAI_ROSTER_MODEL")?.trim() || "gpt-5-mini";
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(buildRosterResponsesRequest(
        model,
        sourceType as AiRosterSource,
        filename,
        mimeType,
        payload.content_base64 as string,
      )),
      signal: AbortSignal.timeout(60_000),
    });
    const responseBody = await response.json().catch(() => null);
    if (!response.ok) {
      throw new Error(`OpenAI roster extraction failed (${response.status})`);
    }
    const preview = previewOpenAiRoster(responseBody);
    return jsonResponse({
      ok: true,
      processing_method: "openai_structured_extraction",
      requires_human_review: true,
      model,
      source_sha256: await sha256Hex(fileBytes),
      ...preview,
      can_submit: false,
    });
  } catch (error) {
    const message = safeErrorMessage(error);
    return jsonResponse(
      { error: message },
      authErrorStatus(error) ??
        (/required|invalid|unsupported|limit|must/i.test(message) ? 400 : 502),
    );
  }
});
