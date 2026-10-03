import { validateWorkerLookup, validateWorkerReceipt } from "./handler.ts";
// Actual SQL outputs, selected explicitly by the source-bound UAT runner.
const directory = Deno.args[0];
Deno.test("actual SQL worker and lookup fixtures satisfy strict Edge projection", async () => {
  if (!directory) throw Error("observed_fixture_directory_required");
  const executed = JSON.parse(
    await Deno.readTextFile(`${directory}/observed-worker-executed.json`),
  );
  const found = JSON.parse(
    await Deno.readTextFile(`${directory}/observed-worker-lookup.json`),
  );
  const missing = JSON.parse(
    await Deno.readTextFile(`${directory}/observed-worker-expired-lookup.json`),
  );
  validateWorkerReceipt(executed.receipt, executed.request_id);
  validateWorkerLookup(found, found.request_id, Date.parse(found.checked_at));
  validateWorkerLookup(
    missing,
    missing.request_id,
    Date.parse(missing.checked_at),
  );
});
