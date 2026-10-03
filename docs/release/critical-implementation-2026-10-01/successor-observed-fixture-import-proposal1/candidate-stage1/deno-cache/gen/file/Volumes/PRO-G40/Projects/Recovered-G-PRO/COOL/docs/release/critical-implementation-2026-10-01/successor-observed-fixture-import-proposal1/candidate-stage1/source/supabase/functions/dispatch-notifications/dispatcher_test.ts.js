import { assertEquals } from "../_shared/test_assert.ts";
import { dispatchBudgetMs, dispatchNotifications, minimumDispatchRemainingMs } from "./dispatcher.ts";
function delivery(attempt = 1) {
  return {
    delivery_id: "delivery-1",
    event_id: "event-1",
    device_id: "device-1",
    user_id: "99870000-0000-4000-8000-000000000001",
    token: "private-token",
    provider: "fcm",
    environment: "production",
    title: "Notification",
    body: "Private body",
    deep_link: null,
    event_type: "group_update",
    attempt_number: attempt,
    claim_token: "claim-1"
  };
}
const accepted = {
  ok: true,
  retryable: false,
  messageId: "provider-1",
  errorCode: null,
  latencyMs: 10
};
Deno.test("dispatch claims only after the previous delivery is completed", async ()=>{
  const operations = [];
  const result = await dispatchNotifications(2, {
    claim: ()=>{
      operations.push("claim");
      return Promise.resolve(delivery());
    },
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>{
      operations.push("send");
      return Promise.resolve(accepted);
    },
    complete: ()=>{
      operations.push("complete");
      return Promise.resolve();
    }
  });
  assertEquals(operations, [
    "claim",
    "send",
    "complete",
    "claim",
    "send",
    "complete"
  ]);
  assertEquals(result.sent, 2);
  assertEquals(result.completion_pending, 0);
});
Deno.test("accepted push with a lost completion response is never marked for retry", async ()=>{
  const completions = [];
  let claims = 0;
  const result = await dispatchNotifications(500, {
    claim: ()=>{
      claims += 1;
      return Promise.resolve(delivery());
    },
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>Promise.resolve(accepted),
    complete: (_delivery, outcome)=>{
      completions.push(outcome);
      throw new Error("Database response lost after commit");
    }
  });
  assertEquals(claims, 1);
  assertEquals(completions, [
    accepted
  ]);
  assertEquals(result.completion_pending, 1);
  assertEquals(result.sent, 0);
  assertEquals(result.retrying, 0);
});
Deno.test("transport failure uses the lease attempt and exhausts the fifth attempt", async ()=>{
  const lease = delivery(5);
  const completions = [];
  const result = await dispatchNotifications(1, {
    claim: ()=>Promise.resolve(lease),
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>{
      throw new Error("private provider body and token");
    },
    complete: (claimed, outcome)=>{
      completions.push({
        lease: claimed,
        result: outcome
      });
      return Promise.resolve();
    }
  });
  assertEquals(completions[0].lease, lease);
  assertEquals(completions[0].result.errorCode, "transport_exception");
  assertEquals(result.failed, 1);
  assertEquals(result.retrying, 0);
});
Deno.test("retryable provider failure below exhaustion is reported as queued", async ()=>{
  const result = await dispatchNotifications(1, {
    claim: ()=>Promise.resolve(delivery(4)),
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>Promise.resolve({
        ...accepted,
        ok: false,
        retryable: true,
        errorCode: "http_503"
      }),
    complete: ()=>Promise.resolve()
  });
  assertEquals(result.retrying, 1);
  assertEquals(result.failed, 0);
});
Deno.test("invalid provider token is terminal without an in-process retry", async ()=>{
  let sends = 0;
  const result = await dispatchNotifications(1, {
    claim: ()=>Promise.resolve(delivery()),
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>{
      sends += 1;
      return Promise.resolve({
        ...accepted,
        ok: false,
        errorCode: "UNREGISTERED"
      });
    },
    complete: ()=>Promise.resolve()
  });
  assertEquals(sends, 1);
  assertEquals(result.failed, 1);
});
Deno.test("dispatch stops claiming with a full send budget still reserved", async ()=>{
  let clock = 0;
  let claims = 0;
  const result = await dispatchNotifications(500, {
    now: ()=>clock,
    claim: ()=>{
      claims += 1;
      return Promise.resolve(delivery());
    },
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>{
      clock += dispatchBudgetMs - minimumDispatchRemainingMs + 1;
      return Promise.resolve(accepted);
    },
    complete: ()=>Promise.resolve()
  });
  assertEquals(claims, 1);
  assertEquals(result.sent, 1);
  assertEquals(result.budget_exhausted, true);
});
Deno.test("an empty queue ends without provider or completion calls", async ()=>{
  const result = await dispatchNotifications(500, {
    claim: ()=>Promise.resolve(null),
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>{
      throw new Error("must not send");
    },
    complete: ()=>{
      throw new Error("must not complete");
    }
  });
  assertEquals(result.claimed, 0);
  assertEquals(result.completion_pending, 0);
  assertEquals(result.budget_exhausted, false);
});
Deno.test("claim failure cannot cause a provider call", async ()=>{
  let rejected = false;
  let sends = 0;
  try {
    await dispatchNotifications(1, {
      claim: ()=>{
        throw new Error("RPC unavailable");
      },
      isCurrent: ()=>Promise.resolve(true),
      send: ()=>{
        sends += 1;
        return Promise.resolve(accepted);
      },
      complete: ()=>Promise.resolve()
    });
  } catch  {
    rejected = true;
  }
  assertEquals(rejected, true);
  assertEquals(sends, 0);
});
Deno.test("lost lease preflight cannot send or complete the replacement claim", async ()=>{
  let sends = 0;
  let completions = 0;
  const result = await dispatchNotifications(1, {
    claim: ()=>Promise.resolve(delivery()),
    isCurrent: ()=>Promise.resolve(false),
    send: ()=>{
      sends += 1;
      return Promise.resolve(accepted);
    },
    complete: ()=>{
      completions += 1;
      return Promise.resolve();
    }
  });
  assertEquals(result.lease_lost, 1);
  assertEquals(sends, 0);
  assertEquals(completions, 0);
});
Deno.test("legacy claim without a fence fails before preflight and provider calls", async ()=>{
  let preflights = 0;
  let sends = 0;
  const legacy = {
    ...delivery(),
    claim_token: undefined
  };
  const result = await dispatchNotifications(1, {
    claim: ()=>Promise.resolve(legacy),
    isCurrent: ()=>{
      preflights += 1;
      return Promise.resolve(true);
    },
    send: ()=>{
      sends += 1;
      return Promise.resolve(accepted);
    },
    complete: ()=>Promise.resolve()
  });
  assertEquals(result.lease_lost, 1);
  assertEquals(preflights, 0);
  assertEquals(sends, 0);
});
Deno.test("claim without recipient binding cannot reach a provider", async ()=>{
  let sends = 0;
  const result = await dispatchNotifications(1, {
    claim: ()=>Promise.resolve({
        ...delivery(),
        user_id: ""
      }),
    isCurrent: ()=>Promise.resolve(true),
    send: ()=>{
      sends++;
      return Promise.resolve(accepted);
    },
    complete: ()=>Promise.resolve()
  });
  assertEquals(result.lease_lost, 1);
  assertEquals(sends, 0);
});
Deno.test("provider floor is propagated and excessive wait terminalizes without early retry", async ()=>{
  for (const seconds of [
    900,
    3601
  ]){
    let captured;
    const result = await dispatchNotifications(1, {
      claim: ()=>Promise.resolve(delivery()),
      isCurrent: ()=>Promise.resolve(true),
      send: ()=>Promise.resolve({
          ...accepted,
          ok: false,
          retryable: true,
          retryAfterSeconds: seconds
        }),
      complete: (_claim, outcome)=>{
        captured = outcome;
        return Promise.resolve();
      }
    });
    assertEquals(captured?.retryAfterSeconds, seconds);
    assertEquals(captured?.retryable, seconds <= 3600);
    assertEquals(result.retrying, seconds <= 3600 ? 1 : 0);
    assertEquals(result.failed, seconds > 3600 ? 1 : 0);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2Rpc3BhdGNoLW5vdGlmaWNhdGlvbnMvZGlzcGF0Y2hlcl90ZXN0LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7IGFzc2VydEVxdWFscyB9IGZyb20gXCIuLi9fc2hhcmVkL3Rlc3RfYXNzZXJ0LnRzXCI7XG5pbXBvcnQge1xuICB0eXBlIENsYWltZWREZWxpdmVyeSxcbiAgdHlwZSBEZWxpdmVyeVJlc3VsdCxcbiAgZGlzcGF0Y2hCdWRnZXRNcyxcbiAgZGlzcGF0Y2hOb3RpZmljYXRpb25zLFxuICBtaW5pbXVtRGlzcGF0Y2hSZW1haW5pbmdNcyxcbn0gZnJvbSBcIi4vZGlzcGF0Y2hlci50c1wiO1xuXG5mdW5jdGlvbiBkZWxpdmVyeShhdHRlbXB0ID0gMSk6IENsYWltZWREZWxpdmVyeSB7XG4gIHJldHVybiB7XG4gICAgZGVsaXZlcnlfaWQ6IFwiZGVsaXZlcnktMVwiLFxuICAgIGV2ZW50X2lkOiBcImV2ZW50LTFcIixcbiAgICBkZXZpY2VfaWQ6IFwiZGV2aWNlLTFcIixcbiAgICB1c2VyX2lkOiBcIjk5ODcwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMVwiLFxuICAgIHRva2VuOiBcInByaXZhdGUtdG9rZW5cIixcbiAgICBwcm92aWRlcjogXCJmY21cIixcbiAgICBlbnZpcm9ubWVudDogXCJwcm9kdWN0aW9uXCIsXG4gICAgdGl0bGU6IFwiTm90aWZpY2F0aW9uXCIsXG4gICAgYm9keTogXCJQcml2YXRlIGJvZHlcIixcbiAgICBkZWVwX2xpbms6IG51bGwsXG4gICAgZXZlbnRfdHlwZTogXCJncm91cF91cGRhdGVcIixcbiAgICBhdHRlbXB0X251bWJlcjogYXR0ZW1wdCxcbiAgICBjbGFpbV90b2tlbjogXCJjbGFpbS0xXCIsXG4gIH07XG59XG5cbmNvbnN0IGFjY2VwdGVkOiBEZWxpdmVyeVJlc3VsdCA9IHtcbiAgb2s6IHRydWUsXG4gIHJldHJ5YWJsZTogZmFsc2UsXG4gIG1lc3NhZ2VJZDogXCJwcm92aWRlci0xXCIsXG4gIGVycm9yQ29kZTogbnVsbCxcbiAgbGF0ZW5jeU1zOiAxMCxcbn07XG5cbkRlbm8udGVzdChcImRpc3BhdGNoIGNsYWltcyBvbmx5IGFmdGVyIHRoZSBwcmV2aW91cyBkZWxpdmVyeSBpcyBjb21wbGV0ZWRcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBvcGVyYXRpb25zOiBzdHJpbmdbXSA9IFtdO1xuICBjb25zdCByZXN1bHQgPSBhd2FpdCBkaXNwYXRjaE5vdGlmaWNhdGlvbnMoMiwge1xuICAgIGNsYWltOiAoKSA9PiB7XG4gICAgICBvcGVyYXRpb25zLnB1c2goXCJjbGFpbVwiKTtcbiAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoZGVsaXZlcnkoKSk7XG4gICAgfSxcbiAgICBpc0N1cnJlbnQ6ICgpID0+IFByb21pc2UucmVzb2x2ZSh0cnVlKSxcbiAgICBzZW5kOiAoKSA9PiB7XG4gICAgICBvcGVyYXRpb25zLnB1c2goXCJzZW5kXCIpO1xuICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZShhY2NlcHRlZCk7XG4gICAgfSxcbiAgICBjb21wbGV0ZTogKCkgPT4ge1xuICAgICAgb3BlcmF0aW9ucy5wdXNoKFwiY29tcGxldGVcIik7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKCk7XG4gICAgfSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhvcGVyYXRpb25zLCBbXG4gICAgXCJjbGFpbVwiLFxuICAgIFwic2VuZFwiLFxuICAgIFwiY29tcGxldGVcIixcbiAgICBcImNsYWltXCIsXG4gICAgXCJzZW5kXCIsXG4gICAgXCJjb21wbGV0ZVwiLFxuICBdKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5zZW50LCAyKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5jb21wbGV0aW9uX3BlbmRpbmcsIDApO1xufSk7XG5cbkRlbm8udGVzdChcImFjY2VwdGVkIHB1c2ggd2l0aCBhIGxvc3QgY29tcGxldGlvbiByZXNwb25zZSBpcyBuZXZlciBtYXJrZWQgZm9yIHJldHJ5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgY29tcGxldGlvbnM6IERlbGl2ZXJ5UmVzdWx0W10gPSBbXTtcbiAgbGV0IGNsYWltcyA9IDA7XG4gIGNvbnN0IHJlc3VsdCA9IGF3YWl0IGRpc3BhdGNoTm90aWZpY2F0aW9ucyg1MDAsIHtcbiAgICBjbGFpbTogKCkgPT4ge1xuICAgICAgY2xhaW1zICs9IDE7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKGRlbGl2ZXJ5KCkpO1xuICAgIH0sXG4gICAgaXNDdXJyZW50OiAoKSA9PiBQcm9taXNlLnJlc29sdmUodHJ1ZSksXG4gICAgc2VuZDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKGFjY2VwdGVkKSxcbiAgICBjb21wbGV0ZTogKF9kZWxpdmVyeSwgb3V0Y29tZSkgPT4ge1xuICAgICAgY29tcGxldGlvbnMucHVzaChvdXRjb21lKTtcbiAgICAgIHRocm93IG5ldyBFcnJvcihcIkRhdGFiYXNlIHJlc3BvbnNlIGxvc3QgYWZ0ZXIgY29tbWl0XCIpO1xuICAgIH0sXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMoY2xhaW1zLCAxKTtcbiAgYXNzZXJ0RXF1YWxzKGNvbXBsZXRpb25zLCBbYWNjZXB0ZWRdKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5jb21wbGV0aW9uX3BlbmRpbmcsIDEpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LnNlbnQsIDApO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LnJldHJ5aW5nLCAwKTtcbn0pO1xuXG5EZW5vLnRlc3QoXCJ0cmFuc3BvcnQgZmFpbHVyZSB1c2VzIHRoZSBsZWFzZSBhdHRlbXB0IGFuZCBleGhhdXN0cyB0aGUgZmlmdGggYXR0ZW1wdFwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGxlYXNlID0gZGVsaXZlcnkoNSk7XG4gIGNvbnN0IGNvbXBsZXRpb25zOiBBcnJheTx7IGxlYXNlOiBDbGFpbWVkRGVsaXZlcnk7IHJlc3VsdDogRGVsaXZlcnlSZXN1bHQgfT4gPVxuICAgIFtdO1xuICBjb25zdCByZXN1bHQgPSBhd2FpdCBkaXNwYXRjaE5vdGlmaWNhdGlvbnMoMSwge1xuICAgIGNsYWltOiAoKSA9PiBQcm9taXNlLnJlc29sdmUobGVhc2UpLFxuICAgIGlzQ3VycmVudDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHRydWUpLFxuICAgIHNlbmQ6ICgpID0+IHtcbiAgICAgIHRocm93IG5ldyBFcnJvcihcInByaXZhdGUgcHJvdmlkZXIgYm9keSBhbmQgdG9rZW5cIik7XG4gICAgfSxcbiAgICBjb21wbGV0ZTogKGNsYWltZWQsIG91dGNvbWUpID0+IHtcbiAgICAgIGNvbXBsZXRpb25zLnB1c2goeyBsZWFzZTogY2xhaW1lZCwgcmVzdWx0OiBvdXRjb21lIH0pO1xuICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSgpO1xuICAgIH0sXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMoY29tcGxldGlvbnNbMF0ubGVhc2UsIGxlYXNlKTtcbiAgYXNzZXJ0RXF1YWxzKGNvbXBsZXRpb25zWzBdLnJlc3VsdC5lcnJvckNvZGUsIFwidHJhbnNwb3J0X2V4Y2VwdGlvblwiKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5mYWlsZWQsIDEpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LnJldHJ5aW5nLCAwKTtcbn0pO1xuXG5EZW5vLnRlc3QoXCJyZXRyeWFibGUgcHJvdmlkZXIgZmFpbHVyZSBiZWxvdyBleGhhdXN0aW9uIGlzIHJlcG9ydGVkIGFzIHF1ZXVlZFwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IHJlc3VsdCA9IGF3YWl0IGRpc3BhdGNoTm90aWZpY2F0aW9ucygxLCB7XG4gICAgY2xhaW06ICgpID0+IFByb21pc2UucmVzb2x2ZShkZWxpdmVyeSg0KSksXG4gICAgaXNDdXJyZW50OiAoKSA9PiBQcm9taXNlLnJlc29sdmUodHJ1ZSksXG4gICAgc2VuZDogKCkgPT5cbiAgICAgIFByb21pc2UucmVzb2x2ZSh7XG4gICAgICAgIC4uLmFjY2VwdGVkLFxuICAgICAgICBvazogZmFsc2UsXG4gICAgICAgIHJldHJ5YWJsZTogdHJ1ZSxcbiAgICAgICAgZXJyb3JDb2RlOiBcImh0dHBfNTAzXCIsXG4gICAgICB9KSxcbiAgICBjb21wbGV0ZTogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKCksXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LnJldHJ5aW5nLCAxKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5mYWlsZWQsIDApO1xufSk7XG5cbkRlbm8udGVzdChcImludmFsaWQgcHJvdmlkZXIgdG9rZW4gaXMgdGVybWluYWwgd2l0aG91dCBhbiBpbi1wcm9jZXNzIHJldHJ5XCIsIGFzeW5jICgpID0+IHtcbiAgbGV0IHNlbmRzID0gMDtcbiAgY29uc3QgcmVzdWx0ID0gYXdhaXQgZGlzcGF0Y2hOb3RpZmljYXRpb25zKDEsIHtcbiAgICBjbGFpbTogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKGRlbGl2ZXJ5KCkpLFxuICAgIGlzQ3VycmVudDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHRydWUpLFxuICAgIHNlbmQ6ICgpID0+IHtcbiAgICAgIHNlbmRzICs9IDE7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHtcbiAgICAgICAgLi4uYWNjZXB0ZWQsXG4gICAgICAgIG9rOiBmYWxzZSxcbiAgICAgICAgZXJyb3JDb2RlOiBcIlVOUkVHSVNURVJFRFwiLFxuICAgICAgfSk7XG4gICAgfSxcbiAgICBjb21wbGV0ZTogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKCksXG4gIH0pO1xuICBhc3NlcnRFcXVhbHMoc2VuZHMsIDEpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LmZhaWxlZCwgMSk7XG59KTtcblxuRGVuby50ZXN0KFwiZGlzcGF0Y2ggc3RvcHMgY2xhaW1pbmcgd2l0aCBhIGZ1bGwgc2VuZCBidWRnZXQgc3RpbGwgcmVzZXJ2ZWRcIiwgYXN5bmMgKCkgPT4ge1xuICBsZXQgY2xvY2sgPSAwO1xuICBsZXQgY2xhaW1zID0gMDtcbiAgY29uc3QgcmVzdWx0ID0gYXdhaXQgZGlzcGF0Y2hOb3RpZmljYXRpb25zKDUwMCwge1xuICAgIG5vdzogKCkgPT4gY2xvY2ssXG4gICAgY2xhaW06ICgpID0+IHtcbiAgICAgIGNsYWltcyArPSAxO1xuICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZShkZWxpdmVyeSgpKTtcbiAgICB9LFxuICAgIGlzQ3VycmVudDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHRydWUpLFxuICAgIHNlbmQ6ICgpID0+IHtcbiAgICAgIGNsb2NrICs9IGRpc3BhdGNoQnVkZ2V0TXMgLSBtaW5pbXVtRGlzcGF0Y2hSZW1haW5pbmdNcyArIDE7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKGFjY2VwdGVkKTtcbiAgICB9LFxuICAgIGNvbXBsZXRlOiAoKSA9PiBQcm9taXNlLnJlc29sdmUoKSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhjbGFpbXMsIDEpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LnNlbnQsIDEpO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LmJ1ZGdldF9leGhhdXN0ZWQsIHRydWUpO1xufSk7XG5cbkRlbm8udGVzdChcImFuIGVtcHR5IHF1ZXVlIGVuZHMgd2l0aG91dCBwcm92aWRlciBvciBjb21wbGV0aW9uIGNhbGxzXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgcmVzdWx0ID0gYXdhaXQgZGlzcGF0Y2hOb3RpZmljYXRpb25zKDUwMCwge1xuICAgIGNsYWltOiAoKSA9PiBQcm9taXNlLnJlc29sdmUobnVsbCksXG4gICAgaXNDdXJyZW50OiAoKSA9PiBQcm9taXNlLnJlc29sdmUodHJ1ZSksXG4gICAgc2VuZDogKCkgPT4ge1xuICAgICAgdGhyb3cgbmV3IEVycm9yKFwibXVzdCBub3Qgc2VuZFwiKTtcbiAgICB9LFxuICAgIGNvbXBsZXRlOiAoKSA9PiB7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoXCJtdXN0IG5vdCBjb21wbGV0ZVwiKTtcbiAgICB9LFxuICB9KTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5jbGFpbWVkLCAwKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5jb21wbGV0aW9uX3BlbmRpbmcsIDApO1xuICBhc3NlcnRFcXVhbHMocmVzdWx0LmJ1ZGdldF9leGhhdXN0ZWQsIGZhbHNlKTtcbn0pO1xuXG5EZW5vLnRlc3QoXCJjbGFpbSBmYWlsdXJlIGNhbm5vdCBjYXVzZSBhIHByb3ZpZGVyIGNhbGxcIiwgYXN5bmMgKCkgPT4ge1xuICBsZXQgcmVqZWN0ZWQgPSBmYWxzZTtcbiAgbGV0IHNlbmRzID0gMDtcbiAgdHJ5IHtcbiAgICBhd2FpdCBkaXNwYXRjaE5vdGlmaWNhdGlvbnMoMSwge1xuICAgICAgY2xhaW06ICgpID0+IHtcbiAgICAgICAgdGhyb3cgbmV3IEVycm9yKFwiUlBDIHVuYXZhaWxhYmxlXCIpO1xuICAgICAgfSxcbiAgICAgIGlzQ3VycmVudDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHRydWUpLFxuICAgICAgc2VuZDogKCkgPT4ge1xuICAgICAgICBzZW5kcyArPSAxO1xuICAgICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKGFjY2VwdGVkKTtcbiAgICAgIH0sXG4gICAgICBjb21wbGV0ZTogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKCksXG4gICAgfSk7XG4gIH0gY2F0Y2gge1xuICAgIHJlamVjdGVkID0gdHJ1ZTtcbiAgfVxuICBhc3NlcnRFcXVhbHMocmVqZWN0ZWQsIHRydWUpO1xuICBhc3NlcnRFcXVhbHMoc2VuZHMsIDApO1xufSk7XG5cbkRlbm8udGVzdChcImxvc3QgbGVhc2UgcHJlZmxpZ2h0IGNhbm5vdCBzZW5kIG9yIGNvbXBsZXRlIHRoZSByZXBsYWNlbWVudCBjbGFpbVwiLCBhc3luYyAoKSA9PiB7XG4gIGxldCBzZW5kcyA9IDA7XG4gIGxldCBjb21wbGV0aW9ucyA9IDA7XG4gIGNvbnN0IHJlc3VsdCA9IGF3YWl0IGRpc3BhdGNoTm90aWZpY2F0aW9ucygxLCB7XG4gICAgY2xhaW06ICgpID0+IFByb21pc2UucmVzb2x2ZShkZWxpdmVyeSgpKSxcbiAgICBpc0N1cnJlbnQ6ICgpID0+IFByb21pc2UucmVzb2x2ZShmYWxzZSksXG4gICAgc2VuZDogKCkgPT4ge1xuICAgICAgc2VuZHMgKz0gMTtcbiAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoYWNjZXB0ZWQpO1xuICAgIH0sXG4gICAgY29tcGxldGU6ICgpID0+IHtcbiAgICAgIGNvbXBsZXRpb25zICs9IDE7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKCk7XG4gICAgfSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhyZXN1bHQubGVhc2VfbG9zdCwgMSk7XG4gIGFzc2VydEVxdWFscyhzZW5kcywgMCk7XG4gIGFzc2VydEVxdWFscyhjb21wbGV0aW9ucywgMCk7XG59KTtcblxuRGVuby50ZXN0KFwibGVnYWN5IGNsYWltIHdpdGhvdXQgYSBmZW5jZSBmYWlscyBiZWZvcmUgcHJlZmxpZ2h0IGFuZCBwcm92aWRlciBjYWxsc1wiLCBhc3luYyAoKSA9PiB7XG4gIGxldCBwcmVmbGlnaHRzID0gMDtcbiAgbGV0IHNlbmRzID0gMDtcbiAgY29uc3QgbGVnYWN5ID0ge1xuICAgIC4uLmRlbGl2ZXJ5KCksXG4gICAgY2xhaW1fdG9rZW46IHVuZGVmaW5lZCxcbiAgfSBhcyB1bmtub3duIGFzIENsYWltZWREZWxpdmVyeTtcbiAgY29uc3QgcmVzdWx0ID0gYXdhaXQgZGlzcGF0Y2hOb3RpZmljYXRpb25zKDEsIHtcbiAgICBjbGFpbTogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKGxlZ2FjeSksXG4gICAgaXNDdXJyZW50OiAoKSA9PiB7XG4gICAgICBwcmVmbGlnaHRzICs9IDE7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHRydWUpO1xuICAgIH0sXG4gICAgc2VuZDogKCkgPT4ge1xuICAgICAgc2VuZHMgKz0gMTtcbiAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoYWNjZXB0ZWQpO1xuICAgIH0sXG4gICAgY29tcGxldGU6ICgpID0+IFByb21pc2UucmVzb2x2ZSgpLFxuICB9KTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5sZWFzZV9sb3N0LCAxKTtcbiAgYXNzZXJ0RXF1YWxzKHByZWZsaWdodHMsIDApO1xuICBhc3NlcnRFcXVhbHMoc2VuZHMsIDApO1xufSk7XG5cbkRlbm8udGVzdChcImNsYWltIHdpdGhvdXQgcmVjaXBpZW50IGJpbmRpbmcgY2Fubm90IHJlYWNoIGEgcHJvdmlkZXJcIiwgYXN5bmMgKCkgPT4ge1xuICBsZXQgc2VuZHMgPSAwO1xuICBjb25zdCByZXN1bHQgPSBhd2FpdCBkaXNwYXRjaE5vdGlmaWNhdGlvbnMoMSwge1xuICAgIGNsYWltOiAoKSA9PiBQcm9taXNlLnJlc29sdmUoeyAuLi5kZWxpdmVyeSgpLCB1c2VyX2lkOiBcIlwiIH0pLFxuICAgIGlzQ3VycmVudDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHRydWUpLFxuICAgIHNlbmQ6ICgpID0+IHtcbiAgICAgIHNlbmRzKys7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKGFjY2VwdGVkKTtcbiAgICB9LFxuICAgIGNvbXBsZXRlOiAoKSA9PiBQcm9taXNlLnJlc29sdmUoKSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhyZXN1bHQubGVhc2VfbG9zdCwgMSk7XG4gIGFzc2VydEVxdWFscyhzZW5kcywgMCk7XG59KTtcbkRlbm8udGVzdChcInByb3ZpZGVyIGZsb29yIGlzIHByb3BhZ2F0ZWQgYW5kIGV4Y2Vzc2l2ZSB3YWl0IHRlcm1pbmFsaXplcyB3aXRob3V0IGVhcmx5IHJldHJ5XCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChjb25zdCBzZWNvbmRzIG9mIFs5MDAsIDM2MDFdKSB7XG4gICAgbGV0IGNhcHR1cmVkOiBEZWxpdmVyeVJlc3VsdCB8IHVuZGVmaW5lZDtcbiAgICBjb25zdCByZXN1bHQgPSBhd2FpdCBkaXNwYXRjaE5vdGlmaWNhdGlvbnMoMSwge1xuICAgICAgY2xhaW06ICgpID0+IFByb21pc2UucmVzb2x2ZShkZWxpdmVyeSgpKSxcbiAgICAgIGlzQ3VycmVudDogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHRydWUpLFxuICAgICAgc2VuZDogKCkgPT5cbiAgICAgICAgUHJvbWlzZS5yZXNvbHZlKHtcbiAgICAgICAgICAuLi5hY2NlcHRlZCxcbiAgICAgICAgICBvazogZmFsc2UsXG4gICAgICAgICAgcmV0cnlhYmxlOiB0cnVlLFxuICAgICAgICAgIHJldHJ5QWZ0ZXJTZWNvbmRzOiBzZWNvbmRzLFxuICAgICAgICB9KSxcbiAgICAgIGNvbXBsZXRlOiAoX2NsYWltLCBvdXRjb21lKSA9PiB7XG4gICAgICAgIGNhcHR1cmVkID0gb3V0Y29tZTtcbiAgICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSgpO1xuICAgICAgfSxcbiAgICB9KTtcbiAgICBhc3NlcnRFcXVhbHMoY2FwdHVyZWQ/LnJldHJ5QWZ0ZXJTZWNvbmRzLCBzZWNvbmRzKTtcbiAgICBhc3NlcnRFcXVhbHMoY2FwdHVyZWQ/LnJldHJ5YWJsZSwgc2Vjb25kcyA8PSAzNjAwKTtcbiAgICBhc3NlcnRFcXVhbHMocmVzdWx0LnJldHJ5aW5nLCBzZWNvbmRzIDw9IDM2MDAgPyAxIDogMCk7XG4gICAgYXNzZXJ0RXF1YWxzKHJlc3VsdC5mYWlsZWQsIHNlY29uZHMgPiAzNjAwID8gMSA6IDApO1xuICB9XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFlBQVksUUFBUSw0QkFBNEI7QUFDekQsU0FHRSxnQkFBZ0IsRUFDaEIscUJBQXFCLEVBQ3JCLDBCQUEwQixRQUNyQixrQkFBa0I7QUFFekIsU0FBUyxTQUFTLFVBQVUsQ0FBQztFQUMzQixPQUFPO0lBQ0wsYUFBYTtJQUNiLFVBQVU7SUFDVixXQUFXO0lBQ1gsU0FBUztJ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
// denoCacheMetadata=3890213526493701640,9813692528026011226