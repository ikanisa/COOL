import { ApiError } from "../core.js";

export const unix = () => Math.floor(Date.now() / 1000);
export const bearerToken = (request) =>
  request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
export const mfaUnavailable = () =>
  new ApiError(410, "mfa_not_available", "Verify your email to confirm sensitive changes.");

export function fail(code = "invalid_session", status = 401) {
  const message = code === "admin_access_not_approved"
    ? "This email does not have Admin access. Contact the super admin to be added."
    : "Sign in again or request a new code.";
  throw new ApiError(status, code, message);
}

export function confirmedIdentity(user, type) {
  if (type === "phone") {
    return user.phone_confirmed_at
      ? (user.phone?.startsWith("+") ? user.phone : "+" + user.phone)
      : null;
  }
  return user.email_confirmed_at ? user.email?.toLowerCase() : null;
}
