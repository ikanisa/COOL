#!/usr/bin/env python3
"""Real private filesystem mutations only; no Flutter/Gradle or stage execution."""
import hashlib
import importlib.util
import json
import os
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE.parent / 'kotlin-sdk-native-consumer-preparation1'

def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result

G = module(HERE / 'consumer_guards.py', 'focused_app_guard')
C = module(HERE / 'run_native_consumer.py', 'focused_app_controller')
F = module(HERE / 'source_fence.py', 'focused_app_fence')
O = module(ORIGINAL / 'test_preparation.py', 'unchanged_original31_tests')
METADATA_READER = O.guards.load_metadata

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

class RegistrantGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='collect-app-guard-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup); self.base = Path(self.temp.name)
        self.app = self.base / 'app'; self.sdk = self.base / 'flutter'; self.pub = self.base / 'pub-cache'
        self.private = self.base / 'proposal'; self.private.mkdir()
        def file(path, body):
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(body); return path
        self.file = file
        source = G.SDK
        for name in G.SDK_PLUGIN_SOURCE_HASHES:
            file(self.sdk / name, (source / name).read_bytes())
        self.root = self.pub / 'hosted/pub.dev/fixture_plugin-1.0.0'
        self.spec = file(self.root / 'pubspec.yaml', b'name: fixture_plugin\nversion: 1.0.0\nflutter:\n  plugin:\n    platforms:\n      ios:\n        pluginClass: FixturePlugin\n')
        for root in (self.root, self.sdk / 'packages/integration_test', self.app): (root / 'lib').mkdir(parents=True, exist_ok=True)
        file(self.app / 'pubspec.yaml', b'name: collect\nversion: 1.0.0\n')
        self.lock = file(self.app / 'pubspec.lock', b'packages:\n  fixture_plugin:\n    description:\n      name: fixture_plugin\n      url: "https://pub.dev"\n    source: hosted\n    version: "1.0.0"\n  integration_test:\n    description: flutter\n    source: sdk\n    version: "0.0.0"\n')
        file(self.app / 'lib/main.dart', b'void main() {}\n'); file(self.app / 'LICENSE', b'Fixture\n')
        file(self.app / 'ios/Runner/Info.plist', b'<plist/>\n')
        authored = {}
        for name in ('pubspec.yaml', 'pubspec.lock', 'lib/main.dart', 'LICENSE', 'ios/Runner/Info.plist'):
            row, _ = G.load_metadata().stable_read(self.app / name)
            authored[name] = {key: row[key] for key in ('sha256', 'bytes', 'mode')}
        canonical = (json.dumps(authored, sort_keys=True, separators=(',', ':'))+'\n').encode()
        manifest = dict(kind='unapproved_collect_source_export', retain_source_drift=False,
                        capture_classification='strict_unapproved_source_export', source_files=authored,
                        source_manifest_sha256=hashlib.sha256(canonical).hexdigest(), file_count=len(authored),
                        approvals={name:False for name in ('trusted_source_verified','reviewed','frozen','owner_approved','signed','production_release_accepted')})
        self.manifest = file(self.app / '.collect-release-candidate.json', json.dumps(manifest).encode())
        packages = [{'name':name,'rootUri':str(root)+'/', 'packageUri':'lib/'} for name,root in
                    [('fixture_plugin',self.root),('integration_test',self.sdk/'packages/integration_test'),('collect',self.app)]]
        self.config = file(self.app / '.dart_tool/package_config.json', json.dumps(dict(configVersion=2,packages=packages)).encode())
        self.metadata = file(self.app / '.flutter-plugins-dependencies', json.dumps(dict(plugins={'ios':[
            dict(name='fixture_plugin',path=str(self.root)+'/',native_build=True),
            dict(name='integration_test',path=str(self.sdk/'packages/integration_test')+'/',native_build=True)]})).encode())
        binding = dict(format='collect-exact-locked-plugin-pubspec-bindings-v1',sources={name:dict(exact_root=str(root),pubspec_sha256=digest(root/'pubspec.yaml'),pubspec_bytes=(root/'pubspec.yaml').stat().st_size) for name,root in [('fixture_plugin',self.root),('integration_test',self.sdk/'packages/integration_test')]})
        self.binding = file(self.private / 'plugin-source-bindings.json', json.dumps(binding).encode())
        self.h = file(self.app / G.IOS_REGISTRANTS[0], (G.APP / G.IOS_REGISTRANTS[0]).read_bytes())
        prefix = '//\n//  Generated file. Do not edit.\n//\n\n// clang-format off\n\n#import "GeneratedPluginRegistrant.h"\n\n'
        native = [('fixture_plugin','FixturePlugin'),('integration_test','IntegrationTestPlugin')]
        imports = ''.join('#if __has_include(<'+name+'/'+cls+'.h>)\n#import <'+name+'/'+cls+'.h>\n#else\n@import '+name+';\n#endif\n\n' for name,cls in native)
        footer = '@implementation GeneratedPluginRegistrant\n\n+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {\n'+''.join('  ['+cls+' registerWithRegistrar:[registry registrarForPlugin:@"'+cls+'"]];\n' for _,cls in native)+'}\n\n@end\n'
        self.m = file(self.app / G.IOS_REGISTRANTS[1], (prefix+imports+footer).encode())
        for key, value in [('APP',self.app),('SDK',self.sdk),('PUB',self.pub),('HERE',self.private),('PLUGIN_BINDINGS_SHA256',digest(self.binding))]:
            patch = mock.patch.object(G, key, value);patch.start();self.addCleanup(patch.stop)
        # The metadata reader is byte-identical to the original; fixtures do not relocate it.
        patch = mock.patch.object(G, 'load_metadata', METADATA_READER);patch.start();self.addCleanup(patch.stop)

    def app_readback(self): return G.app_readback('app-locked', digest(self.manifest))
    def test_exact_names_and_rendering_accept_with_sdk_integration_test(self):
        result = self.app_readback()
        self.assertEqual(len(result['exact_generated_ios_registrants']['method_channel_plugins']), 2)
        self.assertFalse(result['exact_generated_ios_registrants']['output_hash_allowlist_used'])
        self.assertEqual(G.plugin_metadata(self.metadata)['SDK_plugin_exception'], 'integration_test only')
    def test_header_byte_mutation_rejected(self):
        self.h.write_bytes(self.h.read_bytes()+b'// unauthorized\n')
        with self.assertRaisesRegex(ValueError, 'registrant differs'): self.app_readback()
    def test_unlisted_generated_class_rejected(self):
        self.m.write_bytes(self.m.read_bytes().replace(b'FixturePlugin', b'UnlistedPlugin'))
        with self.assertRaisesRegex(ValueError, 'registrant differs'): self.app_readback()
    def test_template_source_drift_rejected(self):
        path=self.sdk/'packages/flutter_tools/lib/src/flutter_plugins.dart';path.write_bytes(path.read_bytes()+b'// changed\n')
        with self.assertRaisesRegex(ValueError, 'SDK plugin template/source drift'): self.app_readback()
    def test_pubspec_class_and_registrant_joint_mutation_rejected(self):
        self.spec.write_bytes(self.spec.read_bytes().replace(b'FixturePlugin',b'UnlistedPlugin'))
        self.m.write_bytes(self.m.read_bytes().replace(b'FixturePlugin',b'UnlistedPlugin'))
        with self.assertRaisesRegex(ValueError, 'pubspec bytes changed'): self.app_readback()
    def test_unlisted_ios_path_is_not_allowed(self):
        self.file(self.app/'ios/Runner/GeneratedPluginRegistrant.extra.m', b'anything\n')
        with self.assertRaisesRegex(ValueError, 'unreviewed generated source/path'): self.app_readback()
    def test_sdk_metadata_path_escape_rejected(self):
        data=json.loads(self.metadata.read_bytes());data['plugins']['ios'][1]['path']=str(self.sdk/'packages/flutter_tools')
        self.metadata.write_text(json.dumps(data))
        with self.assertRaises(ValueError): G.plugin_metadata(self.metadata)
    def test_other_sdk_package_config_root_rejected(self):
        self.file(self.sdk/'packages/flutter_tools/pubspec.yaml',b'name: flutter_tools\nversion: 1.0.0\n')
        data=json.loads(self.config.read_bytes());data['packages'][0]['rootUri']=str(self.sdk/'packages/flutter_tools')+'/'
        self.config.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'only exact integration_test'): G.plugin_metadata(self.metadata)
    def test_sdk_plugin_name_impersonation_rejected(self):
        data=json.loads(self.metadata.read_bytes());data['plugins']['ios'][1]['name']='integration_test_other';self.metadata.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'absent from exact reviewed'): G.plugin_metadata(self.metadata)
    def test_symlink_metadata_rejected(self):
        real=self.metadata.with_name('retained-metadata');self.metadata.rename(real);self.metadata.symlink_to(real)
        with self.assertRaises(ValueError): G.plugin_metadata(self.metadata)
    def test_symlink_plugin_pubspec_rejected(self):
        real=self.spec.with_name('retained-pubspec');self.spec.rename(real);self.spec.symlink_to(real)
        with self.assertRaises(ValueError): G.plugin_metadata(self.metadata)
    def test_missing_second_registrant_rejected(self):
        self.m.unlink()
        with self.assertRaises(FileNotFoundError): self.app_readback()
    def test_app_export_still_rejects_registrants(self):
        self.config.unlink();self.config.parent.rmdir();self.metadata.unlink()
        with self.assertRaisesRegex(ValueError, 'unreviewed generated source/path'): G.app_readback('app-export')
    def test_alias_duplicate_yaml_key_rejected(self):
        body=b'flutter:\n  plugin:\n    platforms:\n      ios:\n        pluginClass: First\n        pluginClass: Second\n'
        with self.assertRaises(ValueError): G.yaml_scalar(body,('flutter','plugin','platforms','ios','pluginClass'))
        with self.assertRaises(ValueError): G.yaml_scalar(b'name: *alias\n',('name',))
    def test_class_prefix_is_empty_for_pinned_modern_platforms_format(self):
        self.assertTrue(all(p['prefix']=='' for p in G.ios_registrants()['method_channel_plugins']))
    def test_stage_failure_remains_terminal(self):
        with self.assertRaisesRegex(ValueError,'terminal stage failure'):G.process_success({'exit_code':0,'owned_process_group_absent':True,'actual_controller_error':'guard refusal'})
    def swiftpm_fixture(self, firebase=False):
        manifest=self.file(self.root/'ios/fixture_plugin/Package.swift',b'// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: "fixture_plugin")\n')
        binding=json.loads(self.binding.read_text());binding['sources']['fixture_plugin']['ios_swiftpm_manifest']=dict(relative_path='ios/fixture_plugin/Package.swift',sha256=digest(manifest),bytes=manifest.stat().st_size)
        metadata=json.loads(self.metadata.read_text());metadata['swift_package_manager_enabled']={'ios':True}
        self.links=self.app/'ios/Flutter/ephemeral/Packages/.packages';self.links.mkdir(parents=True)
        self.link=self.links/self.root.name;self.link.symlink_to(manifest.parent)
        self.file(self.app/'ios/Flutter/AppFrameworkInfo.plist',b'<plist/>\n')
        if firebase:
            source=self.app/'third_party/firebase_messaging'
            pubspec=self.file(source/'pubspec.yaml',b'name: firebase_messaging\nversion: 16.5.0\nflutter:\n  plugin:\n    platforms:\n      ios:\n        pluginClass: FLTFirebaseMessagingPlugin\n')
            swift=self.file(source/'ios/firebase_messaging/Package.swift',b'// swift-tools-version: 5.9\n.package(name: "fixture_plugin", path: "../fixture_plugin")\n')
            self.file(source/'ios/firebase_messaging/Sources/native.m',b'// exact copied source\n')
            copied=self.app/'build/ios/SourcePackages/firebase_messaging';shutil.copytree(source,copied)
            (copied/'ios/firebase_messaging/Package.swift').write_bytes(swift.read_bytes().replace(b'"../fixture_plugin"',b'"../fixture_plugin-1.0.0"'))
            self.copy=copied;self.copy_source=source
            binding['sources']['firebase_messaging']=dict(exact_root=str(source),pubspec_sha256=digest(pubspec),pubspec_bytes=pubspec.stat().st_size,ios_swiftpm_manifest=dict(relative_path='ios/firebase_messaging/Package.swift',sha256=digest(swift),bytes=swift.stat().st_size))
            config=json.loads(self.config.read_text());config['packages'].append(dict(name='firebase_messaging',rootUri=str(source)+'/',packageUri='lib/'));self.config.write_text(json.dumps(config))
            self.lock.write_bytes(self.lock.read_bytes()+b'  firebase_messaging:\n    description:\n      path: "third_party/firebase_messaging"\n      relative: true\n    source: path\n    version: "16.5.0"\n')
            metadata['plugins']['ios'].append(dict(name='firebase_messaging',path=str(source)+'/',native_build=True));metadata['plugins']['ios'].sort(key=lambda row:row['name'])
            firebase_import=b'#if __has_include(<firebase_messaging/FLTFirebaseMessagingPlugin.h>)\n#import <firebase_messaging/FLTFirebaseMessagingPlugin.h>\n#else\n@import firebase_messaging;\n#endif\n\n'
            self.m.write_bytes(self.m.read_bytes().replace(b'#if __has_include(<fixture_plugin/',firebase_import+b'#if __has_include(<fixture_plugin/').replace(b'+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {\n',b'+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {\n  [FLTFirebaseMessagingPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTFirebaseMessagingPlugin"]];\n'))
            self.links.joinpath('firebase_messaging').symlink_to(copied/'ios/firebase_messaging')
        self.binding.write_text(json.dumps(binding));G.PLUGIN_BINDINGS_SHA256=digest(self.binding);self.metadata.write_text(json.dumps(metadata))
        # Refresh only this synthetic authored manifest after fixture construction.
        authored={}
        for path in self.app.rglob('*'):
            if path.is_file() and not path.is_symlink() and (path.name in ('LICENSE','pubspec.yaml','pubspec.lock','main.dart','Info.plist','AppFrameworkInfo.plist') or (firebase and path.is_relative_to(self.copy_source))):
                if path.is_relative_to(self.app/'build'):continue
                row,_=METADATA_READER().stable_read(path);authored[path.relative_to(self.app).as_posix()]={key:row[key] for key in ('sha256','bytes','mode')}
        doc=json.loads(self.manifest.read_text());doc['source_files']=authored;doc['file_count']=len(authored);doc['source_manifest_sha256']=hashlib.sha256((json.dumps(authored,sort_keys=True,separators=(',',':'))+'\n').encode()).hexdigest();self.manifest.write_text(json.dumps(doc))
    def test_exact_computed_swiftpm_link_is_accepted_without_traversal(self):
        self.swiftpm_fixture();result=self.app_readback();proof=result['exact_generated_swiftpm_links'][self.link.relative_to(self.app).as_posix()]
        self.assertEqual(proof['literal_target'],str(self.root/'ios/fixture_plugin'));self.assertTrue(proof['link_not_traversed'])
    def test_changed_generated_literal_target_rejected(self):
        self.swiftpm_fixture();self.link.unlink();self.link.symlink_to(self.sdk/'packages/integration_test')
        with self.assertRaisesRegex(ValueError,'literal target differs'):self.app_readback()
    def test_changed_generated_link_version_name_rejected(self):
        self.swiftpm_fixture();self.link.rename(self.links/'fixture_plugin-2.0.0')
        with self.assertRaisesRegex(ValueError,'unreviewed generated symlink'):self.app_readback()
    def test_generated_case_alias_rejected(self):
        self.swiftpm_fixture();self.link.rename(self.links/'FIXTURE_PLUGIN-1.0.0')
        with self.assertRaises(ValueError):self.app_readback()
    def test_generated_target_alias_rejected(self):
        self.swiftpm_fixture();target=self.root/'ios/fixture_plugin';retained=target.with_name('retained');target.rename(retained);target.symlink_to(retained)
        with self.assertRaises(ValueError):self.app_readback()
    def test_exact_firebase_copy_provenance_and_manifest_rewrite_accepted(self):
        self.swiftpm_fixture(firebase=True);result=self.app_readback();proof=result['generated_copy_provenance']['firebase_messaging']
        self.assertEqual(proof['only_rewritten_manifest'],'ios/firebase_messaging/Package.swift');self.assertGreater(proof['entries_verified'],3)
    def test_generated_copy_unauthorized_bytes_rejected(self):
        self.swiftpm_fixture(firebase=True);(self.copy/'ios/firebase_messaging/Sources/native.m').write_bytes(b'// changed copied source\n')
        with self.assertRaisesRegex(ValueError,'unauthorized byte delta'):self.app_readback()
    def test_generated_copy_signing_input_or_symlink_rejected(self):
        self.swiftpm_fixture(firebase=True);self.file(self.copy/'secret.key',b'private\n')
        with self.assertRaises(ValueError):self.app_readback()
        (self.copy/'secret.key').unlink();path=self.copy/'ios/firebase_messaging/Sources/native.m';path.unlink();path.symlink_to(self.copy_source/'ios/firebase_messaging/Sources/native.m')
        with self.assertRaises(ValueError):self.app_readback()
    def test_plugin_metadata_literal_path_alias_rejected(self):
        data=json.loads(self.metadata.read_text());data['plugins']['ios'][0]['path']=str(self.root)+'/../'+self.root.name+'/'
        self.metadata.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError,'literal package path alias'):G.plugin_metadata(self.metadata)
    def test_existing_exact_generated_java_file_ancestors_and_unknown_sibling(self):
        java=self.file(self.app/'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',b'// synthetic generated fixture\n')
        self.assertIn(java.relative_to(self.app).as_posix(),self.app_readback()['generated_files_separate'])
        self.file(self.app/'android/app/src/main/java/unreviewed/Injected.java',b'// not admitted\n')
        with self.assertRaisesRegex(ValueError,'unreviewed directory path'):self.app_readback()

