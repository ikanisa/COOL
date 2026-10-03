#!/usr/bin/env python3
"""Offline dispatch/arm/archive/storage checks: retained source, synthetic AES, no Android device/network."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELPER = Path('scripts/tests/android_gateway_native_tools.py')
ANDROID_API = Path('/Users/jeanbosco/Library/Android/sdk/platforms/android-36/android.jar')
SHIMS = {
    'Context.kt': '''package android.content
import java.io.File
abstract class Context {
 abstract val noBackupFilesDir: File
 open val resources = android.content.res.Resources()
 open val packageName = "app.cool.mobile"
 open fun getString(id: Int) = "lhbowpbcpwoiparwnwgt.supabase.co"
}
''',
    'Resources.kt': '''package android.content.res
class Resources { fun getIdentifier(name: String, kind: String, packageName: String) = 1 }
''',
    'Keystore.kt': '''package android.security.keystore
import java.security.spec.AlgorithmParameterSpec
class KeyGenParameterSpec : AlgorithmParameterSpec {
 class Builder(alias: String, purposes: Int) {
  fun setBlockModes(vararg modes: String) = this
  fun setEncryptionPaddings(vararg values: String) = this
  fun setKeySize(size: Int) = this
  fun setUserAuthenticationRequired(value: Boolean) = this
  fun setAlgorithmParameterSpec(value: AlgorithmParameterSpec) = this
  fun setDigests(vararg values: String) = this
  fun build() = KeyGenParameterSpec()
 }
}
object KeyProperties {
 const val KEY_ALGORITHM_AES = "AES"
 const val KEY_ALGORITHM_EC = "EC"
 const val PURPOSE_ENCRYPT = 1
 const val PURPOSE_DECRYPT = 2
 const val PURPOSE_SIGN = 4
 const val PURPOSE_VERIFY = 8
 const val DIGEST_SHA256 = "SHA-256"
 const val BLOCK_MODE_GCM = "GCM"
 const val ENCRYPTION_PADDING_NONE = "NoPadding"
}
''',
    'AtomicFile.kt': '''package android.util
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
object AtomicFileFaults { var failFinishOnce = false }
class AtomicFile(val baseFile: File) {
 private val stage get() = File(baseFile.path + ".new")
 fun openRead(): FileInputStream {
  val backup = File(baseFile.path + ".bak")
  if (backup.exists()) Files.move(backup.toPath(), baseFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
  return FileInputStream(baseFile)
 }
 fun startWrite(): FileOutputStream = FileOutputStream(stage)
 fun finishWrite(stream: FileOutputStream) {
  if (AtomicFileFaults.failFinishOnce) { AtomicFileFaults.failFinishOnce = false; throw java.io.IOException("Synthetic atomic finish failure") }
  stream.fd.sync(); stream.close()
  Files.move(stage.toPath(), baseFile.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
 }
 fun failWrite(stream: FileOutputStream) { try { stream.close() } finally { stage.delete() } }
}
object Base64 {
 const val NO_WRAP = 2
 fun decode(value: String, flags: Int): ByteArray = java.util.Base64.getDecoder().decode(value)
 fun encodeToString(value: ByteArray, flags: Int): String = java.util.Base64.getEncoder().encodeToString(value)
}
''',
    'Os.kt': '''package android.system
import java.io.FileDescriptor
import java.nio.channels.FileChannel
import java.nio.file.Path
import java.nio.file.StandardOpenOption
object OsConstants { const val O_RDONLY = 0; const val O_DIRECTORY = 65536 }
object Os {
 private val files = java.util.IdentityHashMap<FileDescriptor, FileChannel>()
 fun open(path: String, flags: Int, mode: Int): FileDescriptor = synchronized(files) {
  val fd = FileDescriptor(); files[fd] = FileChannel.open(Path.of(path), StandardOpenOption.READ); fd
 }
 fun fsync(fd: FileDescriptor) { synchronized(files) { files.getValue(fd).force(true) } }
 fun close(fd: FileDescriptor) { synchronized(files) { files.remove(fd)?.close() } }
}
''',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', type=Path, required=True)
    args = parser.parse_args()
    packet = args.packet.resolve()
    packet.mkdir(parents=True, exist_ok=False)
    # Capture and verify the live helper before its first import.
    helper_target = packet / 'source' / HELPER
    helper_target.parent.mkdir(parents=True, exist_ok=True)
    helper_sha = digest(ROOT / HELPER)
    shutil.copyfile(ROOT / HELPER, helper_target)
    if digest(helper_target) != helper_sha:
        raise RuntimeError('Native helper changed during capture')
    spec = importlib.util.spec_from_file_location('gateway_native_helper', helper_target)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    SHIMS = helper.SHIMS
    suite_names = ['GatewayJournalArchiveTest', 'GatewayDispatchBackendIntegrationTest', 'GatewayArchiveStorageTest', 'GatewayArchiveBackendIntegrationTest', 'GatewaySafetyTest', 'GatewayDispatchWireTest', 'GatewayDispatchArmTest', 'GatewayWireTest', 'GatewayTransportTest', 'GatewayRadioObservationTest']
    sources = helper.product_sources(ROOT) + helper.test_sources(ROOT, suite_names)
    api_sources = helper.api_sources(ROOT)
    paths = list(dict.fromkeys(sources + api_sources + [HELPER, Path('android/app/src/internal_gateway/AndroidManifest.xml'), Path('android/app/src/main/AndroidManifest.xml'), Path('android/app/build.gradle.kts'), Path(__file__).resolve().relative_to(ROOT)]))
    hashes = {str(path): digest(ROOT / path) for path in paths}
    if hashes[str(HELPER)] != helper_sha:
        raise RuntimeError('Native helper changed after import')
    for path in paths:
        target = packet / 'source' / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / path, target)
        if digest(target) != hashes[str(path)]:
            raise RuntimeError('Captured source changed before execution')
    dependencies = [helper.jar(group, name, version) for group, name, version in (
        ('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.3.20'),
        ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.3.20'),
        ('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.3.20'),
        ('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
        ('org.jetbrains', 'annotations', '13.0'),
        ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.1'),
        ('junit', 'junit', '4.13.2'), ('org.hamcrest', 'hamcrest-core', '1.3'),
        ('org.json', 'json', '20250517'))]
    if not ANDROID_API.is_file():
        raise RuntimeError('Cached Android 36 API unavailable')
    flutter_engine = helper.FLUTTER_ENGINE
    engine = flutter_engine.read_text().strip()
    embedding = helper.jar('io.flutter', 'flutter_embedding_debug', '1.0.0-' + engine)
    lifecycle = helper.jar('androidx.lifecycle', 'lifecycle-common-jvm', '2.9.4')
    binary_inputs = dependencies + [ANDROID_API, helper.JBR / 'bin/java', embedding, lifecycle, flutter_engine]
    binary_hashes = {str(path): digest(path) for path in binary_inputs}
    compile_cp = os.pathsep.join(map(str, dependencies))
    source_cp = os.pathsep.join(str(dependencies[index]) for index in (1, 4, 6, 7, 8))
    commands = []
    for name, body in SHIMS.items():
        target = packet / 'shims' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body)

    def run(name, argv):
        try:
            result = subprocess.run(argv, capture_output=True, timeout=360)
        except subprocess.TimeoutExpired as error:
            result = subprocess.CompletedProcess(argv, 124, error.stdout or b'', (error.stderr or b'') + b'\nBounded offline command timeout.\n')
        (packet / (name + '.stdout')).write_bytes(result.stdout)
        (packet / (name + '.stderr')).write_bytes(result.stderr)
        commands.append({'name': name, 'argv': argv, 'exit_code': result.returncode,
                         'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()})
        return result.returncode

    with tempfile.TemporaryDirectory(prefix='collect-gateway-archive-jvm-') as temporary:
        classes = Path(temporary) / 'classes'
        classes.mkdir()
        compiler = [str(helper.JBR / 'bin/java'), '-Xms64m', '-Xmx1g', '-XX:ActiveProcessorCount=2', '-cp', compile_cp,
                    'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-jvm-target', '17']
        code = run('compile-shim', compiler + ['-classpath', source_cp, '-d', str(classes)] +
                   [str(packet / 'source' / path) for path in sources] + [str(path) for path in sorted((packet / 'shims').glob('*.kt'))])
        if not code:
            code = run('tests', [str(helper.JBR / 'bin/java'), '-ea', '-Xmx512m', '-cp', os.pathsep.join([str(classes), source_cp]),
                                'org.junit.runner.JUnitCore', 'app.cool.mobile.gateway.GatewayJournalArchiveTest',
                                'app.cool.mobile.gateway.GatewayDispatchBackendIntegrationTest', 'app.cool.mobile.gateway.GatewayArchiveStorageTest', 'app.cool.mobile.gateway.GatewayArchiveBackendIntegrationTest', 'app.cool.mobile.gateway.GatewaySafetyTest',
                                'app.cool.mobile.gateway.GatewayDispatchWireTest', 'app.cool.mobile.gateway.GatewayDispatchArmTest', 'app.cool.mobile.gateway.GatewayWireTest', 'app.cool.mobile.gateway.GatewayTransportTest',
                                'app.cool.mobile.gateway.GatewayRadioObservationTest'])
        api_classes = Path(temporary) / 'api-classes'
        api_classes.mkdir()
        api_cp = os.pathsep.join([str(ANDROID_API), str(embedding), str(lifecycle), source_cp])
        config = packet / 'api-generated' / 'BuildConfig.kt'
        config.parent.mkdir(exist_ok=True)
        config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
        api_code = run('compile-real-android-api', compiler + ['-classpath', api_cp, '-d', str(api_classes)] +
                       [str(packet / 'source' / path) for path in api_sources] + [str(config)])
    drift = [str(path) for path in paths if digest(ROOT / path) != hashes[str(path)]]
    binary_drift = [str(path) for path in binary_inputs if digest(path) != binary_hashes[str(path)]]
    result = {'status': 'pass' if not code and not api_code and not drift and not binary_drift else 'fail',
              'commands': commands, 'source_sha256': hashes, 'source_changes': drift, 'binary_sha256': binary_hashes,
              'binary_changes': binary_drift, 'shim_sha256': {name: digest(packet / 'shims' / name) for name in SHIMS},
              'scope': 'Actual native archive/journal/crypto/storage plus synthetic AES and narrow filesystem API shims; cached real Android API compilation. No Gradle/APK, Android Keystore/runtime/power-loss/device, authenticated hosted acknowledgement, SMS/network/provider/deployment acceptance.',
              'remaining_integration': ['Attempt compaction requires a future terminal-attempt server acknowledgement; current v1 callbacks/attempts remain active.',
                                        'Archive bound exhaustion preserves evidence and stops compaction; no archive export/pruning protocol exists.']}
    (packet / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'source_changes': drift, 'binary_changes': binary_drift}))
    raise SystemExit(0 if result['status'] == 'pass' else 1)


if __name__ == '__main__':
    main()
