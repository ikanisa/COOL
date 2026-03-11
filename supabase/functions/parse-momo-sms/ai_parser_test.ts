import {
  buildPrompt,
  callGemini,
  callOpenAi,
  getAiProvider,
  normalizeParsedSms,
  type RawSmsRecord,
} from "./ai_parser.ts";

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

function assertStringIncludes(
  actual: string,
  expectedSubstring: string,
  message: string,
): void {
  if (!actual.includes(expectedSubstring)) {
    throw new Error(
      `${message}: expected "${actual}" to include "${expectedSubstring}"`,
    );
  }
}

const sampleRawSms: RawSmsRecord = {
  id: "sms-1",
  user_id: "user-1",
  sender: "M-Money",
  sms_body: "Payment of 10,000 RWF to COOL MARKET confirmed. TxId: ABC12345.",
  provider: "mtn_rwanda",
  country: "RW",
  sms_received_at: "2026-03-11T15:00:00.000Z",
  detected_tx_type: "payment",
  detected_amount: 10000,
  detected_tx_id: "ABC12345",
};

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("buildPrompt includes raw SMS context and extraction hints", () => {
  const prompt = buildPrompt(sampleRawSms);

  assertStringIncludes(prompt, "User ID: user-1", "prompt should include user");
  assertStringIncludes(
    prompt,
    "Sender: M-Money",
    "prompt should include sender",
  );
  assertStringIncludes(
    prompt,
    sampleRawSms.sms_body,
    "prompt should include the raw SMS body",
  );
  assertStringIncludes(
    prompt,
    "Return JSON only matching the schema.",
    "prompt should enforce structured output",
  );
});

Deno.test("getAiProvider uses explicit override and safe default", () => {
  assertEquals(getAiProvider("gemini"), "gemini", "explicit gemini should win");
  assertEquals(getAiProvider("openai"), "openai", "explicit openai should win");
  assertEquals(
    getAiProvider("unexpected"),
    "gemini",
    "unknown providers should fall back to gemini when no provider is configured",
  );
});

Deno.test("callOpenAi builds a Responses API request and extracts nested JSON text", async () => {
  let capturedUrl = "";
  let capturedBody: Record<string, unknown> = {};
  let capturedHeaders: HeadersInit | undefined;
  const responseText = '{"parse_status":"parsed","tx_type":"payment"}';

  const result = await callOpenAi("prompt body", {
    apiKey: "test-openai-key",
    model: "gpt-test",
    fetchFn: async (input, init) => {
      capturedUrl = typeof input === "string" ? input : input.toString();
      capturedHeaders = init?.headers;
      capturedBody = JSON.parse(String(init?.body));
      return jsonResponse({
        output: [
          {
            content: [
              { text: responseText },
            ],
          },
        ],
      });
    },
  });

  const headers = capturedHeaders as Record<string, string>;
  assertEquals(
    capturedUrl,
    "https://api.openai.com/v1/responses",
    "OpenAI URL should target the Responses API",
  );
  assertEquals(result.model, "gpt-test", "model should round-trip");
  assertEquals(result.text, responseText, "should extract JSON text");
  assertEquals(
    headers.Authorization,
    "Bearer test-openai-key",
    "should send bearer auth",
  );
  assertEquals(
    capturedBody.model as string,
    "gpt-test",
    "request should include the selected model",
  );
});

Deno.test("callGemini builds a generateContent request and extracts candidate JSON text", async () => {
  let capturedUrl = "";
  let capturedBody: Record<string, unknown> = {};
  const responseText = '{"parse_status":"needs_review","tx_type":"received"}';

  const result = await callGemini("prompt body", {
    apiKey: "test-gemini-key",
    model: "gemini-test",
    fetchFn: async (input, init) => {
      capturedUrl = typeof input === "string" ? input : input.toString();
      capturedBody = JSON.parse(String(init?.body));
      return jsonResponse({
        candidates: [
          {
            content: {
              parts: [{ text: responseText }],
            },
          },
        ],
      });
    },
  });

  assertStringIncludes(
    capturedUrl,
    "models/gemini-test:generateContent?key=test-gemini-key",
    "Gemini URL should embed model and API key",
  );
  assertEquals(result.model, "gemini-test", "model should round-trip");
  assertEquals(result.text, responseText, "should extract Gemini JSON text");
  assertEquals(
    (capturedBody.generationConfig as Record<string, unknown>)
      .responseMimeType as string,
    "application/json",
    "Gemini request should force JSON output",
  );
});

Deno.test("normalizeParsedSms sanitizes vendor output into stable parsed records", () => {
  const parsed = normalizeParsedSms({
    parse_status: "PARSED",
    confidence: "1.8",
    tx_direction: "credit",
    tx_type: "payment",
    tx_category: "merchant_payment",
    cashflow_bucket: "expense",
    momo_tx_id: " ABC12345 ",
    amount: "10,000 RWF",
    currency: "",
    tx_date: "2026-03-11",
    tx_time: "15:00:00",
    tx_datetime_iso: "2026-03-11T15:00:00.000Z",
    payer_name: "Alice",
    payer_number_last3: "0788-123-456",
    payer_number_full: "0788123456",
    payee_name: "Cool Market",
    payee_number_or_code: "*182*8*1#",
    merchant_code: "MER-99",
    fee_amount: "75 RWF",
    balance_after: "2,500",
    counterparty_name: "Cool Market",
    ai_summary: "Paid Cool Market for groceries",
    recurring_pattern_hint: "one_off",
    narrative: "Groceries",
    notes: "Confirmed by merchant",
  });

  assertEquals(parsed.parse_status, "parsed", "status should normalize");
  assertEquals(parsed.confidence, 1, "confidence should clamp to 1");
  assertEquals(parsed.amount, 10000, "amount should parse to integer");
  assertEquals(parsed.currency, "RWF", "blank currency should default");
  assertEquals(
    parsed.tx_category,
    "merchant_payment",
    "category should persist",
  );
  assertEquals(
    parsed.cashflow_bucket,
    "expense",
    "cashflow bucket should persist",
  );
  assertEquals(
    parsed.payer_number_last3,
    "456",
    "last3 should keep visible digits only",
  );
  assertEquals(parsed.fee_amount, 75, "fee should parse to integer");
  assertEquals(parsed.balance_after, 2500, "balance should parse to integer");
  assertEquals(
    parsed.counterparty_name,
    "Cool Market",
    "counterparty should persist",
  );
  assertEquals(
    parsed.ai_summary,
    "Paid Cool Market for groceries",
    "summary should persist",
  );
});

Deno.test("callOpenAi fails cleanly when the vendor payload has no text output", async () => {
  let threw = false;
  try {
    await callOpenAi("prompt body", {
      apiKey: "test-openai-key",
      model: "gpt-test",
      fetchFn: async () => jsonResponse({ output: [] }),
    });
  } catch (error) {
    threw = true;
    assertStringIncludes(
      error instanceof Error ? error.message : String(error),
      "structured output text",
      "missing text should produce a useful error",
    );
  }

  assert(threw, "OpenAI helper should throw when no text is returned");
});
