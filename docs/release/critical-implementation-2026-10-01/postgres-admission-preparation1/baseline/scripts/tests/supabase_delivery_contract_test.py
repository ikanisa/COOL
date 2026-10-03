#!/usr/bin/env python3
"""Offline executable deployment, pinning and readiness probe contract tests."""

import json
import datetime as dt
import importlib.util
import hashlib
import sys
import uuid
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REF = "abcdefghijklmnopqrst"
MOCK_CLI = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args == ["--version"]:
    print(os.environ.get("MOCK_CLI_VERSION", "2.114.0")); sys.exit(0)
with Path(os.environ["MOCK_CALLS"]).open("a") as f: f.write(json.dumps(args) + "\n")
with Path(os.environ["MOCK_CWD"]).open("a") as f:
    f.write(json.dumps({"args":args,"cwd":os.getcwd(),"link":Path("supabase/.temp/project-ref").read_text(),"companion":os.environ.get("SUPABASE_GO_BINARY")})+"\n")
state = Path(os.environ["MOCK_FUNCTION_STATE"])
functions = json.loads(state.read_text()) if state.exists() else {"stripe-webhook":False}
history = Path(os.environ["MOCK_HISTORY"])
if args[:2] == ["projects", "list"]:
    print(json.dumps([{ "id":os.environ.get("MOCK_VISIBLE_REF","abcdefghijklmnopqrst") }]))
elif args[:2] == ["functions", "list"]:
    if os.environ.get("MOCK_HIDE_FUNCTION"): functions.pop(os.environ["MOCK_HIDE_FUNCTION"],None)
    print(json.dumps([{"name":n,"verify_jwt":v} for n,v in functions.items()]))
elif args[:2] == ["functions", "delete"]:
    functions.pop(args[2],None); state.write_text(json.dumps(functions))
elif args[:2] == ["functions", "deploy"]:
    if os.environ.get("MOCK_FAIL_DEPLOY") == args[2]: sys.exit(1)
    functions[args[2]] = "--no-verify-jwt" not in args; state.write_text(json.dumps(functions))
elif args[:2] == ["db", "push"]:
    if "--dry-run" in args:
        if os.environ.get("MOCK_DRIFT_SOURCE"):
            Path(os.environ["MOCK_DRIFT_SOURCE"]).write_text("changed after preflight")
        if os.environ.get("MOCK_DRIFT_COMPANION"):
            Path(os.environ["SUPABASE_GO_BINARY"]).write_text("changed companion after preflight")
        if os.environ.get("MOCK_DRIFT_STAGE"):
            Path(os.environ["MOCK_DRIFT_STAGE"]).write_text("changed during dry run")
        if os.environ.get("MOCK_RUNTIME_EXTRA"):
            Path("supabase/.temp/unreviewed.ts").write_text("unreviewed source")
        if os.environ.get("MOCK_RUNTIME_WRONG_TARGET"):
            Path("supabase/.temp/project-ref").write_text("z"*20)
        if os.environ.get("MOCK_CONNECTIVITY_FAILURE"):
            print("failed to connect to postgres",file=sys.stderr);sys.exit(1)
        if os.environ.get("MOCK_DRY_RUN_ERROR"):
            print("permission denied",file=sys.stderr);sys.exit(1)
    else:
        rows = [{"version":p.name.split("_",1)[0],"name":p.name.split("_",1)[1][:-4]} for p in sorted(Path("supabase/migrations").glob("*.sql"))]
        if os.environ.get("MOCK_HISTORY_MISMATCH"): rows=rows[:-1]
        history.write_text(json.dumps(rows))
        if os.environ.get("MOCK_APPLY_LOST_REPLY"): sys.exit(1)
'''

MOCK_DENO = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
if sys.argv[1:]==["--version"]:
    print("deno "+os.environ.get("MOCK_DENO_VERSION","2.5.6"));sys.exit(0)
with Path(os.environ["MOCK_DENO_CALLS"]).open("a") as f:f.write(json.dumps(sys.argv[1:])+"\n")
sys.exit(1 if os.environ.get("MOCK_CLOSURE_FAIL") else 0)
'''

