import { verifyDeploymentProfile } from "../../../supabase/functions/_shared/deployment-profile.js";
import { smsFenceBackend } from "./fence.ts";
import {
  gatewayConnection,
  managedGatewayDatabaseUrl,
} from "./gateway-connection.ts";
import { GatewayDatabase } from "./postgres.ts";
import type { Env } from "./types.ts";

export type GatewaySettings = Record<string, string | undefined>;
export type GatewayHandlerOptions = {
  database?: GatewayDatabase;
  fenceBackend?: ReturnType<typeof smsFenceBackend>;
  waitUntil?: (promise: Promise<unknown>) => void;
};

function isDigest(value: string | undefined): value is string {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value) &&
    value !== "0".repeat(64);
}

function isSecret(value: string | undefined): value is string {
  return typeof value === "string" && /^[\x21-\x7e]{32,512}$/.test(value) &&
    !value.startsWith("REPLACE_");
}

export async function createGatewayRuntime(
  settings: GatewaySettings,
  options: GatewayHandlerOptions,
) {
  if (
    settings.COLLECT_SMS_ENABLED !== "true" ||
    !settings.COLLECT_DEPLOYMENT_PROFILE
  ) {
    throw Error("gateway_disabled");
  }
  const profile = await verifyDeploymentProfile(settings);
  const profileSha256 = settings.COLLECT_DEPLOYMENT_PROFILE_SHA256!;
  const sourceSha256 = settings.BUILD_SOURCE_ID;
  const releaseSha256 = settings.COLLECT_SMS_RELEASE_SHA256;
  const approvalSha256 = settings.COLLECT_SMS_APPROVAL_SHA256;
  const rootToken = settings.COLLECT_SMS_ROOT_ADMIN_TOKEN;
  const otpKey = settings.COLLECT_SMS_OTP_HMAC_KEY;
  const maintenanceToken = settings.COLLECT_SMS_MAINTENANCE_TOKEN;
  if (
    profile.mode !== "managed" ||
    profile.environment !== settings.APP_ENVIRONMENT ||
    profile.supabase_origin !== settings.SUPABASE_URL ||
    !isDigest(sourceSha256) ||
    settings.COLLECT_SMS_CORE_SOURCE_SHA256 !== sourceSha256 ||
    !isDigest(releaseSha256) || !isDigest(approvalSha256) ||
    approvalSha256 === sourceSha256 || approvalSha256 === releaseSha256 ||
    !isSecret(rootToken) || !isSecret(otpKey) || rootToken === otpKey ||
    (maintenanceToken !== undefined &&
      (!isSecret(maintenanceToken) || maintenanceToken === rootToken ||
        maintenanceToken === otpKey))
  ) {
    throw Error("gateway_configuration");
  }
  for (
    const name of [
      "COLLECT_SMS_DISPATCH_PAUSED",
      "COLLECT_SMS_FCM_ENABLED",
      "COLLECT_SMS_RETENTION_AUTO_PURGE",
    ]
  ) {
    if (
      settings[name] !== undefined && settings[name] !== "true" &&
      settings[name] !== "false"
    ) {
      throw Error("gateway_configuration");
    }
  }
  const databaseUrl = managedGatewayDatabaseUrl(settings);
  const database = options.database ??
    new GatewayDatabase(gatewayConnection(databaseUrl, settings));
  const backend = options.fenceBackend ??
    smsFenceBackend(
      database.sql,
      gatewayConnection(databaseUrl, settings),
      profileSha256,
    );
  const env: Env = {
    ...settings,
    DB: database,
    ROOT_ADMIN_TOKEN: rootToken,
    OTP_HMAC_KEY: otpKey,
    ENVIRONMENT: "production",
    ALLOW_INSECURE_LOCALHOST: "false",
    ADMIN_ORIGIN: profile.admin_origin,
    DISPATCH_PAUSED: settings.COLLECT_SMS_DISPATCH_PAUSED === "false"
      ? "false"
      : "true",
    FCM_ENABLED: settings.COLLECT_SMS_FCM_ENABLED === "true" ? "true" : "false",
    RETENTION_AUTO_PURGE: settings.COLLECT_SMS_RETENTION_AUTO_PURGE === "true"
      ? "true"
      : "false",
  };
  return {
    profile,
    profileSha256,
    sourceSha256,
    releaseSha256,
    maintenanceToken,
    database,
    backend,
    env,
  };
}
