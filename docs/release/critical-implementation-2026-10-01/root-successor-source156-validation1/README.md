# Fresh current156 canonical Edge/Linux validation

Exactly one fresh canonical aggregate passed in 42.7633 seconds using the current
156-file backend source closure. Actual observations were 92 type inputs; 34 unit
files, 668 tests and 32 steps; 109 HTTP checks; 32 Linux decoder cases; 14 Linux
integration tests; 212 Linux regressions; and six dependency-security tests.
Ignored, failed and skipped counts were zero where reported by the relevant test
runner. The runner-contract phase also passed.

The canonical runner was unchanged at SHA-256
`3f209fb9e308eaeb4d623a094ed8caad8dd0cc8dd6b2f8f0df4f41068ae425f2`.
The existing reviewed private supervisor at SHA-256
`9a04dddb060ada8b333cdfd8582e8c4f045b0f4b5baf681d333bd56b082d55b5`
was copied and minimally adapted in this new packet. Its four declared changes
are the current156 label, verification of a populated private completed Deno
cache, removal of the optional `--cache-dependencies` argument, and failure on
held maintained-source drift. The original whole-run 1200-second, build
300-second and Linux-phase 600-second bounds remain unchanged.
`supervisor-review.json` records every exact adaptation.

The current source closure equals the original154 closure plus
`handler_test_fixture.ts` and `ai_dispatch_policy_test.ts`. The only changed
original files were `Makefile`, `handler_test.ts` and
`scripts/tests/verify_roster_decoder.py`. Production handlers and locks remained
byte-identical to the original154 snapshot. The private source copy, actual
canonical source-before/source-after receipts, independently read private source,
and held maintained source all agree across all 156 files. Dart and browser fixes
being integrated by root are outside this backend closure.

The original completed frozen Deno cache was copied to an exclusive private
directory: 367 regular files and 12,432,732 bytes. This run makes no initially
empty cache claim and performs no optional dependency-cache acquisition phase.
The original cache remained unchanged. The private cache added 92 generated
local-file JavaScript entries and changed 12 local analysis/cache SQLite files;
its before/after manifest is retained. No download lines appeared in the captured
logs. All six wheels, six publisher metadata files and the whole publisher receipt
were copied from the original 13 offline inputs, hash-verified and unchanged
before/after. Publisher receipt SHA-256 is
`58ba030a43beab73906753486051c6a3499a00a70bfa1c9e018a0fb4554cfa74`.

Deno 2.5.6, fixture Python 3.12.14 and its six pinned package versions, the
supervisor Python 3.12.14, Docker and Ruby match the recorded original runtime
hashes before and after. The local Unix Docker endpoint and native Linux ARM64
daemon were observed. The pinned Python base image digest is
`392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e`.
The decoder image was freshly built with `--network=none --no-cache`; its six
dependency-security cases ran with network none. The unchanged canonical decoder
supervisor publishes its actual HTTP port only on `127.0.0.1`, then exercises
seccomp network, memory, CPU and parent-credential denial. Its Docker run itself
does not request `--network none`; this packet does not claim that absent flag.

The new image was
`sha256:508ff7d9b8e7e4976436f628005d0e05fc08eaae45df293056856815039607e8`,
with the sole owned tag `collect_roster_decoder_e671020e0d91:qa`. The canonical
supervisor container is absent and no owned processes remain. Image cleanup
verified the exact ID and sole tag, an empty container listing for that ID,
successful removal and its exact subsequent absence diagnostic. No shared image,
base image, container or global Docker cache was pruned.

`canonical-output/` is a byte- and mode-verified copy of all 513 actual canonical
output files, including complete logs, validation receipts, source snapshots,
malformed fixture outputs and the offline build context. The exclusive private
source, input and cache roots remain at
`/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/root-successor-source156-validation1-private`
for review. `canonical-output-index.json` binds the original and captured copies.
`result.json`, `independent-current-readback.json`, the source/cache/input/runtime
fences and `cleanup-receipt.json` provide the completion evidence.

This attempt changed no maintained source, APP, SDK, original packets, original
offline inputs or original completed Deno cache. It did not rerun current209 SQL
or the unchanged39 Linux-admission suite. It proves the bound canonical backend
aggregate only. The original BE10 SQL-wiring criterion remains separate and open
in this packet; root and the CI worker own that criterion. No hosted provider,
database/customer, deployment, device, visual or production-release acceptance is
claimed.
