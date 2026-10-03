# Collect hosted parity readback — 2 October 2026

Fresh hosted read access was refused. The existing Supabase connector call
`mcp__codex_apps__supabase_get_project({id: "lhbowpbcpwoiparwnwgt"})`
started at 07:48:22 UTC and returned at 07:48:23 UTC with `isError=true`,
structured code `INVALID_ARGUMENT` and the actual protocol message
`MCP error -32600: You do not have permission to perform this action`.
The refusal is retained in `exact-project-call.json`; its cause is unknown.
No further hosted call, project-list fallback, permission retry, token refresh,
SQL query, public endpoint probe, deployment or download was attempted.

The target comes from the existing regular `supabase/.temp/project-ref` file
and the retained metadata's exact project `id`/`ref`, all
`lhbowpbcpwoiparwnwgt`. The local `supabase/config.toml` value `project_id =
"collect"` names the local project and does not identify a hosted project.
The dated metadata records the project as `COOL` in `us-east-2`.
No other project was selected. Existing connector declarations for project,
migration, Edge metadata and SQL reads are retained in
`connector-discovery.json`; only the exact-project metadata call ran.

The current local inventory has 209 ordered unique migration IDs and 13
active function entries. Source entrypoint, configuration, deployment
manifest and readiness probe names agree. The actual maintained local
`/usr/bin/ruby scripts/edge_function_inventory.rb auth-check` returned
exit 0 in 0.089 seconds under a clean UTF-8 environment and a 15-second
deadline. This checks local source/JWT/auth wiring. No HTTP probe or
handler, scheduler, database, sign-in or provider workflow ran.

The hosted comparison below uses the retained 30 September 2026 metadata
and its README, whose hashes and input paths are recorded. The precise
original observation timestamp is not supplied. These are dated observations,
not a fresh hosted inventory:

- Its 124 migration IDs exactly prefix the current 209 IDs; 85 current source
  IDs are absent from that retained inventory and no retained IDs fall outside
  the current source. This does not establish today's pending migration count.
- Three common IDs have different registry/source names:
  `202605230012`: `admin_user_receiver_management` versus current `admin_rpc_grants`;
  `202605230013`: `admin_role_audit_actions` versus current `admin_settings_flags`;
  `202605230014`: `admin_new_rpc_privileges` versus current `admin_review_hardening`.
  Migration ID membership alone therefore does not establish full version/name
  equality or source/definition parity. No registry repair was performed.
- It lists 11 Edge functions. Five current entries were absent then:
  `collect-android-gateway`, `collect-receipt-exception-worker`,
  `collect-receipt-successor-gateway`, `collect-receipt-supervisor` and
  `reconciliation-finalize`.
- Three currently retired entries were present then: `ingest-bank-email`,
  `ingest-bank-sms` and `ingest-bank-statement`. The eight common function
  JWT modes agree with the current contract. That does not prove custom
  authentication, current deployed configuration or retirement today.
- Dated version, timestamp, status, entrypoint and `ezbr_sha256` metadata are
  retained using an explicit field whitelist. A hosted bundle digest and a
  local index-file digest identify different objects; no bundle/source hash
  equality is claimed. No bundle contents were fetched.
- Dated project database build metadata is retained. No current server version
  or target-bound read-only database observation was obtained, and no real
  approved PostgreSQL/toolchain manifest was created.

`inputs-before.json` and `inputs-after.json` bind 273 regular input files:
the 209 migrations, maintained non-test Edge source and the exact target,
manifest, deploy/readiness and retained-metadata inputs. Every complete recorded
identity stayed unchanged. Python and Ruby runtime identities also stayed
unchanged. `local-and-retained-inventory.json` contains the complete ordered IDs,
names, current function/index hashes, filtered dated metadata and exact deltas.
`observation-summary.json` separates static success, fresh permission refusal
and unknown current hosted parity. Raw credential values, keys, logs and
customer/Auth rows were neither requested nor copied into this packet.

BE-01 remains open: restore authorized exact-project read access, then bind the
frozen candidate to dated effective migration/function/configuration/catalog,
owner/search-path/grant/RLS evidence and the authorized denial/positive matrix.
BE-03 and ARC-03 remain open: prove the current 13 endpoint identities, custom
auth modes, immutable bundles, SQL dependencies, retirement, scheduler and
HTTP behavior in approved staging, followed by authorized production readback.
The original report criterion naming twelve endpoints remains unchanged;
the current maintained manifest now has thirteen. BE-10 remains open in its
hosted/CI/database integration scope; this readback does not extend the
separately retained local backend proof into hosted execution.

No finding, deployment, hosted workflow, outage, real toolchain approval or
production acceptance is inferred. Canonical registers were not edited.
The collector writes only this new private packet. Its existing-output refusal
preserves these receipts; a future observation belongs in a new successor.
