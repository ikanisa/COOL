import { assertEquals } from "../_shared/test_assert.ts";
import {
  type ClaimedDelivery,
  type DeliveryResult,
  dispatchBudgetMs,
  dispatchNotifications,
  minimumDispatchRemainingMs,
} from "./dispatcher.ts";

function delivery(attempt = 1): ClaimedDelivery {
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
    claim_token: "claim-1",
  };
}

const accepted: DeliveryResult = {
  ok: true,
  retryable: false,
  messageId: "provider-1",
  errorCode: null,
  latencyMs: 10,
};

Deno.test("dispatch claims only after the previous delivery is completed", async () => {
  const operations: string[] = [];
  const result = await dispatchNotifications(2, {
    claim: () => {
      operations.push("claim");
      return Promise.resolve(delivery());
    },
    isCurrent: () => Promise.resolve(true),
    send: () => {
      operations.push("send");
      return Promise.resolve(accepted);
    },
    complete: () => {
      operations.push("complete");
      return Promise.resolve();
    },
  });
  assertEquals(operations, [
    "claim",
    "send",
    "complete",
    "claim",
    "send",
    "complete",
  ]);
  assertEquals(result.sent, 2);
  assertEquals(result.completion_pending, 0);
});

Deno.test("accepted push with a lost completion response is never marked for retry", async () => {
  const completions: DeliveryResult[] = [];
  let claims = 0;
  const result = await dispatchNotifications(500, {
    claim: () => {
      claims += 1;
      return Promise.resolve(delivery());
    },
    isCurrent: () => Promise.resolve(true),
    send: () => Promise.resolve(accepted),
    complete: (_delivery, outcome) => {
      completions.push(outcome);
      throw new Error("Database response lost after commit");
    },
  });
  assertEquals(claims, 1);
  assertEquals(completions, [accepted]);
  assertEquals(result.completion_pending, 1);
  assertEquals(result.sent, 0);
  assertEquals(result.retrying, 0);
});

Deno.test("transport failure uses the lease attempt and exhausts the fifth attempt", async () => {
  const lease = delivery(5);
  const completions: Array<{ lease: ClaimedDelivery; result: DeliveryResult }> =
    [];
  const result = await dispatchNotifications(1, {
    claim: () => Promise.resolve(lease),
    isCurrent: () => Promise.resolve(true),
    send: () => {
      throw new Error("private provider body and token");
    },
    complete: (claimed, outcome) => {
      completions.push({ lease: claimed, result: outcome });
      return Promise.resolve();
    },
  });
  assertEquals(completions[0].lease, lease);
  assertEquals(completions[0].result.errorCode, "transport_exception");
  assertEquals(result.failed, 1);
  assertEquals(result.retrying, 0);
});

Deno.test("retryable provider failure below exhaustion is reported as queued", async () => {
  const result = await dispatchNotifications(1, {
    claim: () => Promise.resolve(delivery(4)),
    isCurrent: () => Promise.resolve(true),
    send: () =>
      Promise.resolve({
        ...accepted,
        ok: false,
        retryable: true,
        errorCode: "http_503",
      }),
    complete: () => Promise.resolve(),
  });
  assertEquals(result.retrying, 1);
  assertEquals(result.failed, 0);
});

Deno.test("invalid provider token is terminal without an in-process retry", async () => {
  let sends = 0;
  const result = await dispatchNotifications(1, {
    claim: () => Promise.resolve(delivery()),
    isCurrent: () => Promise.resolve(true),
    send: () => {
      sends += 1;
      return Promise.resolve({
        ...accepted,
        ok: false,
        errorCode: "UNREGISTERED",
      });
    },
    complete: () => Promise.resolve(),
  });
  assertEquals(sends, 1);
  assertEquals(result.failed, 1);
});

