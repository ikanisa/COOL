# Local scheduler full recovery — private proposal

Owner: worker_history_map_oct02. Root alone promotes canonical files.

The actual scheduler CLI gains `export --deployment ABS --bundle ABS`,
`restore --bundle ABS --target ABS`, and `inspect --target ABS`.
These branches only read or write local evidence. They never load credentials,
sign, call HTTP, invoke launchctl, execute restored scripts, or enable work.

Export captures exact hot and cold journal, control and diagnostic records plus
the original profile, PREPARATION.json, runtime.sha256, tick.sh and job plist.
Configuration is inert evidence with its original absolute paths and hashes.
Runtime binaries, helper bytes, dependency files and signing material are not
copied. Their source hashes and dependency links are verified and frozen.

The versioned private bundle contains an immutable context, chained numbered
pages, and a final seal binding context, all page hashes/counts and source
snapshot. Pages have at most 64 records / 4 MiB; each record is at most 64 KiB.
Hot inventories are limited to 65,536 records per store; at most 65,536 pages
are admitted. Exceeding a bound refuses completion and retains failed evidence.
Store/tier/name ordering, exact-byte hashes, canonical JSON and conflicting
hot/cold copies are checked. Before/after inventories, directory identities,
configuration identities and cold roots must match. Concurrent source changes
refuse the seal; there is no claim of a cooperative writer lock.
Every captured hot byte hash and path identity must match its initial inventory;
new unpinned runtime modules/dependency links also refuse export. The observed
snapshot does not include publications after its final source check.

Restore requires a fresh private target. It first writes an exclusive import
intent and durably marks every mapped target store inactive, then imports all
evidence through existing retained storage. Original hot/cold provenance stays
in the bundle. All imported records remain readable under their original names;
original UUIDs, graph links and signed envelope digests are never rewritten.
No ordinary active publication bypass is added. Incomplete imports remain
inactive; only a complete, ordered, exact sealed bundle receives a completion
record. Missing pages, duplicates, digest conflicts or source drift fail closed.
Recovery inspection uses the immutable context and explicit mapped stores, not
an edited live profile or a relocated executable prepared deployment.

Read-only configuration validation seam proposed for root review:
`unattended_deployment.ts` will export a pure validator of captured manifest,
profile and artifacts against their ORIGINAL deployment directory. It reuses
the existing manifest and exact artifact generation rules; historical UID is
validated as metadata rather than active authority. The active loader retains
its current UID/path/runtime checks. No other shared validator is needed:
journal.readOriginal, validHistoryPlan/Closure, validOperation and diagnostic
validators already expose read-only consumers. Graph anomalies stay preserved
and are reported as unresolved/integrity-required, never repaired automatically.
Captured and active configuration share the same pure retention-policy and
runtime/dependency layout checks before exact artifact comparison. Credential
field screening normalizes common key names; it does not classify arbitrary
secret strings. Public key hashes and tags remain admissible metadata.

Proof: real Python preparation + real CLI export/restore/inspect; mixed hot
unknown, armed and lookup aliases, cold completed evidence, history and control;
source drift and same-root mutation; missing/reordered/conflicting pages;
interrupted inactive import; original names/hashes and no authority recreation.
Private source/runtime/dependency freeze and all failed proof outputs retained.
