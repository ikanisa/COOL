import type {D1PreparedStatement} from "./postgres.ts";
import type { Context } from "npm:hono@4.13.13";
import { admin, adminActor } from "./auth.ts";
import type { AppEnv, StaffRole } from "./types.ts";
import { STAFF_ROLES } from "./types.ts";
import { ApiError, integer, isoNow, randomToken, sha256, string, uid } from "./util.ts";

const SESSION_MS = 30 * 60_000;
const MAX_SESSIONS = 5;
function role(value: unknown): StaffRole {
  if (!STAFF_ROLES.includes(value as StaffRole))
    throw new ApiError(400,"invalid_role","Choose administrator, operator or viewer");
  return value as StaffRole;
}
function audit(c: Context<AppEnv>, action: string, resource: string, now: string) {
  const actor=adminActor(c);
  return c.env.DB.prepare("INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)")
    .bind(uid("audit"),actor.type,actor.id,action,resource,now);
}
export async function createStaff(c: Context<AppEnv>, body: Record<string,unknown>) {
  admin(c,"staff:manage");
  const name=string(body.name,"name",1,120).trim();
  if (!name) throw new ApiError(400,"invalid_request","Staff name is required");
  const staffRole=role(body.role);
  const days=integer(body.key_lifetime_days ?? 30,"key_lifetime_days",1,90);
  const id=uid("staff"), key=randomToken("staff_"), now=isoNow();
  const expires=new Date(Date.now()+days*86_400_000).toISOString();
  await c.env.DB.batch([
    c.env.DB.prepare("INSERT INTO staff_accounts(staff_id,name,role,key_hash,key_expires_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)")
      .bind(id,name,staffRole,await sha256(key),expires,now,now),
    audit(c,"staff_created",id,now),
  ]);
  return c.json({staff_id:id,name,role:staffRole,access_key:key,key_expires_at:expires,
    notice:"Store this personal key securely. It is displayed once; exchange it for a 30-minute operator session."},201);
}
export async function listStaff(c: Context<AppEnv>) {
  admin(c,"staff:manage");
  const rows=await c.env.DB.prepare("SELECT staff_id,name,role,key_expires_at,generation,created_at,updated_at,revoked_at FROM staff_accounts ORDER BY created_at DESC,staff_id LIMIT 500").all();
  return c.json({staff:rows.results});
}
/** No browser cookies or passwords: exchange one high-entropy personal key. */
export async function createStaffSession(c: Context<AppEnv>) {
  const auth=c.req.header("Authorization") ?? "";
  if (!/^Bearer staff_[a-f0-9]{64}$/.test(auth))
    throw new ApiError(401,"unauthorized","A valid personal staff key is required");
  const digest=await sha256(auth.slice(7)), now=isoNow();
  const account=await c.env.DB.prepare("SELECT staff_id,name,role,generation,key_expires_at FROM staff_accounts WHERE key_hash=? AND revoked_at IS NULL AND key_expires_at>?")
    .bind(digest,now).first<{staff_id:string;name:string;role:StaffRole;generation:number;key_expires_at:string}>();
  if (!account) throw new ApiError(401,"unauthorized","Invalid or expired staff key");
  const id=uid("session"), token=randomToken("operator_");
  const expires=new Date(Math.min(Date.now()+SESSION_MS,Date.parse(account.key_expires_at))).toISOString();
  // Conditional insert closes the key-rotation/revocation race. Concurrent
  // exchanges cannot exceed the per-person session cap inside D1's transaction.
  const result=await c.env.DB.batch([
    c.env.DB.prepare(`INSERT INTO staff_sessions(session_id,staff_id,token_hash,generation,created_at,expires_at)
      SELECT ?,a.staff_id,?,a.generation,?,? FROM staff_accounts a
      WHERE a.staff_id=? AND a.key_hash=? AND a.generation=? AND a.revoked_at IS NULL AND a.key_expires_at>?
      AND (SELECT COUNT(*) FROM staff_sessions s WHERE s.staff_id=a.staff_id AND s.generation=a.generation
        AND s.revoked_at IS NULL AND s.expires_at>?)<?`)
      .bind(id,await sha256(token),now,expires,account.staff_id,digest,account.generation,now,now,MAX_SESSIONS),
    c.env.DB.prepare("INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) SELECT ?,'staff',?,'staff_session_created',?,? WHERE EXISTS(SELECT 1 FROM staff_sessions WHERE session_id=?)")
      .bind(uid("audit"),account.staff_id,id,now,id),
  ]);
  if (!result[0]?.meta.changes)
    throw new ApiError(409,"session_not_created","The key changed or five sessions are already active; sign out or rotate the personal key");
  return c.json({session_id:id,session_token:token,expires_at:expires,staff_id:account.staff_id,name:account.name,role:account.role},201);
}
export async function staffAction(c:Context<AppEnv>,body:Record<string,unknown>) {
  admin(c,"staff:manage");
  const id=c.req.param("id"), action=c.req.param("action");
  if (!["revoke","rotate","role"].includes(action??'')) throw new ApiError(404,"not_found","Staff action not found");
  const existing=await c.env.DB.prepare("SELECT revoked_at FROM staff_accounts WHERE staff_id=?").bind(id).first();
  if (!existing) throw new ApiError(404,"not_found","Staff account not found");
  if (existing.revoked_at && action!=="revoke") throw new ApiError(409,"staff_revoked","Create a new staff identity; a revoked identity cannot be revived");
  const now=isoNow(), statements:D1PreparedStatement[]=[];
  let token:string|undefined, expires:string|undefined;
  if (action==="rotate") {
    const days=integer(body.key_lifetime_days ?? 30,"key_lifetime_days",1,90);
    token=randomToken("staff_"); expires=new Date(Date.now()+days*86_400_000).toISOString();
    statements.push(c.env.DB.prepare("UPDATE staff_accounts SET key_hash=?,key_expires_at=?,generation=generation+1,updated_at=? WHERE staff_id=? AND revoked_at IS NULL")
      .bind(await sha256(token),expires,now,id));
  } else if (action==="role") {
    const target=role(body.role);
    statements.push(c.env.DB.prepare("UPDATE staff_accounts SET role=?,generation=generation+1,updated_at=? WHERE staff_id=? AND revoked_at IS NULL").bind(target,now,id));
  } else statements.push(c.env.DB.prepare("UPDATE staff_accounts SET revoked_at=COALESCE(revoked_at,?),generation=generation+1,updated_at=? WHERE staff_id=?").bind(now,now,id));
  statements.push(c.env.DB.prepare("UPDATE staff_sessions SET revoked_at=COALESCE(revoked_at,?) WHERE staff_id=?").bind(now,id),audit(c,`staff_${action}`,id!,now));
  const result=await c.env.DB.batch(statements);
  if (!result[0]?.meta.changes) throw new ApiError(409,"staff_changed","The staff account changed during this action");
  return c.json({staff_id:id,action,sessions_revoked:true,...(token?{access_key:token,key_expires_at:expires}:{}),...(action==="revoke"?{revoked:true}:{})});
}
export async function currentStaff(c:Context<AppEnv>) {
  const p=admin(c);
  const permissions=p.role==="administrator" ? ["read","messages:cancel","campaigns:write","applications:write","devices:write","staff:manage","retention:manage","audit:read"]
    : p.role==="operator" ? ["read","messages:cancel","campaigns:write"] : ["read"];
  const session=p.sessionId?await c.env.DB.prepare("SELECT expires_at FROM staff_sessions WHERE session_id=?").bind(p.sessionId).first<{expires_at:string}>():null;
  return c.json({staff_id:p.id,name:p.name,role:p.role,session_id:p.sessionId ?? null,permissions,expires_at:session?.expires_at??null});
}
export async function logoutStaff(c:Context<AppEnv>) {
  const p=admin(c);
  if (!p.sessionId) throw new ApiError(409,"bootstrap_not_session","A root credential is not a staff session; rotate the root secret separately");
  const now=isoNow();
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE staff_sessions SET revoked_at=COALESCE(revoked_at,?) WHERE session_id=? AND staff_id=?").bind(now,p.sessionId,p.id),
    audit(c,"staff_session_logout",p.sessionId,now),
  ]);
  return c.json({signed_out:true});
}
export async function listAudit(c:Context<AppEnv>) {
  admin(c,"audit:read");
  const limit=integer(Number(c.req.query("limit") ?? 100),"limit",1,500);
  const rows=await c.env.DB.prepare("SELECT event_id,actor_type,actor_id,action,resource_id,at FROM audit_events ORDER BY at DESC,event_id DESC LIMIT ?").bind(limit).all();
  return c.json({events:rows.results});
}
