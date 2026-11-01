import type {D1Database,D1PreparedStatement} from "./postgres.ts";
import type { Context } from "npm:hono@4.13.13";
import { application } from "./auth.ts";
import type { AppEnv, Env, Kind, MessageRow } from "./types.ts";
import { PRIORITIES } from "./types.ts";
import {
  ApiError,
  after,
  canonical,
  integer,
  isoNow,
  kind,
  object,
  payloadDigest,
  phone,
  segmentEstimate,
  sha256,
  string,
  timestamp,
  uid,
} from "./util.ts";
export interface NewMessage {
  message_id: string;
  application_id: string;
  kind: Kind;
  to: string;
  text: string;
  payload_digest: string;
  request_digest: string;
  idempotency_key: string;
  priority: number;
  not_after: string;
  available_at: string;
  created_at: string;
  campaign_id?: string;
  otp_challenge_id?: string;
  metadata?: unknown;
  requires_fresh_decision?: boolean;
  eligibility_until?: string;
  segments_estimate: number;
}
export async function makeMessage(
  input: Omit<NewMessage, "payload_digest" | "segments_estimate">,
): Promise<NewMessage> {
  return {
    ...input,
    payload_digest: await payloadDigest(input),
    segments_estimate: segmentEstimate(input.text),
  };
}
const MESSAGE_COLUMNS =
  "message_id,application_id,kind,to_number,text,payload_digest,request_digest,idempotency_key,priority,not_after,available_at,created_at,updated_at,campaign_id,otp_challenge_id,metadata_json,requires_fresh_decision,eligibility_until,segments_estimate";
const ACTIVE_CAMPAIGN =
  "EXISTS(SELECT 1 FROM campaigns c JOIN applications a ON a.application_id=c.application_id WHERE c.campaign_id=? AND c.status='running' AND a.revoked_at IS NULL)";
