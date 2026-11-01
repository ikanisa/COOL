import type { Context } from "npm:hono@4.13.13";
import { admin, adminActor } from "./auth.ts";
import type { AppEnv, Env } from "./types.ts";
import { ApiError, integer, isoNow, string, uid } from "./util.ts";

/** Content minimization only. Identities and delivery/replay evidence remain. */
const SAFE_STATES = "'sent','delivered','delivery_unconfirmed','failed','expired','cancelled'";
function policy(env: Env): { days: number; cutoff: string } | null {
  const input = env.MESSAGE_RETENTION_DAYS;
  if (input === undefined || input === "" || input === "0") return null;
  if (!/^\d+$/.test(input) || Number(input)<1 || Number(input)>3650)
    throw new ApiError(503,"invalid_retention_policy","MESSAGE_RETENTION_DAYS must be 0 (disabled) or 1..3650");
  const days=Number(input);
  return {days,cutoff:new Date(Date.now()-days*86_400_000).toISOString()};
}
// Deadline AND last observed activity must be old. Unknown/in-progress/partial
// jobs cannot be redacted by the general policy, even after a long outage.
const MESSAGE_ELIGIBLE = `m.content_redacted_at IS NULL AND m.content_hold=0
 AND m.state IN(${SAFE_STATES}) AND m.not_after<=? AND m.updated_at<=?
 AND NOT EXISTS(SELECT 1 FROM campaigns c WHERE c.campaign_id=m.campaign_id AND c.content_hold=1)`;
const CAMPAIGN_ELIGIBLE = `c.content_redacted_at IS NULL AND c.content_hold=0
 AND c.status IN('completed','cancelled') AND c.not_after<=? AND c.updated_at<=?
 AND NOT EXISTS(SELECT 1 FROM messages m WHERE m.campaign_id=c.campaign_id
   AND (m.content_redacted_at IS NULL OR m.content_hold=1))`;
const FACTS_ELIGIBLE = `e.content_redacted_at IS NULL AND e.created_at<=?
 AND EXISTS(SELECT 1 FROM contribution_receipts r WHERE r.application_id=e.application_id AND r.event_id=e.event_id)
 AND NOT EXISTS(SELECT 1 FROM contribution_receipts r JOIN messages m ON m.message_id=r.message_id
   WHERE r.application_id=e.application_id AND r.event_id=e.event_id
   AND (m.content_redacted_at IS NULL OR m.content_hold=1))`;
const REDACTED_DETAIL = `CASE WHEN json_extract(detail_json,'$.phase')='delivery' THEN '{"phase":"delivery"}' ELSE '{}' END`;

export async function previewRetention(c:Context<AppEnv>) {
  admin(c,"retention:manage");
  const config=policy(c.env);
  if (!config) return c.json({enabled:false,automatic:false,days:0,notice:"General content redaction is disabled. Expired OTP content is separately scrubbed by maintenance."});
  const {cutoff,days}=config;
  const [messages,campaigns,facts,held,uncertain] = await c.env.DB.batch([
    c.env.DB.prepare(`SELECT kind,COUNT(*) AS count FROM messages m WHERE ${MESSAGE_ELIGIBLE} GROUP BY kind`).bind(cutoff,cutoff),
    c.env.DB.prepare(`SELECT COUNT(*) AS count FROM campaigns c WHERE ${CAMPAIGN_ELIGIBLE}`).bind(cutoff,cutoff),
    c.env.DB.prepare(`SELECT COUNT(*) AS count FROM contribution_events e WHERE ${FACTS_ELIGIBLE}`).bind(cutoff),
    c.env.DB.prepare("SELECT COUNT(*) AS count FROM messages WHERE content_hold=1 AND content_redacted_at IS NULL"),
    c.env.DB.prepare("SELECT COUNT(*) AS count FROM messages WHERE state IN('outcome_unknown','handoff_started','partial') AND content_redacted_at IS NULL"),
  ]);
  return c.json({enabled:true,automatic:c.env.RETENTION_AUTO_PURGE==="true",days,cutoff,
    eligible_messages:messages!.results,eligible_campaigns:campaigns!.results[0]!.count,
    eligible_fact_records:facts!.results[0]!.count,held_messages:held!.results[0]!.count,
    uncertain_or_incomplete_messages:uncertain!.results[0]!.count,
    notice:"Preview only. Linked campaign/fact copies become eligible after all child bodies are redacted. Recipient identifiers and delivery/replay evidence are retained."});
}

