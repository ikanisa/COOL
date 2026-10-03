#!/usr/bin/env python3
"""Bind the actually tested router/repository delta; preserve product facts."""
import copy, datetime, hashlib, json, os, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[4]
BASE = pathlib.Path(__file__).resolve().parent

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(rel): return json.loads((ROOT / rel).read_text())
def save(path,value): path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
record = read(str((BASE / 'metadata-originals.json').relative_to(ROOT)))
for row in record['files']:
    assert sha(ROOT/row['path']) == row['sha256'], row['path']
    assert sha(ROOT/row['preserved_as']) == row['sha256'], row['preserved_as']
registry_rel = 'content/product/collect_capabilities.json'
contract_rel = 'docs/release/public-website-current-content-contract.json'
registry = read(registry_rel); old_registry = copy.deepcopy(registry)
reviewed = {
    'lib/app/router.dart': '42365f9991df314997ef485f584db4027668b38c6155eaba0fc2a1a1d0acd4bb',
    'lib/shared/repositories/collect_repository.dart': 'a96a7fe64232d973279d76792e26a1a7bf10d28d0d8ff853fc5122d09de9929f',
}
for rel, expected in registry['source_inputs'].items():
    actual = sha(ROOT/rel)
    if rel in reviewed:
        assert actual == reviewed[rel]
        registry['source_inputs'][rel] = actual
    else:
        assert actual == expected, rel
assert all(registry[k] == old_registry[k] for k in registry if k != 'source_inputs')
save(ROOT/registry_rel,registry)
# The maintained generator also writes existing store metadata; bind unchanged bytes.
store_before = {rel:sha(ROOT/rel) for rel in registry['store_metadata']}
command = ['ruby','scripts/generate_product_capability_content.rb']
env = dict(os.environ, DART='/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart')
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
run = subprocess.run(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=300)
(BASE/'generator.stdout').write_bytes(run.stdout);(BASE/'generator.stderr').write_bytes(run.stderr)
assert run.returncode == 0, run.stderr.decode(errors='replace')
assert store_before == {rel:sha(ROOT/rel) for rel in store_before}
for rel in ['lib/features/landing/public_marketing_page_content.dart', 'lib/features/landing/public_capability_content.dart']:
    old = (BASE/'before'/rel).read_text(); new = (ROOT/rel).read_text()
    old_digest = record['files'][0]['sha256']; new_digest = sha(ROOT/registry_rel)
    assert old.replace(old_digest,new_digest) == new, rel
contract = read(contract_rel); old_contract = copy.deepcopy(contract)
changed = [registry_rel,'lib/features/landing/public_marketing_page_content.dart','lib/features/landing/public_capability_content.dart']
for rel,expected in contract['reviewed_source_sha256'].items():
    actual = sha(ROOT/rel)
    if rel in changed:
        contract['reviewed_source_sha256'][rel] = actual
    else:
        assert actual == expected, rel
reason = ('Bind the actual four-case default-repository/production-router privacy renewal, logout, '
          'owner departure/fresh reentry and denied-profile checks. Preserve all capability facts, '
          'availability, actions and approvals; generated consumer deltas contain registry digests only. '
          'Shared stale-cache consumer regressions and a fresh final public runtime/media/build remain pending. '
          'The previous 55-quality/104-browser public cohort is dated evidence, not acceptance of these source changes.')
contract['reviewed_changes']['privacy_default_router_source_bindings'] = reason
previous_browser = 'docs/release/critical-implementation-2026-10-01/public-media-batch3/batch.json'
contract['latest_source_review'] = {
    **contract['latest_source_review'],
    'reviewed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'reason': reason,
    'comparison_role': 'Dated fifteen-route visible-copy regression baseline; visible copy unchanged and fresh final runtime/media/build pending',
    'latest_frozen_browser_packet': previous_browser,
    'latest_frozen_browser_packet_sha256': sha(ROOT/previous_browser),
    'latest_frozen_browser_packet_role': 'Dated 55-quality/104-browser previous source cohort; does not accept subsequent default-router/repository/scaffold changes',
    'current_full_build_and_browser_accepted': False,
}
for key in old_contract:
    if key not in ['reviewed_changes','reviewed_source_sha256','latest_source_review']:
        assert contract[key] == old_contract[key], key
assert contract['publication_approved'] is False and contract['legal_release_approved'] is False
save(ROOT/contract_rel,contract)
result = {'started_at_utc':started,'completed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'command':command,'environment_overrides':{'DART':env['DART']},'timeout_seconds':300,
    'actual_exit_code':run.returncode,'source_inputs_updated':reviewed,'store_metadata_unchanged':store_before,
    'capability_facts_actions_availability_approval_unchanged':True,'generated_deltas_digest_only':True,
    'fifteen_visible_route_hashes_unchanged':contract['hashes']==old_contract['hashes'],
    'reviewed_source_input_count':len(contract['reviewed_source_sha256']),
    'files_after':{row['path']:sha(ROOT/row['path']) for row in record['files']},
    'current_full_public_runtime_accepted':False,'production_approval':False}
save(BASE/'metadata-reconciliation.json',result)
print(json.dumps(result))
