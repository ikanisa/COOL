#!/usr/bin/env python3
"""Verify the published history optimization in the complete reviewed local set.

Replay all current staged migrations in isolated schema154 databases. Genuine
posting workflows and independent expected rows verify every sort, scope and
depth. The accepted four-arm comparison remains immutable; only its baseline
logical scan/buffer counts are reused, never independently generated public-ID
labels/revision hashes or its timing as an SLO.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import traceback

import current_generated_history_index_candidate_uat as C
import current_generated_query_benchmark_uat as K
import data_correctness_sql_positive_history_uat as P
import staged_bundle_upgrade_uat as B
from local_schema_uat import ROOT, U, isolated, save

MIGRATION = ROOT / "supabase/migrations/20261001095000_member_history_global_keyset_indexes.sql"


def queue_and_intents(db, count, report, case):
    """Actual bounded recent-intent and notification APIs, including rollback-only shrink."""
    D = K.D
    plans = report / "queue-intent-plans"
    plans.mkdir()
    metrics = []
    sender = D.scalar(db, f"select to_jsonb(momo_number_hash) from public.profiles where id='{D.ACTOR}';")
    U.call(db, f"select jsonb_agg(to_jsonb(t)) from generate_series(1,{count})n cross join lateral "
        f"public.create_contribution_intent('{D.GROUP}',10000+n,{D.literal(sender)})t", D.ACTOR, D.SESSION)
    U.psql(db, "analyze public.payment_intents;")
    ids = D.scalar(db, f"select jsonb_agg(id::text order by created_at desc,id) from public.payment_intents where contributor_user_id='{D.ACTOR}';")
    protected = P.financial(db)
    for name, uid, sid, requested in [("recent",D.ACTOR,D.SESSION,None),
        ("exact-old",D.ACTOR,D.SESSION,ids[-1]),("forged",D.ACTOR,D.SESSION,D.MISSING),
        ("foreign",D.PEER,K.PEER_SID,ids[-1])]:
        def probe(name=name,uid=uid,sid=sid,requested=requested):
            doc, metric = K.measured(db,"select public.list_current_member_recent_intents("
                + ("null" if requested is None else D.literal(requested)) + ")",plans,"intent-"+name,uid,sid)
            wanted = ids[:50] if name=="recent" else [ids[-1]] if name=="exact-old" else []
            P.require([item["id"] for item in doc["items"]]==wanted
                and doc["pending_count"]==(0 if uid!=D.ACTOR else count),dict(expected_ids=wanted,actual=doc))
            metrics.append(metric)
            return dict(complete_pending_count=doc["pending_count"],bounded_returned=len(doc["items"]))
        case("current recent-intent ownership/count " + name,probe)
    case("current intent reads preserve every financial/control fingerprint",lambda:
         P.require(P.financial(db)==protected,{}))
    queue = P.financial(db)
    for sort, ordering in (("created_at_desc","created_at desc,id"),("created_at_asc","created_at,id")):
        ids = D.scalar(db,"select jsonb_agg(id::text order by " + ordering + ")from public.notification_events e "
            "where exists(select 1 from public.profiles p where p.id=e.user_id);") or []
        for depth,offset in dict(first=0,middle=len(ids)//2,deep=max(0,len(ids)-25)).items():
            def probe(sort=sort,depth=depth,offset=offset,ids=ids):
                doc,metric=K.measured(db,f"select public.admin_list_notifications(null,null,25,{offset},'{sort}')",
                    plans,"notification-"+sort+"-"+depth,P.MAKER,P.MAKER_SID,"aal2")
                P.require(doc["total"]==len(ids)and[row["id"]for row in doc["rows"]]==ids[offset:offset+25],
                    dict(actual=doc,offset=offset))
                metrics.append(metric)
                return dict(complete_count=doc["total"],offset=offset,returned=len(doc["rows"]))
            case("current notification queue " + sort + " " + depth,probe)
    case("current notification reads preserve every financial/control fingerprint",lambda:
         P.require(P.financial(db)==queue,{}))
    def shrink():
        before=D.clone_snapshot(db)
        doc=D.scalar(db,"begin;delete from public.notification_events;"+P.actor(P.MAKER,P.MAKER_SID)+
            f"select public.admin_list_notifications(null,null,25,{max(0,len(ids)-25)},'created_at_desc');rollback;")
        return P.require(doc==dict(rows=[],total=0)and D.clone_snapshot(db)==before,
            dict(exact_zero_total=True,fixture="Rollback-only queue deletion, no production deletion API claimed"))
    case("current queue shrink returns known zero and restores every row",shrink)
    save(report / "queue-intent-measurements.json", metrics)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reviewed-stages", type=Path, required=True)
    parser.add_argument("--comparison", type=Path, required=True)
    args = parser.parse_args()
    packet = args.output.resolve()
    if packet.exists() or not packet.is_relative_to(ROOT / "docs/release/generated-query-benchmark-2026-10-01"):
        parser.error("Fresh generated-query evidence directory required")
    packet.mkdir(parents=True, mode=0o700)
    proof_path = args.reviewed_stages.resolve(strict=True)
    proof = json.loads(proof_path.read_bytes())
    comparison_path = args.comparison.resolve(strict=True)
    comparison = json.loads(comparison_path.read_bytes())
    stages = [(ROOT / "supabase/migrations" / name,
               (ROOT / "supabase/migrations" / name).read_bytes()) for name in B.STAGES]
    stage_hashes = {path.name: K.sha(path) for path, _ in stages}
    migrations = {path.name: K.sha(path) for path in sorted((ROOT / "supabase/migrations").glob("*.sql"))}
    P.require(proof.get("status") == "pass" and proof.get("source_migration_sha256") == stage_hashes
              and proof.get("all_source_tables_catalog_cron_preserved")
              and proof.get("isolated_database_removed") and len(migrations) == 154 + len(stages)
              and comparison.get("status") == "pass_scoped" and comparison.get("source_inputs_unchanged")
              and [row["volume"] for row in comparison["volume_results"]] == [1000, 10000]
              and all(row["failed"] == 0 and row["source_preserved"] and row["clone_removed"]
                      for row in comparison["volume_results"]), {"phase": "before_sql"})
    inputs = [Path(__file__).resolve(), Path(C.__file__).resolve(), Path(K.__file__).resolve(),
              Path(P.__file__).resolve(), Path(B.__file__).resolve(),
              ROOT / "scripts/tests/data_correctness_sql_uat.py", ROOT / "scripts/tests/local_schema_uat.py",
              ROOT / "scripts/tests/local_offline_verification.py", ROOT / "scripts/tests/shadow_supervisor_uat.py",
              proof_path, comparison_path, P.CATALOG_SOURCE, B.PERMISSION_CATALOG_SOURCE]
    inputs += sorted((ROOT / "supabase/migrations").glob("*.sql"))
    for count in (1000, 10000):
        folder = comparison_path.parent / f"volume-{count}"
        inputs += [folder / "result.json", folder / "baseline/results.json", folder / "final-candidate-catalog.json"]
        P.require(K.sha(folder / "result.json") == next(row["result_sha256"] for row in
                  comparison["volume_results"] if row["volume"] == count), {})
    hashes = {str(path.relative_to(ROOT)): K.sha(path) for path in inputs}
    for path in inputs:
        target = packet / "runner-sources" / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
        P.require(K.sha(path) == K.sha(target) == hashes[str(path.relative_to(ROOT))], {})
    migration_body = MIGRATION.read_text()
    guard_start, guard_end = migration_body.index("do $integrity$"), migration_body.index("$integrity$;")
    integrity_guard = migration_body[guard_start:guard_end + len("$integrity$;")]
    result = dict(status="running", kind="published_history_current_set_actual_api_acceptance",
                  started_at=dt.datetime.now(dt.timezone.utc).isoformat(), source_inputs=hashes,
                  all_migration_inputs_before=migrations, stage_count=len(stages),
                  published_migration_sha256=K.sha(MIGRATION), reviewed_stage_proof_sha256=K.sha(proof_path),
                  accepted_comparison_sha256=K.sha(comparison_path), volume_results=[],
                  source_database_written=False, provider_called=False, hosted_called=False,
                  latency_slo_claimed=False, full_summary_scan_removed=False,
                  independently_generated_public_ids_compared_literally=False)
    save(packet / "result.json", result)
    try:
        for count in (1000, 10000):
            report = packet / f"volume-{count}"
            report.mkdir()
            evidence = dict(status="running", volume=count, cases=[])
            U.SQL_LOG, U.CONCURRENCY_LOG = report / "queries.log", report / "concurrency.log"

            def case(name, fn):
                P.record_case(report, evidence, name, fn)
                if evidence["cases"][-1]["status"] != "pass":
                    raise RuntimeError("Retained published migration failure: " + name)

            try:
                with isolated(report, evidence, count=154, latest="20260930230000") as db:
                    rows = K.seed(db, count, report, evidence, stages)
                    baseline_folder = comparison_path.parent / f"volume-{count}"
                    old_catalog = json.loads((baseline_folder / "final-candidate-catalog.json").read_text())
                    current_catalog = P.catalog(db)
                    case("published function and four index catalogs exactly match the accepted candidate", lambda:
                         P.require(current_catalog[C.HISTORY] == old_catalog[C.HISTORY]
                           and all(current_catalog[key] == old_catalog[key]
                             for key in C.expected_added_index_catalog(current_catalog)), {}))
                    protected_catalog, protected_financial = P.catalog(db), P.financial(db)
                    mutations = {
                        "nullable collection": "alter table public.payments alter column collection_id drop not null;",
                        "deferred foreign key": "alter table public.payments alter constraint payments_collection_id_fkey deferrable initially deferred;",
                        "unvalidated foreign key": "alter table public.payments drop constraint payments_collection_id_fkey;alter table public.payments add constraint payments_collection_id_fkey foreign key(collection_id)references public.collections(id)on delete restrict not valid;",
                        "wrong delete action": "alter table public.payments drop constraint payments_collection_id_fkey;alter table public.payments add constraint payments_collection_id_fkey foreign key(collection_id)references public.collections(id)on delete cascade;",
                    }
                    for name, mutation in mutations.items():
                        case("migration integrity prerequisite refuses " + name, lambda mutation=mutation:
                             U.expected_error(db, mutation + integrity_guard, "55000",
                                 "Member history requires validated immediate collection integrity", role="postgres"))
                    case("all rejected prerequisite probes roll back catalog and genuine financial data", lambda:
                         P.require(P.catalog(db) == protected_catalog and P.financial(db) == protected_financial, {}))
                    old = json.loads((baseline_folder / "baseline/results.json").read_text())
                    current = C.matrix(db, count, rows, report, evidence, "published-current")
                    case("published matrix retains all exact query hashes and independently checks current generated public-ID labels", lambda:
                         P.require(all(current[name]["metric"]["sql_sha256"] == old[name]["metric"]["sql_sha256"]
                                       for name in current), {}))
                    for sort in C.SORTS:
                        for depth in ("first", "middle", "deep"):
                            name = f"history-{sort}-all-{depth}"
                            before, after = old[name]["page"], current[name]["page"]
                            case("published candidate retains scan/buffer benefit " + sort + " " + depth,
                                 lambda before=before, after=after: P.require(
                                     after["payment_rows_examined"] < before["payment_rows_examined"] / 2
                                     and after["root_hits"] < before["root_hits"], dict(baseline=before, published=after)))
                    case("published history plans bound windows to51 and avoid legacy whole-history reconstruction", lambda:
                         P.require(all(
                             not any("payment_history(" in plan["Query Text"].lower()
                                     for plan in row["metric"]["nested_plans"])
                             and all(node["Actual Rows"] <= 51
                                     for plan in row["metric"]["nested_plans"]
                                     for node in K.nodes(plan["Plan"]) if node.get("Node Type") == "Limit")
                             for row in current.values()), {}))
                    case("published read matrix preserves every financial/control fingerprint", lambda:
                         P.require(P.financial(db) == protected_financial, {}))
                    queue_and_intents(db, count, report, case)
                    C.concurrent_all_sorts(db, rows, report, evidence)
                evidence["status"] = "pass_scoped"
            except Exception as error:
                evidence.update(status="failed", failure=str(error), traceback=traceback.format_exc())
            finally:
                U.SQL_LOG = U.CONCURRENCY_LOG = None
                save(report / "result.json", evidence)
                result["volume_results"].append(dict(volume=count, status=evidence["status"],
                    passed=sum(row["status"] == "pass" for row in evidence["cases"]),
                    failed=sum(row["status"] == "failed" for row in evidence["cases"]),
                    source_preserved=evidence.get("all_source_tables_catalog_cron_preserved"),
                    clone_removed=evidence.get("isolated_database_removed"), result_sha256=K.sha(report / "result.json")))
                save(packet / "result.json", result)
            if evidence["status"] != "pass_scoped":
                break
        drift = [name for name, digest in hashes.items() if not (ROOT / name).is_file() or K.sha(ROOT / name) != digest]
        current_migrations = {path.name: K.sha(path) for path in sorted((ROOT / "supabase/migrations").glob("*.sql"))}
        result.update(source_input_drift=drift, migration_source_drift=sorted(
                      name for name in migrations.keys() | current_migrations.keys()
                      if migrations.get(name) != current_migrations.get(name)),
                      completed_at=dt.datetime.now(dt.timezone.utc).isoformat())
        result["status"] = "pass_scoped" if len(result["volume_results"]) == 2 and not drift \
            and not result["migration_source_drift"] and all(row["status"] == "pass_scoped"
                and row["source_preserved"] and row["clone_removed"] for row in result["volume_results"]) else "failed"
    except Exception as error:
        result.update(status="failed", failure=str(error), traceback=traceback.format_exc())
    save(packet / "result.json", result)
    print(json.dumps(result["volume_results"]), flush=True)
    return 0 if result["status"] == "pass_scoped" else 1


if __name__ == "__main__":
    raise SystemExit(main())