class ControllerWiringTests(unittest.TestCase):
    def test_original_commands_and_resource_bounds_remain_exact(self):
        config=json.loads((HERE/'proposed-commands.json').read_text())
        F.validate_commands(config, C.HERE, C.PROPOSAL, C.REPO, C.BASE, C.SDK, C.APP, C.AUTH_DIR)
        original=json.loads((ORIGINAL/'proposed-commands.json').read_text())
        self.assertEqual(config['commands'],original['commands']);self.assertEqual(config['live_free_floor_bytes'],4*1024**3)
    def test_later_native_stage_refused_before_any_packet_read(self):
        with self.assertRaisesRegex(ValueError,'only fresh app-export and app-lock'):
            C.authorization(type('Args',(),dict(stage='native',foundation_child=False))())
    def admission_fixture(self, root, prior_packet, extra_admission=False):
        auth=root/'auth';auth.mkdir();base=root/'base';directory=base/'.control/app-export';directory.mkdir(parents=True)
        prior=directory/'terminal.json';prior.write_text(json.dumps(dict(stage_pass=True,stage='app-export',prepared_manifest_sha256=prior_packet)))
        fence=auth/'source-fence.json';fence.write_text('{}')
        document=dict(errors=[],packet_manifest_sha256='a'*64,checked_packet_leaves=1,
            execution_stage_admissions={'app-lock':True,'native':extra_admission},required_reviewed_guard_sha256=digest(HERE/'consumer_guards.py'),
            current_source_export_authorized=True,strict_current_source_comparison_required=True,private_snapshot_exclusive=True,
            source_scope_held_for_strict_export=False,source_lock_attested=False,transient_write_and_restore_absence_attested=False,
            required_source_fence_sha256=digest(fence),required_predecessor_terminal_sha256=digest(prior))
        receipt=auth/'app-lock-admission.json';receipt.write_text(json.dumps(document))
        return auth,base,fence,type('Args',(),dict(stage='app-lock',foundation_child=False,prepared_manifest_sha256='a'*64,root_review_sha256=digest(receipt)))()
    def test_prior_successful_export_from_other_packet_is_rejected(self):
        with tempfile.TemporaryDirectory(dir='/private/tmp') as tmp:
            auth,base,fence,args=self.admission_fixture(Path(tmp),'b'*64)
            with mock.patch.object(C,'AUTH_DIR',auth),mock.patch.object(C,'BASE',base),mock.patch.object(C,'SOURCE_FENCE',fence),mock.patch.object(C,'packet',return_value={'files':{'fixture':'c'*64}}):
                with self.assertRaisesRegex(ValueError,'fresh whole export'):C.authorization(args)
    def test_receipt_cannot_admit_native_alongside_app_lock(self):
        with tempfile.TemporaryDirectory(dir='/private/tmp') as tmp:
            auth,base,fence,args=self.admission_fixture(Path(tmp),'a'*64,True)
            with mock.patch.object(C,'AUTH_DIR',auth),mock.patch.object(C,'BASE',base),mock.patch.object(C,'SOURCE_FENCE',fence),mock.patch.object(C,'packet',return_value={'files':{'fixture':'c'*64}}):
                with self.assertRaisesRegex(ValueError,'not separately authorized'):C.authorization(args)

