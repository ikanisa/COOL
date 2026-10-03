#!/usr/bin/env python3
"""One-shot current provenance closure and reader implementation reconciliation."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
REGISTER = HERE.parent
LEDGER = REGISTER / "implementation-ledger.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def packet(relative):
    path = REGISTER / relative
    return {"path": str(path.relative_to(ROOT)), "sha256": sha(path)}


def add(row, relatives):
    existing = {entry["path"] for entry in row["evidence_packets"]}
    for relative in relatives:
        item = packet(relative)
        if item["path"] not in existing:
            row["evidence_packets"].append(item)
            existing.add(item["path"])


def main():
    assert sha(LEDGER) == "3ee0bd7d971d5c48ac6e475eeff093c6752beec46e611c4594168bc5ef2e7686"
    assert sha(HERE / "independent-packet-readback.json") == "a65885dcef11f3fd60c81877da52a8ca4c7da8f3d926f5e4663842f9b9c5e923"
    ledger = json.loads(LEDGER.read_text())
    criteria = [(row["id"], row["acceptance_requirement_from_report"]) for row in ledger["items"]]
    assert len(criteria) == 40
    originals = {
        "production-remaining-tasks-2026-09-30.json": "404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f",
        "local-implementation-register-2026-09-30.json": "0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980",
    }
    documents = {name: json.loads((REGISTER.parent / name).read_text()) for name in originals}
    for name, expected in originals.items():
        assert canonical(documents[name]["items"]) == expected
    owned = [LEDGER, REGISTER / "IMPLEMENTATION_REGISTER.md"] + [REGISTER.parent / name for name in originals]
    owned += [REGISTER.parent / name for name in ("PRODUCTION_REMAINING_TASKS_2026-09-30.md", "LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md")]
    backup = HERE / "registers-before"
    backup.mkdir(exist_ok=False)
    for path in owned:
        target = backup / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        assert sha(path) == sha(target)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    rows = {row["id"]: row for row in ledger["items"]}
    public = ["public-media-batch4/batch.json", "public-media-batch4/evidence-files.json",
              "root-public4-arc10-integration-batch1/independent-packet-readback.json",
              "root-public4-arc10-integration-batch1/public-share-original-visual-review.json"]
    for finding in ("PD-01", "PD-02", "PD-07", "PD-12"):
        add(rows[finding], public)
    rows["PD-02"].update({
        "implementation_status": "current_provenance_and_exact_local_served_build_verified",
        "acceptance_status": "closed_current_local_provenance_and_downstream_scope",
        "full_finding_closed": True,
        "next_action": "PD-02's stated local criterion is fulfilled: current graph validates all seven provenance records and the exact generated static build, served media/font readback and affected browser routes bind those files. Fresh344-input media compile/7 captures,55 quality checks,104 actual browser cases/72 direct entry-viewports/378 originals pass; root independently checks704 leaves and current media/source/contract equality. The original stale refusal, later four-source delta and wrapper failures remain preserved. Native visual acceptance, font rights, hosted/provider/store and release approval remain distinct open findings; no recapture is needed without relevant input changes.",
        "closure_scope": "Original PD-02 local provenance criterion plus its separately requested current local downstream build/readback/browser proof only.",
        "closed_at_utc": now,
    })
    rows["PD-01"]["implementation_status"] = "default_privacy_security_heading_and_current_public_consumers_verified_native_fidelity_open"
    rows["PD-01"]["next_action"] = "Actual default privacy4-case and final affected37-case consumers pass; the genuine full136 run retains134 passes and2 Security heading failures before its sole semantic correction. Fresh public4 now recompiles all344 scoped media inputs, captures seven original frames and passes55 quality/104 browser cases. All704 indexed leaves and current media/metadata/source bindings independently match. Native Android/iOS material task/state artifacts, precise Revolut comparators, interactions, rights and owner acceptance remain open; no full fidelity claim."
    rows["PD-07"]["implementation_status"] = "current_source_capability_bindings_and_exact_public_runtime_verified_owner_availability_open"
    rows["PD-07"]["next_action"] = "Digest-only registry/generated adapters and20 current reviewed bindings now feed the genuine fresh public4 compilation/publication/static55-quality/104-case browser result. All15 visible-copy route hashes and7 store metadata files remain unchanged. Capability/owner/publication/legal/provider approval fields remain false. Obtain named availability/provider decisions and observe actual authorized hosted conversion/support/store outcomes for advertised active services."
    rows["PD-12"]["next_action"] += " Public4 is now the independently checked current local public cohort; public3 remains a preserved dated scope. Whole mutable native/Admin/backend release candidate and broad strict export remain unaccepted."
    archive = ["archive-resolver-batch1/batch.json", "archive-resolver-batch1/SHA256SUMS",
               "root-public4-arc10-integration-batch1/independent-packet-readback.json"]
    add(rows["ARC-10"], archive)
    rows["ARC-10"]["implementation_status"] = "read_only_pinned_evidence_reader_verified_real_archive_restore_and_consumers_open"
    rows["ARC-10"]["next_action"] = "The new explicit pinned byte reader passes61 maintained synthetic filesystem/CLI tests, with full root code/test review and14-leaf/15-checksum/source readback. Its98 real missing-trust probes resolve0 references; all98 original73,167,256 bytes/modes/mtimes and original tree indexes remain unchanged. Future normalized file-cohort receipts do not attest an actual archive or restoration; existing DB/vault receipts cannot authorize this compiler-cache cohort. Choose/authenticate an encrypted engine, classify metadata/sensitivity/retention/holds, establish key recovery and approved independent failure-domain copy, prove full-data check and independent archive-only restore, repair all consumers and clean-build without archive before any unique-original removal. No archive, restore, key, copy, movement or removal occurred."
    sdk = REGISTER / "kotlin-sdk-candidate-execution-batch1"
    terminal = json.loads((sdk / "compiler-attempt2-terminal.json").read_text())
    assert terminal["status"] == "ACTUAL_FAILURE_RETAINED__NO_ACCEPTANCE" and terminal["candidate_promoted"] is False
    observation = {"captured_at_utc": now, "scope": "Actual terminal failure observed; worker full seal and scoped remediation plan pending.",
                   "source_artifacts": {str((sdk / name).relative_to(ROOT)): sha(sdk / name) for name in
                                        ("compiler-attempt2-terminal.json", "sdk-compiler-runtime-attempt2.json", "sdk-compiler-runtime-attempt2.stdout", "sdk-compiler-runtime-attempt2.stderr", "candidate-built-source-attempt2-readback.json")},
                   "observed": "Main compileKotlin/jar executed; validatePlugins and compileTestKotlin failed; no JUnit test completion. Applied/core/compiler2.4.20 are scoped artifacts, while runtime stdlib1.7.10 and compiler reflect1.6.10 remain actual transitive versions.",
                   "candidate_accepted": False, "shared_sdk_changed": False, "production_release_approved": False}
    save(HERE / "sdk-failure-observation.json", observation)
    add(rows["ARC-09"], ["root-public4-arc10-integration-batch1/sdk-failure-observation.json"])
    rows["ARC-09"]["implementation_status"] = "isolated_sdk_main_compilation_verified_full_actual_compiler_validation_and_tests_failed"
    rows["ARC-09"]["next_action"] = "Candidate attempt1 was explicitly cancelled during a slow distribution download. New attempt2 physically reused only independently authenticated complete RAW Gradle ZIP in its owned home; no extracted/module caches were copied. The exact real command exits1 after208.412s, without timeout: main compilation/jar produce84 classes, but five upstream task metadata errors fail validatePlugins and two unchanged Gradle-internal shaded test imports fail compileTestKotlin; no JUnit tests ran. Full built-source readback preserves exactly3 approved changes. Applied core/compiler2.4.20 bind independent publisher bytes; actual runtime stdlib1.7.10 and compiler reflect1.6.10 are separately retained. Root reviews a minimal exact remediation extension before local candidate writes; keep strict tasks/assertions, embedded KotlinDSL warning and Collect-only template limits. Full14-class tests, complete transitive provenance/advisory/licences, ABI/current all-flavor consumers, old-pin negatives and packaged SBOM/release acceptance remain open. Shared SDK/source pins/locks unchanged."
    for relative in [public[0], public[1], archive[0], archive[1], public[2]]:
        ledger["evidence_current_readback"][relative] = {"checked_at_utc": now, **packet(relative), "scope": "Independently reviewed scoped proof; no whole release candidate acceptance."}
    ledger["captured_at_utc"] = now
    ledger["candidate_status"] = "Mutable checkout; broad strict export remains unaccepted. Current local public4 scope passes; canonical cold Edge and current Ubuntu owner integration remain open; isolated SDK full command genuinely fails metadata/test compilation."
    assert [(row["id"], row["acceptance_requirement_from_report"]) for row in ledger["items"]] == criteria
    assert [row["id"] for row in ledger["items"] if row["full_finding_closed"]] == ["PD-02", "PD-14"]
    save(LEDGER, ledger)
    prose = (
        "Current public4 uses344 exact media inputs and348 private authored inputs, genuine fresh compilation and seven original captures. All55 quality checks and104 browser cases pass, covering18 direct entries at four viewports and378 original screenshots. Root checks704 indexed leaves,344 current media inputs, four final production hashes and canonical metadata. PD-02 is closed for its stated local provenance and current served-build/readback/browser criterion; PD-14 remains closed for sole-authority hygiene. Native visual/task acceptance, font rights and hosted/provider/store/release approvals remain open.\n\n"
        "The default privacy route renewal/owner-isolation fix passes its four preserved cases. A genuine broader136-case execution retains134 passes and two Security heading failures; its sole headingLevel1 correction passes37 affected checks, analyzer and authority. The exact cache Home case has its own dated scope. Full approved retention/holds, Auth-principal/session revocation, restartable erasure, derivatives/exports/backups and financial-history preservation remain open.\n\n"
        "The read-only pinned evidence reader passes61 synthetic cases. All98 real archive references deny without trusted inputs,0 resolve, and73,167,256 original bytes remain intact. No archive, restore, copy, key, consumer migration or removal occurred. Actual encrypted archive, independently verified restore, custody/retention/metadata policy and archive-free build/consumer acceptance remain open.\n\n"
        "Canonical Ubuntu private formatting passes670 sources and rejects a malformed671st fixture, but three original files remain with their active write owner and no fresh current root Make is accepted. Cold Edge's300-second dependency transfer failure remains; Linux/HTTP/security continuation must retain full canonical scopes.\n\n"
        "The isolated SDK's real attempt2 exits1 after208.412 seconds: main compilation/jar succeed, but five strict task metadata errors and two test-import failures prevent full acceptance; no JUnit tests ran. Core/compiler2.4.20 publisher bindings are scoped, and actual mixed transitive versions/KotlinDSL compatibility warnings remain recorded. Shared SDK and repository pins/locks are unchanged. A concrete local remediation is under review.\n\n"
        "All40 original criteria and original102 production/24 local rows remain unchanged.38 critical findings remain open in full. Production is NO-GO and the implementation goal remains active.\n"
    )
    latest = [packet(relative) for relative in dict.fromkeys(public + archive + ["root-public4-arc10-integration-batch1/sdk-failure-observation.json"])]
    for name, document in documents.items():
        ext = document["critical_review_implementation_extension"]
        ext.update({"captured_at_utc": now, "sha256": sha(LEDGER), "current_integration_note": prose})
        seen = {item["path"] for item in ext["latest_scoped_evidence"]}
        ext["latest_scoped_evidence"] += [item for item in latest if item["path"] not in seen]
        assert canonical(document["items"]) == originals[name]
        save(REGISTER.parent / name, document)
    old = (REGISTER / "IMPLEMENTATION_REGISTER.md").read_text()
    prefix = old[:old.index("| Finding | Local implementation | Full acceptance | Evidence |")]
    prefix = prefix.replace("Updated " + json.loads((backup / LEDGER.relative_to(ROOT)).read_text())["captured_at_utc"] + ".", "Updated " + now + ".", 1)
    prefix = prefix.replace("Only PD-14 sole-authority hygiene is closed.", "PD-02 local provenance/downstream proof and PD-14 sole-authority hygiene are closed;38 findings remain open in full.")
    table = ["| Finding | Local implementation | Full acceptance | Evidence |", "| --- | --- | --- | --- |"]
    for row in ledger["items"]:
        label = "Closed: local provenance/build scope" if row["id"] == "PD-02" else "Closed: authority hygiene only" if row["full_finding_closed"] else "Open"
        links = [f"[{'/'.join(Path(item['path']).parts[-2:])}]({ROOT / item['path']})" for item in row["evidence_packets"]]
        table.append(f"| {row['id']} | {row['implementation_status']} | {label} | {'; '.join(links)} |")
    (REGISTER / "IMPLEMENTATION_REGISTER.md").write_text(prefix + "\n".join(table) + "\n\n" + prose)
    marker = "## Critical review implementation extension — 1 October 2026"
    for name in ("PRODUCTION_REMAINING_TASKS_2026-09-30.md", "LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md"):
        path = REGISTER.parent / name
        prior = path.read_text()
        assert prior.count(marker) == 1
        path.write_text(prior.split(marker)[0] + marker + "\n\nUpdated " + now + ". [Current critical findings register](" + str(REGISTER / "IMPLEMENTATION_REGISTER.md") + ").\n\n" + prose)
    for row in ledger["items"]:
        for item in row["evidence_packets"]:
            assert sha(ROOT / item["path"]) == item["sha256"], item["path"]
    for name, expected in originals.items():
        final = json.loads((REGISTER.parent / name).read_text())
        assert canonical(final["items"]) == expected
        assert final["critical_review_implementation_extension"]["sha256"] == sha(LEDGER)
    save(HERE / "register-reconciliation.json", {"at_utc": now, "status": "pass", "original_criteria_unchanged": True,
         "original_row_digests": originals, "closed_ids": ["PD-02", "PD-14"],
         "current_owned_files": {str(path.relative_to(ROOT)): sha(path) for path in owned},
         "production_ready": False, "goal_status": "active"})
    print(json.dumps({"status": "PASS", "ledger_sha256": sha(LEDGER), "closed": ["PD-02", "PD-14"], "original_rows": [102, 24]}))


if __name__ == "__main__":
    main()
