import {
  createRecordOperationalHealthHandler,
  type RecordOperationalHealthHandlerDependencies,
} from "./index.ts";
import type { OperationalHealthEventInput } from "../_shared/observability.ts";

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

function buildRequest(body: Record<string, unknown>) {
  return new Request(
    "https://example.com/functions/v1/record-operational-health",
    {
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
}

function buildDeps(options: {
  onRecord?: (event: OperationalHealthEventInput) => void | Promise<void>;
  onEdgeFailure?: () => void | Promise<void>;
} = {}): RecordOperationalHealthHandlerDependencies {
  return {
    createAdminClient: () => ({} as ReturnType<
      RecordOperationalHealthHandlerDependencies["createAdminClient"]
    >),
    createUserClient: () =>
      ({
        auth: {
          getUser: async () => ({
            data: { user: { id: "user-1" } },
            error: null,
          }),
        },
      }) as ReturnType<
        RecordOperationalHealthHandlerDependencies["createUserClient"]
      >,
    enforceRateLimit: async () => undefined,
    recordOperationalHealthEvent: async (_adminClient, event) => {
      await options.onRecord?.(event);
    },
    recordEdgeFunctionFailure: async () => {
      await options.onEdgeFailure?.();
    },
  };
}

Deno.test("record-operational-health accepts supported BioPay mobile events", async () => {
  const recordedEvents: OperationalHealthEventInput[] = [];
  const handler = createRecordOperationalHealthHandler(
    buildDeps({
      onRecord: (event) => {
        recordedEvents.push(event);
      },
    }),
  );

  const response = await handler(
    buildRequest({
      service: "biopay",
      component: "matching",
      status: "error",
      message: "BioPay matching failed.",
      metadata: { error: "match_failed" },
      userId: "user-1",
    }),
  );
  const payload = await response.json();

  assertEquals(response.status, 200, "should accept supported mobile event");
  assertEquals(payload.success, true, "should return success");
  if (recordedEvents.length != 1) {
    throw new Error("should record the operational event");
  }
  const event = recordedEvents[0]!;
  assertEquals(event.service, "biopay", "should preserve service");
  assertEquals(
    event.component,
    "matching",
    "should preserve component",
  );
  assertEquals(
    event.userId,
    "user-1",
    "should preserve authenticated user id",
  );
  assertEquals(
    event.ingestOrigin,
    "mobile_app",
    "should tag mobile telemetry origin",
  );
});

Deno.test("record-operational-health rejects unsupported mobile components", async () => {
  let edgeFailureCalls = 0;
  let recordedCalls = 0;
  const handler = createRecordOperationalHealthHandler(
    buildDeps({
      onRecord: () => {
        recordedCalls += 1;
      },
      onEdgeFailure: () => {
        edgeFailureCalls += 1;
      },
    }),
  );

  const response = await handler(
    buildRequest({
      service: "biopay",
      component: "unknown_component",
      message: "Unexpected event",
    }),
  );
  const payload = await response.json();

  assertEquals(
    response.status,
    400,
    "should reject unsupported service/component pairs",
  );
  assertEquals(
    payload.message,
    "Unsupported operational service/component",
    "should return a clear validation message",
  );
  assertEquals(recordedCalls, 0, "should not record invalid events");
  assertEquals(
    edgeFailureCalls,
    0,
    "should not classify validation failures as edge crashes",
  );
});
