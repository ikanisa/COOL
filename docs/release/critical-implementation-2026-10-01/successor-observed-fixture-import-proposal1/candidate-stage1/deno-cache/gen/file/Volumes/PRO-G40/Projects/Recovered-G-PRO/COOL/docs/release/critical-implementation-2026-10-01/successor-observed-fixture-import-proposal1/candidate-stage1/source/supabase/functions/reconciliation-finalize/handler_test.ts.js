import { reconciliationHandler } from "./handler.ts";
const reviewId = "99890000-0000-4000-8000-000000000011";
const paymentId = "99890000-0000-4000-8000-000000000021";
const success = {
  review_id: reviewId,
  payment_id: paymentId,
  payment_status: "posted",
  replayed: false,
  evidence_level: "independently_reconciled"
};
function assert(ok, message) {
  if (!ok) throw new Error(message);
}
function request(body = {
  review_id: reviewId
}, auth = true) {
  return new Request("https://example.invalid/reconciliation-finalize", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...auth ? {
        authorization: "Bearer synthetic-user-jwt"
      } : {}
    },
    body: JSON.stringify(body)
  });
}
function fixture(auth = {
  data: true,
  error: null
}, finalized = {
  data: success,
  error: null
}) {
  const calls = [];
  return {
    calls,
    handler: reconciliationHandler({
      authorize: async (authorization, id)=>{
        assert(authorization === "Bearer synthetic-user-jwt", "wrong bearer");
        assert(id === reviewId, "wrong review");
        calls.push("authorize");
        return auth;
      },
      finalize: async (id)=>{
        assert(id === reviewId, "wrong finalization UUID");
        calls.push("finalize");
        return finalized;
      }
    })
  };
}
Deno.test("only the authorized review UUID reaches the service finalizer", async ()=>{
  const f = fixture();
  const response = await f.handler(request());
  assert(response.status === 200, "not successful");
  assert(f.calls.join() === "authorize,finalize", "wrong call order");
  assert(JSON.stringify(await response.json()) === JSON.stringify(success), "wrong bounded output");
  assert(response.headers.get("cache-control") === "no-store", "cacheable response");
});
Deno.test("replay reports an already reversed payment truthfully", async ()=>{
  const data = {
    ...success,
    replayed: true,
    payment_status: "reversed"
  };
  const f = fixture(undefined, {
    data,
    error: null
  });
  const response = await f.handler(request());
  assert(response.status === 200 && (await response.json()).payment_status === "reversed", "reversal hidden");
});
for (const [label, body] of [
  [
    "missing review",
    {}
  ],
  [
    "null review",
    {
      review_id: null
    }
  ],
  [
    "malformed review",
    {
      review_id: "wrong"
    }
  ],
  [
    "unapproved payment fields",
    {
      review_id: reviewId,
      amount_rwf: 2500
    }
  ],
  [
    "oversized payload",
    {
      review_id: "x".repeat(2200)
    }
  ]
]){
  Deno.test(`rejects ${label} before authorization or posting`, async ()=>{
    const f = fixture();
    const response = await f.handler(request(body));
    assert(response.status >= 400 && response.status < 500, "invalid body accepted");
    assert(f.calls.length === 0, "invalid request reached backend");
  });
}
Deno.test("missing credentials do not reach backend", async ()=>{
  const f = fixture();
  assert((await f.handler(request(undefined, false))).status === 401, "missing auth accepted");
  assert(f.calls.length === 0, "missing auth reached backend");
});
for (const [code, status] of [
  [
    "42501",
    403
  ],
  [
    "PGRST301",
    401
  ],
  [
    "22023",
    409
  ],
  [
    "XX000",
    503
  ]
]){
  Deno.test(`authorization ${code} blocks posting and returns stable error`, async ()=>{
    const f = fixture({
      data: null,
      error: {
        code
      }
    });
    const response = await f.handler(request());
    assert(response.status === status, "wrong stable status");
    assert(f.calls.join() === "authorize", "unauthorized posting attempted");
    assert(!(await response.text()).includes(code), "database code leaked");
  });
}
Deno.test("false authorization is denied", async ()=>{
  const f = fixture({
    data: false,
    error: null
  });
  assert((await f.handler(request())).status === 403, "false permission accepted");
  assert(f.calls.join() === "authorize", "false permission posted");
});
Deno.test("revocation between authorization and finalization fails closed", async ()=>{
  const f = fixture(undefined, {
    data: null,
    error: {
      code: "42501"
    }
  });
  const response = await f.handler(request());
  assert(response.status === 403, "revocation ignored");
  assert(f.calls.join() === "authorize,finalize", "server recheck not reached");
});
for (const data of [
  {
    ...success,
    review_id: paymentId
  },
  {
    ...success,
    payment_id: "bad"
  },
  {
    ...success,
    replayed: "false"
  },
  {
    ...success,
    payment_status: "review"
  }
]){
  Deno.test(`rejects malformed service result ${JSON.stringify(data)}`, async ()=>{
    const f = fixture(undefined, {
      data,
      error: null
    });
    assert((await f.handler(request())).status === 503, "malformed success accepted");
  });
}
Deno.test("service outage details are not exposed", async ()=>{
  const handler = reconciliationHandler({
    authorize: async ()=>({
        data: true,
        error: null
      }),
    finalize: async ()=>{
      throw new Error("secret provider credential SQL detail");
    }
  });
  const response = await handler(request());
  assert(response.status === 503 && !(await response.text()).includes("secret"), "private error leaked");
});
Deno.test("method/preflight handling never posts", async ()=>{
  const f = fixture();
  assert((await f.handler(new Request("https://example.invalid"))).status === 405, "GET permitted");
  assert((await f.handler(new Request("https://example.invalid", {
    method: "OPTIONS"
  }))).status === 200, "preflight failed");
  assert(f.calls.length === 0, "non-POST posted");
});
Deno.test("step-up requirement has an explicit stable error", async ()=>{
  const f = fixture({
    data: null,
    error: {
      code: "42501",
      message: "reconciliation_step_up_required"
    }
  });
  const response = await f.handler(request());
  assert(response.status === 403 && (await response.json()).error === "reconciliation_step_up_required", "step-up hidden");
  assert(f.calls.join() === "authorize", "step-up bypassed");
});
Deno.test("unknown permission detail is not echoed", async ()=>{
  const f = fixture({
    data: null,
    error: {
      code: "42501",
      message: "secret private identity"
    }
  });
  const response = await f.handler(request());
  assert(!(await response.text()).includes("secret"), "permission detail leaked");
});
for (const data of [
  null,
  [],
  {
    ...success,
    payment_status: "reversed"
  }
]){
  Deno.test(`invalid finalizer object ${JSON.stringify(data)} is unavailable`, async ()=>{
    const f = fixture(undefined, {
      data,
      error: null
    });
    assert((await f.handler(request())).status === 503, "invalid server output accepted");
  });
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3JlY29uY2lsaWF0aW9uLWZpbmFsaXplL2hhbmRsZXJfdGVzdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyByZWNvbmNpbGlhdGlvbkhhbmRsZXIsIHR5cGUgUnBjUmVzdWx0IH0gZnJvbSBcIi4vaGFuZGxlci50c1wiO1xuXG5jb25zdCByZXZpZXdJZCA9IFwiOTk4OTAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDExXCI7XG5jb25zdCBwYXltZW50SWQgPSBcIjk5ODkwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAyMVwiO1xuY29uc3Qgc3VjY2VzcyA9IHtcbiAgcmV2aWV3X2lkOiByZXZpZXdJZCxcbiAgcGF5bWVudF9pZDogcGF5bWVudElkLFxuICBwYXltZW50X3N0YXR1czogXCJwb3N0ZWRcIixcbiAgcmVwbGF5ZWQ6IGZhbHNlLFxuICBldmlkZW5jZV9sZXZlbDogXCJpbmRlcGVuZGVudGx5X3JlY29uY2lsZWRcIixcbn07XG5mdW5jdGlvbiBhc3NlcnQob2s6IHVua25vd24sIG1lc3NhZ2U6IHN0cmluZykge1xuICBpZiAoIW9rKSB0aHJvdyBuZXcgRXJyb3IobWVzc2FnZSk7XG59XG5mdW5jdGlvbiByZXF1ZXN0KGJvZHk6IHVua25vd24gPSB7IHJldmlld19pZDogcmV2aWV3SWQgfSwgYXV0aCA9IHRydWUpIHtcbiAgcmV0dXJuIG5ldyBSZXF1ZXN0KFwiaHR0cHM6Ly9leGFtcGxlLmludmFsaWQvcmVjb25jaWxpYXRpb24tZmluYWxpemVcIiwge1xuICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgaGVhZGVyczoge1xuICAgICAgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICAuLi4oYXV0aCA/IHsgYXV0aG9yaXphdGlvbjogXCJCZWFyZXIgc3ludGhldGljLXVzZXItand0XCIgfSA6IHt9KSxcbiAgICB9LFxuICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KGJvZHkpLFxuICB9KTtcbn1cbmZ1bmN0aW9uIGZpeHR1cmUoXG4gIGF1dGg6IFJwY1Jlc3VsdCA9IHsgZGF0YTogdHJ1ZSwgZXJyb3I6IG51bGwgfSxcbiAgZmluYWxpemVkOiBScGNSZXN1bHQgPSB7IGRhdGE6IHN1Y2Nlc3MsIGVycm9yOiBudWxsIH0sXG4pIHtcbiAgY29uc3QgY2FsbHM6IHN0cmluZ1tdID0gW107XG4gIHJldHVybiB7XG4gICAgY2FsbHMsXG4gICAgaGFuZGxlcjogcmVjb25jaWxpYXRpb25IYW5kbGVyKHtcbiAgICAgIGF1dGhvcml6ZTogYXN5bmMgKGF1dGhvcml6YXRpb24sIGlkKSA9PiB7XG4gICAgICAgIGFzc2VydChhdXRob3JpemF0aW9uID09PSBcIkJlYXJlciBzeW50aGV0aWMtdXNlci1qd3RcIiwgXCJ3cm9uZyBiZWFyZXJcIik7XG4gICAgICAgIGFzc2VydChpZCA9PT0gcmV2aWV3SWQsIFwid3JvbmcgcmV2aWV3XCIpO1xuICAgICAgICBjYWxscy5wdXNoKFwiYXV0aG9yaXplXCIpO1xuICAgICAgICByZXR1cm4gYXV0aDtcbiAgICAgIH0sXG4gICAgICBmaW5hbGl6ZTogYXN5bmMgKGlkKSA9PiB7XG4gICAgICAgIGFzc2VydChpZCA9PT0gcmV2aWV3SWQsIFwid3JvbmcgZmluYWxpemF0aW9uIFVVSURcIik7XG4gICAgICAgIGNhbGxzLnB1c2goXCJmaW5hbGl6ZVwiKTtcbiAgICAgICAgcmV0dXJuIGZpbmFsaXplZDtcbiAgICAgIH0sXG4gICAgfSksXG4gIH07XG59XG5EZW5vLnRlc3QoXCJvbmx5IHRoZSBhdXRob3JpemVkIHJldmlldyBVVUlEIHJlYWNoZXMgdGhlIHNlcnZpY2UgZmluYWxpemVyXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBmLmhhbmRsZXIocmVxdWVzdCgpKTtcbiAgYXNzZXJ0KHJlc3BvbnNlLnN0YXR1cyA9PT0gMjAwLCBcIm5vdCBzdWNjZXNzZnVsXCIpO1xuICBhc3NlcnQoZi5jYWxscy5qb2luKCkgPT09IFwiYXV0aG9yaXplLGZpbmFsaXplXCIsIFwid3JvbmcgY2FsbCBvcmRlclwiKTtcbiAgYXNzZXJ0KFxuICAgIEpTT04uc3RyaW5naWZ5KGF3YWl0IHJlc3BvbnNlLmpzb24oKSkgPT09IEpTT04uc3RyaW5naWZ5KHN1Y2Nlc3MpLFxuICAgIFwid3JvbmcgYm91bmRlZCBvdXRwdXRcIixcbiAgKTtcbiAgYXNzZXJ0KFxuICAgIHJlc3BvbnNlLmhlYWRlcnMuZ2V0KFwiY2FjaGUtY29udHJvbFwiKSA9PT0gXCJuby1zdG9yZVwiLFxuICAgIFwiY2FjaGVhYmxlIHJlc3BvbnNlXCIsXG4gICk7XG59KTtcbkRlbm8udGVzdChcInJlcGxheSByZXBvcnRzIGFuIGFscmVhZHkgcmV2ZXJzZWQgcGF5bWVudCB0cnV0aGZ1bGx5XCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZGF0YSA9IHsgLi4uc3VjY2VzcywgcmVwbGF5ZWQ6IHRydWUsIHBheW1lbnRfc3RhdHVzOiBcInJldmVyc2VkXCIgfTtcbiAgY29uc3QgZiA9IGZpeHR1cmUodW5kZWZpbmVkLCB7IGRhdGEsIGVycm9yOiBudWxsIH0pO1xuICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGYuaGFuZGxlcihyZXF1ZXN0KCkpO1xuICBhc3NlcnQoXG4gICAgcmVzcG9uc2Uuc3RhdHVzID09PSAyMDAgJiZcbiAgICAgIChhd2FpdCByZXNwb25zZS5qc29uKCkpLnBheW1lbnRfc3RhdHVzID09PSBcInJldmVyc2VkXCIsXG4gICAgXCJyZXZlcnNhbCBoaWRkZW5cIixcbiAgKTtcbn0pO1xuZm9yIChcbiAgY29uc3QgW2xhYmVsLCBib2R5XSBvZiBbXG4gICAgW1wibWlzc2luZyByZXZpZXdcIiwge31dLFxuICAgIFtcIm51bGwgcmV2aWV3XCIsIHsgcmV2aWV3X2lkOiBudWxsIH1dLFxuICAgIFtcIm1hbGZvcm1lZCByZXZpZXdcIiwgeyByZXZpZXdfaWQ6IFwid3JvbmdcIiB9XSxcbiAgICBbXCJ1bmFwcHJvdmVkIHBheW1lbnQgZmllbGRzXCIsIHsgcmV2aWV3X2lkOiByZXZpZXdJZCwgYW1vdW50X3J3ZjogMjUwMCB9XSxcbiAgICBbXCJvdmVyc2l6ZWQgcGF5bG9hZFwiLCB7IHJldmlld19pZDogXCJ4XCIucmVwZWF0KDIyMDApIH1dLFxuICBdIGFzIGNvbnN0XG4pIHtcbiAgRGVuby50ZXN0KGByZWplY3RzICR7bGFiZWx9IGJlZm9yZSBhdXRob3JpemF0aW9uIG9yIHBvc3RpbmdgLCBhc3luYyAoKSA9PiB7XG4gICAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGYuaGFuZGxlcihyZXF1ZXN0KGJvZHkpKTtcbiAgICBhc3NlcnQoXG4gICAgICByZXNwb25zZS5zdGF0dXMgPj0gNDAwICYmIHJlc3BvbnNlLnN0YXR1cyA8IDUwMCxcbiAgICAgIFwiaW52YWxpZCBib2R5IGFjY2VwdGVkXCIsXG4gICAgKTtcbiAgICBhc3NlcnQoZi5jYWxscy5sZW5ndGggPT09IDAsIFwiaW52YWxpZCByZXF1ZXN0IHJlYWNoZWQgYmFja2VuZFwiKTtcbiAgfSk7XG59XG5EZW5vLnRlc3QoXCJtaXNzaW5nIGNyZWRlbnRpYWxzIGRvIG5vdCByZWFjaCBiYWNrZW5kXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoKTtcbiAgYXNzZXJ0KFxuICAgIChhd2FpdCBmLmhhbmRsZXIocmVxdWVzdCh1bmRlZmluZWQsIGZhbHNlKSkpLnN0YXR1cyA9PT0gNDAxLFxuICAgIFwibWlzc2luZyBhdXRoIGFjY2VwdGVkXCIsXG4gICk7XG4gIGFzc2VydChmLmNhbGxzLmxlbmd0aCA9PT0gMCwgXCJtaXNzaW5nIGF1dGggcmVhY2hlZCBiYWNrZW5kXCIpO1xufSk7XG5mb3IgKFxuICBjb25zdCBbY29kZSwgc3RhdHVzXSBvZiBbW1wiNDI1MDFcIiwgNDAzXSwgW1wiUEdSU1QzMDFcIiwgNDAxXSwgW1wiMjIwMjNcIiwgNDA5XSwgW1xuICAgIFwiWFgwMDBcIixcbiAgICA1MDMsXG4gIF1dIGFzIGNvbnN0XG4pIHtcbiAgRGVuby50ZXN0KGBhdXRob3JpemF0aW9uICR7Y29kZX0gYmxvY2tzIHBvc3RpbmcgYW5kIHJldHVybnMgc3RhYmxlIGVycm9yYCwgYXN5bmMgKCkgPT4ge1xuICAgIGNvbnN0IGYgPSBmaXh0dXJlKHsgZGF0YTogbnVsbCwgZXJyb3I6IHsgY29kZSB9IH0pO1xuICAgIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKHJlcXVlc3QoKSk7XG4gICAgYXNzZXJ0KHJlc3BvbnNlLnN0YXR1cyA9PT0gc3RhdHVzLCBcIndyb25nIHN0YWJsZSBzdGF0dXNcIik7XG4gICAgYXNzZXJ0KGYuY2FsbHMuam9pbigpID09PSBcImF1dGhvcml6ZVwiLCBcInVuYXV0aG9yaXplZCBwb3N0aW5nIGF0dGVtcHRlZFwiKTtcbiAgICBhc3NlcnQoIShhd2FpdCByZXNwb25zZS50ZXh0KCkpLmluY2x1ZGVzKGNvZGUpLCBcImRhdGFiYXNlIGNvZGUgbGVha2VkXCIpO1xuICB9KTtcbn1cbkRlbm8udGVzdChcImZhbHNlIGF1dGhvcml6YXRpb24gaXMgZGVuaWVkXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUoeyBkYXRhOiBmYWxzZSwgZXJyb3I6IG51bGwgfSk7XG4gIGFzc2VydChcbiAgICAoYXdhaXQgZi5oYW5kbGVyKHJlcXVlc3QoKSkpLnN0YXR1cyA9PT0gNDAzLFxuICAgIFwiZmFsc2UgcGVybWlzc2lvbiBhY2NlcHRlZFwiLFxuICApO1xuICBhc3NlcnQoZi5jYWxscy5qb2luKCkgPT09IFwiYXV0aG9yaXplXCIsIFwiZmFsc2UgcGVybWlzc2lvbiBwb3N0ZWRcIik7XG59KTtcbkRlbm8udGVzdChcInJldm9jYXRpb24gYmV0d2VlbiBhdXRob3JpemF0aW9uIGFuZCBmaW5hbGl6YXRpb24gZmFpbHMgY2xvc2VkXCIsIGFzeW5jICgpID0+IHtcbiAgY29uc3QgZiA9IGZpeHR1cmUodW5kZWZpbmVkLCB7IGRhdGE6IG51bGwsIGVycm9yOiB7IGNvZGU6IFwiNDI1MDFcIiB9IH0pO1xuICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGYuaGFuZGxlcihyZXF1ZXN0KCkpO1xuICBhc3NlcnQocmVzcG9uc2Uuc3RhdHVzID09PSA0MDMsIFwicmV2b2NhdGlvbiBpZ25vcmVkXCIpO1xuICBhc3NlcnQoZi5jYWxscy5qb2luKCkgPT09IFwiYXV0aG9yaXplLGZpbmFsaXplXCIsIFwic2VydmVyIHJlY2hlY2sgbm90IHJlYWNoZWRcIik7XG59KTtcbmZvciAoXG4gIGNvbnN0IGRhdGEgb2YgW1xuICAgIHsgLi4uc3VjY2VzcywgcmV2aWV3X2lkOiBwYXltZW50SWQgfSxcbiAgICB7IC4uLnN1Y2Nlc3MsIHBheW1lbnRfaWQ6IFwiYmFkXCIgfSxcbiAgICB7IC4uLnN1Y2Nlc3MsIHJlcGxheWVkOiBcImZhbHNlXCIgfSxcbiAgICB7IC4uLnN1Y2Nlc3MsIHBheW1lbnRfc3RhdHVzOiBcInJldmlld1wiIH0sXG4gIF1cbikge1xuICBEZW5vLnRlc3QoYHJlamVjdHMgbWFsZm9ybWVkIHNlcnZpY2UgcmVzdWx0ICR7SlNPTi5zdHJpbmdpZnkoZGF0YSl9YCwgYXN5bmMgKCkgPT4ge1xuICAgIGNvbnN0IGYgPSBmaXh0dXJlKHVuZGVmaW5lZCwgeyBkYXRhLCBlcnJvcjogbnVsbCB9KTtcbiAgICBhc3NlcnQoXG4gICAgICAoYXdhaXQgZi5oYW5kbGVyKHJlcXVlc3QoKSkpLnN0YXR1cyA9PT0gNTAzLFxuICAgICAgXCJtYWxmb3JtZWQgc3VjY2VzcyBhY2NlcHRlZFwiLFxuICAgICk7XG4gIH0pO1xufVxuRGVuby50ZXN0KFwic2VydmljZSBvdXRhZ2UgZGV0YWlscyBhcmUgbm90IGV4cG9zZWRcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBoYW5kbGVyID0gcmVjb25jaWxpYXRpb25IYW5kbGVyKHtcbiAgICBhdXRob3JpemU6IGFzeW5jICgpID0+ICh7IGRhdGE6IHRydWUsIGVycm9yOiBudWxsIH0pLFxuICAgIGZpbmFsaXplOiBhc3luYyAoKSA9PiB7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoXCJzZWNyZXQgcHJvdmlkZXIgY3JlZGVudGlhbCBTUUwgZGV0YWlsXCIpO1xuICAgIH0sXG4gIH0pO1xuICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGhhbmRsZXIocmVxdWVzdCgpKTtcbiAgYXNzZXJ0KFxuICAgIHJlc3BvbnNlLnN0YXR1cyA9PT0gNTAzICYmICEoYXdhaXQgcmVzcG9uc2UudGV4dCgpKS5pbmNsdWRlcyhcInNlY3JldFwiKSxcbiAgICBcInByaXZhdGUgZXJyb3IgbGVha2VkXCIsXG4gICk7XG59KTtcbkRlbm8udGVzdChcIm1ldGhvZC9wcmVmbGlnaHQgaGFuZGxpbmcgbmV2ZXIgcG9zdHNcIiwgYXN5bmMgKCkgPT4ge1xuICBjb25zdCBmID0gZml4dHVyZSgpO1xuICBhc3NlcnQoXG4gICAgKGF3YWl0IGYuaGFuZGxlcihuZXcgUmVxdWVzdChcImh0dHBzOi8vZXhhbXBsZS5pbnZhbGlkXCIpKSkuc3RhdHVzID09PSA0MDUsXG4gICAgXCJHRVQgcGVybWl0dGVkXCIsXG4gICk7XG4gIGFzc2VydChcbiAgICAoYXdhaXQgZi5oYW5kbGVyKFxuICAgICAgbmV3IFJlcXVlc3QoXCJodHRwczovL2V4YW1wbGUuaW52YWxpZFwiLCB7IG1ldGhvZDogXCJPUFRJT05TXCIgfSksXG4gICAgKSkuc3RhdHVzID09PSAyMDAsXG4gICAgXCJwcmVmbGlnaHQgZmFpbGVkXCIsXG4gICk7XG4gIGFzc2VydChmLmNhbGxzLmxlbmd0aCA9PT0gMCwgXCJub24tUE9TVCBwb3N0ZWRcIik7XG59KTtcbkRlbm8udGVzdChcInN0ZXAtdXAgcmVxdWlyZW1lbnQgaGFzIGFuIGV4cGxpY2l0IHN0YWJsZSBlcnJvclwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBmaXh0dXJlKHtcbiAgICBkYXRhOiBudWxsLFxuICAgIGVycm9yOiB7IGNvZGU6IFwiNDI1MDFcIiwgbWVzc2FnZTogXCJyZWNvbmNpbGlhdGlvbl9zdGVwX3VwX3JlcXVpcmVkXCIgfSxcbiAgfSk7XG4gIGNvbnN0IHJlc3BvbnNlID0gYXdhaXQgZi5oYW5kbGVyKHJlcXVlc3QoKSk7XG4gIGFzc2VydChcbiAgICByZXNwb25zZS5zdGF0dXMgPT09IDQwMyAmJlxuICAgICAgKGF3YWl0IHJlc3BvbnNlLmpzb24oKSkuZXJyb3IgPT09IFwicmVjb25jaWxpYXRpb25fc3RlcF91cF9yZXF1aXJlZFwiLFxuICAgIFwic3RlcC11cCBoaWRkZW5cIixcbiAgKTtcbiAgYXNzZXJ0KGYuY2FsbHMuam9pbigpID09PSBcImF1dGhvcml6ZVwiLCBcInN0ZXAtdXAgYnlwYXNzZWRcIik7XG59KTtcbkRlbm8udGVzdChcInVua25vd24gcGVybWlzc2lvbiBkZXRhaWwgaXMgbm90IGVjaG9lZFwiLCBhc3luYyAoKSA9PiB7XG4gIGNvbnN0IGYgPSBmaXh0dXJlKHtcbiAgICBkYXRhOiBudWxsLFxuICAgIGVycm9yOiB7IGNvZGU6IFwiNDI1MDFcIiwgbWVzc2FnZTogXCJzZWNyZXQgcHJpdmF0ZSBpZGVudGl0eVwiIH0sXG4gIH0pO1xuICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGYuaGFuZGxlcihyZXF1ZXN0KCkpO1xuICBhc3NlcnQoXG4gICAgIShhd2FpdCByZXNwb25zZS50ZXh0KCkpLmluY2x1ZGVzKFwic2VjcmV0XCIpLFxuICAgIFwicGVybWlzc2lvbiBkZXRhaWwgbGVha2VkXCIsXG4gICk7XG59KTtcbmZvciAoY29uc3QgZGF0YSBvZiBbbnVsbCwgW10sIHsgLi4uc3VjY2VzcywgcGF5bWVudF9zdGF0dXM6IFwicmV2ZXJzZWRcIiB9XSkge1xuICBEZW5vLnRlc3QoYGludmFsaWQgZmluYWxpemVyIG9iamVjdCAke0pTT04uc3RyaW5naWZ5KGRhdGEpfSBpcyB1bmF2YWlsYWJsZWAsIGFzeW5jICgpID0+IHtcbiAgICBjb25zdCBmID0gZml4dHVyZSh1bmRlZmluZWQsIHsgZGF0YSwgZXJyb3I6IG51bGwgfSk7XG4gICAgYXNzZXJ0KFxuICAgICAgKGF3YWl0IGYuaGFuZGxlcihyZXF1ZXN0KCkpKS5zdGF0dXMgPT09IDUwMyxcbiAgICAgIFwiaW52YWxpZCBzZXJ2ZXIgb3V0cHV0IGFjY2VwdGVkXCIsXG4gICAgKTtcbiAgfSk7XG59XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxxQkFBcUIsUUFBd0IsZUFBZTtBQUVyRSxNQUFNLFdBQVc7QUFDakIsTUFBTSxZQUFZO0FBQ2xCLE1BQU0sVUFBVTtFQUNkLFdBQVc7RUFDWCxZQUFZO0VBQ1osZ0JBQWdCO0VBQ2hCLFVBQVU7RUFDVixnQkFBZ0I7QUFDbEI7QUFDQSxTQUFTLE9BQU8sRUFBVyxFQUFFLE9BQWU7RUFDMUMsSUFBSSxDQUFDLElBQUksTUFBTSxJQUFJLE1BQU07QUFDM0I7QUFDQSxTQUFTLFFBQVEsT0FBZ0I7RUFBRSxXQUFXO0FBQVMsQ0FBQyxFQUFFLE9BQU8sSUFBSTtFQUNuRSxPQUFPLElBQUksUUFBUSxtREFBbUQ7SUFDcEUsUUFBUTtJQUNSLFNBQVM7TUFDUCxnQkFBZ0I7TUFDaEIsR0FBSSxPQUFPO1FBQUUsZUFBZTtNQUE0QixJQUFJLENBQUMsQ0FBQztJQUNoRTtJQUNBLE1BQU0sS0FBSyxTQUFTLENBQUM7RUFDdkI7QUFDRjtBQUNBLFNBQVMsUUFDUCxPQUFrQjtFQUFFLE1BQU07RUFBTSxPQUFPO0FBQUssQ0FBQyxFQUM3QyxZQUF1QjtFQUFFLE1BQU07RUFBUyxPQUFPO0FBQUssQ0FBQztFQUVyRCxNQUFNLFFBQWtCLEVBQUU7RUFDMUIsT0FBTztJQUNMO0lBQ0EsU0FBUyxzQkFBc0I7TUFDN0IsV0FBVyxPQUFPLGVBQWU7UUFDL0IsT0FBTyxrQkFBa0IsNkJBQTZCO1FB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
// denoCacheMetadata=17909289240414231439,1289641242307978790