export async function purgeRetention(env:Env,actor:{type:string;id:string},batchSize=100) {
  const config=policy(env);
  if (!config) return {enabled:false,redacted_messages:0,redacted_campaigns:0,redacted_fact_records:0};
  integer(batchSize,"batch_size",1,200);
  const {cutoff}=config, now=isoNow(), runId=uid("retention");
  const selected=await env.DB.prepare(`SELECT m.message_id FROM messages m WHERE ${MESSAGE_ELIGIBLE}
    ORDER BY m.not_after,m.message_id LIMIT ?`).bind(cutoff,cutoff,batchSize).all<{message_id:string}>();
  const ids=JSON.stringify(selected.results.map(r=>r.message_id));
  const result=await env.DB.batch([
    // Audit the eligible rows first inside the same atomic transaction. This
    // avoids attributing a prior run's redaction to this run when wall-clock
    // timestamps coincide. A failed later write rolls back the audit too.
    env.DB.prepare(`INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at)
      SELECT ?||':'||m.message_id,?,?,'message_content_redacted',m.message_id,? FROM messages m
      WHERE m.message_id IN(SELECT value FROM json_each(?)) AND ${MESSAGE_ELIGIBLE}`)
      .bind(runId,actor.type,actor.id,now,ids,cutoff,cutoff),
    // Recheck eligibility in the transaction: a newly placed hold or late
    // callback between selection and this transaction preserves content.
    env.DB.prepare(`UPDATE messages AS m SET text='',metadata_json='{}',content_redacted_at=?
      WHERE m.message_id IN(SELECT value FROM json_each(?)) AND ${MESSAGE_ELIGIBLE} RETURNING message_id`)
      .bind(now,ids,cutoff,cutoff),
    env.DB.prepare(`UPDATE device_events SET detail_json=${REDACTED_DETAIL},detail_redacted_at=?
      WHERE event_id IN(SELECT d.event_id FROM device_events d
      WHERE d.detail_redacted_at IS NULL AND EXISTS(SELECT 1 FROM messages m WHERE m.message_id=d.message_id AND m.content_redacted_at IS NOT NULL)
      ORDER BY d.received_at,d.event_id LIMIT 500)`)
      .bind(now),
    // A separate bounded cleanup catches a cancelled draft with zero children,
    // and fact/campaign copies whose last child was redacted in an earlier run.
    env.DB.prepare(`UPDATE campaigns SET text='',recipients_json='[]',content_redacted_at=?
      WHERE campaign_id IN(SELECT c.campaign_id FROM campaigns c WHERE ${CAMPAIGN_ELIGIBLE}
      ORDER BY c.not_after,c.campaign_id LIMIT ?) RETURNING campaign_id`).bind(now,cutoff,cutoff,batchSize),
    env.DB.prepare(`UPDATE contribution_events SET facts_json='{}',content_redacted_at=?
      WHERE (application_id,event_id) IN(SELECT e.application_id,e.event_id FROM contribution_events e
      WHERE ${FACTS_ELIGIBLE} ORDER BY e.created_at,e.application_id,e.event_id LIMIT ?) RETURNING application_id,event_id`)
      .bind(now,cutoff,batchSize),
    env.DB.prepare("INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)")
      .bind(runId,actor.type,actor.id,"retention_run",runId,now),
  ]);
  return {enabled:true,run_id:runId,cutoff,batch_size:batchSize,
    redacted_callback_rows:Number(result[2]!.meta.changes),callback_row_limit:500,
    redacted_messages:result[1]!.results.length,redacted_campaigns:result[3]!.results.length,
    redacted_fact_records:result[4]!.results.length};
}
export async function runRetention(c:Context<AppEnv>,body:Record<string,unknown>) {
  admin(c,"retention:manage");
  if (body.confirm!=="redact_message_content")
    throw new ApiError(400,"confirmation_required","Set confirm to redact_message_content after reviewing the preview");
  if (!policy(c.env)) throw new ApiError(409,"retention_disabled","Configure a retention period before running content redaction");
  return c.json(await purgeRetention(c.env,adminActor(c),integer(body.batch_size??100,"batch_size",1,200)));
}
export async function changeContentHold(c:Context<AppEnv>,body:Record<string,unknown>) {
  admin(c,"retention:manage");
  if (body.resource_type!=="message" && body.resource_type!=="campaign")
    throw new ApiError(400,"invalid_request","resource_type must be message or campaign");
  if (typeof body.hold!=="boolean") throw new ApiError(400,"invalid_request","hold must be boolean");
  const id=string(body.resource_id,"resource_id",1,200);
  const table=body.resource_type==="message"?"messages":"campaigns";
  const column=body.resource_type==="message"?"message_id":"campaign_id";
  const now=isoNow(),actor=adminActor(c);
  const result=await c.env.DB.batch([
    c.env.DB.prepare(`UPDATE ${table} SET content_hold=? WHERE ${column}=? AND content_redacted_at IS NULL RETURNING ${column}`)
      .bind(body.hold?1:0,id),
    c.env.DB.prepare(`INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at)
      SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM ${table} WHERE ${column}=? AND content_redacted_at IS NULL AND content_hold=?)`)
      .bind(uid("audit"),actor.type,actor.id,body.hold?"content_hold_set":"content_hold_released",id,now,id,body.hold?1:0),
  ]);
  if (!result[0]!.results.length) throw new ApiError(409,"content_unavailable","Resource does not exist or its content has already been redacted");
  return c.json({resource_type:body.resource_type,resource_id:id,hold:body.hold});
}

