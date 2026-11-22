import { ApiError, first, id, now, rows } from "../core.js";
import { authRequest, verifyToken } from "../../auth-http.js";
import { guestResponseSession } from "../anonymous_auth.js";
import { bearerToken, confirmedIdentity, fail, mfaUnavailable, unix } from "./support.js";

function originalAuthenticationAt(claims, at) {
  // Token iat renews on refresh; only a validated first-factor AMR event is fresh.
  let authAt = 0;
  for (const entry of Array.isArray(claims.amr) ? claims.amr : []) {
    if (
      entry !== null && typeof entry === "object" && !Array.isArray(entry) &&
      ["otp", "password", "oauth"].includes(entry.method) &&
      Number.isSafeInteger(entry.timestamp) && entry.timestamp > 0 && entry.timestamp <= at
    ) authAt = authAt === 0 ? entry.timestamp : Math.min(authAt, entry.timestamp);
  }
  return authAt; // Missing event evidence preserves ordinary access without freshness.
}

const factorIdIsValid = (value) =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
function userWithFactors(user) {
  // The authenticated GET /user endpoint omits an empty enrolled-factor list.
  // Normalize only this outward user DTO; retain the raw verified provider user.
  const factors = Object.hasOwn(user, "factors") ? user.factors : [];
  if (
    !Array.isArray(factors) || factors.length > 128 ||
    factors.some((factor) =>
      !isObject(factor) || !factorIdIsValid(factor.id) || typeof factor.factor_type !== "string" ||
      !/^[a-z][a-z0-9_]{0,63}$/.test(factor.factor_type) ||
      !["unverified", "verified"].includes(factor.status)
    )
  ) {
    throw new ApiError(
      503,
      "auth_user_unavailable",
      "Account details could not be confirmed. Try again.",
    );
  }
  return { ...user, factors };
}

async function resolveActivePrincipal(
  env,
  { user, claims },
  { surface, existingLinkOnly, expectedUserId, rejectExistingIdentity },
) {
  let link = await first(
    env,
    "SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?",
    user.id,
  );
  if (existingLinkOnly && !link || expectedUserId !== null && link?.user_id !== expectedUserId) {
    fail("verified_identity_mismatch", 403);
  }
  if (!link) {
    const email = confirmedIdentity(user, "email"), phone = confirmedIdentity(user, "phone");
    let principal;
    if (surface === "admin") {
      principal = await first(
        env,
        "SELECT l.user_id AS id FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE a.email=? AND a.status IN('active','invited')",
        email,
      );
    } else {
      const found = await rows(
        env,
        `SELECT id FROM users WHERE (? IS NOT NULL AND lower(email)=?) OR (? IS NOT NULL AND phone=?) UNION SELECT l.user_id AS id FROM admin_principal_links l JOIN admin_users a ON a.id=l.admin_user_id JOIN users u ON u.id=l.user_id WHERE ? IS NOT NULL AND a.email=? AND a.status IN('active','invited')`,
        email,
        email,
        phone,
        phone,
        email,
        email,
      );
      if (found.length > 1) fail("identity_link_conflict", 409);
      principal = found[0];
    }
    if (principal && rejectExistingIdentity) fail("identity_already_exists", 409);
    if (!principal) {
      if (!email && !phone) fail("verified_identity_required", 403);
      if (surface !== "member" || env.AUTH_MEMBER_REGISTRATION_ENABLED !== "true") {
        fail("registration_unavailable", 403);
      }
      const newId = id(), stamp = now();
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO users(id,public_id,phone,email,full_name,created_at,updated_at) VALUES(?,(SELECT printf('%06d',min(candidate)) FROM (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM users WHERE public_id!='999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM users WHERE public_id=printf('%06d',candidate))),?,?,'',?,?)`,
        ).bind(newId, phone, email, stamp, stamp),
      ]);
      principal = { id: newId };
    }
    await env.DB.prepare(
      "INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(?,?,?) ON CONFLICT(auth_user_id) DO NOTHING",
    ).bind(user.id, principal.id, "supabase-auth-getuser:" + claims.session_id).run();
    link = await first(
      env,
      "SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?",
      user.id,
    );
    if (link?.user_id !== principal.id) fail("identity_link_conflict", 409);
  }
  const member = await first(env, "SELECT * FROM users WHERE id=?", link.user_id);
  if (member?.access_status !== "active") fail("access_revoked", 403);
  return member;
}

