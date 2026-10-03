"""Pure fixture identities only. No Gradle, processes, actual JAR or cache writes."""
import copy
import importlib.util
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('r8_proposal_fixture', HERE / 'driver/android_build_overlay.py')
H = importlib.util.module_from_spec(spec); spec.loader.exec_module(H)
REL = HERE.parent
APP = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/app-source')
GH = APP.parent / 'gradle-home'


def artifact():
    value = json.loads((HERE / 'r8-artifact-admission-template.json').read_text())
    value['jar'].update(path=str(HERE / 'synthetic_fixture_only.jar'), sha256=H.PUBLISHER_JAR_SHA256)
    value['actual_acquisition'].update(observed=True, HTTP_code=200, TLS_verify_result=0,
                                      effective_url=H.ARTIFACT_URL)
    return value


def readback():
    return {'coordinate': 'com.android.tools:r8:9.1.29', 'version': '9.1.29',
            'tool_class': 'com.android.builder.dexing.R8Tool', 'R8_class': 'com.android.tools.r8.R8',
            'invoked_declaring_class': 'com.android.tools.r8.R8',
            'invoked_method': 'public static void com.android.tools.r8.R8.main(java.lang.String[])',
            'invoked_method_name': 'main', 'invoked_modifiers': 9, 'invoked_return_type': 'void',
            'invoked_parameter_types': ['[Ljava.lang.String;'], 'invoked_arguments': ['--version'],
            'version_method_invoked': True, 'R8_selected_from_AGP_tool_classloader': True,
            'tool_classloader': 'fixture.AGPLoader', 'tool_classloader_identity': 111,
            'R8_classloader': 'fixture.R8Loader', 'R8_classloader_identity': 222,
            'version_stdout': 'R8 9.1.29 (fixture build)\n',
            'provider': {'path': str(GH / 'fixture/r8-9.1.29.jar'), 'sha256': H.PUBLISHER_JAR_SHA256, 'bytes': 56139715},
            'resolved_artifact': {'path': str(GH / 'fixture/r8-9.1.29.jar'), 'sha256': H.PUBLISHER_JAR_SHA256,
                                  'bytes': 56139715, 'md5_hex': '60e153b8c1dba4d97e9b1ef2d75c2e61'},
            'app_compilation_executed_by_this_task': False}


