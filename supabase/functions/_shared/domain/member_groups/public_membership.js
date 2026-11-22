import { ApiError, first, id, now, uuid } from "../core.js";
import { assertMutationAdmission, mutation } from "../mutations.js";

function publicJoinGuardFailure(error) {
  return error instanceof ApiError && error.code === "stale_state" ||
    !(error instanceof ApiError) &&
      /admin_bridge_guards|admin_bridge_state/.test(String(error?.message ?? error));
}
function publicJoinFailure(error) {
  return publicJoinGuardFailure(error)
    ? new ApiError(409, "group_join_unconfirmed", "Refresh this group before continuing.")
    : error;
}

// Fresh public-join operations consume bounded receipt/audit capacity. A replay
// of the same request is checked by mutation() without consuming this budget.
const publicJoinBudget =
  `(SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='join_public_group' AND request_id!=? AND created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-1 hour'))<60 AND (SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='join_public_group' AND request_id!=? AND created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-1 day'))<500`;

export async function joinPublicGroup(operation, body, env, actor) {
  const groupId = uuid(body.p_collection_id, "collection_id");
  const requestId = uuid(body.p_request_id ?? id(), "request_id");
  const before = id(), after = id();
  const authority = `EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id
   WHERE s.id=? AND s.user_id=? AND s.revoked_at IS NULL AND s.expires_at>unixepoch() AND u.access_status='active')
   AND EXISTS(SELECT 1 FROM collections c WHERE c.id=? AND c.status='active' AND c.visibility_status='public_approved')`;
  // Lock the authority and group before rechecking them. A membership conflict
  // may represent a concurrent insert, so lock and verify it after INSERT too.
  // Inactive memberships are never silently reactivated by a public join.
  const writes = [
    env.DB.prepare("SELECT id FROM auth_sessions WHERE id=? AND user_id=? FOR UPDATE").bind(
      actor.sessionId,
      actor.userId,
    ),
    env.DB.prepare("SELECT id FROM users WHERE id=? FOR UPDATE").bind(actor.userId),
    env.DB.prepare("SELECT id FROM collections WHERE id=? FOR UPDATE").bind(groupId),
    env.DB.prepare(
      `INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN ${authority} AND ${publicJoinBudget} THEN 1 ELSE 0 END`,
    ).bind(
      before,
      actor.sessionId,
      actor.userId,
      groupId,
      actor.userId,
      requestId,
      actor.userId,
      requestId,
    ),
    env.DB.prepare(
      `INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'member',1,?) ON CONFLICT(collection_id,user_id) DO NOTHING`,
    ).bind(id(), groupId, actor.userId, now()),
    env.DB.prepare("SELECT id FROM memberships WHERE collection_id=? AND user_id=? FOR UPDATE")
      .bind(groupId, actor.userId),
    env.DB.prepare(
      `INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN ${authority} AND EXISTS(SELECT 1 FROM memberships WHERE collection_id=? AND user_id=? AND active=1) THEN 1 ELSE 0 END`,
    ).bind(after, actor.sessionId, actor.userId, groupId, groupId, actor.userId),
    env.DB.prepare("DELETE FROM admin_bridge_guards WHERE id IN (?,?)").bind(before, after),
  ];
  let result;
  try {
    result = await mutation(env, actor, operation, requestId, body, groupId, writes, {
      entityType: "collection",
      entityId: groupId,
      auditDetails: { membership: "public_join" },
    });
  } catch (error) {
    if (publicJoinGuardFailure(error)) {
      const budget = await first(
        env,
        "SELECT " + publicJoinBudget + " AS allowed",
        actor.userId,
        requestId,
        actor.userId,
        requestId,
      );
      if (budget && !budget.allowed) {
        throw new ApiError(
          429,
          "public_join_limited",
          "Group joining is temporarily limited. Try again later.",
        );
      }
    }
    throw publicJoinFailure(error);
  }
  if (result !== groupId) {
    throw new ApiError(409, "group_join_unconfirmed", "Refresh this group before continuing.");
  }
  // A retained response proves the earlier operation, not current membership.
  // Recheck managed session, public visibility and membership transactionally.
  const verify = id();
  try {
    await assertMutationAdmission(env, actor, [
      env.DB.prepare("SELECT id FROM collections WHERE id=? FOR UPDATE").bind(groupId),
      env.DB.prepare("SELECT id FROM memberships WHERE collection_id=? AND user_id=? FOR UPDATE")
        .bind(groupId, actor.userId),
      env.DB.prepare(
        `INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN ${authority} AND EXISTS(SELECT 1 FROM memberships WHERE collection_id=? AND user_id=? AND active=1) THEN 1 ELSE 0 END`,
      ).bind(verify, actor.sessionId, actor.userId, groupId, groupId, actor.userId),
      env.DB.prepare("DELETE FROM admin_bridge_guards WHERE id=?").bind(verify),
    ]);
  } catch (error) {
    throw publicJoinFailure(error);
  }
  return { handled: true, value: groupId };
}
