# Native Supabase Edge Runtime qualification

## Result

The exact `supabase/edge-runtime:v1.77.4` binary (embedded Deno 2.1.4) passed all 11 checks in the final `native-edge-current25-result.json`. It loaded the frozen application handlers and connected through the real, restricted `collect_edge` login to a newly cloned, task-owned PostgreSQL 17 current25 fixture on loopback 55445. `integration-current25-result.json` separately records all 25 reviewed migrations installing under the normal owner, the original 16 exact bytes, identity binding and actual restricted logins. The final application graph hash is `d10db9adc4f550d1516b89125ed4e4564f3ee8f175f00a1ed460e44e324ceb93`.

The final receipt pins 159 application/migration inputs, the qualification runner/router/environment inputs, its generated main entrypoint, and 772 files belonging to the actual cached `postgres@3.4.7`, `nodemailer@10.1.7` and `hono@4.13.13` dependencies. Before/after comparisons proved these inputs unchanged. No application handler, dependency import, financial authority or production router mount was replaced with a test implementation. The earlier current24 success, `native-edge-qualified-result.json`, remains unchanged with its original 157-input graph and ten-check scope.

| Check | Actual observation |
| --- | --- |
| Closed router | An unknown function returned 404. |
| Native FCM identity projection | Before the native main began serving, exact `environment.mjs` assertions proved that the `OPENSMS_FCM_*` triple maps only to the SMS device worker, that the member FCM project/service-account values remain separate, and that the other five workers receive no device identity. Only synthetic canary values were used. |
| Member health, Functions prefix | `/functions/v1/collect-api/health` returned 200, `database: available`, and the exact bound source hash after the real SQL query. |
| Member health, direct prefix | `/collect-api/health` returned the same actual database health result. |
| Admin public health | `/functions/v1/admin-api/health` returned 404; no public shortcut was introduced. |
| Admin protected health | `/functions/v1/admin-api/api/admin/oversight/health` returned 401 with `unauthenticated` after normal environment, database identity and application admission checks. The authenticated health query was not executed. |
| Main jobs | A POST without the scheduler token returned 401. |
| Email jobs | A POST without its separate scheduler token returned 401. |
| SMS gateway disabled | The loaded gateway returned 503 with `gateway_unavailable`, distinct from router boot failure. |
| Unsigned SMS hook | The configured signed hook returned 401 before database admission or provider dispatch. |
| Retained SQL admission evidence | Exactly two member and one Admin admission were added. All three settled with the exact source hash, zero external dispatches and zero uncertain dispatches. No job, gateway or hook admission was added. |

This is native runtime integration evidence. It does not assert a running Docker stack, GoTrue/Storage/Realtime service acceptance, authenticated Admin health, authorized scheduler drains, enabled gateway delivery, signed SMS delivery, external providers, public DNS, deployment or production readiness. The fixture's managed Auth interface remains synthetic. Database TLS was qualified separately with the same underlying driver; this loopback fixture uses the existing explicit `test` SQL adapter mode.

## Reproduction and safeguards

Use the exact binary, a fresh private output directory, a new safe result filename, the private descriptor from the complete-current qualification, and the already verified dependency cache:

```sh
COLLECT_CI_SYNTHETIC=true node scripts/supabase/testing/self-hosted-edge-runtime.mjs \
  /absolute/path/to/edge-runtime \
  /absolute/path/to/private-current25-runtime-descriptor.json \
  /absolute/path/to/fresh-private-attempt \
  /absolute/path/to/new-safe-result.json \
  /absolute/path/to/deno-cache
```

The runner refuses a different binary digest, crossed application/profile identity, a nonqualification descriptor, a different database host/port/login, an occupied Edge port, existing output files, or source/dependency changes during execution. It starts only its own native Edge process on 127.0.0.1:9000 and stops only that child. It never starts, stops or alters a PostgreSQL service. The owner connection reads admission evidence only. Application requests create their own normal immutable admission/closure records.

The qualification entrypoint copies the exact production router and environment module bytes next to its own main entrypoint. It injects the repository source path in place of production's fixed `/home/deno/collect` mount. It also supplies `APP_ENVIRONMENT=test` for the explicit loopback SQL fixture and `APP_ENVIRONMENT=qualification` for the signed hook, which requires the real deployment profile environment. Production `index.ts`, router logic and environment filtering remain unchanged. No signed hook request was sent.

The HTTP listener uses the production internal port 9000 so the existing fixed internal-origin normalization is exercised. Caller forwarding headers are not used to establish authority. Private environment files and native logs remain outside the repository; the receipt contains no URLs with credentials, tokens, keys or session material.

## Preserved failed attempts

The initial `native-edge-result.json` remains unchanged. The successful receipt has a different filename. Additional failed attempt receipts remain under the review workspace, with private logs outside the repository.

1. The first main entrypoint used an absolute import outside the native main service graph. The qualification runner now places the exact router/environment modules adjacent to the entrypoint, matching production adjacency.
2. The initial wrapper passed the promise returned by `Deno.readTextFile` directly to `JSON.parse`. The qualification wrapper now awaits it.
3. An empty private npm cache required registry DNS unavailable in this environment. The runner now copies only the three exact already cached runtime package versions and records their complete bytes.
4. Port 9177 was outside the permitted internal transport origins, so Admin correctly returned 403. The runner now uses the available production internal port 9000; Admin protection is unchanged.
5. The synthetic hook settings used the SQL fixture's `test` environment alias and a token without the required `app_` prefix. The runner now supplies the hook's existing valid qualification configuration; the hook itself was not relaxed.
6. The corrected run passed all 10 checks, including actual SQL readback of settled admissions.

Final current25 Edge receipt SHA256: `25ce8364ad5cc0dd65893b3574e2f309b4cfcf466f3e9cbc27d469bd000d47fc`.

Final current25 migration integration receipt SHA256: `0127f65554ff89a2dd3ee3e340318713faba21523f4c0bae7f23f2f20af90066`.

Preserved current24 Edge receipt SHA256: `5fdd6632a23057a43381db9e4473dd3bb13172585247a0f79add5a7d052cd07c`. Its old runner SHA256 remains recorded in that receipt; it is not relabeled as the final runner.

Native binary SHA256: `7883510fe308b4b5c49ec0a8e2020ec81c5fa41133239f3969a372b1cbf107ba`.
