import { assertEquals } from "../_shared/test_assert.ts";
import { createNotificationHandler, requestDispatch } from "./handler.ts";
const user = "99870000-0000-4000-8000-000000000001";
const event = "99870000-0000-4000-8000-000000000020";
function request(overrides = {}, signal) {
  return new Request("https://collect.test/notification", {
    method: "POST",
    signal,
    headers: {
      "content-type": "application/json"
    },
    body: JSON.stringify({
      user_id: user,
      type: "notice",
      title: "Private title",
      body: "Private body",
      ...overrides
    })
  });
}
function dependencies(overrides = {}) {
  return {
    authorize: ()=>{},
    enqueue: ()=>Promise.resolve({
        data: event,
        error: null
      }),
    dispatch: ()=>Promise.resolve(true),
    timeoutMs: 20,
    ...overrides
  };
}
Deno.test("committed enqueue survives a stalled wakeup with exactly one enqueue", async ()=>{
  let enqueues = 0;
  let wakeSignal;
  const handle = createNotificationHandler(dependencies({
    enqueue: (_name, _params, signal)=>{
      enqueues++;
      assertEquals(signal.aborted, false);
      return Promise.resolve({
        data: event,
        error: null
      });
    },
    dispatch: (signal)=>{
      wakeSignal = signal;
      return new Promise(()=>{});
    }
  }));
  const response = await handle(request());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    ok: true,
    skipped: false,
    notification_event_id: event,
    dispatch_requested: false
  });
  assertEquals(enqueues, 1);
  assertEquals(wakeSignal?.aborted, true);
});
Deno.test("uncertain enqueue times out without replay or dispatch and redacts error", async ()=>{
  let enqueues = 0;
  let sends = 0;
  let signal;
  const response = await createNotificationHandler(dependencies({
    enqueue: (_n, _p, s)=>{
      enqueues++;
      signal = s;
      return new Promise(()=>{});
    },
    dispatch: ()=>{
      sends++;
      return Promise.resolve(true);
    }
  }))(request());
  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error: "service_unavailable"
  });
  assertEquals(enqueues, 1);
  assertEquals(sends, 0);
  assertEquals(signal?.aborted, true);
});
Deno.test("template enqueue passes authorized full content while skipped preferences cause no wakeup", async ()=>{
  let name = "";
  let calls = 0;
  const response = await createNotificationHandler(dependencies({
    enqueue: (n, p)=>{
      name = n;
      assertEquals(p.p_context, {
        amount: 5000
      });
      return Promise.resolve({
        data: null,
        error: null
      });
    },
    dispatch: ()=>{
      calls++;
      return Promise.resolve(true);
    }
  }))(request({
    template_key: "contribution",
    context: {
      amount: 5000
    }
  }));
  assertEquals(name, "enqueue_notification_template_event");
  assertEquals((await response.json()).skipped, true);
  assertEquals(calls, 0);
});
Deno.test("abort after enqueue leaves durable event successful without another side effect", async ()=>{
  const controller = new AbortController();
  let wakeups = 0;
  const response = await createNotificationHandler(dependencies({
    enqueue: ()=>{
      controller.abort();
      return Promise.resolve({
        data: event,
        error: null
      });
    },
    dispatch: ()=>{
      wakeups++;
      return Promise.resolve(true);
    }
  }))(request({}, controller.signal));
  // Cancellation racing an enqueue ACK may be uncertain; it must never re-enqueue.
  assertEquals([
    200,
    503
  ].includes(response.status), true);
  assertEquals(wakeups, 0);
});
Deno.test("stalled request body is cancelled before database work", async ()=>{
  let cancelled = false;
  let enqueues = 0;
  const body = new ReadableStream({
    cancel () {
      cancelled = true;
    }
  });
  const response = await createNotificationHandler(dependencies({
    enqueue: ()=>{
      enqueues++;
      return Promise.resolve({
        data: event,
        error: null
      });
    }
  }))(new Request("https://collect.test", {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body
  }));
  assertEquals(response.status, 503);
  assertEquals(cancelled, true);
  assertEquals(enqueues, 0);
});
Deno.test("unauthorized and oversized input cannot enqueue", async ()=>{
  let calls = 0;
  const handler = createNotificationHandler(dependencies({
    authorize: ()=>{
      throw new Error("Internal function authorization failed");
    },
    enqueue: ()=>{
      calls++;
      throw new Error("must not enqueue");
    }
  }));
  assertEquals((await handler(request())).status, 401);
  assertEquals((await createNotificationHandler(dependencies({
    enqueue: ()=>{
      calls++;
      throw new Error("must not enqueue");
    }
  }))(request({
    body: "x".repeat(17000)
  }))).status, 413);
  assertEquals(calls, 0);
});
Deno.test("dispatch wakeup enforces signal and redirect:error and rejects redirects/server errors", async ()=>{
  for (const status of [
    200,
    302,
    500
  ]){
    let calls = 0;
    const signal = AbortSignal.timeout(1000);
    const accepted = await requestDispatch("https://collect.supabase.co", "synthetic-api-key", "synthetic-secret", signal, (_url, init)=>{
      calls++;
      assertEquals(init?.redirect, "error");
      assertEquals(init?.signal, signal);
      return Promise.resolve(new Response("", {
        status
      }));
    });
    assertEquals(accepted, status === 200);
    assertEquals(calls, 1);
  }
});
Deno.test("wakeup refuses insecure/credentialed destinations without forwarding secrets", async ()=>{
  let calls = 0;
  for (const url of [
    "http://collect.supabase.co",
    "https://user:pass@collect.supabase.co",
    "not-url"
  ]){
    assertEquals(await requestDispatch(url, "synthetic-api-key", "synthetic-secret", AbortSignal.timeout(1000), ()=>{
      calls++;
      throw new Error("no fetch");
    }), false);
  }
  assertEquals(calls, 0);
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3NlbmQtbm90aWZpY2F0aW9uL2hhbmRsZXJfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBhc3NlcnRFcXVhbHMgfSBmcm9tIFwiLi4vX3NoYXJlZC90ZXN0X2Fzc2VydC50c1wiO1xuaW1wb3J0IHtcbiAgY3JlYXRlTm90aWZpY2F0aW9uSGFuZGxlcixcbiAgdHlwZSBOb3RpZmljYXRpb25EZXBlbmRlbmNpZXMsXG4gIHJlcXVlc3REaXNwYXRjaCxcbn0gZnJvbSBcIi4vaGFuZGxlci50c1wiO1xuXG5jb25zdCB1c2VyID0gXCI5OTg3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDFcIjtcbmNvbnN0IGV2ZW50ID0gXCI5OTg3MDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMjBcIjtcbmZ1bmN0aW9uIHJlcXVlc3Qob3ZlcnJpZGVzID0ge30sIHNpZ25hbD86IEFib3J0U2lnbmFsKSB7XG4gIHJldHVybiBuZXcgUmVxdWVzdChcImh0dHBzOi8vY29sbGVjdC50ZXN0L25vdGlmaWNhdGlvblwiLCB7XG4gICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICBzaWduYWwsXG4gICAgaGVhZGVyczogeyBcImNvbnRlbnQtdHlwZVwiOiBcImFwcGxpY2F0aW9uL2pzb25cIiB9LFxuICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHtcbiAgICAgIHVzZXJfaWQ6IHVzZXIsXG4gICAgICB0eXBlOiBcIm5vdGljZVwiLFxuICAgICAgdGl0bGU6IFwiUHJpdmF0ZSB0aXRsZVwiLFxuICAgICAgYm9keTogXCJQcml2YXRlIGJvZHlcIixcbiAgICAgIC4uLm92ZXJyaWRlcyxcbiAgICB9KSxcbiAgfSk7XG59XG5mdW5jdGlvbiBkZXBlbmRlbmNpZXMoXG4gIG92ZXJyaWRlczogUGFydGlhbDxOb3RpZmljYXRpb25EZXBlbmRlbmNpZXM+ID0ge30sXG4pOiBOb3RpZmljYXRpb25EZXBlbmRlbmNpZXMge1xuICByZXR1cm4ge1xuICAgIGF1dGhvcml6ZTogKCkgPT4ge30sXG4gICAgZW5xdWV1ZTogKCkgPT4gUHJvbWlzZS5yZXNvbHZlKHsgZGF0YTogZXZlbnQsIGVycm9yOiBudWxsIH0pLFxuICAgIGRpc3BhdGNoOiAoKSA9PiBQcm9taXNlLnJlc29sdmUodHJ1ZSksXG4gICAgdGltZW91dE1zOiAyMCxcbiAgICAuLi5vdmVycmlkZXMsXG4gIH07XG59XG5EZW5vLnRlc3QoXCJjb21taXR0ZWQgZW5xdWV1ZSBzdXJ2aXZlcyBhIHN0YWxsZWQgd2FrZXVwIHdpdGggZXhhY3RseSBvbmUgZW5xdWV1ZVwiLCBhc3luYyAoKSA9PiB7XG4gIGxldCBlbnF1ZXVlcyA9IDA7XG4gIGxldCB3YWtlU2lnbmFsOiBBYm9ydFNpZ25hbCB8IHVuZGVmaW5lZDtcbiAgY29uc3QgaGFuZGxlID0gY3JlYXRlTm90aWZpY2F0aW9uSGFuZGxlcihkZXBlbmRlbmNpZXMoe1xuICAgIGVucXVldWU6IChfbmFtZSwgX3BhcmFtcywgc2lnbmFsKSA9PiB7XG4gICAgICBlbnF1ZXVlcysrO1xuICAgICAgYXNzZXJ0RXF1YWxzKHNpZ25hbC5hYm9ydGVkLCBmYWxzZSk7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHsgZGF0YTogZXZlbnQsIGVycm9yOiBudWxsIH0pO1xuICAgIH0sXG4gICAgZGlzcGF0Y2g6IChzaWduYWwpID0+IHtcbiAgICAgIHdha2VTaWduYWwgPSBzaWduYWw7XG4gICAgICByZXR1cm4gbmV3IFByb21pc2UoKCkgPT4ge30pO1xuICAgIH0sXG4gIH0pKTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBoYW5kbGUocmVxdWVzdCgpKTtcbiAgYXNzZXJ0RXF1YWxzKHJlc3BvbnNlLnN0YXR1cywgMjAwKTtcbiAgYXNzZXJ0RXF1YWxzKGF3YWl0IHJlc3BvbnNlLmpzb24oKSwge1xuICAgIG9rOiB0cnVlLFxuICAgIHNraXBwZWQ6IGZhbHNlLFxuICAgIG5vdGlmaWNhdGlvbl9ldmVudF9pZDogZXZlbnQsXG4gICAgZGlzcGF0Y2hfcmVxdWVzdGVkOiBmYWxzZSxcbiAgfSk7XG4gIGFzc2VydEVxdWFscyhlbnF1ZXVlcywgMSk7XG4gIGFzc2VydEVxdWFscyh3YWtlU2lnbmFsPy5hYm9ydGVkLCB0cnVlKTtcbn0pO1xuRGVuby50ZXN0KFwidW5jZXJ0YWluIGVucXVldWUgdGltZXMgb3V0IHdpdGhvdXQgcmVwbGF5IG9yIGRpc3BhdGNoIGFuZCByZWRhY3RzIGVycm9yXCIsIGFzeW5jICgpID0+IHtcbiAgbGV0IGVucXVldWVzID0gMDtcbiAgbGV0IHNlbmRzID0gMDtcbiAgbGV0IHNpZ25hbDogQWJvcnRTaWduYWwgfCB1bmRlZmluZWQ7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgY3JlYXRlTm90aWZpY2F0aW9uSGFuZGxlcihcbiAgICBkZXBlbmRlbmNpZXMoe1xuICAgICAgZW5xdWV1ZTogKF9uLCBfcCwgcykgPT4ge1xuICAgICAgICBlbnF1ZXVlcysrO1xuICAgICAgICBzaWduYWwgPSBzO1xuICAgICAgICByZXR1cm4gbmV3IFByb21pc2UoKCkgPT4ge30pO1xuICAgICAgfSxcbiAgICAgIGRpc3BhdGNoOiAoKSA9PiB7XG4gICAgICAgIHNlbmRzKys7XG4gICAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUodHJ1ZSk7XG4gICAgICB9LFxuICAgIH0pLFxuICApKHJlcXVlc3QoKSk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDUwMyk7XG4gIGFzc2VydEVxdWFscyhhd2FpdCByZXNwb25zZS5qc29uKCksIHsgZXJyb3I6IFwic2VydmljZV91bmF2YWlsYWJsZVwiIH0pO1xuICBhc3NlcnRFcXVhbHMoZW5xdWV1ZXMsIDEpO1xuICBhc3NlcnRFcXVhbHMoc2VuZHMsIDApO1xuICBhc3NlcnRFcXVhbHMoc2lnbmFsPy5hYm9ydGVkLCB0cnVlKTtcbn0pO1xuRGVuby50ZXN0KFwidGVtcGxhdGUgZW5xdWV1ZSBwYXNzZXMgYXV0aG9yaXplZCBmdWxsIGNvbnRlbnQgd2hpbGUgc2tpcHBlZCBwcmVmZXJlbmNlcyBjYXVzZSBubyB3YWtldXBcIiwgYXN5bmMgKCkgPT4ge1xuICBsZXQgbmFtZSA9IFwiXCI7XG4gIGxldCBjYWxscyA9IDA7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgY3JlYXRlTm90aWZpY2F0aW9uSGFuZGxlcihkZXBlbmRlbmNpZXMoe1xuICAgIGVucXVldWU6IChuLCBwKSA9PiB7XG4gICAgICBuYW1lID0gbjtcbiAgICAgIGFzc2VydEVxdWFscyhwLnBfY29udGV4dCwgeyBhbW91bnQ6IDUwMDAgfSk7XG4gICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHsgZGF0YTogbnVsbCwgZXJyb3I6IG51bGwgfSk7XG4gICAgfSxcbiAgICBkaXNwYXRjaDogKCkgPT4ge1xuICAgICAgY2FsbHMrKztcbiAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUodHJ1ZSk7XG4gICAgfSxcbiAgfSkpKHJlcXVlc3QoeyB0ZW1wbGF0ZV9rZXk6IFwiY29udHJpYnV0aW9uXCIsIGNvbnRleHQ6IHsgYW1vdW50OiA1MDAwIH0gfSkpO1xuICBhc3NlcnRFcXVhbHMobmFtZSwgXCJlbnF1ZXVlX25vdGlmaWNhdGlvbl90ZW1wbGF0ZV9ldmVudFwiKTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCByZXNwb25zZS5qc29uKCkpLnNraXBwZWQsIHRydWUpO1xuICBhc3NlcnRFcXVhbHMoY2FsbHMsIDApO1xufSk7XG5EZW5vLnRlc3QoXCJhYm9ydCBhZnRlciBlbnF1ZXVlIGxlYXZlcyBkdXJhYmxlIGV2ZW50IHN1Y2Nlc3NmdWwgd2l0aG91dCBhbm90aGVyIHNpZGUgZWZmZWN0XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgY29udHJvbGxlciA9IG5ldyBBYm9ydENvbnRyb2xsZXIoKTtcbiAgbGV0IHdha2V1cHMgPSAwO1xuICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGNyZWF0ZU5vdGlmaWNhdGlvbkhhbmRsZXIoXG4gICAgZGVwZW5kZW5jaWVzKHtcbiAgICAgIGVucXVldWU6ICgpID0+IHtcbiAgICAgICAgY29udHJvbGxlci5hYm9ydCgpO1xuICAgICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKHsgZGF0YTogZXZlbnQsIGVycm9yOiBudWxsIH0pO1xuICAgICAgfSxcbiAgICAgIGRpc3BhdGNoOiAoKSA9PiB7XG4gICAgICAgIHdha2V1cHMrKztcbiAgICAgICAgcmV0dXJuIFByb21pc2UucmVzb2x2ZSh0cnVlKTtcbiAgICAgIH0sXG4gICAgfSksXG4gICkocmVxdWVzdCh7fSwgY29udHJvbGxlci5zaWduYWwpKTtcbiAgLy8gQ2FuY2VsbGF0aW9uIHJhY2luZyBhbiBlbnF1ZXVlIEFDSyBtYXkgYmUgdW5jZXJ0YWluOyBpdCBtdXN0IG5ldmVyIHJlLWVucXVldWUuXG4gIGFzc2VydEVxdWFscyhbMjAwLCA1MDNdLmluY2x1ZGVzKHJlc3BvbnNlLnN0YXR1cyksIHRydWUpO1xuICBhc3NlcnRFcXVhbHMod2FrZXVwcywgMCk7XG59KTtcbkRlbm8udGVzdChcInN0YWxsZWQgcmVxdWVzdCBib2R5IGlzIGNhbmNlbGxlZCBiZWZvcmUgZGF0YWJhc2Ugd29ya1wiLCBhc3luYyAoKSA9PiB7XG4gIGxldCBjYW5jZWxsZWQgPSBmYWxzZTtcbiAgbGV0IGVucXVldWVzID0gMDtcbiAgY29uc3QgYm9keSA9IG5ldyBSZWFkYWJsZVN0cmVhbTxVaW50OEFycmF5Pih7XG4gICAgY2FuY2VsKCkge1xuICAgICAgY2FuY2VsbGVkID0gdHJ1ZTtcbiAgICB9LFxuICB9KTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBjcmVhdGVOb3RpZmljYXRpb25IYW5kbGVyKFxuICAgIGRlcGVuZGVuY2llcyh7XG4gICAgICBlbnF1ZXVlOiAoKSA9PiB7XG4gICAgICAgIGVucXVldWVzKys7XG4gICAgICAgIHJldHVybiBQcm9taXNlLnJlc29sdmUoeyBkYXRhOiBldmVudCwgZXJyb3I6IG51bGwgfSk7XG4gICAgICB9LFxuICAgIH0pLFxuICApKFxuICAgIG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9jb2xsZWN0LnRlc3RcIiwge1xuICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgIGhlYWRlcnM6IHsgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIgfSxcbiAgICAgIGJvZHksXG4gICAgfSksXG4gICk7XG4gIGFzc2VydEVxdWFscyhyZXNwb25zZS5zdGF0dXMsIDUwMyk7XG4gIGFzc2VydEVxdWFscyhjYW5jZWxsZWQsIHRydWUpO1xuICBhc3NlcnRFcXVhbHMoZW5xdWV1ZXMsIDApO1xufSk7XG5EZW5vLnRlc3QoXCJ1bmF1dGhvcml6ZWQgYW5kIG92ZXJzaXplZCBpbnB1dCBjYW5ub3QgZW5xdWV1ZVwiLCBhc3luYyAoKSA9PiB7XG4gIGxldCBjYWxscyA9IDA7XG4gIGNvbnN0IGhhbmRsZXIgPSBjcmVhdGVOb3RpZmljYXRpb25IYW5kbGVyKGRlcGVuZGVuY2llcyh7XG4gICAgYXV0aG9yaXplOiAoKSA9PiB7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoXCJJbnRlcm5hbCBmdW5jdGlvbiBhdXRob3JpemF0aW9uIGZhaWxlZFwiKTtcbiAgICB9LFxuICAgIGVucXVldWU6ICgpID0+IHtcbiAgICAgIGNhbGxzKys7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoXCJtdXN0IG5vdCBlbnF1ZXVlXCIpO1xuICAgIH0sXG4gIH0pKTtcbiAgYXNzZXJ0RXF1YWxzKChhd2FpdCBoYW5kbGVyKHJlcXVlc3QoKSkpLnN0YXR1cywgNDAxKTtcbiAgYXNzZXJ0RXF1YWxzKFxuICAgIChhd2FpdCBjcmVhdGVOb3RpZmljYXRpb25IYW5kbGVyKGRlcGVuZGVuY2llcyh7XG4gICAgICBlbnF1ZXVlOiAoKSA9PiB7XG4gICAgICAgIGNhbGxzKys7XG4gICAgICAgIHRocm93IG5ldyBFcnJvcihcIm11c3Qgbm90IGVucXVldWVcIik7XG4gICAgICB9LFxuICAgIH0pKShyZXF1ZXN0KHsgYm9keTogXCJ4XCIucmVwZWF0KDE3MDAwKSB9KSkpLnN0YXR1cyxcbiAgICA0MTMsXG4gICk7XG4gIGFzc2VydEVxdWFscyhjYWxscywgMCk7XG59KTtcbkRlbm8udGVzdChcImRpc3BhdGNoIHdha2V1cCBlbmZvcmNlcyBzaWduYWwgYW5kIHJlZGlyZWN0OmVycm9yIGFuZCByZWplY3RzIHJlZGlyZWN0cy9zZXJ2ZXIgZXJyb3JzXCIsIGFzeW5jICgpID0+IHtcbiAgZm9yIChjb25zdCBzdGF0dXMgb2YgWzIwMCwgMzAyLCA1MDBdKSB7XG4gICAgbGV0IGNhbGxzID0gMDtcbiAgICBjb25zdCBzaWduYWwgPSBBYm9ydFNpZ25hbC50aW1lb3V0KDEwMDApO1xuICAgIGNvbnN0IGFjY2VwdGVkID0gYXdhaXQgcmVxdWVzdERpc3BhdGNoKFxuICAgICAgXCJodHRwczovL2NvbGxlY3Quc3VwYWJhc2UuY29cIixcbiAgICAgIFwic3ludGhldGljLWFwaS1rZXlcIixcbiAgICAgIFwic3ludGhldGljLXNlY3JldFwiLFxuICAgICAgc2lnbmFsLFxuICAgICAgKF91cmwsIGluaXQpID0+IHtcbiAgICAgICAgY2FsbHMrKztcbiAgICAgICAgYXNzZXJ0RXF1YWxzKGluaXQ/LnJlZGlyZWN0LCBcImVycm9yXCIpO1xuICAgICAgICBhc3NlcnRFcXVhbHMoaW5pdD8uc2lnbmFsLCBzaWduYWwpO1xuICAgICAgICByZXR1cm4gUHJvbWlzZS5yZXNvbHZlKG5ldyBSZXNwb25zZShcIlwiLCB7IHN0YXR1cyB9KSk7XG4gICAgICB9LFxuICAgICk7XG4gICAgYXNzZXJ0RXF1YWxzKGFjY2VwdGVkLCBzdGF0dXMgPT09IDIwMCk7XG4gICAgYXNzZXJ0RXF1YWxzKGNhbGxzLCAxKTtcbiAgfVxufSk7XG5EZW5vLnRlc3QoXCJ3YWtldXAgcmVmdXNlcyBpbnNlY3VyZS9jcmVkZW50aWFsZWQgZGVzdGluYXRpb25zIHdpdGhvdXQgZm9yd2FyZGluZyBzZWNyZXRzXCIsIGFzeW5jICgpID0+IHtcbiAgbGV0IGNhbGxzID0gMDtcbiAgZm9yIChcbiAgICBjb25zdCB1cmwgb2YgW1xuICAgICAgXCJodHRwOi8vY29sbGVjdC5zdXBhYmFzZS5jb1wiLFxuICAgICAgXCJodHRwczovL3VzZXI6cGFzc0Bjb2xsZWN0LnN1cGFiYXNlLmNvXCIsXG4gICAgICBcIm5vdC11cmxcIixcbiAgICBdXG4gICkge1xuICAgIGFzc2VydEVxdWFscyhcbiAgICAgIGF3YWl0IHJlcXVlc3REaXNwYXRjaChcbiAgICAgICAgdXJsLFxuICAgICAgICBcInN5bnRoZXRpYy1hcGkta2V5XCIsXG4gICAgICAgIFwic3ludGhldGljLXNlY3JldFwiLFxuICAgICAgICBBYm9ydFNpZ25hbC50aW1lb3V0KDEwMDApLFxuICAgICAgICAoKSA9PiB7XG4gICAgICAgICAgY2FsbHMrKztcbiAgICAgICAgICB0aHJvdyBuZXcgRXJyb3IoXCJubyBmZXRjaFwiKTtcbiAgICAgICAgfSxcbiAgICAgICksXG4gICAgICBmYWxzZSxcbiAgICApO1xuICB9XG4gIGFzc2VydEVxdWFscyhjYWxscywgMCk7XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFlBQVksUUFBUSw0QkFBNEI7QUFDekQsU0FDRSx5QkFBeUIsRUFFekIsZUFBZSxRQUNWLGVBQWU7QUFFdEIsTUFBTSxPQUFPO0FBQ2IsTUFBTSxRQUFRO0FBQ2QsU0FBUyxRQUFRLFlBQVksQ0FBQyxDQUFDLEVBQUUsTUFBb0I7RUFDbkQsT0FBTyxJQUFJLFFBQVEscUNBQXFDO0lBQ3RELFFBQVE7SUFDUjtJQUNBLFNBQVM7TUFBRSxnQkFBZ0I7SUFBbUI7SUFDOUMsTUFBTSxLQUFLLFNBQVMsQ0FBQztNQUNuQixTQUFTO01BQ1QsTUFBTTtNQUNOLE9BQU87TUFDUCxNQUFNO01BQ04sR0FBRyxTQUFTO0lBQ2Q7RUFDRjtBQUNGO0FBQ0EsU0FBUyxhQUNQLFlBQStDLENBQUMsQ0FBQztFQUVqRCxPQUFPO0lBQ0wsV0FBVyxLQUFPO0lBQ2xCLFNBQVMsSUFBTSxRQUFRLE9BQU8sQ0FBQztRQUFFLE1BQU07UUFBTyxPQUFPO01BQUs7SUFDMUQsVUFBVSxJQUFNLFFBQVEsT0FBTyxDQUFDO0lBQ2hDLFdBQVc7SUFDWCxHQUFHLFNBQVM7RUFDZDtBQUNGO0FBQ0EsS0FBSyxJQUFJLENBQUMsd0VBQXdFO0VBQ2hGLElBQUksV0FBVztFQUNmLElBQUk7RUFDSixNQUFNLFNBQVMsMEJBQTBCLGFBQWE7SUFDcEQsU0FBUyxDQUFDLE9BQU8sU0FBUztNQUN4QjtNQUNBLGFBQWEsT0FBTyxPQUFPLEVBQUU7TUFDN0IsT0FBTyxRQUFRLE9BQU8sQ0FBQztRQUFFLE1BQU07UUFBTyxPQUFPO01BQUs7SUFDcEQ7SUFDQSxVQUFVLENBQUM7TUFDVCxhQUFhO01BQ2IsT0FBTyxJQUFJLFFBQVEsS0FBTztJQUM1QjtFQUNGO0VBQ0EsTUFBTSxXQUFXLE1BQU0sT0FBTztFQUM5QixhQUFhLFNBQVMsTUFBTSxFQUFFO0VBQzlCLGFBQWEsTUFBTSxTQUFTLElBQUksSUFBSTtJQUNsQyxJQUFJO0lBQ0osU0FBUztJQUNULHVCQUF1QjtJQUN2QixvQkFBb0I7RUFDdEI7RUFDQSxhQUFhLFVBQVU7RUFDdkIsYUFBYSxZQUFZLFNBQVM7QUFDcEM7QUFDQSxLQUFLLElBQUksQ0FBQyw0RUFBNEU7RUFDcEYsSUFBSSxXQUFXO0VBQ2YsSUFBSSxRQUFRO0VBQ1osSUFBSTtFQUNKLE1BQU0sV0FBVyxNQUFNLDBCQUNyQixhQUFhO0lBQ1gsU0FBUyxDQUFDLElBQUksSUFBSTtNQUNoQjtNQUNBLFNBQVM7TUFDVCxPQUFPLElBQUksUUFBUSxLQUFPO0lBQzVCO0lBQ0EsVUFBVTtNQUNSO01BQ0EsT0FBTyxRQUFRLE9BQU8sQ0FBQztJQUN6QjtFQUNGLElBQ0E7RUFDRixhQUFhLFNBQVMsTUFBTSxFQUFFO0VBQzlCLGFBQWEsTUFBTSxTQUFTLElBQUksSUFBSTtJQUFFLE9BQU87RUFBc0I7RUFDbkUsYUFBYSxVQUFVO0VBQ3ZCLGFBQWEsT0FBTztFQUNwQixhQUFhLFFBQVEsU0FBUztBQUNoQztBQUNBLEtBQUssSUFBSSxDQUFDLDZGQUE2RjtFQUNyRyxJQUFJLE9BQU87RUFDWCxJQUFJLFFBQVE7RUFDWixNQUFNLFdBQVcsTUFBTSwwQkFBMEIsYUFBYTtJQUM1RCxTQUFTLENBQUMsR0FBRztNQUNYLE9BQU87TUFDUCxhQUFhLEVBQUUsU0FBUyxFQUFFO1FBQUUsUUFBUTtNQUFLO01BQ3pDLE9BQU8sUUFBUSxPQUFPLENBQUM7UUFBRSxNQUFNO1FBQU0sT0FBTztNQUFLO0lBQ25EO0lBQ0EsVUFBVTtNQUNSO01BQ0EsT0FBTyxRQUFRLE9BQU8sQ0FBQztJQUN6QjtFQUNGLElBQUksUUFBUTtJQUFFLGNBQWM7SUFBZ0IsU0FBUztNQUFFLFFBQVE7SUFBSztFQUFFO0VBQ3RFLGFBQWEsTUFBTTtFQUNuQixhQUFhLENBQUMsTUFBTSxTQUFTLElBQUksRUFBRSxFQUFFLE9BQU8sRUFBRTtFQUM5QyxhQUFhLE9BQU87QUFDdEI7QUFDQSxLQUFLLElBQUksQ0FBQyxtRkFBbUY7RUFDM0YsTUFBTSxhQUFhLElBQUk7RUFDdkIsSUFBSSxVQUFVO0VBQ2QsTUFBTSxXQUFXLE1BQU0sMEJBQ3JCLGFBQWE7SUFDWCxTQUFTO01BQ1AsV0FBVyxLQUFLO01BQ2hCLE9BQU8sUUFBUSxPQUFPLENBQUM7UUFBRSxNQUFNO1FBQU8sT0FBTztNQUFLO0lBQ3BEO0lBQ0EsVUFBVTtNQUNSO01BQ0EsT0FBTyxRQUFRLE9BQU8sQ0FBQztJQUN6QjtFQUNGLElBQ0EsUUFBUSxDQUFDLEdBQUcsV0FBVyxNQUFNO0VBQy9CLGlGQUFpRjtFQUNqRixhQUFhO0lBQUM7SUFBSztHQUFJLENBQUMsUUFBUSxDQUFDLFNBQVMsTUFBTSxHQUFHO0VBQ25ELGFBQWEsU0FBUztBQUN4QjtBQUNBLEtBQUssSUFBSSxDQUFDLDBEQUEwRDtFQUNsRSxJQUFJLFlBQVk7RUFDaEIsSUFBSSxXQUFXO0VBQ2YsTUFBTSxPQUFPLElBQUksZUFBMkI7SUFDMUM7TUFDRSxZQUFZO0lBQ2Q7RUFDRjtFQUNBLE1BQU0sV0FBVyxNQUFNLDBCQUNyQixhQUFhO0lBQ1gsU0FBUztNQUNQO01BQ0EsT0FBTyxRQUFRLE9BQU8sQ0FBQztRQUFFLE1BQU07UUFBTyxPQUFPO01BQUs7SUFDcEQ7RUFDRixJQUVBLElBQUksUUFBUSx3QkFBd0I7SUFDbEMsUUFBUTtJQUNSLFNBQVM7TUFBRSxnQkFBZ0I7SUFBbUI7SUFDOUM7RUFDRjtFQUVGLGFBQWEsU0FBUyxNQUFNLEVBQUU7RUFDOUIsYUFBYSxXQUFXO0VBQ3hCLGFBQWEsVUFBVTtBQUN6QjtBQUNBLEtBQUssSUFBSSxDQUFDLG1EQUFtRDtFQUMzRCxJQUFJLFFBQVE7RUFDWixNQUFNLFVBQVUsMEJBQTBCLGFBQWE7SUFDckQsV0FBVztNQUNULE1BQU0sSUFBSSxNQUFNO0lBQ2xCO0lBQ0EsU0FBUztNQUNQO01BQ0EsTUFBTSxJQUFJLE1BQU07SUFDbEI7RUFDRjtFQUNBLGFBQWEsQ0FBQyxNQUFNLFFBQVEsVUFBVSxFQUFFLE1BQU0sRUFBRTtFQUNoRCxhQUNFLENBQUMsTUFBTSwwQkFBMEIsYUFBYTtJQUM1QyxTQUFTO01BQ1A7TUFDQSxNQUFNLElBQUksTUFBTTtJQUNsQjtFQUNGLElBQUksUUFBUTtJQUFFLE1BQU0sSUFBSSxNQUFNLENBQUM7RUFBTyxHQUFHLEVBQUUsTUFBTSxFQUNqRDtFQUVGLGFBQWEsT0FBTztBQUN0QjtBQUNBLEtBQUssSUFBSSxDQUFDLDBGQUEwRjtFQUNsRyxLQUFLLE1BQU0sVUFBVTtJQUFDO0lBQUs7SUFBSztHQUFJLENBQUU7SUFDcEMsSUFBSSxRQUFRO0lBQ1osTUFBTSxTQUFTLFlBQVksT0FBTyxDQUFDO0lBQ25DLE1BQU0sV0FBVyxNQUFNLGdCQUNyQiwrQkFDQSxxQkFDQSxvQkFDQSxRQUNBLENBQUMsTUFBTTtNQUNMO01BQ0EsYUFBYSxNQUFNLFVBQVU7TUFDN0IsYUFBYSxNQUFNLFFBQVE7TUFDM0IsT0FBTyxRQUFRLE9BQU8sQ0FBQyxJQUFJLFNBQVMsSUFBSTtRQUFFO01BQU87SUFDbkQ7SUFFRixhQUFhLFVBQVUsV0FBVztJQUNsQyxhQUFhLE9BQU87RUFDdEI7QUFDRjtBQUNBLEtBQUssSUFBSSxDQUFDLGdGQUFnRjtFQUN4RixJQUFJLFFBQVE7RUFDWixLQUNFLE1BQU0sT0FBTztJQUNYO0lBQ0E7SUFDQTtHQUNELENBQ0Q7SUFDQSxhQUNFLE1BQU0sZ0JBQ0osS0FDQSxxQkFDQSxvQkFDQSxZQUFZLE9BQU8sQ0FBQyxPQUNwQjtNQUNFO01BQ0EsTUFBTSxJQUFJLE1BQU07SUFDbEIsSUFFRjtFQUVKO0VBQ0EsYUFBYSxPQUFPO0FBQ3RCIn0=
// denoCacheMetadata=13123186157887014228,14015887848346446204