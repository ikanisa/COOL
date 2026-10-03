#!/usr/bin/env python3
"""Produce a reviewable preservation-first plan; no archive/deletion operations."""
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
os.umask(0o077)

def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def write(name, value):
    (PACKET / name).write_text(json.dumps(value, indent=2) + '\n')

consumers = json.loads((PACKET / 'maintained-consumers.json').read_text())
first = json.loads((PACKET / 'first-batch-candidate-manifest.json').read_text())
critical = ROOT / 'docs/release/critical-review-2026-10-01/architecture-delivery.md'
groups = [
    {'id': 'public_content_contracts', 'observed_reader': 'scripts/qa/public_content_contract.rb', 'lines': [10, 11, 12, 81, 89],
     'required_release_inputs': ['docs/release/public-website-content-baseline.json', 'docs/release/public-website-current-content-contract.json', 'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt121/content-comparison.json', 'docs/release/critical-implementation-2026-10-01/public-media-batch1/content-comparison.json'],
     'action': 'Keep these concise contracts and comparisons in the repo, or promote unchanged bytes with explicit source/hash provenance and update the maintained strict readers in a separate assigned change. Preserve historical baseline, reviewed route text, false approval fields and current source binding.',
     'verification': ['ruby scripts/tests/public_content_contract_test.rb', 'ruby scripts/tests/product_capability_content_test.rb', 'ruby scripts/tests/public_capability_contract_test.rb', 'fresh public static build, strict quality and rendered-route proof from final frozen source']},
    {'id': 'product_capability_before_source_contract', 'observed_reader': 'scripts/tests/product_capability_content_test.rb', 'lines': [201],
     'required_release_inputs': ['docs/release/critical-implementation-2026-10-01/product-capability-batch1/before-source-sha256.json'],
     'action': 'Keep the small original before-source manifest, or relocate unchanged into test/fixtures with explicit dated provenance. Do not turn a historical unchanged-legal assertion into fabricated current approval.',
     'verification': ['ruby scripts/tests/product_capability_content_test.rb']},
    {'id': 'android_native_test_helper', 'observed_reader': 'scripts/tests/android_gateway_archive_jvm.py', 'lines': [14, 116, 125],
     'required_release_inputs': ['docs/release/collect-codex-goal-2026-09-30/android-gateway/run_native_checks.py'],
     'action': 'Promote the actively imported executable helper to a maintained scripts/tests support module; adapt every archive/background/dispatch importing consumer together, preserve its actual behavior and retain the dated original as evidence.',
     'verification': ['actual native helper import/compile tests in isolated caches', 'all current archive/background/dispatch JVM harnesses with their explicit fresh packet outputs']},
    {'id': 'admin_observed_fixtures', 'observed_reader': 'test/support/admin_exception_fixture.dart', 'lines': [13, 14],
     'additional_readers': ['test/admin_gateway_observed_test.dart', 'scripts/tests/admin_matrix_acceptance.py'],
     'required_release_inputs': ['docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat/observed-{empty,populated}.json', 'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/observed-{empty,pending,active,revoked-callbacks}.json', 'dated exception/receipt/worker SQL observations and frozen executed/captured-source listed in admin_matrix_acceptance.py CONFIG'],
     'action': 'Review sensitivity and synthetic provenance before promotion; keep minimum unchanged regression fixtures and source/observation hash links under test/fixtures, matching existing canonical admin fixture patterns. Preserve epoch/time adapters, actor/ACL scope, denial/empty/expiry states and original SQL executed-source distinction. Reports do not become renewed runtime acceptance.',
     'verification': ['full affected Admin Flutter tests using frozen lock and fresh fixture provenance', 'scripts/tests/admin_matrix_acceptance.py with all its real SQL, actor, toolchain and fixture prerequisites']},
    {'id': 'runtime_control_contract_fixtures', 'observed_reader': 'scripts/tests/runtime_control_source_gate.py', 'lines': [8, 9, 11, 14, 16],
     'required_release_inputs': ['docs/release/runtime-controls-2026-09-30/source-candidate/control-spec.json', 'docs/release/runtime-controls-2026-09-30/contracts/client-contract-v2.json', 'docs/release/runtime-controls-2026-09-30/inventory146-attempt1/inventory.json'],
     'action': 'Move the minimal unchanged spec/schema inventory/contract fixtures into a maintained test/contract location only under assigned ownership; keep the SQL-spec parity and 26-family inventory assertions and all no-authority denial checks.',
     'verification': ['python3 scripts/tests/runtime_control_source_gate.py --output <new-private-output>', 'current runtime-control client/source tests and actual isolated SQL acceptance separately']},
    {'id': 'legacy_upgrade_sql', 'observed_reader': 'scripts/tests/signed_otp_recovery_upgrade_uat.py', 'lines': [8, 10],
     'required_release_inputs': ['docs/release/otp-uncertain-recovery-2026-09-30/sources/legacy-signed-otp-limits-v2.sql'],
     'action': 'Promote the exact hash-checked historical SQL to scripts/tests/fixtures/sql with immutable historical provenance; retain the existing expected digest and genuine upgrade exercise. Never replace it with current SQL.',
     'verification': ['actual isolated signed-OTP upgrade UAT with explicit migration SHA and fresh rollback receipt']},
    {'id': 'upgrade_hosted_metadata_and_seed', 'observed_reader': 'scripts/tests/collect_admin_combined_upgrade_uat.py', 'lines': [148, 188, 189],
     'additional_readers': ['scripts/tests/collect_current_release_upgrade_uat.py:24'],
     'required_release_inputs': ['docs/release/collect-codex-goal-2026-09-30/backend-foundation/synthetic-seed.sql', 'docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json'],
     'action': 'Keep/promote the synthetic seed unchanged with provenance. Classify and minimize the actual hosted metadata dependency before any portable fixture publication; its historical migration list remains a dated observed baseline, not a live hosted match. Preserve declared baseline/ACL/source dependencies and isolated guards.',
     'verification': ['fresh isolated current-release and combined upgrade UAT with exact baseline, source manifest, migration and SQL-tool prerequisites']},
    {'id': 'store_audit_readiness_metadata', 'observed_reader': 'maintained release/security tests and .github/workflows/public-website.yml',
     'required_release_inputs': ['docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json', 'docs/release/public-website-content-baseline.json', 'release evidence manifests referenced by strict maintained release validators'],
     'action': 'Keep concise required release contracts and their referenced substantive evidence or add a fail-closed explicit archive resolver. Preserve pending provider/native/store/legal/human approval distinctions; do not blanket-ignore docs/release.',
     'verification': ['release-secret-scan and source-integrity', 'strict affected store/release evidence validators; open external gates remain open']},
    {'id': 'firebase_original_source_comparator', 'observed_reader': 'scripts/qa/firebase_scene_callback_probe.py', 'lines': [175],
     'required_release_inputs': ['docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/source-snapshot/upstream-package'],
     'action': 'Preserve all required original runtime/platform/source/license/comparator bytes and toolchain source bindings. The two selected historical module-cache descendants alone are proposed for preservation and later removal; upstream source, verification.json, compiler logs/dependencies/object and all sibling evidence remain.',
     'verification': ['python3 scripts/qa/firebase_scene_callback_probe.py --output <new-private-output>', 'fresh actual full iOS source compile in a new module cache using the recorded pinned SDK/header/source inputs and unchanged recorded command semantics']}
]
for group in groups:
    name = group['observed_reader'].split(':')[0]
    path = ROOT / name
    if path.is_file():
        group['observed_reader_sha256_at_plan'] = digest(path)
