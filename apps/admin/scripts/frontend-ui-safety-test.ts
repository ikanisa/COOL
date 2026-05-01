import {
  isSensitiveConfigKey,
  maskConfigValue,
} from "../src/lib/sensitive-values.ts";

function expectEquals<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

Deno.test("sensitive config keys are masked before rendering", () => {
  expectEquals(isSensitiveConfigKey("supabase_service_role_key"), true, "service role");
  expectEquals(isSensitiveConfigKey("whatsapp_webhook_secret"), true, "webhook secret");
  expectEquals(isSensitiveConfigKey("firebase_credentials_json"), true, "credentials");
  expectEquals(maskConfigValue("api_token", "abc123").value, "••••••••", "masked token");
  expectEquals(maskConfigValue("api_token", "abc123").masked, true, "masked flag");
});

Deno.test("non-sensitive operational config remains visible", () => {
  const value = maskConfigValue("momo_sms_sender_allowlist", "M-MONEY,MTN");

  expectEquals(isSensitiveConfigKey("momo_sms_sender_allowlist"), false, "allowlist");
  expectEquals(value.value, "M-MONEY,MTN", "visible allowlist");
  expectEquals(value.masked, false, "visible flag");
});
