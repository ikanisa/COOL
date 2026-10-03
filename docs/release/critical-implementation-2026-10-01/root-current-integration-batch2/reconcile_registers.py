#!/usr/bin/env python3
"""Reconcile actual default-route, Ubuntu and independent SDK subscopes."""
import datetime, hashlib, json, pathlib, shutil
ROOT=pathlib.Path(__file__).resolve().parents[4]
BASE=pathlib.Path(__file__).resolve().parent
REGISTER=BASE.parent
LEDGER=REGISTER/'implementation-ledger.json'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def canonical(value): return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def save(path,value): path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def packet(relative):
    path=REGISTER/relative
    return {'path':str(path.relative_to(ROOT)),'sha256':sha(path)}
def add(row,relatives):
    seen={x['path'] for x in row['evidence_packets']}
    for rel in relatives:
        entry=packet(rel)
        if entry['path'] not in seen:row['evidence_packets'].append(entry);seen.add(entry['path'])
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
assert sha(LEDGER)=='05e6f678cddb2586e04dc1e00a2828edc4af70b6a950d22d121cbeebf12c5b91'
ledger=json.loads(LEDGER.read_text());criteria=[(x['id'],x['acceptance_requirement_from_report']) for x in ledger['items']];assert len(criteria)==40
originals={'production-remaining-tasks-2026-09-30.json':'404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f','local-implementation-register-2026-09-30.json':'0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980'}
documents={name:json.loads((REGISTER.parent/name).read_text()) for name in originals}
for name,digest in originals.items():assert canonical(documents[name]['items'])==digest
owned=[LEDGER,REGISTER/'IMPLEMENTATION_REGISTER.md']+[REGISTER.parent/name for name in originals]+[REGISTER.parent/name for name in ['PRODUCTION_REMAINING_TASKS_2026-09-30.md','LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md']]
backup=BASE/'registers-before';backup.mkdir(exist_ok=False)
for path in owned:
    target=backup/path.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target);assert sha(path)==sha(target)
rows={r['id']:r for r in ledger['items']}
privacy=['privacy-default-route-batch1/batch.json','privacy-route-source-integration-batch1/packet-files.json','root-current-cohort-readback-batch1/privacy-default-packet-readback.json']
for finding in ['BE-05','BE-06','PD-01','PD-07','ARC-08']:
    add(rows[finding],privacy)