write('consumer-repair-matrix.json', {'schema_version': 1, 'status': 'proposed_only_no_consumer_edits',
    'maintained_consumer_inventory': 'maintained-consumers.json', 'observed_groups': groups,
    'limits': ['Nine groups are explicitly verified high-impact readers; the 153-consumer static inventory includes writers, test placeholders and additional potential readers needing assignment, not 153 proven failures.',
        'No direct lib runtime path reference was found in this bounded static scan; computed/indirect consumers were not proved absent.',
        'The active source exporter excludes all docs/release; that exclusion alone does not prove tests can run without the archive.']})

sources = [
 {'url': 'https://restic.readthedocs.io/en/stable/100_references.html', 'claim': 'Official design documents content-addressed repository storage, encrypted/authenticated blob and metadata formats, and snapshot content/metadata.', 'application': 'Prefer a maintained encrypted engine with original whole-file SHA catalog, not hand-built encryption or one plain hash directory.', 'words_derived_at_most': 65},
 {'url': 'https://restic.readthedocs.io/en/stable/045_working_with_repos.html#checking-integrity-and-consistency', 'claim': 'Default check is structural; check --read-data also reads actual stored packs.', 'application': 'Require full data integrity read before independent restore; sampled structural checks do not fulfill this first-batch gate.', 'words_derived_at_most': 55},
 {'url': 'https://restic.readthedocs.io/en/stable/050_restore.html', 'claim': 'Restore can select a specific snapshot into an explicit target; path layout should be verified against the snapshot listing.', 'application': 'Restore an exact snapshot into a fresh outside-checkout directory, then independently compare all original relative paths, whole-file hashes, sizes and metadata.', 'words_derived_at_most': 55}
]
write('primary-source-research.json', {'schema_version': 1, 'researched_at_utc': datetime.now(timezone.utc).isoformat(),
    'sources': sources, 'observed_official_stable_documentation_version': '0.19.1',
    'engine_selected_or_installed_by_this_task': False, 'restic_on_PATH_at_readback': False,
    'limits': ['Technical backup-engine research only; no legal retention duration, provider transfer authorization, cryptographic deployment approval or current installed engine acceptance inferred.']})

