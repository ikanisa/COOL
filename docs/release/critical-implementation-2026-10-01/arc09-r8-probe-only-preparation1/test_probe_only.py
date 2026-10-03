"""Pure controller fixtures: every process/guard/provider read is mocked."""
import importlib.util
import json
from pathlib import Path
import tempfile
import types
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('private_probe_fixture', HERE / 'run_probe_only.py')
P = importlib.util.module_from_spec(spec); spec.loader.exec_module(P)


class ProbeFixtures(unittest.TestCase):
    def execute(self, classification='known', process_exit=0, provider_drift=False, live_daemon=False, after_source_exit=0):
        calls = []; captured = {}
        compiler = {'provider': {'path':'/fixture/private/instrumented-r8.jar','sha256':'b'*64,'bytes':123},
                    'resolved_artifact': {'path':'/fixture/private/r8.jar','sha256':'a'*64,'bytes':456}}
        row = {'kind':'collect_default_proguard_directory_readback', 'actual_R8_compiler_readback':compiler,
               'default_proguard_file':'/fixture/BASE/native-build/app/rules','actual_default_file_sha256':'c'*64,'actual_default_file_bytes':10}
        def stable(path):
            if str(path)=='/fixture/BASE/native-build/app/rules': return ({'sha256':'c'*64,'bytes':10},b'')
            observed = next(r for r in compiler.values() if r['path']==str(path))
            return (dict(observed,sha256='0'*64) if provider_drift else dict(observed), b'')
        def admitted(stdout, app):
            self.assertIn('configuration-observation.json', captured)
            self.assertIn('compiler-provider-observation.json', captured)
            if classification=='unknown': raise ValueError('actual R8 classloader uses an unknown or unadmitted compiler provider')
            if classification=='invalid': raise ValueError('actual AGP R8 classloader/version/invocation/artifact readback differs')
            return row
        def process_success(actual):
            if actual['exit_code'] != 0: raise ValueError('actual stage failed')
        def run_process(output,label,argv,bound,cwd,env):
            calls.append((label,argv,bound))
            body='COLLECT_DEFAULT_PROGUARD_READBACK='+json.dumps(row)+'\n' if label=='production-default-proguard-readback' else ''
            (output/(label+'.stdout')).write_text(body);(output/(label+'.stderr')).write_text('fixture retained stderr')
            return {'exit_code':process_exit if label=='production-default-proguard-readback' else
                    (after_source_exit if label=='source-fence-after-command' else 0),'fixture':True}
        class Tracker:
            def __init__(self,*args): pass
            def private_identity(self,row): return {'fixture':True} if live_daemon else None
            def finish(self): return {'observer_error':None,'owned_daemons_absent':True,'fixture':True}
        def save(path,value): captured[path.name]=value;path.write_text(json.dumps(value))
        ctx=types.SimpleNamespace(config={'environment_exact':{'fixture':'original'},'Python_executable':'/fixture/python'},
            readback_command={'label':'production-default-proguard-readback','argv':['/fixture/wrapper',':app:collectVerifyDefaultProguardDirectory'],'cwd':'/fixture/APP','deadline_seconds':300},
            current_app_export={'current_repository_source_fence_pin':{'path':'/fixture/current-fence','sha256':'d'*64}},
            admission={'native_observed_daemons':[]}, reader=types.SimpleNamespace(stable_read=stable),
            overlay=types.SimpleNamespace(validate_proguard_output=admitted),
            controller=types.SimpleNamespace(subprocess=object(),run_process=run_process),
            guards=types.SimpleNamespace(process_success=process_success))
        driver=types.SimpleNamespace(DaemonTracker=Tracker,process_table=lambda:{1:{'fixture':True}} if live_daemon else {},
            context=lambda args:ctx,PREP=Path('/fixture/PREP'),ROOT=Path('/fixture/ROOT'),BASE=Path('/fixture/BASE'),save=save)
        args=types.SimpleNamespace(controller_sha256='e'*64,admission=Path('/fixture/admission'),admission_sha256='f'*64)
        with tempfile.TemporaryDirectory(prefix='pure-probe-',dir=HERE) as directory:
            rc=P.run_probe(ctx,driver,Path(directory),args)
        return rc,calls,captured

    def assert_only_probe_and_guards(self,calls):
        self.assertEqual([c[0] for c in calls],['source-fence-before-command','combined-guard-before-command',
            'production-default-proguard-readback','source-fence-after-command','combined-guard-after-command'])
        self.assertTrue(all(c[2]==300 for c in calls))

    def test_known_provider_stops_after_probe_and_guards(self):
        rc,calls,rows=self.execute();self.assertEqual(rc,0);self.assert_only_probe_and_guards(calls)
        self.assertEqual(rows['terminal.json']['classification'],'OBSERVED_ADMITTED_PROVIDER')
        self.assertFalse(rows['terminal.json']['AAB_built']);self.assertFalse(rows['terminal.json']['APP_compiled'])
        self.assertFalse(rows['terminal.json']['fresh_runtime_compile_graphs_executed'])

    def test_unknown_provider_is_retained_without_acceptance_or_build(self):
        rc,calls,rows=self.execute('unknown');self.assertEqual(rc,2);self.assert_only_probe_and_guards(calls)
        self.assertIn('configuration-observation.json',rows);self.assertIn('compiler-provider-observation.json',rows)
        self.assertIn('provider-admission-refusal.json',rows)
        self.assertTrue(rows['terminal.json']['required_guards_complete'])
        self.assertEqual(rows['terminal.json']['classification'],'OBSERVED_UNADMITTED_PROVIDER')
        self.assertFalse(rows['compiler-provider-observation.json']['root_transformed_provider_admission_claimed'])

    def test_other_invalid_readback_remains_failure_with_actual_evidence(self):
        rc,calls,rows=self.execute('invalid');self.assertEqual(rc,1);self.assert_only_probe_and_guards(calls)
        self.assertIn('compiler-provider-observation.json',rows);self.assertTrue(rows['terminal.json']['errors'])

    def test_provider_drift_cannot_be_classified_as_admitted(self):
        rc,calls,rows=self.execute(provider_drift=True);self.assertEqual(rc,1);self.assert_only_probe_and_guards(calls)
        self.assertIn('configuration-observation.json',rows);self.assertNotIn('compiler-provider-observation.json',rows)

    def test_probe_failure_still_verifies_after_guards(self):
        rc,calls,rows=self.execute(process_exit=143);self.assertEqual(rc,1);self.assert_only_probe_and_guards(calls)
        self.assertEqual(rows['terminal.json']['commands']['production-default-proguard-readback']['command']['exit_code'],143)

    def test_existing_private_daemon_refuses_probe_without_stop(self):
        rc,calls,rows=self.execute(live_daemon=True);self.assertEqual(rc,1)
        self.assertEqual([c[0] for c in calls],['source-fence-after-command','combined-guard-after-command'])
        self.assertFalse(rows['terminal.json']['AAB_built'])

    def test_after_source_failure_still_runs_APP_SDK_protected_guard(self):
        rc,calls,rows=self.execute(after_source_exit=1);self.assertEqual(rc,1);self.assert_only_probe_and_guards(calls)
        self.assertFalse(rows['terminal.json']['required_guards_complete'])
        self.assertEqual(rows['terminal.json']['protected_original_PID_scope'],68020)
        self.assertFalse(rows['terminal.json']['signal_authority_for_protected_original_PID'])


if __name__=='__main__': unittest.main(verbosity=2)
