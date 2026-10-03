#!/usr/bin/env python3
"""Same-dataset real API/plan comparison; candidates apply only to clones.

No published migration is modified. Every fixture posts through the actual
public maker/checker/finalizer APIs. Raw plans and intermediate index-only
results remain separate from the final primary-seek-guard candidate.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import traceback

import current_generated_query_benchmark_uat as K
import data_correctness_sql_positive_history_uat as P
import data_correctness_sql_uat as D
import staged_bundle_upgrade_uat as B
from local_schema_uat import ROOT, U, isolated, save

CANDIDATES = ROOT / '.cache/history-query-performance-candidates'
INDEXES = CANDIDATES / 'global-four-sort-indexes.sql'
GUARDS = CANDIDATES / 'history-primary-seek-guards.sql'
PINS = {INDEXES: 'f1d8514669ce59790ae74bda74d6f03aa0124b453c72b190dff92093dfcfa9d6',
        GUARDS: '356d5debd5ee9a74e338f00cdf02c55f46a7371d2b2b6f71eb2eda7f87e6b4bd'}
SORTS = ('newest', 'oldest', 'highest', 'lowest')
SCOPES = [('all', None, ''), ('readable-private', D.GROUP, ''), ('own-unreadable', D.FOREIGN, ''),
          ('anonymous', None, 'Anonymous supporter'), ('own', None, 'You'),
          ('private-title', None, 'Synthetic private data'), ('own-transactions', None, 'SYNTH-BENCH-'),
          ('hidden-title', None, 'Synthetic foreign private'), ('empty', None, "%' OR true --")]
HISTORY = 'routine:collect_member_actions.history_page(uuid,text,text,jsonb,integer)'


def page_work(metric):
    found = [p for p in metric['nested_plans'] if 'candidate' in p['Query Text']]
    P.require(len(found) == 1, dict(name=metric['name'], page_plan_count=len(found)))
    plan = found[0]
    scans = [n for n in K.nodes(plan['Plan']) if n.get('Relation Name') == 'payments']
    return dict(duration_ms=plan['Observed Duration Milliseconds'],
        root_hits=plan['Plan'].get('Shared Hit Blocks', 0), root_reads=plan['Plan'].get('Shared Read Blocks', 0),
        payment_rows_examined=sum((n['Actual Rows'] + n.get('Rows Removed by Filter', 0)
            + n.get('Rows Removed by Index Recheck', 0)) * n['Actual Loops'] for n in scans),
        payment_scans=scans)


def matrix(db, count, rows, report, evidence, arm, previous=None):
    results = {}
    directory = report / arm
    directory.mkdir()
    for sort in SORTS:
        for scope, group, query in SCOPES:
            wanted = K.ordered(K.matching(rows, group, query), sort)
            first = U.call(db, K.history_sql(group, query, sort), D.ACTOR, D.SESSION)
            for depth, offset in dict(first=0, middle=len(wanted)//2, deep=max(0, len(wanted)-50)).items():
                name = f'history-{sort}-{scope}-{depth}'
                def probe(sort=sort, scope=scope, group=group, query=query, wanted=wanted,
                          first=first, depth=depth, offset=offset, name=name):
                    cursor = None if offset == 0 else dict(revision=first['revision'], after='momo:' + wanted[offset-1]['id'])
                    sql = K.history_sql(group, query, sort, cursor)
                    doc, metric = K.measured(db, sql, directory, name)
                    K.assert_window(doc, wanted, offset)
                    if previous is not None:
                        P.require(doc == previous[name]['response'] and
                                  metric['sql_sha256'] == previous[name]['metric']['sql_sha256'],
                                  dict(name=name, byte_equivalent_json_fields_and_query=True))
                    results[name] = dict(response=doc, metric=metric, page=page_work(metric),
                                         scope=scope, sort=sort, depth=depth, offset=offset)
                    save(directory / 'results.json', results)
                    return dict(exact_authorized_ids_ties_count_sums_cursor_and_privacy=True,
                                returned=len(doc['items']), total_count=doc['total_count'])
                P.record_case(report, evidence, arm + ' ' + name, probe)
                if evidence['cases'][-1]['status'] != 'pass':
                    raise RuntimeError('Retained failed comparison; stop before further candidate mutation: ' + arm + ' ' + name)
    P.require(len(results) == 108, dict(arm=arm, completed=len(results)))
    return results


def concurrent_all_sorts(db, rows, report, evidence):
    first = {sort: U.call(db, K.history_sql(None, '', sort), D.ACTOR, D.SESSION) for sort in SORTS}
    added = dict(rows[0], id='99740000-0000-4000-8000-999999999999', amount=151,
                 date='2026-09-30T12:00:00+00:00', transaction='SYNTH-INDEX-CANDIDATE-CONCURRENT')
    writer = U.Session(db, 'candidate-four-sort-genuine-writer')
    observations = {}
    try:
        writer.write('begin;' + P.review_input_sql(added) + P.post_api_sql(added) + '\\echo POST_READY')
        writer.read('POST_READY', timeout=60)
        for sort in SORTS:
            old = first[sort]
            page = U.call(db, K.history_sql(None, '', sort, old['next_cursor']), D.ACTOR, D.SESSION)
            K.assert_window(page, K.ordered(K.matching(rows, None, ''), sort), 50)
            P.require(page['revision'] == old['revision'], dict(sort=sort, uncommitted_not_published=True))
            observations[sort] = dict(first=old, uncommitted_next_page=page)
        writer.write('commit;\\echo POST_COMMITTED')
        writer.read('POST_COMMITTED', timeout=60)
    finally:
        writer.close()
    for sort in SORTS:
        def probe(sort=sort):
            old = first[sort]
            denial = U.expected_error(db, K.history_sql(None, '', sort, old['next_cursor']),
                'P0001', 'History changed', uid=D.ACTOR, sid=D.SESSION)
            wanted = K.ordered(K.matching(rows + [added], None, ''), sort)
            fresh = U.call(db, K.history_sql(None, '', sort), D.ACTOR, D.SESSION)
            K.assert_window(fresh, wanted, 0)
            P.require(fresh['revision'] != old['revision'], dict(sort=sort, committed_revision_changed=True))
            windows = []
            for offset in (len(wanted)//2, max(0, len(wanted)-50)):
                cursor = dict(revision=fresh['revision'], after='momo:' + wanted[offset-1]['id'])
                page = U.call(db, K.history_sql(None, '', sort, cursor), D.ACTOR, D.SESSION)
                K.assert_window(page, wanted, offset)
                windows.append(dict(offset=offset, response=page))
            observations[sort].update(stale_denial=denial, fresh_first=fresh, fresh_middle_deep=windows)
            save(report / 'actual-all-sort-concurrent-receipts.json', observations)
            return dict(genuine_writer=True, uncommitted_invisible=True, stale_refused=True,
                        exact_fresh_first_middle_deep=True, sort=sort, repeatable_read_claimed=False)
        P.record_case(report, evidence, 'final candidate actual concurrent cursor ' + sort, probe)


def expected_added_index_catalog(before):
    """Exact PostgreSQL objects belonging to the four new partial indexes."""
    columns = {
        'newest': [('posted_at', 'DESC'), ('id', '')],
        'oldest': [('posted_at', ''), ('id', '')],
        'highest': [('amount_rwf', 'DESC'), ('posted_at', 'DESC'), ('id', '')],
        'lowest': [('amount_rwf', ''), ('posted_at', 'DESC'), ('id', '')],
    }
    owner_acl = [dict(grantable=False, grantee='OWNER', grantor='OWNER', privilege=name)
        for name in ('DELETE', 'INSERT', 'MAINTAIN', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE')]
    result = {}
    for sort, parts in columns.items():
        name = 'payments_history_global_' + sort + '_idx'
        ordering = ', '.join(column + (' ' + direction if direction else '') for column, direction in parts)
        result['index:' + name] = dict(
            definition=f"CREATE INDEX {name} ON public.payments USING btree ({ordering}) WHERE ((status = 'posted'::text) AND (currency = 'RWF'::text))",
            ready=True, valid=True)
        result['relation:public.' + name] = dict(acl=owner_acl, force=False, kind='i', rls=False, view=None)
        for column, _ in parts:
            result['column:' + name + '.' + column] = dict(acl=None, default=None, generated='', identity='',
                notnull=False, type=before['column:payments.' + column]['type'])
    return result


def run(db, count, report, evidence, stages):
    def case(name, fn):
        value = P.record_case(report, evidence, name, fn)
        if evidence['cases'][-1]['status'] != 'pass':
            raise RuntimeError('Retained failed candidate check; no later mutation: ' + name)
        return value
    source_catalog, clone_catalog = P.catalog('postgres'), P.catalog(db)
    save(report / 'installed-catalog.json', source_catalog)
    save(report / 'clone-before-stages-catalog.json', clone_catalog)
    case('schema-only clone retains actual catalog and application column grants', lambda:
         P.require(P.restored_catalog_representation(source_catalog) == P.restored_catalog_representation(clone_catalog), {}))
    rows = K.seed(db, count, report, evidence, stages)
    financial = P.financial(db)
    before_catalog = P.catalog(db)
    save(report / 'before-candidate-catalog.json', before_catalog)
    baseline = matrix(db, count, rows, report, evidence, 'baseline')
    case('baseline reads preserve every genuine financial/control fingerprint', lambda:
         P.require(P.financial(db) == financial, {}))
    U.psql(db, INDEXES.read_text())
    indexed_catalog = P.catalog(db)
    added = set(indexed_catalog) - set(before_catalog)
    expected = expected_added_index_catalog(before_catalog)
    case('index-only candidate adds exactly four valid partial indexes and their relation/column metadata without API or ACL changes', lambda:
         P.require(added == set(expected) and set(indexed_catalog) == set(before_catalog) | set(expected)
                   and all(indexed_catalog[k] == v for k, v in before_catalog.items())
                   and all(indexed_catalog[k] == v for k, v in expected.items()), dict(added=sorted(added))))
    index_only = matrix(db, count, rows, report, evidence, 'indexes-only', baseline)
    U.psql(db, GUARDS.read_text())
    guarded_catalog = P.catalog(db)
    expected_body = indexed_catalog[HISTORY]['source']
    for column, op, parameter in [('posted_at','<','$5'), ('posted_at','>','$5'), ('amount_rwf','<','$6'), ('amount_rwf','>','$6')]:
        old = f"keyset_predicate := '($4::uuid is null or payment.{column} {op} {parameter} or '"
        new = f"keyset_predicate := '($4::uuid is null or payment.{column} {op}= {parameter}) and '\n      || '($4::uuid is null or payment.{column} {op} {parameter} or '"
        P.require(expected_body.count(old) == 1, dict(expected_source_fragment=old))
        expected_body = expected_body.replace(old, new)
    expected_catalog = json.loads(json.dumps(indexed_catalog))
    expected_catalog[HISTORY]['source'] = expected_body
    case('seek candidate changes only four logically redundant primary bounds and preserves every other catalog contract', lambda:
         P.require(guarded_catalog == expected_catalog, dict(only_history_source_changed=True)))
    save(report / 'final-candidate-catalog.json', guarded_catalog)
    final = matrix(db, count, rows, report, evidence, 'indexes-and-seek-guards', baseline)
    comparison = {}
    for name, result in final.items():
        comparison[name] = dict(baseline=baseline[name]['page'], indexes_only=index_only[name]['page'],
                                final=result['page'], exact_result_unchanged=True)
    save(report / 'plan-comparison.json', comparison)
    for sort in SORTS:
        for depth in ('first', 'middle', 'deep'):
            name = f'history-{sort}-all-{depth}'
            def benefit(name=name):
                old, new = baseline[name]['page'], final[name]['page']
                return P.require(new['payment_rows_examined'] < old['payment_rows_examined']/2
                    and new['root_hits'] < old['root_hits'],
                    dict(name=name, baseline=old, candidate=new, necessary_full_summary_scan_unchanged=True))
            case('final candidate lowers global window scanning and buffers ' + sort + ' ' + depth, benefit)
    case('all candidate read probes preserve every financial/control fingerprint', lambda:
         P.require(P.financial(db) == financial, {}))
    concurrent_all_sorts(db, rows, report, evidence)
    evidence['deliberate_genuine_posting_count_after_cursor_races'] = count + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reviewed-stages', required=True, type=Path)
    parser.add_argument('--volumes', default='1000,10000')
    args = parser.parse_args()
    volumes = [int(v) for v in args.volumes.split(',')]
    if volumes != [1000, 10000]:
        parser.error('The demonstrated same-volume comparison requires1000 and10000')
    packet = args.output.resolve()
    if not packet.is_relative_to(ROOT / 'docs/release/generated-query-benchmark-2026-10-01'):
        parser.error('Fresh generated-query release evidence directory required')
    packet.mkdir(parents=True, exist_ok=False)
    proof_path = args.reviewed_stages.resolve(strict=True)
    proof = json.loads(proof_path.read_bytes())
    stages = [(ROOT/'supabase/migrations'/name, (ROOT/'supabase/migrations'/name).read_bytes()) for name in B.STAGES]
    stage_hashes = {path.name: hashlib.sha256(body).hexdigest() for path, body in stages}
    migrations = {path.name: K.sha(path) for path in sorted((ROOT/'supabase/migrations').glob('*.sql'))}
    if proof.get('status') != 'pass' or proof.get('source_migration_sha256') != stage_hashes \
            or not proof.get('all_source_tables_catalog_cron_preserved') or not proof.get('isolated_database_removed') \
            or len(migrations) != 154 + len(B.STAGES) or any(K.sha(path) != digest for path, digest in PINS.items()):
        save(packet / 'result.json', dict(status='failed', failure_phase='preflight_before_sql_or_clone',
             sql_executed=False, isolated_database_created=False, actual_stage_count=len(B.STAGES)))
        return 1
    inputs = [Path(__file__).resolve(), Path(K.__file__).resolve(), Path(P.__file__).resolve(), Path(D.__file__).resolve(),
              Path(B.__file__).resolve(), ROOT/'scripts/tests/local_schema_uat.py', ROOT/'scripts/tests/local_offline_verification.py',
              ROOT/'scripts/tests/shadow_supervisor_uat.py', P.CATALOG_SOURCE, B.PERMISSION_CATALOG_SOURCE,
              proof_path, INDEXES, GUARDS] + sorted((ROOT/'supabase/migrations').glob('*.sql'))
    hashes = {str(path.relative_to(ROOT)): K.sha(path) for path in inputs}
    for path in inputs:
        target = packet/'runner-sources'/path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
        P.require(K.sha(path) == K.sha(target) == hashes[str(path.relative_to(ROOT))], {})
    result = dict(status='running', kind='actual_same_dataset_global_sort_index_seek_candidate',
                  source_inputs=hashes, all_migration_inputs_before=migrations, stage_count=len(B.STAGES),
                  reviewed_stage_proof_sha256=K.sha(proof_path), volumes=volumes, volume_results=[],
                  source_database_written=False, provider_called=False, hosted_called=False,
                  published_migration=False, genuine_synthetic_mechanics_only=True)
    try:
        for count in volumes:
            report = packet/f'volume-{count}'
            report.mkdir()
            evidence = dict(status='running', volume=count, cases=[])
            U.SQL_LOG, U.CONCURRENCY_LOG = report/'queries.log', report/'concurrency.log'
            P.MAKER_SID, P.CHECKER_SID = '99640000-0000-4000-8000-000000010004', '99640000-0000-4000-8000-000000010005'
            try:
                with isolated(report, evidence, count=154, latest='20260930230000') as db:
                    run(db, count, report, evidence, stages)
                evidence['status'] = 'pass_scoped' if all(case['status'] == 'pass' for case in evidence['cases']) else 'failed'
            except Exception as error:
                evidence.update(status='failed', failure=str(error), traceback=traceback.format_exc())
            finally:
                U.SQL_LOG = U.CONCURRENCY_LOG = None
                save(report/'result.json', evidence)
                result['volume_results'].append(dict(volume=count, status=evidence['status'],
                    passed=sum(case['status']=='pass' for case in evidence['cases']),
                    failed=sum(case['status']=='failed' for case in evidence['cases']),
                    source_preserved=evidence.get('all_source_tables_catalog_cron_preserved'),
                    clone_removed=evidence.get('isolated_database_removed'), result_sha256=K.sha(report/'result.json')))
                save(packet/'result.json', result)
            if evidence['status'] != 'pass_scoped':
                break
        result['status'] = 'pass_scoped' if len(result['volume_results']) == len(volumes) \
            and all(row['status']=='pass_scoped' for row in result['volume_results']) else 'failed'
    finally:
        after = {path.name: K.sha(path) for path in sorted((ROOT/'supabase/migrations').glob('*.sql'))}
        result['migration_source_drift'] = [name for name in sorted(set(migrations)|set(after)) if migrations.get(name) != after.get(name)]
        result['source_inputs_unchanged'] = not result['migration_source_drift'] and all(
            (ROOT/path).is_file() and K.sha(ROOT/path)==digest for path,digest in hashes.items())
        if not result['source_inputs_unchanged']:
            result['status'] = 'failed'
        result['completed_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
        save(packet/'result.json', result)
    print(json.dumps(result['volume_results']), flush=True)
    return int(result['status'] != 'pass_scoped')


if __name__ == '__main__':
    raise SystemExit(main())