store = {
 'status': 'proposal_only_not_created', 'outside_checkout_root_proposal': '/Volumes/PRO-G40/Application Data/Codex/Collect-Evidence-Objects/v1',
 'engine_proposal': 'Owner-selected pinned maintained encrypted content-addressed engine; restic is a researched candidate, not installed or approved here.',
 'layout_proposal': ['encrypted-repository/ (engine-managed content-addressed encrypted packs, snapshots, indexes)',
                     'catalog manifests included inside exact encrypted snapshots, mapping original relative path + SHA256 + size + mode + epoch/source/toolchain/consumer provenance to snapshot path',
                     'sanitized in-repo relocation receipt with exact repository identity, full snapshot ID, encrypted-catalog digest, cohort totals and restore-receipt hash; no plaintext sensitive bodies/keys'],
 'identity': 'Whole-file plaintext SHA256+size catalog is independent of engine chunk/pack identifiers; equal bytes can share stored content while preserving every original path/epoch record.',
 'access': {'directory_mode_proposal': '0700', 'local_catalog_mode_proposal': '0600', 'operators': 'Named evidence custodian and independently authorized restore verifier; proposed roles, no identities granted.', 'automation': 'Read-only resolver by explicit approved repository identity; no implicit global mount, restored executable discovery, current skill path or automatic network fallback.'},
 'encryption': {'payloads': 'Engine authenticated encryption at rest.', 'metadata': 'Encrypt sensitive path/provenance catalog as well as payloads; sanitize repo-visible pointers.', 'key_management': 'Owner-approved credential manager/escrow with separately tested key recovery, never repo/log/command output.', 'backup': 'Verified second encrypted copy on an approved separate failure domain before removal of unique original objects. Same PRO-G40 destination alone is not that copy.'},
 'classes': [
   {'class': 'public_sanitized_receipt', 'rule': 'Only after actual content review; concise hashes/outcomes may remain in repo, preserve linked-object recovery.'},
   {'class': 'internal_source_and_synthetic_test', 'rule': 'Preserve source/license/toolchain provenance, false acceptance fields and tested fixture semantics; encrypted catalog and named access.'},
   {'class': 'restricted_customer_auth_operational_or_unknown', 'rule': 'Default for unreviewed bodies including caches, raw logs, binaries, backups and archives. No public/cloud transfer until classification/access authority is established.'},
   {'class': 'reproducible_scratch', 'rule': 'Requires an exact genuine regeneration receipt from frozen inputs and approved discard rationale; cache suffix alone is insufficient. First batch preserves bytes anyway.'}],
 'retention': {'approved_schedule_exists_for_this_task': False, 'interim_rule_proposal': 'Retain every proposed archived object and original-path catalog; no automatic forget/prune/expiry while legal/incident/release holds and owner-approved class retention remain unresolved.',
               'decisions_missing': ['Accountable retention/hold owner and exact class schedules', 'Approved storage/second-copy location and capacity', 'Engine/version/authenticated artifact provenance', 'Key custodians/escrow/recovery authorization', 'Customer/secret content classification and permitted access/transfer', 'Immutable evidence-index resolver contract and independent removal authorization']}
}
write('object-store-proposal.json', store)

