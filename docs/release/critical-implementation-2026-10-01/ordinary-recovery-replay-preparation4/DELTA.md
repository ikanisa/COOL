# Complete captured recovery3 delta

All20 category keys are present in both catalogs;7 differ and13 are exactly equal.
There are no ordering-only differences. complete-captured-delta.json contains each
category's complete content hashes and every source-only/restored-only row.

| Category | Source → restored rows | Exact observed difference |
| --- | --- | --- |
| schemas |17 →17|graphql and graphql_public lack the four non-owner source USAGE entries; postgres's USAGE grant option is absent. |
| functions |381 →381|Six graphql extension functions retain identical identity/owner/attributes/body/definition; only their ACL field lacks EXECUTE for postgres, anon, authenticated and service_role. |
| relations |503 →502|graphql.seq_schema_version lacks source SELECT/UPDATE/USAGE for those four roles; net.collect_receipt_http_response_id is missing. |
| columns |2042 →2041|Only index metadata net.collect_receipt_http_response_id.id bigint is missing. |
| indexes |360 →359|Only net.collect_receipt_http_response_id is missing; source valid/ready/live flags are true and definition SHA is9328daab9410518dca5727ad8889381de3d298d548b204d8bed7fd1437a90df3. |
| dependencies |4826 →4825|Only the index's automatic dependency on net._http_response.id is missing. |
| constraints |712 →712|Only two definition hashes differ; all identities and validation/deferral flags match. |

Exactly equal categories: database, default_acls, event_triggers, extensions,
format, memberships, migrations, policies, roles, server, settings, triggers and
types. The fixed graphql_public.graphql wrapper is now exact. All30 role attributes,
23 memberships and8 settings are exact. The observed11 changed paired rows plus
four missing metadata rows are fully explained by the two schemas, six functions,
one sequence, two CHECKs and one index; the index accounts for all four omissions.

The uncompressed custom archive contains no transport index name, and the actual
TOC contains no index or six graphql function/sequence definition/ACL entries.
Captured dependencies prove the extension membership, including pg_net's underlying
table; no name/ACL inference substitutes for that proof. The frozen grant hook and
captured schema ACLs support the explicitly named grants. Every default ACL, data,
history and existing archive ACL entry remains intact.

Dump CHECK deparse preserved source text hashes, but reparsing flattened a nested
AND tree. The notification source BETWEEN grouping deparsed to a nested left
conjunction; the restored CHECK flattened that left conjunction. Provider source
BETWEEN grouping similarly became one flat conjunction alongside its regex. The
captured hashes and original migration bytes precisely identify the two cases.
The proposed transactional re-creation restores the original expressions without
normalizing any comparator or accepting other CHECKs. This diagnosis is based on
captured metadata and frozen source; successful repair remains unverified.

Recovery3 failed after15 passes in78.539 seconds. pg_restore completed; restored18
projection proof and forward85 replay were not reached. Both containers were
removed with cleanup_errors empty. This retained failure does not establish full
BE-08, ARC-08 or ARC-11 closure.