class R8Fixtures(unittest.TestCase):
    def setUp(self):
        self.value = artifact(); self.row = readback()

    def refuse_readback(self):
        with self.assertRaises((ValueError, KeyError)):
            H.validate_r8_readback(self.row, self.value, GH)

    def test_exact_publisher_compiler_fixture_is_accepted(self):
        self.assertEqual(H.validate_r8_readback(self.row, self.value, GH), self.row)

    def test_preparation_template_is_not_execution_admission(self):
        with self.assertRaises(ValueError):
            H.validate_r8_artifact(json.loads((HERE / 'r8-artifact-admission-template.json').read_text()))

    def test_unknown_provider_is_refused(self):
        self.row['provider']['sha256'] = 'b' * 64; self.refuse_readback()

    def test_explicit_root_provider_fixture_is_accepted(self):
        self.row['provider'].update(path=str(GH / 'fixture/instrumented-r8-9.1.29.jar'), sha256='b' * 64, bytes=123)
        self.value['root_pinned_transformed_providers'] = [dict(self.row['provider'],
            source_artifact_sha256=H.PUBLISHER_JAR_SHA256,
            provenance_receipt={'path': str(REL / 'fixture-provenance.json'), 'sha256': 'c' * 64})]
        self.assertEqual(H.validate_r8_readback(self.row, self.value, GH), self.row)

    def test_provider_pin_from_another_artifact_is_refused(self):
        self.value['root_pinned_transformed_providers'] = [dict(self.row['provider'],
            source_artifact_sha256='b' * 64, provenance_receipt={'path':'/fixture','sha256':'c'*64})]
        self.refuse_readback()

    def test_actual_old9_0_32_compiler_is_refused(self):
        self.row['version'] = '9.0.32'; self.row['version_stdout'] = 'R8 9.0.32\n'; self.refuse_readback()

    def test_declared_version_without_actual_matching_output_is_refused(self):
        self.row['version_stdout'] = 'R8 9.0.32\n'; self.refuse_readback()

    def test_dynamic_or_different_coordinate_is_refused(self):
        self.value['coordinate'] = 'com.android.tools:r8:latest.release'; self.refuse_readback()

    def test_non_AGP_loader_selection_is_refused(self):
        self.row['R8_selected_from_AGP_tool_classloader'] = False; self.refuse_readback()

    def test_missing_invocation_is_refused(self):
        self.row['version_method_invoked'] = False; self.refuse_readback()

    def test_different_method_arguments_are_refused(self):
        self.row['invoked_arguments'] = ['--release']; self.refuse_readback()

    def test_nonpublic_method_is_refused(self):
        self.row['invoked_modifiers'] = 2; self.refuse_readback()

    def test_R8_compilation_claim_is_refused(self):
        self.row['app_compilation_executed_by_this_task'] = True; self.refuse_readback()

    def test_outside_controlled_provider_is_refused(self):
        self.row['provider']['path'] = '/tmp/r8-9.1.29.jar'; self.refuse_readback()

    def test_different_resolved_artifact_hash_is_refused(self):
        self.row['resolved_artifact']['sha256'] = 'b' * 64; self.refuse_readback()

    def test_missing_publisher_TLS_proof_is_refused(self):
        self.value['actual_acquisition']['TLS_verify_result'] = 1; self.refuse_readback()

    def test_different_publisher_url_is_refused(self):
        self.value['publisher_url'] = 'https://example.com/r8.jar'; self.refuse_readback()

    def test_unobserved_JAR_acquisition_is_refused(self):
        self.value['actual_acquisition']['observed'] = False; self.refuse_readback()

    def test_different_publisher_MD5_is_refused(self):
        self.value['jar']['md5_hex'] = '0' * 32; self.refuse_readback()

    def test_exact_probe_changes_only_init_argument(self):
        old = json.loads((REL / 'arc09-early-build-root-preparation1/verification-plan.json').read_text())
        supplied = json.loads((HERE / 'root-admission-template.json').read_text())['default_proguard_probe_override']
        seam = types.SimpleNamespace(RELEASE=REL, APP=APP,
            document=lambda p, s: json.loads(Path(p).read_text()), plain_read=lambda p,s: Path(p).read_bytes())
        actual = H.validate_probe_override(seam, supplied, old)
        expected = list(old['argv']); expected[expected.index('--init-script')+1] = supplied['init_script']['path']
        self.assertEqual(actual['argv'], expected); self.assertEqual(actual['deadline_seconds'],300)

    def test_extra_probe_argument_is_refused(self):
        old = json.loads((REL / 'arc09-early-build-root-preparation1/verification-plan.json').read_text())
        new = json.loads((HERE / 'reviewed-verification-plan.json').read_text()); new['argv'].append('--refresh-dependencies')
        supplied = json.loads((HERE / 'root-admission-template.json').read_text())['default_proguard_probe_override']
        seam = types.SimpleNamespace(RELEASE=REL, APP=APP, document=lambda p,s:new, plain_read=lambda p,s:b'fixture')
        with self.assertRaises(ValueError): H.validate_probe_override(seam, supplied, old)

    def test_missing_probe_override_is_refused(self):
        with self.assertRaises(ValueError): H.validate_probe_override(None,None,{})

    def test_unknown_probe_hash_is_refused(self):
        supplied = json.loads((HERE / 'root-admission-template.json').read_text())['default_proguard_probe_override']
        supplied['init_script']['sha256'] = '0' * 64
        seam = types.SimpleNamespace(RELEASE=REL)
        with self.assertRaises(ValueError): H.validate_probe_override(seam,supplied,{})


if __name__ == '__main__': unittest.main(verbosity=2)
