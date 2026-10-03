# Cloudflare read-only provider identity — 2 October 2026

The repository-named `collect-public` Worker has an independently read active
deployment. Its connection to `collect.ikanisa.com` remains unverified because the
exact custom-domain API request returned HTTP 403, code 10000, `Authentication error`.
No provider state was changed.

The successful account GET returned exactly one account:
`2209b915a85b1c11cee79b7806c6e73b`. The successful deployment GET returned the active
deployment `f52b6b24-e892-4435-aa15-2179a1585d8c`, created
`2026-09-07T06:41:18.009965Z`, source `wrangler`, serving version
`29d7cc2a-f3ea-4fae-8ac2-3805a60d4065` at 100% of traffic. Cloudflare documents that
the first item from the [Worker deployment list API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/deployments/methods/list/)
is the latest deployment actively serving traffic. This identifies the named
Worker only; it does not identify the public hostname's active deployment.

`deploy/public.wrangler.jsonc` names `collect-public`, with assets at
`../build/public_web`. It declares neither account nor routes. The current
`.github/workflows/public-website.yml` runs static and production live checks and
contains no publishing step. Its SHA-256 and the config SHA-256 are captured in
`readback.json`, together with relevant builder/CI source and selected candidate
artifact hashes before and after the requests.

The selected candidate is `.cache/public-static-current-20261002-batch4-attempt1`.
Its own `version.json` reports generation at `2026-10-02T00:57:53Z`, commit
`df1150ea118aa5dcc9ecb880c71873423081bffe`, and a dirty source tree. Its root and six
legal HTML files, manifest and version metadata are bound here by hash. This is a
selected-file binding, not a full artifact or transitive source seal. The named
Worker's returned deployment predates that candidate. No content-hash comparison
links provider assets to it, and the candidate is not the configured deployment
directory.

The local credential was already present and unexpired when read. Its values and
raw provider bodies were not written or printed. An absolute existing Node
v24.19.0 runtime, pinned by SHA-256, made bounded HTTPS GET requests; no Wrangler
package was installed or executed. A successful query for `ikanisa.com` returned
no matching zone in this credential's view, so no route-list request was made.
That result does not prove the zone or public hostname is absent.

The first process made two GETs in 2.086 seconds. The independent follow-up made
two GETs in 1.467 seconds. Both exited 0, which means the capture completed;
the JSON status fields and HTTP outcomes determine what was verified. Both
observed the selected files unchanged by SHA-256. The receipts retain request
times, method, endpoint, HTTP status, filtered facts, raw response byte counts and
raw response hashes. They omit account names, author emails and credential values.
The first report's generic final limitation mentions the *kind* of deployment
metadata expected; it actually captured no deployment IDs. The follow-up is the
only deployment receipt.

Original criteria remain open: exact public-domain service mapping, equality to
the current artifact, browser interactions, original Revolut comparison, native
proof and release acceptance. Public HTTP responses are separate evidence. This
provider readback does not rewrite native or registered proof and does not close
production readiness.

Files: `readback.cjs` / `readback.json` contain account and custom-domain capture;
`source-worker-readback.cjs` / `source-worker-readback.json` contain the independent
source-named Worker deployment and zone capture. `process-receipts.json` records
the successful capture process outcomes. `seal.json` binds these proof files and
rechecks the selected source/candidate byte hashes at seal time.