ORIGINAL_AFFECTED = (
    'test_authored_source_and_lock_byte_drift_rejected', 'test_actual_license_loss_rejected',
    'test_unlisted_source_and_generated_symlink_rejected', 'test_recomputed_current_manifest_cannot_replace_original_export',
    'test_actual_volume_alias_and_noncanonical_source_path_rejected', 'test_real_source_manifest_metadata_tamper_rejected',
    'test_actual_unreviewed_empty_source_directory_rejected',
)

if __name__=='__main__':
    with tempfile.TemporaryDirectory(prefix='collect-original-guard-',dir='/private/tmp') as tmp:
        O.FIXTURES=Path(tmp);O.guards=G
        # Original test methods and helpers are loaded unchanged from the sealed file.
        suite=unittest.TestSuite([*(O.Preparation(name) for name in ORIGINAL_AFFECTED),
            unittest.defaultTestLoader.loadTestsFromTestCase(RegistrantGuardTests),
            unittest.defaultTestLoader.loadTestsFromTestCase(ControllerWiringTests)])
        result=unittest.TextTestRunner(verbosity=2).run(suite)
        receipt=dict(tests=result.testsRun,affected_original_cases=list(ORIGINAL_AFFECTED),focused_cases=30,
                     failures=len(result.failures),errors=len(result.errors),skips=len(result.skipped),
                     fixture_parent='/private/tmp',no_Flutter_Gradle_or_stage_execution=True,
                     original31_test_source_sha256=digest(ORIGINAL/'test_preparation.py'),original31_ASTs_preserved=True)
        with (HERE/'tests-result.json').open('x') as out:json.dump(receipt,out,indent=2,sort_keys=True);out.write('\n')
        raise SystemExit(0 if result.wasSuccessful() and not result.skipped and result.testsRun==37 else 1)
