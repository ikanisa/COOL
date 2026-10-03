import {McpServer} from "@modelcontextprotocol/server";
import {serveStdio} from "@modelcontextprotocol/server/stdio";
import * as z from "zod/v4";
import {pathToFileURL} from "node:url";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import {unattendedKeychainSigner} from "./unattended_client.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import type {UnattendedRequest} from "./unattended_contract.ts";
const id = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
const fence = z.number().int().min(1).max(1_000_000_000);
const read = {readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true};
const write = {readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true};
export type UnattendedInvoke = (request: UnattendedRequest) => Promise<unknown>;
export function createUnattendedServer(invoke: UnattendedInvoke, status: (requestId: string) => Promise<unknown>) {
  const server = new McpServer({name: "collect-unattended-operations", version: "2.0.0"}, {instructions:
    "Separate scoped receipt operations. Retain every request UUID before invocation. Backend derives content and destinations. An uncertain response requires an explicit original-request lookup; never replay or create a replacement action. No send or financial action is registered. Existing five-read Collect installation is separate."});
  const schemas = {
    prove_key: z.strictObject({request_id: id}), begin_run: z.strictObject({request_id: id}),
    list_events: z.strictObject({request_id: id, run_id: id, fence_version: fence, limit: z.number().int().min(1).max(25)}),
    ensure_receipt: z.strictObject({request_id: id, run_id: id, fence_version: fence, event_id: id, expected_source_version: fence}),
    reconcile_backlog: z.strictObject({request_id: id, run_id: id, fence_version: fence, limit: z.number().int().min(1).max(25)}),
    complete_run: z.strictObject({request_id: id, run_id: id, fence_version: fence}),
    reconcile_request: z.strictObject({request_id: id, target_request_id: id}),
  };
  for (const [action, schema] of Object.entries(schemas)) server.registerTool(`collect_unattended_${action}`, {
    description: action === "reconcile_request" ? "Explicit fresh signed lookup of an original request using a distinct UUID; no mutation replay. Recorded preparation proof is not delivery." :
      `Governed ${action} under the separate v2 operations identity. Durable request evidence precedes one HTTP attempt. Server lease, quota, current authority and policy gates apply. No caller body/destination/amount or send action.`,
    inputSchema: schema, annotations: action === "reconcile_request" ? read : write,
  }, async (input: Record<string, string | number>) => {
    const {request_id, ...payload} = input; const requestId = String(request_id);
    try {
      const result = await invoke({action: action as UnattendedRequest["action"], requestId, payload});
      return {content: [{type: "text" as const, text: JSON.stringify(result)}], structuredContent: {result}};
    } catch {return {isError: true, content: [{type: "text" as const, text: "UNATTENDED_ACTION_UNAVAILABLE"}]};}
  });
  server.registerTool("collect_unattended_status", {description: "Read original local historical request evidence only; no signer, credential or HTTP request.",
    inputSchema: z.strictObject({request_id: id}), annotations: {...read, openWorldHint: false}}, async input => {
    try {const result = await status(input.request_id); return {content: [{type: "text" as const, text: JSON.stringify(result)}], structuredContent: {result}};}
    catch {return {isError: true, content: [{type: "text" as const, text: "UNATTENDED_LOCAL_STATUS_UNAVAILABLE"}]};}
  });
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  // Discovery is always credential-free. Missing profile prevents every action;
  // no operator JWT, Keychain read, signup or enrollment occurs at startup.
  const invoke: UnattendedInvoke = async request => {
    const profile = await loadUnattendedProfile(process.env.COLLECT_UNATTENDED_PROFILE ?? "");
    const journal = new UnattendedJournal(profile.journal_directory);
    const signer = unattendedKeychainSigner(profile.helper_path, profile.helper_sha256, profile.key_tag_id);
    return request.action === "reconcile_request" ? journal.reconcile(profile.identity, String(request.payload.target_request_id), request.requestId, signer) :
      journal.once(profile.identity, request, signer);
  };
  const status = async (requestId: string) => {
    const profile = await loadUnattendedProfile(process.env.COLLECT_UNATTENDED_PROFILE ?? "");
    return new UnattendedJournal(profile.journal_directory).readOriginal(requestId);
  };
  await serveStdio(() => createUnattendedServer(invoke, status));
}
