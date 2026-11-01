import type {D1PreparedStatement} from "./postgres.ts";
import type { Context } from "npm:hono@4.13.13";
import { admin, adminActor } from "./auth.ts";
import { campaignSummary } from "./campaigns.ts";
import type { CampaignRow } from "./campaigns.ts";
import { summary } from "./messages.ts";
import type { AppEnv, MessageRow } from "./types.ts";
import { KINDS, SCOPES } from "./types.ts";
import {
  ApiError,
  array,
  integer,
  isoNow,
  randomToken,
  sha256,
  string,
  uid,
} from "./util.ts";
export async function createApplication(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  admin(c,"applications:write");
  const name = string(body.name, "name", 1, 120),
    allowed = [...new Set(array(body.allowed_kinds, "allowed_kinds", 4))];
  if (!allowed.length || allowed.some((k) => !KINDS.includes(k as never)))
    throw new ApiError(
      400,
      "invalid_request",
      "Choose at least one supported allowed kind",
    );
  const scopes =
    body.scopes === undefined
      ? [...SCOPES]
      : [...new Set(array(body.scopes, "scopes", SCOPES.length))];
  if (scopes.some((s) => !SCOPES.includes(s as never)))
    throw new ApiError(400, "invalid_request", "Unsupported application scope");
  const id = uid("app"),
    token = randomToken("app_"),
    now = isoNow();
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT INTO applications(application_id,name,token_hash,allowed_kinds,scopes,created_at) VALUES(?,?,?,?,?,?)",
    ).bind(
      id,
      name,
      await sha256(token),
      JSON.stringify(allowed),
      JSON.stringify(scopes),
      now,
    ),
    c.env.DB.prepare(
      "INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)",
    ).bind(uid("audit"), adminActor(c).type, adminActor(c).id, "application_created", id, now),
  ]);
  return c.json(
    {
      application_id: id,
      application_token: token,
      name,
      allowed_kinds: allowed,
      scopes,
    },
    201,
  );
}
export async function createDevice(
  c: Context<AppEnv>,
  body: Record<string, unknown>,
) {
  admin(c,"devices:write");
  const name = string(body.name, "name", 1, 120),
    allowed = [...new Set(array(body.allowed_kinds, "allowed_kinds", 4))];
  if (!allowed.length || allowed.some((k) => !KINDS.includes(k as never)))
    throw new ApiError(
      400,
      "invalid_request",
      "Choose at least one supported allowed kind",
    );
  const slot =
      body.sim_slot === undefined || body.sim_slot === null
        ? null
        : integer(body.sim_slot, "sim_slot", 0, 1),
    id = uid("installation"),
    token = randomToken("device_"),
    now = isoNow();
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT INTO devices(installation_id,name,token_hash,allowed_kinds,sim_slot,created_at) VALUES(?,?,?,?,?,?)",
    ).bind(id, name, await sha256(token), JSON.stringify(allowed), slot, now),
    c.env.DB.prepare(
      "INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)",
    ).bind(uid("audit"), adminActor(c).type, adminActor(c).id, "device_created", id, now),
  ]);
  return c.json(
    {
      installation_id: id,
      device_token: token,
      name,
      allowed_kinds: allowed,
      sim_slot: slot,
    },
    201,
  );
}
export async function listApplications(c: Context<AppEnv>) {
  admin(c);
  const rows = await c.env.DB.prepare(
    "SELECT application_id,name,allowed_kinds,scopes,created_at,revoked_at FROM applications ORDER BY created_at DESC LIMIT 500",
  ).all();
  return c.json({
    applications: rows.results.map((r) => ({
      ...r,
      allowed_kinds: JSON.parse(String(r.allowed_kinds)),
      scopes: JSON.parse(String(r.scopes)),
    })),
  });
}
export async function listDevices(c: Context<AppEnv>) {
  admin(c);
  const rows = await c.env.DB.prepare(
    `SELECT installation_id,name,allowed_kinds,sim_slot,ready,revoked_at,created_at,last_seen_at,app_version,os_version,health_json,CASE WHEN fcm_token IS NULL THEN 0 ELSE 1 END AS has_fcm_token,fcm_attempts,fcm_last_error,(SELECT COUNT(*) FROM messages m WHERE m.owner_installation_id=d.installation_id AND m.state IN('assigned','phone_accepted','queued')) AS pending_count FROM devices d ORDER BY created_at DESC LIMIT 500`,
  ).all();
  return c.json({
    devices: rows.results.map((r) => {
      const { health_json, ...rest } = r;
      return {
        ...rest,
        ready: !!r.ready,
        has_fcm_token: !!r.has_fcm_token,
        allowed_kinds: JSON.parse(String(r.allowed_kinds)),
        health: JSON.parse(String(health_json)),
      };
    }),
  });
}
export async function rotateOrRevoke(
  c: Context<AppEnv>,
  resource: "devices" | "applications",
  action: "rotate" | "revoke",
) {
  admin(c, resource === "devices" ? "devices:write" : "applications:write");
  const id = c.req.param("id"),
    column = resource === "devices" ? "installation_id" : "application_id",
    now = isoNow(),
    exists = await c.env.DB.prepare(
      `SELECT ${column},revoked_at FROM ${resource} WHERE ${column}=?`,
    )
      .bind(id)
      .first();
  if (!exists)
    throw new ApiError(404, "not_found", "Credential owner not found");
  if (action === "rotate" && exists.revoked_at)
    throw new ApiError(
      409,
      "revoked",
      "Enroll a new identity instead of reviving a revoked credential",
    );
  const token =
    action === "rotate"
      ? randomToken(resource === "devices" ? "device_" : "app_")
      : null;
  const statements: D1PreparedStatement[] = [
    action === "rotate"
      ? c.env.DB.prepare(
          `UPDATE ${resource} SET token_hash=? WHERE ${column}=? AND revoked_at IS NULL`,
        ).bind(await sha256(token!), id)
      : c.env.DB.prepare(
          `UPDATE ${resource} SET revoked_at=? ${resource === "devices" ? ",ready=0,fcm_token=NULL,fcm_pending=0" : ""} WHERE ${column}=?`,
        ).bind(now, id),
    c.env.DB.prepare(
      "INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)",
    ).bind(uid("audit"), adminActor(c).type, adminActor(c).id, `${resource}_${action}`, id, now),
  ];
  if (action === "revoke") {
    if (resource === "applications")
      statements.push(
        c.env.DB.prepare(
          "UPDATE campaigns SET status='cancelled',updated_at=? WHERE application_id=? AND status IN('draft','running','paused')",
        ).bind(now, id),
        c.env.DB.prepare(
          "UPDATE devices SET fcm_pending=1,fcm_next_at=?,wake_revision=wake_revision+1 WHERE revoked_at IS NULL AND installation_id IN(SELECT owner_installation_id FROM messages WHERE application_id=?)",
        ).bind(now, id),
      );
    statements.push(
      c.env.DB.prepare(
        `UPDATE messages SET cancel_requested=1,state=CASE WHEN owner_installation_id IS NULL AND state IN('accepted','queued') THEN 'cancelled' ELSE state END,updated_at=? WHERE ${resource === "devices" ? "owner_installation_id" : "application_id"}=?`,
      ).bind(now, id),
    );
  }
  await c.env.DB.batch(statements);
  return c.json(
    resource === "devices"
      ? {
          installation_id: id,
          ...(token ? { device_token: token } : { revoked: true }),
        }
      : {
          application_id: id,
          ...(token ? { application_token: token } : { revoked: true }),
        },
  );
}
export async function listMessages(c: Context<AppEnv>) {
  admin(c);
  const where: string[] = [],
    bind: (string | number)[] = [];
  for (const name of ["state", "kind", "application_id"]) {
    const value = c.req.query(name);
    if (value) {
      where.push(`m.${name}=?`);
      bind.push(value);
    }
  }
  const limit = integer(Number(c.req.query("limit") ?? 100), "limit", 1, 250),
    rows = await c.env.DB.prepare(
      `SELECT m.*,(SELECT MAX(parts_total) FROM attempts a WHERE a.message_id=m.message_id) AS parts_total FROM messages m ${where.length ? `WHERE ${where.join(" AND ")}` : ""} ORDER BY m.created_at DESC,m.message_id LIMIT ?`,
    )
      .bind(...bind, limit)
      .all<MessageRow>();
  return c.json({ messages: rows.results.map(summary) });
}
export async function listCampaigns(c: Context<AppEnv>) {
  admin(c);
  const rows = await c.env.DB.prepare(
    "SELECT * FROM campaigns ORDER BY created_at DESC LIMIT 250",
  ).all<CampaignRow>();
  return c.json({ campaigns: rows.results.map(campaignSummary) });
}
export async function overview(c: Context<AppEnv>) {
  admin(c);
  const [states, kinds, devices] = await c.env.DB.batch<
    Record<string, unknown>
  >([
    c.env.DB.prepare(
      "SELECT state,COUNT(*) AS count FROM messages GROUP BY state",
    ),
    c.env.DB.prepare(
      "SELECT kind,COUNT(*) AS count FROM messages GROUP BY kind",
    ),
    c.env.DB.prepare(
      "SELECT COUNT(*) AS total,COALESCE(SUM(CASE WHEN ready=1 AND revoked_at IS NULL AND last_seen_at>? THEN 1 ELSE 0 END),0) AS ready,COALESCE(SUM(CASE WHEN revoked_at IS NOT NULL THEN 1 ELSE 0 END),0) AS revoked FROM devices",
    ).bind(new Date(Date.now() - 90_000).toISOString()),
  ]);
  return c.json({
    counts: Object.fromEntries(
      states!.results.map((r) => [String(r.state), Number(r.count)]),
    ),
    by_kind: Object.fromEntries(
      kinds!.results.map((r) => [String(r.kind), Number(r.count)]),
    ),
    devices: devices!.results[0] ?? { total: 0, ready: 0, revoked: 0 },
  });
}
