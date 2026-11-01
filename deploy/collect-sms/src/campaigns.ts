import type { Context } from "npm:hono@4.13.13";
import { application } from "./auth.ts";
import { campaignMessageInsert, makeMessage } from "./messages.ts";
import type { NewMessage } from "./messages.ts";
import type { AppEnv, Env } from "./types.ts";
import {
  ApiError,
  array,
  canonical,
  integer,
  isoNow,
  phone,
  segmentEstimate,
  sha256,
  string,
  timestamp,
  uid,
} from "./util.ts";
export interface CampaignRow {
  campaign_id: string;
  application_id: string;
  name: string;
  text: string;
  recipients_json: string;
  recipient_count: number;
  expansion_cursor: number;
  request_key: string;
  request_digest: string;
  status: string;
  not_after: string;
  scheduled_at: string;
  segments_per_minute: number;
  segments_per_message: number;
  created_at: string;
  updated_at: string;
  content_redacted_at: string | null;
  content_hold: number;
}
export function campaignSummary(row: CampaignRow) {
  return {
    campaign_id: row.campaign_id,
    application_id: row.application_id,
    name: row.name,
    text: row.content_redacted_at ? "[Content removed by retention policy]" : row.text,
    content_redacted_at: row.content_redacted_at ?? null,
    content_hold: !!row.content_hold,
    state: row.status,
    recipient_count: row.recipient_count,
    expanded_count: row.expansion_cursor,
    not_after: row.not_after,
    scheduled_at: row.scheduled_at,
    segments_per_minute: row.segments_per_minute,
    segments_per_message: row.segments_per_message,
    estimated_segments: row.recipient_count * row.segments_per_message,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}
export async function createCampaign(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = application(c, "campaigns", "campaign"),
    name = string(body.name, "name", 1, 120),
    text = string(body.text, "text", 1, 2000),
    recipients = [
      ...new Set(array(body.recipients, "recipients", 5000).map(phone)),
    ];
  if (!recipients.length)
    throw new ApiError(
      400,
      "invalid_request",
      "A campaign needs at least one recipient",
    );
  const notAfter = timestamp(body.not_after, "not_after"),
    now = isoNow(),
    scheduled =
      body.scheduled_at === undefined
        ? undefined
        : timestamp(body.scheduled_at, "scheduled_at"),
    rate =
      body.segments_per_minute === undefined
        ? 30
        : integer(body.segments_per_minute, "segments_per_minute", 1, 6000),
    segments = segmentEstimate(text);
  if (segments > rate)
    throw new ApiError(
      400,
      "rate_too_small",
      "The minute budget must fit at least one complete message",
    );
  const key = c.req.header("Idempotency-Key")
      ? string(c.req.header("Idempotency-Key"), "Idempotency-Key", 1, 128)
      : uid("request"),
    digest = await sha256(
      canonical({
        name,
        text,
        recipients,
        not_after: notAfter,
        scheduled_at: scheduled ?? null,
        segments_per_minute: rate,
      }),
    );
  const old = await c.env.DB.prepare(
    "SELECT * FROM campaigns WHERE application_id=? AND request_key=?",
  )
    .bind(p.id, key)
    .first<CampaignRow>();
  if (old) {
    if (old.request_digest !== digest)
      throw new ApiError(
        409,
        "idempotency_conflict",
        "Campaign key was used with a different request",
      );
    return c.json(campaignSummary(old), 201);
  }
  if (notAfter <= now || (scheduled && scheduled >= notAfter))
    throw new ApiError(
      400,
      "invalid_request",
      "The schedule must precede a future not_after",
    );
  const id = uid("campaign");
  try {
    await c.env.DB.prepare(
      "INSERT INTO campaigns(campaign_id,application_id,name,text,recipients_json,recipient_count,request_key,request_digest,not_after,scheduled_at,segments_per_minute,segments_per_message,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    )
      .bind(
        id,
        p.id,
        name,
        text,
        JSON.stringify(recipients),
        recipients.length,
        key,
        digest,
        notAfter,
        scheduled ?? now,
        rate,
        segments,
        now,
        now,
      )
      .run();
  } catch (error) {
    const raced = await c.env.DB.prepare(
      "SELECT * FROM campaigns WHERE application_id=? AND request_key=?",
    )
      .bind(p.id, key)
      .first<CampaignRow>();
    if (!raced) throw error;
    if (raced.request_digest !== digest)
      throw new ApiError(
        409,
        "idempotency_conflict",
        "Campaign key was used with a different request",
      );
    return c.json(campaignSummary(raced), 201);
  }
  return c.json(
    { campaign_id: id, state: "draft", recipient_count: recipients.length },
    201,
  );
}
export async function expandCampaign(
  env: Env,
  id: string,
  chunkSize = 20,
): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT c.* FROM campaigns c JOIN applications a ON a.application_id=c.application_id WHERE c.campaign_id=? AND c.status='running' AND c.not_after>? AND a.revoked_at IS NULL",
  )
    .bind(id, isoNow())
    .first<CampaignRow>();
  if (!row || row.expansion_cursor >= row.recipient_count) return 0;
  const recipients = JSON.parse(row.recipients_json) as string[],
    start = row.expansion_cursor,
    end = Math.min(start + chunkSize, recipients.length),
    messages: NewMessage[] = [],
    now = isoNow();
  for (let i = start; i < end; i++) {
    const recipient = recipients[i]!,
      key = `campaign:${id}:${i}`;
    messages.push(
      await makeMessage({
        message_id: `msg_${(await sha256(`${row.application_id}\n${key}`)).slice(0, 40)}`,
        application_id: row.application_id,
        kind: "campaign",
        to: recipient,
        text: row.text,
        request_digest: await sha256(
          canonical({ campaign_id: id, index: i, to: recipient }),
        ),
        idempotency_key: key,
        priority: 10,
        not_after: row.not_after,
        available_at: row.scheduled_at,
        created_at: now,
        campaign_id: id,
        metadata: { campaign_name: row.name },
      }),
    );
  }
  await env.DB.batch([
    campaignMessageInsert(env.DB, messages, id),
    env.DB.prepare(
      "UPDATE campaigns SET expansion_cursor=MAX(expansion_cursor,?),updated_at=? WHERE campaign_id=? AND status='running' AND EXISTS(SELECT 1 FROM applications a WHERE a.application_id=campaigns.application_id AND a.revoked_at IS NULL)",
    ).bind(end, now, id),
  ]);
  return end - start;
}
export async function campaignAction(
  env: Env,
  id: string,
  action: string,
  actor: { type: string; id: string },
  appId?: string,
) {
  if (!["start", "pause", "resume", "cancel"].includes(action??''))
    throw new ApiError(404, "not_found", "Campaign action not found");
  const row = await env.DB.prepare(
    `SELECT * FROM campaigns WHERE campaign_id=? ${appId ? "AND application_id=?" : ""}`,
  )
    .bind(id, ...(appId ? [appId] : []))
    .first<CampaignRow>();
  if (!row) throw new ApiError(404, "not_found", "Campaign not found");
  if (row.content_redacted_at) throw new ApiError(409,"content_redacted","An archived campaign cannot restart or change state");
  const target =
      action === "pause"
        ? "paused"
        : action === "cancel"
          ? "cancelled"
          : "running",
    permitted =
      action === "start"
        ? ["draft", "running"]
        : action === "resume"
          ? ["paused", "running"]
          : action === "pause"
            ? ["running", "paused"]
            : ["draft", "running", "paused", "cancelled"];
  if (!permitted.includes(row.status))
    throw new ApiError(
      409,
      "campaign_state",
      "The campaign cannot perform that transition",
    );
  if (target === "running" && row.not_after <= isoNow())
    throw new ApiError(409, "expired", "This campaign has expired");
  const now = isoNow();
  const statements = [
    env.DB.prepare(
      `UPDATE campaigns SET status=?,updated_at=? WHERE campaign_id=? AND status IN(${permitted.map(() => "?").join(",")})`,
    ).bind(target, now, id, ...permitted),
    env.DB.prepare(
      "INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM campaigns WHERE campaign_id=? AND status=?)",
    ).bind(
      uid("audit"),
      actor.type,
      actor.id,
      `campaign_${action}`,
      id,
      now,
      id,
      target,
    ),
  ];
  if (action === "cancel")
    statements.push(
      env.DB.prepare(
        "UPDATE messages SET cancel_requested=1,state=CASE WHEN owner_installation_id IS NULL AND state IN('accepted','queued') THEN 'cancelled' ELSE state END,updated_at=? WHERE campaign_id=? AND EXISTS(SELECT 1 FROM campaigns WHERE campaign_id=? AND status='cancelled')",
      ).bind(now, id, id),
    );
  statements.push(
    env.DB.prepare(
      "UPDATE devices SET fcm_pending=1,fcm_next_at=?,wake_revision=wake_revision+1 WHERE installation_id IN(SELECT DISTINCT owner_installation_id FROM messages WHERE campaign_id=?) AND EXISTS(SELECT 1 FROM campaigns WHERE campaign_id=? AND status=?)",
    ).bind(now, id, id, target),
  );
  const changed = await env.DB.batch(statements);
  if (!changed[0]!.meta.changes)
    throw new ApiError(
      409,
      "campaign_state",
      "A concurrent campaign transition won",
    );
  if (target === "running") await expandCampaign(env, id);
  return campaignSummary(
    (await env.DB.prepare("SELECT * FROM campaigns WHERE campaign_id=?")
      .bind(id)
      .first<CampaignRow>())!,
  );
}
