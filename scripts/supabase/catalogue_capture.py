#!/usr/bin/env python3
"""Compile a fixed read-only PostgreSQL catalogue query and normalize its result.

Status: candidate; no provider transport or live qualification is established.

The program never opens a database connection, executes SQL, uses credentials,
reads row data or contacts a provider. It has two independent modes:

    python3 -m scripts.supabase.catalogue_capture --sql > catalogue-query.sql
    python3 -m scripts.supabase.catalogue_capture --response response.json \\
      --environment local_self_hosted --identity local-app \\
      --captured-at 2026-11-13T10:00:00Z --classifications classifications.json \\
      > LOCAL.json 2> LOCAL.capture-notice.json

For the cloud use --environment managed_cloud --identity rrlduytparvsjfmegalh.
The classifications file is an explicit JSON array using the exact entries
specified by catalogue_reconciliation.py, for example:
    [{"schema":"app","name":"users","classification":"business"}]

A separately authorized operator must capture the fixed SELECT in an actual
PostgreSQL 17 UTF-8 database using a single REPEATABLE READ READ ONLY transaction
with these exact LOCAL settings, followed by ROLLBACK:
    search_path=pg_catalog; TimeZone=UTC; DateStyle='ISO, YMD';
    IntervalStyle=postgres; bytea_output=hex; extra_float_digits=3;
    client_encoding=UTF8; standard_conforming_strings=on;
    quote_all_identifiers=off; statement_timeout='30s'; lock_timeout='5s'.
The SELECT checks those settings and returns a refusal rather than partial data
if the catalogue, descriptor, expression or result bounds are exceeded.

Save an explicitly supplied response as exactly [{"payload": {...}}], using the
JSONB value returned by the SELECT without deleting or adding fields. A provider
transport wrapper must be independently normalized to that single-row shape.
The builder validates the result and supplied classification list, emits the
comparator's exact metadata JSON on stdout, and writes a non-sensitive JSON
limitations notice to stderr. Preserve this notice: present_schemas and the
server version are not fields in the comparator-compatible metadata format.
Its query_sha256 hashes the local --sql output, including the trailing newline;
it does not prove that the supplied response came from that query.
The identity and capture time come only from
explicit caller arguments; they are not verified by this program. Both sides
must use the same classification list and capture/deparser settings.

The SQL enumerates ordinary/partitioned tables, including child partitions,
only in app/private/collect_sms, their visible non-dropped columns and their
pg_constraint records. It never returns default/constraint expressions: the
hashes are SHA-256 of the exact UTF-8 pg_get_expr/pg_get_constraintdef output.
The query reports which of the three schemas existed; absence is not silently
represented as an existing empty schema. Coverage is scoped, not independently
proven complete. The response can still be fabricated, stale, visibility-limited,
or normalized incorrectly by an external transport; checking counts cannot
prove otherwise. No data equality, schema parity, deployment or copy authority
is established. Indexes, standalone triggers, policies, functions, grants,
partition bounds, type definitions, Auth/Storage and row/object contents are
outside this format.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
from hashlib import sha256
import json
import re
import sys

if __package__:
    from . import catalogue_reconciliation as catalogue
else:
    import catalogue_reconciliation as catalogue

CAPTURE_FORMAT = "collect.supabase.catalogue-capture.v1"
MAX_EXPRESSION_BYTES = 16384
# Leaves room for the caller's classification list and JSON encoding overhead.
MAX_CAPTURE_PAYLOAD_BYTES = 4 * 1024 * 1024 - 4096
MAX_RESPONSE_BYTES = catalogue.MAX_INPUT_BYTES

# There are no caller-controlled identifiers, expressions, clauses or values in
# this query. LIMIT n+1 detects overflow rather than silently truncating it.
# The guard bounds the JSON aggregate and never returns raw expression strings.
SQL = r'''WITH
context AS MATERIALIZED (
 SELECT pg_catalog.current_setting('server_version_num')::text AS server_version_num,
  pg_catalog.current_setting('server_encoding')::text AS server_encoding,
  pg_catalog.current_setting('client_encoding')::text AS client_encoding,
  pg_catalog.current_setting('search_path')::text AS search_path,
  pg_catalog.current_setting('TimeZone')::text AS timezone,
  pg_catalog.current_setting('DateStyle')::text AS date_style,
  pg_catalog.current_setting('IntervalStyle')::text AS interval_style,
  pg_catalog.current_setting('bytea_output')::text AS bytea_output,
  pg_catalog.current_setting('extra_float_digits')::text AS extra_float_digits,
  pg_catalog.current_setting('standard_conforming_strings')::text AS standard_conforming_strings,
  pg_catalog.current_setting('quote_all_identifiers')::text AS quote_all_identifiers,
  pg_catalog.current_setting('statement_timeout')::text AS statement_timeout,
  pg_catalog.current_setting('lock_timeout')::text AS lock_timeout,
  pg_catalog.current_setting('transaction_read_only')::text AS transaction_read_only,
  pg_catalog.current_setting('transaction_isolation')::text AS transaction_isolation
),
context_guard AS MATERIALIZED (
 SELECT c.*,
  (c.server_version_num ~ '^17[0-9]{4}$' AND c.server_encoding='UTF8' AND c.client_encoding='UTF8'
   AND c.search_path='pg_catalog' AND c.timezone='UTC' AND c.date_style='ISO, YMD'
   AND c.interval_style='postgres' AND c.bytea_output='hex' AND c.extra_float_digits='3'
   AND c.standard_conforming_strings='on' AND c.quote_all_identifiers='off'
   AND c.statement_timeout='30s' AND c.lock_timeout='5s'
   AND c.transaction_read_only='on' AND c.transaction_isolation='repeatable read') AS context_ok
 FROM context c
),
namespaces AS MATERIALIZED (
 SELECT n.oid,n.nspname::text AS schema FROM context_guard g CROSS JOIN pg_catalog.pg_namespace n
 WHERE g.context_ok IS TRUE AND n.nspname IN ('app','private','collect_sms')
),
relations AS MATERIALIZED (
 SELECT n.schema,c.relname::text AS name,c.relkind::text AS kind,c.relispartition AS is_partition,c.oid
 FROM namespaces n JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid
 WHERE c.relkind IN ('r','p')
 ORDER BY n.schema COLLATE pg_catalog."C",c.relname::text COLLATE pg_catalog."C"
 LIMIT 10001
),
columns AS MATERIALIZED (
 SELECT r.oid AS relation_oid,a.attname::text AS name,a.attnum::text AS position,
  tn.nspname::text AS type_schema,t.typname::text AS type_name,t.typtype::text AS type_kind,
  a.atttypmod::text AS type_modifier,a.attnotnull AS not_null,a.attidentity::text AS identity,
  a.attgenerated::text AS generated,
  CASE WHEN a.attcollation=0 THEN NULL ELSE pg_catalog.jsonb_build_object('schema',cn.nspname::text,'name',co.collname::text) END AS collation,
  CASE WHEN d.oid IS NULL THEN NULL
   WHEN pg_catalog.octet_length(pg_catalog.pg_get_expr(d.adbin,d.adrelid))<=16384
   THEN pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_expr(d.adbin,d.adrelid),'UTF8')),'hex')
   ELSE NULL END AS default_sha256,
  CASE WHEN d.oid IS NULL THEN true
   ELSE COALESCE(pg_catalog.octet_length(pg_catalog.pg_get_expr(d.adbin,d.adrelid))<=16384,false) END AS expression_ok
 FROM relations r JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid
 JOIN pg_catalog.pg_type t ON t.oid=a.atttypid JOIN pg_catalog.pg_namespace tn ON tn.oid=t.typnamespace
 LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 LEFT JOIN pg_catalog.pg_collation co ON co.oid=a.attcollation
 LEFT JOIN pg_catalog.pg_namespace cn ON cn.oid=co.collnamespace
 WHERE a.attnum>0 AND NOT a.attisdropped
 ORDER BY r.schema COLLATE pg_catalog."C",r.name COLLATE pg_catalog."C",a.attnum
 LIMIT 40001
),
constraints AS MATERIALIZED (
 SELECT r.oid AS relation_oid,x.conname::text AS name,x.contype::text AS kind,
  x.condeferrable AS deferrable,x.condeferred AS initially_deferred,x.convalidated AS validated,
  CASE WHEN pg_catalog.octet_length(pg_catalog.pg_get_constraintdef(x.oid))<=16384
   THEN pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_constraintdef(x.oid),'UTF8')),'hex')
   ELSE NULL END AS definition_sha256,
  COALESCE(pg_catalog.octet_length(pg_catalog.pg_get_constraintdef(x.oid))<=16384,false) AS definition_ok
 FROM relations r JOIN pg_catalog.pg_constraint x ON x.conrelid=r.oid
 ORDER BY r.schema COLLATE pg_catalog."C",r.name COLLATE pg_catalog."C",x.conname::text COLLATE pg_catalog."C"
 LIMIT 40001
),
bounds AS MATERIALIZED (
 SELECT (SELECT pg_catalog.count(*) FROM relations) AS relation_count,
  (SELECT pg_catalog.count(*) FROM columns) AS column_count,
  (SELECT pg_catalog.count(*) FROM constraints) AS constraint_count,
  NOT EXISTS(SELECT 1 FROM columns GROUP BY relation_oid HAVING pg_catalog.count(*)>1600) AS columns_per_relation_ok,
  NOT EXISTS(SELECT 1 FROM constraints GROUP BY relation_oid HAVING pg_catalog.count(*)>10000) AS constraints_per_relation_ok,
  NOT EXISTS(SELECT 1 FROM columns WHERE NOT expression_ok) AS expressions_ok,
  NOT EXISTS(SELECT 1 FROM constraints WHERE NOT definition_ok) AS definitions_ok
),
validity AS MATERIALIZED (
 SELECT c.*,b.*,
  (b.relation_count>0 AND b.relation_count<=10000 AND b.column_count+b.constraint_count<=40000
   AND b.columns_per_relation_ok AND b.constraints_per_relation_ok AND b.expressions_ok AND b.definitions_ok) AS bounds_ok
 FROM context_guard c CROSS JOIN bounds b
),
assembled AS MATERIALIZED (
 SELECT pg_catalog.jsonb_build_object(
  'format','collect.supabase.catalogue-capture.v1','status','ok',
  'context',pg_catalog.to_jsonb(c),
  'covered_schemas',pg_catalog.jsonb_build_array('app','private','collect_sms'),
  'present_schemas',COALESCE((SELECT pg_catalog.jsonb_agg(n.schema ORDER BY n.schema COLLATE pg_catalog."C") FROM namespaces n),'[]'::pg_catalog.jsonb),
  'counts',pg_catalog.jsonb_build_object('relations',b.relation_count,'columns',b.column_count,'constraints',b.constraint_count),
  'relations',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'schema',r.schema,'name',r.name,'kind',r.kind,'is_partition',r.is_partition,
   'columns',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'name',a.name,'position',a.position,'type_schema',a.type_schema,'type_name',a.type_name,
    'type_kind',a.type_kind,'type_modifier',a.type_modifier,'not_null',a.not_null,
    'identity',a.identity,'generated',a.generated,'collation',a.collation,
    'default_sha256',a.default_sha256
    ) ORDER BY a.position::integer) FROM columns a WHERE a.relation_oid=r.oid),'[]'::pg_catalog.jsonb),
   'constraints',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'name',x.name,'kind',x.kind,'definition_sha256',x.definition_sha256,
    'deferrable',x.deferrable,'initially_deferred',x.initially_deferred,'validated',x.validated
    ) ORDER BY x.name COLLATE pg_catalog."C") FROM constraints x WHERE x.relation_oid=r.oid),'[]'::pg_catalog.jsonb)
   ) ORDER BY r.schema COLLATE pg_catalog."C",r.name COLLATE pg_catalog."C"),'[]'::pg_catalog.jsonb) FROM relations r)
 ) AS payload
 FROM context c CROSS JOIN bounds b CROSS JOIN validity v WHERE v.context_ok AND v.bounds_ok
)
SELECT CASE
 WHEN v.context_ok IS DISTINCT FROM true THEN pg_catalog.jsonb_build_object('format','collect.supabase.catalogue-capture.v1','status','refused','reason','capture_context')
 WHEN v.bounds_ok IS DISTINCT FROM true THEN pg_catalog.jsonb_build_object('format','collect.supabase.catalogue-capture.v1','status','refused','reason','capture_bound')
 WHEN a.payload IS NULL OR pg_catalog.octet_length(a.payload::text)>4190208 THEN pg_catalog.jsonb_build_object('format','collect.supabase.catalogue-capture.v1','status','refused','reason','response_bound')
 ELSE a.payload END AS payload
FROM validity v LEFT JOIN assembled a ON true;'''

CONTEXT = {
    "server_encoding": "UTF8", "client_encoding": "UTF8", "search_path": "pg_catalog",
    "timezone": "UTC", "date_style": "ISO, YMD", "interval_style": "postgres",
    "bytea_output": "hex", "extra_float_digits": "3", "standard_conforming_strings": "on",
    "quote_all_identifiers": "off", "statement_timeout": "30s", "lock_timeout": "5s",
    "transaction_read_only": "on", "transaction_isolation": "repeatable read",
}


class CaptureInputError(ValueError):
    """A fixed, non-sensitive normalization failure code."""


def _exact(value, keys):
    return isinstance(value, dict) and set(value) == set(keys)


def _bounded_payload(response):
    if (not isinstance(response, list) or len(response) != 1
            or not _exact(response[0], ("payload",)) or not isinstance(response[0]["payload"], dict)):
        raise CaptureInputError("invalid_response_shape")
    payload = response[0]["payload"]
    if (_exact(payload, ("format", "status", "reason")) and payload["format"] == CAPTURE_FORMAT
            and payload["status"] == "refused" and isinstance(payload["reason"], str)
            and payload["reason"] in ("capture_context", "capture_bound", "response_bound")):
        raise CaptureInputError("capture_refused_" + payload["reason"])
    if payload.get("format") != CAPTURE_FORMAT or payload.get("status") != "ok":
        raise CaptureInputError("capture_refused_or_invalid")
    if not _exact(payload, ("format", "status", "context", "covered_schemas", "present_schemas", "counts", "relations")):
        raise CaptureInputError("invalid_capture_fields")
    context = payload["context"]
    if (not _exact(context, (*CONTEXT, "server_version_num"))
            or any(context[key] != value for key, value in CONTEXT.items())
            or not isinstance(context["server_version_num"], str)
            or re.fullmatch(r"17[0-9]{4}", context["server_version_num"]) is None):
        raise CaptureInputError("capture_context_mismatch")
    covered, present = payload["covered_schemas"], payload["present_schemas"]
    if (not isinstance(covered, list) or len(covered) != 3
            or any(not isinstance(name, str) for name in covered) or set(covered) != catalogue.SCHEMAS
            or not isinstance(present, list) or len(present) > 3
            or any(not isinstance(name, str) for name in present)
            or len(set(present)) != len(present) or not set(present).issubset(catalogue.SCHEMAS)):
        raise CaptureInputError("capture_schema_coverage_invalid")
    counts, relations = payload["counts"], payload["relations"]
    if (not _exact(counts, ("relations", "columns", "constraints"))
            or any(type(counts[key]) is not int or counts[key] < 0 for key in counts)
            or not isinstance(relations, list) or len(relations) != counts["relations"]
            or not 0 < len(relations) <= catalogue.MAX_RELATIONS
            or counts["columns"] + counts["constraints"] > catalogue.MAX_DESCRIPTORS):
        raise CaptureInputError("capture_count_mismatch")
    columns = constraints = 0
    for relation in relations:
        if (not isinstance(relation, dict) or not isinstance(relation.get("schema"), str)
                or relation["schema"] not in present or not isinstance(relation.get("columns"), list)
                or not isinstance(relation.get("constraints"), list)):
            raise CaptureInputError("capture_relation_invalid")
        columns += len(relation["columns"])
        constraints += len(relation["constraints"])
    if columns != counts["columns"] or constraints != counts["constraints"]:
        raise CaptureInputError("capture_count_mismatch")
    if len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")) > MAX_CAPTURE_PAYLOAD_BYTES:
        raise CaptureInputError("capture_payload_bound")
    return payload


def build_metadata(response, *, environment, identity, captured_at, classifications):
    """Return comparator-compatible JSON; no identity or provenance is attested."""
    payload = _bounded_payload(response)
    snapshot = deepcopy({"format": catalogue.FORMAT, "environment": environment, "identity": identity,
                         "captured_at": captured_at, "covered_schemas": payload["covered_schemas"],
                         "classifications": classifications, "relations": payload["relations"]})
    if (environment, identity) not in (("local_self_hosted", "local-app"),
                                        ("managed_cloud", catalogue.PROJECT)):
        raise CaptureInputError("identity_argument_invalid")
    catalogue.validate(snapshot, environment=environment, identity=identity)
    if len((json.dumps(snapshot, indent=2, ensure_ascii=True) + "\n").encode("utf-8")) > catalogue.MAX_INPUT_BYTES:
        raise CaptureInputError("metadata_output_bound")
    return snapshot


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sql", action="store_true", help="Print the fixed read-only catalogue SELECT")
    parser.add_argument("--response", help="Explicit captured response JSON file")
    parser.add_argument("--environment", choices=("local_self_hosted", "managed_cloud"))
    parser.add_argument("--identity")
    parser.add_argument("--captured-at")
    parser.add_argument("--classifications", help="Explicit classification JSON array file")
    args = parser.parse_args(argv)
    options = (args.response, args.environment, args.identity, args.captured_at, args.classifications)
    if args.sql:
        if any(value is not None for value in options):
            parser.error("--sql does not accept capture inputs")
        print(SQL)
        return 0
    if any(value is None for value in options):
        parser.error("provide all five explicit capture inputs or --sql")
    try:
        response = catalogue.load_metadata(args.response)
        classifications = catalogue.load_metadata(args.classifications)
        payload = _bounded_payload(response)
        metadata = build_metadata(response, environment=args.environment, identity=args.identity,
                                  captured_at=args.captured_at, classifications=classifications)
        print(json.dumps(metadata, indent=2, ensure_ascii=True))
        print(json.dumps({"status": "metadata_only", "query_sha256": sha256((SQL + "\n").encode("utf-8")).hexdigest(),
                          "server_version_num": payload["context"]["server_version_num"],
                          "present_schemas": sorted(payload["present_schemas"]),
                          "missing_schemas": sorted(catalogue.SCHEMAS - set(payload["present_schemas"])),
                          "schema_presence_in_comparator_metadata": False, "query_origin_independently_verified": False,
                          "provenance_independently_verified": False, "database_identity_independently_verified": False,
                          "catalogue_completeness_independently_verified": False, "data_equality_verified": False,
                          "data_copy_authorized": False, "cutover_authorized": False}), file=sys.stderr)
        return 0
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        code = str(exc) if isinstance(exc, (CaptureInputError, catalogue.CatalogueInputError)) else "malformed_or_unreadable_input"
        print(json.dumps({"status": "invalid_input", "error_code": code, "data_equality_verified": False,
                          "data_copy_authorized": False, "cutover_authorized": False}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
