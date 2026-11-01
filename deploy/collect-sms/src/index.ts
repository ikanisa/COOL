import {reportApplicationHealth} from "./application-health.ts";
import {scheduleOccurrences} from "./schedules.ts";
import {ledgerSnapshot} from "./snapshots.ts";
import {recoveryExport} from "./recovery.ts";
import {createTemplate,listTemplates,templateAction} from "./templates.ts";
import {createSchedule,listSchedules,scheduleAction,enqueueSchedules} from "./schedules.ts";
export {enqueueSchedules};
import { history, auditHistory } from "./history.ts";
import { metrics,alerts,evaluateAlerts } from "./metrics.ts";
import { configureCallback,disableCallback,listCallbacks,flushCallbacks } from "./callbacks.ts";
export { flushCallbacks,evaluateAlerts };
import { Hono } from "npm:hono@4.13.13";
import { admin, adminActor, application, authenticate } from "./auth.ts";
import {
  createApplication,
  createDevice,
  listApplications,
  listCampaigns,
  listDevices,
  listMessages,
  overview,
  rotateOrRevoke,
} from "./admin.ts";
import { campaignAction, createCampaign, expandCampaign } from "./campaigns.ts";
import {
  acceptJobs,
  deviceEvents,
  messagePermit,
  pullJobs,
  registerDevice,
} from "./devices.ts";
import { flushWakeups } from "./fcm.ts";
import {
  cancelMessage,
  contribution,
  createMessage,
  messageDetail,
  updateEligibility,
} from "./messages.ts";
import { createStaff, listStaff, createStaffSession, staffAction, currentStaff, logoutStaff, listAudit } from "./staff.ts";
import { previewRetention, runRetention, changeContentHold, purgeRetention, scrubExpiredOtp } from "./retention.ts";
import { createChallenge, verifyChallenge } from "./otp.ts";
import type { AppEnv, Env } from "./types.ts";
import { ApiError, isoNow, object } from "./util.ts";
export const app = new Hono<AppEnv>();
app.use("*", async (c, next) => {
  const url = new URL(c.req.url),
    local =
      c.env.ENVIRONMENT === "development" &&
      c.env.ALLOW_INSECURE_LOCALHOST === "true" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !local)
    throw new ApiError(
      403,
      "https_required",
      "Use HTTPS; local HTTP must be explicitly enabled for development",
    );
  const origin = c.req.header("Origin");
  if (origin) {
    if (origin !== c.env.ADMIN_ORIGIN && origin !== url.origin)
      throw new ApiError(
        403,
        "origin_denied",
        "This browser origin is not enabled",
      );
    c.header("Access-Control-Allow-Origin", origin);
    c.header("Vary", "Origin");
    c.header(
      "Access-Control-Allow-Headers",
      "Authorization, Content-Type, Idempotency-Key",
    );
    c.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  }
  c.header("Cache-Control", "no-store");
  c.header("X-Content-Type-Options", "nosniff");
  if (c.req.method === "OPTIONS") return c.body(null, 204);
  await next();
});
app.get("/health", async (c) => {
  try {
    await c.env.DB.prepare("SELECT 1 AS ok").first();
  } catch {
    throw new ApiError(
      503,
      "database_unavailable",
      "The durable store is unavailable",
    );
  }
  return c.json({ status: "ok", service: "collect-sms", version: "0.3.0" });
});
app.post("/v1/staff/sessions", createStaffSession);
app.use("/v1/*", authenticate);
app.use("/v1/*", async (c, next) => {
  await next();
  if (c.res.status < 400 && c.env.FCM_ENABLED === "true")
    c.executionCtx.waitUntil(flushWakeups(c.env));
});
async function body(c: {
  req: { raw: Request };
}): Promise<Record<string, unknown>> {
  const maximum = 262144,
    declared = Number(c.req.raw.headers.get("Content-Length") ?? 0);
  if (declared > maximum)
    throw new ApiError(413, "too_large", "Request exceeds 256 KiB");
  const reader = c.req.raw.body?.getReader();
  if (!reader)
    throw new ApiError(400, "invalid_json", "A JSON object is required");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > maximum) {
        try {
          await reader.cancel();
        } catch {}
        throw new ApiError(413, "too_large", "Request exceeds 256 KiB");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return object(JSON.parse(new TextDecoder().decode(bytes)));
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "invalid_json", "A JSON object is required");
  }
}
app.get("/v1/templates",listTemplates);
app.post("/v1/templates",async c=>createTemplate(c,await body(c)));
app.post("/v1/templates/:key/:version/:locale/:action",async c=>templateAction(c,await body(c)));
app.get("/v1/schedules",listSchedules);
app.get("/v1/schedules/:id/occurrences",scheduleOccurrences);
app.post("/v1/application/health",async c=>reportApplicationHealth(c,await body(c)));
app.post("/v1/schedules",async c=>createSchedule(c,await body(c)));
app.post("/v1/schedules/:id/:action",scheduleAction);
app.post("/v1/messages", async (c) => createMessage(c, await body(c)));
app.get("/v1/messages/:id", async (c) => {
  const p = application(c, "messages:read");
  return c.json(await messageDetail(c.env, c.req.param("id"), p.id));
});
app.post("/v1/messages/:id/cancel", async (c) => {
  const p = application(c, "messages:cancel");
  return c.json(
    await cancelMessage(
      c.env,
      c.req.param("id"),
      { type: "application", id: p.id },
      p.id,
    ),
  );
});
app.post("/v1/messages/:id/eligibility", async (c) =>
  updateEligibility(c, await body(c)),
);
app.post("/v1/events/contribution-posted", async (c) =>
  contribution(c, await body(c)),
);
app.post("/v1/otp/challenges", async (c) => createChallenge(c, await body(c)));
app.post("/v1/otp/verify", async (c) => verifyChallenge(c, await body(c)));
app.post("/v1/campaigns", async (c) => createCampaign(c, await body(c)));
app.post("/v1/campaigns/:id/:action", async (c) => {
  const p = application(c, "campaigns", "campaign");
  return c.json(
    await campaignAction(
      c.env,
      c.req.param("id"),
      c.req.param("action"),
      { type: "application", id: p.id },
      p.id,
    ),
  );
});
app.post("/v1/events/ledger-snapshot", async c=>ledgerSnapshot(c,await body(c)));
app.get("/v1/admin/recovery-evidence",recoveryExport);
app.get("/v1/admin/message-history", c=>history(c));
app.get("/v1/admin/message-export", c=>history(c,true));
app.get("/v1/admin/audit-history", auditHistory);
app.get("/v1/admin/metrics",metrics);
app.get("/v1/admin/alerts",alerts);
app.get("/v1/admin/callbacks",listCallbacks);
app.post("/v1/admin/callbacks",async c=>configureCallback(c,await body(c)));
app.post("/v1/admin/callbacks/:id/disable",disableCallback);
app.get("/v1/admin/me", currentStaff);
app.post("/v1/admin/logout", logoutStaff);
app.get("/v1/admin/staff", listStaff);
app.post("/v1/admin/staff", async c => createStaff(c, await body(c)));
app.post("/v1/admin/staff/:id/:action", async c => staffAction(c, await body(c)));
app.get("/v1/admin/audit", listAudit);
app.get("/v1/admin/retention", previewRetention);
app.post("/v1/admin/retention/run", async c => runRetention(c, await body(c)));
app.post("/v1/admin/retention/holds", async c => changeContentHold(c, await body(c)));
app.get("/v1/admin/overview", overview);
app.get("/v1/admin/messages", listMessages);
app.get("/v1/admin/messages/:id", async (c) => {
  admin(c);
  return c.json(await messageDetail(c.env, c.req.param("id")));
});
app.post("/v1/admin/messages/:id/cancel", async (c) => {
  admin(c,"messages:cancel");
  return c.json(await cancelMessage(c.env, c.req.param("id"), adminActor(c)));
});
app.get("/v1/admin/applications", listApplications);
app.post("/v1/admin/applications", async (c) =>
  createApplication(c, await body(c)),
);
app.get("/v1/admin/devices", listDevices);
app.post("/v1/admin/devices", async (c) => createDevice(c, await body(c)));
app.get("/v1/admin/campaigns", listCampaigns);
app.post("/v1/admin/campaigns/:id/:action", async (c) => {
  admin(c,"campaigns:write");
  return c.json(await campaignAction(c.env, c.req.param("id"), c.req.param("action"), adminActor(c)));
});
for (const resource of ["devices", "applications"] as const)
  for (const action of ["rotate", "revoke"] as const)
    app.post(`/v1/admin/${resource}/:id/${action}`, (c) =>
      rotateOrRevoke(c, resource, action),
    );
