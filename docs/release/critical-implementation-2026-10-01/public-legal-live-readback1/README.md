# Public legal live readback — 2 October 2026

PD-04 and PD-05 remain open. The public root and all six legal entries returned
HTTP 200, but the public responses differ materially from the current local
candidate. Three destinations linked by the live legal pages return HTTP 404.
This is anonymous public evidence; authenticated Cloudflare deployment identity,
configuration, publication and approval were not observed.

The direct readback ran at **2026-10-02T06:23:33.383848Z–06:23:38.094414Z** against
the repository target `https://collect.ikanisa.com`, as declared by
`scripts/qa/ios_delivery_guard.py`. It issued 16 distinct same-origin GETs and two
support-link GETs, with a 2 MiB response cap, 15-second per-hop timeout, at most
three redirects, four concurrent requests and no retries. No credentials,
cookies, form submission, account/data request, message, upload, deployment or
provider mutation was used. Response headers retain an explicit safe allowlist;
Set-Cookie values were not saved.

## Exact public destinations

| Public URL | Status | Redirects | Result |
| --- | --- | --- | --- |
| [Root](https://collect.ikanisa.com/) | 200 | None | Canonical and heading agree; bytes and visible content differ from candidate |
| [Privacy](https://collect.ikanisa.com/privacy/) | 200 | None | Old links, deletion instructions, geographic/payment content and media reference |
| [Terms](https://collect.ikanisa.com/terms/) | 200 | None | Old cookie link, deletion path and geographic/payment content |
| [Account deletion](https://collect.ikanisa.com/account-deletion/) | 200 | None | Promises a form, with zero form/input elements in returned HTML |
| [Data deletion](https://collect.ikanisa.com/data-deletion/) | 200 | None | Old deletion instructions; current candidate retention anchor absent |
| [Trust](https://collect.ikanisa.com/trust/) | 200 | None | Legal-body text agrees; bytes and media reference differ |
| [Security](https://collect.ikanisa.com/security/) | 200 | None | Legal-body text agrees; bytes and media reference differ |
| [Subprocessors](https://collect.ikanisa.com/subprocessors/) | 404 | None | Linked by live Privacy |
| [Privacy request](https://collect.ikanisa.com/privacy-request/) | 404 | None | Linked by live Privacy |
| [Cookies](https://collect.ikanisa.com/cookies/) | 404 | None | Linked by live Privacy and Terms |

All other internal destinations appearing in the generated/live legal graph
returned 200: `/community-groups/`, `/craas/`, `/group-savings/`, `/insurance/`,
`/our-partners/` and the additional live `/diaspora/`. Their reachability does not
accept their claims, rendered appearance or intended current content.

## Graph, content and support observations

The six generated legal entries contain **90 internal link occurrences**.
All destination URLs returned 200. One fragment failed on the public response:
`/data-deletion/#retained-data-summary`. The other generated fragments, including
`/privacy/#cookies`, `/privacy/#sharing`, skip links and deletion section anchors,
were present. This gives **89/90 HTTP-and-fragment checks**, not intended-content
or deployment acceptance. The current generated notices differ from public
notices, so working destinations alone cannot close PD-05.

The live six-entry graph contains **97 internal link occurrences**, with four
failures at the three 404 destinations above. All other live internal URL and
fragment occurrences resolved. Every occurrence, label, exact source route,
destination and fragment result is retained in `live-legal-links-check.json` and
`generated-links-live-check.json`.

The public [deletion page](https://collect.ikanisa.com/account-deletion/) still
describes an online form and displays field specifications. The retained HTML
has no `<form>` or `<input>` and only a navigation-menu button. The current
candidate instead directs users to support and describes information support
may request. Public Privacy, Terms and both deletion pages still show the old
app deletion path; the candidate uses Settings → Security → Delete data.
Current candidate Rwanda/MoMo scope also differs from the public bank-transfer,
SEPA and diaspora wording. Root marketing content retains broader service
claims than the current capability-bound candidate. The diffs preserve exact
observations without inferring which provider deployment produced them.

All seven sampled HTML byte hashes differ from the current artifact. Canonicals
and main headings agree. Privacy, Terms and both deletion legal-body text differ;
Trust and Security legal-body text agree. The public legal pages reference
different screenshot filenames from the current candidate, including the old
account-deletion media and its different alt description. No image-pixel,
rendered visual or interaction acceptance is claimed.

All generated/live mailto links address `info@ikanisa.com`; their subjects and
labels are retained. Both distinct WhatsApp support links returned a 302 to an
HTTPS `api.whatsapp.com/send/` landing page followed by HTTP 200, with the expected
phone `250795588248` displayed. Only anonymous landing HTML was read. No app was
opened and no message sent. Email delivery, supported response, acknowledgment,
receipt/status, failure, duplicate-request recovery and actual erasure remain
unexercised. Store/download links and arbitrary third-party marketing sites are
outside this legal/support readback.

## Candidate and untouched-input proof

The default deployment asset directory is `build/public_web`, which is absent.
The existing candidate was read from
`.cache/public-static-current-20261002-batch4-attempt1`; it was not rebuilt.
All **55 candidate file hashes** match the original batch4 artifact record.
All **70 tracked input/target/instruction hashes** remained unchanged across this
readback, and the current inputs match the prior static-build execution record.
The maintained sources, registries and earlier proof packets were not edited.
The original PD-04/PD-05 criteria were copied unchanged to
`acceptance-criteria-readback.json`.

`live-responses.json` retains dated exact request URLs, every response/redirect,
selected headers, byte lengths, content hashes, parsed links/anchors and HTML
paths. `candidate-live-comparison.json` binds sampled local/public hashes and
media markers. Raw response bodies are retained under `responses/`.
`readback-summary.json`, before/after source/artifact maps, markup readback and
the visible-text diffs complete the proof. HTTP Cloudflare headers establish
only what the anonymous endpoint returned; they do not identify an authenticated
deployment, source commit or published artifact.

## Remaining acceptance

For PD-05, the authorized release owner must publish/serve the reviewed current
legal candidate or otherwise repair the observed public links and notices,
bind the exact artifact to the actual target deployment, and verify every
generated legal URL/anchor against the intended public content. The promised
privacy-request outcome must work.

For PD-04, the public no-app journey must truthfully reach the supported request
channel and produce observed acknowledgment/receipt/status with failure and
duplicate recovery. Request confirmation must remain distinct from completed
deletion. Legal, privacy/provider, owner publication and full production
acceptance remain open under the original criteria. This readback authorizes
no publication or request/message submission.

Primary public pages were also opened through the web tool. Its displayed crawl
dates were historical, and `/security/` was unavailable there; current status and
hash assertions above come from the bounded direct GETs, where `/security/`
returned 200. No conclusion about site outage or authenticated provider access
is inferred from a tool-specific access result.
