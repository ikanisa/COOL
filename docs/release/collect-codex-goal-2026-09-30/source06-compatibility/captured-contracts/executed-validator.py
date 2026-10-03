#!/usr/bin/env python3
"""Validate actual source06 SQL observations against its exact frozen schemas."""
import hashlib
import json
import pathlib

PACKET = pathlib.Path(__file__).resolve().parent
SOURCE = pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06')
MARKER_SHA = '3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    marker_bytes = (SOURCE / '.collect-release-candidate.json').read_bytes()
    assert sha(marker_bytes) == MARKER_SHA
    marker = json.loads(marker_bytes)
    destination = PACKET / 'captured-contracts'
    assert not destination.exists()
    destination.mkdir()
    schemas = {}
    files = ['collect-safe-receipt-action-v1.schema.json', 'collect-operator-entity-audit-v1.schema.json',
             'collect-unattended-operating-policy-v1.schema.json']
    for name in files:
        body = (SOURCE / 'contracts' / name).read_bytes()
        assert sha(body) == marker['source_files']['contracts/' + name]['sha256']
        (destination / name).write_bytes(body)
        schemas[name] = json.loads(body)
    script_bytes = pathlib.Path(__file__).read_bytes()
    (destination / 'executed-validator.py').write_bytes(script_bytes)
    import jsonschema
    actual = PACKET / 'backend-uat/populated/observed-source06-narrow-composition.json'
    actual_bytes = actual.read_bytes(); observations = json.loads(actual_bytes)
    bindings = {
        files[0]: ['inspection', 'cancel', 'cancel_replay', 'cancel_lookup'],
        files[1]: ['receipt_audit', 'shadow_audit'],
        files[2]: ['policy_default', 'policy_receipt', 'policy_replay', 'policy_lookup', 'policy_current'],
    }
    cases = []
    for name, keys in bindings.items():
        jsonschema.Draft202012Validator.check_schema(schemas[name])
        validator = jsonschema.Draft202012Validator(schemas[name], format_checker=jsonschema.FormatChecker())
        for key in keys:
            validator.validate(observations[key]); cases.append({'schema': name, 'observation': key, 'status': 'pass'})
    result = {'kind': 'frozen_source06_actual_sql_contract_readback', 'status': 'pass',
        'cases': cases, 'case_count': len(cases), 'source06_manifest_sha256': MARKER_SHA,
        'actual_observation_sha256': sha(actual_bytes), 'validator_sha256': sha(script_bytes),
        'source_schema_sha256': {name: sha((destination / name).read_bytes()) for name in files},
        'capture_before_validator_execution': True, 'observation_is_rolled_back_synthetic_composition': True,
        'sql_or_product_mutation': False}
    (PACKET / 'contract-readback.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': 'pass', 'actual_observations_validated': len(cases)}))


if __name__ == '__main__':
    main()
