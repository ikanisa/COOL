import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import * as z from "zod/v4";

import { callNotificationOperator } from "./operator_client.ts";

const uuid = z.string().uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const worker = z.string().regex(/^[A-Za-z0-9._:-]{3,80}$/);

function toolResult(result: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(result) }],
    structuredContent: { result },
  };
}

function createServer() {
  const server = new McpServer(
    { name: "collect-notification-operator", version: "0.1.0" },
    {
      instructions:
        "Read health and pending work first. Never infer a destination, message, balance, confirmation, send result, or delivery. A receipt requires a current claim, exact receipt read, explicit user confirmation, send-start record, one Messages action, UI readback, and an observed outcome. Never retry an uncertain attempt.",
    },
  );

  server.registerTool(
    "collect_notification_health",
    {
      description:
        "Read safe aggregate Collect SMS queue health. Use at the start of a scheduled scan; returns counts and worker freshness without phone numbers or receipt bodies.",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true },
    },
    async () => toolResult(await callNotificationOperator("health", {})),
  );

  server.registerTool(
    "collect_list_pending_receipts",
    {
      description:
        "List a bounded page of queued Collect receipt jobs. Use after health reports queued work; returns opaque job IDs and masked destinations, never full receipt content.",
      inputSchema: z.object({
        limit: z.number().int().min(1).max(50).default(20),
        after_created_at: z.string().datetime().optional(),
      }),
      annotations: { readOnlyHint: true },
    },
    async (input) =>
      toolResult(await callNotificationOperator("list_pending", input)),
  );

  server.registerTool(
    "collect_claim_receipt",
    {
      description:
        "Claim one queued Collect receipt for this worker with a time-limited fencing token. Use before requesting exact content; this changes only queue ownership and does not send SMS.",
      inputSchema: z.object({
        job_id: uuid,
        worker_id: worker,
        request_id: uuid,
      }),
    },
    async (input) => toolResult(await callNotificationOperator("claim", input)),
  );

  server.registerTool(
    "collect_get_claimed_receipt",
    {
      description:
        "Read the exact registered destination and immutable Buri Munsi receipt for a current fenced claim. Use only to present the imminent recipient and full content for user confirmation; returns sensitive member data.",
      inputSchema: z.object({
        job_id: uuid,
        claim_token: uuid,
        fence_version: z.number().int().positive(),
      }),
      annotations: { readOnlyHint: true },
    },
    async (input) =>
      toolResult(await callNotificationOperator("get_claimed", input)),
  );

  server.registerTool(
    "collect_confirm_receipt",
    {
      description:
        "Record a fresh action-specific user approval for the exact claimed destination revision and body hash. Call only after the user has just confirmed that exact recipient and exact content; this does not send SMS.",
      inputSchema: z.object({
        job_id: uuid,
        claim_token: uuid,
        fence_version: z.number().int().positive(),
        destination_revision: z.number().int().positive(),
        body_sha256: sha256,
        confirmation_id: uuid,
        user_confirmation: z.literal(true),
      }),
    },
    async (input) =>
      toolResult(await callNotificationOperator("confirm", input)),
  );

  server.registerTool(
    "collect_record_send_start",
    {
      description:
        "Consume the fresh exact receipt confirmation and record the durable pre-send boundary. Call immediately before one Apple Messages send; it does not operate Messages or prove sending.",
      inputSchema: z.object({
        job_id: uuid,
        claim_token: uuid,
        fence_version: z.number().int().positive(),
        confirmation_id: uuid,
      }),
    },
    async (input) =>
      toolResult(await callNotificationOperator("record_send_start", input)),
  );

  server.registerTool(
    "collect_record_observed_outcome",
    {
      description:
        "Record the Apple Messages UI readback after a send-start as observed_sent, failed_no_send, or uncertain. Use observed_sent only when the exact outgoing message is visibly present; this never claims handset delivery.",
      inputSchema: z.object({
        attempt_id: uuid,
        outcome: z.enum(["observed_sent", "failed_no_send", "uncertain"]),
        evidence_reference: z.string().trim().min(8).max(500),
        outcome_note: z.string().trim().max(500).optional(),
      }),
    },
    async (input) =>
      toolResult(await callNotificationOperator("record_outcome", input)),
  );

  server.registerTool(
    "collect_release_unsent_claim",
    {
      description:
        "Release a current claim only when no send-start exists. Use after cancellation or preparation failure; it safely requeues the unchanged receipt and rejects any possibly sent attempt.",
      inputSchema: z.object({
        job_id: uuid,
        claim_token: uuid,
        fence_version: z.number().int().positive(),
        reason: z.string().trim().min(8).max(500),
      }),
    },
    async (input) =>
      toolResult(await callNotificationOperator("release_claim", input)),
  );

  server.registerTool(
    "collect_worker_heartbeat",
    {
      description:
        "Record that the designated Collect Mac worker completed a queue scan in no-send or assisted-send mode. Stores only safe aggregate status and never establishes delivery.",
      inputSchema: z.object({
        worker_id: worker,
        run_id: uuid,
        mode: z.enum(["no_send", "assisted_send"]),
        queue_checked: z.boolean(),
      }),
    },
    async (input) =>
      toolResult(await callNotificationOperator("heartbeat", input)),
  );

  return server;
}

void serveStdio(createServer);
console.error("Collect notification MCP server listening on stdio");
