#!/usr/bin/env python3
"""Verify existing signed APKs and attach production UAT evidence without rebuilding.

This reads retained bytes and executes only local Android inspection tools. It does
not sign, install, deploy, send SMS, rewrite candidate receipts, or grant release
authority. A UAT manifest records the operator's executed results; checksums bind
that evidence, but cannot independently establish the truth of its assertions.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
import native_pipeline as pipeline
import release_readiness as readiness
import sign_candidate as signer

CHECKS = {
    'production_deployment': 'live_existing_collect_backend',
    'admin_signin_persistence': 'physical_device',
    'staff_signin_persistence': 'physical_device',
    'sms_permissions_capture': 'physical_device',
    'sms_to_ledger': 'physical_device_mmoney_sms_to_shared_ledger',
    'duplicate_prevention': 'shared_ledger',
    'offline_catch_up': 'physical_device_to_shared_ledger',
    'access_boundaries': 'live_native_and_admin',
    'backup_restore': 'actual_database_restore',
    'shared_admin': 'live_transactions',
    'installed_update': readiness.UPGRADE_SCOPE,
}


class QualificationRejected(ValueError):
    pass


def need(value, code):
    if not value:
        raise QualificationRejected(code)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_bound(path, expected, *, maximum=8 * 1024 * 1024):
    readiness._digest(expected)
    path = Path(path).absolute()
    raw = readiness._physical(path, maximum)
    need(digest(raw) == expected, 'evidence_changed')
    return raw, path


def read_ref(base, ref):
    readiness._keys(ref, ('path', 'sha256'))
    need(type(ref['path']) is str and ref['path'] and '\\' not in ref['path'], 'evidence_path_wrong')
    path = Path(ref['path'])
    need('..' not in path.parts, 'evidence_path_wrong')
    return read_bound(path if path.is_absolute() else base / path, ref['sha256'])


def fingerprint(source):
    """Use the build pipeline's source set and encoding for a frozen checkout."""
    source = Path(source).absolute()
    need(source.resolve() == source and not any(p.is_symlink() for p in (source, *source.parents)), 'source_link_refused')
    rows = []
    for base in (source / 'native/burimunsi', source / 'upstream/collect'):
        need(base.is_dir(), 'source_missing')
        for path in pipeline.fingerprint_source_files(base):
            raw = readiness._physical(path, 64 * 1024 * 1024)
            rows.append({'path': path.relative_to(source).as_posix(), 'sha256': digest(raw)})
    return {'sha256': digest(json.dumps(rows, sort_keys=True).encode()), 'files': rows}


def live_evidence(path, expected, binding, now, certificate=None, sdk=None, java_home=None):
    raw, path = read_bound(path, expected)
    doc = readiness._object(raw)
    readiness._keys(doc, ('format', 'checked_at', 'source_sha256', 'backend_sha256', 'profile_sha256', 'apk_sha256', 'checks'))
    need(doc['format'] == 'collect.burimunsi.production-uat.v1', 'uat_format_wrong')
    readiness._fresh(doc['checked_at'], now)
    need(all(doc[name] == value for name, value in binding.items()), 'uat_identity_wrong')
    readiness._keys(doc['checks'], CHECKS)
    bound = []
    for name, scope in CHECKS.items():
        check = doc['checks'][name]
        readiness._keys(check, ('status', 'scope', 'evidence'))
        need(check['status'] == 'PASS' and check['scope'] == scope, 'uat_check_not_passed:' + name)
        refs = check['evidence']
        need(type(refs) is list and 1 <= len(refs) <= 20, 'uat_evidence_missing:' + name)
        if name == 'installed_update':
            need(len(refs) == 1, 'uat_upgrade_witness_ambiguous')
        for ref in refs:
            raw, artifact = read_ref(path.parent, ref)
            if name == 'installed_update':
                readiness.installed_update(readiness._object(raw), artifact.parent, binding['source_sha256'],
                                          binding['apk_sha256'], certificate, sdk, java_home)
            bound.append({'check': name, 'path': str(artifact), 'sha256': ref['sha256']})
    return {'manifest_sha256': expected, 'checked_at': doc['checked_at'], 'checks': list(CHECKS), 'artifacts': bound}


def production_profile(profile, expected_sha):
    readiness._keys(profile, ('format', 'id', 'mode', 'environment', 'supabase_origin',
                              'member_api_origin', 'admin_origin', 'public_origin', 'google_callback_origin'))
    need(all(type(value) is str for value in profile.values()), 'production_profile_wrong')
    profile_sha = digest(signer.canonical(profile))
    cloud = readiness.COLLECT_CLOUD_ORIGIN
    need(profile['format'] == 'collect.deployment.v1' and profile['environment'] == 'production' and
         profile['mode'] == 'managed' and profile['supabase_origin'] == profile['member_api_origin'] ==
         profile['admin_origin'] == cloud and profile['google_callback_origin'] == cloud and
         re.fullmatch('[a-z][a-z0-9-]{0,62}', profile['id']) and profile_sha == expected_sha,
         'production_profile_wrong')
    for name, value in profile.items():
        if name.endswith('_origin'):
            readiness._origin(value)
    return profile_sha


