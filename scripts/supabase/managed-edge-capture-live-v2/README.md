# Managed Edge response capture candidate

**Review candidate; no live request has been made.** This is a separate
successor to the frozen synthetic preparation. Do not run its managed path
until the exact source pins, plan, transport, credential handling and launcher
have been independently reviewed. The existing project and organization are
fixed; no deployment, database write, secret-list call or provider mutation is
implemented.

The reviewed plan binds an operation ID, archive and key directories, private
token-file path, source-pin digest and deadline. A clean Node launcher sends only
that plan and its digest to a bounded child. Before reading the token, the child
hashes the exact manifest-listed source files and Node binary and compares the
manifest to the supplied digest. The manifest also includes the launcher and
tests. This is a point-in-time check and assumes the operator actually starts
the reviewed launcher in a clean environment, with a trusted local user, OS,
Node startup, native libraries and directories. It is not protection against
another same-user or privileged process.

The child validates the provider project and reads metadata, an opaque response,
and metadata again for each of `collect-api`, `admin-api` and `collect-jobs`.
It compares the complete JSON metadata response bytes, including `verify_jwt`
and unknown fields; only a digest and a selected safe subset are retained.
Even harmless whitespace or field-order changes cause refusal. This is a
before/after comparison of what the metadata endpoint returned, not proof of
every provider setting, cross-function consistency or absence of an ABA
deployment between reads.

The candidate requests `multipart/form-data`, as in Supabase's
[function download implementation](https://github.com/supabase/cli/blob/develop/apps/cli/src/shared/functions/download.ts),
and requires a bounded structurally recognized multipart envelope with at least
one nonempty file part. Its bounded ASCII-header subset recognizes
`supabase-path`, UTF-8/US-ASCII `filename*`, quoted or unquoted `filename`,
and permits absent metadata; other valid MIME variants can still be refused.
The entire original response is
encrypted without extraction. A 200 JSON error, malformed envelope, compressed
response, redirect, oversized body or unsupported multipart form is refused.
These checks do not validate file semantics or prove the source is restorable.
The [Management API body documentation](https://supabase.com/docs/reference/api/v1-get-a-function-body)
does not specify the deployed project's actual response representation; it has
not been observed in this work, and a valid but unsupported form will be refused.
The provider's optional upload digest and the opaque response digest refer to
potentially different representations; any equality flag is informational only.

The encrypted archive binds project, operation, plan, selected function data,
full-response metadata digests, content type, and body digests. The archive and
the generated 32-byte key are written in separate owner-only directories with
exclusive creation and authenticated readback. This does not establish separate
or durable key custody. Receipt metadata and hashes are owner-only plaintext and
can reveal correlation; opaque bodies may contain sensitive literals. No source
or credential is intentionally written in plaintext, but process memory, swap,
crash dumps and pre-existing source files are outside that statement. Buffer
wiping is best effort, and Node strings cannot be reliably wiped.

Claims and outcomes are scoped to the selected archive directory, not global
across directories or hosts. A claim without a completed, independently verified
receipt is uncertain and never authorizes an automatic retry. The launcher
returns nonzero on refusal, interruption, timeout, missing acknowledgement or
unconfirmed stop; on SIGTERM/SIGINT it requests child cancellation then escalates
to SIGKILL. A watchdog pipe also asks the child to abort if the launcher dies.
Unexpected kernel stalls, uninterruptible work, a dead or compromised runtime,
escaped descendants, host failure and same-user interference remain outside
the proof; no global actor exclusion or cloud-session closure is claimed.

The same bounded launcher supports read-only `status` and `verify` actions
using the original plan and pin digests. `status` reads only claim and outcome
records; it does not inspect the archive or key and reports a completed record
as unverified. `verify` requires completed matching records, reads the separate
key, authenticates the archive, compares its digests and selected metadata to
the receipt, and structurally rechecks the multipart bodies in memory. Neither
action reads the provider token or contacts the provider. Missing, altered or
unconfirmed records do not authorize retry. Status deliberately exits nonzero
even for a completed-but-unverified record; verification exits zero only for an
authenticated point-in-time result. This is not proof of independent custody,
source semantics, restoration or redeployment. A different source-pin version
requires retaining and reviewing a compatible verifier rather than silently
substituting a new one for the original plan.

After independent review, a trusted operator would provide an exclusively
created private plan file and independently reviewed digests to the launcher:

```json
{
  "format": "collect.edge-capture.plan.v2",
  "scope": "managed",
  "operation_id": "<new-uuid>",
  "archive_dir": "/absolute/private/archive-directory",
  "key_dir": "/absolute/private/separate-key-directory",
  "token_path": "/absolute/private/provider-token-file",
  "source_pins_sha256": "<reviewed-manifest-sha256>",
  "deadline_ms": 900000,
  "fixture": null
}
```

The token file is read only in the capture worker and must be an owner-only
regular file. `planDigest` in `core.mjs` computes the canonical plan digest;
the JSON file's bytewise SHA-256 is not interchangeable with that digest.

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node \
  scripts/supabase/managed-edge-capture-live-v2/supervisor.mjs \
  ACTION PLAN_SHA256 SOURCE_PINS_SHA256 < /absolute/path/to/private-plan.json
```

`ACTION` is `capture`, `status`, or `verify`; this command has not been run
against the managed project. The plan contains paths and hashes only, not token
or key bytes. Keep the reviewed plan, exact source pins, archive, key and outcome
records under appropriate custody.

Synthetic tests use invented multipart bytes, private temporary files and a
mock transport. They do not prove the provider accepts the requested format or
that a managed capture, restore or deployment can succeed. Run from the
physical checkout with a clean environment:

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-edge-capture-live-v2/*.test.mjs
```
