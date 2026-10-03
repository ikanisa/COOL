#!/usr/bin/env python3
"""Preserving read-only154 progress refresh with exactly evidenced local browser closure."""
import argparse
from collections import Counter
from copy import deepcopy
import datetime as dt
import json
from pathlib import Path
import subprocess
from zoneinfo import ZoneInfo

import local_schema_uat as local

R, U, ROOT = local.R, local.U, local.ROOT
RELEASE = ROOT / "docs/release"
NAMES = ["local-implementation-register-2026-09-30.json",
         "LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md",
         "production-remaining-tasks-2026-09-30.json",
         "PRODUCTION_REMAINING_TASKS_2026-09-30.md",
         "production-remaining-tasks-2026-09-30.validation.json"]
PACKETS = [
    "local-database-runtime-2026-09-30/install154-attempt1-guarded/result.json",
    "import-export-protection-2026-09-30/invitation-installed154-attempt6-function-name-binding/result.json",
    "import-export-protection-2026-09-30/admin-rls154-attempt3-email-integration/result.json",
    "import-export-protection-2026-09-30/admin-sensitive154-attempt3-rls-audit-effects/result.json",
    "import-export-protection-2026-09-30/admin-sensitive154-attempt4-current-nine/result.json",
    "import-export-protection-2026-09-30/invitation-save-final-attempt15/validation.json",
    "data-correctness-2026-09-30/immutable-attempt16-current-client/validation.json",
    "data-correctness-2026-09-30/sql154-attempt2/result.json",
    "data-correctness-2026-09-30/sql154-attempt4-candidate234000/result.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt3-exact-private-tables/result.json",
    "local-database-runtime-2026-09-30/local-qa-recovery-readback/restore-readback-attempt1.json",
    "admin-full-coverage-2026-09-30/isolated-attempt47-final-current-admin/validation.json",
    "admin-full-coverage-2026-09-30/email-targeted-attempt2/validation.json",
    "asset-build-hygiene-2026-09-30/reachability-gateway-attempt59/validation.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt7-exact-column-acl-all167/result.json",
    "local-schema-acl-correction-2026-10-01/attempt3-exact-contracts/result.json",
    "import-export-protection-2026-09-30/email-action-bounds154-attempt2-current13-unicode-catalog/result.json",
    "data-correctness-2026-09-30/immutable-attempt21-current-calendar/validation.json",
    "admin-full-coverage-2026-09-30/inventory-attempt17-current-common83/validation.json",
    "collect-codex-goal-2026-09-30/current-full-upgrade/result.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt12-current18-cancel-integration/result.json",
    "import-export-protection-2026-10-01/admin-rls-current18-attempt1/result.json",
    "import-export-protection-2026-10-01/sensitive-current16-unicode-attempt1/result.json",
    "import-export-protection-2026-10-01/sensitive-current16-unicode-attempt2-candidate/result.json",
    "import-export-protection-2026-10-01/sensitive-current18-unicode-attempt3-integrated/result.json",
    "runtime-controls-2026-10-01/full26-current13-attempt1/result.json",
    "runtime-controls-2026-10-01/full26-current13-attempt2-reason-candidate/result.json",
    "data-correctness-2026-09-30/sql154-positive-history-attempt5-candidate235000/result.json",
    "data-correctness-2026-09-30/sql154-positive-history-attempt6-full-current167/result.json",
    "data-correctness-2026-09-30/immutable-attempt22-current167-sql-bridge/validation.json",
    "data-correctness-2026-09-30/immutable-attempt22-post-run-completion1/validation.json",
    "admin-full-coverage-2026-09-30/gateway-private-authority-current-attempt5/private-provider-scoped-acceptance.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt13-current18-source-reference/result.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt17-current20-shadow-lease/result.json",
    "cache-session-2026-10-01/member-realtime-attempt4-current-fatal-analysis/validation.json",
    "cache-session-2026-10-01/accepted-current-proof.json",
    "generated-query-benchmark-2026-10-01/diagnostic-offline-attempt3-preflight/validation.json",
    "asset-build-hygiene-2026-09-30/public-current-content-contract-attempt133/validation.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt19-current21-cancellation-audit/result.json",
    "runtime-controls-2026-10-01/current21-full26-races-attempt1/result.json",
    "runtime-controls-2026-10-01/current21-cancellation-positive-attempt3-joined-contract/result.json",
    "data-correctness-2026-09-30/sql154-positive-history-attempt7-full-current175-all-sort-cursors/result.json",
    "data-correctness-2026-09-30/immutable-attempt23-current175-history-bridge-only/validation.json",
    "generated-query-benchmark-2026-10-01/current20-attempt4-1000-10000/result.json",
    "generated-query-benchmark-2026-10-01/current20-attempt4-source-inventory/validation.json",
    "generated-query-benchmark-2026-10-01/current20-plan-growth-review1/plan-growth.json",
    "generated-query-benchmark-2026-10-01/current21-index-candidate-attempt1-1000-10000/result.json",
    "admin-full-coverage-2026-09-30/private-entity-receipt-current-attempt10/four-complete-cohort-scoped-acceptance.json",
    "asset-build-hygiene-2026-09-30/public-capture-execution-attempt154/execution.json",
    "asset-build-hygiene-2026-09-30/public-media-visual-review-transfer-attempt155/validation.json",
    "asset-build-hygiene-2026-09-30/public-media-publication-attempt157/publication.json",
    "asset-build-hygiene-2026-09-30/public-website-rebuild-attempt158/verification.json",
    "asset-build-hygiene-2026-09-30/public-browser-routes-attempt159/validation.json",
    "asset-build-hygiene-2026-09-30/public-browser-build-provenance-readback-attempt166/readback.json",
    "asset-build-hygiene-2026-09-30/current-source-inventory-attempt168/validation.json",
    "local-database-runtime-2026-09-30/ordinary-installer-current175-attempt1/result.json",
    "local-database-runtime-2026-09-30/ordinary-installer-current175-attempt2-managed-cron-owner/result.json",
    "local-database-runtime-2026-09-30/ordinary-installer-current175-attempt3-retained-cron-api/result.json",
    "local-database-runtime-2026-09-30/ordinary-installer-owner-correction-attempt2/quiet154-cron-api-prerequisite-readback.json",
    "admin-full-coverage-2026-09-30/receipt-policy-preference-current-attempt15-root/validation.json",
    "admin-full-coverage-2026-09-30/receipt-policy-preference-current-attempt16-root-frame-refresh/validation.json",
]
PACKETS += ['generated-query-benchmark-2026-10-01/current23-published-global-history-attempt2-independent-fixture-labels/result.json', 'generated-query-benchmark-2026-10-01/current21-index-candidate-attempt3-root-title-lookup/result.json', 'generated-query-benchmark-2026-10-01/published-global-keyset-root1/review.json', 'local-database-runtime-2026-09-30/staged-bundle154-attempt20-current22-global-history/result.json', 'local-database-runtime-2026-09-30/staged-bundle154-attempt21-current23-global-history-and-receipt-policy/result.json', 'local-database-runtime-2026-09-30/staged-bundle154-attempt22-current23-private-policy-inventory/result.json', 'local-database-runtime-2026-09-30/staged-bundle154-attempt23-current23-policy-scope-metadata/result.json', 'local-database-runtime-2026-09-30/ordinary-installer-current177-attempt4-global-history-policy/result.json', 'local-database-runtime-2026-09-30/ordinary-installer-current177-attempt4-global-history-policy/currentness-failure-readback.json', 'local-browser-lifecycle-2026-09-30/current-email-memory-auth-attempt9/validation.json', 'local-browser-lifecycle-2026-09-30/current-browser-source-scope-acceptance-root1/validation.json', 'admin-full-coverage-2026-09-30/isolated-attempt52-root-current95-permission-fixtures/validation.json', 'admin-full-coverage-2026-09-30/isolated-attempt56-root-raw-sms-rendered-refresh/validation.json', 'admin-full-coverage-2026-09-30/inventory-attempt18-root-current95/validation.json', 'asset-build-hygiene-2026-09-30/native-export-attempt127-ios-postbuild-verification1/artifact-verification.json', 'asset-build-hygiene-2026-09-30/swift-cached-artifact-inputs-root177-workspace-order/validation.json', 'final-local-edge-2026-10-01/current177-unit-attempt1/validation.json', 'final-local-edge-2026-10-01/current-http-attempt2-signed-endpoint-contracts/validation.json', 'final-local-edge-2026-10-01/current-http-attempt3-exact-start-count/validation.json', 'final-local-mcp-2026-10-01/current-source-attempt1/validation.json', 'final-local-mcp-2026-10-01/current-source-attempt2-complete-imports/validation.json', 'final-local-mcp-2026-10-01/current-source-attempt3-bounded-sql-fixtures/validation.json']
PACKETS += [
 'generated-query-benchmark-2026-10-01/published-global-history-attempt3-frozen177-execution/result.json',
 'generated-query-benchmark-2026-10-01/published-global-history-attempt4-frozen177-volume10000/result.json',
 'generated-query-benchmark-2026-10-01/published-history-two-volume-acceptance-root193/validation.json',
 'local-database-runtime-2026-09-30/ordinary-installer-current177-attempt5-final-policy/result.json',
 'local-database-runtime-2026-09-30/staged-bundle154-attempt24-current23-final-policy/result.json',
 'asset-build-hygiene-2026-09-30/ios-warning-source-review-root190-current127/review.json',
 'local-progress-2026-09-30/accepted-qa-publication-root194/validation.json',
 'local-browser-lifecycle-2026-09-30/current-email-memory-auth-root218-attempt17/validation.json',
 'local-browser-lifecycle-2026-09-30/current-email-memory-auth-root215-attempt16/validation.json',
 'local-browser-lifecycle-2026-09-30/current-email-memory-auth-root212-attempt15/validation.json',
 'visual-regression-review-2026-10-01/root211-reviewed-candidates/validation.json',
 'visual-regression-review-2026-10-01/root211-reviewed-candidates/publication.json',
 'native-gateway-observation-2026-10-01/current-pure-jvm-root210/validation.json',
 'native-gateway-observation-2026-10-01/flavor-boundary-relocation-root206.json',
 'final-local-flutter-2026-10-01/current-final-set-attempt1/validation.json',
 'gateway-reduced-motion-2026-10-01/root216-current-regressions/validation.json',
]
SECURITY_COLLECTION = Path("/Volumes/PRO-G40/Application Data/Codex/Codex-Home/state/plugins/codex-security/scans/local-qa-recovery-readback/artifacts-9695f9c8ce578ca8bc6c373da4f9f51094b3325c86b2d5d45318b79ccb0b6e6d")
SECURITY_PACKETS = ["artifacts/02_discovery/validation_artifacts/local-qa-bootstrap/rotation1/result.json",
                    "artifacts/02_discovery/validation_artifacts/local-qa-bootstrap/rotation1/independent-readback2.json"]