def qualify(args):
    raw, receipt_path = read_bound(args.signed_result, args.signed_result_sha256)
    receipt = readiness._object(raw)
    need(receipt.get('format') == 'collect.burimunsi.signed-testing-candidate.v1' and
         receipt.get('status') == 'PASS' and receipt.get('signing_executed') is True, 'signed_receipt_wrong')
    # Preserve the historical candidate's meaning. Production evidence is a new,
    # separately bound readback, never a mutation of these prior flags.
    need(receipt.get('purpose') == 'testing-candidate-only' and
         receipt.get('production_authorized') is False and receipt.get('distribution_authorized') is False,
         'candidate_receipt_relabelled')
    source = fingerprint(args.source_root)
    need(source['sha256'] == receipt.get('source_sha256'), 'source_changed')
    profile_raw = readiness._physical(args.profile)
    profile = readiness._object(profile_raw)
    profile_sha = production_profile(profile, receipt.get('profile_sha256'))
    rows = receipt.get('artifacts')
    need(type(rows) is list and len(rows) == len(signer.PACKAGES), 'signed_artifacts_wrong')
    selected, tool_hashes, env = signer.tools(args.sdk, args.java_home)
    certificate = readiness._digest(receipt.get('certificate_sha256'))
    artifacts = []
    seen = set()
    for row in rows:
        flavor = row.get('flavor')
        need(flavor in signer.PACKAGES and flavor not in seen and row.get('package') == signer.PACKAGES[flavor], 'signed_artifacts_wrong')
        seen.add(flavor)
        need(row.get('signature_verified') is True and row.get('certificate_sha256') == certificate and
             row.get('version_code') == signer.VERSION_CODE, 'signed_artifact_identity_wrong')
        apk, path = read_ref(receipt_path.parent, {'path': row.get('path'), 'sha256': row.get('sha256')})
        need(path.suffix == '.apk' and signer.payload(apk, flavor, unsigned=False) == row.get('payload_sha256'), 'apk_payload_changed')
        checked = signer.run_tool([selected['apksigner'], 'verify', '--verbose', '--print-certs', path], env).decode('utf8')
        pins = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$', checked, re.M)
        need(pins == [certificate] and re.search(r'^Verified using v2 scheme .*: true$', checked, re.M), 'apk_signature_wrong')
        manifest = signer.manifest(signer.run_tool([selected['apkanalyzer'], 'manifest', 'print', path], env), flavor)
        need(all(row.get(k) == v for k, v in manifest.items()), 'apk_manifest_changed')
        artifacts.append({'flavor': flavor, 'path': str(path), 'sha256': row['sha256'],
                          'certificate_sha256': certificate, **manifest})
    result = {'format': 'collect.burimunsi.production-qualification.v1',
              'checked_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'status': 'ARTIFACTS_VERIFIED_UAT_REQUIRED', 'production_evidence_complete': False,
              'source_sha256': source['sha256'], 'source_root': str(Path(args.source_root).absolute()),
              'signed_result_sha256': args.signed_result_sha256, 'profile_sha256': profile_sha,
              'artifacts': artifacts, 'tool_sha256': tool_hashes,
              'actions_performed': ['read_retained_source_and_evidence', 'verify_apk_signature_payload_and_manifest'],
              'meaning': 'Artifact integrity and supplied UAT evidence completeness. The UAT assertions remain operator evidence; this checker does not grant release authority or perform deployment/distribution/installation.'}
    if args.live_evidence is not None:
        readiness._digest(args.backend_sha256)
        binding = {'source_sha256': source['sha256'], 'backend_sha256': args.backend_sha256,
                   'profile_sha256': profile_sha, 'apk_sha256': {r['flavor']: r['sha256'] for r in artifacts}}
        result['uat'] = live_evidence(args.live_evidence, args.live_evidence_sha256, binding,
                                      dt.datetime.now(dt.timezone.utc), certificate, args.sdk, args.java_home)
        result.update(status='PASS', production_evidence_complete=True, backend_sha256=args.backend_sha256)
    # Check all retained source/APK bytes again after potentially slow SDK tools.
    need(fingerprint(args.source_root) == source, 'source_changed')
    read_bound(receipt_path, args.signed_result_sha256)
    need(readiness._physical(args.profile) == profile_raw, 'production_profile_changed')
    for row in artifacts:
        read_bound(row['path'], row['sha256'], maximum=64 * 1024 * 1024)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('signed-result', 'source-root', 'profile', 'sdk', 'java-home'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--signed-result-sha256', required=True)
    parser.add_argument('--live-evidence', type=Path)
    parser.add_argument('--live-evidence-sha256')
    parser.add_argument('--backend-sha256')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        need((args.live_evidence is None and args.live_evidence_sha256 is None and args.backend_sha256 is None) or
             (args.live_evidence is not None and args.live_evidence_sha256 is not None and args.backend_sha256 is not None), 'uat_inputs_incomplete')
        result = qualify(args)
        if args.output:
            path = args.output.absolute()
            need(not any(path.is_relative_to(p) for p in (pipeline.OVERLAY, Path(args.source_root).absolute())), 'output_inside_source')
            need(path.parent.resolve() == path.parent, 'output_link_refused')
            signer.write_private(path, json.dumps(result, indent=2).encode() + b'\n')
        print(json.dumps(result, indent=2))
        return 0 if result['production_evidence_complete'] else 2
    except (OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError) as error:
        # Never print SDK output, SMS text, credentials, or arbitrary evidence.
        code = str(error) if isinstance(error, QualificationRejected) else 'qualification_input_or_tool_invalid'
        print(json.dumps({'status': 'FAIL', 'production_evidence_complete': False, 'error_code': code}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