function messageValues(m: NewMessage) {
  return [
    m.message_id,
    m.application_id,
    m.kind,
    m.to,
    m.text,
    m.payload_digest,
    m.request_digest,
    m.idempotency_key,
    m.priority,
    m.not_after,
    m.available_at,
    m.created_at,
    m.created_at,
    m.campaign_id ?? null,
    m.otp_challenge_id ?? null,
    canonical(m.metadata ?? {}),
    m.requires_fresh_decision ? 1 : 0,
    m.eligibility_until ?? null,
    m.segments_estimate,
  ];
}
export function messageInsert(
  db: D1Database,
  m: NewMessage,
  options: {
    challengeGuard?: string;
    occurrenceGuard?: string;
    campaignGuard?: string;
    ignoreExisting?: boolean;
  } = {},
): D1PreparedStatement {
  const values = messageValues(m),
    marks = values.map(() => "?").join(",");
  const guard = options.challengeGuard
    ? "EXISTS(SELECT 1 FROM otp_challenges WHERE challenge_id=?)"
    : options.occurrenceGuard
      ? "EXISTS(SELECT 1 FROM schedule_occurrences WHERE message_id=?)"
    : options.campaignGuard
      ? ACTIVE_CAMPAIGN
      : null;
  return db
    .prepare(
      `INSERT INTO messages(${MESSAGE_COLUMNS}) ${guard ? `SELECT ${marks} WHERE ${guard}` : `VALUES(${marks})`} ${options.ignoreExisting ? "ON CONFLICT(message_id) DO NOTHING" : ""}`,
    )
    .bind(
      ...values,
      ...(guard ? [options.challengeGuard ?? options.occurrenceGuard ?? options.campaignGuard!] : []),
    );
}
export function campaignMessageInsert(
  db: D1Database,
  messages: NewMessage[],
  campaignId: string,
): D1PreparedStatement {
  const names = MESSAGE_COLUMNS.split(",");
  const rows = messages.map((m) => {
    const values = messageValues(m);
    return Object.fromEntries(
      names.map((name, index) => [name, values[index]]),
    );
  });
  return db
    .prepare(
      `INSERT INTO messages(${MESSAGE_COLUMNS}) SELECT ${names.map((name) => `json_extract(value,'$.${name}')${['priority','requires_fresh_decision','segments_estimate'].includes(name)?'::bigint':''}`).join(",")} FROM json_each(?) WHERE ${ACTIVE_CAMPAIGN} ON CONFLICT(message_id) DO NOTHING`,
    )
    .bind(JSON.stringify(rows), campaignId);
}
export async function existingMessage(
  db: D1Database,
  appId: string,
  key: string,
  digest: string,
): Promise<MessageRow | null> {
  const existing = await db
    .prepare(
      "SELECT * FROM messages WHERE application_id=? AND idempotency_key=?",
    )
    .bind(appId, key)
    .first<MessageRow>();
  if (existing && existing.request_digest !== digest)
    throw new ApiError(
      409,
      "idempotency_conflict",
      "The idempotency key was already used with another payload",
    );
  return existing;
}
export async function createMessage(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const workload = kind(body.kind),
    p = application(c, "messages:write", workload),
    key = string(c.req.header("Idempotency-Key"), "Idempotency-Key", 1, 128);
  const to = phone(body.to),
    text = string(body.text, "text", 1, 2000),
    notAfter = timestamp(body.not_after, "not_after");
  const priority =
      body.priority === undefined
        ? PRIORITIES[workload]
        : integer(body.priority, "priority", 0, 127),
    metadata =
      body.metadata === undefined ? {} : object(body.metadata, "metadata");
  if (canonical(metadata).length > 8192)
    throw new ApiError(413, "too_large", "metadata is too large");
  const requestedId =
    body.message_id === undefined
      ? undefined
      : string(body.message_id, "message_id", 1, 200);
  if (requestedId && !requestedId.startsWith(`${p.id}:`))
    throw new ApiError(
      400,
      "message_namespace",
      `A client message_id must start with ${p.id}:`,
    );
  const digest = await sha256(
    canonical({
      kind: workload,
      to,
      text,
      not_after: notAfter,
      priority,
      metadata,
      message_id: requestedId ?? null,
    }),
  );
  const old = await existingMessage(c.env.DB, p.id, key, digest);
  if (old) return c.json({ message_id: old.message_id, state: old.state }, 202);
  if (notAfter <= isoNow())
    throw new ApiError(400, "expired", "not_after must be in the future");
  const now = isoNow();
  const m = await makeMessage({
    message_id:
      requestedId ?? `msg_${(await sha256(`${p.id}\n${key}`)).slice(0, 40)}`,
    application_id: p.id,
    kind: workload,
    to,
    text,
    request_digest: digest,
    idempotency_key: key,
    priority,
    not_after: notAfter,
    available_at: now,
    created_at: now,
    metadata,
    requires_fresh_decision:
      workload === "operation" && metadata.immutable_facts !== true,
  });
  try {
    if (workload === "campaign") {
      const campaignId = uid("campaign");
      m.campaign_id = campaignId;
      m.payload_digest = await payloadDigest(m);
      await c.env.DB.batch([
        c.env.DB.prepare(
          "INSERT INTO campaigns(campaign_id,application_id,name,text,recipients_json,recipient_count,expansion_cursor,request_key,request_digest,status,not_after,scheduled_at,segments_per_minute,segments_per_message,created_at,updated_at) VALUES(?,?,?,?,?,1,1,?,?,'running',?,?,30,?,?,?)",
        ).bind(
          campaignId,
          p.id,
          "Direct campaign message",
          text,
          JSON.stringify([to]),
          `direct:${key}`,
          digest,
          notAfter,
          now,
          m.segments_estimate,
          now,
          now,
        ),
        messageInsert(c.env.DB, m),
      ]);
    } else await messageInsert(c.env.DB, m).run();
  } catch (error) {
    const raced = await existingMessage(c.env.DB, p.id, key, digest);
    if (raced)
      return c.json({ message_id: raced.message_id, state: raced.state }, 202);
    if (/UNIQUE/.test(String(error)))
      throw new ApiError(
        409,
        "message_conflict",
        "The message ID already exists",
      );
    throw error;
  }
  return c.json({ message_id: m.message_id, state: "accepted" }, 202);
}
export function summary(m: MessageRow & { parts_total?: number | null }) {
  return {
    message_id: m.message_id,
    application_id: m.application_id,
    kind: m.kind,
    to: m.to_number,
    text: m.content_redacted_at ? "[Content removed by retention policy]" : m.kind === "otp" ? "[OTP content hidden]" : m.text,
    content_redacted_at: m.content_redacted_at ?? null,
    content_hold: !!m.content_hold,
    payload_digest: m.payload_digest,
    priority: m.priority,
    not_after: m.not_after,
    available_at: m.available_at,
    state: m.state,
    owner_installation_id: m.owner_installation_id,
    assignment_version: m.assignment_version,
    cancel_requested: !!m.cancel_requested,
    created_at: m.created_at,
    updated_at: m.updated_at,
    phone_accepted_at: m.phone_accepted_at,
    campaign_id: m.campaign_id,
    parts_total: m.parts_total ?? null,
    requires_fresh_decision: !!m.requires_fresh_decision,
    eligibility_until: m.eligibility_until,
    metadata: m.kind === "otp" ? {} : JSON.parse(m.metadata_json),
  };
}
export async function messageDetail(env: Env, id: string, appId?: string) {
  const row = await env.DB.prepare(
    `SELECT m.*,(SELECT MAX(parts_total) FROM attempts a WHERE a.message_id=m.message_id) AS parts_total FROM messages m WHERE m.message_id=? ${appId ? "AND m.application_id=?" : ""}`,
  )
    .bind(id, ...(appId ? [appId] : []))
    .first<MessageRow>();
  if (!row) throw new ApiError(404, "not_found", "Message not found");
  const results = await env.DB.batch<Record<string, unknown>>([
    env.DB.prepare(
      "SELECT * FROM attempts WHERE message_id=? ORDER BY updated_at,attempt_id",
    ).bind(id),
    env.DB.prepare(
      "SELECT * FROM message_parts WHERE message_id=? ORDER BY attempt_id,part_index",
    ).bind(id),
    env.DB.prepare(
      "SELECT event_id,type,attempt_id,at,received_at,part_index,parts_total,error_code,detail_json,detail_redacted_at FROM device_events WHERE message_id=? ORDER BY received_at,event_id",
    ).bind(id),
    env.DB.prepare(
      "SELECT * FROM audit_events WHERE resource_id=? ORDER BY at,event_id",
    ).bind(id),
  ]);
  return {
    message: summary(row),
    attempts: results[0]!.results,
    parts: results[1]!.results,
    history: results[2]!.results.map((event) => {
      const { detail_json, ...rest } = event;
      return { ...rest, detail: JSON.parse(String(detail_json)) };
    }),
    audit: results[3]!.results,
  };
}
export async function cancelMessage(
  env: Env,
  id: string,
  actor: { type: string; id: string },
  appId?: string,
) {
  const row = await env.DB.prepare(
    `SELECT * FROM messages WHERE message_id=? ${appId ? "AND application_id=?" : ""}`,
  )
    .bind(id, ...(appId ? [appId] : []))
    .first<MessageRow>();
  if (!row) throw new ApiError(404, "not_found", "Message not found");
  const now = isoNow();
  await env.DB.batch([
    env.DB.prepare(
      "UPDATE messages SET cancel_requested=1,state=CASE WHEN owner_installation_id IS NULL AND state IN ('accepted','queued') THEN 'cancelled' ELSE state END,updated_at=? WHERE message_id=?",
    ).bind(now, id),
    env.DB.prepare(
      "INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)",
    ).bind(uid("audit"), actor.type, actor.id, "cancel_requested", id, now),
    env.DB.prepare(
      "UPDATE devices SET fcm_pending=1,fcm_next_at=?,wake_revision=wake_revision+1 WHERE installation_id=?",
    ).bind(now, row.owner_installation_id),
  ]);
  const current = (await env.DB.prepare(
    "SELECT * FROM messages WHERE message_id=?",
  )
    .bind(id)
    .first<MessageRow>())!;
  const evidence = await env.DB.prepare(
    "SELECT 1 AS present FROM attempts WHERE message_id=? AND (handoff_at IS NOT NULL OR unknown_observed=1) UNION SELECT 1 FROM message_parts WHERE message_id=? LIMIT 1",
  )
    .bind(id, id)
    .first();
  return {
    message_id: id,
    state: current.state,
    cancel_requested: true,
    cancellation:
      current.state === "cancelled"
        ? "cancelled_before_handoff"
        : current.state === "outcome_unknown"
          ? "outcome_unknown"
          : evidence
            ? "too_late"
            : "cancel_requested",
  };
}
export async function updateEligibility(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = application(c, "messages:write", "operation"),
    id = c.req.param("id");
  if (typeof body.eligible !== "boolean")
    throw new ApiError(400, "invalid_request", "eligible must be boolean");
  const now = isoNow(),
    until = body.eligible ? timestamp(body.valid_until, "valid_until") : null;
  if (until && (until <= now || Date.parse(until) > Date.now() + 60_000))
    throw new ApiError(
      400,
      "invalid_request",
      "Eligibility must expire within 60 seconds",
    );
  const result = await c.env.DB.prepare(
    "UPDATE messages SET eligibility_until=?,updated_at=? WHERE message_id=? AND application_id=? AND kind='operation' AND requires_fresh_decision=1 RETURNING message_id",
  )
    .bind(until, now, id, p.id)
    .all();
  if (!result.results.length)
    throw new ApiError(404, "not_found", "State-dependent operation not found");
  return c.json({
    message_id: id,
    eligible: body.eligible,
    eligibility_until: until,
  });
}
export async function contribution(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = application(c, "contributions", "receipt"),
    eventId = string(body.event_id, "event_id", 1, 160),
    recipient = phone(body.recipient);
  const facts = {
    event_id: eventId,
    group_id: string(body.group_id, "group_id", 1, 160),
    group_name: string(body.group_name, "group_name", 1, 80),
    amount_rwf: integer(body.amount_rwf, "amount_rwf", 1),
    member_total_rwf: integer(body.member_total_rwf, "member_total_rwf"),
    group_total_rwf: integer(body.group_total_rwf, "group_total_rwf"),
    scope: string(body.scope, "scope", 1, 80),
    ledger_version: integer(body.ledger_version, "ledger_version"),
    recorded_at: timestamp(body.recorded_at, "recorded_at"),
    locale:
      body.locale === undefined ? "en" : string(body.locale, "locale", 2, 12),
  };
  if (facts.locale !== "en")
    throw new ApiError(
      400,
      "template_unavailable",
      "Only the reviewed English receipt template is bundled; add reviewed locale templates before enabling another language",
    );
  const factsJson = canonical(facts),
    factsDigest = await sha256(factsJson),
    key = `contribution:${eventId}:${recipient}`,
    requestDigest = await sha256(canonical({ facts, recipient }));
  const existing = await existingMessage(c.env.DB, p.id, key, requestDigest);
  if (existing)
    return c.json(
      {
        message_id: existing.message_id,
        state: existing.state,
        event_id: eventId,
      },
      202,
    );
  const oldFacts = await c.env.DB.prepare("SELECT content_redacted_at FROM contribution_events WHERE application_id=? AND event_id=?")
    .bind(p.id,eventId).first<{content_redacted_at:string|null}>();
  if (oldFacts?.content_redacted_at)
    throw new ApiError(409,"source_facts_redacted","This archived event cannot create another receipt; original recipient replays still return their existing message");
  const now = isoNow(),
    ref = (await sha256(`${p.id}\n${eventId}`)).slice(0, 8).toUpperCase(),
    fmt = (v: number) =>
      new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(v);
  const text = `COLLECT: RWF ${fmt(facts.amount_rwf)} received for ${facts.group_name}. Your contributions: RWF ${fmt(facts.member_total_rwf)}. Group contributions: RWF ${fmt(facts.group_total_rwf)}. Scope: ${facts.scope}. As of ${facts.recorded_at}. Ref ${ref}.`;
  const m = await makeMessage({
    message_id: `msg_${(await sha256(`${p.id}\n${key}`)).slice(0, 40)}`,
    application_id: p.id,
    kind: "receipt",
    to: recipient,
    text,
    request_digest: requestDigest,
    idempotency_key: key,
    priority: 80,
    not_after: after(86_400_000),
    available_at: now,
    created_at: now,
    metadata: facts,
  });
  try {
    await c.env.DB.batch([
      c.env.DB.prepare(
        "INSERT INTO contribution_events(application_id,event_id,facts_json,facts_digest,created_at) VALUES(?,?,?,?,?) ON CONFLICT(application_id,event_id) DO UPDATE SET facts_json=excluded.facts_json,facts_digest=excluded.facts_digest",
      ).bind(p.id, eventId, factsJson, factsDigest, now),
      messageInsert(c.env.DB, m),
      c.env.DB.prepare(
        "INSERT INTO contribution_receipts(application_id,event_id,recipient,message_id) VALUES(?,?,?,?)",
      ).bind(p.id, eventId, recipient, m.message_id),
    ]);
  } catch (error) {
    const raced = await existingMessage(c.env.DB, p.id, key, requestDigest);
    if (raced)
      return c.json(
        { message_id: raced.message_id, state: raced.state, event_id: eventId },
        202,
      );
    if (/event_immutable|UNIQUE/.test(String(error)))
      throw new ApiError(
        409,
        "immutable_event_conflict",
        "The contribution event already exists with different facts",
      );
    throw error;
  }
  return c.json(
    { message_id: m.message_id, state: "accepted", event_id: eventId },
    202,
  );
}
