import {
  createGoogleDoc,
  logAiAudit,
  readGoogleWorkspaceConfig,
  sendGmail,
  uploadToDrive,
  upsertCalendarEvent,
} from "./google_workspace.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function snapshotEnv(
  keys: string[],
): Map<string, string | undefined> {
  return new Map(keys.map((key) => [key, Deno.env.get(key)]));
}

function restoreEnv(values: Map<string, string | undefined>): void {
  for (const [key, value] of values.entries()) {
    if (value == null) {
      Deno.env.delete(key);
      continue;
    }
    Deno.env.set(key, value);
  }
}

const googleWorkspaceEnvKeys = [
  "GOOGLE_SERVICE_ACCOUNT_EMAIL",
  "GOOGLE_PRIVATE_KEY",
  "AI_AUDIT_SHEET_ID",
];

Deno.test("readGoogleWorkspaceConfig normalizes values", () => {
  const config = readGoogleWorkspaceConfig({
    GOOGLE_SERVICE_ACCOUNT_EMAIL: " service-account@example.com ",
    GOOGLE_PRIVATE_KEY: "line1\\nline2",
    AI_AUDIT_SHEET_ID: " sheet-id ",
  });

  assertEquals(
    config.serviceAccountEmail,
    "service-account@example.com",
    "should trim service account email",
  );
  assertEquals(
    config.privateKey,
    "line1\nline2",
    "should normalize escaped newlines in the private key",
  );
  assertEquals(
    config.aiAuditSheetId,
    "sheet-id",
    "should trim the sheet id",
  );
});

Deno.test("Google Workspace actions fail closed when integration is not implemented", async () => {
  const env = snapshotEnv(googleWorkspaceEnvKeys);
  try {
    Deno.env.set("GOOGLE_SERVICE_ACCOUNT_EMAIL", "service-account@example.com");
    Deno.env.set("GOOGLE_PRIVATE_KEY", "line1\\nline2");
    Deno.env.set("AI_AUDIT_SHEET_ID", "sheet-id");

    const docUrl = await createGoogleDoc("Title", "Body");
    const driveUrl = await uploadToDrive("memo.txt", "Body");
    const gmailSent = await sendGmail(
      "admin@example.com",
      "Subject",
      "Body",
    );
    const calendarEventId = await upsertCalendarEvent({
      summary: "Contribution due",
      description: "Collect April contribution",
      start_date: "2026-04-10",
      end_date: "2026-04-10",
      category: "group_contribution",
    });

    assertEquals(docUrl, null, "createGoogleDoc should not return a fake URL");
    assertEquals(
      driveUrl,
      null,
      "uploadToDrive should not return a fake Drive URL",
    );
    assertEquals(
      gmailSent,
      false,
      "sendGmail should fail closed until the integration is implemented",
    );
    assertEquals(
      calendarEventId,
      null,
      "upsertCalendarEvent should not return a fake event id",
    );
  } finally {
    restoreEnv(env);
  }
});

Deno.test("logAiAudit remains non-fatal when the sink is unavailable", async () => {
  const env = snapshotEnv(googleWorkspaceEnvKeys);
  try {
    for (const key of googleWorkspaceEnvKeys) {
      Deno.env.delete(key);
    }

    await logAiAudit({
      function_name: "evaluate-transfer-risk",
      user_id: "user-1",
      model: "gemini",
      confidence: 0.9,
      decision: "ALLOW",
      metadata: { amount: 1200 },
      latency_ms: 42,
    });

    Deno.env.set("GOOGLE_SERVICE_ACCOUNT_EMAIL", "service-account@example.com");
    Deno.env.set("GOOGLE_PRIVATE_KEY", "line1\\nline2");
    Deno.env.set("AI_AUDIT_SHEET_ID", "sheet-id");

    await logAiAudit({
      function_name: "evaluate-transfer-risk",
      user_id: "user-2",
      model: "gemini",
      confidence: 0.7,
      decision: "WARN",
      metadata: { amount: 2400 },
      latency_ms: 64,
    });

    assert(true, "logAiAudit should complete without throwing");
  } finally {
    restoreEnv(env);
  }
});
