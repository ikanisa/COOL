# Scheduler local full recovery — frozen private handoff

Five owned files are listed with exact source and original canonical hashes in
PROMOTION_MAP.json. Canonical inputs remained unchanged during implementation.
Root alone reviews/promotes them; the other private workspace files are frozen
transitive proof inputs, not proposed changes.

The actual operating CLI now supports:

```
node --experimental-strip-types src/unattended_schedule_cli.ts export --deployment /absolute/prepared --bundle /absolute/new-bundle
node --experimental-strip-types src/unattended_schedule_cli.ts restore --bundle /absolute/bundle --target /absolute/new-recovery
node --experimental-strip-types src/unattended_schedule_cli.ts inspect --target /absolute/recovery
node --experimental-strip-types src/unattended_schedule_cli.ts inspect --target /absolute/recovery --request-id ORIGINAL-UUID
```

`unattended:recovery` is a package script for the same CLI. Output/target paths
must be new, disjoint, under an owner-private parent and have no symlink
ancestors. Import keeps every mapped journal/control/diagnostic store inactive.
An interrupted target is preserved for inspection; retry uses a new target.

The bounded bundle includes all original hot/cold evidence plus inert exact
configuration. It preserves UUIDs, signed digests, original lookup aliases,
history hashes, unknown records and graph anomalies. Source hot records remain
hot at the source; imported copies use retained storage with tier provenance
in the immutable bundle. It neither prunes the source nor restores runtime,
credentials, executable scripts or operational authority. Inspection works
after original profile/configuration/runtime paths are removed.

Before/after complete hot inventories and directory/cold-head identities must
match, and each captured hot record matches its initial bytes/path identity.
Declared runtime hashes and complete module/dependency/link inventories are
checked. Chained pages and final seal enforce order/counts/hashes; conflicting
copies and missing/extra/reordered pages refuse completion. There is no writer
lock or claim to include publications occurring after the final source check.

The accepted deployment seam returns a distinct inert configuration type and
shares exact artifact generation plus retention-policy/runtime/dependency layout
checks with the active loader. The active loader
retains current UID, path, runtime and helper checks. Existing preparations pin
the old runtime bytes; promotion requires new explicit preparation before a
later active deployment can use changed runtime. Recovery never activates it.

proof-final-02/result.json records a typecheck and 101 passing cases: 26 recovery
cases plus 75 existing scheduler-control cases. Both source/dependency input
drift and original canonical baseline drift are empty. The source/runtime/
dependency capture SHA is
567c016121e2c41706892a4d1b1f737f1ed4778ab82f02568a88cc189bacbea6.
The final command includes 9 forged matching-artifact layout rejections and
14 credential-key spellings/public metadata checks, real CLI round-trip, process-killed import,
original-path removal, unknown/alias/history preservation, drift, corruption,
inactive mid-flight gates and zero signer/HTTP/owner/daemon authority.

All failed and intermediate proofs remain in this staging directory; see
FAILED_PROOFS.md. This proves the private local recovery slice. Root's canonical
promotion, final integration freeze and whole-goal acceptance remain separate.

The 99-case predecessor and its five exact source files remain in proof-final-01
and predecessor-99. Promotion must preserve existing target modes, particularly
package.json; PROMOTION_MAP.json records them. Credential field screening
recognizes normalized common names and does not classify arbitrary strings.
