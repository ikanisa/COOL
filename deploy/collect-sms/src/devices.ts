import type { Context } from "npm:hono@4.13.13";
import { device } from "./auth.ts";
import type {
  AppEnv,
  DeviceEvent,
  DeviceRow,
  EventType,
  Job,
  MessageRow,
} from "./types.ts";
import { EVENT_TYPES } from "./types.ts";
import {
  ApiError,
  after,
  array,
  canonical,
  integer,
  isoNow,
  object,
  sha256,
  string,
  timestamp,
  uid,
} from "./util.ts";
export async function registerDevice(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = device(c),
    row = (await c.env.DB.prepare(
      "SELECT * FROM devices WHERE installation_id=?",
    )
      .bind(p.id)
      .first<DeviceRow>())!;
  if (typeof body.ready !== "boolean")
    throw new ApiError(400, "invalid_request", "ready must be boolean");
  if (
    body.allowed_kinds !== undefined &&
    array(body.allowed_kinds, "allowed_kinds", 4).some(
      (k) => !p.allowedKinds.includes(k as never),
    )
  )
    throw new ApiError(
      403,
      "device_scope",
      "The device cannot add allowed workloads",
    );
  const slot =
    body.sim_slot === undefined
      ? row.sim_slot
      : integer(body.sim_slot, "sim_slot", 0, 1);
  if (row.sim_slot !== null && slot !== row.sim_slot)
    throw new ApiError(
      409,
      "sim_configuration",
      "The reported SIM slot differs from operator configuration",
    );
  const fcm =
      body.fcm_token === undefined
        ? row.fcm_token
        : body.fcm_token === null
          ? null
          : string(body.fcm_token, "fcm_token", 1, 4096),
    appVersion =
      body.app_version === undefined
        ? row.app_version
        : string(body.app_version, "app_version", 1, 80),
    osVersion =
      body.os_version === undefined
        ? row.os_version
        : string(body.os_version, "os_version", 1, 80),
    health =
      body.health === undefined
        ? row.health_json
        : canonical(object(body.health, "health"));
  if (health.length > 8192)
    throw new ApiError(413, "too_large", "Health report is too large");
  const now = isoNow();
  const updates = [
    "ready=?",
    "last_seen_at=?",
    "app_version=?",
    "os_version=?",
    "sim_slot=?",
    "health_json=?",
  ];
  const bindings: (number | string | null)[] = [
    body.ready ? 1 : 0,
    now,
    appVersion,
    osVersion,
    slot,
    health,
  ];
  let reportedTokenHash: string | null = null;
  if (body.fcm_token !== undefined) {
    reportedTokenHash = fcm === null ? null : await sha256(fcm);
    // Compare against the row at mutation time. An omitted token never rewrites
    // a concurrent rotation; unchanged/retired tokens never rearm idle pushes.
    const unchanged = "(? IS fcm_token OR ?=fcm_rejected_token_hash)";
    updates.push(
      `fcm_pending=CASE WHEN ? IS NULL THEN 0 WHEN ${unchanged} THEN fcm_pending ELSE 1 END`,
      `fcm_next_at=CASE WHEN ? IS NULL THEN NULL WHEN ${unchanged} THEN fcm_next_at ELSE ? END`,
      `fcm_attempts=CASE WHEN ${unchanged} THEN fcm_attempts ELSE 0 END`,
      `fcm_last_error=CASE WHEN ${unchanged} THEN fcm_last_error ELSE NULL END`,
      `wake_revision=wake_revision+CASE WHEN ${unchanged} THEN 0 ELSE 1 END`,
      "fcm_token=CASE WHEN ?=fcm_rejected_token_hash THEN fcm_token ELSE ? END",
      "fcm_rejected_token_hash=CASE WHEN ? IS NULL OR ?=fcm_rejected_token_hash THEN fcm_rejected_token_hash ELSE NULL END",
    );
    bindings.push(
      fcm,
      fcm,
      reportedTokenHash,
      fcm,
      fcm,
      reportedTokenHash,
      now,
      fcm,
      reportedTokenHash,
      fcm,
      reportedTokenHash,
      fcm,
      reportedTokenHash,
      reportedTokenHash,
      fcm,
      fcm,
      reportedTokenHash,
    );
  }
  const updated = await c.env.DB.prepare(
    `UPDATE devices SET ${updates.join(",")} WHERE installation_id=? AND revoked_at IS NULL RETURNING fcm_token,fcm_rejected_token_hash`,
  )
    .bind(...bindings, p.id)
    .first<{
      fcm_token: string | null;
      fcm_rejected_token_hash: string | null;
    }>();
  if (!updated)
    throw new ApiError(
      401,
      "device_unavailable",
      "This device installation is no longer active",
    );
  return c.json({
    installation_id: p.id,
    server_time: now,
    allowed_kinds: p.allowedKinds,
    sim_slot: slot,
    ready: body.ready,
    fcm_token_rejected:
      reportedTokenHash !== null &&
      reportedTokenHash === updated.fcm_rejected_token_hash,
  });
}
const ELIGIBLE = `m.content_redacted_at IS NULL AND m.cancel_requested=0 AND m.not_after>? AND m.available_at<=?
AND EXISTS(SELECT 1 FROM applications a WHERE a.application_id=m.application_id AND a.revoked_at IS NULL)
AND (m.requires_fresh_decision=0 OR m.eligibility_until>?)
AND (m.campaign_id IS NULL OR EXISTS(SELECT 1 FROM campaigns c WHERE c.campaign_id=m.campaign_id AND c.status='running' AND c.scheduled_at<=? AND c.not_after>?))
AND (m.otp_challenge_id IS NULL OR EXISTS(SELECT 1 FROM otp_challenges o JOIN otp_slots s ON s.current_challenge_id=o.challenge_id WHERE o.challenge_id=m.otp_challenge_id AND o.consumed_at IS NULL AND o.expires_at>?))`;
function job(row: MessageRow, slot: number | null): Job {
  return {
    message_id: row.message_id,
    application_id: row.application_id,
    kind: row.kind,
    to: row.to_number,
    text: row.text,
    payload_digest: row.payload_digest,
    priority: row.priority,
    not_after: row.not_after,
    available_at: row.available_at,
    owner_installation_id: row.owner_installation_id!,
    assignment_version: row.assignment_version,
    ...(slot === null ? {} : { sim_slot: slot }),
    ...(row.campaign_id ? { campaign_id: row.campaign_id } : {}),
  };
}
export async function pullJobs(c: Context<AppEnv>) {
  const p = device(c),
    limit = integer(Number(c.req.query("limit") ?? 10), "limit", 1, 25),
    now = isoNow(),
    row = await c.env.DB.prepare(
      "SELECT * FROM devices WHERE installation_id=? AND revoked_at IS NULL",
    )
      .bind(p.id)
      .first<DeviceRow>();
  if (c.env.DISPATCH_PAUSED === "true" || !row?.ready)
    return c.json({
      server_time: now,
      jobs: [],
      cancellations: [],
      dispatch_permit_until: now,
    });
  await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE devices SET last_seen_at=? WHERE installation_id=?",
    ).bind(now, p.id),
    c.env.DB.prepare(
      "UPDATE messages SET state='expired',updated_at=? WHERE owner_installation_id IS NULL AND not_after<=? AND state='accepted'",
    ).bind(now, now),
    c.env.DB.prepare(
      `UPDATE messages SET owner_installation_id=?,assignment_version=assignment_version+1,state='assigned',updated_at=? WHERE owner_installation_id IS NULL AND message_id IN(
SELECT m.message_id FROM messages m WHERE m.owner_installation_id IS NULL AND m.state='accepted' AND ${ELIGIBLE}
AND EXISTS(SELECT 1 FROM devices d,json_each(d.allowed_kinds) k WHERE d.installation_id=? AND d.ready=1 AND d.revoked_at IS NULL AND k.value=m.kind)
ORDER BY CASE m.kind WHEN 'otp' THEN 4 WHEN 'receipt' THEN 3 WHEN 'operation' THEN 2 ELSE 1 END DESC,m.priority DESC,m.created_at,m.message_id
LIMIT MAX(0,?-(SELECT COUNT(*) FROM messages held WHERE held.owner_installation_id=? AND held.state IN('assigned','phone_accepted','queued') AND ${ELIGIBLE.replace(/\bm\./g, "held.")})))`,
    ).bind(
      p.id,
      now,
      now,
      now,
      now,
      now,
      now,
      now,
      p.id,
      limit,
      p.id,
      now,
      now,
      now,
      now,
      now,
      now,
    ),
  ]);
  const results = await c.env.DB.batch([
    c.env.DB.prepare(
      `SELECT m.* FROM messages m WHERE m.owner_installation_id=? AND m.state IN('assigned','phone_accepted','queued') AND ${ELIGIBLE} ORDER BY CASE m.kind WHEN 'otp' THEN 4 WHEN 'receipt' THEN 3 WHEN 'operation' THEN 2 ELSE 1 END DESC,m.priority DESC,m.created_at,m.message_id LIMIT ?`,
    ).bind(p.id, now, now, now, now, now, now, limit),
    c.env.DB.prepare(
      "SELECT message_id,assignment_version FROM messages WHERE owner_installation_id=? AND cancel_requested=1 AND state IN('assigned','phone_accepted','queued') ORDER BY created_at LIMIT 100",
    ).bind(p.id),
  ]);
  return c.json({
    server_time: now,
    jobs: (results[0]!.results as unknown as MessageRow[]).map((m) =>
      job(m, row.sim_slot),
    ),
    cancellations: results[1]!.results,
    dispatch_permit_until: after(30_000),
  });
}
export async function acceptJobs(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = device(c),
    items = array(body.acceptances, "acceptances", 25),
    now = isoNow();
  const accepted = items.map((raw) => {
    const a = object(raw, "acceptance");
    return {
      message_id: string(a.message_id, "message_id", 1, 200),
      payload_digest: string(a.payload_digest, "payload_digest", 64, 64),
      assignment_version: integer(
        a.assignment_version,
        "assignment_version",
        1,
      ),
      accepted_at: timestamp(a.accepted_at, "accepted_at"),
    };
  });
  if (accepted.length)
    await c.env.DB.batch(
      accepted.map((a) =>
        c.env.DB.prepare(
          "INSERT INTO acceptances(message_id,assignment_version,installation_id,payload_digest,accepted_at,received_at) VALUES(?,?,?,?,?,?) ON CONFLICT(message_id,assignment_version) DO NOTHING",
        ).bind(
          a.message_id,
          a.assignment_version,
          p.id,
          a.payload_digest,
          a.accepted_at,
          now,
        ),
      ),
    );
  return c.json({
    acknowledged: [...new Set(accepted.map((a) => a.message_id))],
  });
}
function parseEvent(raw: unknown): DeviceEvent {
  const e = object(raw, "event"),
    type = string(e.type, "type") as EventType;
  if (!EVENT_TYPES.includes(type))
    throw new ApiError(400, "invalid_request", "Unsupported device event type");
  const out: DeviceEvent = {
    event_id: string(e.event_id, "event_id", 1, 200),
    message_id: string(e.message_id, "message_id", 1, 200),
    assignment_version: integer(e.assignment_version, "assignment_version", 1),
    type,
    at: timestamp(e.at, "at"),
  };
  if (e.attempt_id !== undefined)
    out.attempt_id = string(e.attempt_id, "attempt_id", 1, 160);
  if (e.part_index !== undefined)
    out.part_index = integer(e.part_index, "part_index", 0, 254);
  if (e.parts_total !== undefined)
    out.parts_total = integer(e.parts_total, "parts_total", 1, 255);
  if (e.error_code !== undefined)
    out.error_code = string(e.error_code, "error_code", 1, 160);
  if (e.detail !== undefined) {
    if (canonical(e.detail).length > 2048)
      throw new ApiError(413, "too_large", "Event detail is too large");
    out.detail = e.detail;
  }
  if (
    (type === "handoff_started" ||
      type.startsWith("part_") ||
      out.part_index !== undefined) &&
    !out.attempt_id
  )
    throw new ApiError(
      400,
      "invalid_request",
      "This event requires attempt_id",
    );
  if (type === "handoff_started" && out.parts_total === undefined)
    throw new ApiError(400, "invalid_request", "Handoff requires parts_total");
  if (type.startsWith("part_") && out.part_index === undefined)
    throw new ApiError(
      400,
      "invalid_request",
      "Part events require part_index",
    );
  if (
    out.part_index !== undefined &&
    out.parts_total !== undefined &&
    out.part_index >= out.parts_total
  )
    throw new ApiError(
      400,
      "invalid_request",
      "part_index must be less than parts_total",
    );
  if (
    (out.error_code === "ABORTED_BEFORE_CALL" && type !== "failed") ||
    (out.error_code === "DEADLINE_BEFORE_CALL" && type !== "expired")
  )
    throw new ApiError(
      400,
      "invalid_request",
      "Pre-call abort code does not match its terminal event",
    );
  return out;
}
export async function deviceEvents(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  const p = device(c),
    events = array(body.events, "events", 25).map(parseEvent),
    now = isoNow(),
    prepared = await Promise.all(
      events.map(async (e) => ({
        e,
        digest: await sha256(canonical({ ...e, installation_id: p.id })),
      })),
    );
  if (prepared.length)
    await c.env.DB.batch(
      prepared.map(({ e, digest }) =>
        c.env.DB.prepare(
          `INSERT INTO device_events(event_id,message_id,installation_id,assignment_version,attempt_id,type,at,received_at,part_index,parts_total,error_code,detail_json,payload_digest) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(event_id) DO UPDATE SET payload_digest=excluded.payload_digest`,
        ).bind(
          e.event_id,
          e.message_id,
          p.id,
          e.assignment_version,
          e.attempt_id ?? null,
          e.type,
          e.at,
          now,
          e.part_index ?? null,
          e.parts_total ?? null,
          e.error_code ?? null,
          canonical(e.detail ?? null),
          digest,
        ),
      ),
    );
  return c.json({ acknowledged: [...new Set(events.map((e) => e.event_id))] });
}
export async function messagePermit(c: Context<AppEnv>) {
  const p = device(c),
    id = c.req.param("id"),
    now = isoNow(),
    m = await c.env.DB.prepare(
      "SELECT * FROM messages WHERE message_id=? AND owner_installation_id=?",
    )
      .bind(id, p.id)
      .first<MessageRow>();
  if (!m) throw new ApiError(404, "not_found", "Assigned message not found");
  const reportedParts=c.req.query("parts_total");
  const parts=reportedParts===undefined?m.segments_estimate:integer(Number(reportedParts),"parts_total",1,255);
  const response = (allowed: boolean, until = now) =>
    c.json({
      allowed,
      parts_total: parts,
      server_time: now,
      dispatch_permit_until: until,
      cancel_requested: !!m.cancel_requested,
      assignment_version: m.assignment_version,
    });
  const eligible = await c.env.DB.prepare(
    `SELECT m.message_id FROM messages m WHERE m.message_id=? AND m.owner_installation_id=? AND m.state IN('assigned','phone_accepted','queued') AND ${ELIGIBLE} AND EXISTS(SELECT 1 FROM devices WHERE installation_id=? AND ready=1 AND revoked_at IS NULL)`,
  )
    .bind(id, p.id, now, now, now, now, now, now, p.id)
    .first();
  if (c.env.DISPATCH_PAUSED === "true" || !eligible ||
      (c.env.REQUIRE_ACTUAL_PARTS === "true" && reportedParts === undefined))
    return response(false);
  const slot=await c.env.DB.prepare("SELECT slot_start FROM otp_capacity_reservations WHERE message_id=?").bind(id).first<{slot_start:number}>();
  if(slot&&slot.slot_start>Date.now())return response(false);
  let until = new Date(
    Math.min(
      Date.now() + 30_000,
      Date.parse(m.not_after),
      m.requires_fresh_decision
        ? Date.parse(m.eligibility_until ?? now)
        : Infinity,
    ),
  ).toISOString();
  if (m.campaign_id) {
    const window = new Date(
      Math.floor(Date.now() / 60_000) * 60_000,
    ).toISOString();
    await c.env.DB.batch([
      c.env.DB.prepare(
        "INSERT INTO campaign_budget(campaign_id,window_start,used_segments) VALUES(?,?,0) ON CONFLICT(campaign_id,window_start) DO NOTHING",
      ).bind(m.campaign_id, window),
      c.env.DB.prepare(
        `INSERT INTO dispatch_permits(permit_id,message_id,campaign_id,installation_id,window_start,valid_until,segments,created_at) SELECT ?,m.message_id,m.campaign_id,?,?,?,?,? FROM messages m JOIN campaigns c ON c.campaign_id=m.campaign_id JOIN campaign_budget b ON b.campaign_id=c.campaign_id AND b.window_start=? WHERE m.message_id=? AND m.owner_installation_id=? AND m.cancel_requested=0 AND m.not_after>? AND m.state IN('assigned','phone_accepted','queued') AND c.status='running' AND b.used_segments+?<=c.segments_per_minute AND NOT EXISTS(SELECT 1 FROM dispatch_permits WHERE message_id=m.message_id AND valid_until>?)`,
      ).bind(
        uid("permit"),
        p.id,
        window,
        until,
        parts,
        now,
        window,
        id,
        p.id,
        now,
        parts,
        now,
      ),
    ]);
    const permit = await c.env.DB.prepare(
      "SELECT d.valid_until,d.segments FROM dispatch_permits d JOIN campaigns c ON c.campaign_id=d.campaign_id JOIN messages m ON m.message_id=d.message_id WHERE d.message_id=? AND d.installation_id=? AND d.valid_until>? AND c.status='running' AND m.cancel_requested=0 ORDER BY d.valid_until DESC LIMIT 1",
    )
      .bind(id, p.id, now)
      .first<{ valid_until: string; segments: number }>();
    if (!permit || permit.segments !== parts) return response(false);
    until = permit.valid_until;
  }
  return response(true, until);
}