export async function projectSession(
  env,
  verified,
  {
    surface = "member",
    mfaVerified = false,
    existingLinkOnly = false,
    expectedAuthUserId = null,
    expectedUserId = null,
    rejectExistingIdentity = false,
  } = {},
) {
  if (mfaVerified) throw mfaUnavailable();
  const { user, claims } = verified;
  if (user.is_anonymous === true || claims.is_anonymous === true) {
    fail("verified_identity_required", 403);
  }
  if (expectedAuthUserId !== null && user.id !== expectedAuthUserId) {
    fail("verified_identity_mismatch", 403);
  }
  env.DB.setClaims(claims);
  if (env.AUTH_ANONYMOUS_ENABLED === "true") {
    const upgrade = await first(
      env,
      "SELECT private.guest_upgrade_projection_allowed() AS allowed",
    );
    if (upgrade?.allowed !== true) fail("guest_upgrade_unknown", 403);
  }
  const managed = await first(
    env,
    "SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed",
    user.id,
    claims.session_id,
  );
  if (!managed?.allowed) fail("access_revoked");
  const principal = await resolveActivePrincipal(env, verified, {
    surface,
    existingLinkOnly,
    expectedUserId,
    rejectExistingIdentity,
  });
  const previous = await first(env, "SELECT * FROM auth_sessions WHERE id=?", claims.session_id);
  const admission = await first(
    env,
    "SELECT a.id FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE s.auth_session_id=? AND a.status='active' AND s.auth_version=a.auth_version AND l.user_id=? AND s.expires_at>?",
    claims.session_id,
    principal.id,
    unix(),
  );
  const actualSurface = admission ? "admin" : surface;
  if (actualSurface === "admin" && !env.ADMIN_AUTH_EXCHANGE && !admission) {
    fail("admin_admission_required", 403);
  }
  const authAt = previous?.auth_at ?? originalAuthenticationAt(claims, unix());
  if (!previous) {
    const lifetime = actualSurface === "admin" ? 28800 : 2592000;
    const expiry =
      (await first(env, "SELECT private.session_expiry(?) AS expires_at", unix() + lifetime))
        .expires_at;
    await env.DB.prepare(
      `INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at,assurance_level,mfa_at,mfa_factor_id) VALUES(?,?,?,?,?,?,1,NULL,NULL) ON CONFLICT(id) DO NOTHING`,
    ).bind(claims.session_id, principal.id, actualSurface, authAt, unix(), expiry).run();
  }
  const session = await first(env, "SELECT * FROM auth_sessions WHERE id=?", claims.session_id);
  if (
    session?.revoked_at || session?.surface !== actualSurface ||
    existingLinkOnly && session?.user_id !== principal.id
  ) fail("access_revoked");
  const effectiveAal = Number(session.assurance_level) === 2 && claims.aal === "aal2" ? 2 : 1;
  const permissions = actualSurface === "admin"
    ? new Set(
      (await rows(
        env,
        `SELECT g.permission FROM admin_grants g JOIN admin_sessions s ON s.auth_session_id=? JOIN admin_users a ON a.id=s.user_id JOIN admin_account_role_capabilities c ON c.role=a.role AND c.permission=g.permission WHERE g.user_id=? AND g.permission<>'auth.mfa.enroll' AND a.status='active' AND s.auth_version=a.auth_version`,
        claims.session_id,
        principal.id,
      )).map((r) => r.permission),
    )
    : new Set();
  const actor = {
    userId: principal.id,
    sessionId: claims.session_id,
    surface: actualSurface,
    assuranceLevel: effectiveAal,
    aal: effectiveAal === 2 ? "aal2" : "aal1",
    authAt: effectiveAal === 2 ? session.mfa_at : session.auth_at,
    mfaAt: effectiveAal === 2 ? session.mfa_at : null,
    mfaFactorId: effectiveAal === 2 ? session.mfa_factor_id : null,
    permissions,
    user: {
      ...user,
      id: principal.id,
      auth_user_id: user.id,
      user_metadata: {
        full_name: principal.full_name,
        public_id: principal.public_id,
        country_code: principal.country_code,
        currency_code: principal.currency_code,
        momo_provider: principal.momo_provider,
        momo_number: principal.momo_number,
      },
      app_metadata: {
        provider: user.app_metadata?.provider,
        roles: permissions.size ? ["admin"] : ["member"],
        permissions: [...permissions],
      },
    },
  };
  env.AUTH_ACTOR = actor;
  env.AUTH_VERIFIED = verified;
  return actor;
}
export async function requireSession(request, env) {
  const token = bearerToken(request);
  if (!token) fail();
  const verified = env.AUTH_VERIFIED?.token === token
    ? env.AUTH_VERIFIED
    : await verifyToken(env, token);
  return projectSession(env, verified);
}
export async function responseSession(env, data, options = {}) {
  if (options.allowGuest === true) {
    const verified = await verifyToken(env, data.access_token, { allowAnonymous: true });
    if (verified.user.is_anonymous === true) return guestResponseSession(env, data);
  }
  const verified = await verifyToken(env, data.access_token);
  const actor = await projectSession(env, verified, options);
  return { ...data, user: actor.user };
}

export async function currentAuthUser(request, env) {
  const token = bearerToken(request);
  if (token && env.AUTH_ANONYMOUS_ENABLED === "true") {
    const verified = await verifyToken(env, token, { allowAnonymous: true });
    if (verified.user.is_anonymous === true) {
      env.DB.setClaims(verified.claims);
      await first(env, "SELECT private.guest_auth_session(false) AS actor");
      return {
        id: verified.user.id,
        auth_user_id: verified.user.id,
        is_anonymous: true,
        app_metadata: { capabilities: ["public_read"] },
        user_metadata: {},
      };
    }
  }
  const actor = await requireSession(request, env);
  return userWithFactors(actor.user);
}

export async function logoutSession(request, env) {
  const token = bearerToken(request);
  if (token && env.AUTH_ANONYMOUS_ENABLED === "true") {
    const verified = await verifyToken(env, token, {
      allowAnonymous: true,
      allowAnonymousTransition: true,
    });
    if (verified.claims.is_anonymous === true) {
      await authRequest(env, "/logout?scope=local", { token });
      return { ok: true };
    }
  }
  const actor = await requireSession(request, env);
  await authRequest(env, "/logout?scope=local", { token: env.AUTH_VERIFIED.token });
  await env.DB.prepare(
    "UPDATE auth_sessions SET revoked_at=?,revocation_reason='signed_out' WHERE id=? AND user_id=?",
  ).bind(unix(), actor.sessionId, actor.userId).run();
  return { ok: true };
}
