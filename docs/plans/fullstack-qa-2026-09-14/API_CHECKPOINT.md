# Collect HTTP authorization checkpoint

Latest continuation: [EDGE_CHECKPOINT.md](EDGE_CHECKPOINT.md) records schema
126, 94 PostgREST checks, 66 Edge HTTP checks and the OTP repair. The schema125
evidence below is retained as its historical checkpoint.

14 September 2026. **82 checks pass on the isolated current-schema HTTP target.**
The full-system goal remains active. This is real PostgREST request/response
evidence with synthetic JWTs and database sessions. It does not establish
GoTrue/OTP, hosted gateway, Edge, browser-to-backend, native, provider or visual
acceptance.

## Target and evidence

The new runner uses a disposable copy of the existing task-owned schema 125.
That schema still derives from 124 clean migrations and one bounded upgrade.
The cached PostgREST 16.1 image is pinned by its full image ID in the report;
no image was downloaded and hosted-version parity has not been established.

The API exposes only the configured `public` schema on the owned internal
network. Its root filesystem is read-only, capabilities are dropped, host
mounts and published ports are absent, and scheduled/network database
workers remain disabled. HTTP requests use curl inside the owned database
container. JWTs travel through stdin and are excluded from command arguments,
reports and source snapshots. The temporary credential file was removed.

[Docker's bridge documentation](https://docs.docker.com/engine/network/drivers/bridge/)
describes communication between containers on the same user-defined network.
The initial attempt requested a loopback host port, but runtime inspection
found no binding. The guard failed before HTTP testing; the revised transport
keeps all requests inside the existing network.

Raw evidence: `.cache/fullstack-qa/20260914T151002Z/api-continuation/`.

| Evidence | Result |
| --- | --- |
| `http-authorization/report.json` | 82 passing checks from 73 HTTP requests plus persisted/source assertions; statuses, parsed responses, runner/migration hashes and cleanup |
| `http-authorization/source-snapshots/` | Exact four Ruby sources used by that run |
| `http-authorization/seed-fixtures.sql` | Eight synthetic accounts with generated immutable IDs, approved operator, distinct sessions and public/private groups |
| `http-authorization/persisted-effects.sql` and `.log` | Independent database readback after HTTP mutations |
| `qa-tooling-final.json` and `.log` | 75 tests / 365 assertions across ten test files; zero failures, errors or skips; unchanged inputs |
| `admin-rpc-signatures.json` | Current catalog signatures and grants for the 22 mapped Admin primary RPCs plus country wrapper; execution coverage remains partial |
| `harness-attempts.json` | Four preserved setup/adapter failures and their cleanup evidence |
| `source-checkpoint.json` | Current HEAD, preserved settings hash, migration hashes and prior Flutter input comparison |
| `final-shutdown.json` and `pg-shutdown.log` | Original fixture stopped with container exit 0 and completed PostgreSQL shutdown; only `_supabase` and `postgres` remained |

## What passed

- A verified, approved operator reaches Admin. Forged metadata, absent,
  malformed and cross-user session IDs expose no Admin identity and cannot
  read protected account details. Invalid signatures, expired tokens,
  future not-before tokens and malformed JWTs are rejected by PostgREST.
- Anonymous and ordinary member requests cannot approve, revoke or activate
  Admin access. Browser operators cannot invoke the service bootstrap or
  retired role-mutation functions. Private approval tables, schemas and
  identity helpers are not available through the public API.
- Approval and activation return their exact receipts and tolerate retries.
  Activation does not revive a preapproval session. A separately inserted
  new synthetic session gains access while the old session remains denied.
  Revocation immediately denies the same unexpired new-session JWT and
  removes its active roles. This models session records; it is not a real
  sign-in or WhatsApp verification exercise.
- Both current and installed-client roster RPCs allow owners and active
  members for public and private groups. They reject outsiders, former and
  invited members, another group's owner, unrelated platform operators and
  anonymous callers. Current roster payloads omit direct account and phone
  identifiers. Linked/claimed feature-phone identities and contribution
  amount privacy retain their separate SQL evidence.
- Persisted readback finds exactly one approval audit after retry, no active
  candidate role after revocation, no role created by denied mutations and
  two distinct candidate sessions. Payments, ledger entries, raw SMS and
  notification outbox remain zero.

The older `assert_admin_permission` encodes its explicit permission denial
as `P0001` / HTTP 400. The runner accepts only that exact permission-message
form or `42501` with the corresponding 401/403 response. A parameter error,
missing RPC, generic 400 or unavailable record cannot count as an access
denial. Regressions enforce this distinction; no product permission was
changed to obtain a pass.

## Cleanup and remaining work

Every API attempt's container and created database copy was removed. The
first setup's automatic cleanup also failed its endpoint guard; an exact
container-ID/run-label follow-up verified and removed those resources.
Its failed report is retained alongside the successful cleanup record.
The original bootstrap database is unchanged and its volume is retained.
PostgreSQL then completed its own shutdown and the container exited 0. The
Docker exec client exited 137 when the container closed; the separate
container state and completed-shutdown log establish the database outcome.

Only QA scripts and the Makefile were changed in this continuation. Of the
615 inputs recorded for the prior 867-test Flutter run, 614 are unchanged;
the Makefile now registers the Ruby SQL and HTTP helper tests. No Dart,
Flutter test, asset or platform input changed. The earlier Flutter run is
not presented as a newly executed regression.

Remaining work includes all other Admin action/role/country outcomes,
browser-to-API integration, real Auth/session expiry flows, Edge HTTP
authentication and abuse tests, hosted-version/configuration drift, broader
financial concurrency, uninterrupted current replay and restore, installed
PWA/native execution, and required independent/owner visual acceptance.
former mobile visual acceptance rule remains mandatory and unresolved.
