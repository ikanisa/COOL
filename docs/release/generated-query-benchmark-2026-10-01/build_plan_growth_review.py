#!/usr/bin/env python3
"""Read-only interpretation of retained genuine benchmark plans; no SQL."""
import hashlib
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'docs/release/generated-query-benchmark-2026-10-01'
PACKET = BASE / 'current20-attempt4-1000-10000'
OUTPUT = BASE / 'current20-plan-growth-review1'
PINNED = {
    PACKET / 'result.json': 'aa35a017abb480ab5bffa8dcd3a7768f4d55d39a2872ad8ba7ac7dd48754d9bd',
    PACKET / 'volume-1000/result.json': '511d7e44683dac549848888c7ef50b36f90e2fcbb9b62f771f06bea56b5a470f',
    PACKET / 'volume-10000/result.json': '638d972a739d5a227dc98cd6510990a20ca4996b719e3391057711b5f352b87a',
    BASE / 'current20-attempt4-source-inventory/validation.json': 'e967ccabeb779df251fa15efe407f14e2834ea7b8870d6091319f9d16f9035a3',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def walk(node):
    yield node
    for child in node.get('Plans', []):
        yield from walk(child)


def plan_detail(plan):
    scans = [{key: node[key] for key in (
        'Node Type', 'Relation Name', 'Index Name', 'Actual Rows', 'Actual Loops',
        'Rows Removed by Filter', 'Rows Removed by Index Recheck', 'Shared Hit Blocks',
        'Shared Read Blocks', 'Index Cond', 'Filter') if key in node}
        for node in walk(plan['Plan']) if node.get('Relation Name') == 'payments']
    return {
        'query_sha256': hashlib.sha256(plan['Query Text'].encode()).hexdigest(),
        'duration_ms': plan['Observed Duration Milliseconds'],
        'root_shared_hits': plan['Plan'].get('Shared Hit Blocks', 0),
        'root_shared_reads': plan['Plan'].get('Shared Read Blocks', 0),
        'payment_rows_examined': sum((node['Actual Rows'] + node.get('Rows Removed by Filter', 0)
                                     + node.get('Rows Removed by Index Recheck', 0))
                                    * node['Actual Loops'] for node in scans),
        'payment_scans': scans,
        'window_and_sort': [{key: node[key] for key in (
            'Node Type', 'Actual Rows', 'Actual Loops', 'Shared Hit Blocks', 'Shared Read Blocks',
            'Sort Method', 'Sort Space Used', 'Sort Space Type') if key in node}
            for node in walk(plan['Plan']) if node['Node Type'] in ('Limit', 'Sort')],
    }


def main():
    for path, digest in PINNED.items():
        assert sha(path) == digest, str(path)
    inputs = dict(PINNED)
    rows = []
    for volume in (1000, 10000):
        path = PACKET / f'volume-{volume}/result.json'
        result = json.loads(path.read_bytes())
        assert result['status'] == 'pass_scoped' and result['isolated_database_removed']
        assert result['all_source_tables_catalog_cron_preserved'] and result['recorder_sources_unchanged']
        assert sum(case['status'] == 'pass' for case in result['cases']) == 124
        assert all(case['status'] == 'pass' for case in result['cases'])
        measurements_path = path.parent / 'measurements.json'
        inputs[measurements_path] = sha(measurements_path)
        measurements = json.loads(measurements_path.read_bytes())
        assert len(measurements) == 118
        for measurement in measurements:
            if not measurement['name'].startswith('history-'):
                continue
            plans = measurement['nested_plans']
            summary = [plan for plan in plans if 'scoped as' in plan['Query Text']]
            page = [plan for plan in plans if 'candidate' in plan['Query Text']]
            assert len(summary) == len(page) == 1, measurement['name']
            assert measurement['execution_session_authorization'] == 'postgres'
            assert measurement['execution_api_role'] == 'authenticated'
            assert not measurement['wrapper_only_plan_accepted']
            assert not measurement['instrumentation_in_uninstrumented_samples']
            assert statistics.median(measurement['end_to_end_seconds']) == measurement['median_seconds']
            rows.append({key: measurement[key] for key in (
                'name', 'volume', 'scope', 'sort', 'depth', 'returned', 'total_count',
                'median_seconds', 'end_to_end_seconds', 'sql_sha256', 'raw_stdout_sha256', 'raw_stderr_sha256')}
                | {'summary': plan_detail(summary[0]), 'page': plan_detail(page[0])})
    assert len(rows) == 216
    catalog_path = PACKET / 'volume-10000/clone-before-stages-catalog.json'
    inputs[catalog_path] = sha(catalog_path)
    catalog = json.loads(catalog_path.read_bytes())
    indexes = {key: value for key, value in catalog.items()
               if key.startswith('index:payments_history_')}
    assert len(indexes) == 8 and all(value['valid'] and value['ready'] for value in indexes.values())
    by_name = {(row['volume'], row['name']): row for row in rows}
    growth = []
    for name in sorted({row['name'] for row in rows}):
        small, large = by_name[1000, name], by_name[10000, name]
        growth.append({'name': name, 'sample_median_growth_ratio': large['median_seconds'] / small['median_seconds'],
                       'summary_duration_growth_ratio': large['summary']['duration_ms'] / small['summary']['duration_ms'],
                       'page_duration_growth_ratio': large['page']['duration_ms'] / small['page']['duration_ms'],
                       'page_examined_small': small['page']['payment_rows_examined'],
                       'page_examined_large': large['page']['payment_rows_examined'],
                       'page_root_hits_small': small['page']['root_shared_hits'],
                       'page_root_hits_large': large['page']['root_shared_hits']})
    headline = by_name[10000, 'history-newest-all-first']
    assert headline['page']['payment_rows_examined'] == 10000
    assert headline['returned'] == 50 and headline['page']['payment_scans'][0]['Node Type'] == 'Seq Scan'
    report = {
        'kind': 'read_only_actual_nested_plan_growth_interpretation', 'sql_executed_here': False,
        'input_sha256': {str(path.relative_to(ROOT)): digest for path, digest in inputs.items()},
        'scoped_correctness_cases_passed': 248, 'volumes': [1000, 10000],
        'history_measurements': rows, 'growth': growth, 'actual_baseline_sort_indexes': indexes,
        'outer_current_source_acceptance': False,
        'outer_added_source_refusal_preserved': ['20261001004651_receipt_cancel_audit_actor.sql'],
        'remaining_defect': 'Global page selection scans every payment row for a bounded output window; full totals and revision scans remain separate.',
        'candidate_not_yet_accepted': 'Compare four global partial sort indexes on genuine same-volume data, exact API and privacy results, all sorts and stale/fresh cursors.',
        'production_latency_or_service_objective_acceptance': False,
    }
    OUTPUT.mkdir(exist_ok=False)
    (OUTPUT / 'plan-growth.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# Actual query plans and growth — scoped current20 benchmark', '',
             '248 checks passed on genuine local maker/checker/finalizer postings at 1,000 and 10,000 rows, with all production triggers. Both clones were removed and the shared database/catalog/column grants/cron were preserved. This is synthetic mechanical evidence.', '',
             'The outer current-source gate failed when the cancellation audit migration arrived. That refusal remains a failure; the captured20-stage correctness and plans remain usable scoped evidence.', '',
             '## Page selection still scans the global payment set', '',
             'The newest global first page returns50 items and materializes51 candidates, but its actual nested page plan examines every payment row. Full totals and revision computation necessarily read the matching data; this finding concerns the second page-selection scan.', '',
             '| Volume | Matched | Returned | Summary ms / root hits | Page ms / root hits | Page payment rows examined |',
             '|---:|---:|---:|---:|---:|---:|']
    for volume in (1000, 10000):
        item = by_name[volume, 'history-newest-all-first']
        lines.append(f"| {volume} | {item['total_count']} | {item['returned']} | {item['summary']['duration_ms']} / {item['summary']['root_shared_hits']} | {item['page']['duration_ms']} / {item['page']['root_shared_hits']} | {item['page']['payment_rows_examined']} |")
    lines += ['', 'The10,000-row newest page has a sequential payment scan (8,334 rows accepted and1,666 filtered) followed by a top-N51 sort using34kB. Deep highest still examines10,000 rows (50 accepted and9,950 filtered). Bounded JSON output does not prove a bounded storage scan.', '',
              'The same10,000-row readable-private newest first page uses `payments_history_collection_newest_idx`:51 payment rows,45 scan-node hits. The own-unreadable private first page examines100 payment rows with58 scan-node hits. Existing eight partial history indexes are prefixed by collection or contributor; the retained catalog has no global sort-prefix index.', '',
              '## Measured growth in global history calls', '',
              'Each number is the median of three uninstrumented local Docker/psql calls, including process startup. Independent nested auto_explain diagnostics capture query plans and buffers. These are neither hosted service latency nor p95/p99 or an approved service objective.', '',
              '| Sort / depth | 1,000 median seconds | 10,000 median seconds | Page rows examined at10,000 |',
              '|---|---:|---:|---:|']
    for sort in ('newest', 'oldest', 'highest', 'lowest'):
        for depth in ('first', 'middle', 'deep'):
            name = f'history-{sort}-all-{depth}'
            small, large = by_name[1000, name], by_name[10000, name]
            lines.append(f"| {sort} / {depth} | {small['median_seconds']:.6f} | {large['median_seconds']:.6f} | {large['page']['payment_rows_examined']} |")
    lines += ['', '## Required local correction and verification', '',
              'Compare an isolated global four-sort partial-index candidate against the identical generated production query, dataset and authorization. Require exact known IDs/ties/pages/counts/full and own sums, hidden/foreign/anonymous privacy, and actual stale/fresh cursors. Retain raw plans and prove reduced page scanning/buffers for first, middle and deep windows. Publish an additive migration only after that comparison demonstrates correctness and benefit.', '',
              'An index alone may leave deep cursors scanning from the beginning if the keyset predicate remains a filter. Actual index conditions and rows examined must decide the result. Complete totals/revision scans and search costs must remain explicit; an improved page window does not remove them.', '',
              'All216 actual history measurements, query hashes, payment scan nodes, sort memory observations and root buffers are in `plan-growth.json`. Root buffer totals are not added to child totals. Three samples and warm-cache zero-read plans cannot certify cold-cache behavior, peak memory, production hardware or settlement.', '']
    (OUTPUT / 'critical-review.md').write_text('\n'.join(lines))
    assert all(sha(path) == digest for path, digest in inputs.items())
    print(json.dumps({'output': str(OUTPUT.relative_to(ROOT)),
                      'review_sha256': sha(OUTPUT / 'critical-review.md'),
                      'json_sha256': sha(OUTPUT / 'plan-growth.json')}))


if __name__ == '__main__':
    main()