rows['BE-05']['implementation_status']='actual_default_guarded_privacy_renewal_and_owner_isolation_verified_full_lifecycle_open'
rows['BE-05']['next_action']=('Actual default repository/global router initially failed same-owner OTP renewal. The causal fix passes all4 preserved behavioral cases; all587 inputs match. The broader136-case cohort retains134 passes and2 real Security heading failures; the sole headingLevel correction passes37 affected tests, analyzer and post-header authority with1345 inputs unchanged. Exact restored-cache Home case passes on its explicitly pre-heading scope. The prior202-migration27+53 status/intake checks and84 SDK checks remain dated subscopes. Complete approved per-class retention/holds, Auth principal/FK plan, bounded restartable erasure, derivatives/exports/backups/session revocation and preserved financial history. No full erasure/native/hosted acceptance.')
rows['PD-01']['implementation_status']='default_privacy_and_security_heading_consumers_verified_current_public_media_pending_full_fidelity_open'
rows['PD-01']['next_action']=('Default privacy route/owner renewal behavior and shared Security heading semantics are now verified in actual maintained consumers; the affected37-case replay and exact restored-cache Home check pass on distinguished scopes. Public-media-batch3 retains its55-quality/104-browser dated proof, but four subsequent router/repository/scaffold/header source deltas require a new final public compilation/media/build/browser cohort. Current registry/generated consumer digest corrections preserve facts/copy/approvals. Native Android/iOS, precise legal/deletion comparator interactions, complete task outcomes, rights and owner acceptance remain open; no100% fidelity or release closure.')
rows['PD-07']['implementation_status']='current_source_observed_capability_bindings_verified_current_final_public_runtime_pending'
rows['PD-07']['next_action']=('Root updates exactly2 reviewed registry source hashes and regenerates2 digest-only Dart consumers through the actual maintained generator. All7 store files, capability facts, availability/actions/approval flags and15 visible route-copy hashes stay unchanged. All20 public reviewed input bindings match. The prior full55-quality/104-browser public3 cohort predates four production deltas; fresh final media/publication/build/browser proof is underway. Named availability/provider approvals and actual hosted conversion/support/store outcomes remain open.')
rows['ARC-08']['next_action']+=' The later actual default privacy guard/scaffold and Security semantic changes invalidate public3 as current-source acceptance; a fresh final public cohort is underway. Root preserves original metadata and verifies only registry-digest generated deltas, unchanged15 route hashes and20 reviewed bindings.'
ubuntu=['arc01-ubuntu-resolved-batch1/batch.json','arc01-ubuntu-current-preparation-batch1/batch.json','root-current-cohort-readback-batch1/arc01-resolved-packet-readback.json']
add(rows['ARC-01'],ubuntu)
rows['ARC-01']['implementation_status']='canonical_clean_ubuntu_full_private_formatter_candidate_verified_current_owner_integration_pending'
rows['ARC-01']['next_action']=('The original ARM64/no-Pub cohort really fails15 changes. Fresh authenticated Flutter3.44.4/Dart3.12.2 Ubuntu amd64 canonical enforced-lock Pub resolves language metadata and reduces actual full670-source Make failures to exactly3. Formatting only those3 in a private candidate passes670/0; the unchanged maintained Make rejects an added malformed fixture671/1 and passes restored670/0. Root independently checks117 sealed leaves and reviews the whitespace diff. No source promotion: those3 files belong to another active human-owned chat and coordination authorization is pending. A preparatory current823/670 export and171 unchanged dependency identities are frozen, but later Security header drift and no actual current Make mean current acceptance remains false. Integrate by the write owner and prove fresh full current Make without inventory or gate changes.')
sdk=['kotlin-sdk-expansion-admission-batch1/packet-files.json','kotlin-sdk-physical-foundation-batch1/packet-files.json','kotlin-sdk-candidate-preparation-batch1/packet-files.json','root-sdk-foundation-review-batch1/exact-expansion-admission-review.json','root-sdk-foundation-review-batch1/physical-foundation-readback.json','root-sdk-foundation-review-batch1/candidate-preparation-readback.json','root-sdk-foundation-review-batch1/live-candidate-three-source-readback.json']
add(rows['ARC-09'],sdk)
rows['ARC-09']['implementation_status']='authenticated_independent_sdk_three_source_candidate_verified_actual_compiler_runtime_in_progress'
rows['ARC-09']['next_action']=('Frozen prior app/file_saver compile and12 JVM units pass; installed included SDK KGP2.2.20/runtime2.0.0 remain unresolved. Publisher-authenticated independent foundation and separate Collect-only candidate physically verify22415 paths/15660 source leaves, exact modes/links/licences/CRC and zero shared SDK inodes. Root reads12 physical and10 preparation leaves and independently checks all3 actual patched source hashes/pristine originals. Only the approved KGP/checker/test delta is applied in the outside-checkout candidate; the real compileKotlin/compileTestKotlin/validatePlugins/test/jar/runtime graph invocation is running under its fixed2700s deadline. No compiler/JUnit/runtime acceptance yet, shared SDK/pins/locks untouched. Generic template/maxKnownKGP remains2.3.20 within the explicit Collect-only scope. Complete actual14-class tests, loaded plugin/compiler publisher bindings, ABI/current all-flavor consumers, negative old pins, current packaged AAB/IPA/web SBOM/advisory/licence acceptance; local DSSE/PGP crypto verification remains unperformed.')
ledger['supplementary_discovered_gaps']['privacy_global_route_consumer']={'status':'causal_default_route_fix_locally_verified_full_lifecycle_open','observed':'Actual same-owner renewal disposed the guarded form; later failed fixes exposed build-phase notifications and an unchanged encoded old private request reopening for a replacement owner. Requested/settled diagnostics preserved that causal trace.','verification':'Original4 assertions pass; only test lint corrections afterward.37 affected final checks, analyzer and authority pass. Prior134/136 and exact cache1/1 scopes remain explicitly distinguished.','next_action':'Fresh final public media/source/build/browser; native/provider/hosted and approved full erasure lifecycle remain open.'}
ledger['supplementary_discovered_gaps']['security_heading_level']={'status':'existing_semantics_gap_corrected_affected_tests_verified','observed':'Two existing shared-chrome Security tests found0 required headingLevel1 nodes. The custom header had header:true without its level.','change':'Add only headingLevel:1; retain text/layout/Back/visuals.','verification':'Affected37 checks include both formerly failing cases and all6 maintained header tests. Sole final header source amendment independently bound; no full fresh136 claim.'}
new_packets=list(dict.fromkeys(privacy+ubuntu+sdk))
for rel in ['root-current-cohort-readback-batch1/privacy-default-packet-readback.json','root-current-cohort-readback-batch1/arc01-resolved-packet-readback.json','root-sdk-foundation-review-batch1/physical-foundation-readback.json','root-sdk-foundation-review-batch1/candidate-preparation-readback.json','root-sdk-foundation-review-batch1/live-candidate-three-source-readback.json']:
    ledger['evidence_current_readback'][rel]={'checked_at_utc':now,**packet(rel),'scope':'Independent scoped artifact/code/current source readback; whole mutable release candidate not accepted.'}
