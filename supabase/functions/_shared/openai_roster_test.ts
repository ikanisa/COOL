import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildRosterResponsesRequest,
  previewOpenAiRoster,
  responseOutputText,
} from "./openai_roster.ts";

Deno.test("OpenAI roster request is strict, non-persistent and tool-free", () => {
  const request = buildRosterResponsesRequest(
    "configured-model",
    "pdf",
    "members.pdf",
    "application/pdf",
    "cGRm",
  );
  assertEquals(request.model, "configured-model");
  assertEquals(request.store, false);
  assertEquals("tools" in request, false);
  const format = (request.text as Record<string, unknown>).format as Record<
    string,
    unknown
  >;
  assertEquals(format.type, "json_schema");
  assertEquals(format.strict, true);
});

Deno.test("OpenAI roster output is normalized and remains review-only", () => {
  const preview = previewOpenAiRoster({
    output: [{
      content: [{
        type: "output_text",
        text: JSON.stringify({
          rows: [{
            source_row: 4,
            member_name: "  Aline Uwase ",
            momo_name: "ALINE UWASE",
            momo_number: "0788123456",
            confidence: 0.91,
          }],
        }),
      }],
    }],
  });
  assertEquals(preview.can_submit, true);
  assertEquals(preview.normalized_rows[0].momo_number, "+250788123456");
});

Deno.test("refusals and malformed model output fail closed", () => {
  assertThrows(
    () => responseOutputText({ output: [{ content: [{ type: "refusal" }] }] }),
    Error,
    "declined",
  );
  assertThrows(
    () => previewOpenAiRoster({ output_text: "not json" }),
    Error,
    "not valid JSON",
  );
});
