# Collect platform operations

The API emits a bounded, fixed-field application health record for unexpected
failures, server failures and capacity denials. Successful and ordinary rejected
requests do not fill this failure stream. The component is a source-defined
label; raw paths, queries, messages, bodies, cookies, phone numbers and actor
identifiers are excluded. A generic outer HTTP or domain failure's generated response request ID links
its user-visible failure to the application record without retaining the
submitted request. Fenced/custom responses retain their existing payload and
have no invented request correlation. Scheduled failures record the existing
valid opaque `dispatch_id` when present, otherwise null; the independent
`request_id` stays null and no scheduler response field is added. A route that already handled its own failure keeps its
exact response; the outer observation uses a null request ID rather than
inventing a correlation with that route's private error record.

This application-health stream emits at most64 records plus one
`events_suppressed` notice per isolate
per minute, shared by domain and outer HTTP/scheduled failures. A suppressed
runtime record carries no diagnostic detail. This limit does not impose a
project-wide logging quota. Supabase's own invocation metadata has a separate
retention/access configuration and is not certified as redacted by the
application's field contract. Existing transport-rejection and application-work
close diagnostics remain separate; this limit does not claim a cap on all
provider or application logs.

Run one read-only check with the exact deployed and reviewed source identity:

```sh
node scripts/supabase/platform_health_probe.mjs --expected-source SOURCE_SHA256
```

The probe reads only
`https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-api/health`, refuses redirects,
uses no credentials and makes no retry. Its five-second deadline,2KiB body bound,
exact response contract, source pin and timestamp checks prevent an old or
unrelated successful page from counting as current API health. Exit0 means this
single source-bound read passed; exit1 means it did not; exit2 means invalid CLI
configuration. No probe result establishes OTP, payments, notification delivery,
backup recovery, application availability over time or an accepted SLO.

| Observed event or probe outcome | Operator response |
| --- | --- |
| `source_mismatch` | Read the latest deployment/version from the provider and compare the actual collect-api/admin-api/collect-jobs source identity, function versions, configuration and SQL chain with the sealed Supabase release. Do not change the probe pin just to silence the mismatch. |
| `unavailable`, `network_failure`, `timeout` | Read provider status and current deployment logs. Check PostgreSQL/pooler availability, application-fence state, connection/request limits and the accepted source tuple. Preserve the failed probe and its time before any recovery action. |
| `invalid_response` | Inspect provider routing, cache headers and the actual Supabase function metadata and retained deployed ESZIP body. Do not retain a body that may contain private data in the shared incident log. |
| `runtime_unavailable` | Use only the fixed stage/reason/presence classes and exact source/request ID when present. Check the matching Supabase configuration and database target; never log the raw exception or connection URL. |
| `unexpected_failure` | Correlate the generated request ID and component with the exact deployed source. Preserve the private failing evidence separately; do not paste credentials or submitted bodies into a public issue. |
| `service_degraded` | Check the component's required configuration and provider state. Unconfigured OTP, integrity, processor or approval controls must remain unavailable until their actual authorized configuration is present. |
| `capacity_limited` | Check the configured budget/window and upstream allowance. Do not repeatedly retry, bypass admission limits or replay a financial or privacy mutation with a new operation ID. |
| `events_suppressed` | Treat the failure stream as incomplete for that isolate/window. Check provider aggregate failures and the incident's actual scope; a small retained log count is not evidence of low impact. |

For an unknown mutation outcome, use the retained original operation ID and its
readback route. A fresh ID can duplicate an external action. Financial evidence,
review/reversal history and retention barrier/effect/outcome records remain
authoritative; a successful health request cannot replace their reconciliation.
For rollback or restore, retain the current artifact/configuration and use the
version-specific deployment/recovery tools with independently verified archives.
Restored credentials remain quarantined until separately authorized.

Read maintenance state through the existing authorized scheduler operator's
`status` action; it does not dispatch a job. Its `awaiting`, `unconfirmed`,
`month_dispatches`, enabled/Cron flags and existing original dispatch IDs
are the maintained local incident inputs. Reconcile an unknown outcome using
that same dispatch ID and the reviewed operator; do not send a new job to
make a red health record disappear. Source budgets are concrete controls,
not measured project capacity or approved operational objectives.

The duty owner, accepted SLOs, alert destination/acknowledgement, incident
severity, real capacity/device/session floors and a delivered fault/recovery
rehearsal remain acceptance decisions. This source implementation does not
invent those decisions or claim that an alert has been delivered.