checks = [
 'Freeze only the exact assigned historical cohort and all relevant incoming indexes; re-read each of98 original paths against this manifest. Deny path traversal, symlink ancestors, nonregular files, mismatch/missing objects and source/index drift.',
 'Preserve all98 exact bytes plus path/mode/mtime/owner/ACL/xattr/source/toolchain/provenance as applicable in the approved encrypted engine; retain a full exact snapshot ID and catalog digest. Metadata not currently captured (owner/ACL/xattr) must be inventoried before operation; mode/mtime/inode are in the present manifest.',
 'Run full repository data integrity verification (for the researched engine, check --read-data), record actual version/config/repository/snapshot identity and exit status. Do not replace it with a sampled/no-data check.',
 'A separate verification implementation/operator restores the exact snapshot into a NEW private outside-checkout directory from archive only, without reading original payload bytes for reconstruction. Independently compare all98 relative paths, SHA256, sizes, modes and required metadata. Record 98/98 result and actual repository/snapshot/catalog identities.',
 'Exercise denial cases on isolated verifier fixtures: missing/wrong object, tampered payload/index, path traversal, symlink alias, wrong snapshot/repository and changed source. Reject before removal; no damage to source/archive.',
 'Verify the approved second encrypted failure-domain copy and key recovery. Distinguish restored byte identity from backup availability, signing, native acceptance or deployment approval.',
 'Create append-only immutable original-path relocation catalog entries for all98 objects. Preserve original dated verification/hash-index bytes, and have a separately assigned fail-closed resolver verify every exact path+hash consumer listed in this packet against archive/restored payloads. Preserve compiler command/dependency records as historical values; never insert empty stubs or symlinks that masquerade as original files.',
 'Prove relevant regression/source/compile checks in a new isolated clean checkout with the archive absent and no historical cache/copy fallback. Preserve required original Firebase source comparator until its separate promotion is genuinely complete.',
 'Root reviews preservation, independent restore, consumer/index resolution, metadata/access/retention and the new evidence-free build result; root then assigns exact removal ownership. Remove only manifest-listed originals that still match and record actual before/after class/file/byte/path counts. Any divergence stops the batch.',
 'Finally recheck all affected original report/hash-index references through the durable resolver, prove approved restores still work after removal, retain root removal receipt, and keep broader ARC10 open until its full clean-checkout/sensitivity/link criteria are achieved.'
]
write('first-batch-plan.json', {'schema_version': 1, 'status': 'reviewable_preservation_first_recommendation_no_execution',
    'finding': 'ARC-10', 'original_report': str(critical.relative_to(ROOT)), 'original_report_sha256': digest(critical),
    'original_acceptance': 'Before/after file/class/byte counts; every removed path recoverable identically or justified reproducible discard; report/fixture links resolve; isolated clean build/tests without archive; classified secret/customer data and access controls.',
    'candidate_manifest': 'first-batch-candidate-manifest.json', 'candidate_manifest_sha256': digest(PACKET / 'first-batch-candidate-manifest.json'),
    'exact_candidate_trees': [first['prefix'] + 'prior-module-cache/', first['prefix'] + 'current-module-cache/'],
    'candidate_files': first['file_count'], 'logical_bytes': first['logical_bytes'], 'unique_whole_file_objects': 98,
    'disposition': 'Preserve all objects before any later approved original removal; no justified-discard shortcut.',
    'preserve_siblings': ['verification.json', 'current.o', 'prior/current stdout/stderr', 'prior/current compiler .d/.dia metadata', 'common-args.resp', 'all other evidence and source-snapshot/upstream-package original comparators'],
    'consumer_evidence': ['maintained-consumers.json', 'consumer-repair-matrix.json', 'bounded-link-review.json', 'exact-index-consumers.json', 'compressed-index-consumers.json', 'large-index-consumers.json'],
    'ordered_required_checks': checks,
    'space_interpretation': '73,167,256 original logical bytes are relocation candidates, not net or physical space savings.98 unique objects remain retained outside checkout, and same-volume preservation can consume space until approved removal; compression/dedup/clone allocation and second copy require actual measurements.',
    'deferred_sets': ['All active native current/prior APKs even where exact duplicates', 'All dated source exports/candidate bundles and unique SQL/code/source/licence variants', 'All customer/auth/raw/archive backups, images, report manifests and active test fixtures until class/consumers/retention/restore proof is complete'],
    'original_files_removed': 0, 'archives_created': 0, 'independent_archive_restores_run': 0,
    'clean_checkout_without_archive_verified': False, 'sensitivity_classification_complete': False,
    'all_arbitrary_incoming_links_verified': False, 'original_removal_authorized': False,
    'ARC10_full_acceptance_met': False, 'production_release_approved': False})
print(json.dumps({'plan_created': True, 'candidate_files': first['file_count'], 'original_files_removed': 0}))