MOCK_CURL = r'''#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
args = sys.argv[1:]
with Path(os.environ["MOCK_PROBES"]).open("a") as f: f.write(json.dumps(args) + "\n")
if any("/database/query" in arg for arg in args):
    query=json.loads(sys.stdin.read())["query"]
    path=Path(os.environ["MOCK_HISTORY"]);rows=json.loads(path.read_text()) if path.exists() else []
    if "insert into supabase_migrations.schema_migrations" in query:
        match=re.search(r"values \('([^']+)', array\[[^]]+\], '([^']+)'",query)
        if os.environ.get("MOCK_FAIL_MIGRATION")==match[1]:
            print("{}\n500");sys.exit(0)
        rows.append({"version":match[1],"name":match[2]});path.write_text(json.dumps(rows))
        if os.environ.get("MOCK_MANAGEMENT_DRIFT"):
            Path(os.environ["MOCK_MANAGEMENT_DRIFT"]).write_text("mid-management drift")
        data=[]
    elif "select count(*)" in query:
        version=re.search(r"version = '([^']+)'",query)[1];data=[{"count":sum(r["version"]==version for r in rows)}]
    else: data=rows
    print(json.dumps(data)+"\n200");sys.exit(0)
slug = next(arg.rsplit("/", 1)[-1] for arg in args if "/functions/v1/" in arg)
status, code = {
    "auth-send-whatsapp-otp": (401, "invalid_hook_signature"),
    "collect-android-gateway": (400, "GATEWAY_REQUEST_INVALID"),
    "collect-receipt-successor-gateway": (400, "GATEWAY_REQUEST_INVALID"),
    "collect-receipt-supervisor": (400, "SUPERVISOR_REQUEST_INVALID"),
    "collect-receipt-exception-worker": (401, "WORKER_AUTH_REQUIRED"),
}.get(slug, (401, "authentication_required"))
if os.environ.get("MOCK_MISSING_ENDPOINT") == slug: status, code = 404, "NOT_FOUND"
if "-o" not in args: print(json.dumps({"error": code}), end="\n")
print(status, end="")
'''



class SupabaseDeliveryContractTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / "repo"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in (
            "supabase_deploy.sh", "supabase_cli_helpers.sh",
            "supabase_production_readiness.sh", "load_dotenv_strict.sh",
            "edge_function_inventory.rb", "edge_function_inventory.sh",
        ):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        shutil.copy2(ROOT / ".supabase-cli-version", self.root / ".supabase-cli-version")
        shutil.copytree(ROOT / "contracts", self.root / "contracts")
        (self.root / "supabase/.temp").mkdir(parents=True)
        (self.root / "supabase/.temp/project-ref").write_text(REF)
        shutil.copy2(ROOT / "supabase/config.toml", self.root / "supabase/config.toml")
        shutil.copytree(ROOT / "supabase/functions", self.root / "supabase/functions")
        (scripts / "migrations").mkdir()
        self.executable(scripts / "migrations/validate_supabase_migrations.sh", "#!/usr/bin/env bash\nexit 0\n")
        self.executable(scripts / "supabase_production_readiness.sh", '#!/usr/bin/env bash\nprintf "%s" "$SUPABASE_READY_STRICT_PLATFORM" > "$MOCK_READINESS"\n')
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.executable(self.bin / "supabase", MOCK_CLI)
        self.executable(self.bin / "supabase-go", '#!/usr/bin/env python3\nprint("2.114.0")\n')
        self.executable(self.bin / "curl", MOCK_CURL)
        self.executable(self.bin / "deno", MOCK_DENO)
        self.env = os.environ.copy()
        self.env.pop("SUPABASE_GO_BINARY", None)
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + self.env["PATH"],
            "SUPABASE_BIN": str(self.bin / "supabase"),
            "COLLECT_SKIP_DOTENV": "1", "SUPABASE_ACCESS_TOKEN": "test-only-token",
            "SUPABASE_PROJECT_REF": REF, "CONFIRM_SUPABASE_DEPLOY": REF,
            "SUPABASE_DB_PASSWORD": "test-only-password",
            "SUPABASE_URL": f"https://{REF}.supabase.co",
            "DATABASE_URL": f"postgresql://postgres@db.{REF}.supabase.co:5432/postgres",
            "DENO_BIN": str(self.bin / "deno"),
            "MOCK_DENO_CALLS": str(self.base / "deno-calls.jsonl"),
            "MOCK_HISTORY": str(self.base / "history.json"),
            "MOCK_FUNCTION_STATE": str(self.base / "functions.json"),
            "MOCK_CWD": str(self.base / "cwd.jsonl"),
            "MOCK_CALLS": str(self.root / "calls.jsonl"),
            "MOCK_PROBES": str(self.root / "probes.jsonl"),
            "MOCK_READINESS": str(self.root / "readiness-strict.txt"),
        })
        for name in ("qa/backend_release_delivery.py", "qa/collect_release_candidate.py"):
            (scripts / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        for name in ("supabase_schema_inventory.sh", "audits/collect_index_inventory.rb",
                     "supabase_advisors_gate.sh", "supabase_advisors_warning_inventory.sh",
                     "collect_linked_uat.sh", "rwanda_momo_readiness_uat.sql", "collect_admin_security_uat.sh"):
            (scripts / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        shutil.copytree(ROOT / "supabase/migrations", self.root / "supabase/migrations")
        sys.path.insert(0, str(ROOT / "scripts/qa"))
        import collect_release_candidate
        import backend_release_delivery
        self.candidate, self.delivery = collect_release_candidate, backend_release_delivery
        for name in self.candidate.REQUIRED:
            p = self.root / name
            if not p.exists(): p.parent.mkdir(parents=True, exist_ok=True); p.write_text("synthetic source")
        (self.root / ".fvmrc").write_text(json.dumps({"flutter":"3.44.4"}))
        (self.root / ".dvmrc").write_text("2.5.6\n")
        (self.root / "tools/collect-notification-mcp/package.json").write_text(json.dumps({"dependencies":{}}))
        self.sdk = self.base / "sdk"
        (self.sdk / "bin/cache").mkdir(parents=True)
        (self.sdk / "bin/flutter").write_text("synthetic launcher")
        (self.sdk / "bin/cache/flutter.version.json").write_text(json.dumps({"frameworkVersion":"3.44.4","frameworkRevision":"synthetic","dartSdkVersion":"3.12.2"}))
        self.attempt = 0
        self.reviewed_fixture()

    def reviewed_fixture(self, operations=None, environment="production"):
        export = self.base / "candidate"
        if export.exists(): shutil.rmtree(export)
        result = self.candidate.export_candidate(self.root, export, self.sdk)
        manifest = json.loads((export / self.candidate.MANIFEST).read_text())
        now = dt.datetime.now(dt.timezone.utc)
        self.approval = {
            "schema_version":1,"kind":"collect_backend_deployment_approval",
            "approval_id":str(uuid.uuid4()),"reviewer":"synthetic unit-test reviewer; no human approval",
            "approved_at_utc":(now-dt.timedelta(seconds=1)).isoformat(),
            "expires_at_utc":(now+dt.timedelta(hours=1)).isoformat(),
            "candidate_manifest_sha256":result["manifest_sha256"],
            "backend_manifest_sha256":self.candidate.sha(self.candidate.canonical(self.delivery.backend_files(manifest))),
            "target":{"project_ref":REF,"url":f"https://{REF}.supabase.co","environment":environment},
            "purpose":"remediation","operations":operations if operations is not None else list(self.delivery.OPERATIONS),
            "toolchain":{name:{"version":version,"binary_sha256":self.candidate.sha((self.bin/binary).read_bytes())} for name,binary,version in [("supabase","supabase","2.114.0"),("supabase_go","supabase-go","2.114.0"),("deno","deno","2.5.6")]},
        }
        self.env.update(COLLECT_BACKEND_CANDIDATE=str(export),COLLECT_BACKEND_MANIFEST_SHA256=result["manifest_sha256"],COLLECT_BACKEND_ENVIRONMENT=environment)
        self.bind_approval()

    def bind_approval(self):
        path=self.base/"approval.json";path.write_bytes(self.candidate.canonical(self.approval))
        self.env.update(COLLECT_BACKEND_APPROVAL=str(path),COLLECT_BACKEND_APPROVAL_SHA256=self.candidate.sha(path.read_bytes()))

    @staticmethod
    def executable(path, source):
        path.write_text(source)
        path.chmod(0o700)

    def run_deploy(self):
        self.attempt += 1
        self.env["COLLECT_BACKEND_RECEIPT"] = str(self.base / f"receipt-{self.attempt}.json")
        return subprocess.run(["bash", str(self.root / "scripts/supabase_deploy.sh")], env=self.env, text=True, capture_output=True)

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_all_thirteen_deploy_with_manifest_auth_modes_and_strict_readiness(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.root / "contracts/edge-functions.json").read_text())
        deployments = [args for args in self.calls() if args[:2] == ["functions", "deploy"]]
        self.assertEqual(len(deployments), 13)
        self.assertEqual({args[2] for args in deployments}, {entry["name"] for entry in manifest["functions"]})
        modes = {entry["name"]: entry["verify_jwt"] for entry in manifest["functions"]}
        for args in deployments:
            self.assertEqual("--no-verify-jwt" in args, not modes[args[2]])
        successor = "collect-receipt-successor-gateway"
        self.assertFalse(modes[successor])
        self.assertFalse(self.receipt()["readback"]["functions"]["observed_auth_modes"][successor])
        self.assertEqual((self.root / "readiness-strict.txt").read_text(), "1")
        self.assertIn(["functions", "delete", "stripe-webhook", "--project-ref", REF, "--yes"], self.calls())

    def test_wrong_cli_pin_stops_before_any_project_operation(self):
        self.env["MOCK_CLI_VERSION"] = "2.113.0"
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DOES_NOT_MATCH_REPOSITORY_VERSION", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_missing_and_swapped_companion_are_refused_before_project_calls(self):
        companion=self.bin/"supabase-go";original=companion.read_text()
        companion.unlink()
        result=self.run_deploy();self.assert_no_remote(result)
        self.assertIn("DEPLOY_SUPABASE_COMPANION_MISSING",result.stderr)
        self.executable(companion,original+"\n# changed binary bytes\n")
        result=self.run_deploy();self.assert_no_remote(result)
        self.assertIn("DEPLOY_TOOLCHAIN_BINDING_INVALID",result.stderr)

    def test_unapproved_companion_override_is_refused(self):
        override=self.bin/"different-go"
        self.executable(override,'#!/usr/bin/env python3\nprint("2.114.0")\n# unrelated executable\n')
        self.env["SUPABASE_GO_BINARY"]=str(override)
        self.assert_no_remote(self.run_deploy())

    def test_companion_drift_after_preflight_stops_before_first_write(self):
        self.env["MOCK_DRIFT_COMPANION"]="1"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertIn("DEPLOY_TOOL_CHANGED",result.stderr)
        self.assertFalse(any(c[:2]==["functions","deploy"] or c[:2]==["functions","delete"] or c[:2]==["db","push"] and "--dry-run" not in c for c in self.calls()))

    def test_missing_local_function_stops_before_any_project_operation(self):
        (self.root / "supabase/functions/reconciliation-finalize/index.ts").unlink()
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DEPLOY_CURRENT_BACKEND_SOURCE_CHANGED", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_connectivity_fallback_preserves_strict_readiness(self):
        self.env["MOCK_CONNECTIVITY_FAILURE"] = "1"
        rows = [{"version":p.name.split("_",1)[0],"name":p.name.split("_",1)[1][:-4]} for p in sorted((self.root/"supabase/migrations").glob("*.sql"))]
        Path(self.env["MOCK_HISTORY"]).write_text(json.dumps(rows[:-1]))
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "readiness-strict.txt").read_text(), "1")

    def receipt(self):
        return json.loads(Path(self.env["COLLECT_BACKEND_RECEIPT"]).read_text())

    def assert_no_remote(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
        path = Path(self.env["MOCK_PROBES"])
        self.assertFalse(path.exists() and path.read_text().strip())

    def pending_history(self, pending):
        rows = [{"version":p.name.split("_",1)[0],"name":p.name.split("_",1)[1][:-4]} for p in sorted((self.root/"supabase/migrations").glob("*.sql"))]
        Path(self.env["MOCK_HISTORY"]).write_text(json.dumps(rows[:-pending] if pending else rows))
        return rows

    def test_missing_approval_and_invalid_operation_scope_have_no_remote_effect(self):
        approval=self.env.pop("COLLECT_BACKEND_APPROVAL")
        self.assert_no_remote(self.run_deploy())
        self.env["COLLECT_BACKEND_APPROVAL"]=approval
        self.approval["operations"]=["unapproved_mutation"]
        self.bind_approval()
        self.assert_no_remote(self.run_deploy())

    def test_missing_strict_readiness_inputs_and_wrong_database_target_stop_before_remote(self):
        self.env.pop("DATABASE_URL")
        self.assert_no_remote(self.run_deploy())
        self.env["DATABASE_URL"]="postgresql://postgres@db."+"z"*20+".supabase.co:5432/postgres"
        self.assert_no_remote(self.run_deploy())

    def test_wrong_approval_hash_blocks_before_any_remote_call(self):
        Path(self.env["COLLECT_BACKEND_APPROVAL"]).write_text("changed approval")
        self.assert_no_remote(self.run_deploy())
        self.assertEqual(self.receipt()["status"], "preflight_blocked")

    def test_expired_approval_with_matching_hash_is_still_refused(self):
        self.approval["expires_at_utc"] = (dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=1)).isoformat()
        self.bind_approval()
        self.assert_no_remote(self.run_deploy())

    def test_wrong_target_environment_and_url_are_refused(self):
        self.env["COLLECT_BACKEND_ENVIRONMENT"] = "staging"
        self.assert_no_remote(self.run_deploy())
        self.env["COLLECT_BACKEND_ENVIRONMENT"] = "production"
        self.env["SUPABASE_URL"] = "https://wrong.supabase.co"
        self.assert_no_remote(self.run_deploy())

    def test_wrong_source_approval_binding_is_refused(self):
        self.approval["backend_manifest_sha256"] = "0"*64
        self.bind_approval()
        self.assert_no_remote(self.run_deploy())

    def test_unbound_candidate_manifest_is_refused(self):
        self.env["COLLECT_BACKEND_MANIFEST_SHA256"] = "0"*64
        self.assert_no_remote(self.run_deploy())

    def test_dirty_candidate_and_unlisted_candidate_source_are_refused(self):
        (Path(self.env["COLLECT_BACKEND_CANDIDATE"])/"supabase/functions/_shared/hash.ts").write_text("changed export")
        self.assert_no_remote(self.run_deploy())
        self.reviewed_fixture()
        (Path(self.env["COLLECT_BACKEND_CANDIDATE"])/"supabase/functions/_shared/extra.ts").write_text("unlisted export")
        self.assert_no_remote(self.run_deploy())

    def test_candidate_runtime_metadata_is_not_ignored_by_preflight(self):
        p=Path(self.env["COLLECT_BACKEND_CANDIDATE"])/"supabase/.temp/project-ref"
        p.parent.mkdir();p.write_text(REF)
        self.assert_no_remote(self.run_deploy())

    def test_stale_worktree_helper_and_added_backend_source_are_refused(self):
        p=self.root/"scripts/supabase_cli_helpers.sh";p.write_text(p.read_text()+"\n# changed after review\n")
        self.assert_no_remote(self.run_deploy())
        self.reviewed_fixture()
        (self.root/"supabase/functions/_shared/ignored-extra.ts").write_text("new unreviewed backend source")
        self.assert_no_remote(self.run_deploy())

    def test_missing_transitive_module_is_refused_before_project_calls(self):
        (self.root/"supabase/functions/_shared/roster_provenance.ts").unlink()
        self.assert_no_remote(self.run_deploy())

    def test_frozen_closure_failure_and_wrong_deno_pin_have_no_remote_effect(self):
        self.env["MOCK_CLOSURE_FAIL"] = "1"
        self.assert_no_remote(self.run_deploy())
        self.env.pop("MOCK_CLOSURE_FAIL")
        self.env["MOCK_DENO_VERSION"] = "2.9.6"
        self.assert_no_remote(self.run_deploy())

    def test_mid_run_worktree_drift_stops_before_first_write(self):
        self.env["MOCK_DRIFT_SOURCE"] = str(self.root/"supabase/functions/_shared/hash.ts")
        result=self.run_deploy()
        self.assertNotEqual(result.returncode,0)
        self.assertIn(["db","push","--dry-run","--skip-vault"],self.calls())
        self.assertFalse(any(c[:2]==["functions","deploy"] or c[:2]==["functions","delete"] or c[:2]==["db","push"] and "--dry-run" not in c for c in self.calls()))

    def test_mid_run_execution_drift_and_unlisted_runtime_metadata_stop_writes(self):
        self.env["MOCK_DRIFT_STAGE"] = "supabase/functions/_shared/hash.ts"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertNotIn(["db","push","--skip-vault"],self.calls())
        self.env.pop("MOCK_DRIFT_STAGE")
        self.env["MOCK_RUNTIME_EXTRA"] = "1"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertNotIn(["db","push","--skip-vault"],self.calls())

    def test_wrong_runtime_link_and_unapproved_dry_run_failure_stop_writes(self):
        self.env["MOCK_RUNTIME_WRONG_TARGET"] = "1"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertNotIn(["db","push","--skip-vault"],self.calls())
        self.env.pop("MOCK_RUNTIME_WRONG_TARGET")
        self.env["MOCK_DRY_RUN_ERROR"] = "1"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertNotIn(["db","push","--skip-vault"],self.calls())

    def test_partial_function_failure_keeps_receipt_and_stops_later_mutations(self):
        names=[r["name"] for r in json.loads((self.root/"contracts/edge-functions.json").read_text())["functions"]]
        self.env["MOCK_FAIL_DEPLOY"] = names[2]
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        attempted=[c[2] for c in self.calls() if c[:2]==["functions","deploy"]]
        self.assertEqual(attempted,names[:3])
        receipt=self.receipt();self.assertEqual(receipt["status"],"partial_or_failed")
        self.assertEqual(receipt["automatic_retries"],0)
        self.assertIn(names[0],receipt["readback"]["functions"]["observed_auth_modes"])
        self.assertFalse((self.root/"readiness-strict.txt").exists())

    def test_lost_migration_reply_is_reconciled_without_retry_or_function_mutation(self):
        self.env["MOCK_APPLY_LOST_REPLY"] = "1"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.calls().count(["db","push","--skip-vault"]),1)
        self.assertFalse(any(c[:2] in [["functions","deploy"],["functions","delete"]] for c in self.calls()))
        self.assertTrue(self.receipt()["readback"]["migrations"]["matches_candidate"])
        self.assertEqual(self.receipt()["status"],"partial_or_failed")

    def test_management_partial_failure_retains_commits_and_stops_functions(self):
        rows=self.pending_history(2)
        self.env.update(MOCK_CONNECTIVITY_FAILURE="1",MOCK_FAIL_MIGRATION=rows[-1]["version"])
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        observed=json.loads(Path(self.env["MOCK_HISTORY"]).read_text())
        self.assertEqual(observed,rows[:-1])
        self.assertFalse(any(c[:2] in [["functions","deploy"],["functions","delete"]] for c in self.calls()))
        self.assertFalse(self.receipt()["readback"]["migrations"]["matches_candidate"])

    def test_management_mid_run_drift_stops_the_next_transport_request(self):
        rows=self.pending_history(2)
        self.env.update(MOCK_CONNECTIVITY_FAILURE="1",MOCK_MANAGEMENT_DRIFT=str(self.root/"supabase/functions/_shared/hash.ts"))
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertEqual(json.loads(Path(self.env["MOCK_HISTORY"]).read_text()),rows[:-1])
        self.assertFalse(any(c[:2] in [["functions","deploy"],["functions","delete"]] for c in self.calls()))
        self.assertIn("unavailable_or_blocked",self.receipt()["readback"]["reconciliation"])

    def test_staging_edge_scope_executes_export_without_production_acceptance(self):
        self.reviewed_fixture(["edge_functions"],"staging")
        self.env.pop("SUPABASE_DB_PASSWORD")
        (self.root/"supabase/.temp/project-ref").write_text("z"*20)
        result=self.run_deploy();self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(any(c[:2]==["db","push"] or c[:2]==["functions","delete"] for c in self.calls()))
        self.assertFalse((self.root/"readiness-strict.txt").exists())
        traces=[json.loads(x) for x in Path(self.env["MOCK_CWD"]).read_text().splitlines()]
        self.assertTrue(all(t["cwd"]!=str(self.root) and t["link"]==REF and t["companion"]==str(self.bin/"supabase-go") for t in traces))
        deno=[json.loads(x) for x in Path(self.env["MOCK_DENO_CALLS"]).read_text().splitlines()]
        self.assertTrue(all("--frozen" in c and "--cached-only" in c and "--no-run" in c for c in deno))
        self.assertEqual(self.receipt()["status"],"delivered_and_read_back")
        self.assertFalse(self.receipt()["human_identity_authenticated"])

    def test_mandatory_migration_readback_failure_blocks_functions(self):
        self.env["MOCK_HISTORY_MISMATCH"] = "1"
        result=self.run_deploy();self.assertNotEqual(result.returncode,0)
        self.assertFalse(any(c[:2] in [["functions","deploy"],["functions","delete"]] for c in self.calls()))
        self.assertFalse(self.receipt()["readback"]["migrations"]["matches_candidate"])

    def test_unsigned_probes_cover_thirteen_endpoints_and_use_no_hook_secret(self):
        script = (ROOT / "scripts/supabase_production_readiness.sh").read_text()
        # Source actual function definitions without executing its remote main.
        self.executable(self.root / "scripts/readiness-functions.sh", script.rsplit('main "$@"', 1)[0])
        command = '. "$1"; supabase_cli() { ruby "$ROOT_DIR/scripts/edge_function_inventory.rb" expected | ruby -r json -e "puts STDIN.readlines.map { |x| {name: x.strip} }.to_json"; }; check_functions'
        result = subprocess.run(["bash", "-c", command, "bash", str(self.root / "scripts/readiness-functions.sh")], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in (self.root / "probes.jsonl").read_text().splitlines()]
        self.assertEqual(len(calls), 13)
        expected = {entry["name"] for entry in json.loads((self.root / "contracts/edge-functions.json").read_text())["functions"]}
        observed = [next(arg.rsplit("/", 1)[-1] for arg in call if "/functions/v1/" in arg) for call in calls]
        self.assertEqual(set(observed), expected)
        self.assertEqual(len(set(observed)), len(observed))
        self.assertFalse(any("x-hook-secret" in arg or "test-only-token" in arg for call in calls for arg in call))
        self.env["MOCK_MISSING_ENDPOINT"] = "collect-receipt-supervisor"
        refused = subprocess.run(["bash", "-c", command, "bash", str(self.root / "scripts/readiness-functions.sh")], env=self.env, text=True, capture_output=True)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("unsigned negative probe", refused.stderr)

    def readiness_probe_command(self):
        script = (ROOT / "scripts/supabase_production_readiness.sh").read_text()
        self.executable(self.root / "scripts/readiness-functions.sh", script.rsplit('main "$@"', 1)[0])
        command = '. "$1"; supabase_cli() { ruby "$ROOT_DIR/scripts/edge_function_inventory.rb" expected | ruby -r json -e "puts STDIN.readlines.map { |x| {name: x.strip} }.to_json"; }; check_functions'
        return ["bash", "-c", command, "bash", str(self.root / "scripts/readiness-functions.sh")]

    def test_unsigned_successor_probe_is_empty_json_without_signed_device_or_bearer_inputs(self):
        result = subprocess.run(self.readiness_probe_command(), env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in Path(self.env["MOCK_PROBES"]).read_text().splitlines()]
        successor = [call for call in calls if any(arg.endswith("/functions/v1/collect-receipt-successor-gateway") for arg in call)]
        self.assertEqual(len(successor), 1)
        args = successor[0]
        self.assertEqual(args[args.index("-X") + 1], "POST")
        self.assertEqual(args[args.index("--data") + 1], "{}")
        headers = [args[index + 1] for index, arg in enumerate(args) if arg == "-H"]
        self.assertEqual(headers, ["content-type: application/json"])
        self.assertFalse(any("authorization" in arg.lower() or "x-collect-gateway" in arg.lower() for arg in args))

    def test_missing_successor_endpoint_refuses_readiness(self):
        self.env["MOCK_MISSING_ENDPOINT"] = "collect-receipt-successor-gateway"
        result = subprocess.run(self.readiness_probe_command(), env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("collect-receipt-successor-gateway unsigned negative probe", result.stderr)

    def test_missing_successor_deploy_readback_stops_before_strict_readiness(self):
        self.env["MOCK_HIDE_FUNCTION"] = "collect-receipt-successor-gateway"
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "readiness-strict.txt").exists())
        self.assertNotIn("collect-receipt-successor-gateway", self.receipt()["readback"]["functions"]["observed_auth_modes"])

    def test_missing_successor_local_source_refuses_before_any_project_operation(self):
        (self.root / "supabase/functions/collect-receipt-successor-gateway/index.ts").unlink()
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DEPLOY_CURRENT_BACKEND_SOURCE_CHANGED", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_make_tool_defaults_use_path_and_keep_explicit_overrides(self):
        for name in ("flutter", "dart"):
            self.executable(self.bin / name, f'#!/usr/bin/env bash\nprintf "{name}-from-path\\n"\n')
        extra = self.root / "portable-tools.mk"
        extra.write_text('portable-tools:\n\t@$(FLUTTER) --version\n\t@$(DART) --version\n')
        env = self.env.copy()
        env.pop("FLUTTER", None)
        env.pop("DART", None)
        result = subprocess.run(["make", "-s", "-f", str(ROOT / "Makefile"), "-f", str(extra), "portable-tools"], cwd=self.root, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["flutter-from-path", "dart-from-path"])
        self.executable(self.bin / "custom-dart", '#!/usr/bin/env bash\nprintf "custom-dart\\n"\n')
        result = subprocess.run(["make", "-s", "-f", str(ROOT / "Makefile"), "-f", str(extra), f"DART={self.bin / 'custom-dart'}", "portable-tools"], cwd=self.root, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["flutter-from-path", "custom-dart"])


if __name__ == "__main__":
    unittest.main()
