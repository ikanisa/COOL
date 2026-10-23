#!/usr/bin/env python3
import copy
import importlib.util
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
import tempfile
import struct
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("collect_ci_policy", ROOT / "scripts/qa/collect_ci_policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class CollectCiPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflows = {p.name: policy.read_workflow(p) for p in policy.workflow_paths(ROOT / ".github/workflows")}

    def setUp(self):
        self.workflows = copy.deepcopy(self.__class__.workflows)

    def codes(self):
        return {f["code"] for f in policy.validate_workflows(self.workflows)}

    def checkout(self):
        return self.workflows["ci.yml"]["jobs"]["repo-hygiene"]["steps"][0]

    def test_current_declared_boundary_is_valid(self):
        self.assertEqual(policy.validate_workflows(self.workflows), [])

    def test_missing_and_enabled_persisted_credentials_fail(self):
        for value in [None, True, "false", "${{ inputs.persist }}"]:
            with self.subTest(value=value):
                self.checkout()["with"]["persist-credentials"] = value
                self.assertIn("CI_CHECKOUT_CREDENTIAL_PERSISTENCE_FORBIDDEN", self.codes())

    def test_mutable_action_tag_fails(self):
        self.checkout()["uses"] = "actions/checkout@v4"
        self.assertIn("CI_ACTION_COMMIT_PIN_REQUIRED", self.codes())

    def test_privileged_pull_request_trigger_fails(self):
        self.workflows["ci.yml"].setdefault("true", {})["pull_request_target"] = None
        self.assertIn("CI_PRIVILEGED_PR_TRIGGER_FORBIDDEN", self.codes())

    def test_default_token_write_fails(self):
        self.workflows["ci.yml"]["permissions"]["contents"] = "write"
        self.assertIn("CI_DEFAULT_CONTENTS_READ_REQUIRED", self.codes())

    def test_missing_or_invalid_deadline_fails(self):
        for value in [None, True, 0, 61, "15"]:
            self.workflows["ci.yml"]["jobs"]["repo-hygiene"]["timeout-minutes"] = value
            self.assertIn("CI_JOB_DEADLINE_REQUIRED", self.codes())

    def test_codeql_platform_must_cover_both_events(self):
        events = self.workflows["codeql.yml"].get("true", self.workflows["codeql.yml"].get("on"))
        for event in ["push", "pull_request"]:
            for required in ["deploy/platform-api/**/*.js", "deploy/platform-admin/**/*.js"]:
                original = list(events[event]["paths"])
                events[event]["paths"].remove(required)
                self.assertIn("CI_CODEQL_PLATFORM_TRIGGER_REQUIRED", self.codes())
                events[event]["paths"] = original

    def test_four_retained_legacy_jobs_cannot_be_reactivated(self):
        original = copy.deepcopy(self.workflows)
        for name in policy.LEGACY_JOBS:
            for value in (None, True, '${{ true }}', '${{ inputs.legacy }}', "${{ github.event_name == 'workflow_dispatch' }}"):
                with self.subTest(job=name, condition=value):
                    self.workflows = copy.deepcopy(original)
                    job = self.workflows['ci.yml']['jobs'][name]
                    if value is None:
                        job.pop('if')
                    else:
                        job['if'] = value
                    self.assertIn('CI_LEGACY_AUTOMATIC_EXECUTION_FORBIDDEN', self.codes())

    def test_legacy_execution_cannot_move_to_an_active_job_or_other_workflow(self):
        original = copy.deepcopy(self.workflows)
        for filename in ('ci.yml', 'public-website.yml'):
            for hook in ({'run': 'npm test', 'working-directory': 'deploy/platform-api'},
                         {'run': 'npm ci --ignore-scripts', 'working-directory': 'deploy/admin-api'},
                         {'run': 'make cloudflare-platform-test'},
                         {'run': 'node scripts/qa/recovery17_ci.mjs'},
                         {'run': 'bash scripts/admin_cloudflare_build.sh'}):
                with self.subTest(workflow=filename, hook=hook):
                    self.workflows = copy.deepcopy(original)
                    job = next(iter(self.workflows[filename]['jobs'].values()))
                    job['steps'].append(hook)
                    self.assertIn('CI_LEGACY_AUTOMATIC_EXECUTION_FORBIDDEN', self.codes())

    def test_each_current_consumer_hook_cannot_be_omitted_masked_duplicated_moved_or_redirected(self):
        original = copy.deepcopy(self.workflows)
        for cwd, command in policy.CURRENT_CONSUMERS:
            for mutation in ('omit', 'conditional', 'ignore', 'duplicate', 'move', 'directory', 'active-decoy'):
                with self.subTest(command=command, mutation=mutation):
                    self.workflows = copy.deepcopy(original)
                    jobs = self.workflows['ci.yml']['jobs']
                    steps = jobs['supabase-admin-consumers']['steps']
                    hook = next(x for x in steps if x.get('run', '').strip() == command)
                    if mutation == 'omit': steps.remove(hook)
                    elif mutation == 'conditional': hook['if'] = '${{ false }}'
                    elif mutation == 'ignore': hook['continue-on-error'] = True
                    elif mutation == 'duplicate': steps.append(copy.deepcopy(hook))
                    elif mutation == 'directory': hook['working-directory'] = 'unrelated'
                    elif mutation == 'active-decoy': jobs['repo-hygiene']['steps'].append(copy.deepcopy(hook))
                    else:
                        steps.remove(hook); jobs['repo-hygiene']['steps'].append(hook)
                    self.assertIn('CI_CURRENT_CONSUMER_HOOK_REQUIRED', self.codes())

    def test_current_consumer_job_cannot_be_masked_or_depend_on_another_job(self):
        original = copy.deepcopy(self.workflows)
        for field, value in [('if', '${{ false }}'), ('continue-on-error', True),
                             ('needs', ['supabase-platform']), ('defaults', {'run': {'working-directory': 'deploy/platform-api'}})]:
            with self.subTest(field=field):
                self.workflows = copy.deepcopy(original)
                self.workflows['ci.yml']['jobs']['supabase-admin-consumers'][field] = value
                self.assertIn('CI_CURRENT_CONSUMER_JOB_REQUIRED', self.codes())

    def test_locked_host_install_must_precede_bundled_parent_execution(self):
        steps = self.workflows['ci.yml']['jobs']['supabase-admin-consumers']['steps']
        install = next(x for x in steps if x.get('run') == policy.CURRENT_CONSUMERS[0][1])
        steps.remove(install); steps.append(install)
        self.assertIn('CI_CURRENT_CONSUMER_INSTALL_ORDER_REQUIRED', self.codes())

    def test_node_pin_fails_when_changed(self):
        original = copy.deepcopy(self.workflows)
        for field, value in [('version', '24'), ('if', '${{ false }}'), ('continue-on-error', True)]:
            self.workflows = copy.deepcopy(original)
            steps = self.workflows['ci.yml']['jobs']['supabase-admin-consumers']['steps']
            node = next(x for x in steps if str(x.get('uses', '')).startswith('actions/setup-node@'))
            if field == 'version': node['with']['node-version'] = value
            else: node[field] = value
            self.assertIn('CI_CURRENT_CONSUMER_NODE_PIN_REQUIRED', self.codes())

    def test_manual_history_hooks_are_preserved_without_requiring_automatic_legacy_execution(self):
        source = (ROOT / 'Makefile').read_text()
        self.assertEqual(policy.validate_legacy_makefile_history(source), [])
        for filename, code in [('recovery12_test.mjs', 'CI_PLATFORM_MAKE_RECOVERY12_REQUIRED'),
                               ('recovery13_test.mjs', 'CI_PLATFORM_MAKE_RECOVERY13_REQUIRED'),
                               ('recovery15_test.mjs', 'CI_PLATFORM_MAKE_RECOVERY15_REQUIRED'),
                               ('momo_release_candidate_test.mjs', 'CI_PLATFORM_MAKE_MOMO_CANDIDATE_REQUIRED')]:
            command = '@node --test scripts/tests/' + filename
            with self.subTest(filename=filename):
                changed = source.replace(command, '@true', 1)
                self.assertIn(code, {x['code'] for x in policy.validate_legacy_makefile_history(changed)})

    def test_current_make_policy_does_not_require_historical_backend_command_hooks(self):
        source = (ROOT / 'Makefile').read_text()
        for filename in ('recovery12_test.mjs', 'recovery13_test.mjs', 'recovery15_test.mjs', 'momo_release_candidate_test.mjs'):
            source = source.replace('\t@node --test scripts/tests/' + filename + '\n', '', 1)
        self.assertEqual(policy.validate_platform_makefile(source), [])
        self.assertTrue(policy.validate_legacy_makefile_history(source))

    def test_current_make_hooks_cannot_be_omitted_masked_duplicated_or_redirected(self):
        source = (ROOT / 'Makefile').read_text()
        for command in policy.CURRENT_MAKE_COMMANDS:
            line = '\t@' + command + '\n'
            self.assertEqual(source.count(line), 1)
            for replacement in ('', line + line, line.replace('@', '-@', 1),
                                line.rstrip() + ' || true\n', line.replace('deploy/platform-admin', 'unrelated')):
                if replacement == line: continue
                with self.subTest(command=command, replacement=replacement):
                    self.assertIn('CI_CURRENT_MAKE_CONSUMERS_REQUIRED',
                                  {x['code'] for x in policy.validate_platform_makefile(source.replace(line, replacement, 1))})

    def test_supabase_make_target_must_call_current_consumers_without_legacy_dependency(self):
        source = (ROOT / 'Makefile').read_text()
        for replacement in ('', '\t@$(MAKE) cloudflare-platform-test\n',
                            '\t@$(MAKE) supabase-admin-consumers-test || true\n'):
            changed = source.replace('\t@$(MAKE) supabase-admin-consumers-test\n', replacement, 1)
            self.assertIn('CI_CURRENT_MAKE_QUALIFICATION_REQUIRED', {x['code'] for x in policy.validate_platform_makefile(changed)})

    def test_recovery13_make_hook_cannot_be_conditional_ignored_or_duplicated(self):
        source = (ROOT / "Makefile").read_text()
        command = "\t@node --test scripts/tests/recovery13_test.mjs\n"
        for replacement in [
            "\t-@node --test scripts/tests/recovery13_test.mjs\n",
            "\t@node --test scripts/tests/recovery13_test.mjs || true\n",
            "\t@if false; then node --test scripts/tests/recovery13_test.mjs; fi\n",
        ]:
            with self.subTest(replacement=replacement):
                findings = policy.validate_legacy_makefile_history(source.replace(command, replacement, 1))
                self.assertEqual({item["code"] for item in findings},
                                 {"CI_PLATFORM_MAKE_RECOVERY13_REQUIRED"})
        duplicate = source + "\ncloudflare-platform-test:\n" + command
        self.assertIn("CI_PLATFORM_MAKE_RECOVERY13_REQUIRED",
                      {item["code"] for item in policy.validate_legacy_makefile_history(duplicate)})


    def test_momo_successor_make_checks_cannot_be_decoys_masked_or_duplicated(self):
        source = (ROOT / "Makefile").read_text()
        for filename, code in [("recovery15_test.mjs", "CI_PLATFORM_MAKE_RECOVERY15_REQUIRED"),
                               ("momo_release_candidate_test.mjs", "CI_PLATFORM_MAKE_MOMO_CANDIDATE_REQUIRED")]:
            command = f"\t@node --test scripts/tests/{filename}\n"
            for replacement in ["", command.replace("@node", "-@node"),
                                command.rstrip() + " || true\n",
                                f"\t@if false; then node --test scripts/tests/{filename}; fi\n", command + command]:
                with self.subTest(filename=filename, replacement=replacement):
                    changed = source.replace(command, replacement, 1)
                    if not replacement:
                        changed += "\nunrelated-recovery-check:\n" + command
                    self.assertEqual({f["code"] for f in policy.validate_legacy_makefile_history(changed)}, {code})


    def test_apk_size_uses_validated_public_profile_and_preserves_dev_size_checks(self):
        job = self.workflows['ci.yml']['jobs']['apk-size']
        step = next(s for s in job['steps'] if s.get('name') == 'Build release APK size proxy (dev flavor)')
        public = step['env']
        self.assertEqual(public['COLLECT_BACKEND'], 'supabase')
        self.assertEqual(public['SUPABASE_URL'], 'https://rrlduytparvsjfmegalh.supabase.co')
        self.assertEqual(public['SUPABASE_API_URL'], 'https://platform-admin.collect.ikanisa.com')
        self.assertIn('vars.COLLECT_SUPABASE_PUBLISHABLE_KEY', public['SUPABASE_PUBLISHABLE_KEY'])
        self.assertIn('vars.COLLECT_AUTH_CAPTCHA_SITE_KEY', public['AUTH_CAPTCHA_SITE_KEY'])
        self.assertEqual(public['AUTH_CAPTCHA_ENABLED'], 'true')
        self.assertNotIn('secrets.', str(public))
        self.assertLess(step['run'].index('native_build_config.py'), step['run'].index('flutter build apk'))
        size_check = next(s['run'] for s in job['steps'] if s.get('name') == 'Check per-device APK size budget')
        self.assertIn('"${#APK_PATHS[@]}" -ne 3', size_check)
        self.assertIn('MAX_SIZE_BYTES=$((50 * 1048576))', size_check)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'scripts/qa').mkdir(parents=True)
            (root / 'scripts/qa/native_build_config.py').write_bytes(
                (ROOT / 'scripts/qa/native_build_config.py').read_bytes())
            (root / 'pubspec.yaml').write_text('name: synthetic_ci_fixture\nversion: 1.2.4+23\n')
            (root / 'bin').mkdir()
            (root / 'tmp').mkdir()
            compiler = root / 'bin/flutter'
            compiler.write_text('#!' + sys.executable + '\n' +
                'import json,sys\nfrom pathlib import Path\n'
                'args=sys.argv[1:]\n'
                'config=Path(next(value.split("=",1)[1] for value in args if value.startswith("--dart-define-from-file=")))\n'
                'with Path("observations.jsonl").open("a") as output:\n'
                ' output.write(json.dumps({"args":args,"defines":json.loads(config.read_text()),"mode":config.stat().st_mode&0o777,"temporary_path":str(config)})+"\\n")\n')
            compiler.chmod(0o700)
            env = {'PATH': str(root / 'bin') + ':' + str(Path(sys.executable).parent) + ':/usr/bin:/bin',
                   'RUNNER_TEMP': str(root / 'tmp'), 'PYTHONDONTWRITEBYTECODE': '1',
                   'COLLECT_BACKEND': 'supabase',
                   'SUPABASE_URL': 'https://rrlduytparvsjfmegalh.supabase.co',
                   'SUPABASE_API_URL': 'https://platform-admin.collect.ikanisa.com',
                   'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_synthetic_public_fixture',
                   'AUTH_CAPTCHA_ENABLED': 'true', 'AUTH_CAPTCHA_PROVIDER': 'turnstile',
                   'AUTH_CAPTCHA_SITE_KEY': '1x00000000000000000000AA'}
            result = subprocess.run(['bash', '-e', '-c', step['run']], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            observations = root / 'observations.jsonl'
            [record] = [json.loads(line) for line in observations.read_text().splitlines()]
            self.assertEqual(record['defines']['SUPABASE_PUBLISHABLE_KEY'], env['SUPABASE_PUBLISHABLE_KEY'])
            self.assertEqual(record['defines']['COLLECT_BACKEND'], 'supabase')
            self.assertEqual(record['mode'], 0o600)
            self.assertFalse(Path(record['temporary_path']).exists())
            self.assertIn('--split-per-abi', record['args'])
            self.assertEqual(record['args'][record['args'].index('--flavor') + 1], 'dev')
            self.assertIn('--dart-define=FLAVOR=dev', record['args'])
            for key in ['SUPABASE_PUBLISHABLE_KEY', 'AUTH_CAPTCHA_SITE_KEY']:
                with self.subTest(missing=key):
                    result = subprocess.run(['bash', '-e', '-c', step['run']], cwd=root,
                                            env=env | {key: ''}, capture_output=True, text=True, timeout=20)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(len(observations.read_text().splitlines()), 1)

    def test_shipping_identity_needs_its_actual_platform_backend(self):
        job = self.workflows['ci.yml']['jobs']['admin-platform-candidate']
        job['needs'] = ['repo-hygiene', 'admin-web-build', 'cloudflare-backend']
        self.assertIn('CI_SHIPPING_PLATFORM_DEPENDENCY_REQUIRED', self.codes())

    def test_shipping_requires_both_independent_current_jobs(self):
        original = copy.deepcopy(self.workflows)
        for omitted in ('repo-hygiene', 'admin-web-build', 'supabase-platform', 'supabase-admin-consumers'):
            self.workflows = copy.deepcopy(original)
            self.workflows['ci.yml']['jobs']['admin-platform-candidate']['needs'].remove(omitted)
            self.assertIn('CI_SHIPPING_PLATFORM_DEPENDENCY_REQUIRED', self.codes())

    def test_supabase_cf_web_transport_command_and_filtered_events(self):
        command = ('node --test deploy/platform-admin/test/backend-selection.test.mjs '
                   'deploy/platform-admin/test/supabase-transport.test.mjs')
        for filename, job_name in [('ci.yml', 'supabase-platform'),
                                   ('supabase.yml', 'local-qualification')]:
            with self.subTest(workflow=filename):
                workflow = self.workflows[filename]
                job = workflow['jobs'][job_name]
                matching = [step for step in job['steps'] if step.get('run') == command]
                self.assertEqual(len(matching), 1)
                step = matching[0]
                for boundary in (job, step):
                    self.assertNotIn('if', boundary)
                    self.assertIs(boundary.get('continue-on-error', False), False)
                default = job.get('defaults', {}).get('run', {}).get('working-directory', '.')
                self.assertIn(step.get('working-directory', default),
                              ('.', '${{ github.workspace }}'))
                events = workflow.get('on', workflow.get('true', {}))
                for event in ('push', 'pull_request'):
                    declaration = events.get(event)
                    if isinstance(declaration, dict) and 'paths' in declaration:
                        self.assertIn('deploy/platform-admin/**', declaration['paths'])

    def test_supabase_checks_cannot_skip_fixture_or_drift_from_declared_workflow(self):
        original = copy.deepcopy(self.workflows)
        for mutation in ('omit', 'skip-job', 'ignore-job', 'skip-check', 'ignore-check', 'wrong-db', 'workflow-drift'):
            with self.subTest(mutation=mutation):
                self.workflows = copy.deepcopy(original)
                job = self.workflows['ci.yml']['jobs']['supabase-platform']
                other = self.workflows['supabase.yml']['jobs']['local-qualification']
                if mutation == 'workflow-drift':
                    other['timeout-minutes'] = 24
                else:
                    for target in (job, other):
                        if mutation == 'omit':
                            target['steps'] = [step for step in target['steps'] if step.get('run') != '"$COLLECT_DENO" task test']
                        elif mutation == 'skip-job':
                            target['if'] = '${{ false }}'
                        elif mutation == 'ignore-job':
                            target['continue-on-error'] = True
                        elif mutation in ('skip-check', 'ignore-check'):
                            step = next(step for step in target['steps'] if step.get('run') == '"$COLLECT_DENO" task test')
                            step['if' if mutation == 'skip-check' else 'continue-on-error'] = '${{ false }}' if mutation == 'skip-check' else True
                        else:
                            target['env']['COLLECT_TEST_DATABASE_URL'] = 'postgres://hosted.invalid/production'
                self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_supabase_candidate_cannot_fall_back_to_another_backend(self):
        original = copy.deepcopy(self.workflows)
        for boundary in ('build', 'receipt', 'consumer'):
            with self.subTest(boundary=boundary):
                self.workflows = copy.deepcopy(original)
                jobs = self.workflows['ci.yml']['jobs']
                if boundary == 'consumer':
                    jobs['admin-platform-candidate']['env']['COLLECT_BACKEND'] = 'cloudflare'
                else:
                    key = 'bash scripts/admin_pwa_release_build.sh' if boundary == 'build' else 'PY_PLATFORM_IDENTITY'
                    step = next(s for s in jobs['admin-web-build']['steps'] if key in s.get('run', ''))
                    step['env']['COLLECT_BACKEND'] = "${{ vars.COLLECT_BACKEND || 'cloudflare' }}"
                self.assertIn('CI_SUPABASE_CANDIDATE_SELECTION_REQUIRED', self.codes())

    def test_shipping_identity_cannot_download_the_legacy_preview_artifact(self):
        job = self.workflows['ci.yml']['jobs']['admin-platform-candidate']
        step = next(s for s in job['steps'] if str(s.get('uses', '')).startswith('actions/download-artifact@'))
        step['with']['name'] = 'admin-cloudflare-candidate'
        self.assertIn('CI_SHIPPING_PLATFORM_ARTIFACT_REQUIRED', self.codes())

    def test_legacy_preview_compilation_cannot_gate_the_shipping_build(self):
        job = self.workflows['ci.yml']['jobs']['admin-web-build']
        job['steps'].append({'run': 'bash scripts/admin_cloudflare_build.sh'})
        self.assertIn('CI_SHIPPING_PLATFORM_BUILD_REQUIRED', self.codes())

    def test_safe_parser_rejects_aliases_and_malformed_yaml_without_echo(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "workflow.yml"
            for contents in ["x: &s secret\ny: *s\n", "SECRET_CREDENTIAL: [\n"]:
                path.write_text(contents)
                with self.assertRaisesRegex(policy.PolicyInputError, "^CI_POLICY_YAML_INVALID$"):
                    policy.read_workflow(path)

    def test_missing_parser_and_symlink_fail_closed(self):
        with patch.object(policy.shutil, "which", return_value=None):
            with self.assertRaisesRegex(policy.PolicyInputError, "CI_POLICY_RUBY_REQUIRED"):
                policy.read_workflow(ROOT / ".github/workflows/ci.yml")
        with tempfile.TemporaryDirectory() as folder:
            link = Path(folder) / "workflow.yml"
            link.symlink_to(ROOT / ".github/workflows/ci.yml")
            with self.assertRaisesRegex(policy.PolicyInputError, "CI_POLICY_WORKFLOW_INPUT_INVALID"):
                policy.read_workflow(link)

    def test_verified_filesystem_metadata_is_excluded_but_yaml_stays_active(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "current.yaml").write_text("name: current\n")
            (root / "ci.yml").write_text("name: current\n")
            header = struct.pack(">II16sH", 0x00051607, 0x00020000, b"\0" * 16, 1)
            (root / "._ci.yml").write_bytes(header + struct.pack(">III", 9, 38, 4) + b"META")
            self.assertEqual([p.name for p in policy.workflow_paths(root)], ["ci.yml", "current.yaml"])
            (root / "._ci.yml").write_text("name: executable text\n")
            self.assertIn("._ci.yml", [p.name for p in policy.workflow_paths(root)])

    def test_malformed_and_symlinked_metadata_does_not_bypass_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "ci.yml").write_text("name: current\n")
            (root / "._ci.yml").write_bytes(b"broken metadata")
            self.assertIn("._ci.yml", [p.name for p in policy.workflow_paths(root)])
            (root / "._ci.yml").unlink()
            (root / "._ci.yml").symlink_to(root / "ci.yml")
            self.assertIn("._ci.yml", [p.name for p in policy.workflow_paths(root)])
            with self.assertRaises(policy.PolicyInputError):
                policy.read_workflow(root / "._ci.yml")


    def test_shipping_pwa_identity_binds_real_clean_commit_and_rejects_invalid_inputs(self):
        steps = self.workflows["ci.yml"]["jobs"]["admin-web-build"]["steps"]
        identity = next(s for s in steps if s.get("name") == "Bind shipping PWA artifact to the clean workflow commit")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            # Tiny local artifact files exercise the actual receipt gate. They
            # are not Flutter, hosted, browser or release acceptance evidence.
            inputs = [
                'scripts/admin_pwa_release_build.sh', 'scripts/supabase/admin_build_config.py', 'scripts/admin_pwa_manifest_gate.sh',
                'scripts/admin_pwa_hosting_gate.sh', 'scripts/admin_cloudflare_assets.py',
                'scripts/templates/admin_pwa_service_worker.js', 'deploy/platform-admin/src/index.js', 'deploy/platform-admin/src/supabase-transport.js',
                'deploy/admin.wrangler.jsonc', 'deploy/platform-admin/wrangler.jsonc',
                '.github/workflows/ci.yml', '.fvmrc', 'pubspec.yaml', 'pubspec.lock',
                'scripts/admin_platform_candidate.py',
            ]
            for name in inputs:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('isolated receipt gate source fixture\n')
            # The real producer delegates source selection to the consumer.
            (root / 'scripts/admin_platform_candidate.py').write_bytes(
                (ROOT / 'scripts/admin_platform_candidate.py').read_bytes())
            (root / '.gitignore').write_text('build/\n')
            for args in [['init', '--quiet'], ['add', '.'],
                         ['-c', 'user.name=Receipt fixture', '-c', 'user.email=fixture@example.invalid',
                          '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'isolated receipt gate fixture']]:
                subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True, text=True)
            commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
            build = root / 'build/web'
            build.mkdir(parents=True)
            for name in ['main.dart.js', 'index.html', 'flutter_bootstrap.js', 'manifest.json', '_headers', '.well-known/assetlinks.json', '.well-known/apple-app-site-association']:
                output = build / name
                output.parent.mkdir(parents=True,exist_ok=True)
                output.write_text('isolated output role: ' + name)
            (build / 'custom-sw.js').write_text(
                'const CACHE_NAME = "collect-admin-fixture";\n'
                'const CACHE_URLS = ["./"];\nconst CACHE_HASHES = {"./":"fixture-hash"};\n')
            version = {'source_commit': commit, 'source_dirty': False,
                       'backend': 'cloudflare', 'authentication': 'email_otp_cookie_with_totp',
                       'minimum_core_schema_migration': '0017_admin_email_otp.sql',
                       'financial_model': 'canonical_evidence_ledger', 'financial_contract_version': 2}
            version_path = build / 'version.json'
            def run(changes=None, sha=commit):
                version_path.write_text(json.dumps({**version, **(changes or {})}))
                return subprocess.run(['bash', '-e', '-c', identity['run']], cwd=root,
                                      env={**os.environ, 'GITHUB_SHA': sha, 'COLLECT_BACKEND':'cloudflare'}, capture_output=True, text=True)
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            receipt_path = root / 'build/admin-platform-pwa-artifact.json'
            receipt = json.loads(receipt_path.read_text())
            self.assertEqual(receipt['source_commit'], commit)
            self.assertIs(receipt['source_dirty'], False)
            self.assertIs(receipt['hosted_deployment_verified'], False)
            self.assertEqual(receipt['main_dart_js_sha256'], hashlib.sha256((build / 'main.dart.js').read_bytes()).hexdigest())
            self.assertEqual(receipt['worker_sha256'], hashlib.sha256((build / 'custom-sw.js').read_bytes()).hexdigest())
            self.assertEqual(set(receipt['input_sha256']), set(inputs))
            for changes, sha in [({'source_dirty': True}, commit), ({'source_commit': '0' * 40}, commit),
                                 ({}, '0' * 40), ({'backend': 'unknown'}, commit),
                                 ({'authentication': 'email'}, commit), ({'financial_model': 'legacy_core'}, commit),
                                 ({'financial_contract_version': 1}, commit)]:
                with self.subTest(changes=changes, sha=sha):
                    receipt_path.unlink(missing_ok=True)
                    self.assertNotEqual(run(changes, sha).returncode, 0)
                    self.assertFalse(receipt_path.exists())
            (build / 'main.dart.js').unlink()
            receipt_path.unlink(missing_ok=True)
            self.assertNotEqual(run().returncode, 0)
            self.assertFalse(receipt_path.exists())
            (build / 'main.dart.js').write_text('restored isolated output')
            (root / 'pubspec.yaml').write_text('changed tracked fixture source\n')
            self.assertNotEqual(run().returncode, 0)
            self.assertFalse(receipt_path.exists())

    def test_local_pass_cannot_attest_hosted_security_or_mutation(self):
        report = policy.inspect(ROOT)
        self.assertEqual(report["status"], "pass")
        self.assertIs(report["hosted_enforcement_verified"], False)
        self.assertIs(report["security_scan_execution_verified"], False)
        self.assertIs(report["remote_settings_changed"], False)


if __name__ == "__main__":
    unittest.main()
