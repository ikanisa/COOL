import {pathToFileURL} from "node:url";
import {parseShadowOptions} from "./shadow_cli_options.ts";
import {shadowSafeCodes} from "./shadow_client.ts";
import {shadowStdio, type ShadowTransport} from "./shadow_stdio.ts";
import {projectedShadowSample, shadowResult} from "./shadow_contract.ts";

const safe = new Set<string>([...shadowSafeCodes, "SHADOW_ARGUMENTS_INVALID"]);
function result(reply: Record<string, unknown>) {
  const tool = reply.result;
  if (!tool || typeof tool !== "object" || Array.isArray(tool) || reply.error) throw new Error("SHADOW_RESPONSE_INVALID");
  const row = tool as Record<string, unknown>;
  if (row.isError === true) {
    const content = row.content;
    const text = Array.isArray(content) && content.length === 1 && typeof content[0] === "object" && content[0] !== null ?
      (content[0] as Record<string, unknown>).text : null;
    throw new Error(typeof text === "string" && safe.has(text) ? text : "SHADOW_RESPONSE_INVALID");
  }
  const structured = row.structuredContent;
  if (!structured || typeof structured !== "object" || Array.isArray(structured)) throw new Error("SHADOW_RESPONSE_INVALID");
  return (structured as Record<string, unknown>).result;
}
function runSummary(value: unknown) {
  const row = value as Record<string, unknown>;
  const summary = row.summary as Record<string, unknown> | null;
  const sampledAt = typeof row.sampled_at === "string" ? row.sampled_at : null;
  return {run_id: row.run_id, run_status: row.status, fence_version: row.fence_version,
    started_at: row.started_at, lease_expires_at: row.lease_expires_at, sampled_at: sampledAt, completed_at: row.completed_at,
    recorded_health_status: summary?.health_status ?? null, summary_evidence: "historical",
    checks_recorded: summary?.checks_recorded ?? 0, samples_recorded: summary?.samples_recorded ?? 0};
}

export async function runShadowSupervisor(
  args: readonly string[],
  factory: () => ShadowTransport = () => shadowStdio(),
): Promise<Record<string, unknown> & {status: string}> {
  let options;
  try {options = parseShadowOptions(args);}
  catch {return {status: "SHADOW_ARGUMENTS_INVALID", business_mutations: 0, provider_sends: 0, credentials_printed: false};}
  let transport: ShadowTransport | undefined, phase: "initialize" | "begin" | "sample" | "complete" | "get" = "initialize", runId: string | undefined;
  const boundary = {request_id: options.requestId, mode: "shadow", scope: "collect_platform", business_mutations: 0, provider_sends: 0, credentials_printed: false};
  try {
    transport = factory();
    await transport.initialize();
    if (options.mode === "status") {
      phase = "get";
      const raw = result(await transport.call("get_supervisor_run", {request_id: options.requestId}));
      const value = shadowResult("get", raw, {request_id: options.requestId});
      if (!("found" in value)) throw new Error("SHADOW_RESPONSE_INVALID");
      return {status: value.found ? "SHADOW_STATUS_FOUND" : "SHADOW_STATUS_NOT_FOUND", ...boundary,
        ...(value.run ? runSummary(value.run) : {})};
    }
    phase = "begin";
    const startedRaw = result(await transport.call("begin_supervisor_run", {request_id: options.requestId}));
    const started = shadowResult("begin", startedRaw, {request_id: options.requestId});
    if (!("outcome" in started)) throw new Error("SHADOW_RESPONSE_INVALID");
    if (started.outcome === "busy") return {status: "SHADOW_BUSY", ...boundary};
    if (!("run" in started) || !started.run) throw new Error("SHADOW_RESPONSE_INVALID");
    runId = started.run.run_id;
    if (started.run.status !== "running") return {status: started.run.status === "completed" ? "SHADOW_ALREADY_COMPLETED" : "SHADOW_EXPIRED",
      ...boundary, ...runSummary(started.run)};
    if (Date.now() >= Date.parse(started.run.lease_expires_at)) return {status: "SHADOW_EXPIRED", ...boundary, ...runSummary(started.run)};
    const fenced = {run_id: runId, fence_version: started.run.fence_version};
    phase = "sample";
    const sample = projectedShadowSample(result(await transport.call("sample_supervisor_run", fenced)), fenced);
    if (!sample.sample.sample_fresh) throw new Error("SHADOW_HEALTH_STALE");
    phase = "complete";
    const completedRaw = result(await transport.call("complete_supervisor_run", fenced));
    const completed = shadowResult("complete", completedRaw, fenced);
    if (!("run" in completed) || !completed.run || completed.run.request_id !== options.requestId) throw new Error("SHADOW_RESPONSE_INVALID");
    return {status: "SHADOW_COMPLETED", ...boundary, ...runSummary(completed.run)};
  } catch (error) {
    const code = error instanceof Error && safe.has(error.message) ? error.message :
      phase === "initialize" || phase === "get" ? "SHADOW_READ_UNAVAILABLE" : "SHADOW_OUTCOME_UNKNOWN";
    return {status: code, ...boundary, ...(runId ? {run_id: runId} : {}),
      reconciliation_required: phase !== "initialize" && phase !== "get",
      blocked_phase: phase};
  } finally {await transport?.close().catch(() => {});}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const report = await runShadowSupervisor(process.argv.slice(2));
  console.log(JSON.stringify(report));
  if (!["SHADOW_COMPLETED", "SHADOW_ALREADY_COMPLETED", "SHADOW_STATUS_FOUND", "SHADOW_STATUS_NOT_FOUND"].includes(report.status)) process.exitCode = 2;
}
