#!/usr/bin/env python3
"""Source review views from the existing native gate and tested route factories.

This writes planning CSV/JSON only. It cannot create acceptance or infer that a
screen was rendered. Repository calls are lexical candidates, not a call graph.
"""
import csv
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs/plans/fullstack-qa-2026-09-14'
TOKENS = re.compile(r'''r?\'\'\'[\s\S]*?\'\'\'|r?"""[\s\S]*?"""|r?'(?:\\.|[^'\\])*'|r?"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/''')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mask(source):
    return TOKENS.sub(lambda match: re.sub(r'[^\n]', ' ', match[0]), source)


def balanced_end(text, start, opening, closing):
    depth = 0
    for index in range(start, len(text)):
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError('Unbalanced source declaration')


def source_record(path, source, offset):
    return {'source': str(path.relative_to(ROOT)),
            'line': source[:offset].count('\n') + 1, 'source_sha256': sha(path)}


def api_calls(source):
    calls = []
    for method, kind in [('rpc', 'rpc'), ('from', 'table'), ('invoke', 'edge_function')]:
        for match in re.finditer(r'\.' + method + r"(?:<[^()]*>)?\s*\(\s*'([a-zA-Z0-9_-]+)'", source):
            calls.append({'kind': kind, 'name': match[1], 'offset': match.start()})
    return calls


def repository_declarations():
    definitions, calls = [], []
    for path in sorted((ROOT / 'lib/shared/repositories').glob('collect_repository*.dart')):
        source = path.read_text()
        clean = mask(source)
        for call in api_calls(source):
            calls.append({**source_record(path, source, call['offset']),
                          'kind': call['kind'], 'name': call['name']})
        pattern = r'(?m)^ {0,2}(?:Future|Stream|bool|String|int|void|Collect\w+|MemberHistoryPage)(?:<[^;{}]*>)?\??\s+(\w+)\s*\('
        for match in re.finditer(pattern, clean):
            end_params = balanced_end(clean, match.end() - 1, '(', ')')
            body = re.match(r'\s*(?:async\*?\s*)?(\{|=>)', clean[end_params:])
            if body is None:
                continue
            start = end_params + body.end() - len(body[1])
            end = balanced_end(clean, start, '{', '}') if body[1] == '{' else clean.find(';', start) + 1
            if end <= start:
                continue
            definitions.append({**source_record(path, source, match.start()), 'method': match[1],
                                'end_line': source[:end].count('\n') + 1,
                                'direct_api_candidates': [{k: v for k, v in call.items() if k != 'offset'}
                                                          for call in api_calls(source[start:end])]})
    return definitions, calls


