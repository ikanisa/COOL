# Legacy Admin entry candidate

This directory is a **prepared source candidate**, not proof of a particular
published source identity. It targets only the existing `collect-admin` Worker.
The current API and `collect-platform-admin` Worker are independent release
parents; this source does not deploy either.

Historical evidence described `admin.collect.ikanisa.com` as an assets-only
host serving a previous Admin build. A read-only public check on 1 November 2026
instead observed an HTML-accepting root request return a 302 to the platform
Admin host, and `/admin/users?sort=fixture` return a 302 whose Location contains
`/#/admin/users?sort=fixture`. `/custom-sw.js` returned the natural-unregister
script shown below. Read-only provider metadata on the same date identified
deployment `10f8f485-ed1a-462c-8ae9-f23aff19c726` as 100% on version 42,
`ef67525c-163c-4929-a288-3409c7e5abf3`, created on 16 October 2026. The
previous listed deployment was 100% version 41,
`2dce5a15-6902-40ee-96eb-added7ae52f8`, annotated as a build of `f0b8b37a`
on 6 September 2026. The annotation and current matching responses do not prove
the shipped assets match that Git source or establish independent rollback
custody. An older cache-first service worker can keep an existing tab on its
previous build. The prepared `deploy/admin.wrangler.jsonc` proxy is not an
observed rollback preimage.

