# C11/C13 local investigation slice — 2026-09-30

This packet records local implementation and scoped verification. It is outside
the retained snapshot02 candidate. It does not authorize deployment, close the
whole-Collect production gates, establish authenticated browser acceptance, or
certify a visual-match percentage.

`admin_get_collect_investigation_v1(p_kind, p_id)` reads the transaction/receipt
join after the installed current-session, approved platform-owner and permission
locks. Payment and notification sections remain independently authorized.
Supported Rwanda scope uses the private `rwanda_sms_scope(uuid)` proof from
230300; unknown/unsupported targets return `unclassified` scope and null evidence
sections. The projection uses one statement snapshot and a 60-second measurement
display lifetime. It does not change financial or messaging state.

The actual recorded timeline separates device receipt, ingestion, parsed-event
record creation, allocation-record creation, reported provider confirmation or
rejection, stored confirmation/rejection creation, payment posting, journal
posting, immutable snapshot capture, receipt creation/update, operator approval,
attempt start and recorded outcome. No parser completion, independently attested
settlement, provider callback or carrier delivery is inferred. Kigali displays
retain seconds so events within one minute can be distinguished.

Posting balances come from immutable journal snapshots. Current recorded balances
retain their separate actual update timestamps. The separately named
`masked_snapshot_preview` requires notification read access, derives from the
matching immutable receipt posting snapshot, and replaces the original reference
with an opaque snapshot alias. It is explicitly labeled a reconstruction. The
original message, full destination, body/destination hashes, claim tokens,
operator/worker identity and private outcome notes are absent. Existing
privileged raw-SMS reveal and fenced claim-only original receipt access remain
separate.

Approvals and send attempts expose their actual opaque IDs, state/attempt number
and recorded timestamps. Each history is bounded at the newest 50 rows with its
actual total and an explicit partial-history notice. There is no pagination or
complete-history claim for records beyond this limit. There are no retry,
resend, cancel or send controls; Refresh investigation performs reads only.
Group/member/transaction/receipt links use the real registered routes and current
read capability. The panel has explicit accessible semantics boundaries and
headings; this fixed an observed route-transition rendering assertion.

Validation retained here:

- `view-tests-final2.log`: 15/15 dedicated DTO/UI/route/capture tests passed,
  including unclassified scope, stale hiding, independent permission states,
  no-read denial, safe unavailable/error copy, disposal, read-only Refresh,
  the actual transaction-to-receipt route and both themes at 320px with 2× text.
- `sdk-tests-attempt11.log`: 73/73 preserved real-SDK contract/provider/view tests
  passed, including current Bearer, no compatibility fallback, wrong targets,
  A→B and A→B→A session fences, authority refresh/revocation, partial history and
  actual detail consumers. These use synthetic local HTTP responses.
- `analysis-final.log`: eight scoped files analyzed with no issues.
- `design-authority.log`: sole revolut-design authority hygiene passed. This
  does not certify visual fidelity.
- `investigation-dark-synthetic.png` and `investigation-light-synthetic.png`:
  actual widget renders with bundled Inter/MaterialIcons; inspected for readable
  status, source timestamps, balances, reconstruction, timeline and Refresh.
  They are synthetic component evidence, not an authenticated hosted comparator.

Earlier failed attempts are retained. The first test suite was concurrently
replaced by another checkout writer; both their hardened real-SDK suite and the
distinct dedicated view suite have been preserved. Earlier failed logs describe
earlier source/test setup and do not replace the passing current runs.

The sole visual authority is the selected revolut-design skill and its brand,
DESIGN, web and operator references. The inspected Business source remains
`/Users/jeanbosco/Documents/ChatGPT/Revolut/assets/public-business/enterprise.png`;
it is a public illustration, not a matching authenticated detail route or a
light-theme comparator. The product fixture in `test/fixtures/admin_investigation_v1.json`
is explicitly synthetic and is not backend acceptance evidence.

The subsequent isolated backend run passed 57/57 cases at corrected migration
SHA256 `1360760521245089df8c90265877e951777f09f9422a3e2e15bac3619c0e089b`.
Its first attempt found `payment_provider_confirmations.created_at` does not
exist; the projection now uses the actual `recorded_at` column while preserving
the `confirmation_recorded_at` response field. The failed attempt is retained
in the backend packet. The four retained posted-transaction, posted-receipt,
reversed and bounded-history observations also parse with the current DTO
(`actual-sql-dto-smoke.log`). These are actual isolated service responses using
synthetic local records, not provider sends. The backend packet is
`../investigation-backend/README.md`; its cases include scope mismatches,
independent denial, current email/approval/grant/session expiry, RLS and 50-of-61
partial history.

Remaining acceptance includes later candidate/source binding and release build,
authenticated hosted populated,
empty, denied, stale and failure routes, actual keyboard/screen-reader/browser
zoom checks, matching Business comparator review and owner acceptance. The
organization-owned Android gateway selection does not establish provider or
carrier evidence in this service. No production call, OTP, SMS, deployment or
commit was performed for this slice.
