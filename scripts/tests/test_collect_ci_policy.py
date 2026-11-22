#!/usr/bin/env python3
import copy
import importlib.util
import json
import os
import shutil
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

    def test_retired_browser_admin_sources_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("admin-web/src/app/App.tsx", "lib/main.dart", "lib/admin/panel.dart",
                         "lib/main_admin.dart", "test/admin/old-fixture.json"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            found = {item["job"] for item in policy.retired_admin_sources(root)}
            self.assertEqual(found, {"lib/admin/panel.dart", "lib/main_admin.dart", "test/admin/old-fixture.json"})

    def checkout(self):
        return self.workflows["ci.yml"]["jobs"]["repo-hygiene"]["steps"][0]

    def test_current_declared_boundary_is_valid(self):
        self.assertEqual(policy.validate_workflows(self.workflows), [])

    def test_public_website_static_checks_watch_content_and_capture_inputs(self):
        workflow = self.workflows['public-website.yml']
        events = workflow.get('on', workflow.get('true', {}))
        required_inputs = {
            'content/legal/**', 'content/product/**', 'scripts/product_capabilities.rb',
            'scripts/generate_product_capability_content.rb',
            'scripts/public_site/**', 'scripts/qa/public_website/**', 'scripts/qa/browser/**',
            'scripts/qa/asset_manifest_integrity.rb', 'scripts/qa/bounded_git_metadata.rb',
            'web/**', 'third_party/firebase_messaging/**', '.fvmrc', '.metadata',
            'analysis_options.yaml', 'docs/PRODUCT.md', 'scripts/qa/public_*',
            'docs/release/public-website-current-content-contract.json',
            'docs/release/public-content-provenance/**',
            'docs/implementation/**/capture-report.json',
            'docs/implementation/**/visual-review.json',
            'supabase/functions/_shared/domain/momo_pipeline.js',
        }
        for event in ('push', 'pull_request'):
            with self.subTest(event=event):
                self.assertEqual(required_inputs.difference(events[event]['paths']), set())

        live_build = [step['run'] for step in workflow['jobs']['production-live-public-website']['steps'] if 'run' in step]
        self.assertLess(
            live_build.index('bash scripts/public_landing_prepare_build.sh'),
            live_build.index('bash scripts/public_website_ci_gate.sh live'),
        )

    def test_fallback_secret_scan_requires_inventory_and_redacts_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory).resolve()
            scripts = fixture / 'scripts' / 'release'
            tools = fixture / 'bin'
            scripts.mkdir(parents=True)
            tools.mkdir()
            scanner = scripts / 'release_secret_scan.sh'
            shutil.copyfile(ROOT / 'scripts/release/release_secret_scan.sh', scanner)
            for command in ('dirname', 'git', 'mktemp', 'unlink', 'perl'):
                (tools / command).symlink_to(shutil.which(command))
            runner = [shutil.which('bash'), str(scanner)]
            env = {'PATH': str(tools), 'GIT_CEILING_DIRECTORIES': str(fixture.parent)}
            result = subprocess.run(
                runner, env=env, capture_output=True, text=True, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Could not inventory repository files.', result.stdout)
            self.assertNotIn('fallback secret scan passed', result.stdout)

            subprocess.run([shutil.which('git'), '-C', str(fixture), 'init', '--quiet'], check=True)
            source = fixture / 'working file.txt'
            source.write_text('public fixture\n', encoding='utf-8')
            clear = subprocess.run(runner, env=env, capture_output=True, text=True, check=False)
            self.assertEqual(clear.returncode, 0, clear.stderr)

            synthetic = 'sk-' + 'proj-' + 'x' * 30
            source.write_text(synthetic, encoding='utf-8')
            detected = subprocess.run(runner, env=env, capture_output=True, text=True, check=False)
            self.assertNotEqual(detected.returncode, 0)
            self.assertIn('OpenAI API key in working file.txt', detected.stderr)
            self.assertNotIn(synthetic, detected.stdout + detected.stderr)

    def test_managed_cloud_is_the_only_current_qualification_profile(self):
        workflow = self.workflows['supabase.yml']
        events = workflow.get('on', workflow.get('true', {}))
        profile = events['workflow_dispatch']['inputs']['qualification_profile']
        self.assertEqual(profile['default'], 'current-managed-cloud')
        profile['default'] = 'current-self-hosted'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_historical_current16_keeps_owned_cluster_and_safe_receipts_at_exact_source(self):
        job = self.workflows['supabase.yml']['jobs']['current16-integration-native']
        self.assertEqual(job['needs'], 'select-profile')
        self.assertEqual(job['if'], "needs.select-profile.outputs.profile == 'historical-current16'")
        self.assertIs(job.get('continue-on-error', False), False)
        env = job['env']
        self.assertEqual(env['COLLECT_CI_SYNTHETIC'], 'true')
        self.assertEqual(env['COLLECT_CURRENT16_ADMIN_DATABASE_URL'],
                         'postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/postgres')
        self.assertEqual(env['COLLECT_DENO'],
                         '${{ github.workspace }}/scripts/supabase/node_modules/@deno/linux-x64-glibc/deno')
        self.assertEqual(env['COLLECT_PG_MODULE'], '${{ github.workspace }}/scripts/supabase/node_modules/pg')
        self.assertEqual(env['DENO_TLS_CA_STORE'], 'system')
        self.assertNotIn('COLLECT_NATIVE_PROFILE', env)
        self.assertNotIn('COLLECT_CURRENT16_OUTPUT_DIR', env)
        steps = job['steps']
        for step in [job, *steps]:
            self.assertNotIn('COLLECT_CURRENT16_OWNER_DATABASE_URL', step.get('env', {}))
        start = next(s for s in steps if s.get('run') == 'sh scripts/supabase/testing/ci-native-postgres.sh start')
        warm = next(s for s in steps if 'current16-runtime.ts' in s.get('run', ''))
        native = next(s for s in steps if s.get('run', '').endswith('node scripts/supabase/testing/current16-integration.mjs'))
        self.assertEqual(warm['run'], '"$COLLECT_DENO" check --frozen --node-modules-dir=none --config=supabase/functions/deno.json --lock=supabase/functions/deno.lock scripts/supabase/testing/current16-runtime.ts')
        self.assertEqual(native['run'], 'timeout --signal=TERM --kill-after=5s 300s node scripts/supabase/testing/current16-integration.mjs')
        self.assertEqual(warm['env']['DENO_DIR'], native['env']['DENO_DIR'])
        output = '${{ runner.temp }}/collect-current16-integration'
        self.assertEqual(native['env']['COLLECT_CURRENT16_OUTPUT_DIR'], output)
        self.assertLess(steps.index(warm), steps.index(start))
        self.assertLess(steps.index(start), steps.index(native))
        for step in [start, warm, native]:
            self.assertNotIn('if', step)
            self.assertIs(step.get('continue-on-error', False), False)
        stop = next(s for s in steps if 'ci-native-postgres.sh stop' in s.get('run', ''))
        self.assertEqual(stop['if'], 'always()')
        self.assertLess(steps.index(native), steps.index(stop))
        upload = next(s for s in steps if s.get('uses', '').startswith('actions/upload-artifact@'))
        self.assertEqual(upload['if'], 'always()')
        self.assertEqual(upload['with']['if-no-files-found'], 'error')
        names = {'INPUTS.json', 'CREATE-INTENT.json', 'PREPARATION.json', 'CHILD-STDOUT.log',
                 'CHILD-STDERR.log', 'CHILD-METADATA.json', 'CASES.json', 'OBSERVATIONS.json',
                 'WORK-CLOSURES.json', 'NATIVE-RESULT.json', 'RESULT.json'}
        expected = {output + '/' + name for name in names} | {'!' + output + '/RUN-SPEC.private.json'}
        self.assertEqual(set(upload['with']['path'].splitlines()), expected)
        suite = 'scripts/supabase/testing/current16-integration.test.mjs'
        for workflow, name in [('supabase.yml', 'local-qualification'), ('supabase.yml', 'current-source-contracts')]:
            matches = [s for s in self.workflows[workflow]['jobs'][name]['steps'] if suite in s.get('run', '')]
            self.assertEqual(len(matches), 1)
            self.assertNotIn('if', matches[0])
            self.assertIs(matches[0].get('continue-on-error', False), False)
            self.assertTrue(matches[0]['run'].startswith('node --test '))
        makefile = policy.read_make_sources(ROOT)
        self.assertIn('\n\t@node --test ' + suite + '\n', makefile)
        self.assertIn('\nsupabase-current16-integration-native:\n\t@node scripts/supabase/testing/current16-integration.mjs\n', makefile)

    def test_original_job_env_runner_temp_placement_is_rejected(self):
        job = self.workflows['supabase.yml']['jobs']['stopped-admission-lifecycle-native']
        step = next(step for step in job['steps'] if '--with-member-history' in step.get('run', ''))
        name = 'COLLECT_MEMBER_HISTORY_OUTPUT_DIR'
        value = step['env'].pop(name)
        self.assertEqual(value, '${{ runner.temp }}/collect-current14-member-history')
        if not step['env']:
            step.pop('env')
        job['env'][name] = value
        self.assertIn({'workflow': 'supabase.yml', 'job': 'stopped-admission-lifecycle-native',
                       'code': 'CI_JOB_ENV_CONTEXT_UNAVAILABLE'},
                      policy.validate_workflows(self.workflows))

    def test_job_env_accepts_all_early_contexts(self):
        job = self.workflows['ci.yml']['jobs']['repo-hygiene']
        expressions = ['github.workspace', 'needs.prepare.result', 'strategy.job-index',
                       'matrix.flavor', 'vars.runner', 'secrets.job', 'inputs.manual']
        job.setdefault('env', {}).update({f'CONTEXT_{i}': '${{ ' + value + ' }}'
                                         for i, value in enumerate(expressions)})
        self.assertNotIn('CI_JOB_ENV_CONTEXT_UNAVAILABLE', self.codes())

    def test_step_env_keeps_runner_and_other_late_contexts_available(self):
        self.checkout()['env'] = {'TEMP': '${{ runner.temp }}', 'VALUE': '${{ env.VALUE }}',
                                  'STATUS': '${{ job.status }}',
                                  'OUTPUT': '${{ steps.compile.outputs.path }}'}
        self.assertNotIn('CI_JOB_ENV_CONTEXT_UNAVAILABLE', self.codes())

    def test_job_env_refuses_late_roots_in_actual_member_forms(self):
        original = copy.deepcopy(self.workflows)
        expressions = ['runner.temp', "runner['temp']", "RuNnEr [ 'temp' ]", '(runner).temp',
                       'env.VALUE', "job['status']", "steps['compile'].outputs['path']",
                       'jobs.release.outputs.path']
        for expression in expressions:
            with self.subTest(expression=expression):
                self.workflows = copy.deepcopy(original)
                self.workflows['ci.yml']['jobs']['repo-hygiene'].setdefault('env', {})['PROBE'] = '${{ ' + expression + ' }}'
                self.assertIn('CI_JOB_ENV_CONTEXT_UNAVAILABLE', self.codes())

    def test_job_env_refuses_nested_and_multiple_expression_late_roots(self):
        original = copy.deepcopy(self.workflows)
        values = ["${{ format('{0}', runner.temp) }}", '${{ vars[runner.temp] }}',
                  "${{ fromJSON(env.CONFIG).value }}",
                  "${{ 'literal }}' }}-${{ steps.compile.outputs.path }}",
                  "${{ format('literal }} {0}', job.status) }}",
                  "${{ format(\n  '{0}',\n  runner['temp']\n) }}"]
        for value in values:
            with self.subTest(value=value):
                self.workflows = copy.deepcopy(original)
                self.workflows['ci.yml']['jobs']['repo-hygiene'].setdefault('env', {})['PROBE'] = value
                self.assertIn('CI_JOB_ENV_CONTEXT_UNAVAILABLE', self.codes())

    def test_job_env_ignores_quoted_literals_and_context_named_properties(self):
        job = self.workflows['ci.yml']['jobs']['repo-hygiene']
        values = ['runner.temp env.VALUE job.status steps.compile',
                  "${{ 'runner.temp env.VALUE job.status steps.compile' }}",
                  "${{ 'It''s runner.temp }} and env.VALUE' }}",
                  '${{ vars.runner }}', "${{ vars['env'] }}", '${{ vars . steps }}',
                  "${{ format('{0}', vars.job) }}",
                  '${{ fromJSON(vars.configuration).runner }}',
                  "${{ github.event.inputs['steps'] }}"]
        job.setdefault('env', {}).update({f'VALUE_{i}': value for i, value in enumerate(values)})
        job['env']['runner'] = 'literal key and value'
        self.assertNotIn('CI_JOB_ENV_CONTEXT_UNAVAILABLE', self.codes())

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
            for required in ["deploy/platform-api/**/*.js", "deploy/platform-admin/**/*.js",
                             "deploy/platform-admin/**/*.mjs"]:
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

    def test_toolchain_inventory_rejects_drift_in_the_actual_source_runners(self):
        checks = (
            ('supabase.yml', 'current-source-contracts', 'actions/setup-node@', 'node-version', '24'),
            ('ci.yml', 'analyze', 'subosito/flutter-action@', 'flutter-version', '3.44.4'),
            ('ci.yml', 'apk-size', 'actions/setup-java@', 'java-version', '21'),
        )
        for path, job, action, setting, version in checks:
            with self.subTest(job=job):
                scenario = copy.deepcopy(self.workflows)
                steps = scenario[path]['jobs'][job]['steps']
                consumer = next(step for step in steps if str(step.get('uses', '')).startswith(action))
                consumer['with'][setting] = version
                inventory, findings = policy.inventory_toolchains(ROOT, scenario)
                self.assertEqual(len(findings), 1)
                self.assertEqual(findings[0]['code'], 'CI_TOOLCHAIN_PIN_DRIFT')
                self.assertEqual(findings[0]['workflow'], path)
                self.assertTrue(findings[0]['job'].startswith(job + '/'))
                self.assertIn('burimunsi', inventory['android'])

    def test_make_policy_reads_only_required_included_fragments(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            makefile = root / "Makefile"
            path = "scripts/make/supabase.mk"
            fragment = root / path
            fragment.parent.mkdir(parents=True)
            fragment.write_text("supabase-test:\n\t@true\n")
            makefile.write_text(f"include {path}\n")
            self.assertIn("supabase-test:\n\t@true\n", policy.read_make_sources(root))
            for source in (f"-include {path}\n", f"include {path}\ninclude {path}\n",
                           "include scripts/make/missing.mk\n"):
                with self.subTest(source=source):
                    makefile.write_text(source)
                    with self.assertRaisesRegex(policy.PolicyInputError, "CI_POLICY_MAKEFILE_INPUT_INVALID"):
                        policy.read_make_sources(root)

    def test_manual_history_hooks_are_preserved_without_requiring_automatic_legacy_execution(self):
        source = policy.read_make_sources(ROOT)
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
        source = policy.read_make_sources(ROOT)
        for filename in ('recovery12_test.mjs', 'recovery13_test.mjs', 'recovery15_test.mjs', 'momo_release_candidate_test.mjs'):
            source = source.replace('\t@node --test scripts/tests/' + filename + '\n', '', 1)
        self.assertEqual(policy.validate_platform_makefile(source), [])
        self.assertTrue(policy.validate_legacy_makefile_history(source))

    def test_current_make_hooks_cannot_be_omitted_masked_duplicated_or_redirected(self):
        source = policy.read_make_sources(ROOT)
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
        source = policy.read_make_sources(ROOT)
        for replacement in ('', '\t@$(MAKE) cloudflare-platform-test\n',
                            '\t@$(MAKE) supabase-admin-consumers-test || true\n'):
            changed = source.replace('\t@$(MAKE) supabase-admin-consumers-test\n', replacement, 1)
            self.assertIn('CI_CURRENT_MAKE_QUALIFICATION_REQUIRED', {x['code'] for x in policy.validate_platform_makefile(changed)})

    def test_current_make_cannot_substitute_source_checks_for_native_evidence(self):
        source = policy.read_make_sources(ROOT)
        for command in ('$(MAKE) supabase-source-test', '$(MAKE) supabase-current-native', '$(MAKE) supabase-current-transfer-test'):
            line = '\t@' + command + '\n'
            for replacement in ('', line + line, line.rstrip() + ' || true\n', '\t@true\n'):
                with self.subTest(command=command, replacement=replacement):
                    changed = source.replace('supabase-test:\n', 'supabase-test:\n', 1)
                    before, rest = changed.split('supabase-test:\n', 1)
                    changed = before + 'supabase-test:\n' + rest.replace(line, replacement, 1)
                    self.assertIn('CI_CURRENT_MAKE_QUALIFICATION_REQUIRED',
                                  {x['code'] for x in policy.validate_platform_makefile(changed)})
        command = '\t@' + policy.CURRENT_NATIVE_MAKE_COMMAND + '\n'
        for replacement in ('', command + command, command.replace('@node', '-@node'),
                            command.rstrip() + ' || true\n', '\t@node scripts/supabase/testing/current16-integration.mjs\n'):
            with self.subTest(native=replacement):
                self.assertIn('CI_CURRENT_MAKE_NATIVE_REQUIRED',
                              {x['code'] for x in policy.validate_platform_makefile(source.replace(command, replacement, 1))})
        for command in ('python3 supabase/schema-src/generate_baseline.py --check',
                        'node scripts/supabase/run_edge_node_tests.mjs',
                        policy.CURRENT_CLOUD_IDENTITY_COMMAND,
                        policy.WRITER_JOURNAL_SOURCE_COMMAND,
                        'cd deploy/managed-sms && python3 test/verify_source_tests_test.py && python3 test/verify_source_tests.py',
                        policy.CURRENT_COMMISSIONING_DENO_MAKE_COMMAND,
                        'cd supabase/functions && "$${COLLECT_DENO:-deno}" task check'):
            before, rest = source.split('supabase-source-test:\n', 1)
            changed = before + 'supabase-source-test:\n' + rest.replace('\t@' + command + '\n', '\t@true\n', 1)
            self.assertIn('CI_CURRENT_MAKE_SOURCE_REQUIRED',
                          {x['code'] for x in policy.validate_platform_makefile(changed)})

    def test_current_transfer_make_requires_owned_fixture_and_no_skips(self):
        source = policy.read_make_sources(ROOT)
        before, rest = source.split('supabase-current-transfer-test:\n', 1)
        for command in ('test "$$(id -u)" -ne 0',
                        'test -n "$${COLLECT_SYNTHETIC_PG_BIN:-}"',
                        'test "$$(cd "$$COLLECT_SYNTHETIC_PG_BIN" && pwd -P)" = "$$COLLECT_SYNTHETIC_PG_BIN"',
                        'command -v openssl >/dev/null',
                        policy.CURRENT_TRANSFER_MAKE_COMMAND):
            for replacement in ('', '\t@true\n', '\t@' + command + ' || true\n'):
                with self.subTest(command=command[:60], replacement=replacement[:60]):
                    changed = before + 'supabase-current-transfer-test:\n' + rest.replace('\t@' + command + '\n', replacement, 1)
                    self.assertIn('CI_CURRENT_MAKE_NATIVE_REQUIRED',
                                  {x['code'] for x in policy.validate_platform_makefile(changed)})

    def test_current_transfer_requires_every_fixture_and_named_result(self):
        source = policy.read_make_sources(ROOT)
        original = copy.deepcopy(self.workflows)
        required = (
            'scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs',
            'scripts/supabase/current-pg-transfer/test-support/lifecycle.test.mjs',
            'scripts/supabase/current-pg-transfer/object-transfer/transfer.test.mjs',
            'scripts/supabase/current-pg-transfer/object-transfer/scope-rebind.test.mjs',
            'scripts/supabase/current-pg-transfer/object-transfer/supabase-adapter.test.mjs',
            'scripts/supabase/current-pg-transfer/business-import/import.test.mjs',
            'scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs',
            'scripts/supabase/retention-convergence/user-id-forward.test.mjs',
            'scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs',
            'scripts/supabase/retention-convergence/history-plan.test.mjs',
            'supabase/functions/_shared/tests/burimunsi/native-sms-ledger.test.mjs',
            'supabase/managed-deployment-identity/bind-managed-pg17.test.mjs',
            'scripts/supabase/managed-cloud-migrations/event-trigger-preimage.test.mjs',
            'scripts/supabase/managed-cloud-migrations/migration-postconditions.test.mjs',
            'scripts/supabase/device-commissioning/synthetic-transport.test.mjs',
            'supabase/managed-cloud-stopped-recovery/evidence.test.mjs',
            'isolated PostgreSQL reconciliation',
            'managed reconciliation admits only the pinned target, TLS root and verified peer',
            'connected clients with startup options are refused',
            'owner-approved identity mapping holds both existing principals',
            'encrypted quarantine on disposable PostgreSQL 17',
            'SIGTERM stops a confirmed server before removing its fixture',
            'provider database CA is a valid self-signed root with the pinned DER fingerprint',
            'canonical input, exact project and clean environment are required before connecting',
            'CLI reports or reconciles commit with closed-stdout',
            'commissioning receipt transaction fixture',
            'exact immutable ciphertext is copied once with encrypted durable intent and receipt',
            'synthetic owner rebind reproduces Storage fingerprints while preserving ciphertext identity',
            'actual adapter reads, creates once and verifies synthetic protected bytes',
            'HTTPS client rejects a self-signed loopback server',
            'mutating an approved plan cannot redirect import or lost-ack reconciliation',
            'count-only financial graph inventory on owned PostgreSQL 17',
            'financial consistency is aggregate-only and read-only on owned PostgreSQL 17',
            'selected native source prerequisites are aggregate-only on owned PostgreSQL 17',
            'synthetic posted financial graphs transfer atomically with cloud-primary mapping',
            'synthetic accepted native SMS history and posted financial graph',
            'forward-only retention user ID correction on owned PostgreSQL 17',
            'synthetic full chain refuses divergent originals and runs pinned candidates without writing history',
            'history candidate keeps divergent originals unrecorded and uses distinct ordered versions',
            'all pinned non-WIP predecessors execute in order while both MFA sources remain absent',
            'deferred proposal keeps every non-WIP source action without inventing history',
            'a coherently mapped replay with an existing complete financial link performs no second write',
            'managed candidate on native PostgreSQL 17 without a postgres superuser',
            'a correctly serialized v2-style digest cannot authorize the v3 executor',
            'diagnostics rechecks after history insertion',
            'notification rechecks after history insertion',
            'signed commissioning transport with durable synthetic PostgreSQL receipts',
            'managed stopped-work evidence remains non-authorizing with synthetic PG snapshots',
        )
        for required_input in required:
            with self.subTest(required_input=required_input):
                self.assertIn(required_input, policy.CURRENT_TRANSFER_MAKE_COMMAND)
                self.assertIn(required_input, policy.CURRENT_TRANSFER_NATIVE_COMMAND)
                changed = source.replace(required_input, 'removed-required-transfer-input', 1)
                self.assertIn('CI_CURRENT_MAKE_NATIVE_REQUIRED',
                              {x['code'] for x in policy.validate_platform_makefile(changed)})
                offset = -1
                for occurrence in range(policy.CURRENT_TRANSFER_NATIVE_COMMAND.count(required_input)):
                    with self.subTest(occurrence=occurrence):
                        self.workflows = copy.deepcopy(original)
                        job = self.workflows['supabase.yml']['jobs'][policy.CURRENT_NATIVE_JOB]
                        step = next(step for step in job['steps'] if step.get('run', '').strip() == policy.CURRENT_TRANSFER_NATIVE_COMMAND)
                        offset = step['run'].find(required_input, offset + 1)
                        self.assertNotEqual(offset, -1)
                        step['run'] = step['run'][:offset] + 'removed-required-transfer-input' + step['run'][offset + len(required_input):]
                        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = original

    def test_transfer_ci_requires_openssl_install_before_suite(self):
        original = copy.deepcopy(self.workflows)
        for mutation in ('omit', 'skip', 'ignore', 'remove-package', 'remove-check', 'after-suite'):
            self.workflows = copy.deepcopy(original)
            job = self.workflows['supabase.yml']['jobs'][policy.CURRENT_NATIVE_JOB]
            steps = job['steps']
            step = next(step for step in steps if step.get('run', '').strip() == policy.CURRENT_NATIVE_CONTAINER_PREREQ)
            if mutation == 'omit': steps.remove(step)
            elif mutation == 'skip': step['if'] = '${{ false }}'
            elif mutation == 'ignore': step['continue-on-error'] = True
            elif mutation == 'remove-package': step['run'] = step['run'].replace('xz-utils openssl', 'xz-utils')
            elif mutation == 'remove-check': step['run'] = step['run'].replace('command -v openssl >/dev/null', 'true')
            else:
                steps.remove(step)
                transfer = next(item for item in steps if item.get('run', '').strip() == policy.CURRENT_TRANSFER_NATIVE_COMMAND)
                steps.insert(steps.index(transfer) + 1, step)
            with self.subTest(mutation=mutation):
                self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = original

    def test_commissioning_deno_gate_pins_runtime_lock_and_named_pass(self):
        original = copy.deepcopy(self.workflows)
        source = policy.read_make_sources(ROOT)
        for required in ('--lock=supabase/functions/deno.lock', '--frozen',
                         'scripts/supabase/device-commissioning/edge-smoke.test.ts',
                         'synthetic Edge request signs and verifies commissioning receipt and acknowledgement',
                         "'^deno 2[.]9[.]6 '"):
            with self.subTest(required=required):
                self.assertIn(required, policy.CURRENT_COMMISSIONING_DENO_MAKE_COMMAND)
                self.assertIn(required, policy.CURRENT_COMMISSIONING_DENO_COMMAND)
                changed = source.replace(required, 'removed-required-deno-input', 1)
                self.assertIn('CI_CURRENT_MAKE_SOURCE_REQUIRED',
                              {x['code'] for x in policy.validate_platform_makefile(changed)})
                self.workflows = copy.deepcopy(original)
                job = self.workflows['supabase.yml']['jobs']['current-source-contracts']
                step = next(step for step in job['steps'] if step.get('run') == policy.CURRENT_COMMISSIONING_DENO_COMMAND)
                step['run'] = step['run'].replace(required, 'removed-required-deno-input', 1)
                self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = copy.deepcopy(original)
        self.workflows['supabase.yml']['jobs']['current-source-contracts']['env']['COLLECT_DENO'] = '/unreviewed/deno'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = copy.deepcopy(original)
        job = self.workflows['supabase.yml']['jobs']['current-source-contracts']
        step = next(step for step in job['steps'] if step.get('run') == policy.CURRENT_COMMISSIONING_DENO_COMMAND)
        step['working-directory'] = '/unreviewed/checkout'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = copy.deepcopy(original)
        job = self.workflows['supabase.yml']['jobs']['current-source-contracts']
        step = next(step for step in job['steps'] if step.get('run') == policy.CURRENT_COMMISSIONING_DENO_COMMAND)
        step['run'] += ' || true'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = original

    def test_recovery13_make_hook_cannot_be_conditional_ignored_or_duplicated(self):
        source = policy.read_make_sources(ROOT)
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
        source = policy.read_make_sources(ROOT)
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
                   'AUTH_CAPTCHA_SITE_KEY': 'synthetic_public_site_key'}
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
        transport = ('node --test deploy/platform-admin/test/backend-selection.test.mjs '
                     'deploy/platform-admin/test/supabase-transport.test.mjs')
        challenge = ('node --test deploy/platform-admin/test/supabase-transport-bounded.test.mjs '
                     'deploy/platform-admin/test/human-parent.test.mjs test/local-challenge-parent.test.mjs')
        caller = self.workflows['ci.yml']['jobs']['supabase-platform']
        self.assertEqual(caller['uses'], './.github/workflows/supabase.yml')
        self.assertNotIn('if', caller)
        self.assertNotIn('with', caller)
        job = self.workflows['supabase.yml']['jobs']['current-source-contracts']
        self.assertEqual(job['if'], policy.CURRENT_PROFILE_CONDITION)
        self.assertIs(job.get('continue-on-error', False), False)
        default = job.get('defaults', {}).get('run', {}).get('working-directory', '.')
        for command in (transport, challenge):
            with self.subTest(command=command):
                matching = [step for step in job['steps'] if step.get('run') == command]
                self.assertEqual(len(matching), 1)
                self.assertNotIn('if', matching[0])
                self.assertIs(matching[0].get('continue-on-error', False), False)
                self.assertIn(matching[0].get('working-directory', default), ('.', '${{ github.workspace }}'))
        historical = self.workflows['supabase.yml']['jobs']['local-qualification']
        historical_commands = [step.get('run') for step in historical['steps']]
        self.assertIn(transport, historical_commands)
        self.assertIn('node --test test/local-challenge-parent.test.mjs', historical_commands)
        for filename in ('ci.yml', 'supabase.yml'):
            workflow = self.workflows[filename]
            events = workflow.get('on', workflow.get('true', {}))
            for event in ('push', 'pull_request'):
                declaration = events.get(event)
                if isinstance(declaration, dict) and 'paths' in declaration:
                    required = {'deploy/platform-admin/**', 'test/local-challenge-parent.test.mjs',
                                'test/fixtures/local-challenge-parent-harness.mjs'}
                    self.assertTrue(required.issubset(declaration['paths']), (filename, event))

    def test_supabase_current_checks_cover_recovered_decoder_and_handoff(self):
        workflow = self.workflows['supabase.yml']
        events = workflow.get('on', workflow.get('true', {}))
        paths = {
            'tools/roster-decoder/**',
            'scripts/qa/roster_wheelhouse.py',
            'scripts/tests/roster_wheelhouse_test.py',
            'scripts/tests/roster_decoder_lifecycle_support.py',
            'scripts/tests/roster_decoder_lifecycle_worker.py',
        }
        for event in ('push', 'pull_request'):
            self.assertTrue(paths.issubset(set(events[event]['paths'])), event)
        job = workflow['jobs']['current-source-contracts']
        self.assertEqual(job['if'], policy.CURRENT_PROFILE_CONDITION)
        for command in (
            'node --test deploy/platform-admin/test/static-handoff.test.mjs',
            'python3 scripts/tests/roster_wheelhouse_test.py',
            'node --test scripts/supabase/testing/recovered-domain-safety.test.mjs',
        ):
            with self.subTest(command=command):
                matches = [step for step in job['steps'] if step.get('run') == command]
                self.assertEqual(len(matches), 1)
                self.assertNotIn('if', matches[0])
                self.assertIs(matches[0].get('continue-on-error', False), False)

    def test_current_native_cannot_be_omitted_or_masked(self):
        original = copy.deepcopy(self.workflows)
        name, command = policy.CURRENT_NATIVE_JOB, policy.CURRENT_NATIVE_COMMAND
        for mutation in ('omit', 'skip-job', 'ignore-job', 'skip-check', 'ignore-check', 'different-command', 'mutable-checkout'):
            with self.subTest(job=name, mutation=mutation):
                self.workflows = copy.deepcopy(original)
                job = self.workflows['supabase.yml']['jobs'][name]
                step = next(step for step in job['steps'] if step.get('run', '').strip() == command)
                if mutation == 'omit': job['steps'].remove(step)
                elif mutation == 'skip-job': job['if'] = '${{ false }}'
                elif mutation == 'ignore-job': job['continue-on-error'] = True
                elif mutation == 'skip-check': step['if'] = '${{ false }}'
                elif mutation == 'ignore-check': step['continue-on-error'] = True
                elif mutation == 'different-command': step['run'] += ' || true'
                else:
                    checkout = next(step for step in job['steps'] if step.get('uses', '').startswith('actions/checkout@'))
                    checkout['with']['ref'] = 'main'
                self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_http_admission_native_qualification_cannot_be_omitted_or_masked(self):
        original = copy.deepcopy(self.workflows)
        for command in (policy.CURRENT_HTTP_NATIVE_COMMAND, policy.CURRENT_BURI_NATIVE_COMMAND,
                        policy.CURRENT_NONCE_NATIVE_COMMAND, policy.CURRENT_PORTABILITY_NATIVE_COMMAND,
                        policy.CURRENT_TRANSFER_NATIVE_COMMAND, policy.CURRENT_SMS_NATIVE_COMMAND,
                        policy.WRITER_JOURNAL_PG_COMMAND, policy.CURRENT_PG_HANDLER_COMMAND):
            for mutation in ('omit', 'skip', 'ignore', 'different-command'):
                self.workflows = copy.deepcopy(original)
                job = self.workflows['supabase.yml']['jobs'][policy.CURRENT_NATIVE_JOB]
                step = next(step for step in job['steps'] if step.get('run', '').strip() == command)
                if mutation == 'omit': job['steps'].remove(step)
                elif mutation == 'skip': step['if'] = '${{ false }}'
                elif mutation == 'ignore': step['continue-on-error'] = True
                else: step['run'] += ' || true'
                with self.subTest(command=command, mutation=mutation):
                    self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_current_pg_handler_job_requires_its_disposable_fixtures(self):
        job = self.workflows['supabase.yml']['jobs'][policy.CURRENT_NATIVE_JOB]
        step = next(s for s in job['steps'] if s.get('run', '').strip() == policy.CURRENT_PG_HANDLER_COMMAND)
        step['env']['COLLECT_TEST_DATABASE_URL'] = 'postgres://hosted.invalid/production'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_writer_journal_requires_the_digest_pinned_postgres_runner(self):
        native = next(job for job in self.workflows['supabase.yml']['jobs'].values()
                      if any(step.get('run', '').strip() == policy.WRITER_JOURNAL_PG_COMMAND
                             for step in job.get('steps', [])))
        native['container']['image'] = 'postgres:17.10'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_supabase_source_contracts_and_synthetic_target_cannot_drift(self):
        original = copy.deepcopy(self.workflows)
        for command in policy.CURRENT_SOURCE_COMMANDS:
            for mutation in ('omit', 'skip', 'ignore'):
                self.workflows = copy.deepcopy(original)
                job = self.workflows['supabase.yml']['jobs']['current-source-contracts']
                step = next(step for step in job['steps'] if step.get('run', '').strip() == command)
                if mutation == 'omit': job['steps'].remove(step)
                elif mutation == 'skip': step['if'] = '${{ false }}'
                else: step['continue-on-error'] = True
                with self.subTest(command=command, mutation=mutation):
                    self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())
        self.workflows = copy.deepcopy(original)
        self.workflows['supabase.yml']['jobs'][policy.CURRENT_NATIVE_JOB]['env']['COLLECT_FENCE_ADMIN_DATABASE_URL'] = 'postgres://hosted.invalid/production'
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_reusable_current_gate_cannot_select_history_or_be_hidden(self):
        original = copy.deepcopy(self.workflows)
        for patch in ({'uses': './.github/workflows/other.yml'}, {'if': '${{ false }}'},
                      {'continue-on-error': True}, {'with': {'qualification_profile': 'historical-current16'}},
                      {'secrets': 'inherit'}, {'steps': []}, {'timeout-minutes': 25}):
            self.workflows = copy.deepcopy(original)
            self.workflows['ci.yml']['jobs']['supabase-platform'].update(patch)
            with self.subTest(patch=patch):
                self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_historical_native_jobs_require_reviewed_immutable_source(self):
        original = copy.deepcopy(self.workflows)
        for name in ('local-qualification', 'control-concurrency-native', 'stopped-admission-lifecycle-native',
                     'current16-integration-native', 'current14-member-history-dart'):
            for mutation in ('automatic', 'mutable-source'):
                self.workflows = copy.deepcopy(original)
                job = self.workflows['supabase.yml']['jobs'][name]
                if mutation == 'automatic': job.pop('if')
                else:
                    checkout = next(step for step in job['steps'] if step.get('uses', '').startswith('actions/checkout@'))
                    checkout['with']['ref'] = 'main'
                with self.subTest(job=name, mutation=mutation):
                    self.assertIn('CI_HISTORICAL_SOURCE_REQUIRED', self.codes())

    def test_current_profile_cannot_default_to_or_auto_admit_history(self):
        original = copy.deepcopy(self.workflows)
        for mutation in ('historical-default', 'mutable-history', 'automatic-history'):
            self.workflows = copy.deepcopy(original)
            step = self.workflows['supabase.yml']['jobs']['select-profile']['steps'][0]
            if mutation == 'historical-default': step['env']['PROFILE'] = 'historical-current16'
            elif mutation == 'mutable-history': step['run'] = step['run'].replace("assert re.fullmatch(r'[a-f0-9]{40}', source)", 'assert source')
            else: step['run'] = step['run'].replace("assert not historical or os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch'", 'assert True')
            with self.subTest(mutation=mutation):
                self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_current_evidence_never_uploads_private_runtime_descriptor(self):
        job = self.workflows['supabase.yml']['jobs'][policy.CURRENT_NATIVE_JOB]
        job['steps'].append({'uses': 'actions/upload-artifact@' + 'a' * 40,
                             'with': {'path': '/tmp/runtime.private.json'}})
        self.assertIn('CI_SUPABASE_QUALIFICATION_REQUIRED', self.codes())

    def test_supabase_candidate_cannot_fall_back_to_another_backend(self):
        original = copy.deepcopy(self.workflows)
        for boundary in ('build', 'consumer'):
            with self.subTest(boundary=boundary):
                self.workflows = copy.deepcopy(original)
                jobs = self.workflows['ci.yml']['jobs']
                job = jobs['admin-web-build' if boundary == 'build' else 'admin-platform-candidate']
                step = next(s for s in job['steps'] if 'build-admin.mjs verify-ci' in s.get('run', ''))
                step['env']['COLLECT_BACKEND'] = 'cloudflare'
                self.assertIn('CI_SUPABASE_CANDIDATE_SELECTION_REQUIRED', self.codes())

    def test_shipping_identity_cannot_download_the_legacy_preview_artifact(self):
        job = self.workflows['ci.yml']['jobs']['admin-platform-candidate']
        step = next(s for s in job['steps'] if str(s.get('uses', '')).startswith('actions/download-artifact@'))
        step['with']['name'] = 'admin-cloudflare-candidate'
        self.assertIn('CI_SHIPPING_PLATFORM_ARTIFACT_REQUIRED', self.codes())

    def test_shipping_identity_requires_retained_react_receipt(self):
        job = self.workflows['ci.yml']['jobs']['admin-web-build']
        step = next(s for s in job['steps'] if s.get('with', {}).get('name') == 'admin-platform-pwa-candidate')
        step['with']['path'] = '\n'.join(line for line in step['with']['path'].splitlines()
                                         if line.strip() != 'build/admin-web.json')
        self.assertIn('CI_SHIPPING_PLATFORM_INPUT_REQUIRED', self.codes())

    def test_shipping_build_requires_the_compiled_browser_session_checks(self):
        steps = self.workflows['ci.yml']['jobs']['admin-web-build']['steps']
        step = next(s for s in steps if 'admin-web/tests/browser/smoke.mjs' in s.get('run', ''))
        step['continue-on-error'] = True
        self.assertIn('CI_COMPILED_ADMIN_BROWSER_REQUIRED', self.codes())

    def test_unit_job_runs_the_bound_member_history_decoder(self):
        steps = self.workflows['ci.yml']['jobs']['unit-test']['steps']
        step = next(s for s in steps if s.get('run') == 'make test-history-retained')
        step['continue-on-error'] = True
        self.assertIn('CI_RETAINED_MEMBER_HISTORY_REQUIRED', self.codes())

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


    def test_shipping_identity_cannot_skip_the_clean_commit_and_profile_verifier(self):
        for job_name in ('admin-web-build', 'admin-platform-candidate'):
            with self.subTest(job_name=job_name):
                job = self.workflows['ci.yml']['jobs'][job_name]
                step = next(s for s in job['steps'] if 'build-admin.mjs verify-ci' in s.get('run', ''))
                original = step['run']
                step['run'] = original.replace('verify-ci', 'verify')
                expected = ('CI_SHIPPING_PLATFORM_BUILD_REQUIRED' if job_name == 'admin-web-build'
                            else 'CI_SHIPPING_PLATFORM_ARTIFACT_REQUIRED')
                self.assertIn(expected, self.codes())
                step['run'] = original

    def test_local_pass_cannot_attest_hosted_security_or_mutation(self):
        report = policy.inspect(ROOT)
        self.assertEqual(report["status"], "pass")
        self.assertIs(report["hosted_enforcement_verified"], False)
        self.assertIs(report["security_scan_execution_verified"], False)
        self.assertIs(report["remote_settings_changed"], False)


if __name__ == "__main__":
    unittest.main()
