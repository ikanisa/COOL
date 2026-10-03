#!/usr/bin/env python3
"""Current generated-query mechanics with genuine synthetic posting workflows.

Every payment starts in REVIEW and reaches POSTED only through public
maker/checker/service APIs, with all production triggers intact. Local
auto_explain is a diagnostic superuser setup followed by normal postgres and
authenticated execution; no posted fixture bypass, hosted call or provider
truth is accepted. Each volume uses a unique, removed schema-only database.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import statistics
import time
import traceback

import data_correctness_sql_positive_history_uat as P
import data_correctness_sql_uat as D
import staged_bundle_upgrade_uat as B
from local_schema_uat import ROOT, R, U, isolated, save

PEER_SID = '99740000-0000-4000-8000-000000090003'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows_for(count):
    rows = []
    for n in range(count):
        kind = n % 6
        group = D.GROUP if kind in (0, 1, 5) else D.PUBLIC if kind == 2 else D.FOREIGN
        contributor = D.ACTOR if kind in (0, 3) else None if kind == 2 else D.OUTSIDER if kind == 4 else D.PEER
        rows.append(dict(id=f'99740000-0000-4000-8000-{n+1:012d}', group=group,
            contributor=contributor, amount=100 + n % 37,
            date=(dt.datetime(2026, 9, 29, 12, tzinfo=dt.timezone.utc) + dt.timedelta(seconds=n // 3)).isoformat(),
            transaction=f'SYNTH-BENCH-{n:06d}', anonymity='public_id' if kind in (0, 5) else 'anonymous',
            own=contributor == D.ACTOR, visible=kind != 4, readable=group != D.FOREIGN,
            title={D.GROUP: 'Synthetic private data', D.PUBLIC: 'Synthetic public data', D.FOREIGN: 'Synthetic foreign private'}[group]))
    return rows


def ordered(rows, sort):
    def key(row):
        stamp = dt.datetime.fromisoformat(row['date']).timestamp()
        return ((stamp, row['id']) if sort == 'oldest' else
                (-row['amount'], -stamp, row['id']) if sort == 'highest' else
                (row['amount'], -stamp, row['id']) if sort == 'lowest' else (-stamp, row['id']))
    return sorted(rows, key=key)


def matching(rows, group, query):
    text = query.strip().lower()
    return [row for row in rows if row['visible'] and (group is None or row['group'] == group)
        and (not text or text in row['label'].lower()
             or row['own'] and text in row['transaction'].lower()
             or row['readable'] and text in row['title'].lower())]


def history_sql(group, query, sort, cursor=None, limit=50):
    return ('select public.list_current_member_history_page('
        + ('null' if group is None else D.literal(group) + '::uuid') + ','
        + D.literal(query) + ',' + D.literal(sort) + ','
        + ('null' if cursor is None else D.literal(json.dumps(cursor)) + '::jsonb') + f',{limit})')


def assert_window(page, wanted, offset, limit=50):
    items = wanted[offset:offset+limit]
    P.require([w['payment_id'] for w in page['items']] == ['momo:' + r['id'] for r in items]
        and page['total_count'] == len(wanted)
        and page['totals'] == (dict(RWF=sum(r['amount'] for r in wanted)) if wanted else {})
        and page['own_totals'] == (dict(RWF=sum(r['amount'] for r in wanted if r['own'])) if wanted else {})
        and page['own_collection_ids'] == sorted({r['group'] for r in wanted if r['own']}),
        dict(expected_count=len(wanted), offset=offset, actual=page))
    for wire, row in zip(page['items'], items):
        P.require(wire['collection_id'] == row['group'] and wire['amount_minor'] == row['amount']
            and wire['is_current_user_contribution'] == row['own']
            and wire['supporter_label'] == row['label']
            and wire['transaction_id'] == (row['transaction'] if row['own'] else None)
            and dt.datetime.fromisoformat(wire['posted_at']) == dt.datetime.fromisoformat(row['date']),
            dict(actual=wire, expected=row))
    cursor = page['next_cursor']
    if offset + len(items) < len(wanted):
        P.require(cursor == dict(revision=page['revision'], after='momo:' + items[-1]['id']), dict(cursor=cursor))
    else:
        P.require(cursor is None, dict(cursor=cursor))


def nested_plans(text):
    decoder = json.JSONDecoder()
    found = []
    for start, char in enumerate(text):
        if char != '{':
            continue
        try:
            value, _ = decoder.raw_decode(text[start:])
        except ValueError:
            continue
        if isinstance(value, dict) and 'Query Text' in value and 'Plan' in value:
            duration = re.search(r'duration:\s*([0-9.]+)\s*ms\s+plan:\s*$', text[max(0,start-500):start])
            if duration:
                value['Observed Duration Milliseconds'] = float(duration.group(1))
            found.append(value)
    return found


def nodes(plan):
    yield plan
    for child in plan.get('Plans', []):
        yield from nodes(child)


def diagnostic_query(db, body):
    # Match the reviewed local recorder's credential handling: expansion is
    # confined to the pinned container, never host argv/env or evidence. The
    # database name is a positional shell argument, not interpolated code.
    return U.command([U.DOCKER, 'exec', '-i', U.CONTAINER, 'sh', '-c',
        'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -XqAt -U supabase_admin -d "$1" '
        '-v ON_ERROR_STOP=1 -v VERBOSITY=verbose',
        'collect_generated_query_diagnostic', db], body, check=False)


def diagnostic_preflight(db, report):
    # Admit the exact diagnostic connection/module/role transition before any
    # expensive synthetic postings. This is not a nested-plan benchmark.
    body = "load 'auto_explain';set session authorization postgres;begin;" + P.actor(D.ACTOR, D.SESSION, 'aal1') + \
        "select jsonb_build_object('preflight',true,'session_user',session_user,'api_role',current_user," \
        "'actor',auth.uid(),'session',auth.jwt()->>'session_id');rollback;"
    result = diagnostic_query(db, body)
    (report / 'diagnostic-preflight.stdout').write_text(result.stdout)
    (report / 'diagnostic-preflight.stderr').write_text(result.stderr)
    P.require(result.returncode == 0, dict(diagnostic_preflight_exit_code=result.returncode,
                                          error=result.stderr[-2000:]))
    records = [json.loads(line) for line in result.stdout.splitlines()
               if line.startswith('{') and '"preflight"' in line]
    expected = dict(preflight=True, session_user='postgres', api_role='authenticated',
                    actor=D.ACTOR, session=D.SESSION)
    P.require(records == [expected], dict(diagnostic_preflight_expected=expected, actual=records))
    return dict(actual=expected, raw_stdout_sha256=sha(report / 'diagnostic-preflight.stdout'),
                raw_stderr_sha256=sha(report / 'diagnostic-preflight.stderr'),
                attempted_before_dataset_posting=True, nested_plan_acceptance_claimed=False)


def measured(db, sql, packet, name, uid=D.ACTOR, sid=D.SESSION, aal='aal1'):
    samples, answer = [], None
    for _ in range(3):
        start = time.monotonic()
        answer = D.scalar(db, 'begin;' + P.actor(uid, sid, aal) + sql + ';rollback;')
        samples.append(time.monotonic() - start)
    # LOAD/settings require diagnostic privilege. Every measured API itself
    # executes after dropping session authorization and under its genuine role.
    diagnostic = """load 'auto_explain';set client_min_messages=log;
      set auto_explain.log_min_duration=0;set auto_explain.log_analyze=on;
      set auto_explain.log_buffers=on;set auto_explain.log_nested_statements=on;
      set auto_explain.log_format=json;set auto_explain.log_timing=off;
      set session authorization postgres;begin;"""
    body = diagnostic + P.actor(uid, sid, aal) + sql + ';rollback;'
    result = diagnostic_query(db, body)
    (packet / f'{name}.stdout').write_text(result.stdout)
    (packet / f'{name}.stderr').write_text(result.stderr)
    P.require(result.returncode == 0, dict(name=name, diagnostic_exit_code=result.returncode,
        error=result.stderr[-2000:]))
    plans = nested_plans(result.stderr)
    nested = [p for p in plans if 'public.list_current_member_history_page' not in p['Query Text'].lower()
              and 'public.admin_list_notifications(' not in p['Query Text'].lower()
              and 'public.list_current_member_recent_intents(' not in p['Query Text'].lower()]
    record = dict(name=name, sql_sha256=hashlib.sha256(sql.encode()).hexdigest(),
        end_to_end_seconds=samples, median_seconds=statistics.median(samples), max_seconds=max(samples),
        nested_plan_count=len(nested), nested_plans=nested,
        raw_stdout_sha256=sha(packet / f'{name}.stdout'), raw_stderr_sha256=sha(packet / f'{name}.stderr'),
        diagnostic_setup_role='supabase_admin', execution_session_authorization='postgres',
        credential_expansion_scope='inside exact pinned QA container only; no host or evidence credential copy',
        execution_api_role='authenticated', end_to_end_includes_docker_and_psql=True,
        wrapper_only_plan_accepted=False, instrumentation_in_uninstrumented_samples=False)
    P.require(nested and any('Shared Hit Blocks' in node for plan in nested for node in nodes(plan['Plan'])),
        dict(name=name, missing_nested_buffers=True, raw_stderr=result.stderr[-2000:]))
    return answer, record


def write_review(packet, result):
    lines = ['# Current generated-query mechanical benchmark', '',
        'Each volume uses an isolated schema-only154 baseline plus the exact reviewed current stage manifest. '
        'Payments reach POSTED through genuine public reconciliation APIs with all production triggers intact. '
        'Synthetic evidence is not independent provider or settlement evidence.', '',
        '| Volume | Passing cases | Failed cases | Shared source preserved | Clone removed |',
        '| --- | --- | --- | --- | --- |']
    for row in result['volume_results']:
        lines.append(f"| {row['volume']} | {row['passed']} | {row['failed']} | {row['all_source_tables_catalog_cron_preserved']} | {row['isolated_database_removed']} |")
    lines += ['', '## Sampled history measurements', '',
        'Each median is three uninstrumented end-to-end Docker/psql/API samples. '
        'It is not a hosted p95/p99, a server-only latency or an approved service objective. '
        'Independent nested auto_explain JSON and actual buffers are retained for every measured call. '
        'The exact duration reported by that diagnostic is retained when present.', '',
        '| Volume | Sort | Depth | Matched rows | Returned | Median end-to-end seconds | Nested plans |',
        '| --- | --- | --- | --- | --- | --- | --- |']
    for row in result['volume_results']:
        path = packet/f"volume-{row['volume']}"/'measurements.json'
        if not path.exists():
            continue
        for metric in json.loads(path.read_text()):
            if metric.get('scope') == 'all':
                lines.append(f"| {row['volume']} | {metric['sort']} | {metric['depth']} | {metric['total_count']} | {metric['returned']} | {metric['median_seconds']:.6f} | {metric['nested_plan_count']} |")
    lines += ['', '## Interpretation', '',
        '- First, middle and deep pages use the actual current public API; known synthetic anchor IDs are labelled separately from full navigation chains proved by the69-row receipt packet.',
        '- Generated history window Limit nodes must return no more than51 rows; exact counts/sums/content revision still scan the complete matched relational scope. Nested legacy whole-history JSON reconstruction is refused.',
        '- Readable private groups, own unreadable groups, anonymous rows, own transaction search, readable title search, hidden private titles and empty hostile text are checked against independent known fixture identities and complete exact totals.',
        '- The actual recent-intent API is a bounded50 window with full pending count and exact-ID lookup. No nonexistent paging API is claimed.',
        '- Notifications are generated by posting triggers; both actual sorts and first/middle/deep offsets are checked. Queue shrink is an explicitly rollback-only local notification deletion, not a claimed production deletion API.',
        '- Concurrent genuine posting keeps uncommitted data invisible; after commit, the old cursor must be rejected and a refreshed page must expose the new complete count/sum.',
        '- Raw plans, buffers, query hashes, posting batch ACKs, immutable source bytes and restoration receipts remain in the volume packet. Failures and unavailable diagnostics remain failures.', '',
        'Overall scoped status: **' + result['status'] + '**. No hosted, native, provider or settlement acceptance is inferred.', '']
    (packet/'critical-review.md').write_text('\n'.join(lines))


def seed(db, count, report, evidence, stages):
    B.seed_schema_clone_permission_catalog(db, report, evidence)
    for path, body in stages:
        U.psql(db, body.decode())
    D.seed(db)
    P.seed_authority(db)
    P.seed_notification_catalog(db)
    # Additional permission is followed by distinct fresh sessions; existing
    # captured sessions are never made artificially newer by UPDATE.
    P.MAKER_SID = '99740000-0000-4000-8000-000000090001'
    P.CHECKER_SID = '99740000-0000-4000-8000-000000090002'
    U.psql(db, f"""begin;
      insert into public.admin_role_permissions(role_id,permission_name) values('{P.ROLE}','notifications.read');
      insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
        ('{P.MAKER_SID}','{P.MAKER}',now(),now(),now()+interval '4 hours','aal2'),
        ('{P.CHECKER_SID}','{P.CHECKER}',now(),now(),now()+interval '4 hours','aal2'),
        ('{PEER_SID}','{D.PEER}',now(),now(),now()+interval '4 hours','aal1');commit;""")
    ack = D.scalar(db, 'begin;' + P.actor(P.MAKER, P.MAKER_SID) +
        "select public.admin_set_operator_email_mode_v1('Synthetic current query benchmark email cutover');commit;")
    P.require(ack == dict(ok=True, mode='email', replay=False), dict(actual_email_cutover_ack=ack))
    evidence['diagnostic_preflight'] = diagnostic_preflight(db, report)
    rows = rows_for(count)
    public_ids = D.scalar(db, 'select jsonb_object_agg(id::text,public_id) from public.profiles;')
    for row in rows:
        row['label'] = 'You' if row['own'] else 'Collect ID ' + str(public_ids[row['contributor']]) if row['anonymity'] == 'public_id' else 'Anonymous supporter'
    batch_receipts = []
    for start in range(0, count, 100):
        batch = rows[start:start+100]
        text = 'begin;set local statement_timeout=\'180s\';' + ''.join(P.review_input_sql(row) for row in batch)
        text += ''.join(P.post_api_sql(row) for row in batch) + 'commit;'
        clock = time.monotonic()
        result = U.psql(db, text)
        acks = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{"') and 'payment_status' in line]
        P.require(len(acks) == len(batch) and all(a['payment_status'] == 'posted' and a['replayed'] is False for a in acks),
            dict(offset=start, expected=len(batch), actual=len(acks)))
        batch_receipts.append(dict(offset=start, count=len(batch), seconds=round(time.monotonic()-clock, 6),
            stdout_sha256=hashlib.sha256(result.stdout.encode()).hexdigest(), receipts=acks))
        save(report / 'genuine-posting-batches.json', batch_receipts)
        print(f'POSTED {start+len(batch)}/{count} through actual public APIs', flush=True)
    U.psql(db, 'analyze public.payments;analyze public.notification_events;analyze public.notification_deliveries;')
    actual = D.scalar(db, """select jsonb_build_object(
      'posted',(select count(*) from public.payments where status='posted'),
      'confirmations',(select count(*) from public.payment_provider_confirmations),
      'journal',(select count(*) from collect_hybrid.momo_journal_entries),
      'ledger',(select count(*) from public.ledger_entries),
      'unbalanced',(select count(*) from collect_hybrid.momo_journal_entries e where
        (select sum(case when direction='debit' then amount_rwf else -amount_rwf end)
         from collect_hybrid.momo_journal_lines l where l.journal_entry_id=e.id)<>0),
      'disabled_user_triggers',(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
        join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','collect_hybrid','collect_ops')
        and not t.tgisinternal and t.tgenabled<>'O'),
      'posted_active_ops',(select count(*) from collect_ops.exceptions e join public.payments p on p.id=e.source_id
        where e.source_kind='payment' and p.status='posted' and e.active));""")
    P.require(actual == dict(posted=count, confirmations=count, journal=count, ledger=count*2,
        unbalanced=0, disabled_user_triggers=0, posted_active_ops=0), dict(actual=actual))
    save(report / 'fixture-payment-inputs.json', rows)
    evidence['genuine_fixture'] = dict(rows=count, actual=actual, public_api_route=True,
        direct_posted_write=False, production_triggers_preserved=True, independent_provider_truth=False)
    return rows


def run_volume(db, count, report, evidence, stages):
    def case(name, fn):
        P.record_case(report, evidence, name, fn)
    installed_catalog, cloned_catalog = P.catalog('postgres'), P.catalog(db)
    save(report / 'installed-catalog.json', installed_catalog)
    save(report / 'clone-before-stages-catalog.json', cloned_catalog)
    case('schema clone retains exact normalized application catalog and column ACLs', lambda:
        P.require(P.restored_catalog_representation(installed_catalog) == P.restored_catalog_representation(cloned_catalog),
                  dict(raw_catalogs_retained=True, only_reviewed_pg_dump_normalization=True)))
    rows = seed(db, count, report, evidence, stages)
    baseline = P.financial(db)
    measurements = []
    plans = report / 'plans'
    plans.mkdir()
    scopes = [('all', None, ''), ('readable-private', D.GROUP, ''), ('own-unreadable', D.FOREIGN, ''),
              ('anonymous', None, 'Anonymous supporter'), ('own', None, 'You'),
              ('private-title', None, 'Synthetic private data'), ('own-transactions', None, 'SYNTH-BENCH-'),
              ('hidden-title', None, 'Synthetic foreign private'), ('empty', None, '%\' OR true --')]
    for sort in ('newest', 'oldest', 'highest', 'lowest'):
        for scope, group, query in scopes:
            wanted = ordered(matching(rows, group, query), sort)
            first = U.call(db, history_sql(group, query, sort), D.ACTOR, D.SESSION)
            depths = dict(first=0, middle=len(wanted)//2, deep=max(0, len(wanted)-50))
            for depth, offset in depths.items():
                name = f'history-{sort}-{scope}-{depth}'
                def probe(offset=offset, name=name):
                    cursor = None if not offset else dict(revision=first['revision'], after='momo:' + wanted[offset-1]['id'])
                    doc, metric = measured(db, history_sql(group, query, sort, cursor), plans, name)
                    assert_window(doc, wanted, offset)
                    metric.update(volume=count, scope=scope, sort=sort, depth=depth,
                        total_count=len(wanted), returned=len(doc['items']), anchor_from_known_fixture=offset>0)
                    generated = [p for p in metric['nested_plans'] if 'payment' in p['Query Text'].lower()]
                    limits = [n for p in generated for n in nodes(p['Plan']) if n.get('Node Type') == 'Limit']
                    P.require(generated and (not wanted or limits) and all(n['Actual Rows'] <= 51 for n in limits),
                        dict(name=name, generated_count=len(generated), actual_limit_rows=[n.get('Actual Rows') for n in limits]))
                    P.require(not any(re.search(r'\bpayment_history\s*\(', p['Query Text'], re.I) for p in metric['nested_plans']),
                        dict(legacy_whole_history_reconstruction=False))
                    measurements.append(metric)
                    save(report / 'measurements.json', measurements)
                    return dict(expected_count=len(wanted), offset=offset, returned=len(doc['items']), nested_count=metric['nested_plan_count'])
                case(name, probe)
    case('all generated history measurements preserve financial fingerprints', lambda:
        P.require(P.financial(db) == baseline, dict(preserved=P.financial(db) == baseline)))
    # Genuine public contribution creation: pending count is complete despite a
    # bounded50 response. No paging API is invented.
    sender = D.scalar(db, f"select to_jsonb(momo_number_hash) from public.profiles where id='{D.ACTOR}';")
    U.call(db, f"select jsonb_agg(to_jsonb(t)) from generate_series(1,{count})n cross join lateral "
        f"public.create_contribution_intent('{D.GROUP}',10000+n,{D.literal(sender)})t", D.ACTOR, D.SESSION)
    U.psql(db, 'analyze public.payment_intents;')
    intent_ids = D.scalar(db, f"select jsonb_agg(id::text order by created_at desc,id) from public.payment_intents where contributor_user_id='{D.ACTOR}';")
    intent_before = P.financial(db)
    for name, uid, sid, requested in [('recent', D.ACTOR, D.SESSION, None),
        ('exact-old', D.ACTOR, D.SESSION, intent_ids[-1]), ('forged', D.ACTOR, D.SESSION, D.MISSING),
        ('foreign', D.PEER, PEER_SID, intent_ids[-1])]:
        def probe(name=name, uid=uid, sid=sid, requested=requested):
            doc, metric = measured(db, 'select public.list_current_member_recent_intents('
                + ('null' if requested is None else D.literal(requested)) + ')', plans, 'intent-'+name, uid, sid)
            expected = intent_ids[:50] if name == 'recent' else [intent_ids[-1]] if name == 'exact-old' else []
            P.require([item['id'] for item in doc['items']] == expected
                and doc['pending_count'] == (0 if uid != D.ACTOR else count), dict(actual=doc, expected_ids=expected))
            measurements.append(metric)
            return dict(full_pending_count=doc['pending_count'], returned=len(doc['items']), no_paging_api=True)
        case('actual intent '+name+' complete count and request ownership', probe)
    case('recent intent probes preserve all financial rows', lambda: P.require(P.financial(db) == intent_before, dict(preserved=True)))
    # Notification queue is produced by genuine posting triggers, not seeded
    # under disabled notification triggers.
    queue_before = P.financial(db)
    queue_ids = D.scalar(db, "select jsonb_agg(id::text order by created_at desc,id) from public.notification_events e "
        "where exists(select 1 from public.profiles p where p.id=e.user_id);") or []
    for sort in ('created_at_desc', 'created_at_asc'):
        expected_ids = queue_ids if sort == 'created_at_desc' else D.scalar(db,
            "select jsonb_agg(id::text order by created_at,id) from public.notification_events e "
            "where exists(select 1 from public.profiles p where p.id=e.user_id);") or []
        for depth, offset in dict(first=0, middle=len(expected_ids)//2, deep=max(0,len(expected_ids)-25)).items():
            def probe(offset=offset, depth=depth):
                doc, metric = measured(db, f"select public.admin_list_notifications(null,null,25,{offset},'{sort}')",
                    plans, 'notification-'+sort+'-'+depth, P.MAKER, P.MAKER_SID, 'aal2')
                P.require(doc['total'] == len(expected_ids) and [r['id'] for r in doc['rows']] == expected_ids[offset:offset+25], dict(actual=doc, offset=offset))
                measurements.append(metric)
                return dict(total=doc['total'], offset=offset, returned=len(doc['rows']))
            case('notification '+sort+' '+depth+' exact page', probe)
    case('notification reads preserve financial and notification fingerprints', lambda: P.require(P.financial(db) == queue_before, dict(preserved=True)))
    # Deliberate local queue-only deletion inside a rollback exercises shrink
    # without inventing a production delete API or changing financial status.
    def shrink():
        before = D.clone_snapshot(db)
        doc = D.scalar(db, 'begin;delete from public.notification_events;' + P.actor(P.MAKER, P.MAKER_SID) +
            f"select public.admin_list_notifications(null,null,25,{max(0,len(queue_ids)-25)},'created_at_desc');rollback;")
        P.require(doc == dict(rows=[], total=0) and D.clone_snapshot(db) == before,
            dict(actual=doc, fixture_mutation='rollback-only notification queue deletion; no production API claimed'))
        return dict(empty_page=True, exact_zero_total=True, rollback_preserved=True)
    case('notification queue shrink retains known zero and restores every row', shrink)
    def mutation():
        first = U.call(db, history_sql(None, '', 'newest'), D.ACTOR, D.SESSION)
        cursor = first['next_cursor']
        P.require(cursor is not None, dict(cursor=cursor))
        row = dict(rows[0], id='99740000-0000-4000-8000-999999999999', amount=151,
            date='2026-09-30T12:00:00+00:00', transaction='SYNTH-BENCH-CONCURRENT')
        writer = U.Session(db, 'genuine-posting-writer')
        try:
            writer.write('begin;' + P.review_input_sql(row) + P.post_api_sql(row) + "\\echo POST_READY")
            writer.read('POST_READY', timeout=60)
            prior_page = U.call(db, history_sql(None, '', 'newest', cursor), D.ACTOR, D.SESSION)
            P.require(prior_page['revision'] == first['revision'] and prior_page['total_count'] == first['total_count'], dict(uncommitted_not_published=True))
            writer.write('commit;\\echo POST_COMMITTED')
            writer.read('POST_COMMITTED', timeout=60)
        finally:
            writer.close()
        denial = U.expected_error(db, history_sql(None, '', 'newest', cursor), 'P0001', 'History changed', uid=D.ACTOR, sid=D.SESSION)
        fresh = U.call(db, history_sql(None, '', 'newest'), D.ACTOR, D.SESSION)
        P.require(fresh['total_count'] == first['total_count'] + 1
            and fresh['revision'] != first['revision'] and fresh['items'][0]['payment_id'] == 'momo:'+row['id']
            and fresh['totals']['RWF'] == first['totals']['RWF']+151, dict(fresh=fresh))
        return dict(uncommitted_read_kept_old_consistent_revision=True, stale_cursor_denial=denial,
            committed_fresh_count=fresh['total_count'], actual_public_workflow=True, repeatable_read_not_claimed=True)
    case('genuine concurrent posting rejects committed stale cursor and accepts refreshed totals', mutation)
    save(report / 'measurements.json', measurements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reviewed-stages', required=True, type=Path)
    parser.add_argument('--volumes', default='1000,10000')
    args = parser.parse_args()
    volumes = [int(x) for x in args.volumes.split(',')]
    if volumes != sorted(set(volumes)) or any(x not in (1000, 10000, 20000) for x in volumes):
        parser.error('Ascending distinct reviewed1000/10000/20000 volumes required')
    packet = args.output.resolve()
    if not packet.is_relative_to(ROOT/'docs/release'):
        parser.error('Repository release packet required')
    packet.mkdir(parents=True, exist_ok=False)
    review = args.reviewed_stages.resolve(strict=True)
    proof = json.loads(review.read_bytes())
    expected = {name:sha(ROOT/'supabase/migrations'/name) for name in B.STAGES}
    if proof.get('status') != 'pass' or proof.get('source_migration_sha256') != expected \
        or not expected or len(expected) != len(B.STAGES) \
        or not proof.get('all_source_tables_catalog_cron_preserved') or not proof.get('isolated_database_removed'):
        rejected = dict(kind='current_staged_genuine_synthetic_generated_query_benchmark',
            status='failed', failure_phase='preflight_before_sql_or_clone',
            failure='Exact current root stage manifest and terminal proof required',
            reviewed_stages_sha256=sha(review), reviewed_stage_count=len(B.STAGES),
            reviewed_stage_sha256=proof.get('source_migration_sha256'),
            observed_stage_sha256=expected, sql_executed=False,
            isolated_database_created=False, source_database_written=False,
            hosted_called=False, provider_called=False)
        save(packet/'result.json', rejected)
        print(json.dumps(rejected), flush=True)
        return 1
    stages = [(ROOT/'supabase/migrations'/name,(ROOT/'supabase/migrations'/name).read_bytes()) for name in B.STAGES]
    inputs = [Path(__file__).resolve(),Path(P.__file__).resolve(),Path(D.__file__).resolve(),Path(B.__file__).resolve(),
        ROOT/'scripts/tests/local_schema_uat.py', ROOT/'scripts/tests/local_offline_verification.py',
        ROOT/'scripts/tests/shadow_supervisor_uat.py', P.CATALOG_SOURCE,B.PERMISSION_CATALOG_SOURCE,review] + [p for p,b in stages]
    hashes = {str(p.relative_to(ROOT)):sha(p) for p in inputs}
    source = packet/'runner-sources'
    source.mkdir(mode=0o700)
    for path in inputs:
        body = path.read_bytes()
        if hashlib.sha256(body).hexdigest() != hashes[str(path.relative_to(ROOT))]:
            raise RuntimeError('Source changed during copy')
        dest=source/path.relative_to(ROOT)
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(body)
    result = dict(kind='current_staged_genuine_synthetic_generated_query_benchmark',status='running',
        started_at=dt.datetime.now(dt.timezone.utc).isoformat(),volumes=volumes,source_inputs=hashes,
        reviewed_stages_sha256=sha(review),reviewed_stage_count=len(B.STAGES),
        reviewed_source_migration_count=154+len(B.STAGES),reviewed_stage_sha256=expected,
        hosted_called=False,provider_called=False,
        source_database_written=False,independent_provider_truth=False,signed_jwt_tested=False,
        service_objectives_or_device_performance_approved=False, volume_results=[])
    try:
        for count in volumes:
            report=packet/f'volume-{count}'
            report.mkdir(mode=0o700)
            evidence=dict(status='running',cases=[],volume=count)
            U.SQL_LOG=report/'queries.log'
            U.CONCURRENCY_LOG=report/'concurrency.log'
            # seed_authority originally uses fresh unique starting sessions.
            P.MAKER_SID='99640000-0000-4000-8000-000000010004'
            P.CHECKER_SID='99640000-0000-4000-8000-000000010005'
            try:
                with isolated(report,evidence,count=154,latest='20260930230000') as db:
                    run_volume(db,count,report,evidence,stages)
                evidence['status']='failed' if any(c['status']=='failed' for c in evidence['cases']) else 'pass_scoped'
            except Exception as error:
                evidence.update(status='failed',failure=str(error),traceback=traceback.format_exc())
            finally:
                U.SQL_LOG=None
                U.CONCURRENCY_LOG=None
                save(report/'result.json',evidence)
                result['volume_results'].append(dict(volume=count,status=evidence['status'],
                    passed=sum(c['status']=='pass' for c in evidence['cases']),
                    failed=sum(c['status']=='failed' for c in evidence['cases']),
                    all_source_tables_catalog_cron_preserved=evidence.get('all_source_tables_catalog_cron_preserved'),
                    isolated_database_removed=evidence.get('isolated_database_removed'),
                    recorder_sources_unchanged=evidence.get('recorder_sources_unchanged'), result_sha256=sha(report/'result.json')))
                save(packet/'result.json',result)
            if evidence['status']=='failed':
                break
        result['status']='pass_scoped' if len(result['volume_results'])==len(volumes) and all(v['status']=='pass_scoped' for v in result['volume_results']) else 'failed'
    finally:
        result['source_inputs_unchanged']=all(sha(ROOT/p)==h for p,h in hashes.items())
        if not result['source_inputs_unchanged']:
            result['status']='failed'
        result['completed_at']=dt.datetime.now(dt.timezone.utc).isoformat()
        result['remaining_acceptance']=['Synthetic genuine workflows are mechanical evidence; no independent provider/native/settlement truth.',
            'Local plan/buffer and end-to-end samples do not approve hosted capacity or service objectives.']
        save(packet/'result.json',result)
        write_review(packet,result)
    print(json.dumps(result['volume_results']),flush=True)
    return int(result['status']=='failed')


if __name__=='__main__':
    raise SystemExit(main())