def write_csv(name, rows):
    if not rows:
        raise ValueError('Empty review view: ' + name)
    with (OUTPUT / name).open('w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: export_member_coverage.py VERIFIED_ROUTE_MAP_REPORT.json')
    report_path = pathlib.Path(sys.argv[1]).resolve()
    if not report_path.is_relative_to(ROOT / '.cache'):
        raise ValueError('Owned cached route report required')
    report = json.loads(report_path.read_text())
    if report.get('status') != 'pass' or not report.get('source_inputs_unchanged'):
        raise ValueError('Passing source-bound route-factory report required')
    for path, expected in report['source_inputs'].items():
        if sha(ROOT / path) != expected:
            raise ValueError('Route-factory source changed: ' + path)
    events = [json.loads(line) for line in (report_path.parent / 'stdout.jsonl').read_text().splitlines()
              if line.startswith('{')]
    exported = [json.loads(event['message'].removeprefix('COLLECT_QA_ROUTE_MAP=')) for event in events
                if event.get('type') == 'print' and event.get('message', '').startswith('COLLECT_QA_ROUTE_MAP=')]
    if len(exported) != 1 or sha(report_path.parent / 'stdout.jsonl') != report['stdout_sha256']:
        raise ValueError('Exactly one hash-bound route export required')
    observations = exported[0]
    code = "require './scripts/qa/mobile_design_gate'; g=MobileDesignGate.new(Dir.pwd); puts JSON.generate(routes:g.inventory_specs('route_inventory','Route'),states:g.inventory_specs('material_state_inventory','State'),cases:g.required_cases,contract:g.contract,fingerprints:g.fingerprints)"
    inventory = json.loads(subprocess.check_output(['ruby', '-e', code], cwd=ROOT, text=True))
    library_files = sorted((ROOT / 'lib').rglob('*.dart'))
    types = {}
    for path in library_files:
        source = path.read_text()
        for match in re.finditer(r'\bclass\s+(\w+)\b', mask(source)):
            types.setdefault(match[1], []).append(source_record(path, source, match.start()))
    methods, api_declarations = repository_declarations()
    route_rows = []
    for route in sorted({row['route'] for row in observations}):
        rows = [row for row in observations if row['route'] == route]
        if len(rows) != 6 or len({(row['platform'], row['identity']) for row in rows}) != 6:
            raise ValueError('Incomplete platform/identity factory matrix: ' + route)
        screens = {row['screen_type'] for row in rows if row['screen_type']}
        records = [record for screen in screens for record in types.get(screen, [])]
        if screens and len(records) != len(screens):
            raise ValueError('Screen class source unresolved: ' + route)
        files = {ROOT / record['source'] for record in records}
        for file in list(files):
            for part in re.findall(r"^part '([^']+)';", file.read_text(), re.M):
                files.add((file.parent / part).resolve())
        sources = '\n'.join(file.read_text() for file in files)
        invocations = sorted(set(re.findall(r'\b(?:repo|repository)\s*\.\s*(\w+)\s*\(', sources)) |
                             set(re.findall(r'collectRepositoryProvider\.notifier\s*\)\s*\.\s*(\w+)\s*\(', sources)))
        candidates = [item for item in methods if item['method'] in invocations]
        route_rows.append({'route': route, 'screen_types': '|'.join(sorted(screens)),
                           'screen_sources': json.dumps(records, sort_keys=True),
                           'source_library_files': '|'.join(sorted(str(file.relative_to(ROOT)) for file in files)),
                           'repository_invocations_at_file_scope': '|'.join(invocations),
                           'repository_declaration_candidates': json.dumps(candidates, sort_keys=True),
                           'unresolved_invocation_names': '|'.join(name for name in invocations if not any(item['method'] == name for item in methods)),
                           'provider_references_at_file_scope': '|'.join(sorted(set(re.findall(r'\b\w+Provider\b', sources)))),
                           'factory_and_guard_observations': json.dumps(rows, sort_keys=True),
                           'source_report': str(report_path.relative_to(ROOT)),
                           'evidence_status': 'source_and_callback_discovery_only',
                           'rendered_task_backend_visual_acceptance': 'unverified'})
    specs = inventory['routes'] + inventory['states']
    legacy = set(inventory['contract']['additional_states']) - {spec['id'] for spec in specs}
    case_rows = []
    for case in inventory['cases']:
        base, variant = case.rsplit('@', 1)
        matching = [spec for spec in specs if spec['id'] == base]
        case_rows.append({'case_id': case, 'base_id': base, 'variant': variant,
                          'route_locations': '|'.join(sorted({spec['route'] for spec in matching})),
                          'harness_declarations': json.dumps(matching, sort_keys=True),
                          'mapping_status': 'declared_harness_case' if matching else 'contract_case_without_exact_harness_id',
                          'required_platforms': 'android|ios', 'android_acceptance': 'unverified',
                          'ios_acceptance': 'unverified', 'comparator_review': 'unverified'})
    OUTPUT.mkdir(parents=True, exist_ok=True)
    write_csv('member-route-dependencies.csv', route_rows)
    write_csv('member-native-cases.csv', case_rows)
    summary = {'status': 'in_progress_source_discovery', 'final_acceptance': False,
               'route_templates': len(route_rows), 'factory_guard_observations': len(observations),
               'native_route_specs': len(inventory['routes']), 'native_material_specs': len(inventory['states']),
               'required_cases_per_platform': len(case_rows), 'legacy_cases_without_exact_harness_id': sorted(legacy),
               'repository_method_candidates': methods, 'repository_direct_api_declarations': api_declarations,
               'native_gate_fingerprints': inventory['fingerprints'],
               'route_report': str(report_path.relative_to(ROOT)), 'route_report_sha256': sha(report_path),
               'limitations': ['Factories and guard callbacks were exercised; destination screens were not mounted.',
                              'File-level dependencies can include neighboring screens and miss delegated provider/service calls.',
                              'Lexical method/API candidates are not resolved control flow or server-enforcement evidence.',
                              'Legacy contract cases remain required; apparent aliases were not silently merged.',
                              'Complete membership/role/geography/overlay/keyboard/theme and runtime support mapping remains open.',
                              'Comparator, native artifact, quality and independent/owner reviews remain unverified.'],
               'output_hashes': {name: sha(OUTPUT / name) for name in ['member-route-dependencies.csv', 'member-native-cases.csv']}}
    (OUTPUT / 'member-coverage-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({key: summary[key] for key in ['route_templates', 'factory_guard_observations',
                                                 'native_route_specs', 'native_material_specs', 'required_cases_per_platform']}))


if __name__ == '__main__':
    main()
