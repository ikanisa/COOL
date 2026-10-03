# Effective catalog domain and caller inventory

Acceptance: **draft-with-open-mappings**. This is lexical inventory and catalog evidence; all domain maintenance owners require review.

Catalog migrations: 209; source migrations: 209. Source-only versions: none.

| Domain | Schemas | Relations | Functions | Types | Database owner | Caller candidates |
|---|---:|---:|---:|---:|---|---|
| admin-access | 1 | 24 | 21 | 18 | postgres | admin-dart, operational-script-tool |
| android-gateway | 4 | 58 | 58 | 30 | postgres | admin-dart, edge-typescript, operational-script-tool |
| authentication-security | 2 | 42 | 56 | 28 | postgres | edge-typescript |
| automation | 1 | 5 | 4 | 4 | postgres | none found |
| bank-reconciliation | 0 | 55 | 46 | 28 | postgres | admin-dart, edge-typescript, operational-script-tool |
| collections-membership | 0 | 59 | 35 | 34 | postgres | admin-dart, member-shared-dart, operational-script-tool |
| device-integrity | 1 | 13 | 8 | 8 | postgres | edge-typescript, operational-script-tool |
| member-actions | 1 | 3 | 10 | 2 | postgres | none found |
| member-profile | 1 | 10 | 16 | 8 | postgres | admin-dart, member-shared-dart, operational-script-tool |
| notification | 0 | 34 | 27 | 18 | postgres | admin-dart, edge-typescript, member-shared-dart, operational-script-tool, operator-worker-tool |
| operations-governance | 1 | 91 | 32 | 56 | postgres | none found |
| operator-audit | 1 | 11 | 21 | 6 | postgres | admin-dart, operational-script-tool |
| payments-ledger | 0 | 78 | 44 | 32 | postgres | admin-dart, edge-typescript, member-shared-dart, operational-script-tool |
| platform:auth | 1 | 111 | 4 | 64 | postgres | none found |
| platform:cron | 1 | 7 | 7 | 4 | supabase_admin | none found |
| platform:extensions | 1 | 2 | 55 | 4 | postgres, supabase_admin | none found |
| platform:graphql | 1 | 1 | 6 | 0 | supabase_admin | none found |
| platform:graphql_public | 1 | 0 | 1 | 0 | supabase_admin | none found |
| platform:net | 1 | 7 | 12 | 12 | supabase_admin | none found |
| platform:pgbouncer | 1 | 0 | 1 | 0 | pgbouncer, supabase_admin | none found |
| platform:realtime | 1 | 0 | 0 | 0 | supabase_admin | none found |
| platform:storage | 1 | 0 | 0 | 0 | postgres | none found |
| platform:supabase_migrations | 1 | 2 | 0 | 2 | postgres | none found |
| platform:vault | 1 | 4 | 5 | 4 | supabase_admin | none found |
| privacy | 1 | 26 | 14 | 16 | postgres | member-shared-dart, operational-script-tool |
| receipt-actions | 1 | 5 | 27 | 4 | postgres | admin-dart, edge-typescript |
| receipt-delivery | 1 | 145 | 121 | 90 | postgres | admin-dart, edge-typescript, operational-script-tool, operator-worker-tool |
| receipt-history | 1 | 0 | 2 | 0 | postgres | none found |
| receipt-operations | 1 | 51 | 37 | 26 | postgres | admin-dart, edge-typescript, operator-worker-tool |
| receipt-policy | 1 | 4 | 11 | 4 | postgres | operational-script-tool |
| receipt-retention-controls | 1 | 4 | 10 | 4 | postgres | admin-dart |
| receipt-source-projection | 1 | 17 | 7 | 12 | postgres | none found |
| receipt-successors | 1 | 55 | 47 | 32 | postgres | admin-dart, edge-typescript, operational-script-tool |
| receipt-supervisor | 1 | 10 | 15 | 6 | postgres | edge-typescript |
| receipt-telemetry | 1 | 20 | 13 | 14 | postgres | admin-dart |
| receipt-worker-history | 1 | 12 | 31 | 12 | postgres | none found |
| roster | 0 | 0 | 22 | 0 | postgres | admin-dart, edge-typescript, member-shared-dart, operational-script-tool |
| runtime-configuration | 0 | 29 | 10 | 20 | postgres | admin-dart, edge-typescript, member-shared-dart, operational-script-tool, operator-worker-tool |
| unclassified | 2 | 2 | 66 | 4 | pg_database_owner, postgres | admin-dart, edge-typescript, member-shared-dart, operational-script-tool |

Maintained sources: 664. Caller sites: 718. Exact catalog body hash matches: 776/902 functions.
Unclassified objects: 74. Dynamic/unresolved callers: 58.

See schema-domain-map.json for every catalog row, owner, ACL, source hash binding, caller index and SQL candidate. See gaps.json for unresolved work. PostgreSQL dependencies are preserved independently; they are not a complete procedural call graph.