ledger['captured_at_utc']=now
assert [(x['id'],x['acceptance_requirement_from_report']) for x in ledger['items']]==criteria
assert [x['id'] for x in ledger['items'] if x['full_finding_closed']]==['PD-14']
save(LEDGER,ledger)
prose=('The actual default-provider/global-router privacy renewal bug is fixed. Same-owner OTP/native reread, logout, owner departure with fresh clean reentry and denied-profile/cache clearing pass the four preserved assertions. The original136-case consumer execution records134 passes and two real Security heading failures. Adding only headingLevel1 corrects them; the37-case affected replay, analyzer and actual post-header authority pass with1345 inputs unchanged. The exact real-cache Home warning case also passes on its distinct pre-heading scope. These are separate receipts, not a newly executed full136-case run. Full approved erasure/retention/hold/Auth-principal/session/derivative/backups/financial-preservation acceptance remains open.\n\n'
       'Current capability bindings change two source hashes and two generated digests only; seven store files, public claims/actions/availability/approval flags and all fifteen visible route hashes remain unchanged. Previous public3 passes55 quality and104 browser cases for its dated source. Four later production changes require a fresh final public compilation/media/build/browser cohort, which is underway. Native task outcomes, exact Revolut comparators, rights/legal and hosted/provider/store approvals remain open.\n\n'
       'A genuine canonical Ubuntu amd64 Flutter/enforced-lock Pub bootstrap resolves language metadata. The full670-file maintained Make identifies exactly three format errors. The private three-file formatting candidate passes670/0; an untracked malformed fixture is rejected671/1, and the restored candidate passes670/0. The originals remain with their active write owner; a new preparatory source export has no current Make result and later source drift is recorded. Current clean-source acceptance is still open.\n\n'
       'Two physically independent SDK foundations/candidates now verify all22415 paths and15660 source leaves with no shared SDK inodes. Root independently confirms the three approved candidate source changes and unchanged pristine originals. The real compiler, fourteen upstream test-class sources and runtime graph invocation is active under one2700-second deadline. The shared SDK and repository pins/locks stay unchanged, and no candidate compiler/runtime/ABI/shipped SBOM acceptance is claimed yet. The unchanged template/maxKnownKGP2.3.20 is an explicit Collect-only fork limit.\n\n'
       'The earlier cold Edge download failure, archive relocation/independent restore and archive-free consumers, owner-populated migration/security/financial acceptance, font-rights decision, incident/provider/device/store and immutable final-artifact approval remain open. Production is NO-GO; only PD-14 sole-design-authority hygiene is closed, and the implementation goal remains active.\n')
latest=[packet(rel) for rel in new_packets]
for name,document in documents.items():
    ext=document['critical_review_implementation_extension'];ext.update({'captured_at_utc':now,'sha256':sha(LEDGER),'current_integration_note':prose})
    seen={x['path'] for x in ext['latest_scoped_evidence']};ext['latest_scoped_evidence'] += [x for x in latest if x['path'] not in seen]
    assert canonical(document['items'])==originals[name];save(REGISTER.parent/name,document)
current=(REGISTER/'IMPLEMENTATION_REGISTER.md').read_text();table_start=current.index('| Finding | Local implementation | Full acceptance | Evidence |')
prefix=current[:table_start];prefix=prefix.replace('Updated '+json.loads((backup/LEDGER.relative_to(ROOT)).read_text())['captured_at_utc']+'.','Updated '+now+'.',1)
table=['| Finding | Local implementation | Full acceptance | Evidence |','| --- | --- | --- | --- |']
for row in ledger['items']:
    links=[f"[{ '/'.join(pathlib.PurePosixPath(x['path']).parts[-2:])}]({ROOT/x['path']})" for x in row['evidence_packets']]
    acceptance='Closed: authority hygiene only' if row['full_finding_closed'] else 'Open'
    table.append(f"| {row['id']} | {row['implementation_status']} | {acceptance} | {'; '.join(links)} |")
(REGISTER/'IMPLEMENTATION_REGISTER.md').write_text(prefix+'\n'.join(table)+'\n\n'+prose)
marker='## Critical review implementation extension — 1 October 2026'
for name in ['PRODUCTION_REMAINING_TASKS_2026-09-30.md','LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md']:
    path=REGISTER.parent/name;old=path.read_text();assert old.count(marker)==1
    path.write_text(old.split(marker)[0]+marker+'\n\nUpdated '+now+'. [The critical findings register]('+str(REGISTER/'IMPLEMENTATION_REGISTER.md')+') retains all40 original criteria. Original102 production/24 local rows remain byte-canonical unchanged; only PD-14 authority hygiene is closed.\n\n'+prose)
for row in ledger['items']:
    for x in row['evidence_packets']:assert sha(ROOT/x['path'])==x['sha256'],x['path']
for name,digest in originals.items():
    final=json.loads((REGISTER.parent/name).read_text());assert canonical(final['items'])==digest;assert final['critical_review_implementation_extension']['sha256']==sha(LEDGER)
result={'checked_at_utc':now,'original_finding_count':40,'criteria_unchanged':True,'original_row_digests':originals,'closed_ids':['PD-14'],'owned_files_after_sha256':{str(p.relative_to(ROOT)):sha(p) for p in owned},'linked_packet_digests_verified':True,'production_ready':False,'goal_status':'active'}
save(BASE/'register-reconciliation.json',result)
print(json.dumps({'status':'PASS','ledger_sha256':sha(LEDGER),'original_rows':[102,24],'closed':['PD-14']}))
