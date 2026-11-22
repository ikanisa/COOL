import { ApiError, digest, id, json, readJson } from "./core.js";
import { authRequest, verifyToken } from "../auth-http.js";
import { projectSession } from "./member_auth/session.js";
import { helper } from "./member_privacy_email/challenge_store.js";
import {
  assertLive,
  assertNative,
  authority,
  candidate,
  install,
  nativeAuthority,
  proof,
  tokens,
} from "./member_privacy_email/identity.js";
import {
  denied,
  envelope,
  epoch,
  object,
  parse,
  receipt,
  unknown,
  unresolved,
} from "./member_privacy_email/protocol.js";

async function markVerify(env, input, original, outcome) {
  install(env, original);
  try {
    return await helper(
      env,
      "verify_finish",
      input,
      input.challenge_id,
      input.hash,
      input.operation_id,
      outcome,
    );
  } catch {
    throw unknown();
  }
}
async function challenge(env, input, original) {
  install(env, original);
  const prepared = await helper(
    env,
    "prepare",
    input,
    input.challenge_id,
    input.mode,
    input.email,
    input.hash,
  );
  if (original) assertNative(original, prepared.challenge);
  if (prepared.created !== true) return json(receipt(input, prepared), 202);
  const claim = id(),
    claimed = await helper(env, "send_claim", input, input.challenge_id, input.hash, claim);
  if (claimed.claimed !== true) return json(receipt(input, claimed), 202);
  assertLive(claimed.challenge);
  let outcome = "accepted";
  try {
    await authRequest(env, "/otp", {
      body: {
        email: claimed.challenge.identity_value,
        create_user: false,
        gotrue_meta_security: { captcha_token: input.captcha_token },
      },
    });
  } catch (error) {
    outcome = error instanceof ApiError && [400, 401, 403, 422, 429].includes(error.status)
      ? "rejected"
      : "unknown";
  }
  let finished;
  try {
    finished = await helper(
      env,
      "send_finish",
      input,
      input.challenge_id,
      input.hash,
      claim,
      outcome,
    );
  } catch {
    throw unknown();
  }
  // Eligibility and a broken mailer must have the same anonymous receipt.
  // Keep the actual outcome server-side; it must not become an existence oracle.
  if (outcome === "unknown" && input.mode !== "portal_bootstrap") return unresolved(input);
  return json(receipt(input, finished), 202);
}
async function verify(request, env, input, original) {
  install(env, original);
  const claimed = await helper(
    env,
    "verify_claim",
    input,
    input.challenge_id,
    input.hash,
    input.operation_id,
  );
  if (claimed.claimed !== true) {
    return json(
      receipt(input, claimed),
      claimed.challenge.verification_state === "verifying" ||
        claimed.challenge.verification_state === "unconfirmed"
        ? 503
        : 200,
    );
  }
  const c = claimed.challenge;
  if (original) assertNative(original, c);
  assertLive(c);
  let data;
  try {
    data = await authRequest(env, "/verify", {
      body: {
        email: c.identity_value,
        token: input.code,
        type: "email",
        gotrue_meta_security: { captcha_token: input.captcha_token },
      },
    });
  } catch (error) {
    const rejected = error instanceof ApiError && [400, 401, 403, 422, 429].includes(error.status);
    const result = await markVerify(env, input, original, rejected ? "rejected" : "unconfirmed");
    if (!rejected) return unresolved(input);
    return json({
      ...receipt(input, result),
      code: "privacy_email_code_rejected",
      message: "The code could not be verified.",
    }, error.status === 429 ? 429 : 401);
  }
  let safeCandidate = false, verified;
  try {
    if (!object(data) || typeof data.access_token !== "string") throw unknown();
    verified = await verifyToken(env, data.access_token);
    const session = tokens(data, verified), checked = await candidate(env, verified, c, original);
    safeCandidate = true;
    // Revalidate the captured initiating bearer after provider I/O, before projection.
    if (original) original = await nativeAuthority(request, env, c);
    const actor = await projectSession(env, verified, {
      existingLinkOnly: true,
      expectedAuthUserId: verified.user.id,
      expectedUserId: checked.member.user_id,
    });
    const at = epoch();
    if (
      actor.surface !== "member" || !Number.isSafeInteger(actor.authAt) ||
      actor.authAt < at - 300 || actor.authAt > at || actor.authAt !== checked.event
    ) throw denied();
    if (original) original = await nativeAuthority(request, env, c);
    env.DB.setClaims(verified.claims);
    const consumed = await helper(
      env,
      "consume",
      input,
      input.challenge_id,
      input.hash,
      input.operation_id,
    );
    const purposeProof = proof(consumed, input, verified, checked.member, checked.event);
    return json({
      ...session,
      user: actor.user,
      ...envelope(input),
      operation_id: input.operation_id,
      auth_event: { method: "otp", timestamp: checked.event },
      purpose_proof: purposeProof,
    });
  } catch {
    // The token is still server-local and unadopted. Never guess or use another
    // token when identity/event validation did not establish this exact candidate.
    if (safeCandidate) {
      await authRequest(env, "/logout?scope=local", { token: verified.token }).catch(() => {});
    }
    await markVerify(env, input, original, "unconfirmed").catch(() => {});
    return unresolved(input);
  }
}
async function cleanup(env, input) {
  // Candidate cleanup grants no sign-in access. Its exact recorded proof remains
  // usable for irreversible retirement after the initiating session is revoked.
  const verified = await verifyToken(env, input.candidate_access_token);
  env.DB.setClaims(verified.claims);
  if (!input.operation_id) throw denied();
  const claim = id();
  const claimed = await helper(
    env,
    "cleanup_claim",
    input,
    input.challenge_id,
    input.hash,
    input.operation_id,
    claim,
  );
  if (claimed.claimed !== true) {
    return json(
      receipt(input, claimed),
      claimed.challenge.cleanup_state === "confirmed" ? 200 : 503,
    );
  }
  try {
    if (claimed.challenge.verification_operation_id !== input.operation_id) throw denied();
    await candidate(env, verified, claimed.challenge, null, { cleanup: true });
  } catch {
    env.DB.setClaims(verified.claims);
    await helper(
      env,
      "cleanup_finish",
      input,
      input.challenge_id,
      input.hash,
      input.operation_id,
      claim,
      "unconfirmed",
    ).catch(() => {});
    return unresolved(input);
  }
  let outcome = "confirmed";
  try {
    await authRequest(env, "/logout?scope=local", { token: input.candidate_access_token });
  } catch {
    outcome = "unconfirmed";
  }
  env.DB.setClaims(verified.claims);
  let finished;
  try {
    finished = await helper(
      env,
      "cleanup_finish",
      input,
      input.challenge_id,
      input.hash,
      input.operation_id,
      claim,
      outcome,
    );
  } catch {
    throw unknown();
  }
  if (outcome !== "confirmed" || finished.challenge.cleanup_state !== "confirmed") {
    return unresolved(input);
  }
  return json(receipt(input, finished));
}
/** Four POST-only, no-cookie routes. index.js must dispatch before requireSession. */
export async function handlePrivacyEmailAuth(request, env) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith("/v1/privacy/email/")) return null;
  const operation = path.slice("/v1/privacy/email/".length);
  if (!["challenge", "verify", "status", "cancel"].includes(operation)) {
    throw new ApiError(404, "not_found", "This verification route is unavailable.");
  }
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed", "Use POST.");
  if (request.headers.get("Sec-Fetch-Site") === "cross-site") throw denied();
  const input = parse(await readJson(request, 32768), operation);
  input.hash = await digest(input.challenge_context);
  try {
    if (operation === "cancel" && input.candidate_access_token) return await cleanup(env, input);
    const original = await authority(request, env, input);
    install(env, original);
    if (operation === "challenge") return await challenge(env, input, original);
    if (operation === "verify") return await verify(request, env, input, original);
    const result = await helper(
      env,
      operation,
      input,
      input.challenge_id,
      input.hash,
      ...(operation === "cancel" ? [input.operation_id] : []),
    );
    if (original) assertNative(original, result.challenge);
    return json(receipt(input, result));
  } catch (error) {
    if (error instanceof ApiError && error.code === "privacy_email_operation_unknown") {
      return unresolved(input);
    }
    throw error;
  }
}
