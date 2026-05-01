import {
  createEvaluateTransferRiskHandler,
  type EvaluateTransferRiskDependencies,
} from "./index.ts";

type AuditEvent = Parameters<EvaluateTransferRiskDependencies["logAiAudit"]>[0];
type AdminClient = ReturnType<
  EvaluateTransferRiskDependencies["createAdminClient"]
>;
type UserClient = ReturnType<
  EvaluateTransferRiskDependencies["createUserClient"]
>;

function expectEquals<T>(actual: T, expected: T, message: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function expect(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

function buildRequest(body: unknown = {
  recipientNumber: "+250788222222",
  amount: 100000,
  currency: "RWF",
}) {
  return new Request(
    "https://example.com/functions/v1/evaluate-transfer-risk",
    {
      method: "POST",
      headers: {
        authorization: "Bearer caller-token",
        "content-type": "application/json",
      },
      body: typeof body === "string" ? body : JSON.stringify(body),
    },
  );
}

function buildAdminClient(rows: Array<Record<string, unknown>>): AdminClient {
  const query = {
    select: () => query,
    eq: () => query,
    gte: () => query,
    order: () => query,
    limit: async () => ({ data: rows, error: null }),
  };

  return {
    from: () => query,
  } as unknown as AdminClient;
}

function buildUserClient(): UserClient {
  return {
    auth: {
      getUser: async () => ({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
  } as unknown as UserClient;
}

function buildDeps(options: {
  fetchImpl: typeof fetch;
  rows?: Array<Record<string, unknown>>;
}) {
  const audits: AuditEvent[] = [];
  const deps: EvaluateTransferRiskDependencies = {
    createAdminClient: () => buildAdminClient(options.rows ?? []),
    createUserClient: () => buildUserClient(),
    fetch: options.fetchImpl,
    getGeminiApiKey: () => "gemini-secret",
    logAiAudit: async (event) => {
      audits.push(event);
    },
    now: () => new Date("2026-05-01T12:00:00.000Z"),
  };

  return { deps, audits };
}

Deno.test("evaluate-transfer-risk fails closed to review when Gemini fails", async () => {
  const { deps, audits } = buildDeps({
    fetchImpl: async () => new Response("upstream down", { status: 503 }),
    rows: [
      {
        amount: 1000,
        counterparty_name: null,
        description: null,
        statement_label: null,
        metadata: { recipient_number: "+250788111111" },
      },
    ],
  });
  const handler = createEvaluateTransferRiskHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();

  expectEquals(response.status, 200, "fallback response status");
  expectEquals(payload.success, true, "fallback response success");
  expectEquals(
    payload.data.action_suggestion,
    "review",
    "AI outage must not allow transfer",
  );
  expectEquals(payload.data.is_anomaly, true, "fallback anomaly state");
  expect(
    payload.data.risk_score >= 0.65,
    "fallback risk score should be review-grade",
  );
  expectEquals(audits.length, 1, "fallback audit count");
  expectEquals(audits[0].decision, "REVIEW", "fallback audit decision");
  expectEquals(
    audits[0].metadata.recipient,
    "***2222",
    "audit should not log full recipient",
  );
  expectEquals(
    audits[0].metadata.ai_fallback,
    true,
    "fallback audit marker",
  );
});

Deno.test("evaluate-transfer-risk returns normalized AI decision and masked audit metadata", async () => {
  const aiResult = {
    risk_score: 0.2,
    is_anomaly: false,
    reason: "Known recipient with normal amount.",
    warning_title: "",
    warning_body: "",
    trust_score: 0.9,
    action_suggestion: "allow",
  };
  const { deps, audits } = buildDeps({
    fetchImpl: async () =>
      Response.json({
        candidates: [
          {
            content: {
              parts: [{ text: JSON.stringify(aiResult) }],
            },
          },
        ],
      }),
    rows: [
      {
        amount: 95000,
        counterparty_name: null,
        description: null,
        statement_label: null,
        metadata: { recipient_number: "+250788222222" },
      },
    ],
  });
  const handler = createEvaluateTransferRiskHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();

  expectEquals(response.status, 200, "AI response status");
  expectEquals(payload.data.action_suggestion, "allow", "AI action");
  expectEquals(payload.data.risk_score, 0.2, "AI risk score");
  expectEquals(audits.length, 1, "AI audit count");
  expectEquals(audits[0].decision, "ALLOW", "AI audit decision");
  expectEquals(
    audits[0].metadata.recipient,
    "***2222",
    "AI audit should mask recipient",
  );
});

Deno.test("evaluate-transfer-risk rejects invalid JSON before external AI calls", async () => {
  let fetchCalls = 0;
  const { deps } = buildDeps({
    fetchImpl: async () => {
      fetchCalls++;
      return Response.json({});
    },
  });
  const handler = createEvaluateTransferRiskHandler(deps);

  const response = await handler(buildRequest("{"));
  const payload = await response.json();

  expectEquals(response.status, 400, "invalid JSON status");
  expectEquals(payload.message, "Invalid JSON body.", "invalid JSON message");
  expectEquals(fetchCalls, 0, "AI fetch should not be called");
});
