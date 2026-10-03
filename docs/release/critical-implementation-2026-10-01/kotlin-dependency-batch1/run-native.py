#!/usr/bin/env python3
"""Run fixed, unsigned native checks against the isolated reviewed source copy."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

PACKET = Path(__file__).resolve().parent
ROOT = PACKET.parents[3]
WORK = ROOT / '.cache/kotlin-dependency-batch1/native-source'
GRADLE_HOME = ROOT / '.cache/kotlin-dependency-batch1/gradle-home'
JDK = Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home')
SDK = Path.home() / 'Library/Android/sdk'
TASKS = {
    'sdk-runtime': ['-I', str(PACKET / 'observe-sdk-runtime.init.gradle'), ':gradle:collectSdkRuntimeGraph'],
    'resolve-compile': [':app:dependencies', '--configuration', 'productionReleaseCompileClasspath', '--write-locks'],
    'resolve-runtime': [':app:dependencies', '--configuration', 'productionReleaseRuntimeClasspath', '--write-locks'],
    'compile': [':file_saver:compileReleaseKotlin', ':app:compileProductionReleaseKotlin'],
    'unit': [':app:testProductionDebugUnitTest'],
    'graph-compile': ['-I', str(ROOT / 'scripts/supply_chain/gradle_runtime_inventory.init.gradle'),
                      '-PcollectInventoryConfiguration=productionReleaseCompileClasspath', ':app:collectRuntimeGraph'],
    'graph-runtime': ['-I', str(ROOT / 'scripts/supply_chain/gradle_runtime_inventory.init.gradle'),
                      '-PcollectInventoryConfiguration=productionReleaseRuntimeClasspath', ':app:collectRuntimeGraph'],
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('check', choices=TASKS)
    parser.add_argument('--attempt', type=int, required=True)
    args = parser.parse_args()
    assert args.attempt > 0 and WORK.is_dir() and (JDK / 'bin/java').is_file()
    assert not (WORK / 'android/key.properties').exists()
    assert not list((WORK / 'android').rglob('*.jks'))
    assert not list((WORK / 'android').rglob('*.keystore'))
    argv = ['bash', str(WORK / 'android/gradlew'), '-p', str(WORK / 'android'),
            '--no-daemon', '--no-build-cache', '--console=plain', '--max-workers=2',
            '-I', str(PACKET / 'observe-kotlin.init.gradle'), '-PcollectUnsignedLocalQa=true', *TASKS[args.check]]
    env = {key: os.environ[key] for key in ['PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL'] if key in os.environ}
    env.update(JAVA_HOME=str(JDK), ANDROID_HOME=str(SDK), ANDROID_SDK_ROOT=str(SDK),
               GRADLE_USER_HOME=str(GRADLE_HOME), FLUTTER_SUPPRESS_ANALYTICS='true')
    name = f'{args.check}-attempt{args.attempt}'
    log = PACKET / (name + '.log')
    assert not log.exists(), 'Retain each attempt rather than overwriting it'
    started_utc = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()
    runner_sha256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    code, timed_out = None, False
    with log.open('xb') as out:
        try:
            result = subprocess.run(argv, env=env, cwd=WORK, stdout=out, stderr=subprocess.STDOUT, timeout=2700)
            code = result.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
    document = {'argv': argv, 'exit_code': code, 'timed_out': timed_out,
                'started_utc': started_utc, 'finished_utc': datetime.now(timezone.utc).isoformat(),
                'configured_timeout_seconds': 2700,
                'process_only_analytics_suppression': {'FLUTTER_SUPPRESS_ANALYTICS': 'true'},
                'elapsed_seconds': round(time.monotonic() - start, 2),
                'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
                'runner_sha256': runner_sha256,
                'scope': 'Task-local Gradle cache and copied source; unsigned source checks only. No credentials, signing keystore, provider operation, installation, deployment or production approval.'}
    (PACKET / (name + '.json')).write_text(json.dumps(document, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'check': args.check, 'exit_code': code, 'timed_out': timed_out}))
    raise SystemExit(code if code is not None else 1)

if __name__ == '__main__':
    main()