/** Invalidate secret material only after dispatch is closed AND the challenge
 * has expired/been consumed. Preserve rows used by replay/rate-limit controls.
 * A manual content hold intentionally does not preserve expired OTP secrets.
 */
export async function scrubExpiredOtp(env:Env):Promise<void> {
  const now=isoNow();
  await env.DB.batch([
    env.DB.prepare(`UPDATE messages SET text='',metadata_json='{}',content_redacted_at=?
      WHERE message_id IN(SELECT m.message_id FROM messages m WHERE m.kind='otp'
      AND m.content_redacted_at IS NULL AND m.not_after<=?
      AND (m.otp_challenge_id IS NULL OR EXISTS(SELECT 1 FROM otp_challenges o WHERE o.challenge_id=m.otp_challenge_id
        AND (o.expires_at<=? OR o.consumed_at IS NOT NULL))) ORDER BY m.not_after LIMIT 200)`)
      .bind(now,now,now),
    env.DB.prepare(`UPDATE otp_challenges SET verifier='' WHERE challenge_id IN(
      SELECT challenge_id FROM otp_challenges WHERE verifier<>'' AND (expires_at<=? OR consumed_at IS NOT NULL)
      ORDER BY expires_at LIMIT 200)`).bind(now),
    env.DB.prepare(`UPDATE device_events SET detail_json=${REDACTED_DETAIL},detail_redacted_at=?
      WHERE event_id IN(SELECT d.event_id FROM device_events d JOIN messages m ON m.message_id=d.message_id
      WHERE d.detail_redacted_at IS NULL AND m.kind='otp' AND m.content_redacted_at IS NOT NULL
      ORDER BY d.received_at LIMIT 200)`).bind(now),
    // Session records can be dropped after their replay window because the
    // unpredictable token is not usable without a live row. Audit rows remain.
    env.DB.prepare("DELETE FROM staff_sessions WHERE session_id IN(SELECT session_id FROM staff_sessions WHERE expires_at<? ORDER BY expires_at LIMIT 200)")
      .bind(new Date(Date.now()-86_400_000).toISOString()),
  ]);
}
