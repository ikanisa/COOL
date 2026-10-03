# Ordinary installer / receipt transport owner review

## Result and scope

The finite ACL tail passed **50 named controls**, including **30 actual SQL permission denials** under `SET ROLE anon`, `authenticated` and `service_role`. The owned network-none container was removed; application source and consumed proposal inputs have zero drift. This is a candidate prerequisite proof, **not** a whole migration185 replay, provider execution, or L08/L23 release acceptance.

- [Terminal ACL proof](acl-tail-result.json), [executed SQL and output](acl_tail_owned_probe/queries.log).
- [Preserved original ordinary-owner42501](../platform-owned-index-preflight1/result.json).
- [Earlier20 accepted controls and preserved probe typo](attempt2-required-column-fixture/result.json): missing/compatible platform index; wrong-column, partial and expression index refusal; bounded original sampler and duplicate conflict. The final tail executes the changed privacy validator and required-column cases; it does not relabel the failed earlier command as a pass.
- [First inherited-read fixture failure](attempt1-read-role-fixture/result.json) and [nologin-role fixture failure](acl-tail-attempt1-role-fixture/acl-tail-result.json) are retained.

## Concrete defects

1. The application's `CREATE INDEX IF NOT EXISTS` still requires table ownership even when the index already exists. Ordinary `postgres NOSUPERUSER` cannot index platform-owned `net._http_response`.
2. The original schema validator checks types only. It cannot distinguish a suitable bounded ID index from a wrong/partial/expression index or verify that the security definer can read its seven required columns.
3. The retained platform has PUBLIC ALL privileges on both net tables, and PUBLIC/client schema USAGE. Table ACL removal alone also leaves possible column ACLs. The application should reject an exposed prerequisite rather than treating it as acceptable private transport storage.

The source sampler uses only response `id`, `status_code`, `content`, `timed_out`, `error_msg`, `created`, and queue `id`. It reads at most two matching responses, never outputs raw headers/URLs/errors, bounds inspected content, and distinguishes duplicate responses.

## Proposed correction — no active source changed

- [Exact application migration diff](proposed-migration.diff), [complete proposed migration](proposed-migration.sql).
- [Owner-only platform prerequisite](proposed-platform-prerequisites.sql).
- [Local ordinary-installer fixture diff](proposed-installer.diff).

The application skips index DDL when the named index exists. If it is absent and the installer is not the table owner, it refuses with `receipt_transport_platform_index_prerequisite` /55000. It strictly validates the exact nonunique btree ID index, table/column types, schema USAGE and effective required-column SELECT, and absence of untrusted table/column privileges. Unsatisfied reads, index shape or private ACLs refuse with `receipt_transport_platform_read_prerequisite` /55000. It does not drop platform indexes, change platform owners, SET ROLE, or grant itself permissions.

The platform table owner prepares the index, revokes table **and every column** privileges from PUBLIC/anon/authenticated/service_role/postgres, then grants postgres schema USAGE and the seven SELECT columns. No INSERT/UPDATE/DELETE or broad table SELECT is added. Its ownership/dispatch guards refuse an ordinary caller or undeclared platform invoker function. Existing trusted functions and the C worker are preserved.

## Trusted platform compatibility and limits

[Read-only retained worker catalog](retained-platform-worker-readonly-catalog.log) establishes that the real pg_net0.20.0 worker runs as `supabase_admin`; existing `net.http_post` and `net.http_get` are SECURITY DEFINER owned by that same platform role with `search_path=net`. `http_delete` is an invoker and is not the receipt POST path. The finite clone retains the worker owner/liveness and these function owner/definer/search-path values after the ACL proposal. It does not invoke an HTTP function or prove request delivery.

A fresh `CREATE EXTENSION` has invoker get/post functions. The clone and proposed **local rehearsal only** fixture explicitly reproduce the retained trusted get/post metadata before owner preparation. This is a disclosed platform fixture input, not an application change or instruction to introduce definer authority on an unknown hosted platform. See [upstream pinned worker identity code](https://github.com/supabase/pg_net/blob/v0.20.0/src/worker.c#L221) and [pinned invoker POST definition](https://github.com/supabase/pg_net/blob/v0.20.0/sql/pg_net.sql#L143); the retained catalog governs this particular platform.

[Read-only retained role catalog](retained-platform-readonly-catalog.log) shows postgres already inherits `pg_read_all_data`. The proposal normalizes **direct** postgres ACLs to seven SELECT columns; it does not revoke this shared membership, and therefore does not claim seven-column-only **effective** access for retained postgres. The clone alone removes that inherited read role for the exact minimum-profile sampler/missing-column proof. This limitation remains explicit. No shared database role or table was mutated.

[Read-only retained client ACL catalog](retained-platform-reader-readonly-catalog.log) records the original PUBLIC table grants and schema USAGE. In the clone, PUBLIC table grants plus explicit stale column grants form a positive raw-read control before preparation. All30 SELECT/INSERT/UPDATE/DELETE attempts afterward return42501, including service_role despite its RLS bypass. The ACL proof uses the actual database roles via SET ROLE because they are NOLOGIN; it is not an Auth/JWT or API gateway test.

## Integration instructions for root

1. The diff base is `e3e1e56a32160db25d903d6cb436279c47e684b1b7e594ff342071e9882c1096`. Guard that base before applying; if changed, reconcile the current owner's source. At final packaging the active migration already hashes to `7307a061e03243b82bd98d94eff5b2b83dc457dcb8dae47580c642ccc144191d`, exactly the proposed migration. This later integration is separate from the immutable finite proof; this lane wrote no active migration/helper.
2. Review/apply only `proposed-migration.diff` to the peer-owned migration after its ownership boundary is resolved.
3. In the existing ordinary-installer local platform setup, declare the exact retained platform get/post metadata, then execute `proposed-platform-prerequisites.sql` as the table owner before demoting postgres. `proposed-installer.diff` is the exact candidate for the captured helper. On any other platform, verify the actual trusted dispatcher/worker prerequisites first; the proposal refuses invoker dispatch rather than adding authority.
4. Run the canonical ordinary installer once against the integrated frozen candidate. The finite proof does not replace that gate. Do not change shared154 or platform role memberships as part of this correction.

Final paths/hashes are in [validation.json](validation.json). No process is left running in this lane.
