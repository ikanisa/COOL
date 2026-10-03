import assert from "node:assert/strict";
import test from "node:test";
import {healthyQueue, operatorFixture, runStdioPreflight} from "./testing/stdio_harness.ts";

test("stdio preflight verifies real initialize/health/list and outputs aggregates only", {timeout: 15_000}, async () => {
  const fixture = await operatorFixture((request, response) => response.end(JSON.stringify({ok: true,
    result: request.body.action === "health" ? healthyQueue : [{job_id: "private-fixture-job", destination_masked: "private-fixture-mask"}]})));
  try {
    const result = await runStdioPreflight(fixture.environment);
    assert.equal(result.code, 0);
    assert.equal(result.report.status, "PASS_AUTHENTICATED_STDIO_MCP");
    assert.equal(result.report.pending_page_count, 1);
    assert.deepEqual(fixture.requests.map(x => x.body), [{action: "health"}, {action: "list_pending", limit: 1}]);
    assert.doesNotMatch(result.stdout + result.stderr, /private-fixture|qa-operator-no-authority|qa-public-anon-no-authority/);
  } finally { await fixture.close(); }
});

test("stdio preflight rejects malformed queue counts before listing", {timeout: 20_000}, async () => {
  for (const health of [{enabled: false}, {...healthyQueue, queued: "1"}, {...healthyQueue, uncertain: -1}]) {
    const fixture = await operatorFixture((request, response) => response.end(JSON.stringify({ok: true, result: request.body.action === "health" ? health : []})));
    try {
      const result = await runStdioPreflight(fixture.environment);
      assert.equal(result.code, 2);
      assert.equal(result.report.status, "BLOCKED_STDIO_MCP");
      assert.deepEqual(fixture.requests.map(x => x.body.action), ["health"]);
      assert.equal(result.report.queue_mutations, 0);
      assert.equal(result.report.provider_sends, 0);
    } finally { await fixture.close(); }
  }
});

test("stdio preflight rejects an oversized page and authorization failure without exposing payloads", {timeout: 15_000}, async () => {
  for (const denied of [false, true]) {
    const fixture = await operatorFixture((request, response) => {
      if (denied) response.writeHead(403).end(JSON.stringify({error: "private-fixture-denial"}));
      else response.end(JSON.stringify({ok: true, result: request.body.action === "health" ? healthyQueue : [{job_id: "private-fixture-a"}, {job_id: "private-fixture-b"}]}));
    });
    try {
      const result = await runStdioPreflight(fixture.environment);
      assert.equal(result.code, 2);
      assert.equal(result.report.status, "BLOCKED_STDIO_MCP");
      assert.equal(fixture.requests.length, denied ? 1 : 2);
      assert.doesNotMatch(result.stdout + result.stderr, /private-fixture|qa-operator-no-authority/);
    } finally { await fixture.close(); }
  }
});
