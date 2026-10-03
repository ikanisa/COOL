import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PublicError, publicFailure } from "./production_contract.ts";
import { previewOpenAiRoster, responseOutputText } from "./openai_roster.ts";
import { MAX_ROSTER_OUTPUT_BYTES, MAX_ROSTER_PROVIDER_BYTES, rosterResponseCandidates } from "./roster_response_policy.ts";
const candidate = ()=>({
    source_row: 1,
    member_name: "Aline Uwase",
    momo_name: "ALINE UWASE",
    momo_number: "0788123456",
    confidence: 0.95
  });
function envelope(rows = [
  candidate()
]) {
  return rawEnvelope(JSON.stringify({
    rows
  }));
}
function message(content) {
  return {
    id: "msg_fixture",
    type: "message",
    role: "assistant",
    status: "completed",
    content
  };
}
function rawEnvelope(text) {
  return {
    id: "resp_fixture",
    object: "response",
    status: "completed",
    error: null,
    incomplete_details: null,
    tools: [],
    output: [
      message([
        {
          type: "output_text",
          annotations: [],
          text
        }
      ])
    ]
  };
}
function rejected(value, code = "roster_provider_response_invalid", status = 502) {
  const error = assertThrows(()=>previewOpenAiRoster(value), PublicError);
  assertEquals(publicFailure(error), {
    error: code,
    status
  });
}
Deno.test("strict roster response preserves multilingual source strings and stays non-submittable", ()=>{
  const names = [
    "Niyonzima Élodie",
    "سارة أحمد",
    "王美玲",
    "अनीता शर्मा",
    "N’Dah Jean-Paul"
  ];
  for (const name of names){
    const response = envelope([
      {
        ...candidate(),
        member_name: name,
        momo_name: name
      }
    ]);
    const before = JSON.stringify(response), preview = previewOpenAiRoster(response);
    assertEquals(preview.ready_count, 1);
    assertEquals(preview.rows[0].member_name, name);
    assertEquals(preview.normalized_rows[0].member_name, name);
    assertEquals(preview.can_submit, false);
    assertEquals(JSON.stringify(response), before);
  }
});
Deno.test("strict roster response supports supplementary Unicode names at the schema character limit", ()=>{
  const name = "𠀀".repeat(120);
  const preview = previewOpenAiRoster(envelope([
    {
      ...candidate(),
      member_name: name,
      momo_name: name
    }
  ]));
  assertEquals(preview.ready_count, 1);
  assertEquals(preview.rows[0].member_name, name);
  rejected(envelope([
    {
      ...candidate(),
      member_name: name + "𠀀"
    }
  ]));
});
Deno.test("bounded reasoning metadata is accepted and never returned as roster content", ()=>{
  const response = envelope();
  response.output.unshift({
    id: "rs_fixture",
    type: "reasoning",
    summary: [
      {
        type: "summary_text",
        text: "Synthetic summary"
      }
    ],
    content: [
      {
        type: "reasoning_text",
        text: "Synthetic reasoning"
      }
    ],
    encrypted_content: "encrypted-fixture",
    status: "completed"
  });
  const preview = previewOpenAiRoster(response);
  assertEquals(preview.row_count, 1);
  assertEquals(JSON.stringify(preview).includes("Synthetic"), false);
});
Deno.test("matching SDK text alias cannot bypass canonical envelope validation", ()=>{
  const response = envelope(), canonical = responseOutputText(response);
  response.output_text = canonical;
  assertEquals(responseOutputText(response), canonical);
  response.output_text = JSON.stringify({
    rows: [
      {
        ...candidate(),
        member_name: "Different"
      }
    ]
  });
  rejected(response);
  rejected({
    output_text: canonical
  });
});
for (const status of [
  undefined,
  null,
  "in_progress",
  "queued",
  "failed",
  "cancelled",
  "unexpected"
]){
  Deno.test(`reject non-completed response status ${String(status)}`, ()=>{
    const value = envelope();
    if (status === undefined) delete value.status;
    else value.status = status;
    rejected(value);
  });
}
Deno.test("incomplete and refusal response codes contain no provider content", ()=>{
  rejected({
    ...envelope(),
    status: "incomplete"
  }, "roster_extraction_incomplete");
  rejected({
    ...envelope(),
    output: [
      message([
        {
          type: "refusal",
          refusal: "sensitive provider detail"
        }
      ])
    ]
  }, "roster_extraction_refused", 422);
});
Deno.test("extra message, text, refusal and tool items all fail closed", ()=>{
  const valid = envelope().output;
  for (const extra of [
    valid[0],
    {
      type: "function_call",
      name: "create_member",
      arguments: "{}"
    },
    {
      type: "web_search_call"
    },
    {
      type: "refusal",
      refusal: "private"
    },
    null,
    42
  ])rejected({
    ...envelope(),
    output: [
      ...valid,
      extra
    ]
  });
  const text = valid[0].content;
  for (const extra of [
    text[0],
    {
      type: "refusal",
      refusal: "private"
    },
    {
      type: "output_audio",
      audio: "data"
    }
  ])rejected({
    ...envelope(),
    output: [
      message([
        ...text,
        extra
      ])
    ]
  });
});
Deno.test("message status, role, phase and shape must be explicit supported output", ()=>{
  const original = envelope().output[0];
  for (const patch of [
    {
      status: "in_progress"
    },
    {
      role: "user"
    },
    {
      phase: "commentary"
    },
    {
      type: "function_call"
    },
    {
      content: []
    },
    {
      extra: "payload"
    },
    {
      id: 3
    }
  ])rejected({
    ...envelope(),
    output: [
      {
        ...original,
        ...patch
      }
    ]
  });
  for (const key of [
    "status",
    "role",
    "type",
    "id",
    "content"
  ]){
    const item = {
      ...original
    };
    delete item[key];
    rejected({
      ...envelope(),
      output: [
        item
      ]
    });
  }
});
Deno.test("nonempty tools, annotations and logprobs are unsupported in this tool-free contract", ()=>{
  rejected({
    ...envelope(),
    tools: [
      {
        type: "web_search"
      }
    ]
  });
  const text = responseOutputText(envelope());
  for (const patch of [
    {
      annotations: [
        {
          type: "url_citation",
          url: "https://example.test"
        }
      ]
    },
    {
      annotations: null
    },
    {
      logprobs: [
        {
          token: "x"
        }
      ]
    },
    {
      unknown: true
    }
  ]){
    rejected({
      ...envelope(),
      output: [
        message([
          {
            type: "output_text",
            text,
            annotations: [],
            ...patch
          }
        ])
      ]
    });
  }
});
Deno.test("nonempty error and incomplete details cannot coexist with completed success", ()=>{
  rejected({
    ...envelope(),
    error: {
      message: "sensitive",
      code: "vendor"
    }
  });
  rejected({
    ...envelope(),
    incomplete_details: {
      reason: "max_output_tokens"
    }
  });
});
Deno.test("unsupported or malformed reasoning structures fail closed", ()=>{
  for (const patch of [
    {
      summary: null
    },
    {
      summary: [
        {
          type: "function_call",
          text: "x"
        }
      ]
    },
    {
      content: [
        {
          type: "output_text",
          text: "x"
        }
      ]
    },
    {
      status: "incomplete"
    },
    {
      encrypted_content: {}
    },
    {
      unknown: []
    }
  ]){
    const response = envelope();
    response.output.unshift({
      id: "rs_fixture",
      type: "reasoning",
      summary: [],
      ...patch
    });
    rejected(response);
  }
});
Deno.test("overlong output is bounded by UTF-8 bytes before JSON parsing", ()=>{
  for (const text of [
    " ".repeat(MAX_ROSTER_OUTPUT_BYTES) + "{}",
    "é".repeat(MAX_ROSTER_OUTPUT_BYTES / 2 + 1)
  ])rejected(rawEnvelope(text), "roster_provider_response_too_large");
});
Deno.test("oversized or deeply nested provider metadata is rejected iteratively", ()=>{
  rejected({
    ...envelope(),
    metadata: {
      padding: "x".repeat(MAX_ROSTER_PROVIDER_BYTES)
    }
  }, "roster_provider_response_too_large");
  let nested = {};
  for(let i = 0; i < 18; i++)nested = {
    nested
  };
  rejected({
    ...envelope(),
    metadata: nested
  }, "roster_provider_response_too_large");
  rejected({
    ...envelope(),
    metadata: Array.from({
      length: 20_001
    }, ()=>0)
  }, "roster_provider_response_too_large");
  const cyclic = envelope();
  cyclic.metadata = cyclic;
  rejected(cyclic);
});
Deno.test("malformed, deeply nested, duplicate-key and unknown document fields fail closed", ()=>{
  for (const value of [
    "not JSON",
    "[]",
    "null",
    '{"rows":[]}',
    JSON.stringify({
      rows: [
        candidate()
      ],
      can_submit: true
    }),
    '{"rows":[],"rows":[' + JSON.stringify(candidate()) + "]}",
    '{"rows":[],"r\\u006fws":[' + JSON.stringify(candidate()) + "]}"
  ])rejected(rawEnvelope(value));
  rejected(rawEnvelope('{"rows":' + "[".repeat(20) + "0" + "]".repeat(20) + "}"), "roster_provider_response_too_large");
  const duplicate = JSON.stringify(candidate()).replace('"confidence":0.95', '"confidence":0.1,"confidence":0.95');
  rejected(rawEnvelope('{"rows":[' + duplicate + "]}"));
});
Deno.test("only exact typed row fields are accepted without fallback aliases or coercion", ()=>{
  for (const patch of [
    {
      source_row: "1"
    },
    {
      source_row: 0
    },
    {
      source_row: 1.5
    },
    {
      source_row: Number.MAX_SAFE_INTEGER + 1
    },
    {
      confidence: "0.99"
    },
    {
      confidence: null
    },
    {
      confidence: true
    },
    {
      confidence: -0.1
    },
    {
      confidence: 1.1
    },
    {
      member_name: []
    },
    {
      momo_name: {}
    },
    {
      momo_number: 788123456
    },
    {
      extra: "ignored before"
    }
  ])rejected(envelope([
    {
      ...candidate(),
      ...patch
    }
  ]));
  for (const key of Object.keys(candidate())){
    const row = candidate();
    delete row[key];
    rejected(envelope([
      row
    ]));
  }
  rejected(envelope([
    {
      name: "Alice",
      registered_name: "Alice",
      phone: "0788123456",
      confidence: 1,
      source_row: 1
    }
  ]));
});
Deno.test("all row string limits and invalid control/unicode sequences are enforced before normalization", ()=>{
  for (const patch of [
    {
      member_name: "a".repeat(121)
    },
    {
      momo_name: "a".repeat(121)
    },
    {
      momo_number: "1".repeat(33)
    },
    {
      member_name: "A\nB"
    },
    {
      momo_number: "0788\t123456"
    },
    {
      member_name: "A\ud800B"
    },
    {
      momo_name: "A\udc00B"
    }
  ])rejected(envelope([
    {
      ...candidate(),
      ...patch
    }
  ]));
});
Deno.test("empty unreadable fields, low confidence and duplicate phones stay visible for correction", ()=>{
  const preview = previewOpenAiRoster(envelope([
    candidate(),
    {
      ...candidate(),
      source_row: 2,
      confidence: 0.5
    },
    {
      source_row: 3,
      member_name: "",
      momo_name: "",
      momo_number: "",
      confidence: 0
    }
  ]));
  assertEquals(preview.row_count, 3);
  assertEquals(preview.error_count, 2);
  assertEquals(preview.can_submit, false);
  assertEquals(preview.rows[2].member_name, "");
});
Deno.test("500 candidate boundary is enforced without truncation", ()=>{
  const rows = Array.from({
    length: 500
  }, (_, i)=>({
      ...candidate(),
      source_row: i + 1
    }));
  assertEquals(rosterResponseCandidates(envelope(rows)).length, 500);
  assertEquals(previewOpenAiRoster(envelope(rows)).row_count, 500);
  rejected(envelope([
    ...rows,
    candidate()
  ]));
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX3Jlc3BvbnNlX3BvbGljeV90ZXN0LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7XG4gIGFzc2VydEVxdWFscyxcbiAgYXNzZXJ0VGhyb3dzLFxufSBmcm9tIFwiaHR0cHM6Ly9kZW5vLmxhbmQvc3RkQDAuMjI0LjAvYXNzZXJ0L21vZC50c1wiO1xuaW1wb3J0IHsgUHVibGljRXJyb3IsIHB1YmxpY0ZhaWx1cmUgfSBmcm9tIFwiLi9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5pbXBvcnQgeyBwcmV2aWV3T3BlbkFpUm9zdGVyLCByZXNwb25zZU91dHB1dFRleHQgfSBmcm9tIFwiLi9vcGVuYWlfcm9zdGVyLnRzXCI7XG5pbXBvcnQge1xuICBNQVhfUk9TVEVSX09VVFBVVF9CWVRFUyxcbiAgTUFYX1JPU1RFUl9QUk9WSURFUl9CWVRFUyxcbiAgcm9zdGVyUmVzcG9uc2VDYW5kaWRhdGVzLFxufSBmcm9tIFwiLi9yb3N0ZXJfcmVzcG9uc2VfcG9saWN5LnRzXCI7XG5cbmNvbnN0IGNhbmRpZGF0ZSA9ICgpID0+ICh7XG4gIHNvdXJjZV9yb3c6IDEsXG4gIG1lbWJlcl9uYW1lOiBcIkFsaW5lIFV3YXNlXCIsXG4gIG1vbW9fbmFtZTogXCJBTElORSBVV0FTRVwiLFxuICBtb21vX251bWJlcjogXCIwNzg4MTIzNDU2XCIsXG4gIGNvbmZpZGVuY2U6IDAuOTUsXG59KTtcbmZ1bmN0aW9uIGVudmVsb3BlKHJvd3M6IHVua25vd24gPSBbY2FuZGlkYXRlKCldKTogUmVjb3JkPHN0cmluZywgdW5rbm93bj4ge1xuICByZXR1cm4gcmF3RW52ZWxvcGUoSlNPTi5zdHJpbmdpZnkoeyByb3dzIH0pKTtcbn1cbmZ1bmN0aW9uIG1lc3NhZ2UoY29udGVudDogdW5rbm93bik6IFJlY29yZDxzdHJpbmcsIHVua25vd24+IHtcbiAgcmV0dXJuIHtcbiAgICBpZDogXCJtc2dfZml4dHVyZVwiLFxuICAgIHR5cGU6IFwibWVzc2FnZVwiLFxuICAgIHJvbGU6IFwiYXNzaXN0YW50XCIsXG4gICAgc3RhdHVzOiBcImNvbXBsZXRlZFwiLFxuICAgIGNvbnRlbnQsXG4gIH07XG59XG5mdW5jdGlvbiByYXdFbnZlbG9wZSh0ZXh0OiBzdHJpbmcpOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiB7XG4gIHJldHVybiB7XG4gICAgaWQ6IFwicmVzcF9maXh0dXJlXCIsXG4gICAgb2JqZWN0OiBcInJlc3BvbnNlXCIsXG4gICAgc3RhdHVzOiBcImNvbXBsZXRlZFwiLFxuICAgIGVycm9yOiBudWxsLFxuICAgIGluY29tcGxldGVfZGV0YWlsczogbnVsbCxcbiAgICB0b29sczogW10sXG4gICAgb3V0cHV0OiBbbWVzc2FnZShbeyB0eXBlOiBcIm91dHB1dF90ZXh0XCIsIGFubm90YXRpb25zOiBbXSwgdGV4dCB9XSldLFxuICB9O1xufVxuZnVuY3Rpb24gcmVqZWN0ZWQoXG4gIHZhbHVlOiB1bmtub3duLFxuICBjb2RlID0gXCJyb3N0ZXJfcHJvdmlkZXJfcmVzcG9uc2VfaW52YWxpZFwiLFxuICBzdGF0dXMgPSA1MDIsXG4pOiB2b2lkIHtcbiAgY29uc3QgZXJyb3IgPSBhc3NlcnRUaHJvd3MoKCkgPT4gcHJldmlld09wZW5BaVJvc3Rlcih2YWx1ZSksIFB1YmxpY0Vycm9yKTtcbiAgYXNzZXJ0RXF1YWxzKHB1YmxpY0ZhaWx1cmUoZXJyb3IpLCB7IGVycm9yOiBjb2RlLCBzdGF0dXMgfSk7XG59XG5EZW5vLnRlc3QoXCJzdHJpY3Qgcm9zdGVyIHJlc3BvbnNlIHByZXNlcnZlcyBtdWx0aWxpbmd1YWwgc291cmNlIHN0cmluZ3MgYW5kIHN0YXlzIG5vbi1zdWJtaXR0YWJsZVwiLCAoKSA9PiB7XG4gIGNvbnN0IG5hbWVzID0gW1xuICAgIFwiTml5b256aW1hIMOJbG9kaWVcIixcbiAgICBcItiz2KfYsdipINij2K3ZhdivXCIsXG4gICAgXCLnjovnvo7njrJcIixcbiAgICBcIuCkheCkqOClgOCkpOCkviDgpLbgpLDgpY3gpK7gpL5cIixcbiAgICBcIk7igJlEYWggSmVhbi1QYXVsXCIsXG4gIF07XG4gIGZvciAoY29uc3QgbmFtZSBvZiBuYW1lcykge1xuICAgIGNvbnN0IHJlc3BvbnNlID0gZW52ZWxvcGUoW3tcbiAgICAgIC4uLmNhbmRpZGF0ZSgpLFxuICAgICAgbWVtYmVyX25hbWU6IG5hbWUsXG4gICAgICBtb21vX25hbWU6IG5hbWUsXG4gICAgfV0pO1xuICAgIGNvbnN0IGJlZm9yZSA9IEpTT04uc3RyaW5naWZ5KHJlc3BvbnNlKSxcbiAgICAgIHByZXZpZXcgPSBwcmV2aWV3T3BlbkFpUm9zdGVyKHJlc3BvbnNlKTtcbiAgICBhc3NlcnRFcXVhbHMocHJldmlldy5yZWFkeV9jb3VudCwgMSk7XG4gICAgYXNzZXJ0RXF1YWxzKHByZXZpZXcucm93c1swXS5tZW1iZXJfbmFtZSwgbmFtZSk7XG4gICAgYXNzZXJ0RXF1YWxzKHByZXZpZXcubm9ybWFsaXplZF9yb3dzWzBdLm1lbWJlcl9uYW1lLCBuYW1lKTtcbiAgICBhc3NlcnRFcXVhbHMocHJldmlldy5jYW5fc3VibWl0LCBmYWxzZSk7XG4gICAgYXNzZXJ0RXF1YWxzKEpTT04uc3RyaW5naWZ5KHJlc3BvbnNlKSwgYmVmb3JlKTtcbiAgfVxufSk7XG5EZW5vLnRlc3QoXCJzdHJpY3Qgcm9zdGVyIHJlc3BvbnNlIHN1cHBvcnRzIHN1cHBsZW1lbnRhcnkgVW5pY29kZSBuYW1lcyBhdCB0aGUgc2NoZW1hIGNoYXJhY3RlciBsaW1pdFwiLCAoKSA9PiB7XG4gIGNvbnN0IG5hbWUgPSBcIvCggIBcIi5yZXBlYXQoMTIwKTtcbiAgY29uc3QgcHJldmlldyA9IHByZXZpZXdPcGVuQWlSb3N0ZXIoXG4gICAgZW52ZWxvcGUoW3sgLi4uY2FuZGlkYXRlKCksIG1lbWJlcl9uYW1lOiBuYW1lLCBtb21vX25hbWU6IG5hbWUgfV0pLFxuICApO1xuICBhc3NlcnRFcXVhbHMocHJldmlldy5yZWFkeV9jb3VudCwgMSk7XG4gIGFzc2VydEVxdWFscyhwcmV2aWV3LnJvd3NbMF0ubWVtYmVyX25hbWUsIG5hbWUpO1xuICByZWplY3RlZChlbnZlbG9wZShbeyAuLi5jYW5kaWRhdGUoKSwgbWVtYmVyX25hbWU6IG5hbWUgKyBcIvCggIBcIiB9XSkpO1xufSk7XG5EZW5vLnRlc3QoXCJib3VuZGVkIHJlYXNvbmluZyBtZXRhZGF0YSBpcyBhY2NlcHRlZCBhbmQgbmV2ZXIgcmV0dXJuZWQgYXMgcm9zdGVyIGNvbnRlbnRcIiwgKCkgPT4ge1xuICBjb25zdCByZXNwb25zZSA9IGVudmVsb3BlKCk7XG4gIChyZXNwb25zZS5vdXRwdXQgYXMgdW5rbm93bltdKS51bnNoaWZ0KHtcbiAgICBpZDogXCJyc19maXh0dXJlXCIsXG4gICAgdHlwZTogXCJyZWFzb25pbmdcIixcbiAgICBzdW1tYXJ5OiBbeyB0eXBlOiBcInN1bW1hcnlfdGV4dFwiLCB0ZXh0OiBcIlN5bnRoZXRpYyBzdW1tYXJ5XCIgfV0sXG4gICAgY29udGVudDogW3sgdHlwZTogXCJyZWFzb25pbmdfdGV4dFwiLCB0ZXh0OiBcIlN5bnRoZXRpYyByZWFzb25pbmdcIiB9XSxcbiAgICBlbmNyeXB0ZWRfY29udGVudDogXCJlbmNyeXB0ZWQtZml4dHVyZVwiLFxuICAgIHN0YXR1czogXCJjb21wbGV0ZWRcIixcbiAgfSk7XG4gIGNvbnN0IHByZXZpZXcgPSBwcmV2aWV3T3BlbkFpUm9zdGVyKHJlc3BvbnNlKTtcbiAgYXNzZXJ0RXF1YWxzKHByZXZpZXcucm93X2NvdW50LCAxKTtcbiAgYXNzZXJ0RXF1YWxzKEpTT04uc3RyaW5naWZ5KHByZXZpZXcpLmluY2x1ZGVzKFwiU3ludGhldGljXCIpLCBmYWxzZSk7XG59KTtcbkRlbm8udGVzdChcIm1hdGNoaW5nIFNESyB0ZXh0IGFsaWFzIGNhbm5vdCBieXBhc3MgY2Fub25pY2FsIGVudmVsb3BlIHZhbGlkYXRpb25cIiwgKCkgPT4ge1xuICBjb25zdCByZXNwb25zZSA9IGVudmVsb3BlKCksIGNhbm9uaWNhbCA9IHJlc3BvbnNlT3V0cHV0VGV4dChyZXNwb25zZSk7XG4gIHJlc3BvbnNlLm91dHB1dF90ZXh0ID0gY2Fub25pY2FsO1xuICBhc3NlcnRFcXVhbHMocmVzcG9uc2VPdXRwdXRUZXh0KHJlc3BvbnNlKSwgY2Fub25pY2FsKTtcbiAgcmVzcG9uc2Uub3V0cHV0X3RleHQgPSBKU09OLnN0cmluZ2lmeSh7XG4gICAgcm93czogW3sgLi4uY2FuZGlkYXRlKCksIG1lbWJlcl9uYW1lOiBcIkRpZmZlcmVudFwiIH1dLFxuICB9KTtcbiAgcmVqZWN0ZWQocmVzcG9uc2UpO1xuICByZWplY3RlZCh7IG91dHB1dF90ZXh0OiBjYW5vbmljYWwgfSk7XG59KTtcbmZvciAoXG4gIGNvbnN0IHN0YXR1cyBvZiBbXG4gICAgdW5kZWZpbmVkLFxuICAgIG51bGwsXG4gICAgXCJpbl9wcm9ncmVzc1wiLFxuICAgIFwicXVldWVkXCIsXG4gICAgXCJmYWlsZWRcIixcbiAgICBcImNhbmNlbGxlZFwiLFxuICAgIFwidW5leHBlY3RlZFwiLFxuICBdXG4pIHtcbiAgRGVuby50ZXN0KGByZWplY3Qgbm9uLWNvbXBsZXRlZCByZXNwb25zZSBzdGF0dXMgJHtTdHJpbmcoc3RhdHVzKX1gLCAoKSA9PiB7XG4gICAgY29uc3QgdmFsdWUgPSBlbnZlbG9wZSgpO1xuICAgIGlmIChzdGF0dXMgPT09IHVuZGVmaW5lZCkgZGVsZXRlIHZhbHVlLnN0YXR1cztcbiAgICBlbHNlIHZhbHVlLnN0YXR1cyA9IHN0YXR1cztcbiAgICByZWplY3RlZCh2YWx1ZSk7XG4gIH0pO1xufVxuRGVuby50ZXN0KFwiaW5jb21wbGV0ZSBhbmQgcmVmdXNhbCByZXNwb25zZSBjb2RlcyBjb250YWluIG5vIHByb3ZpZGVyIGNvbnRlbnRcIiwgKCkgPT4ge1xuICByZWplY3RlZChcbiAgICB7IC4uLmVudmVsb3BlKCksIHN0YXR1czogXCJpbmNvbXBsZXRlXCIgfSxcbiAgICBcInJvc3Rlcl9leHRyYWN0aW9uX2luY29tcGxldGVcIixcbiAgKTtcbiAgcmVqZWN0ZWQoXG4gICAge1xuICAgICAgLi4uZW52ZWxvcGUoKSxcbiAgICAgIG91dHB1dDogW1xuICAgICAgICBtZXNzYWdlKFt7IHR5cGU6IFwicmVmdXNhbFwiLCByZWZ1c2FsOiBcInNlbnNpdGl2ZSBwcm92aWRlciBkZXRhaWxcIiB9XSksXG4gICAgICBdLFxuICAgIH0sXG4gICAgXCJyb3N0ZXJfZXh0cmFjdGlvbl9yZWZ1c2VkXCIsXG4gICAgNDIyLFxuICApO1xufSk7XG5EZW5vLnRlc3QoXCJleHRyYSBtZXNzYWdlLCB0ZXh0LCByZWZ1c2FsIGFuZCB0b29sIGl0ZW1zIGFsbCBmYWlsIGNsb3NlZFwiLCAoKSA9PiB7XG4gIGNvbnN0IHZhbGlkID0gZW52ZWxvcGUoKS5vdXRwdXQgYXMgdW5rbm93bltdO1xuICBmb3IgKFxuICAgIGNvbnN0IGV4dHJhIG9mIFtcbiAgICAgIHZhbGlkWzBdLFxuICAgICAgeyB0eXBlOiBcImZ1bmN0aW9uX2NhbGxcIiwgbmFtZTogXCJjcmVhdGVfbWVtYmVyXCIsIGFyZ3VtZW50czogXCJ7fVwiIH0sXG4gICAgICB7IHR5cGU6IFwid2ViX3NlYXJjaF9jYWxsXCIgfSxcbiAgICAgIHsgdHlwZTogXCJyZWZ1c2FsXCIsIHJlZnVzYWw6IFwicHJpdmF0ZVwiIH0sXG4gICAgICBudWxsLFxuICAgICAgNDIsXG4gICAgXVxuICApIHJlamVjdGVkKHsgLi4uZW52ZWxvcGUoKSwgb3V0cHV0OiBbLi4udmFsaWQsIGV4dHJhXSB9KTtcbiAgY29uc3QgdGV4dCA9ICh2YWxpZFswXSBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPikuY29udGVudCBhcyB1bmtub3duW107XG4gIGZvciAoXG4gICAgY29uc3QgZXh0cmEgb2YgW3RleHRbMF0sIHsgdHlwZTogXCJyZWZ1c2FsXCIsIHJlZnVzYWw6IFwicHJpdmF0ZVwiIH0sIHtcbiAgICAgIHR5cGU6IFwib3V0cHV0X2F1ZGlvXCIsXG4gICAgICBhdWRpbzogXCJkYXRhXCIsXG4gICAgfV1cbiAgKSByZWplY3RlZCh7IC4uLmVudmVsb3BlKCksIG91dHB1dDogW21lc3NhZ2UoWy4uLnRleHQsIGV4dHJhXSldIH0pO1xufSk7XG5EZW5vLnRlc3QoXCJtZXNzYWdlIHN0YXR1cywgcm9sZSwgcGhhc2UgYW5kIHNoYXBlIG11c3QgYmUgZXhwbGljaXQgc3VwcG9ydGVkIG91dHB1dFwiLCAoKSA9PiB7XG4gIGNvbnN0IG9yaWdpbmFsID0gKGVudmVsb3BlKCkub3V0cHV0IGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+W10pWzBdO1xuICBmb3IgKFxuICAgIGNvbnN0IHBhdGNoIG9mIFtcbiAgICAgIHsgc3RhdHVzOiBcImluX3Byb2dyZXNzXCIgfSxcbiAgICAgIHsgcm9sZTogXCJ1c2VyXCIgfSxcbiAgICAgIHsgcGhhc2U6IFwiY29tbWVudGFyeVwiIH0sXG4gICAgICB7IHR5cGU6IFwiZnVuY3Rpb25fY2FsbFwiIH0sXG4gICAgICB7IGNvbnRlbnQ6IFtdIH0sXG4gICAgICB7IGV4dHJhOiBcInBheWxvYWRcIiB9LFxuICAgICAgeyBpZDogMyB9LFxuICAgIF1cbiAgKSByZWplY3RlZCh7IC4uLmVudmVsb3BlKCksIG91dHB1dDogW3sgLi4ub3JpZ2luYWwsIC4uLnBhdGNoIH1dIH0pO1xuICBmb3IgKGNvbnN0IGtleSBvZiBbXCJzdGF0dXNcIiwgXCJyb2xlXCIsIFwidHlwZVwiLCBcImlkXCIsIFwiY29udGVudFwiXSkge1xuICAgIGNvbnN0IGl0ZW0gPSB7IC4uLm9yaWdpbmFsIH07XG4gICAgZGVsZXRlIGl0ZW1ba2V5XTtcbiAgICByZWplY3RlZCh7IC4uLmVudmVsb3BlKCksIG91dHB1dDogW2l0ZW1dIH0pO1xuICB9XG59KTtcbkRlbm8udGVzdChcIm5vbmVtcHR5IHRvb2xzLCBhbm5vdGF0aW9ucyBhbmQgbG9ncHJvYnMgYXJlIHVuc3VwcG9ydGVkIGluIHRoaXMgdG9vbC1mcmVlIGNvbnRyYWN0XCIsICgpID0+IHtcbiAgcmVqZWN0ZWQoeyAuLi5lbnZlbG9wZSgpLCB0b29sczogW3sgdHlwZTogXCJ3ZWJfc2VhcmNoXCIgfV0gfSk7XG4gIGNvbnN0IHRleHQgPSByZXNwb25zZU91dHB1dFRleHQoZW52ZWxvcGUoKSk7XG4gIGZvciAoXG4gICAgY29uc3QgcGF0Y2ggb2YgW1xuICAgICAgeyBhbm5vdGF0aW9uczogW3sgdHlwZTogXCJ1cmxfY2l0YXRpb25cIiwgdXJsOiBcImh0dHBzOi8vZXhhbXBsZS50ZXN0XCIgfV0gfSxcbiAgICAgIHsgYW5ub3RhdGlvbnM6IG51bGwgfSxcbiAgICAgIHsgbG9ncHJvYnM6IFt7IHRva2VuOiBcInhcIiB9XSB9LFxuICAgICAgeyB1bmtub3duOiB0cnVlIH0sXG4gICAgXVxuICApIHtcbiAgICByZWplY3RlZCh7XG4gICAgICAuLi5lbnZlbG9wZSgpLFxuICAgICAgb3V0cHV0OiBbXG4gICAgICAgIG1lc3NhZ2UoW3sgdHlwZTogXCJvdXRwdXRfdGV4dFwiLCB0ZXh0LCBhbm5vdGF0aW9uczogW10sIC4uLnBhdGNoIH1dKSxcbiAgICAgIF0sXG4gICAgfSk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwibm9uZW1wdHkgZXJyb3IgYW5kIGluY29tcGxldGUgZGV0YWlscyBjYW5ub3QgY29leGlzdCB3aXRoIGNvbXBsZXRlZCBzdWNjZXNzXCIsICgpID0+IHtcbiAgcmVqZWN0ZWQoeyAuLi5lbnZlbG9wZSgpLCBlcnJvcjogeyBtZXNzYWdlOiBcInNlbnNpdGl2ZVwiLCBjb2RlOiBcInZlbmRvclwiIH0gfSk7XG4gIHJlamVjdGVkKHtcbiAgICAuLi5lbnZlbG9wZSgpLFxuICAgIGluY29tcGxldGVfZGV0YWlsczogeyByZWFzb246IFwibWF4X291dHB1dF90b2tlbnNcIiB9LFxuICB9KTtcbn0pO1xuRGVuby50ZXN0KFwidW5zdXBwb3J0ZWQgb3IgbWFsZm9ybWVkIHJlYXNvbmluZyBzdHJ1Y3R1cmVzIGZhaWwgY2xvc2VkXCIsICgpID0+IHtcbiAgZm9yIChcbiAgICBjb25zdCBwYXRjaCBvZiBbXG4gICAgICB7IHN1bW1hcnk6IG51bGwgfSxcbiAgICAgIHsgc3VtbWFyeTogW3sgdHlwZTogXCJmdW5jdGlvbl9jYWxsXCIsIHRleHQ6IFwieFwiIH1dIH0sXG4gICAgICB7IGNvbnRlbnQ6IFt7IHR5cGU6IFwib3V0cHV0X3RleHRcIiwgdGV4dDogXCJ4XCIgfV0gfSxcbiAgICAgIHsgc3RhdHVzOiBcImluY29tcGxldGVcIiB9LFxuICAgICAgeyBlbmNyeXB0ZWRfY29udGVudDoge30gfSxcbiAgICAgIHsgdW5rbm93bjogW10gfSxcbiAgICBdXG4gICkge1xuICAgIGNvbnN0IHJlc3BvbnNlID0gZW52ZWxvcGUoKTtcbiAgICAocmVzcG9uc2Uub3V0cHV0IGFzIHVua25vd25bXSkudW5zaGlmdCh7XG4gICAgICBpZDogXCJyc19maXh0dXJlXCIsXG4gICAgICB0eXBlOiBcInJlYXNvbmluZ1wiLFxuICAgICAgc3VtbWFyeTogW10sXG4gICAgICAuLi5wYXRjaCxcbiAgICB9KTtcbiAgICByZWplY3RlZChyZXNwb25zZSk7XG4gIH1cbn0pO1xuRGVuby50ZXN0KFwib3Zlcmxvbmcgb3V0cHV0IGlzIGJvdW5kZWQgYnkgVVRGLTggYnl0ZXMgYmVmb3JlIEpTT04gcGFyc2luZ1wiLCAoKSA9PiB7XG4gIGZvciAoXG4gICAgY29uc3QgdGV4dCBvZiBbXG4gICAgICBcIiBcIi5yZXBlYXQoTUFYX1JPU1RFUl9PVVRQVVRfQllURVMpICsgXCJ7fVwiLFxuICAgICAgXCLDqVwiLnJlcGVhdChNQVhfUk9TVEVSX09VVFBVVF9CWVRFUyAvIDIgKyAxKSxcbiAgICBdXG4gICkgcmVqZWN0ZWQocmF3RW52ZWxvcGUodGV4dCksIFwicm9zdGVyX3Byb3ZpZGVyX3Jlc3BvbnNlX3Rvb19sYXJnZVwiKTtcbn0pO1xuRGVuby50ZXN0KFwib3ZlcnNpemVkIG9yIGRlZXBseSBuZXN0ZWQgcHJvdmlkZXIgbWV0YWRhdGEgaXMgcmVqZWN0ZWQgaXRlcmF0aXZlbHlcIiwgKCkgPT4ge1xuICByZWplY3RlZCh7XG4gICAgLi4uZW52ZWxvcGUoKSxcbiAgICBtZXRhZGF0YTogeyBwYWRkaW5nOiBcInhcIi5yZXBlYXQoTUFYX1JPU1RFUl9QUk9WSURFUl9CWVRFUykgfSxcbiAgfSwgXCJyb3N0ZXJfcHJvdmlkZXJfcmVzcG9uc2VfdG9vX2xhcmdlXCIpO1xuICBsZXQgbmVzdGVkOiB1bmtub3duID0ge307XG4gIGZvciAobGV0IGkgPSAwOyBpIDwgMTg7IGkrKykgbmVzdGVkID0geyBuZXN0ZWQgfTtcbiAgcmVqZWN0ZWQoXG4gICAgeyAuLi5lbnZlbG9wZSgpLCBtZXRhZGF0YTogbmVzdGVkIH0sXG4gICAgXCJyb3N0ZXJfcHJvdmlkZXJfcmVzcG9uc2VfdG9vX2xhcmdlXCIsXG4gICk7XG4gIHJlamVjdGVkKFxuICAgIHsgLi4uZW52ZWxvcGUoKSwgbWV0YWRhdGE6IEFycmF5LmZyb20oeyBsZW5ndGg6IDIwXzAwMSB9LCAoKSA9PiAwKSB9LFxuICAgIFwicm9zdGVyX3Byb3ZpZGVyX3Jlc3BvbnNlX3Rvb19sYXJnZVwiLFxuICApO1xuICBjb25zdCBjeWNsaWMgPSBlbnZlbG9wZSgpO1xuICBjeWNsaWMubWV0YWRhdGEgPSBjeWNsaWM7XG4gIHJlamVjdGVkKGN5Y2xpYyk7XG59KTtcbkRlbm8udGVzdChcIm1hbGZvcm1lZCwgZGVlcGx5IG5lc3RlZCwgZHVwbGljYXRlLWtleSBhbmQgdW5rbm93biBkb2N1bWVudCBmaWVsZHMgZmFpbCBjbG9zZWRcIiwgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IHZhbHVlIG9mIFtcbiAgICAgIFwibm90IEpTT05cIixcbiAgICAgIFwiW11cIixcbiAgICAgIFwibnVsbFwiLFxuICAgICAgJ3tcInJvd3NcIjpbXX0nLFxuICAgICAgSlNPTi5zdHJpbmdpZnkoeyByb3dzOiBbY2FuZGlkYXRlKCldLCBjYW5fc3VibWl0OiB0cnVlIH0pLFxuICAgICAgJ3tcInJvd3NcIjpbXSxcInJvd3NcIjpbJyArIEpTT04uc3RyaW5naWZ5KGNhbmRpZGF0ZSgpKSArIFwiXX1cIixcbiAgICAgICd7XCJyb3dzXCI6W10sXCJyXFxcXHUwMDZmd3NcIjpbJyArIEpTT04uc3RyaW5naWZ5KGNhbmRpZGF0ZSgpKSArIFwiXX1cIixcbiAgICBdXG4gICkgcmVqZWN0ZWQocmF3RW52ZWxvcGUodmFsdWUpKTtcbiAgcmVqZWN0ZWQoXG4gICAgcmF3RW52ZWxvcGUoJ3tcInJvd3NcIjonICsgXCJbXCIucmVwZWF0KDIwKSArIFwiMFwiICsgXCJdXCIucmVwZWF0KDIwKSArIFwifVwiKSxcbiAgICBcInJvc3Rlcl9wcm92aWRlcl9yZXNwb25zZV90b29fbGFyZ2VcIixcbiAgKTtcbiAgY29uc3QgZHVwbGljYXRlID0gSlNPTi5zdHJpbmdpZnkoY2FuZGlkYXRlKCkpLnJlcGxhY2UoXG4gICAgJ1wiY29uZmlkZW5jZVwiOjAuOTUnLFxuICAgICdcImNvbmZpZGVuY2VcIjowLjEsXCJjb25maWRlbmNlXCI6MC45NScsXG4gICk7XG4gIHJlamVjdGVkKHJhd0VudmVsb3BlKCd7XCJyb3dzXCI6WycgKyBkdXBsaWNhdGUgKyBcIl19XCIpKTtcbn0pO1xuRGVuby50ZXN0KFwib25seSBleGFjdCB0eXBlZCByb3cgZmllbGRzIGFyZSBhY2NlcHRlZCB3aXRob3V0IGZhbGxiYWNrIGFsaWFzZXMgb3IgY29lcmNpb25cIiwgKCkgPT4ge1xuICBmb3IgKFxuICAgIGNvbnN0IHBhdGNoIG9mIFtcbiAgICAgIHsgc291cmNlX3JvdzogXCIxXCIgfSxcbiAgICAgIHsgc291cmNlX3JvdzogMCB9LFxuICAgICAgeyBzb3VyY2Vfcm93OiAxLjUgfSxcbiAgICAgIHsgc291cmNlX3JvdzogTnVtYmVyLk1BWF9TQUZFX0lOVEVHRVIgKyAxIH0sXG4gICAgICB7IGNvbmZpZGVuY2U6IFwiMC45OVwiIH0sXG4gICAgICB7IGNvbmZpZGVuY2U6IG51bGwgfSxcbiAgICAgIHsgY29uZmlkZW5jZTogdHJ1ZSB9LFxuICAgICAgeyBjb25maWRlbmNlOiAtMC4xIH0sXG4gICAgICB7IGNvbmZpZGVuY2U6IDEuMSB9LFxuICAgICAgeyBtZW1iZXJfbmFtZTogW10gfSxcbiAgICAgIHsgbW9tb19uYW1lOiB7fSB9LFxuICAgICAgeyBtb21vX251bWJlcjogNzg4MTIzNDU2IH0sXG4gICAgICB7IGV4dHJhOiBcImlnbm9yZWQgYmVmb3JlXCIgfSxcbiAgICBdXG4gICkgcmVqZWN0ZWQoZW52ZWxvcGUoW3sgLi4uY2FuZGlkYXRlKCksIC4uLnBhdGNoIH1dKSk7XG4gIGZvciAoY29uc3Qga2V5IG9mIE9iamVjdC5rZXlzKGNhbmRpZGF0ZSgpKSkge1xuICAgIGNvbnN0IHJvdzogUmVjb3JkPHN0cmluZywgdW5rbm93bj4gPSBjYW5kaWRhdGUoKTtcbiAgICBkZWxldGUgcm93W2tleV07XG4gICAgcmVqZWN0ZWQoZW52ZWxvcGUoW3Jvd10pKTtcbiAgfVxuICByZWplY3RlZChcbiAgICBlbnZlbG9wZShbe1xuICAgICAgbmFtZTogXCJBbGljZVwiLFxuICAgICAgcmVnaXN0ZXJlZF9uYW1lOiBcIkFsaWNlXCIsXG4gICAgICBwaG9uZTogXCIwNzg4MTIzNDU2XCIsXG4gICAgICBjb25maWRlbmNlOiAxLFxuICAgICAgc291cmNlX3JvdzogMSxcbiAgICB9XSksXG4gICk7XG59KTtcbkRlbm8udGVzdChcImFsbCByb3cgc3RyaW5nIGxpbWl0cyBhbmQgaW52YWxpZCBjb250cm9sL3VuaWNvZGUgc2VxdWVuY2VzIGFyZSBlbmZvcmNlZCBiZWZvcmUgbm9ybWFsaXphdGlvblwiLCAoKSA9PiB7XG4gIGZvciAoXG4gICAgY29uc3QgcGF0Y2ggb2YgW1xuICAgICAgeyBtZW1iZXJfbmFtZTogXCJhXCIucmVwZWF0KDEyMSkgfSxcbiAgICAgIHsgbW9tb19uYW1lOiBcImFcIi5yZXBlYXQoMTIxKSB9LFxuICAgICAgeyBtb21vX251bWJlcjogXCIxXCIucmVwZWF0KDMzKSB9LFxuICAgICAgeyBtZW1iZXJfbmFtZTogXCJBXFxuQlwiIH0sXG4gICAgICB7IG1vbW9fbnVtYmVyOiBcIjA3ODhcXHQxMjM0NTZcIiB9LFxuICAgICAgeyBtZW1iZXJfbmFtZTogXCJBXFx1ZDgwMEJcIiB9LFxuICAgICAgeyBtb21vX25hbWU6IFwiQVxcdWRjMDBCXCIgfSxcbiAgICBdXG4gICkgcmVqZWN0ZWQoZW52ZWxvcGUoW3sgLi4uY2FuZGlkYXRlKCksIC4uLnBhdGNoIH1dKSk7XG59KTtcbkRlbm8udGVzdChcImVtcHR5IHVucmVhZGFibGUgZmllbGRzLCBsb3cgY29uZmlkZW5jZSBhbmQgZHVwbGljYXRlIHBob25lcyBzdGF5IHZpc2libGUgZm9yIGNvcnJlY3Rpb25cIiwgKCkgPT4ge1xuICBjb25zdCBwcmV2aWV3ID0gcHJldmlld09wZW5BaVJvc3RlcihcbiAgICBlbnZlbG9wZShbY2FuZGlkYXRlKCksIHsgLi4uY2FuZGlkYXRlKCksIHNvdXJjZV9yb3c6IDIsIGNvbmZpZGVuY2U6IDAuNSB9LCB7XG4gICAgICBzb3VyY2Vfcm93OiAzLFxuICAgICAgbWVtYmVyX25hbWU6IFwiXCIsXG4gICAgICBtb21vX25hbWU6IFwiXCIsXG4gICAgICBtb21vX251bWJlcjogXCJcIixcbiAgICAgIGNvbmZpZGVuY2U6IDAsXG4gICAgfV0pLFxuICApO1xuICBhc3NlcnRFcXVhbHMocHJldmlldy5yb3dfY291bnQsIDMpO1xuICBhc3NlcnRFcXVhbHMocHJldmlldy5lcnJvcl9jb3VudCwgMik7XG4gIGFzc2VydEVxdWFscyhwcmV2aWV3LmNhbl9zdWJtaXQsIGZhbHNlKTtcbiAgYXNzZXJ0RXF1YWxzKHByZXZpZXcucm93c1syXS5tZW1iZXJfbmFtZSwgXCJcIik7XG59KTtcbkRlbm8udGVzdChcIjUwMCBjYW5kaWRhdGUgYm91bmRhcnkgaXMgZW5mb3JjZWQgd2l0aG91dCB0cnVuY2F0aW9uXCIsICgpID0+IHtcbiAgY29uc3Qgcm93cyA9IEFycmF5LmZyb20oXG4gICAgeyBsZW5ndGg6IDUwMCB9LFxuICAgIChfLCBpKSA9PiAoeyAuLi5jYW5kaWRhdGUoKSwgc291cmNlX3JvdzogaSArIDEgfSksXG4gICk7XG4gIGFzc2VydEVxdWFscyhyb3N0ZXJSZXNwb25zZUNhbmRpZGF0ZXMoZW52ZWxvcGUocm93cykpLmxlbmd0aCwgNTAwKTtcbiAgYXNzZXJ0RXF1YWxzKHByZXZpZXdPcGVuQWlSb3N0ZXIoZW52ZWxvcGUocm93cykpLnJvd19jb3VudCwgNTAwKTtcbiAgcmVqZWN0ZWQoZW52ZWxvcGUoWy4uLnJvd3MsIGNhbmRpZGF0ZSgpXSkpO1xufSk7XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FDRSxZQUFZLEVBQ1osWUFBWSxRQUNQLDhDQUE4QztBQUNyRCxTQUFTLFdBQVcsRUFBRSxhQUFhLFFBQVEsMkJBQTJCO0FBQ3RFLFNBQVMsbUJBQW1CLEVBQUUsa0JBQWtCLFFBQVEscUJBQXFCO0FBQzdFLFNBQ0UsdUJBQXVCLEVBQ3ZCLHlCQUF5QixFQUN6Qix3QkFBd0IsUUFDbkIsOEJBQThCO0FBRXJDLE1BQU0sWUFBWSxJQUFNLENBQUM7SUFDdkIsWUFBWTtJQUNaLGFBQWE7SUFDYixXQUFXO0lBQ1gsYUFBYTtJQUNiLFlBQVk7RUFDZCxDQUFDO0FBQ0QsU0FBUyxTQUFTLE9BQWdCO0VBQUM7Q0FBWTtFQUM3QyxPQUFPLFlBQVksS0FBSyxTQUFTLENBQUM7SUFBRTtFQUFLO0FBQzNDO0FBQ0EsU0FBUyxRQUFRLE9BQWdCO0VBQy9CLE9BQU87SUFDTCxJQUFJO0lBQ0osTUFBTTtJQUNOLE1BQU07SUFDTixRQUFRO0lBQ1I7RUFDRjtBQUNGO0FBQ0EsU0FBUyxZQUFZLElBQVk7RUFDL0IsT0FBTztJQUNMLElBQUk7SUFDSixRQUFRO0lBQ1IsUUFBUTtJQUNSLE9BQU87SUFDUCxvQkFBb0I7SUFDcEIsT0FBTyxFQUFFO0lBQ1QsUUFBUTtNQUFDLFFBQVE7UUFBQztVQUFFLE1BQU07VUFBZSxhQUFhLEVBQUU7VUFBRTtRQUFLO09BQUU7S0FBRTtFQUNyRTtBQUNGO0FBQ0EsU0FBUyxTQUNQLEtBQWMsRUFD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
// denoCacheMetadata=17081733947239091216,10273442746100767052