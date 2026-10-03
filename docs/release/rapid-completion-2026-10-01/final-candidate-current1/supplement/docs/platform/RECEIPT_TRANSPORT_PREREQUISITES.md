# Receipt transport platform prerequisites

The transport health migration reads ephemeral `pg_net` observations. HTTP
transport observations, worker receipts, financial results and handset/carrier
results have independent meanings; none is evidence that another completed.

## Installation order

1. The platform owner installs the reviewed `pg_net` version and existing trusted
   dispatch functions. The local reference platform uses `pg_net 0.20.0`, owned
   by `supabase_admin`, with existing owner `SECURITY DEFINER` `net.http_post` and
   `net.http_get` functions and `search_path=net`.
2. The actual transport table owner runs
   `scripts/sql/receipt_transport_platform_prerequisites.sql` before application
   migrations. It checks existing trusted dispatch authority, creates the
   response ID index, removes direct table and column privileges from public,
   client and service roles, and grants the ordinary application definer owner
   schema usage and seven necessary SELECT columns. It grants no queue writes,
   table ownership, role membership or superuser authority.
3. Run application migrations as the ordinary installer. The transport migration
   accepts an existing valid, nonpartial single-column B-tree response ID index.
   It only creates a missing index when its caller already has owner authority.
   Its preflight refuses a missing, invalid or incompatible index, missing read
   columns or client/service raw transport exposure.

The shipping prerequisite preserves existing trusted dispatch function and
worker identity. It does not create a new definer or authorize an invoker
platform. Ordinary installer access inherited through existing trusted platform
roles can exceed the seven direct column grants; this script does not change or
claim to constrain those platform memberships.

## Local verification and operation

`scripts/tests/current_ordinary_installer_rehearsal.py` reconstructs the retained
platform metadata in networkless disposable targets before demoting the
application installer. The prerequisite's exact hash is recorded in both clean
and populated rehearsal results. The local harness adjustment to trusted
function metadata is fixture setup and is not application migration authority.

The focused owner/ACL packet under
`docs/release/rapid-completion-2026-10-01/ordinary-transport-owner-review1` retains
the original installer ownership failure and actual client/service raw read and
write denials. It preserves worker identity and trusted function metadata and
records that no queue request or external HTTP operation occurred.

A prerequisite failure stops installation. Check owner, index and effective
privileges through the platform operator; do not grant raw response or queue
access to a browser, service credential or handset. Transport-unavailable
observations must remain unavailable, rather than be presented as healthy zero
counts. Managed hosted installation and dispatch require separate environment
evidence.
