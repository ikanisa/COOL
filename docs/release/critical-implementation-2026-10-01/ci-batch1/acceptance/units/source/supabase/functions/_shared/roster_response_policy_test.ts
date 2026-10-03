import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PublicError, publicFailure } from "./production_contract.ts";
import { previewOpenAiRoster, responseOutputText } from "./openai_roster.ts";
import {
  MAX_ROSTER_OUTPUT_BYTES,
  MAX_ROSTER_PROVIDER_BYTES,
  rosterResponseCandidates,
} from "./roster_response_policy.ts";

const candidate = () => ({
  source_row: 1,
  member_name: "Aline Uwase",
  momo_name: "ALINE UWASE",
  momo_number: "0788123456",
  confidence: 0.95,
});
function envelope(rows: unknown = [candidate()]): Record<string, unknown> {
  return rawEnvelope(JSON.stringify({ rows }));
}
function message(content: unknown): Record<string, unknown> {
  return {
    id: "msg_fixture",
    type: "message",
    role: "assistant",
    status: "completed",
    content,
  };
}
function rawEnvelope(text: string): Record<string, unknown> {
  return {
    id: "resp_fixture",
    object: "response",
    status: "completed",
    error: null,
    incomplete_details: null,
    tools: [],
    output: [message([{ type: "output_text", annotations: [], text }])],
  };
}
function rejected(
  value: unknown,
  code = "roster_provider_response_invalid",
  status = 502,
): void {
  const error = assertThrows(() => previewOpenAiRoster(value), PublicError);
  assertEquals(publicFailure(error), { error: code, status });
}
Deno.test("strict roster response preserves multilingual source strings and stays non-submittable", () => {
  const names = [
    "Niyonzima Élodie",
    "سارة أحمد",
    "王美玲",
    "अनीता शर्मा",
    "N’Dah Jean-Paul",
  ];
  for (const name of names) {
    const response = envelope([{
      ...candidate(),
      member_name: name,
      momo_name: name,
    }]);
    const before = JSON.stringify(response),
      preview = previewOpenAiRoster(response);
    assertEquals(preview.ready_count, 1);
    assertEquals(preview.rows[0].member_name, name);
    assertEquals(preview.normalized_rows[0].member_name, name);
    assertEquals(preview.can_submit, false);
    assertEquals(JSON.stringify(response), before);
  }
});
Deno.test("strict roster response supports supplementary Unicode names at the schema character limit", () => {
  const name = "𠀀".repeat(120);
  const preview = previewOpenAiRoster(
    envelope([{ ...candidate(), member_name: name, momo_name: name }]),
  );
  assertEquals(preview.ready_count, 1);
  assertEquals(preview.rows[0].member_name, name);
  rejected(envelope([{ ...candidate(), member_name: name + "𠀀" }]));
});
Deno.test("bounded reasoning metadata is accepted and never returned as roster content", () => {
  const response = envelope();
  (response.output as unknown[]).unshift({
    id: "rs_fixture",
    type: "reasoning",
    summary: [{ type: "summary_text", text: "Synthetic summary" }],
    content: [{ type: "reasoning_text", text: "Synthetic reasoning" }],
    encrypted_content: "encrypted-fixture",
    status: "completed",
  });
  const preview = previewOpenAiRoster(response);
  assertEquals(preview.row_count, 1);
  assertEquals(JSON.stringify(preview).includes("Synthetic"), false);
});
Deno.test("matching SDK text alias cannot bypass canonical envelope validation", () => {
  const response = envelope(), canonical = responseOutputText(response);
  response.output_text = canonical;
  assertEquals(responseOutputText(response), canonical);
  response.output_text = JSON.stringify({
    rows: [{ ...candidate(), member_name: "Different" }],
  });
  rejected(response);
  rejected({ output_text: canonical });
});
for (
  const status of [
    undefined,
    null,
    "in_progress",
    "queued",
    "failed",
    "cancelled",
    "unexpected",
  ]
) {
  Deno.test(`reject non-completed response status ${String(status)}`, () => {
    const value = envelope();
    if (status === undefined) delete value.status;
    else value.status = status;
    rejected(value);
  });
}
Deno.test("incomplete and refusal response codes contain no provider content", () => {
  rejected(
    { ...envelope(), status: "incomplete" },
    "roster_extraction_incomplete",
  );
  rejected(
    {
      ...envelope(),
      output: [
        message([{ type: "refusal", refusal: "sensitive provider detail" }]),
      ],
    },
    "roster_extraction_refused",
    422,
  );
});
Deno.test("extra message, text, refusal and tool items all fail closed", () => {
  const valid = envelope().output as unknown[];
  for (
    const extra of [
      valid[0],
      { type: "function_call", name: "create_member", arguments: "{}" },
      { type: "web_search_call" },
      { type: "refusal", refusal: "private" },
      null,
      42,
    ]
  ) rejected({ ...envelope(), output: [...valid, extra] });
  const text = (valid[0] as Record<string, unknown>).content as unknown[];
  for (
    const extra of [text[0], { type: "refusal", refusal: "private" }, {
      type: "output_audio",
      audio: "data",
    }]
  ) rejected({ ...envelope(), output: [message([...text, extra])] });
});
Deno.test("message status, role, phase and shape must be explicit supported output", () => {
  const original = (envelope().output as Record<string, unknown>[])[0];
  for (
    const patch of [
      { status: "in_progress" },
      { role: "user" },
      { phase: "commentary" },
      { type: "function_call" },
      { content: [] },
      { extra: "payload" },
      { id: 3 },
    ]
  ) rejected({ ...envelope(), output: [{ ...original, ...patch }] });
  for (const key of ["status", "role", "type", "id", "content"]) {
    const item = { ...original };
    delete item[key];
    rejected({ ...envelope(), output: [item] });
  }
});
Deno.test("nonempty tools, annotations and logprobs are unsupported in this tool-free contract", () => {
  rejected({ ...envelope(), tools: [{ type: "web_search" }] });
  const text = responseOutputText(envelope());
  for (
    const patch of [
      { annotations: [{ type: "url_citation", url: "https://example.test" }] },
      { annotations: null },
      { logprobs: [{ token: "x" }] },
      { unknown: true },
    ]
  ) {
    rejected({
      ...envelope(),
      output: [
        message([{ type: "output_text", text, annotations: [], ...patch }]),
      ],
    });
  }
});
Deno.test("nonempty error and incomplete details cannot coexist with completed success", () => {
  rejected({ ...envelope(), error: { message: "sensitive", code: "vendor" } });
  rejected({
    ...envelope(),
    incomplete_details: { reason: "max_output_tokens" },
  });
});
Deno.test("unsupported or malformed reasoning structures fail closed", () => {
  for (
    const patch of [
      { summary: null },
      { summary: [{ type: "function_call", text: "x" }] },
      { content: [{ type: "output_text", text: "x" }] },
      { status: "incomplete" },
      { encrypted_content: {} },
      { unknown: [] },
    ]
  ) {
    const response = envelope();
    (response.output as unknown[]).unshift({
      id: "rs_fixture",
      type: "reasoning",
      summary: [],
      ...patch,
    });
    rejected(response);
  }
});
Deno.test("overlong output is bounded by UTF-8 bytes before JSON parsing", () => {
  for (
    const text of [
      " ".repeat(MAX_ROSTER_OUTPUT_BYTES) + "{}",
      "é".repeat(MAX_ROSTER_OUTPUT_BYTES / 2 + 1),
    ]
  ) rejected(rawEnvelope(text), "roster_provider_response_too_large");
});
Deno.test("oversized or deeply nested provider metadata is rejected iteratively", () => {
  rejected({
    ...envelope(),
    metadata: { padding: "x".repeat(MAX_ROSTER_PROVIDER_BYTES) },
  }, "roster_provider_response_too_large");
  let nested: unknown = {};
  for (let i = 0; i < 18; i++) nested = { nested };
  rejected(
    { ...envelope(), metadata: nested },
    "roster_provider_response_too_large",
  );
  rejected(
    { ...envelope(), metadata: Array.from({ length: 20_001 }, () => 0) },
    "roster_provider_response_too_large",
  );
  const cyclic = envelope();
  cyclic.metadata = cyclic;
  rejected(cyclic);
});
Deno.test("malformed, deeply nested, duplicate-key and unknown document fields fail closed", () => {
  for (
    const value of [
      "not JSON",
      "[]",
      "null",
      '{"rows":[]}',
      JSON.stringify({ rows: [candidate()], can_submit: true }),
      '{"rows":[],"rows":[' + JSON.stringify(candidate()) + "]}",
      '{"rows":[],"r\\u006fws":[' + JSON.stringify(candidate()) + "]}",
    ]
  ) rejected(rawEnvelope(value));
  rejected(
    rawEnvelope('{"rows":' + "[".repeat(20) + "0" + "]".repeat(20) + "}"),
    "roster_provider_response_too_large",
  );
  const duplicate = JSON.stringify(candidate()).replace(
    '"confidence":0.95',
    '"confidence":0.1,"confidence":0.95',
  );
  rejected(rawEnvelope('{"rows":[' + duplicate + "]}"));
});
Deno.test("only exact typed row fields are accepted without fallback aliases or coercion", () => {
  for (
    const patch of [
      { source_row: "1" },
      { source_row: 0 },
      { source_row: 1.5 },
      { source_row: Number.MAX_SAFE_INTEGER + 1 },
      { confidence: "0.99" },
      { confidence: null },
      { confidence: true },
      { confidence: -0.1 },
      { confidence: 1.1 },
      { member_name: [] },
      { momo_name: {} },
      { momo_number: 788123456 },
      { extra: "ignored before" },
    ]
  ) rejected(envelope([{ ...candidate(), ...patch }]));
  for (const key of Object.keys(candidate())) {
    const row: Record<string, unknown> = candidate();
    delete row[key];
    rejected(envelope([row]));
  }
  rejected(
    envelope([{
      name: "Alice",
      registered_name: "Alice",
      phone: "0788123456",
      confidence: 1,
      source_row: 1,
    }]),
  );
});
Deno.test("all row string limits and invalid control/unicode sequences are enforced before normalization", () => {
  for (
    const patch of [
      { member_name: "a".repeat(121) },
      { momo_name: "a".repeat(121) },
      { momo_number: "1".repeat(33) },
      { member_name: "A\nB" },
      { momo_number: "0788\t123456" },
      { member_name: "A\ud800B" },
      { momo_name: "A\udc00B" },
    ]
  ) rejected(envelope([{ ...candidate(), ...patch }]));
});
Deno.test("empty unreadable fields, low confidence and duplicate phones stay visible for correction", () => {
  const preview = previewOpenAiRoster(
    envelope([candidate(), { ...candidate(), source_row: 2, confidence: 0.5 }, {
      source_row: 3,
      member_name: "",
      momo_name: "",
      momo_number: "",
      confidence: 0,
    }]),
  );
  assertEquals(preview.row_count, 3);
  assertEquals(preview.error_count, 2);
  assertEquals(preview.can_submit, false);
  assertEquals(preview.rows[2].member_name, "");
});
Deno.test("500 candidate boundary is enforced without truncation", () => {
  const rows = Array.from(
    { length: 500 },
    (_, i) => ({ ...candidate(), source_row: i + 1 }),
  );
  assertEquals(rosterResponseCandidates(envelope(rows)).length, 500);
  assertEquals(previewOpenAiRoster(envelope(rows)).row_count, 500);
  rejected(envelope([...rows, candidate()]));
});
