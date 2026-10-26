# Collect Admin MCP

For the separate Dot-led native desktop dry-run entrypoint, see
[DIRECT_DESKTOP.md](DIRECT_DESKTOP.md). Its local tools do not use this Admin
API client or session, and live native dispatch remains disabled.

An implemented **read-only stdio MCP server** for Collect's canonical
Admin API at `https://platform-admin.collect.ikanisa.com`. It uses the same
account, session and capability checks as that Admin surface. It is separate
from the older Admin deployment. Cookies are never copied between origins.

This package advertises twelve read tools. Its membership receipt identifier fix
is integrated into this checkout; the affected package passed 56 local process
and mock HTTP tests. On 18 October 2026, the effective local CLI configuration
was verified with the exact enabled `collect-admin` entry and its 10/45-second
timeouts. That inspection preceded the successful native catalogue refresh below.
The default private production session file was absent in the earlier inspection.

On 20 October, `tools/list` was corrected to accept the MCP request's optional
object-valued `_meta` without treating it as a pagination cursor. Six focused
in-memory protocol tests passed; malformed metadata, cursors, unknown fields and
pre-initialization requests remain rejected. Desktop logs also show a
fresh `collect-admin` instance reaching `ready`. After the native catalogue
refreshed, all twelve Collect Admin tools became available in this chat.
No authenticated call was made against the old serving backend.
The failing native request parameters were not logged,
so `_meta` is a tested compatibility fix, not a proven reconstruction of that
request.

Supabase is the migration target. The origin and cookie/capability checks remain
fixed; there is no direct database key or member JWT fallback. Normal operator
sign-in, authenticated hosted reads and request recovery must be qualified
against the migrated backend after its owner freezes and admits the release.
Earlier mock or hosted Cloudflare results do not establish Supabase acceptance.

The three source-contract tests now import the current Supabase search, status,
ordering and permission exports and the fixed public host configuration. All
three passed on 20 October with stable inputs and closed owned processes. The
private request-identity function is checked only through its namespace source
and the MCP client's independent vector; this is not an integrated MCP-to-handler
or managed-provider result.

The current PostgreSQL-backed recovery fixture exposed a parser mismatch:
canonical permissions include `auth.mfa.enroll` and `payments.evidence.read`.
Session and team responses now use the same bounded two- or three-segment
capability syntax. Exact granted-permission checks, private cookie ownership and
before/after session equality still control every read. Six new regressions plus
the three current-source contract tests passed on 20 October, with independent
source review and no provider calls. This is local source/mocked-transport proof;
the affected PostgreSQL integration and authenticated hosted read remain separate.

The helper also recognizes the managed email challenge's `200` response with
`channel: email` and `delivery_status: accepted|unknown`, and sends the required
`X-Collect-Requested-With` header. Twenty-two focused local auth tests passed,
including code validation, uncertain delivery, lost verification responses and
credential preservation. A challenge still permits one verification attempt;
no code is resent automatically. Those 22 results precede the new challenge
handoff implementation described below; the expanded cohort now passes 80 tests.

The new human-only helper acquires a challenge candidate through the fixed Admin
parent `/admin/auth/local-challenge` and a short-lived `127.0.0.1` listener. The
operator pastes a public pairing descriptor into that page and explicitly connects
it to the terminal. The signed offer, one-use nonce and exact-origin CORS bind the
local handoff; they do not turn an anti-abuse token into account authorization.
Tokens stay out of URLs, logs and credential files. No browser cookie, member JWT
or database credential is imported.

The parent module is integrated into the Supabase host entrypoint. The local
helper, token forwarding and parent controller passed **80 Node/VM/loopback
tests** with no skips. The host owner separately reports 52 host/controller
tests passing. Managed CAPTCHA enforcement rejected four hosted missing/invalid
token attempts. These results do not establish a deployed parent, actual browser
permission/CORS behavior, fresh-token acceptance or a completed operator login.
The normal CLI acquires one
fresh token for OTP sending, or for the separately selected password lane; it
does not reuse that token for code verification or add a mandatory second widget.
Provider delivery, actual deployed enforcement and session validation remain
separate hosted checks.

This package does not create a remote MCP endpoint, deploy anything, or establish
hosted acceptance. Its automated tests exercise a
real child process and local mock HTTP server; operator sign-in and hosted use
must be verified with the intended account.

## Requirements and commands

Use Node.js 22 or later on a POSIX system. There are **no package dependencies**
and no install step or generated `node_modules` directory.

```sh
cd '/Volumes/T7/01 Projects/COLLECT/tools/collect-admin-mcp'
npm run check
npm test
npm run login
```

