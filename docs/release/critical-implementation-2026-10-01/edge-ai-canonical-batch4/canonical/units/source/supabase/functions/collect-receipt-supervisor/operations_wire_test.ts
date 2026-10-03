import {
  type OperationAction,
  validateOperationPayload,
  validateOperationResult,
} from "./operations_contract.ts";
const fixture = new URL(
  "./fixtures/observed-operations-v2.json",
  import.meta.url,
);
Deno.test("seven actual SQL v2 action results satisfy the strict Edge contract", async () => {
  const rows = JSON.parse(await Deno.readTextFile(fixture));
  if (!Array.isArray(rows) || rows.length !== 7) {
    throw Error("actual_operations_fixture_missing");
  }
  for (const item of rows) {
    const { action, payload, result } = item;
    const original = action === "reconcile_request" ? result.receipt : result;
    if (
      !validateOperationPayload(action as OperationAction, payload) ||
      !validateOperationResult(
        result,
        original.principal_id,
        original.request_id,
        action as OperationAction,
        payload,
      )
    ) throw Error("actual_operations_wire_refused:" + action);
    if (
      JSON.stringify(result).includes("+250") ||
      Object.hasOwn(result, "message_body") ||
      Object.hasOwn(result, "destination")
    ) throw Error("private_operations_output");
  }
});
