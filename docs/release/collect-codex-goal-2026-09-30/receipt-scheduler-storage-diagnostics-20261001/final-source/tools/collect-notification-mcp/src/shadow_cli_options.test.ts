import assert from "node:assert/strict";
import test from "node:test";
import {parseShadowOptions} from "./shadow_cli_options.ts";
const id = "11111111-1111-4111-8111-111111111111";
test("manual shadow CLI requires one explicit mode and retained request ID", () => {
  assert.deepEqual(parseShadowOptions(["--once", "--request-id", id]), {mode: "once", requestId: id});
  assert.deepEqual(parseShadowOptions(["--request-id", id.toUpperCase(), "--status"]), {mode: "status", requestId: id});
});
test("missing, duplicate, conflicting, arbitrary and unsafe shadow args fail before any runtime work", () => {
  for (const args of [[], ["--once"], ["--status"], ["--request-id", id], ["--once", "--request-id"],
    ["--once", "--status", "--request-id", id], ["--once", "--once", "--request-id", id],
    ["--once", "--request-id", id, "--request-id", id], ["--once", "--request-id", "SECRET_BAD_INPUT"],
    ["--once", "--request-id", id, "--recipient", "+250788123456"], ["--once", "--request-id", id, "--loop"],
    ["--once", "--request-id", id, "--deadline", "900"], ["--once", "--request-id", id, "unexpected"],
    ["--once", "--request-id", "11111111-1111-0111-8111-11111111111"]]) {
    assert.throws(() => parseShadowOptions(args), /^Error: SHADOW_ARGUMENTS_INVALID$/);
  }
});