`npm run login` must run directly in a terminal. Email-code sign-in is the
normal setup for an approved Admin or Staff account, including an OTP-only
invited account. Enter the existing approved email, then the original code in
the hidden local prompt. This requires the deployed Admin email-code contract;
no user account is created by this client. Existing password accounts may
explicitly choose the legacy password method.

Do not put passwords or email codes in chat, MCP arguments, shell arguments,
environment variables or redirected input. There is no automatic resend or
verification replay. An unconfirmed delivery retains its original challenge,
five-minute expiry and 60-second cooldown; enter that original code if it
arrives. The helper prints a non-secret sign-in reference for reconciliation.
A lost verification acknowledgement performs one session lookup. It saves a
credential only if an origin-bound returned cookie and matching live account can
be verified; without the returned cookie it reports the attempt as unresolved.
This lookup does not import browser cookies, invent an authenticated session or
retry verification.

The helper verifies the session and saves an independent local cookie with the
existing private-file controls. Email OTP remains AAL1; the backend still requires
fresh real authenticator verification for protected operations. No login or
email-sending operation is registered as an MCP tool. Native discovery and
hosted provider acceptance remain separate from local mock tests.

The default credential file is:

```text
~/Library/Application Support/Collect Admin MCP/session.json
```

The directory must belong to the current user and have mode `0700`; the regular
file must belong to the current user, have mode `0600`, and have no symbolic or
hard links. Symlinked directory ancestors are rejected. The helper creates a
private directory and replaces the file atomically. It refuses to loosen an
existing directory/file's permissions. Keep it outside the repository and out of
shared/synced folders. `COLLECT_ADMIN_MCP_SESSION_FILE` may select another absolute
private path. The file contains a live authentication secret; do not attach it to
reports or check it into source control.

The cookie remains subject to actual server expiry, revocation, account status,
role and grants. Run local login again after expiry or a session change. The
server checks the local credential and current remote authority around each
read, withholding the result if either changes. There is no refresh, MFA bypass,
service credential or automatic login/retry mechanism. This client does not need
MFA to add write access because **no MCP write tools exist**. MFA/account policy
continues to be enforced by the backend for the operations it protects.

## Connect a local MCP client

