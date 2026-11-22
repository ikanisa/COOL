#!/usr/bin/env python3
"""Read-only, source-bound finding inventory. Never clears a packaging gate.

No matched text, credential value, value hash, or automatic allowlist is emitted.
File hashes identify retained evidence, not the suspected secret itself.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import release_guard as g

RULE_IDS = ('private-key-marker', 'cloud-access-id', 'provider-token',
            'service-account-type', 'url-userinfo', 'secret-assignment', 'jwt-shape')
MAX_MATCHES_PER_FILE = 1000


def finding_locations(raw: bytes) -> list[dict]:
    """Offsets and line numbers refer to the named decoded view, not original bytes."""
    findings = []
    seen = set()
    for view_name, view in g.content_views(raw):
        for rule, pattern in zip(RULE_IDS, g.PATTERNS):
            for match in pattern.finditer(view):
                key = (rule, view_name, match.start(), match.end())
                if key in seen:
                    continue
                seen.add(key)
                g.need(len(findings) < MAX_MATCHES_PER_FILE, 'TRIAGE_MATCH_LIMIT')
                findings.append({'rule': rule, 'view': view_name,
                                 'line': view[:match.start()].count(b'\n') + 1,
                                 'start_offset': match.start(), 'end_offset': match.end()})
    return sorted(findings, key=lambda item: (item['view'], item['start_offset'], item['rule']))


def triage(root: Path, product: str, version: str) -> dict:
    g.policy(product, 'source');g.text(version, 'INVALID_VERSION')
    rows = g.source_entries(root, check_credentials=False)
    findings = []
    for row in rows:
        raw = g.read_file(root, row['path'])
        g.need(g.sha(raw) == row['sha256'], 'SOURCE_CHANGED_DURING_TRIAGE')
        try:
            g.scan(row['path'], raw)
        except g.Rejected as exc:
            path = row['path']
            kind = ('historical_evidence' if path.startswith('evidence/') else
                    'historical_patch' if path.endswith(('.patch', '.diff')) else
                    'test_source' if ('test' in Path(path).name.lower() or '/test/' in path or path.startswith('backend-tests/')) else
                    'unclassified_source')
            locations = finding_locations(raw)
            findings.append({'file': row, 'reason': str(exc), 'context_hint': kind,
                             'locations': locations, 'disposition': 'unresolved',
                             'owner_review_required': True,
                             'archive_member_location_unavailable': not bool(locations) and str(exc) == 'CREDENTIAL_LIKE_CONTENT'})
    g.need(g.source_entries(root, check_credentials=False) == rows, 'SOURCE_CHANGED_DURING_TRIAGE')
    return {'schema_version': 1, 'kind': 'credential-triage', 'validator_version': g.VERSION,
            'product': product, 'source_version': version, 'recorded_at': g.utcnow(),
            'source_tree_sha256': g.sha(g.canonical(rows)), 'files_checked': len(rows),
            'finding_file_count': len(findings), 'findings': findings,
            'scan_status': 'blocked' if findings else 'no_heuristic_matches',
            'gate_override_permitted': False, 'production_authorized': False,
            'meaning': 'Context hints are not clearance, evidence authentication, or proof that any credential is active. Original files are unchanged.'}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--product', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        g.need(not args.output.absolute().is_relative_to(args.source.resolve()), 'OUTPUT_ALIASES_INPUT')
        g.no_links(args.output);g.need(not args.output.exists(), 'OUTPUT_EXISTS')
        result = triage(args.source, args.product, args.version)
        g.write_new(args.output, g.pretty(result))
        print(json.dumps({'status': result['scan_status'], 'finding_files': result['finding_file_count'],
                          'production_authorized': False, 'gate_override_permitted': False}))
        return 2 if result['findings'] else 0
    except (g.Rejected, OSError, ValueError, TypeError, KeyError) as exc:
        print(json.dumps({'status': 'blocked', 'errors': [str(exc) if isinstance(exc, g.Rejected) else 'TRIAGE_FAILED'],
                          'production_authorized': False}))
        return 2

if __name__ == '__main__':
    raise SystemExit(main())
