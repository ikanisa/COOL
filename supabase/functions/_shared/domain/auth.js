import { ApiError, json, readJson } from "./core.js";
import { authRequest } from "../auth-http.js";
import { handleGoogleAuth } from "./google_auth.js";
import { handleGuestAuth } from "./anonymous_auth.js";
import { startOtp, verifyOtp } from "./member_auth/otp.js";
import {
  currentAuthUser,
  logoutSession,
  projectSession,
  responseSession,
} from "./member_auth/session.js";
import { fail, mfaUnavailable } from "./member_auth/support.js";

export {
  otpDeliveryAvailable,
  otpDeliveryChannel,
  startOtp,
  verifyOtp,
} from "./member_auth/otp.js";
export { projectSession, requireSession, responseSession } from "./member_auth/session.js";

export async function handleAuth(request, env) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith("/v1/auth/")) return null;
  if (path === "/v1/auth/mfa" || path.startsWith("/v1/auth/mfa/")) throw mfaUnavailable();
  if (path.startsWith("/v1/auth/google/")) return handleGoogleAuth(request, env);
  if (request.method === "GET" && path === "/v1/auth/user") {
    return json(await currentAuthUser(request, env));
  }
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed", "Use POST.");
  const body = await readJson(request, 16384);
  const guest = await handleGuestAuth(request, env, body, projectSession);
  if (guest) return guest;
  if (path === "/v1/auth/otp") return json(await startOtp(env, body));
  if (path === "/v1/auth/verify") {
    if (body.surface === "admin") fail("admin_cookie_required", 403);
    return json(await verifyOtp(env, body));
  }
  if (path === "/v1/auth/refresh") {
    const data = await authRequest(env, "/token?grant_type=refresh_token", {
      body: { refresh_token: body.refresh_token },
    });
    return json(
      await responseSession(env, data, { allowGuest: env.AUTH_ANONYMOUS_ENABLED === "true" }),
    );
  }
  if (path === "/v1/auth/logout") return json(await logoutSession(request, env));
  throw new ApiError(404, "not_found", "This identity operation does not exist.");
}