Wrangler's version metadata reported `has_preview: true` for version 41 but did
not provide its version URL or an asset manifest in the readback used here. The
Cloudflare dashboard sign-in required authenticator verification, which was
pending in this continuation. The documented [version-detail
API](https://developers.cloudflare.com/api/resources/workers/subresources/beta/subresources/workers/subresources/versions/methods/get/)
can list version-specific URLs, but that API result was not available in this
session. `has_preview` alone does not prove that a version URL remains routable.
No v41 asset bytes or immutable manifest were obtained. The annotated Git
revision tracks `web/flutter_bootstrap.js`, but not the generated `build/web`
bundle; source binding also needs retained build provenance or a reproducible
build, as appropriate. No OAuth credentials were extracted.

This candidate redirects GET/HEAD document entries at `/`, `/index.html`,
`/admin` and `/admin/*` to `https://platform-admin.collect.ikanisa.com`.
For `/` and `/index.html`, it keeps the exact path/query and browsers inherit the
original fragment because Location supplies none. Path-based `/admin` entries
become `/#` followed by their exact requested path/query for the destination's
hash router, subject to its login and verification rules. Mixed path-plus-fragment URLs are
ambiguous: the explicit path takes priority and the original fragment is not
preserved, because it is invisible to the HTTP handler. Other origins, unsafe
methods, API/auth/function aliases, stale assets, ambiguous path encodings and
fetch/XHR/subresource and Authorization-bearing requests receive a non-HTML denial.
Older browsers without Fetch Metadata must positively accept HTML; metadata-free
HEAD tools may omit Accept or use `*/*`. Partial or contradictory metadata fails
closed. No upstream fetch,
request body read, service/data binding, session transfer or cookie is involved.
The destination requires its own normal login.

Both historical service-worker script names return a minimal same-origin
retirement script. It waits naturally and unregisters only when activated.
There is no skipWaiting, clients.claim, navigation, cache deletion, storage
clearing, message handler or fetch handler. Existing tabs must finish their work
and close before the old controller can retire. Offline old clients may remain
old indefinitely. The server redirect alone cannot override an old cache-first
controller. The candidate does not clear old-origin browser storage, but it
does not make stored drafts or request history available at the new origin.
Same-tab session storage can be lost when the tab closes; in-memory drafts can
be lost on navigation, reload or tab closure. The presence and recoverability
of real user data have not been verified.

The current source and the observed path redirect do **not** satisfy the
fragment and recovery requirement. A local two-origin browser fixture using the
same entry source showed that `/admin/users?sort=name#synthetic-section` arrived
as `/#/admin/users?sort=name`: the original fragment was lost. Synthetic old-
origin local and same-tab session entries remained on their original origin but
were not available at the destination. This result did not exercise an installed
worker, real accounts or actual predecessor data. The source candidate's 11
local entry tests cover its existing path-priority behavior, not the missing
handoff. The current public response makes that behavior a potential live risk;
it is not an observed real-user data-loss incident.

An isolated decision-only probe compared six ordinary routes with this local
Worker and returned a preserve-original decision for a synthetic conflicting
path and fragment. It did not run as a Worker or browser adapter and did not
navigate a real client. A deployable bridge would need to inspect the fragment in the
browser before navigation, preserve ambiguous cases, and respect the existing
destination guard. The guard rejects a return location with a fragment, while
the email-verification return rule deliberately strips most query parameters;
placing the extra fragment in a query is not a proven preservation protocol.
Holding an address cannot recover an in-memory form already lost to navigation.

A separate synthetic browser fixture carried an allowlisted route and fragment
across two loopback origins through a fake login and reload. Its missing-receiver
case also showed that browser Back can return to a blank page instead of the
original entry. A revised fixture retains a bounded synthetic old-origin backup
and provides a static recovery link; eight local script/HTTP checks passed, but
that revision has not been browser-tested. Neither fixture used actual Admin
authentication, predecessor storage, drafts or an installed service worker.

Before replacing or accepting this entry, refresh the provider version and
reconcile the retained predecessor/rollback artifact, then bind the actual
predecessor's route, storage-key and record schemas to its served bytes. The
current source's `AdminPendingAttemptStore`, for example, binds retained
operations to actor, session, email, role and permissions, and removes records
on a mismatched binding. Do not copy those records into a new session or remove
the old copy merely to make the new origin appear populated.

A qualified successor must preserve the original route/fragment according to
the verified predecessor contract and the destination's authenticated return
rules. It also needs a reviewed, explicit old-to-new identity and operation
reconciliation path: read only the supported bounded record formats, retain the
old originals, validate current actor and permissions, and check each original
request's authoritative status before allowing a retry. Unknown, conflicting,
expired or unresolvable records must remain recoverable and must not trigger a
new effect. Prove the protocol with the actual predecessor and destination
artifacts, synthetic old-origin storage, lost responses, cross-user/session and
concurrent-tab cases, old controlled/offline clients, natural worker retirement
and rollback. No session transfer, automatic data copying or status inference
is implemented by this candidate.

The annotated historical Git revision includes an assisted-group form whose
draft values and roster preview are held in widget memory before submission.
That is source-level evidence only: the v41 asset bytes have not been bound to
the revision, and no actual open editor was inspected. If that implementation
was shipped, a storage-only handoff could not recover an already-closed tab's
unsaved form. The rehearsal must therefore include an open predecessor tab and
an explicit safe finish or preservation path, not only browser-storage checks.

Before further publication or acceptance, review the sealed observed
Worker/version/domain and asset evidence, candidate source/config hashes, local
tests and real-browser fixture results. Verify the observed legacy version is
still current and retained for rollback. Do not rebuild either application or
alter routes, secrets, permissions, credentials or databases as a side effect.
A successful source-bound provider readback, fresh hosted redirect checks, actual
legacy waiting-worker lifecycle, intended account login and business acceptance
remain separate release steps.

The configuration preserves the observed compatibility date, custom domain and
workers.dev/preview enablement. The entry code refuses other origins, including
the workers.dev alias. It has no assets binding, SPA fallback or services. This
deliberately prevents the old host from serving mixed application bundles after
cutover. Provider rollback to the retained old version restores the assets-only
server; it does not recreate a worker registration that a client has already
retired or undo any browser navigation.

Run the dependency-free route/lifecycle contract tests with:

```sh
node --test scripts/tests/admin_entry_test.mjs
```
