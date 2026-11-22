import assert from "node:assert/strict";
import test from "node:test";
import { readMemberHistory } from "../domain/member_history.js";

test("both member history contracts validate sort values before querying", async () => {
  const env = {
    DB: { prepare: () => assert.fail("Invalid history requests must not reach PostgreSQL") },
  };
  for (const version of [1, 2]) {
    for (const p_sort of ["toString", "unknown", ["newest"], 1]) {
      await assert.rejects(
        readMemberHistory({ p_contract_version: version, p_sort }, env, {}),
        { status: 400, code: "invalid_sort" },
      );
    }
  }
});
