import { assertEquals } from "./test_assert.ts";
import { notificationOperatorCommand } from "./notification_operator.ts";

const operator = "95000000-0000-4000-8000-000000000001";
const session = "95000000-0000-4000-8000-000000000099";
const job = "95000000-0000-4000-8000-000000000002";
const claim = "95000000-0000-4000-8000-000000000003";

Deno.test("health and pending list expose only read commands", () => {
  const health = notificationOperatorCommand("health", {}, operator, session);
  assertEquals(health.permission, "notifications.read");
  assertEquals(health.sensitive, false);
  assertEquals(health.rpc, "collect_notification_health_v2");
  const list = notificationOperatorCommand(
    "list_pending",
    { limit: 12 },
    operator,
    session,
  );
  assertEquals(list.params.p_limit, 12);
  assertEquals(list.sensitive, false);
});

Deno.test("claimed receipt is the only sensitive read", () => {
  const command = notificationOperatorCommand(
    "get_claimed",
    {
      job_id: job,
      claim_token: claim,
      fence_version: 2,
    },
    operator,
    session,
  );
  assertEquals(command.rpc, "collect_get_claimed_receipt_v2");
  assertEquals(command.sensitive, true);
  assertEquals(command.params.p_fence_version, 2);
});

Deno.test("confirmation requires an explicit current user confirmation", () => {
  let rejected = false;
  try {
    notificationOperatorCommand(
      "confirm",
      {
        job_id: job,
        claim_token: claim,
        fence_version: 1,
        destination_revision: 1,
        body_sha256: "a".repeat(64),
        confirmation_id: "95000000-0000-4000-8000-000000000004",
      },
      operator,
      session,
    );
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
});

Deno.test("operator action names cannot become arbitrary RPC calls", () => {
  let rejected = false;
  try {
    notificationOperatorCommand(
      "execute_sql",
      { sql: "select 1" },
      operator,
      session,
    );
  } catch {
    rejected = true;
  }
  assertEquals(rejected, true);
});

Deno.test("heartbeat retains only an aggregate queue-checked flag", () => {
  const command = notificationOperatorCommand(
    "heartbeat",
    {
      worker_id: "collect-mac-mini",
      run_id: "95000000-0000-4000-8000-000000000005",
      mode: "no_send",
      queue_checked: true,
      phone: "+250788000000",
    },
    operator,
    session,
  );
  assertEquals(command.params.p_safe_status, { queue_checked: true });
});

Deno.test("every action carries the verified actor and exact originating session", () => {
  const input = {
    job_id: job,
    claim_token: claim,
    fence_version: 1,
    request_id: claim,
    worker_id: "worker-1",
    destination_revision: 1,
    body_sha256: "a".repeat(64),
    confirmation_id: claim,
    user_confirmation: true,
    attempt_id: claim,
    outcome: "failed_no_send",
    evidence_reference: "synthetic-evidence",
    reason: "Synthetic safely unsent claim",
    run_id: claim,
    mode: "no_send",
    operator_user_id: job,
    operator_session_id: job,
    p_operator_user_id: job,
    p_operator_session_id: job,
  };
  const expected = {
    health: "collect_notification_health_v2",
    list_pending: "collect_list_pending_receipts_v2",
    claim: "collect_claim_receipt_v2",
    get_claimed: "collect_get_claimed_receipt_v2",
    confirm: "collect_confirm_receipt_v2",
    record_send_start: "collect_record_send_start_v2",
    record_outcome: "collect_record_observed_outcome_v2",
    release_claim: "collect_release_unsent_claim_v2",
    heartbeat: "collect_worker_heartbeat_v2",
  };
  for (const [action, rpc] of Object.entries(expected)) {
    const command = notificationOperatorCommand(
      action,
      input,
      operator,
      session,
    );
    assertEquals(command.rpc, rpc);
    assertEquals(command.params.p_operator_user_id, operator);
    assertEquals(command.params.p_operator_session_id, session);
  }
});

Deno.test("missing or malformed originating session cannot create a command", () => {
  for (const invalid of ["", "service-role", job + " "]) {
    let rejected = false;
    try {
      notificationOperatorCommand("health", {}, operator, invalid);
    } catch (error) {
      rejected = error instanceof Error &&
        error.message === "Authentication required";
    }
    assertEquals(rejected, true);
  }
});