def inventory():
    return [{"path": str(path.relative_to(ROOT)), "version": path.name.split("_", 1)[0],
             "bytes": path.stat().st_size, "sha256": R.sha(path.read_bytes()),
             "normalized_sha256": R.sha(path.read_text().rstrip().encode())}
            for path in sorted((ROOT / "supabase/migrations").glob("*.sql"))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(RELEASE):
        parser.error("Fresh release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    old = {name: (RELEASE / name).read_bytes() for name in NAMES}
    for name, body in old.items():
        (report / name).write_bytes(body)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    prior = {name: R.sha(body) for name, body in old.items()}
    original_local = json.loads(old[NAMES[0]])
    original_prod = json.loads(old[NAMES[2]])
    local_data, production = deepcopy(original_local), deepcopy(original_prod)
    guard = R.guard(154, "20260930230000")
    before = R.snapshot()
    raw_migrations = inventory()
    migrations = deepcopy(raw_migrations)
    registry = json.loads(U.psql("postgres", """select jsonb_agg(jsonb_build_object(
      'version',version,'name',name,'normalized_sha256',encode(extensions.digest(rtrim(statements[1],E'\\n\\r '),'sha256'),'hex')) order by version)
      from supabase_migrations.schema_migrations;""").stdout)
    installed = {item["version"]: item for item in registry}
    for item in migrations:
        item["installed"] = item["version"] in installed
        item["registry_normalized_source_match"] = item["installed"] and item["normalized_sha256"] == installed[item["version"]]["normalized_sha256"]
    staged = [item["version"] for item in migrations if not item["installed"]]
    ordinary_path = RELEASE / "local-database-runtime-2026-09-30/ordinary-installer-current177-attempt5-final-policy/result.json"
    ordinary = json.loads(ordinary_path.read_text())
    ordinary_current = (
        ordinary.get("status") == "pass" and ordinary.get("all_task_containers_removed") is True
        and {item["path"]: item["sha256"] for item in ordinary["source_inventory"]}
        == {item["path"]: item["sha256"] for item in migrations}
        and all(len(ordinary["phases"][phase]["migrations"]) == len(migrations)
            and ordinary["phases"][phase]["status"] == "pass"
            and all(row["status"] == "pass" and row["actual_installer_authority"]["superuser"] is False
                for row in ordinary["phases"][phase]["migrations"])
            for phase in ("clean", "populated"))
    )
    browser_proof_path = RELEASE / "local-browser-lifecycle-2026-09-30/current-email-memory-auth-root218-attempt17/validation.json"
    browser_report_path = browser_proof_path.parent / "report.json"
    browser_proof = json.loads(browser_proof_path.read_bytes())
    browser_report = json.loads(browser_report_path.read_bytes())
    browser_binding = json.loads((browser_proof_path.parent / "source-binding.json").read_bytes())
    browser_inputs = browser_binding["inputs_sha256"]
    assert browser_proof["status"] == browser_report["status"] == "pass"
    assert browser_proof["report_sha256"] == R.sha(browser_report_path.read_bytes())
    assert browser_proof["actual_browser_return_code"] == 0
    assert browser_proof["source_inputs_current"] and browser_proof["runtime_executables_unchanged"]
    assert browser_proof["whole_L18_original_local_criterion_complete"] and not browser_proof["whole_L01_complete"]
    assert not browser_proof["checkout_input_drift"] and not browser_proof["export_drift"]
    assert len(browser_inputs) == browser_binding["source_count"] == browser_proof["source_input_count"]
    assert len(browser_report["checks"]) == 26 and all(row["status"] == "pass" for row in browser_report["checks"])
    assert len(browser_report["coverage"]) == 16 and all(browser_report["coverage"].values())
    assert not browser_report["errors"] and browser_report["source_inputs_stable"]
    assert all((ROOT / name).is_file() and R.sha((ROOT / name).read_bytes()) == digest
               for name, digest in browser_inputs.items())
    browser_closure = dict(id="L18", status="complete", checks=26, actual_coverage_cases=16,
        current_captured_input_count=len(browser_inputs), report_sha256=R.sha(browser_report_path.read_bytes()),
        scoped_acceptance_sha256=R.sha(browser_proof_path.read_bytes()),
        scope="Original local browser/PWA criterion only; current root218 normal Admin/Public rebuild with explicit compiler/fixture/build inputs; original dated failures preserved; no whole L01, hosted, physical-device, design or production closure")
    R.save(report / "browser-local-closure-proof.json", browser_closure)
    now = dt.datetime.now(dt.timezone.utc)
    timestamp = now.isoformat()
    date = now.astimezone(ZoneInfo("Africa/Kigali")).strftime("%d %B %Y")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    status = subprocess.check_output(["git", "status", "--porcelain=v1"], cwd=ROOT, text=True)
    R.save(report / "source-table-catalog-cron.json", before)
    R.save(report / "migration-source-inventory.json", migrations)
    evidence = []
    for relative in PACKETS:
        path = RELEASE / relative
        body = path.read_bytes()
        decoded = json.loads(body)
        fallback = ("pass_scoped" if decoded["passed"] else "failed") if isinstance(decoded.get("passed"), bool) else "see_scoped_manifest"
        evidence.append(dict(path=str(path.relative_to(ROOT)), sha256=R.sha(body),
                             observed_status=decoded.get("status", decoded.get("result", fallback))))
    for relative in SECURITY_PACKETS:
        path = SECURITY_COLLECTION / relative
        body = path.read_bytes()
        decoded = json.loads(body)
        if decoded.get("status") != "pass" or decoded.get("keys_retained") is not False:
            raise RuntimeError("Managed local-key security proof is incomplete")
        evidence.append(dict(path=str(path), sha256=R.sha(body), observed_status=decoded["status"],
                             storage="persistent_security_plugin_collection", keys_retained=False))
    readback = dict(captured_at_utc=timestamp, guard=guard, migration_count=154,
                    latest_installed_version="20260930230000", table_count=len(before["tables"]),
                    source_migration_count=len(migrations), staged_source_versions=staged,
                    source_inventory_sha256=R.sha((report / "migration-source-inventory.json").read_bytes()),
                    table_catalog_cron_sha256=R.sha((report / "source-table-catalog-cron.json").read_bytes()),
                    head=head, working_tree_status_entries=len(status.splitlines()),
                    source_frozen=False, hosted_state_refreshed=False, provider_called=False)
    if inventory() != raw_migrations or before != R.snapshot():
        raise RuntimeError("Source changed during read-only capture; prior registers preserved")
    R.guard(154, "20260930230000")
    R.save(report / "current-readback.json", readback)
    # Preserve earlier status fields in the immutable five-file backup. These
    # notes describe remaining scope without replacing any acceptance criterion.
    notes = {
      "L01": "Roster recovery/Auth/calendar have accepted scoped SQL, VM, Chrome and normal-browser sections. Bind current email/approval and common source, verifying materially changed paths; no final-source closure.",
      "L03": "Actual SDK private-provider defects were corrected with70 accepted cases. The reproduced receipt identity mismatch is corrected by saved session/identity equality fences, now accepted in238 current receipt/policy/preference tests and4 actual Chrome checkpoints with972 source and SDK inputs unchanged. Full current provider/dialog/session integration remains.",
      "L04": "Current238 receipt/policy/preference tests and4 browser checkpoints pass, including exact cancellation ACK/checkpoint recovery, uncertainty, late session/permission departure and policy expiry/refresh. One frame-wait fixture correction preserves the exact two-refresh-request assertion. Final complete action/audit/source integration remains.",
      "L05": "Current declared Admin route set is28. Entity/private-provider scoped243 and four browser adapters pass, with earlier aggregate failures retained. Full current cohort aggregate, source-stable route/action/provider/state inventory and actual browser acceptance remain.",
      "L07": "Exposed local QA bootstrap key replacement is verified:old synthetic ciphertext no longer decrypts, fresh crypto succeeds, both files0600/postgres, same retained image/data volume, old container absent and no literal key in active startup. Independent readback preserves all153 shared tables/catalog/cron plus internal rows/schema; managed proof retains no keys. Full current client/Edge/log/export negative coverage remains.",
      "L08": "Current18 staged sensitive suite passes126 actual public RPC/role/ACL/reason/audit/retry checks and8 observed blocking authority races. Current18 RLS snapshot suite passes19/nine positives across legacy/email transition and email cutover; committed revocation refuses established snapshots with40001. Shared154/153tables/catalog/cron preserved; complete final cross-group/role/RLS scope remains.",
      "L12": "Installed154 invitation40/6blocking races and QR save80 remain dated. Current13 email actions133 establish exact ACK/Unicode reason/audit/private-helper contracts. Current16 sensitive Unicode reproduction122PASS/4FAIL led to235700:127candidatePASS/8races, followed by126 integrated current18PASS/8races. Full current import/export resource/formula/permission/audit coverage remains.",
      "L14": "Actual1000/10000 genuine posting baseline passes248 scoped checks, preserving triggers and all153 shared tables/catalog/cron. Outer source inventory refuses the added175th actor-only migration; separately accepted current21 source proves that delta. Actual10000 nested page plans scan10000 rows unnecessarily for unfiltered/deep history. Candidate comparison1 stopped on a transient Docker read refusal before candidate application;107 history cases plus schema passed and cleanup preserved shared source. Current3-arm index/leading-cursor comparison and demonstrated beneficial integration remain.",
      "L15": "Accepted Data22 has744VM/299actualChrome with clean scoped analysis; current21 actual postings/sort-cursor history pass72 with finalizer/triggers intact. Their actual SQL receipts pass6VM/6Chrome decoder bridges. Current consumer inventory indexes103 files/20 families and all71 symbol-reference files. Newly added Admin references and final common-source integration remain; shared154 is unchanged.",
      "L16": "Actual lockedSDK/Phoenix loopback reproduced3 departed-frame refresh defects. Unique scoped topics and sticky callback fences pass18 cases/zero failures/errors/skips with fatal analysis clean and849source/6191export inputs unchanged. Four live runtime/test hashes and exactly3 repository substitutions are bound; common-source/full cache lifecycle integration remains.",
      "L20": "Single-body Unicode-reason correction passes1330 actual contract checks. Current21 full26 runtime-family races pass108 assertions with78 observed blocking overlaps, exact actor/session/reason audit and shared153 preservation. Current238 receipt/policy/preference tests cover settings/preference recovery, policy TTL/permissions and exact ACK behavior. Full current feature-flag/copy consumer aggregate and source integration remain.",
      "L21": "Public seven-capture execution, byte-identical visual review transfer and publication pass; static rebuild passes55 and actual Public browser76 cases/181 captures pass. Additive166 binds actual158 served assets, correcting the dated scope label without rewriting159. Current168 proves242/242 reachable runtime Dart files across four entrypoints, zero unresolved assets/directives and deterministic688-component source SBOM. Final common-source cleanup/licence/reachability binding remains.",
      "L22": "Current168 source inventory/SBOM is accepted. The receipt identity fence now has238-test/4-browser semantic acceptance; strict common165 is dated by that saved production change. Nine Swift binary artifact paths need guarded relocation/binding. Fresh common acceptance, unsigned production/Gateway/iOS builds, native lint/JVM/warnings and native graphs/SBOM remain.",
      "L23": "Current21 staged populated schema154 clone passes81 checks with exact175 source,24 private-table protections and unchanged153 shared rows/catalog/cron. Genuine cancellation passes14 and all26 runtime races pass108/78 overlaps. Current175 ordinary-installer clean/populated rehearsal passes32 checks and350 migration executions: installer NOSUPERUSER/no cron DML throughout, all51 post124 migrations preserve18 predecessor projections, cronoff/net0/history0 and both task containers removed. Managed cron ownership plus installer-only alter_job execution prerequisite were verified against quiet154; two failed rehearsals retained. Final compatibility/rollback/full-suite/current-source integration remains.",
      "L24": "All24 local and102 production acceptance criteria, original closure IDs and five prior registers are preserved. Latest proof packets include current21/175 stage, runtime races, genuine cancellation/history, Public and source reachability, with earlier failures retained. Fresh quiet154 readback and final frozen-source reproducible handover remain.",
    }
    notes.update({
        "L01": "Current normal browser email/memory-only Auth passes26 checks/16 cases withcurrent source/runtime bindings hash-bound in root218. Reference-only storage and fresh-sign-in reload denial are current; whole149 recovery/quota/CAS/final source acceptance remains separate.",
        "L05": "Current source inventory18 enumerates28 routes,96 endpoints/79 active,38 providers,14 dialogs,212 callbacks and120 API sites. Full95 run52 has2863 pass/one raw-SMS pending-render failure/two dated receipt skips. Complete corrected raw-SMS file56 passes6 with real replacement-render waits and old evidence absence. Final215-file suite is separately running; no matrix-wide execution is inferred from references.",
        "L14": "Same-dataset four-arm actual API comparison passes455 checks per1000/10000 volume. All432 windows per volume retain byte-equivalent authorized fields/totals/revisions;12 global windows examine below half baseline payment rows and strictly fewer buffers. Additive095000 publishes four partial indexes, exact seek/title function and integrity guard. Published frozen177 history runs at1000/10000 each pass146 checks, with exact pending counts, six notification pages, rollback-only zero queue and four concurrent sorts per volume; full exact-summary scan remains required.",
        "L18": "Complete original local browser/PWA criterion: actual production Admin and separate Public builds pass26 checks/all16 lifecycle cases, including current email/memory-only Auth, reference-only bookmark, fresh-sign-in reload, multi-tab departure protocol, logout/A-B-A, offline installed PWA, warm/failed updates and legacy cache privacy.Current root218 normal Admin/Public rebuild and all captured source/runtime bytes are verified. Original broad wrapper failure is retained; no hosted/device/design or whole L01 acceptance inferred.",
        "L22": "Actual unsigned iOS127 compilation0 and199-file/41609096-byte postbuild verification remain accepted at their captured source; review190 individually reconciles23 warning strings/19 primary/4 duplicate renderings,14 compiler aliases,9 artifact relocations and13 pinned checkouts. Later source changes date broad currentness. Android125/126 compiled unsigned but full lint failed4 actual API/permission errors. Current flavor-only Gateway isolation removes privileged code from production and fresh production lint passes. Current production/Gateway APK, native JVM, individual warning review and observed graph/SBOM completion remain pending. Current48 Gateway pure JVM cases pass; whole native/release acceptance is open.",
        "L23": "Current23-stage clone passes86 checks with177 sources/26 protected private tables; later metadata-only policy-scope stage23 also passes86. Both177 ordinary clean/populated executions completed177 migrations/phase with18 predecessor projections preserved, no superuser/cronDML/net. The earlier peer source guard failure remains dated evidence; fresh ordinary177 attempt5 passes all32 checks/354 migrations with current bytes and both containers removed.400 Edge units,86 actual HTTP checks/all11 entrypoints and146 MCP tests/type checking pass in their source scopes. Full Flutter179 finished with4450 passes/17 failed/0 skipped/0 unfinished; original failures remain retained. Omitted export inputs, Gateway motion/typography, exact11-endpoint list and upstream dummy parser fixtures are corrected. Five intentional visual differences were individually reviewed and published; isolated13-capture/14-check regression passes without changing tolerance. Current48 Gateway JVM tests pass. Current affected12-file aggregate passes167 tests with no failures/skips/unfinished; three public-SDK Auth parser/JWKS rejection tests and fatal analysis pass. Current Android flavored build/lint/JVM/SBOM integration remains pending.",
        "L24": "Original24 local and102 production acceptance criteria remain intact. New successful and failed browser/iOS/Swift/query/Admin/current23/Edge/MCP packets are hash-bound; only exact local L18 closure is added. Entire final source and production acceptance remain unverified.",
    })
    for item in local_data["items"]:
        if item["id"] == "L18":
            item["status"] = "complete"
            item["completed_at_utc"] = timestamp
            item["completion_evidence"] += [str(browser_proof_path.relative_to(ROOT)), str(browser_report_path.relative_to(ROOT)),
                                            str((report / "browser-local-closure-proof.json").relative_to(ROOT))]
        if item["id"] in notes:
            item["verified_progress"] = notes[item["id"]]
        if item["id"] in ("L08", "L12", "L15"):
            item["status"] = "in_progress"
    local_data.update(captured_at_utc=timestamp, snapshot_revision=original_local["snapshot_revision"] + 1,
                      current_local_migration_count=154, current_local_table_count=len(before["tables"]),
                      source_migration_count=len(migrations), staged_source_migrations=staged)
    local_data["latest_verified_local_result"] = dict(migration_count=154, table_count=len(before["tables"]),
        readback=str((report / "current-readback.json").relative_to(ROOT)),
        readback_sha256=R.sha((report / "current-readback.json").read_bytes()), evidence_packets=evidence,
        scope="Fresh154 readback and explicitly scoped packets; final whole-source acceptance unproven", whole_goal_complete=False)
    local_data["previous_latest_verified_local_result"] = original_local["latest_verified_local_result"]
    closed = [item["id"] for item in local_data["items"] if item["status"] == "complete"]
    assert set(closed) == set(original_local["locally_closed_goal_items"]) | {"L18"}
    local_data["locally_closed_goal_items"] = closed
    assert [item["id"] for item in local_data["items"]] == [item["id"] for item in original_local["items"]]
    assert all(item["local_acceptance"] == prior_item["local_acceptance"] for item, prior_item in zip(local_data["items"], original_local["items"]))
    observation = dict(captured_at_utc=timestamp, fixture="collect_fin_concurrency_qa_20260929",
        migration_count=154, table_count=len(before["tables"]), last_migration="20260930230000",
        cron_launch_active_jobs="off", pg_net_batch_size=0, worker_sessions_remaining=guard["busy"],
        docker_labels_verified=True, scope="Exact quiet shared-source guard/readback; unique synthetic clones are separately scoped")
    production["historical_local_fixture_readonly_observation"] = original_prod["local_fixture_readonly_observation"]
    production.update(captured_at_utc=timestamp, as_of=now.astimezone(ZoneInfo("Africa/Kigali")).date().isoformat(),
        supersedes_captured_at_utc=original_prod["captured_at_utc"], snapshot_revision=original_prod["snapshot_revision"] + 1,
        installed_table_count=len(before["tables"]), isolated_local_registry_migration_count=154,
        isolated_local_table_count=len(before["tables"]), local_upgrade_registry_migration_count=154,
        source_migration_count=len(migrations), staged_source_versions=staged, staged_source_migrations=staged,
        local_fixture_readonly_observation=observation, local_progress_refreshed_at_utc=timestamp,
        local_progress_readback=local_data["latest_verified_local_result"]["readback"],
        local_progress_note=f"7 local goals closed;17 open.154 installed/153 tables;{len(migrations)} current source migrations with{len(staged)} staged versions. Current23-stage/177-source local upgrade and full current177 ordinary clean/populated replay are scoped evidence; final compatibility and whole-source verification remain.",
        current_local_scoped_packets=evidence, base_commit=head, working_tree_status_entries=len(status.splitlines()),
        frozen_candidate=False, external_state_refreshed_for_this_report=False)
    assert production["items"] == original_prod["items"] and len(production["items"]) == 102
    assert production["locally_closed_ids"] == original_prod["locally_closed_ids"] == ["G06"]
    assert production["open_acceptance_checks"] == 101
    local_md = f"# Collect local implementation register\n\nCaptured: {timestamp}. Revision{local_data['snapshot_revision']}.\n\n**7 of24 local goals verified complete;17 remain open.** Original102 production criteria retain their acceptance scope.\n\nInstalled local registry:154 migrations/{len(before['tables'])} tables. {len(migrations)} source files; staged versions: {', '.join(staged)}. Final whole-source acceptance is pending.\n\n| ID | Task | Status | Remaining scope or verified result |\n| --- | --- | --- | --- |\n"
    local_md += "\n".join(f"| {item['id']} | {item['title']} | {item['status']} | {item.get('verified_progress', item['local_acceptance']).replace('|', '/')} |" for item in local_data["items"])
    local_md += "\n\n## Original local acceptance criteria" + old[NAMES[1]].decode().split("## Original local acceptance criteria", 1)[1]
    prod_suffix = "## G — Source and governance" + old[NAMES[3]].decode().split("## G — Source and governance", 1)[1]
    production_md = f"# Collect — exhaustive remaining production tasks\n\n**Snapshot: {date} (Africa/Kigali), revision{production['snapshot_revision']}. Release decision: NO-GO.**\n\n**101 acceptance checks remain open:99 of100 original tasks, plus X01 and X02.** G06 remains locally closed; every original acceptance criterion is preserved.\n\n| Priority | Open |\n| --- | ---: |\n| P0 |24|\n| P1 |71|\n| P2 |4|\n| Crosscutting |2|\n| **Total** |**101**|\n\nEvidence states remain67 Partial,27 External,7 Unverified.\n\nSource: HEAD {head} plus{len(status.splitlines())} working-tree entries captured at {timestamp}. No release candidate is frozen. {len(migrations)} source migrations are present; the exact quiet local registry has154 installed migrations/{len(before['tables'])} tables. Staged versions: {', '.join(staged)}. Current177 clean/populated local replay uses an installer without superuser or direct cron DML after explicit platform prerequisites; final compatibility and whole-source acceptance remain.\n\n## Latest verified local progress and limits\n\n"
    production_md += "\n".join(f"- **{item['id']}:** {item['verified_progress']}" for item in local_data["items"] if item["id"] in notes)
    production_md += f"\n\nThe [local progress packet]({report.relative_to(RELEASE)}/validation.json) preserves all five prior registers and binds the current154 readback, migration inventory and scoped packets. Seven local closures are L02/L06/L09/L10/L11/L13/L18;17 local goals remain open. Hosted/provider/device/signing/store acceptance is not refreshed.\n\n" + prod_suffix
    bodies = {NAMES[0]: (json.dumps(local_data, indent=2, sort_keys=True) + "\n").encode(),
              NAMES[1]: local_md.encode(), NAMES[2]: (json.dumps(production, indent=2, sort_keys=True) + "\n").encode(),
              NAMES[3]: production_md.encode()}
    validation = dict(status="pass", scope="Register integrity and scoped154 progress only; not whole-system acceptance",
        validated_at_utc=timestamp, snapshot_revision=production["snapshot_revision"], local_snapshot_revision=local_data["snapshot_revision"],
        all_original_ids_preserved=True, original_criteria_preserved=True, local_criteria_preserved=True,
        closed_ids=["G06"], local_goal_closed_ids=closed, unique_open_rows=101,
        installed_migration_count=154, installed_table_count=len(before["tables"]),
        source_migration_count=len(migrations), staged_source_versions=staged,
        last_complete_clean_replay=141, last_complete_clean_replay_scope="Historical normal-owner fixture only; not latest owner-normalized DDL replay",
        latest_owner_normalized_ddl_replay=163, owner_normalized_ddl_installer_superuser=True,
        latest_ordinary_local_ddl_replay=len(ordinary["source_inventory"]),
        latest_ordinary_local_ddl_replay_sha256=R.sha(ordinary_path.read_bytes()),
        ordinary_current_clean_and_populated_verified=ordinary_current,
        final_current_clean_replay_verified=ordinary_current, full_current_source_acceptance=False, external_state_refreshed=False,
        prior_revision_preserved=prior, new_scoped_evidence_packets=evidence,
        priority_counts=dict(Counter(item["priority"] for item in production["items"] if item["open"])),
        sha256={name: R.sha(body) for name, body in bodies.items()})
    bodies[NAMES[4]] = (json.dumps(validation, indent=2, sort_keys=True) + "\n").encode()
    if any((RELEASE / name).read_bytes() != body for name, body in old.items()):
        raise RuntimeError("A register owner changed the source during refresh; do not overwrite")
    for name, body in bodies.items():
        temporary = RELEASE / (name + ".refresh154.tmp")
        with temporary.open("xb") as handle:
            handle.write(body)
        temporary.replace(RELEASE / name)
    assert all((RELEASE / name).read_bytes() == body for name, body in bodies.items())
    validation["published_sha256"] = {name: R.sha(body) for name, body in bodies.items()}
    R.save(report / "validation.json", validation)
    print(json.dumps(dict(status="pass", installed=154, tables=len(before["tables"]),
                          source=len(migrations), staged=staged, local_closed=7, local_open=17,
                          production_open=101, prior_registers_preserved=5)))


if __name__ == "__main__":
    main()
