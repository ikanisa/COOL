import { assertEquals } from "../_shared/test_assert.ts";
import {
  createNotificationHandler,
  type NotificationDependencies,
  requestDispatch,
} from "./handler.ts";

const user = "99870000-0000-4000-8000-000000000001";
const event = "99870000-0000-4000-8000-000000000020";
function request(overrides = {}, signal?: AbortSignal) {
  return new Request("https://collect.test/notification", {
    method: "POST",
    signal,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      user_id: user,
      type: "notice",
      title: "Private title",
      body: "Private body",
      ...overrides,
    }),
  });
}
function dependencies(
  overrides: Partial<NotificationDependencies> = {},
): NotificationDependencies {
  return {
    authorize: () => {},
    enqueue: () => Promise.resolve({ data: event, error: null }),
    dispatch: () => Promise.resolve(true),
    timeoutMs: 20,
    ...overrides,
  };
}
Deno.test("committed enqueue survives a stalled wakeup with exactly one enqueue", async () => {
  let enqueues = 0;
  let wakeSignal: AbortSignal | undefined;
  const handle = createNotificationHandler(dependencies({
    enqueue: (_name, _params, signal) => {
      enqueues++;
      assertEquals(signal.aborted, false);
      return Promise.resolve({ data: event, error: null });
    },
    dispatch: (signal) => {
      wakeSignal = signal;
      return new Promise(() => {});
    },
  }));
  const response = await handle(request());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    ok: true,
    skipped: false,
    notification_event_id: event,
    dispatch_requested: false,
  });
  assertEquals(enqueues, 1);
  assertEquals(wakeSignal?.aborted, true);
});
Deno.test("uncertain enqueue times out without replay or dispatch and redacts error", async () => {
  let enqueues = 0;
  let sends = 0;
  let signal: AbortSignal | undefined;
  const response = await createNotificationHandler(
    dependencies({
      enqueue: (_n, _p, s) => {
        enqueues++;
        signal = s;
        return new Promise(() => {});
      },
      dispatch: () => {
        sends++;
        return Promise.resolve(true);
      },
    }),
  )(request());
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "service_unavailable" });
  assertEquals(enqueues, 1);
  assertEquals(sends, 0);
  assertEquals(signal?.aborted, true);
});
Deno.test("template enqueue passes authorized full content while skipped preferences cause no wakeup", async () => {
  let name = "";
  let calls = 0;
  const response = await createNotificationHandler(dependencies({
    enqueue: (n, p) => {
      name = n;
      assertEquals(p.p_context, { amount: 5000 });
      return Promise.resolve({ data: null, error: null });
    },
    dispatch: () => {
      calls++;
      return Promise.resolve(true);
    },
  }))(request({ template_key: "contribution", context: { amount: 5000 } }));
  assertEquals(name, "enqueue_notification_template_event");
  assertEquals((await response.json()).skipped, true);
  assertEquals(calls, 0);
});
Deno.test("abort after enqueue leaves durable event successful without another side effect", async () => {
  const controller = new AbortController();
  let wakeups = 0;
  const response = await createNotificationHandler(
    dependencies({
      enqueue: () => {
        controller.abort();
        return Promise.resolve({ data: event, error: null });
      },
      dispatch: () => {
        wakeups++;
        return Promise.resolve(true);
      },
    }),
  )(request({}, controller.signal));
  // Cancellation racing an enqueue ACK may be uncertain; it must never re-enqueue.
  assertEquals([200, 503].includes(response.status), true);
  assertEquals(wakeups, 0);
});
Deno.test("stalled request body is cancelled before database work", async () => {
  let cancelled = false;
  let enqueues = 0;
  const body = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
    },
  });
  const response = await createNotificationHandler(
    dependencies({
      enqueue: () => {
        enqueues++;
        return Promise.resolve({ data: event, error: null });
      },
    }),
  )(
    new Request("https://collect.test", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body,
    }),
  );
  assertEquals(response.status, 503);
  assertEquals(cancelled, true);
  assertEquals(enqueues, 0);
});
Deno.test("unauthorized and oversized input cannot enqueue", async () => {
  let calls = 0;
  const handler = createNotificationHandler(dependencies({
    authorize: () => {
      throw new Error("Internal function authorization failed");
    },
    enqueue: () => {
      calls++;
      throw new Error("must not enqueue");
    },
  }));
  assertEquals((await handler(request())).status, 401);
  assertEquals(
    (await createNotificationHandler(dependencies({
      enqueue: () => {
        calls++;
        throw new Error("must not enqueue");
      },
    }))(request({ body: "x".repeat(17000) }))).status,
    413,
  );
  assertEquals(calls, 0);
});
Deno.test("dispatch wakeup enforces signal and redirect:error and rejects redirects/server errors", async () => {
  for (const status of [200, 302, 500]) {
    let calls = 0;
    const signal = AbortSignal.timeout(1000);
    const accepted = await requestDispatch(
      "https://collect.supabase.co",
      "synthetic-api-key",
      "synthetic-secret",
      signal,
      (_url, init) => {
        calls++;
        assertEquals(init?.redirect, "error");
        assertEquals(init?.signal, signal);
        return Promise.resolve(new Response("", { status }));
      },
    );
    assertEquals(accepted, status === 200);
    assertEquals(calls, 1);
  }
});
Deno.test("wakeup refuses insecure/credentialed destinations without forwarding secrets", async () => {
  let calls = 0;
  for (
    const url of [
      "http://collect.supabase.co",
      "https://user:pass@collect.supabase.co",
      "not-url",
    ]
  ) {
    assertEquals(
      await requestDispatch(
        url,
        "synthetic-api-key",
        "synthetic-secret",
        AbortSignal.timeout(1000),
        () => {
          calls++;
          throw new Error("no fetch");
        },
      ),
      false,
    );
  }
  assertEquals(calls, 0);
});
