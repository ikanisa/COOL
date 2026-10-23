# Legacy Admin entry candidate

This is a **prepared proposal, not a published release**. It targets only the
existing `collect-admin` Worker. The current API and `collect-platform-admin`
Worker are independent release parents; this proposal does not deploy either.

The old `admin.collect.ikanisa.com` assets-only host still serves a previous
Admin build. Its active cache-first service worker can keep an existing tab on
that build. The prepared `deploy/admin.wrangler.jsonc` proxy is not that live
configuration and must not be used as its rollback preimage.

This candidate redirects GET/HEAD document entries at `/`, `/index.html`,
`/admin` and `/admin/*` to `https://platform-admin.collect.ikanisa.com`.
For `/` and `/index.html`, it keeps the exact path/query and browsers inherit the
original fragment because Location supplies none. Path-based `/admin` entries
become `/#` followed by their exact requested path/query so the destination's
hash router and login retain the task. Mixed path-plus-fragment URLs are
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
controller. Origin-bound drafts and request history are preserved on the old
origin; this does not make them available at the new origin.

Before publication, review the sealed observed Worker/version/domain and asset
evidence, candidate source/config hashes, local tests and real-browser fixture
results. Verify the observed legacy version is still current and retained for
rollback. Do not rebuild either application or alter routes, secrets, permissions,
credentials or databases as a side effect. Provider publication and readback,
fresh hosted redirect checks, actual legacy waiting-worker lifecycle, intended
account login and business acceptance remain separate release steps.

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
