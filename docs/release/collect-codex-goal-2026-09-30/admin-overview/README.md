# Admin Overview and readable headings — C09/C17 source progress

2026-09-30. Local source and synthetic implementation evidence only. No
production request, migration deployment, OTP, SMS send, commit or hosted
acceptance was performed by this slice.

## Implemented behavior

Owned migration: `supabase/migrations/20260930230200_admin_receipt_overview.sql`.

- `admin_receipt_overview_v1(p_country: 'RW')` is an authenticated read. It locks
  the installed current approved platform-owner authority for `overview.read`.
  Receipt authority is independently locked for `notifications.read`; denied
  receipt access returns `receipts_state: denied` and a null section, while
  financial measurements remain available.
- The Rwanda MoMo financial measure counts payments still `posted`, currency
  `RWF`, provider `mtn_momo`/`airtel_money`, and canonical `posted_at` within the
  Africa/Kigali day. Reversed payments are excluded. The numeric sum is an exact
  decimal string, not a JavaScript floating-point amount or a wallet balance.
- Financial and receipt aggregates share one SQL statement snapshot. The read
  timestamp is captured afterward; a midnight crossing fails closed for refresh.
- Pending receipts mean queued plus awaiting confirmation. The oldest timestamp,
  definite `failed_no_send`, unknown `uncertain`, and unresolved `send_started`
  counts remain distinct. Counts cover current outbox records across all Rwanda
  groups, rather than only today's receipts. Observed sent is not a delivery claim.
- The exact DTO rejects missing/extra fields, permissive numeric types, invalid
  Kigali day intervals, invalid count/oldest relationships and fabricated zeros.
  Samples expire after 60 seconds; stale measurements and sensitive values are
  hidden while explicit refresh remains reachable.
- Operational health and assisted-SMS gate reads are independent. Only the
  existing redacted alert measurements establish queue-check outcomes. Provider
  configuration, sender/device/network diagnostics and unattended execution
  remain explicitly unverified or unavailable. Heartbeats never mean successful
  supervisor execution or handset delivery.
- An unavailable queue total, SLA or allocation read no longer suppresses the
  other loaded Overview sections. A failure does not become a healthy zero.
- Receipt alert links use the registered Admin route and validated status query.
  Explicit alert filters clear remembered search/page/sort; ordinary list/detail
  return preferences and stable realtime activity behavior remain supported.
- Specialized Overview, group/member and transaction column headings now have
  visible labels. Overview headings retain accessible names. The light summary
  uses existing readable text adapters, correcting previously invisible white
  text on a white panel. Narrow attention age/action rows wrap.

## Verification and retained logs

- `tests-final.log`: 42 scoped tests passed across the new Overview suite, existing
  Overview totals, queue navigation, realtime stability and shared readability.
- `registered-route-test.log`: the changed alert test then passed against the
  actual `CollectAdminApp` router, replacing its earlier isolated test router.
- `overview-final-tests.log`: 26 current Overview/total tests passed after the
  verified light foreground fix, including dark/light 1440px captures and 320px
  at 2x text with scroll and overflow checks.
- `health-partial-state-test.log`: 1 additional current test passed for unavailable
  operational health while financial and SMS measurements remain readable.
  These are 44 distinct tests across the scoped files, with selective reruns after
  the relevant changes; these counts are not global Collect acceptance.
- `analysis-final.log`: final 7-file scoped Flutter analysis. Earlier analysis and
  failed test attempts are retained under their attempt names.
- `heading-semantics-test.log`: 1 selective rerun passed after the Overview header
  semantics addition; this is an existing test, not an extra unique test.
- `design-authority.log`: sole-authority hygiene check, separate from visual fidelity.

## Reference and capture scope

The sole design authority is the owner-selected `revolut-design` skill. This
implementation uses its brand-adaptation, DESIGN and Business/operator web
references through existing Collect theme/components. Inspected public Business
pattern comparator:
`/Users/jeanbosco/Documents/ChatGPT/Revolut/assets/public-business/enterprise.png`.
It supports its visible dark rounded operational row and readable pending state,
not a measured full authenticated dashboard or a light-theme acceptance claim.

`overview-dark-synthetic.png` and `overview-light-synthetic.png` are 1440×1400
component captures using synthetic financial/queue data, the actual bundled Inter
and MaterialIcons fonts, and existing Collect runtime adapters. They exclude the
Admin shell and are not authenticated browser or production route captures.
The corrected light capture and dark capture were inspected for readable values,
visible headings, distinct outcomes and desktop overflow.320px enlarged-text
checks exercise the scrollable implementation; screen-reader speech, actual
browser zoom, keyboard acceptance and owner comparison remain unverified.

## Remaining acceptance

The migration still requires isolated database UAT and reviewed deployment.
Authenticated authority/role/session revocation and real populated/empty/stale/
error route states require hosted checks. Latest web bundle, direct route reload,
keyboard/screen-reader behavior, production measurements, matching Business
comparator and owner acceptance remain open. C09/C17 are source progress, with
those evidence gates retained; no 100% design or production-ready claim is made.
