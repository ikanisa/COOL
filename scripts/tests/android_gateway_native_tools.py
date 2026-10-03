#!/usr/bin/env python3
"""Pinned, offline tools and finite current Android gateway source closure.

Release evidence helpers are immutable historical inputs. This live helper never
fetches dependencies, mutates SDK/cache files or contacts a device/provider.
"""
import hashlib
import json
from pathlib import Path

CACHE = Path.home() / '.gradle/caches/modules-2/files-2.1'
JBR = Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home')
ANDROID_API = Path('/Users/jeanbosco/Library/Android/sdk/platforms/android-36/android.jar')
FLUTTER_ENGINE = Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/internal/engine.version')
BASE = Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway')
TEST_DIRS = (Path('android/app/src/testInternal_gateway/kotlin/app/cool/mobile/gateway'),
             Path('android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway'))
DEPENDENCIES = (
 ('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.3.20'),
 ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.3.20'),
 ('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.3.20'),
 ('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
 ('org.jetbrains', 'annotations', '13.0'),
 ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.1'),
 ('junit', 'junit', '4.13.2'), ('org.hamcrest', 'hamcrest-core', '1.3'),
 ('org.json', 'json', '20250517'),
)
PRODUCT_NAMES = ('GatewayJournal', 'GatewayJournalArchive', 'GatewayEncryptedStore', 'GatewayCrypto', 'GatewayAttemptArchive', 'GatewayAttemptArchiveWire', 'GatewayDispatch', 'GatewayDispatchWire', 'GatewayBackgroundCoordinator', 'GatewayInstalledEnrollment', 'GatewayWire', 'GatewayTransport', 'GatewayRadioObservation', 'GatewayDeviceIdentity', 'GatewaySignedBackend', 'GatewayRetentionIndex', 'GatewayLateRetention', 'GatewayRecovery', 'GatewayRecoveryTransfer', 'GatewayRecoveryPause', 'GatewayRecoveryAdmission', 'GatewayDispatchRoute', 'GatewaySuccessorWire')
API_NAMES = ('GatewayActivity', 'GatewayAndroidObservations', 'GatewayAndroidRuntime', 'GatewayAttemptArchive', 'GatewayAttemptArchiveWire', 'GatewayBackgroundCoordinator', 'GatewayBackgroundService', 'GatewayBridge', 'GatewayCrypto', 'GatewayDeviceIdentity', 'GatewayDispatch', 'GatewayDispatchRoute', 'GatewayDispatchWire', 'GatewayEncryptedStore', 'GatewayInstalledEnrollment', 'GatewayJournal', 'GatewayJournalArchive', 'GatewayLateRetention', 'GatewayRadioObservation', 'GatewayRecovery', 'GatewayRecoveryAdmission', 'GatewayRecoveryOperator', 'GatewayRecoveryPause', 'GatewayRecoveryTransfer', 'GatewayRetentionIndex', 'GatewaySignedBackend', 'GatewaySmsCallbackReceiver', 'GatewaySmsInvoker', 'GatewaySuccessorWire', 'GatewayTransport', 'GatewayWire')
FIXTURE_SHA256 = {'observed-successor-grant.json': '93f338c820962065fef0d6a471ebb90a853c9889f072dad79f7dabb7264974f7', 'observed-successor-arm.json': '4c8d914824ad403986114fc2bae8317c08ab8ae301c5a52a8ca6b1d500c96c23', 'observed-multipart-callbacks.json': 'a303622a3def0763da094074469d8d340c14ab49f51cdbecaec0d76c822ffd13', 'observed-exact-successor-archive-ack.json': '2e63c7feceaf45b0f116079ff0faf86bbaf9a7bea18952036c71d20dddd134ac', 'observed-late-original-request-recovery.json': '496b1138b44f808e624fe2e7eb5229e6aa9d9f516633224607e124ee7742fbbf', 'observed-late-conflicting-status.json': '2a81608ef03e1742177b36e57dcd68a4caf125c00dad910b57aa346c3c570dde'}
PRODUCER_RESULT_SHA256 = '80c46483108f830e7078cf3af06f54a94b806c9fea7756f0d89b375451b1be2b'
PRODUCER_MANIFEST_SHA256 = 'b6f2e1f2c08d7cd3af071c85c8b1e5543b2cae2153ad24867a6d75b498a51885'

SHIMS = {
    'Build.kt': '''package android.os
object Build { object VERSION { const val SDK_INT = 36 } }
''',
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
object AtomicFileFaults { var failFinishOnce = false; var failFileOnce: String? = null; var writeCount = 0; var failWriteNumberOnce: Int? = null }
class AtomicFile(val baseFile: File) {
 private val stage get() = File(baseFile.path + ".new")
 fun openRead(): FileInputStream {
  val backup = File(baseFile.path + ".bak")
  if (backup.exists()) Files.move(backup.toPath(), baseFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
  return FileInputStream(baseFile)
 }
 fun startWrite(): FileOutputStream = FileOutputStream(stage)
 fun finishWrite(stream: FileOutputStream) {
  AtomicFileFaults.writeCount++; if (AtomicFileFaults.failFinishOnce || AtomicFileFaults.failFileOnce == baseFile.name || AtomicFileFaults.failWriteNumberOnce == AtomicFileFaults.writeCount) { AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failWriteNumberOnce = null; AtomicFileFaults.failFinishOnce = false; throw java.io.IOException("Synthetic atomic finish failure") }
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
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def jar(group, name, version):
    found = sorted((CACHE / group / name / version).glob('*/*.jar'))
    if len(found) != 1:
        raise RuntimeError(f'Pinned cached dependency unavailable or ambiguous: {name} {version}')
    return found[0]


def api_sources(root):
    observed = {path.stem for path in (root / BASE).glob('*.kt')}
    if observed != set(API_NAMES):
        raise RuntimeError('Gateway API source closure changed: missing=' + str(sorted(set(API_NAMES)-observed)) +
                           ', extra=' + str(sorted(observed-set(API_NAMES))))
    return [BASE / (name + '.kt') for name in API_NAMES]


def product_sources(root):
    api_sources(root)
    return [BASE / (name + '.kt') for name in PRODUCT_NAMES]


def test_sources(root, suites):
    if len(suites) != len(set(suites)):
        raise RuntimeError('Duplicate native suite selection')
    paths = []
    for name in suites:
        found = [directory / (name + '.kt') for directory in TEST_DIRS if (root / directory / (name + '.kt')).is_file()]
        if len(found) != 1:
            raise RuntimeError('Missing or ambiguous native test: ' + name)
        paths.extend(found)
    return paths


def fixture_sources(directory):
    observed = {path.name for path in directory.iterdir() if path.is_file()}
    if observed != set(FIXTURE_SHA256) | {'producer-association.json'}:
        raise RuntimeError('Exact six successor fixtures and producer association required')
    association = json.loads((directory / 'producer-association.json').read_text())
    if association != {'producer_result_sha256': PRODUCER_RESULT_SHA256,
                        'producer_manifest_sha256': PRODUCER_MANIFEST_SHA256,
                        'fixtures': FIXTURE_SHA256}:
        raise RuntimeError('Successor producer association mismatch')
    for name, expected in FIXTURE_SHA256.items():
        if digest(directory / name) != expected:
            raise RuntimeError('Successor fixture bytes changed: ' + name)
    return [directory / name for name in (*FIXTURE_SHA256, 'producer-association.json')]