app.post("/v1/device/registration", async (c) =>
  registerDevice(c, await body(c)),
);
app.get("/v1/device/jobs", pullJobs);
app.post("/v1/device/acceptances", async (c) => acceptJobs(c, await body(c)));
app.post("/v1/device/events", async (c) => deviceEvents(c, await body(c)));
app.get("/v1/device/messages/:id/permit", messagePermit);
app.notFound((c) =>
  c.json({ error: { code: "not_found", message: "Route not found" } }, 404),
);
app.onError((error, c) => {
  if (error instanceof ApiError)
    return c.json(
      { error: { code: error.code, message: error.message } },
      error.status,
    );
  const text = String(error);
  if (/otp_capacity_unavailable/.test(text)) return c.json({error:{code:"otp_capacity_unavailable",message:"No estimated OTP dispatch slot is available; no challenge was created"}},503);
  if (/otp_phone_rate|otp_application_rate/.test(text))
    return c.json(
      {
        error: {
          code: "otp_rate_limit",
          message: "OTP issuance limit reached; wait before trying again",
        },
      },
      429,
    );
  if (/event_wrong_owner/.test(text))
    return c.json(
      {
        error: {
          code: "wrong_owner",
          message:
            "The event or acknowledgement does not match this device assignment",
        },
      },
      403,
    );
  if (/event_|handoff_|UNIQUE constraint|CHECK constraint|unique constraint|check constraint/.test(text))
    return c.json(
      {
        error: {
          code: "state_conflict",
          message:
            "The operation conflicts with immutable identity or recorded delivery evidence",
        },
      },
      409,
    );
  console.error(
    JSON.stringify({ component: "collect-sms", error_type: error.name }),
  );
  return c.json(
    {
      error: {
        code: "internal_error",
        message:
          "The operation did not complete; retry using the same idempotency key",
      },
    },
    500,
  );
});
export async function maintenance(env: Env): Promise<void> {
  const now = isoNow();
  await env.DB.batch([
    env.DB.prepare(
      "UPDATE messages SET state='expired',updated_at=? WHERE owner_installation_id IS NULL AND state='accepted' AND not_after<=?",
    ).bind(now, now),
    env.DB.prepare(
      "UPDATE messages SET state='delivery_unconfirmed',updated_at=? WHERE state='sent' AND updated_at<?",
    ).bind(now, new Date(Date.now() - 86_400_000).toISOString()),
    env.DB.prepare("DELETE FROM campaign_budget WHERE window_start<?").bind(
      new Date(Date.now() - 86_400_000).toISOString(),
    ),
    env.DB.prepare("DELETE FROM dispatch_permits WHERE valid_until<?").bind(
      new Date(Date.now() - 86_400_000).toISOString(),
    ),
  ]);
  const campaigns = await env.DB.prepare(
    "SELECT c.campaign_id FROM campaigns c JOIN applications a ON a.application_id=c.application_id WHERE c.status='running' AND c.expansion_cursor<c.recipient_count AND c.not_after>? AND a.revoked_at IS NULL ORDER BY c.updated_at,c.campaign_id LIMIT 5",
  )
    .bind(now)
    .all<{ campaign_id: string }>();
  for (const campaign of campaigns.results)
    await expandCampaign(env, campaign.campaign_id);
  await env.DB.prepare(
    "UPDATE campaigns SET status='completed',updated_at=? WHERE status='running' AND expansion_cursor=recipient_count AND NOT EXISTS(SELECT 1 FROM messages m WHERE m.campaign_id=campaigns.campaign_id AND m.state NOT IN('sent','delivered','delivery_unconfirmed','expired','cancelled','failed'))",
  )
    .bind(now)
    .run();
  await scrubExpiredOtp(env);
  await env.DB.prepare(`UPDATE ledger_notification_events SET facts_json='{}',redacted_at=? WHERE (application_id,event_id) IN(
    SELECT e.application_id,e.event_id FROM ledger_notification_events e WHERE e.redacted_at IS NULL
    AND EXISTS(SELECT 1 FROM ledger_notification_receipts r WHERE r.application_id=e.application_id AND r.event_id=e.event_id)
    AND NOT EXISTS(SELECT 1 FROM ledger_notification_receipts r JOIN messages m ON m.message_id=r.message_id WHERE r.application_id=e.application_id AND r.event_id=e.event_id AND (m.content_redacted_at IS NULL OR m.content_hold=1))
    ORDER BY e.created_at LIMIT 100)`).bind(now).run();
  if (env.RETENTION_AUTO_PURGE === "true") await purgeRetention(env, {type:"system",id:"scheduled"}, 100);
  if(env.DISPATCH_PAUSED!=="true") await enqueueSchedules(env);
  await evaluateAlerts(env);
  await flushCallbacks(env);
  await flushWakeups(env);
}
export default {
  fetch: app.fetch,
  scheduled(_event: unknown, env: Env, ctx: {waitUntil(promise: Promise<unknown>): void}) {
    ctx.waitUntil(maintenance(env));
  },
};
