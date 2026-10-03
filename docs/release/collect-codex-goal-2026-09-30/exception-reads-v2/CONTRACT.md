# Admin operational exception reads v2

These reads expose retained derived source conditions and human review evidence.
They do not settle a payment, resolve its source, authorize a send or attest alert
delivery. `source_scan_complete=false` means the durable inbox is not an
exhaustive historical scan. Migration does not backfill historical exceptions.

`admin_list_operational_exceptions_v2(p_active boolean=true,p_limit integer=20,
p_before_changed_at timestamptz=null,p_before_id uuid=null,
p_source_kind text=null)` requires the current approved `platform_owner`, live
JWT-bound session and all of `payments.read`, `notifications.read`,
`system_health.read`, using the inherited locked authority helper. No service or
anonymous execution is granted; private RLS tables/helpers retain no API grants.
Repeatable Read and Serializable requests are refused with
`40001 operational_exception_snapshot_retry`.

List envelope keys are exactly `contract_version:2`, `scope:platform_global`,
`checked_at`, `sample_valid_until`, `active`, `source_kind`, `limit`, `rows`,
`next_cursor`, `escalation_delivery_verified:false`, `source_scan_complete:false`.
Both timestamps are canonical UTC with exactly six fractional digits; one
committed statement derives them and every row. The read expires at checked_at
plus 60 seconds; this does not renew the source observation or prove a healthy
source. UUIDs are general canonical lowercase UUIDs, not restricted to version 4.
Revisions are integers 1..1000000000. No overall counts are returned.

`p_source_kind` is null for all categories, otherwise exactly `raw_sms`,
`allocation`, `payment`, `receipt` or `gateway`. The category and active filters
apply before paging and are echoed exactly. Limit is 1..50. Cursor parameters are
both null or both present; timestamps must be finite. Rows are strictly ordered
by `(last_changed_at,id)` descending; a supplied cursor excludes its pair and
all newer pairs. `next_cursor` is null when this read found no extra candidate,
otherwise is exactly `{changed_at:last row.last_changed_at,id:last row.id}` and
the page has limit rows. Separate reads can observe source changes; the cursor
does not reserve a historical snapshot. Invalid arguments are refused with
`22023 operational_exception_query_invalid`.

Each row has exactly `id`, `source_kind`, `source_id`, `reason_code`, `active`,
`revision`, `source_sha256`, `first_observed_at`, `last_changed_at`,
`transaction_sms_id`, `acknowledged`, `escalation_requested`. Observation time is
ordered `first_observed_at <= last_changed_at <= checked_at`. `source_sha256` is
a digest of the server-derived redacted predicate signature, not a receipt body
or destination hash. Review flags apply only to the current head revision.

`transaction_sms_id` is server-derived and nullable. A raw source links to its
own raw SMS UUID only if current `rwanda_sms_scope` accepts it. Allocation links
through the actual parsed event's raw SMS join and the same scope helper.
Payment links through its actual parsed event only when currency is RWF, parsed
receiver/provider and raw receiving hash match the stored payment, and current
Rwanda SMS scope accepts the raw source. A payment with a valid receiving route
but no linked parsed observation still has a null SMS link. Receipt and gateway
rows always have null SMS links; their opaque source UUIDs refer to their own
sources. Clients must not construct an SMS link from allocation/payment IDs.

`admin_get_operational_exception_action_v2(p_request_id uuid)` requires the same
current read authority. It uses function-local `lock_timeout='100ms'`, restored
on return or error. If authority locks cannot be acquired within that bound,
`55P03 operational_exception_authority_busy` returns no request outcome. This is
neither `not_recorded` nor permission to replay a mutation. No request lookup or
lock probe precedes current authority. An invalid null request is refused with
`22023 operational_exception_action_invalid` after authority succeeds.

Lookup envelope keys are exactly `contract_version:2`, `scope:platform_global`,
`checked_at`, `sample_valid_until`, `request_id`, `status`, `receipt`. It has the
same single-statement 60-second read TTL. `status` is `recorded`, `not_recorded`
or `in_progress`. Only recorded has a non-null immutable v1 action receipt;
another actor's request is indistinguishable from an absent request. After
authority succeeds, a held request advisory lock may yield in_progress with
null receipt. The original action usually holds the global roster authority
lock, so concurrent lookup instead returns bounded authority_busy until commit.

Recorded receipt keys are exactly `contract_version:1`, `request_id`,
`exception_id`, `revision`, `action`, `recorded_at`, `source_resolved:false`,
`financial_action:false`, `send_action:false`,
`escalation_delivery_verified:false`. Action is acknowledge or escalate;
recorded_at<=lookup checked_at and request_id binds the requested UUID. V2
projects only the immutable action columns, never arbitrary stored JSON.
V1 action RPC, original request replay rules and captured receipts are unchanged.
Manual reconciliation reads never automatically retry the original mutation.

Canonical navigation is `exceptions`, `Exceptions`, `warning_amber`,
`/admin/exceptions`, permission `payments.read`, order 147, enabled true. This
single menu permission is visibility only; actual reads require all three
permissions. Existing custom/disabled key or route entries are preserved; an
explicit empty or hidden navigation configuration is not overridden by clients.

Schema-only UAT and fixtures are synthetic local evidence. Deployment, actual
Auth provider/JWT, email provisioning, supervised business handling and delivery
remain outside this foundation.
