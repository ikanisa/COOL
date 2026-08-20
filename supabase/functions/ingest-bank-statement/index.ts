import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";
import { sha256Hex } from "../_shared/hash.ts";
import { parseBankStatement } from "../_shared/bank_statement.ts";

const encoder = new TextEncoder();

function requiredString(value: unknown, name: string, maxBytes: number): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} is required`);
  const clean = value.trim();
  if (encoder.encode(clean).byteLength > maxBytes) throw new Error(`${name} exceeds the ingestion limit`);
  return clean;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  try {
    const { supabase } = await requireUser(request.headers.get("authorization"));
    const payload = await request.json();
    if (typeof payload !== "object" || payload == null || Array.isArray(payload)) {
      throw new Error("A JSON object is required");
    }
    const fileName = requiredString(payload.file_name, "file_name", 240);
    const format = requiredString(payload.format, "format", 20);
    const content = requiredString(payload.content, "content", 2_000_000);
    const reason = requiredString(payload.reason, "reason", 500);
    if (reason.length < 8) throw new Error("reason must be at least 8 characters");
    const periodStart = requiredString(payload.period_start, "period_start", 10);
    const periodEnd = requiredString(payload.period_end, "period_end", 10);
    const lines = parseBankStatement(format, content);
    const fileHash = await sha256Hex(content);
    const { data, error } = await supabase.rpc("admin_import_bank_statement", {
      p_file_name: fileName,
      p_file_hash: fileHash,
      p_period_start: periodStart,
      p_period_end: periodEnd,
      p_lines: lines,
      p_reason: reason,
    });
    if (error) throw error;
    return jsonResponse({ ok: true, import: data });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    const message = safeErrorMessage(error);
    if (authStatus) return jsonResponse({ error: message }, authStatus);
    if (/permission/i.test(message)) return jsonResponse({ error: message }, 403);
    if (/required|invalid|unsupported|between|exceeds|already imported|only EUR|outside/i.test(message)) {
      return jsonResponse({ error: message }, 400);
    }
    console.error(JSON.stringify({ event: "ingest_bank_statement_failed", message }));
    return jsonResponse({ error: "Bank statement could not be imported" }, 500);
  }
});
