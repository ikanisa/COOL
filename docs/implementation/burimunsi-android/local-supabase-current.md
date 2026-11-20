# Existing local Supabase: observed target and shared deployment gap

Observed on 9 November 2026. The owner clarified that Collect and BuriMunsi must use the same existing local Supabase service, Collect Admin, business schema and ledger. No independent BuriMunsi backend instance was created.

## Exact retained installation

| Identity | Observed value |
| --- | --- |
| Owning workspace | `/Users/jeanbosco/Documents/Supabase` |
| Retained project source | `local/development/projects/app` under that workspace |
| Supabase project/container identity | `local-app` |
| Existing Colima profile | `supabase-local` |
| Existing Lima instance | `colima-supabase-local` |
| Backing image | `/Volumes/T7/Development/Supabase/runtime/SupabaseRuntime.sparsebundle` |
| Required T7 UUID | `FCC99452-6DC6-3A10-829F-FAB9AD586743` |
| Mounted runtime | `/Volumes/SupaRuntime` |
| Dedicated Docker socket | `/Volumes/SupaRuntime/.colima/supabase-local/docker.sock` |
| Actual database | `postgres`, PostgreSQL 17.11, container `supabase_db_local-app` |
| Exported public API URL | `http://127.0.0.1:55101` |
| Exported environment | `local` |
| Studio | `http://127.0.0.1:55103` |

The exported public contract is `/Users/jeanbosco/Documents/Supabase/local/development/projects/app/generated/client.json`. Its field names are `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ANON_KEY` and `APP_ENVIRONMENT`. Private credential files were not opened, and credential values are not reproduced here.

## What was resumed

The retained sparse image initially existed but was unmounted; the dedicated daemon/socket and local service ports were unavailable. The existing Docker Desktop context is a separate daemon and could not establish this installation's status.

After authorization to resume the existing installation, the T7 UUID, image ownership, mounted APFS identity, original source-root/backing-image marker, existing Colima configuration, Lima configuration and retained VM disk were checked. The existing image was mounted, and only the existing Colima profile was started with `--activate=false --ssh-config=false`. Thirteen retained services resumed automatically.

The remaining existing Edge Runtime container, `d439be61a572`, had restart policy `no`. Its exact container identity, original workspace labels and network ownership hash were verified before `docker start supabase_edge_runtime_local-app`. No replacement container, image pull, instance initialization or new service was requested.

The maintained `manage.py start` launcher was deliberately not invoked: it unconditionally runs `bootstrap_local.py --apply`, whose documented work includes auth setup and migration application. Neither that bootstrap nor any migration, schema reset, auth configuration, data mutation or application deployment ran. The user's default Docker context remains `desktop-linux`.

Final readback showed all 14 original project containers running; all 12 configured health checks were healthy. PostgREST and Edge Runtime have no configured Docker health check. The loopback Auth health endpoint and Studio returned HTTP 200. All six pre-existing daemon volumes remained present. The services and mounted runtime are left running for the owner's local-backend work.

## Actual schema differs from the Collect source candidate

Read-only SQL transactions against the retained database returned:

| Metadata check | Actual result |
| --- | --- |
| Public base tables | Exactly `account_profiles` |
| Installed application migration versions | `20261031141635`, `20261106205729` |
| Roles named `collect_%` | None |
| Functions named `collect_%` or `burimunsi_%` outside system schemas | None |
| `collections`, `members`, `payments`, `contributions`, `ledger_entries` | Absent |
| `admin_users`, `admin_principal_links`, `collect_deployment_identity` | Absent |

The retained project function-source directory contains `delete-account` and `send-sms-hook`; the existing Edge container binds that same directory. There is no deployed Collect business schema to query for BuriMunsi collection IDs or names. Member/account records were not printed.

The current Collect repository contains the business implementation, self-hosted deployment machinery and Admin transport. That source presence does not establish installation into this retained generic database. Its tracked examples still nominate the managed Supabase project unless an explicit deployment profile is supplied.

The supplied Drive folder's current generic 1.7.0 package is a separate source delivery. Its integration documentation supplies ordinary Supabase client/hosting primitives and explicitly leaves business tables and administrator authorization to the product. It was not installed or used to upgrade this retained environment.

## Concrete requirements for one shared local deployment

1. Prepare a reviewed, additive Collect schema/function deployment for the retained `local-app` database. Reconcile the existing neutral account schema and native Auth interfaces with Collect's business tables, least-privilege runtime roles, Admin principal links, deployment identity and shared ledger writer. Preserve the current keys, Auth identities, volumes and recovery custody. BuriMunsi must use those same Collect business records and permissions; do not introduce another instance, administrator universe or ledger.
2. Bind the maintained `collect-api`, `admin-api` and `collect-jobs` function sources to this same installation and its reviewed server configuration. The existing native Supabase paths are `/auth/v1`, `/rest/v1`, `/storage/v1`, `/realtime/v1`, `/graphql/v1` and `/functions/v1/<function>`. Collect member requests use `/functions/v1/collect-api/v1/...`; Collect Admin requests use `/functions/v1/admin-api/api/admin/...`. The existing frontend transport can expose logical `/v1/...` and `/api/admin/...` paths while forwarding to those exact functions.
3. Select and verify the real device-accessible HTTPS hostnames and certificate trust for this existing service. Only loopback HTTP is exported today; a phone's `127.0.0.1` is the phone itself. No phone-accessible HTTPS origin was identified in the inspected public configuration, and no TLS listener/domain was commissioned. Keep database and administration ports private.
4. Derive the clients and server from one canonical nine-field `collect.deployment.v1` profile and SHA-256. Its Supabase/member/Admin/public/callback origins and Auth issuer must agree with the existing installation's actual public routes, redirect/CORS/cookie settings and native session verification. The current Collect validator requires HTTPS DNS origins and derives the issuer as `<supabase_origin>/auth/v1`; it does not admit the present loopback HTTP URL as a release identity. Native BuriMunsi must receive the appropriate public configuration and verified user session while retaining the exact shared API prefix. Server credentials remain server-only.

These requirements describe the missing shared deployment work. Mounting and resuming the retained generic stack did not install Collect, bind BuriMunsi to a live ledger, or enable gateway uploads.

Owning references: `/Users/jeanbosco/Documents/Supabase/README_LOCAL_SETUP.md`, `tools/runtime/manage.py` in that workspace; Collect's `deploy/self-hosted/README.md`, `scripts/supabase/deployment_profile.py`, `lib/core/supabase/collect_supabase_configuration.dart`, `supabase/functions/_shared/serve.js`, and `deploy/platform-admin/src/supabase-transport.js`. Drive client/hosting references: [integration.md](https://drive.google.com/file/d/1kCUdMiq6mrbq1kExvydTHhJ0uFMcvqRC/view), [self-hosted.md](https://drive.google.com/file/d/1rqQ-xJMl1MLgzwOaN06_XIqIU-fGuTzn/view).