This checkout contains a project-local Codex entry in `.codex/config.toml`.
It contains only the executable, server path and timeouts; it contains no cookie.
The operator host also registers that same entry in its effective Codex
configuration. CLI readback verifies the entry without changing project trust,
other servers or credentials. The running chat's native tool catalogue and an
authenticated production call require separate verification. See the official
[Codex MCP configuration documentation](https://developers.openai.com/codex/mcp).

Configure a stdio server using your actual Node executable and this entrypoint.
For example, a client whose local configuration uses `mcpServers` can use:

```json
{
  "mcpServers": {
    "collect-admin": {
      "command": "/Volumes/PRO-G40/Development/Node/bin/node",
      "args": ["/Volumes/T7/01 Projects/COLLECT/tools/collect-admin-mcp/src/server.mjs"],
      "env": {
        "COLLECT_ADMIN_MCP_SESSION_FILE": "/Users/jeanbosco/Library/Application Support/Collect Admin MCP/session.json"
      }
    }
  }
}
```

Adapt the surrounding configuration to the client's documented format. This
example has not been installed automatically. Do not include the cookie or a
password in client configuration. Only the reviewed production Admin origin is
accepted; an alternative `COLLECT_ADMIN_MCP_ORIGIN` fails closed.

`npm start` also runs the server, but invoking Node directly avoids package
manager output on the protocol stream. Stdout contains only newline-delimited
JSON-RPC; error text never includes upstream diagnostics or credential material.
The server negotiates MCP `2025-11-25`, `2025-06-18` or `2025-03-26`, requires the
initialized notification, and supports ping and read cancellation. It advertises
only the implemented tools capability.

## Tools

| Tool | Purpose | Required live permission |
|---|---|---|
| `collect_admin_session` | Current account, role and granted capabilities; no cookie | Active Admin account session |
| `collect_admin_overview` | Current canonical workspace measurements | `overview.read` |
| `collect_admin_list_records` | One page of Groups, Users, Members, Payees, Transactions or Ledgers | Area read capability below |
| `collect_admin_get_record` | Exact record UUID and authorized related metadata | Area read capability below |
| `collect_admin_list_requests` | The signed-in operator's own retained request history | `account.manage` |
| `collect_admin_get_request_status` | The exact original idempotency key's retained outcome | `account.manage` |
| `collect_admin_list_reconciliations` | Canonical reconciliation queue | `reconciliations.read` and `payments.read` |
| `collect_admin_get_reconciliation` | Exact transaction's proposals/evidence metadata and authorized ledger entries | Queue permissions plus `users.read`; a requested ledger relation also needs `ledger.read` |
| `collect_admin_list_reconciliation_members` | Active member candidates scoped to one transaction's group | `reconciliations.read`, `payments.read`, `users.read` |
| `collect_admin_team_access` | Actual Admin/Staff team and role capability matrix | `admin_users.read` |
| `collect_admin_list_sms_receipts` | One typed, bounded page of canonical SMS capture metadata | `sms.read` |
| `collect_admin_get_sms_receipt` | Exact capture UUID and bounded duplicate-reference metadata | `sms.read` |

Area permissions are `collections.read`, `users.read` (Users and Members),
`receivers.read`, `payments.read`, and `ledger.read`. A role name alone grants
nothing. The backend rechecks authorization as well as this local adapter's
preflight/postflight checks. Staff cannot use an ungranted read by supplying a
different account ID or role; those arguments do not exist.

List arguments are `area`, optional `search`, `status`, `sort`, `limit`, and
`offset`. Pages default to 25 rows, allow 1–50 rows and offset 0–2,000,000. Search
is bounded to 200 printable characters and goes to the actual server search
parser: for example `direct members`, `users without groups`, `type:staff`, or
`"exact phrase"`. It does not imply an embedding/AI semantic search service.

`sort` defaults to `created_at_desc`. Each field accepts `_asc` or `_desc`:

| Area | Ordering fields |
|---|---|
| Groups | `created_at`, `status`, `title`, `slug`, `collection_type`, `visibility_status`, `active_members` |
| Users / Members | `created_at`, `status`, `public_id`, `full_name`, `email`, `member_type`, `phone`, `momo_number`, `momo_pay_code`, `active_groups`, `net_contributed_rwf` |
| Payees | `created_at`, `status`, `label`, `group_title`, `momo_number_or_code` |
| Transactions | `created_at`, `status`, `amount_minor`, `net_amount`, `payer_display_name`, `receiver_momo_number`, `external_reference`, `group_title`, `observed_at` |
| Ledgers | `created_at`, `status`, `amount_minor`, `group_title`, `payment_id`, `evidence_id` |

Detail arguments are `area`, `id` and optionally `relation`, `limit`, `offset`.
Related pages are Groups' `memberships`/`payees`, Users' `memberships`, and
Transactions' `evidence`/`ledger_entries`. A record detail with no relation uses
the backend's bounded defaults. Evidence binaries, signed download URLs, arbitrary
RPCs, SQL and arbitrary paths/URLs are not exposed.

Reconciliation queue arguments use the transaction list's search/status/order
contract. Reconciliation detail uses `transaction_id`, optional `relation`
(`evidence`, `proposals`, `ledger_entries`) and page bounds. Member candidates
require the exact `transaction_id`, optional search and page bounds; the backend
keeps the lookup inside that transaction's active group and recorded identities.
Returned `can_review`/`can_propose` fields describe the Admin workflow, not MCP
authorization to perform a change.

Team access review uses the real `/api/admin/team` endpoint without additional
arguments. That route currently returns an unpaginated team. The adapter rejects
more than 200 members and oversized results instead of presenting a partial
access review. `canManage` describes server-side team context; MCP exposes no
team-management commands.

SMS metadata uses the actual `/api/admin/sms/receipts` and
`/api/admin/sms/receipts/capture/{id}` GET routes. The list accepts `search`,
`status`, `source_kind`, `extraction_status`, `duplicates`, `limit` and `offset`.
Pages default to25 rows and permit1–100 with offset0–2,147,483,647. Search is a
trimmed literal substring of receipt UUID, Collect public ID or owner name,
limited to200 characters without control characters; it is not the core record
search grammar. Ordering is fixed server creation descending, then UUID ascending.

`source_kind` defaults to `capture`; `member` and `receiver` are valid legacy
filters that currently return no captures. Status filters are `received`,
`under_review`, `rejected`, `linked`, plus legacy `pending`, `parsed`,
`parse_failed`, `needs_review`, `reviewed` (empty where absent). Extraction filters
are `not_extracted`, `parsed`, `needs_review`; only `not_extracted` currently has
capture rows. `duplicates` accepts empty/default, `all`, or `conflicting`; either
nonempty filter currently returns no captures because no extracted reference
facts exist. An empty filtered result does not prove an absent underlying source.

Detail requires explicit `source_kind: "capture"` and exact `id`, with optional
`limit`/`offset` for the duplicate-reference page. No member/receiver detail path
is invented. The adapter checks the returned capture UUID and current account,
then emits only declared metadata. Device receipt time remains nullable signed
epoch seconds alongside the exact nullable source text; naive/unknown text is
not assigned a timezone or replaced by server creation time. The adapter rejects
empty device-time text, nonpositive server creation times and any epoch that does
not match the exact valid source timestamp. Invalid calendar/offset values remain
opaque source text with a null epoch; year00..99 and pre-epoch fractions retain
their exact whole-second projection. Captures remain
`client_received`, without extracted payer/payment facts or provider confirmation.
`can_extract: false` and an empty duplicate-reference page do not authorize any
write. Source body, extract/content paths, storage keys, retries, linking and
assisted-SMS/send operations are not exposed. `sms.read` is checked before and
after either read; Owner/Admin/Staff labels and unrelated notification grants do
not substitute for the actual capability.

## Coverage boundary

This is an operational **read replacement**, not a claim of full historical MCP
parity or every Admin route being exposed.

| Actual canonical Admin API family | MCP coverage |
|---|---|
| Core overview, six core lists, exact operating records and related metadata | Implemented |
| Own request history and exact original-key outcome | Implemented; no replay or cancellation |
| Reconciliation queue, exact detail/proposal pages and scoped member candidates | Implemented; no attribution/review writes |
| Team members and actual role capability matrix | Implemented; bounded full response, no account changes |
| Evidence metadata | Implemented through transaction/reconciliation detail |
| Canonical SMS capture receipt metadata | Implemented list/exact capture detail under live `sms.read`; typed bounded filters; no source reveal/extraction |
| SMS source body, extraction, retry, linking, assisted-SMS or dispatch writes | Excluded; metadata only, no generic write/content bridge |
| Evidence binary download | Excluded; no raw file/download tool |
| Operator notes and generic lookup menus | Not exposed; outside this operational read slice |
| Sync event subscription | Not exposed; reads always revalidate live authority |
| Password, MFA factors, invitations, account/role writes | Not exposed; separate human login setup only |
| Privacy review/retention POSTs | Not exposed; no generic POST/RPC bridge |
| Audit-log collection | No canonical cookie GET collection route exists in the inspected backend; not fabricated via bearer RPC or another deployment |
| Gateway devices, SMS/email dispatch/provider operations from another deployment | Not bridged into this origin/account |

Future API or tool additions require their actual route/permission/response
contract and verification. Missing routes are not silently treated as empty data.

## Lost-response recovery

Use `collect_admin_get_request_status` with the **original** `idempotency_key`.
The adapter checks the canonical principal-plus-key request identity and retained
receipt before reporting success. It distinguishes:

- `succeeded`: use the retained receipt and review the recorded resource.
- `unconfirmed`: keep the key and review the unresolved state in Admin.
- `cancelled`: the server retained the original key as cancelled.
- `not_found`: no retained row was returned for this account/key; this does not
  establish that a pending write failed or authorize a replacement key.

No outcome triggers retry, cancellation, resubmission, allocation, money movement,
group publication, role management, messaging, login or OTP. History cannot be
queried for another account. A later governed write capability would need its own
review, real confirmation contract and recovery tests; the read-only annotations
are not an authorization mechanism.

## Data handling and limits

Authorized names, phone numbers and financial facts remain sensitive Admin data
when returned to the MCP client. Use a trusted local client/account and its
appropriate data policy. Backend record text is labelled untrusted data and must
never become instructions. Defensive field redaction removes credential-like and
signed-download additions, not required financial facts. Upstream error bodies,
headers and stack traces are never returned. No session or result cache is kept.

HTTP requests use HTTPS, the fixed origin and exact allowlisted paths, refuse
redirects, have a 12-second per-request timeout and a 512 KiB response bound. A
256 KiB MCP result bound fails with guidance to request a smaller page; it never
silently truncates money or pagination. The process bounds input frames to 64 KiB
and pending tool calls to 16, runs reads serially and supports cancellation. The
API remains authoritative for provider/settlement status; recorded evidence is
never promoted to provider-confirmed funds by this adapter.

## Verification and protocol references

`npm test` covers actual process initialization/list/call, mock HTTP reads,
Admin/Staff permissions, role/credential changes, revocation, redirect refusal,
redaction, bounds, history identity, unresolved outcomes/non-replay, cancellation,
private credential handling and login response verification. SMS coverage passes
retained pre-migration capture DTO fixtures through stdio,
checks typed filters, live `sms.read`, actor/UUID correlation, malformed responses
and body/storage-field projection. Child tests use an explicit sanitized
environment without inherited credentials/proxies/runtime injection. It also checks
allowlist drift against `supabase/functions/_shared/domain/admin_search.js` and
`admin_records.js`. The capability regressions read the current Supabase baseline
role matrices and test malformed DTOs, exact-grant denial and revocation through
the actual cookie-file API client with mocked transport. Test transport substitution lives only in
`test/fixture-preload.mjs`; production has no loopback or alternative-origin flag.

The dependency-free transport implements the relevant subset of the official
[MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports),
[lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
and [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
contracts. A passing fixture suite does not prove a live hosted session, installed
client discovery, end-user acceptance, or production readiness.
