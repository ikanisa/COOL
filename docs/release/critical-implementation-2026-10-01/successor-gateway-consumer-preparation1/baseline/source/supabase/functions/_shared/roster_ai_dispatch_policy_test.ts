import { assertEquals } from "./test_assert.ts";
import { PublicError } from "./production_contract.ts";
import { rosterSha256 } from "./roster_provenance.ts";
import {
  assertRosterAiDispatchApproval,
  prepareRosterAiDispatchApproval,
  type RosterAiConfiguration,
  snapshotRosterAiConfiguration,
} from "./roster_ai_dispatch_policy.ts";
import {
  SYNTHETIC_ROSTER_AI_CONFIGURATION,
  syntheticRosterAiApproval,
} from "./roster_ai_dispatch_test_fixture.ts";
const encoder = new TextEncoder();
function configuration(): RosterAiConfiguration {
  return {
    ...SYNTHETIC_ROSTER_AI_CONFIGURATION,
    model: "fixture-model",
    apiKey: "synthetic-not-a-real-key",
    decoderUrl: "http://localhost/decode",
    decoderSecret: "synthetic-secret-not-a-real-signing-key",
    decoderBuildSha256: "d".repeat(64),
  };
}
async function denied(run: () => unknown): Promise<void> {
  try {
    await run();
  } catch (error) {
    assertEquals(error instanceof PublicError, true);
    const publicError = error as PublicError;
    assertEquals(publicError.code, "roster_extraction_unavailable");
    assertEquals(publicError.status, 503);
    assertEquals(publicError.message, "roster_extraction_unavailable");
    return;
  }
  throw new Error("Expected safe default-deny response");
}
Deno.test("AI policy snapshot copies immutable primitive configuration without freezing caller", async () => {
  const current = configuration(),
    snapshot = snapshotRosterAiConfiguration(current);
  assertEquals(Object.isFrozen(current), false);
  assertEquals(Object.isFrozen(snapshot), true);
  const approved = await prepareRosterAiDispatchApproval(snapshot);
  assertEquals(Object.isFrozen(approved), true);
  assertEquals(Object.keys(approved).sort(), [
    "approvedAt",
    "organizationId",
    "policySha256",
    "projectId",
    "validUntil",
  ]);
  current.apiKey = "changed-synthetic-key";
  assertEquals(snapshot.apiKey, "synthetic-not-a-real-key");
  await denied(() =>
    assertRosterAiDispatchApproval(snapshot, approved, current)
  );
});
for (
  const [label, raw] of [
    ["array", "[]"],
    ["null", "null"],
    ["scalar", "true"],
    ["malformed", "{"],
    [
      "duplicate enabled key",
      SYNTHETIC_ROSTER_AI_CONFIGURATION.aiApprovalJson.replace(
        '"enabled":true',
        '"enabled":false,"enabled":true',
      ),
    ],
    [
      "noncanonical interior whitespace",
      SYNTHETIC_ROSTER_AI_CONFIGURATION.aiApprovalJson.replace(
        '"enabled":true',
        '"enabled": true',
      ),
    ],
    ["too many bytes", "é".repeat(4097)],
  ] as const
) {
  Deno.test(`AI policy ${label} never authorizes dispatch`, async () => {
    const config = configuration();
    config.aiApprovalJson = raw;
    config.aiApprovalSha256 = await rosterSha256(encoder.encode(raw));
    await denied(() =>
      prepareRosterAiDispatchApproval(snapshotRosterAiConfiguration(config))
    );
  });
}
for (
  const [label, patch] of [
    ["invalid approval ID", { approval_id: "not-an-approval-id" }],
    ["invalid approval evidence digest", {
      approval_evidence_sha256: "F".repeat(64),
    }],
    ["missing field", { decoder_retention_evidence_ref: undefined }],
    ["invalid evidence reference", {
      retention_evidence_ref: "record\nAuthorization: secret",
    }],
    ["wrong schema", { schema_version: 2 }],
    ["impossible calendar", { approved_at: "2026-02-30T00:00:00Z" }],
    ["no timezone", { approved_at: "2020-01-01T00:00:00" }],
    ["reversed window", {
      approved_at: "2099-01-01T00:00:00Z",
      valid_until: "2020-01-01T00:00:00Z",
    }],
    ["window equal", {
      approved_at: "2020-01-01T00:00:00Z",
      valid_until: "2020-01-01T00:00:00Z",
    }],
  ] as const
) {
  Deno.test(`AI policy ${label} stays default denied`, async () => {
    const config = configuration();
    Object.assign(
      config,
      await syntheticRosterAiApproval(
        config.model,
        config.decoderUrl,
        config.decoderBuildSha256,
        patch,
      ),
    );
    await denied(() =>
      prepareRosterAiDispatchApproval(snapshotRosterAiConfiguration(config))
    );
  });
}
for (
  const url of [
    "http://foreign.invalid/decode",
    "https://user:password@decoder.invalid/decode",
    "https://decoder.invalid/decode?token=synthetic",
    "https://decoder.invalid/decode#fragment",
    "https://decoder.invalid/not-decode",
    "file:///decode",
  ]
) {
  Deno.test(`AI policy matching but unsafe decoder tuple rejects ${new URL(url).protocol}`, async () => {
    const config = configuration();
    config.decoderUrl = url;
    Object.assign(
      config,
      await syntheticRosterAiApproval(
        config.model,
        url,
        config.decoderBuildSha256,
      ),
    );
    await denied(() =>
      prepareRosterAiDispatchApproval(snapshotRosterAiConfiguration(config))
    );
  });
}
Deno.test("AI policy exact beginning permits dispatch and exact expiration denies it synchronously", async () => {
  const originalNow = Date.now, config = configuration();
  const starts = Date.parse("2026-10-02T00:00:00Z"), ends = starts + 60000;
  Object.assign(
    config,
    await syntheticRosterAiApproval(
      config.model,
      config.decoderUrl,
      config.decoderBuildSha256,
      {
        approved_at: new Date(starts).toISOString(),
        valid_until: new Date(ends).toISOString(),
      },
    ),
  );
  const snapshot = snapshotRosterAiConfiguration(config);
  try {
    Date.now = () => starts;
    const approval = await prepareRosterAiDispatchApproval(snapshot);
    assertRosterAiDispatchApproval(snapshot, approval, config);
    Date.now = () => ends - 1;
    assertRosterAiDispatchApproval(snapshot, approval, config);
    Date.now = () => ends;
    await denied(() =>
      assertRosterAiDispatchApproval(snapshot, approval, config)
    );
  } finally {
    Date.now = originalNow;
  }
});
Deno.test("AI policy whole JSON pin binds its original UTF8 bytes including outer whitespace", async () => {
  const config = configuration();
  config.aiApprovalJson += "\n";
  await denied(() =>
    prepareRosterAiDispatchApproval(snapshotRosterAiConfiguration(config))
  );
  config.aiApprovalSha256 = await rosterSha256(
    encoder.encode(config.aiApprovalJson),
  );
  const approval = await prepareRosterAiDispatchApproval(
    snapshotRosterAiConfiguration(config),
  );
  assertRosterAiDispatchApproval(
    snapshotRosterAiConfiguration(config),
    approval,
    config,
  );
});
