import { assertEquals } from "./test_assert.ts";
import { notificationOperatorCommand } from "./notification_operator.ts";

const operator = "95000000-0000-4000-8000-000000000001";
const job = "95000000-0000-4000-8000-000000000002";
const claim = "95000000-0000-4000-8000-000000000003";

Deno.test("health and pending list expose only read commands", () => {
  const health = notificationOperatorCommand("health", {}, operator);
  assertEquals(health.permission, "notifications.read");
  assertEquals(health.sensitive, false);
  assertEquals(health.rpc, "collect_notification_health");
  const list = notificationOperatorCommand(
    "list_pending",
    { limit: 12 },
    operator,
  );
  assertEquals(list.params.p_limit, 12);
  assertEquals(list.sensitive, false);
});

Deno.test("claimed receipt is the only sensitive read", () => {
  const command = notificationOperatorCommand("get_claimed", {
    job_id: job,
    claim_token: claim,
    fence_version: 2,
  }, operator);
  assertEquals(command.rpc, "collect_get_claimed_receipt");
  assertEquals(command.sensitive, true);
  assertEquals(command.params.p_fence_version, 2);
});

Deno.test("confirmation requires an explicit current user confirmation", () => {
  let rejected = false;
  try {
    notificationOperatorCommand("confirm", {
      job_id: job,
      claim_token: claim,
      fence_version: 1,
      destination_revision: 1,
      body_sha256: "a".repeat(64),
      confirmation_id: "95000000-0000-4000-8000-000000000004",
    }, operator);
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
});

Deno.test("operator action names cannot become arbitrary RPC calls", () => {
  let rejected = false;
  try {
    notificationOperatorCommand("execute_sql", { sql: "select 1" }, operator);
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
});

Deno.test("heartbeat retains only an aggregate queue-checked flag", () => {
  const command = notificationOperatorCommand("heartbeat", {
    worker_id: "collect-mac-mini",
    run_id: "95000000-0000-4000-8000-000000000005",
    mode: "no_send",
    queue_checked: true,
    phone: "+250788000000",
  }, operator);
  assertEquals(command.params.p_safe_status, { queue_checked: true });
});
