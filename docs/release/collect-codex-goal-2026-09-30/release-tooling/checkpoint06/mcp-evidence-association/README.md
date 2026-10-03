# Source06 MCP evidence association

All 58 inputs from the retained supervisor-journal test packet and all 42 inputs
from checkpoint05's credential-free local MCP discovery match source06's
manifest and actual copied bytes. The two overlapping inventories are separate
scopes. Both original evidence manifests read back intact: 36 journal files and
39 checkpoint05 files. No existing packet was changed.

The retained source06 root is
`/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06`.
Its external manifest SHA-256 is
`3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f`.
The 1,905-file source export is an unapproved, non-atomic implementation
checkpoint. Source06 reported no capture-window source drift; this association
does not accept the current working tree or mark the source reviewed/frozen.

The earlier 139/139 synthetic bridge tests in 18 files and TypeScript check are
associated with the unchanged listed inputs. The earlier real local
initialize/tools-list result registered 16 tools and exposed schemas for exactly
five host-enabled reads. Its original discovery time remains September 30 at
23:50:44 UTC. Tests, TypeScript and MCP discovery were not rerun. The associated
schema fingerprint remains
`416ca58e679a9ce09d127569dec0cd8e29a2578afe6157b0a3e58194da1c78fa`.

The regression Node binary and compiler hashes match their earlier records;
all eight retained installed package-manifest hashes and versions also match.
Source06 records the same regression Node path and version. The host configuration
still enables exactly collect_list_pending_receipts, collect_notification_health,
get_collect_health, get_notification_status and list_notification_failures,
with the fixed local server invocation and 15/45-second deadlines.

The host uses the bundled cache Node binary, while the regression checks use
Development Node. Both currently report v24.19.0 and their binary hashes differ.
Prior discovery recorded the configured Node version, without its binary hash;
exact historical configured-binary equality cannot be attested. This is a
retained scope limitation, not evidence of a newly changed host binary. Full
installed dependency-file bytes were not rehashed; package manifests and the
compiler entrypoint are metadata checks. Source06 excludes node_modules.

association.json records every expected/manifest/readback hash, runtime and safe
host metadata, historical scope and limitations. association-run.log is actual
output from the read-only association command. No profile environment values
were reported or forwarded. No MCP process, tools/call, backend read, Auth or
Keychain call, installation mutation, live action, send or scheduling occurred.
Host runtime reload, current-user connection and deployed backend acceptance
remain unverified. Later SQL behavior outside the listed 58 inputs is not
covered by the retained mock/stdio/unit checks. No production approval is claimed.
