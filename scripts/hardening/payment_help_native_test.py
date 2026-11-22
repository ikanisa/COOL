#!/usr/bin/env python3
"""Focused host-native store proof, without Gradle/Xcode app builds or keychain writes.

Executes the actual protected store/cipher with controlled keys. Android's
AtomicFile is a small host adapter, so Android platform durability/KeyStore and
Flutter channel wiring remain separate app/device integration obligations.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--android-jar', type=Path, default=Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk')) / 'platforms/android-36/android.jar')
    parser.add_argument('--gradle-cache', type=Path, default=Path.home() / '.gradle/caches/modules-2/files-2.1')
    args = parser.parse_args()
    evidence = args.evidence_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    prefix = 'next-payment-help-native-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    android = ROOT / 'android/app/src/main/kotlin/app/cool/mobile'
    ios = ROOT / 'ios/Runner'
    kotlin_store = android / 'security/ProtectedSnapshotStore.kt'
    kotlin_cipher = android / 'security/SnapshotCipher.kt'
    kotlin_test = ROOT / 'scripts/hardening/PaymentHelpProtectedStoreTest.kt'
    swift_store = ios / 'CollectProtectedSnapshotStore.swift'
    swift_test = ROOT / 'scripts/hardening/PaymentHelpProtectedStoreTest.swift'
    swift_bridges = [ios / 'AppDelegate.swift', ios / 'MemberProtectedChannels.swift']
    sources = [
        android / 'MainActivity.kt',
        android / 'MemberProtectedChannels.kt',
        kotlin_store,
        kotlin_cipher,
        kotlin_test,
        *swift_bridges,
        swift_store,
        swift_test,
        Path(__file__).resolve(),
    ]
    source_hashes = {str(p.relative_to(ROOT)): sha(p) for p in sources}
    (evidence / (prefix + '-sources.json')).write_text(json.dumps(source_hashes, indent=2) + '\n')

    def jar(group, name, version):
        paths = list((args.gradle_cache / group / name / version).glob('*/' + name + '-' + version + '.jar'))
        if len(paths) != 1:
            raise RuntimeError('One cached dependency required: ' + name + ' ' + version)
        return paths[0]

    compiler = [jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.20'),
                jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.20'),
                jar('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
                jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0'),
                jar('org.jetbrains', 'annotations', '13.0')]
    classpath = [compiler[1], compiler[-1], args.android_jar.resolve()]
    tool_hashes = {str(p): sha(p) for p in set(compiler + classpath)}
    result = {'status': 'running', 'source_manifest': prefix + '-sources.json', 'source_inputs': source_hashes,
              'dependency_sha256': tool_hashes, 'commands': [], 'limitations': __doc__}
    log_path = evidence / (prefix + '.log')
    result_path = evidence / (prefix + '-result.json')
    with tempfile.TemporaryDirectory(prefix='collect-payment-help-native-') as work, log_path.open('x') as log:
        work = Path(work)
        classes = work / 'classes'
        classes.mkdir()
        # This adapter replaces only the unavailable Android platform primitive.
        # Real file I/O and fsync are used; its failure hook tests the production
        # store's failWrite branch, not Android AtomicFile implementation itself.
        atomic = work / 'AtomicFileHost.kt'
        atomic.write_text('''package android.util
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
class AtomicFile(val baseFile:File) {
 companion object { var failNextFinish=false }
 fun openRead():FileInputStream=baseFile.inputStream()
 fun startWrite():FileOutputStream=File(baseFile.path+".new").outputStream()
 fun finishWrite(stream:FileOutputStream) {
  stream.flush();stream.fd.sync();stream.close()
  if(failNextFinish){failNextFinish=false;error("Controlled atomic replacement failure")}
  Files.move(File(baseFile.path+".new").toPath(),baseFile.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)
 }
 fun failWrite(stream:FileOutputStream) { runCatching{stream.close()};File(baseFile.path+".new").delete() }
}
''')
        result['atomic_file_host_adapter_sha256'] = sha(atomic)

        def run(command):
            result['commands'].append(command)
            log.write('\nCOMMAND ' + json.dumps(command) + '\n')
            log.flush()
            process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            if process.returncode:
                raise RuntimeError('Command failed with exit ' + str(process.returncode))

        try:
            java = shutil.which('java')
            swift = shutil.which('swiftc')
            if not java or not swift:
                raise RuntimeError('Cached JVM and Swift compiler required')
            result['java_sha256'] = sha(Path(java).resolve())
            run([java, '-cp', ':'.join(map(str, compiler)), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                 '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', ':'.join(map(str, classpath)),
                 '-d', str(classes), str(kotlin_store), str(kotlin_cipher), str(kotlin_test), str(atomic)])
            run([java, '-cp', ':'.join(map(str, [classes] + classpath)), 'PaymentHelpProtectedStoreTestKt'])
            swift_main = work / 'main.swift'
            shutil.copyfile(swift_test, swift_main)
            result['executed_swift_source_sha256'] = sha(swift_store)
            run([swift, str(swift_store), str(swift_main), '-o', str(work / 'swift-store-tests')])
            run([str(work / 'swift-store-tests')])
            run([swift, '-frontend', '-parse', *map(str, swift_bridges)])
            result['status'] = 'passed'
        except Exception as failure:
            result['status'] = 'failed'
            result['failure'] = str(failure)
        finally:
            result['post_run_source_mismatches'] = [str(p.relative_to(ROOT)) for p in sources if sha(p) != source_hashes[str(p.relative_to(ROOT))]]
            if result['post_run_source_mismatches']:
                result['status'] = 'source_changed'
            result['log'] = log_path.name
            result_path.write_text(json.dumps(result, indent=2) + '\n')
    print(result_path)
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