Deno.test("dispatch stops claiming with a full send budget still reserved", async () => {
  let clock = 0;
  let claims = 0;
  const result = await dispatchNotifications(500, {
    now: () => clock,
    claim: () => {
      claims += 1;
      return Promise.resolve(delivery());
    },
    isCurrent: () => Promise.resolve(true),
    send: () => {
      clock += dispatchBudgetMs - minimumDispatchRemainingMs + 1;
      return Promise.resolve(accepted);
    },
    complete: () => Promise.resolve(),
  });
  assertEquals(claims, 1);
  assertEquals(result.sent, 1);
  assertEquals(result.budget_exhausted, true);
});

Deno.test("an empty queue ends without provider or completion calls", async () => {
  const result = await dispatchNotifications(500, {
    claim: () => Promise.resolve(null),
    isCurrent: () => Promise.resolve(true),
    send: () => {
      throw new Error("must not send");
    },
    complete: () => {
      throw new Error("must not complete");
    },
  });
  assertEquals(result.claimed, 0);
  assertEquals(result.completion_pending, 0);
  assertEquals(result.budget_exhausted, false);
});

Deno.test("claim failure cannot cause a provider call", async () => {
  let rejected = false;
  let sends = 0;
  try {
    await dispatchNotifications(1, {
      claim: () => {
        throw new Error("RPC unavailable");
      },
      isCurrent: () => Promise.resolve(true),
      send: () => {
        sends += 1;
        return Promise.resolve(accepted);
      },
      complete: () => Promise.resolve(),
    });
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
  assertEquals(sends, 0);
});

Deno.test("lost lease preflight cannot send or complete the replacement claim", async () => {
  let sends = 0;
  let completions = 0;
  const result = await dispatchNotifications(1, {
    claim: () => Promise.resolve(delivery()),
    isCurrent: () => Promise.resolve(false),
    send: () => {
      sends += 1;
      return Promise.resolve(accepted);
    },
    complete: () => {
      completions += 1;
      return Promise.resolve();
    },
  });
  assertEquals(result.lease_lost, 1);
  assertEquals(sends, 0);
  assertEquals(completions, 0);
});

Deno.test("legacy claim without a fence fails before preflight and provider calls", async () => {
  let preflights = 0;
  let sends = 0;
  const legacy = {
    ...delivery(),
    claim_token: undefined,
  } as unknown as ClaimedDelivery;
  const result = await dispatchNotifications(1, {
    claim: () => Promise.resolve(legacy),
    isCurrent: () => {
      preflights += 1;
      return Promise.resolve(true);
    },
    send: () => {
      sends += 1;
      return Promise.resolve(accepted);
    },
    complete: () => Promise.resolve(),
  });
  assertEquals(result.lease_lost, 1);
  assertEquals(preflights, 0);
  assertEquals(sends, 0);
});

Deno.test("claim without recipient binding cannot reach a provider", async () => {
  let sends = 0;
  const result = await dispatchNotifications(1, {
    claim: () => Promise.resolve({ ...delivery(), user_id: "" }),
    isCurrent: () => Promise.resolve(true),
    send: () => {
      sends++;
      return Promise.resolve(accepted);
    },
    complete: () => Promise.resolve(),
  });
  assertEquals(result.lease_lost, 1);
  assertEquals(sends, 0);
});
Deno.test("provider floor is propagated and excessive wait terminalizes without early retry", async () => {
  for (const seconds of [900, 3601]) {
    let captured: DeliveryResult | undefined;
    const result = await dispatchNotifications(1, {
      claim: () => Promise.resolve(delivery()),
      isCurrent: () => Promise.resolve(true),
      send: () =>
        Promise.resolve({
          ...accepted,
          ok: false,
          retryable: true,
          retryAfterSeconds: seconds,
        }),
      complete: (_claim, outcome) => {
        captured = outcome;
        return Promise.resolve();
      },
    });
    assertEquals(captured?.retryAfterSeconds, seconds);
    assertEquals(captured?.retryable, seconds <= 3600);
    assertEquals(result.retrying, seconds <= 3600 ? 1 : 0);
    assertEquals(result.failed, seconds > 3600 ? 1 : 0);
  }
});
