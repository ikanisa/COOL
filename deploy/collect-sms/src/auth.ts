import type { Context, Next } from "npm:hono@4.13.13";
import type { AdminPermission, AppEnv, Kind, Scope, StaffRole } from "./types.ts";
import { ApiError, safeEqual, sha256 } from "./util.ts";
export async function authenticate(c: Context<AppEnv>, next: Next) {
  const authorization = c.req.header("Authorization");
  if (!authorization?.startsWith("Bearer "))
    throw new ApiError(401, "unauthorized", "A bearer credential is required");
  const token = authorization.slice(7);
  if (!token || token.length > 512)
    throw new ApiError(401, "unauthorized", "Invalid credential");
  const digest = await sha256(token);
  const root = c.env.ROOT_ADMIN_TOKEN;
  if (
    root &&
    root.length >= 32 &&
    !root.startsWith("REPLACE_") &&
    safeEqual(digest, await sha256(root))
  ) {
    c.set("principal", { type: "admin", id: "root", name: "Bootstrap administrator", role: "administrator" });
    await next();
    return;
  }
  // Staff access keys are only accepted by the dedicated session exchange.
  // Read roles and revocation on every request; never trust a client-supplied role.
  if (token.startsWith("operator_")) {
    const staff = await c.env.DB.prepare(
      `SELECT a.staff_id,a.name,a.role,s.session_id FROM staff_sessions s
       JOIN staff_accounts a ON a.staff_id=s.staff_id
       WHERE s.token_hash=? AND s.revoked_at IS NULL AND a.revoked_at IS NULL
       AND s.expires_at>? AND a.key_expires_at>? AND s.generation=a.generation`,
    ).bind(digest, new Date().toISOString(), new Date().toISOString())
      .first<{staff_id:string;name:string;role:StaffRole;session_id:string}>();
    if (staff) {
      c.set("principal", { type: "admin", id: staff.staff_id, name: staff.name, role: staff.role, sessionId: staff.session_id });
      await next(); return;
    }
    throw new ApiError(401, "session_expired", "Staff session is expired or revoked; sign in again");
  }
  const app = await c.env.DB.prepare(
    "SELECT application_id,allowed_kinds,scopes FROM applications WHERE token_hash=? AND revoked_at IS NULL",
  )
    .bind(digest)
    .first<{ application_id: string; allowed_kinds: string; scopes: string }>();
  if (app) {
    c.set("principal", {
      type: "application",
      id: app.application_id,
      allowedKinds: JSON.parse(app.allowed_kinds),
      scopes: JSON.parse(app.scopes),
    });
    await next();
    return;
  }
  const device = await c.env.DB.prepare(
    "SELECT installation_id,allowed_kinds FROM devices WHERE token_hash=? AND revoked_at IS NULL",
  )
    .bind(digest)
    .first<{ installation_id: string; allowed_kinds: string }>();
  if (device) {
    c.set("principal", {
      type: "device",
      id: device.installation_id,
      allowedKinds: JSON.parse(device.allowed_kinds),
    });
    await next();
    return;
  }
  throw new ApiError(401, "unauthorized", "Invalid or revoked credential");
}
export function admin(c: Context<AppEnv>, permission: AdminPermission = "read") {
  const p = c.get("principal");
  if (p.type !== "admin")
    throw new ApiError(403, "forbidden", "Administration credential required");
  if (p.role !== "administrator" && permission !== "read" &&
      !(p.role === "operator" && ["messages:cancel", "campaigns:write"].includes(permission)))
    throw new ApiError(403, "staff_permission_denied", "Your staff role does not allow this operation");
  return p;
}
export function adminActor(c: Context<AppEnv>) {
  const p = admin(c);
  return { type: p.id === "root" ? "admin" : "staff", id: p.id };
}
export function application(c: Context<AppEnv>, scope: Scope, kind?: Kind) {
  const p = c.get("principal");
  if (p.type !== "application")
    throw new ApiError(403, "forbidden", "Application credential required");
  if (!p.scopes.includes(scope) || (kind && !p.allowedKinds.includes(kind)))
    throw new ApiError(
      403,
      "forbidden",
      "The credential does not allow this operation",
    );
  return p;
}
export function device(c: Context<AppEnv>) {
  const p = c.get("principal");
  if (p.type !== "device")
    throw new ApiError(403, "forbidden", "Device credential required");
  return p;
}
