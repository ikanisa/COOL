#!/usr/bin/env python3
"""Check local build prerequisites without modifying or installing tools."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

from bootstrap_gradle import SHA256, VERSION, checked_entries, verify_tree
from native_pipeline_io import PipelineError, sdk_tool


def has_jdk17():
    java_home = os.environ.get('JAVA_HOME')
    tools = (
        ('java', r'version "17(?:[.\-"]|$)'),
        ('javac', r'(?m)^\s*javac 17(?:[.\-\s]|$)'),
    )
    for name, version in tools:
        executable = str(Path(java_home) / 'bin' / name) if java_home else shutil.which(name)
        if executable is None:
            return False
        try:
            result = subprocess.run([executable, '-version'], text=True, capture_output=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return False
        if result.returncode != 0 or not re.search(version, result.stderr + result.stdout):
            return False
    return True


def inspect(sdk=None):
    checks = []

    def add(name, ok, detail):
        checks.append({'name': name, 'ok': bool(ok), 'detail': detail})

    add('java', has_jdk17(), 'JDK 17 is required. Both java and javac must report version 17.')
    sdk = Path(sdk or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or '/__missing_android_sdk__')
    add('android_platform_36', (sdk / 'platforms/android-36/android.jar').is_file(), 'Android SDK platform 36 required.')
    tools = (
        ('build_tools_aapt2', 'aapt2', 'Android build-tools 36.0.0 required.'),
        ('build_tools_apksigner', 'apksigner', 'Android build-tools 36.0.0 required.'),
        ('build_tools_zipalign', 'zipalign', 'Android build-tools 36.0.0 required.'),
        ('platform_tools', 'adb', 'adb required for installation and device evidence.'),
        ('sdkmanager', 'sdkmanager', 'Android command-line tools required for package inventory and setup.'),
        ('apkanalyzer', 'apkanalyzer', 'Android command-line tools required for APK boundary checks.'),
    )
    for name, executable, detail in tools:
        try:
            sdk_tool(sdk, executable)
        except PipelineError:
            add(name, False, detail)
        else:
            add(name, True, detail)

    cache = Path(os.environ.get('BURI_GRADLE_CACHE', str(Path.home() / '.cache/burimunsi/gradle')))
    archive = Path(os.environ.get('BURI_GRADLE_ARCHIVE', str(cache / f'gradle-{VERSION}-bin.zip')))
    try:
        entries = checked_entries(archive)
        verify_tree(archive, cache, entries)
    except (OSError, ValueError, zipfile.BadZipFile):
        add('gradle', False, f'Bootstrap the checksum-pinned Gradle {VERSION} distribution.')
    else:
        add('gradle', True, f'Verified Gradle {VERSION} distribution and extracted bytes.')

    return {
        'ready_for_build': all(check['ok'] for check in checks),
        'checks': checks,
        'gradle_sha256': SHA256,
        'sdk_licences_accepted': None,
        'native_build_executed': False,
        'scope': 'Local prerequisites only. Build and device verification have separate results.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = inspect(args.sdk)
    text = json.dumps(report, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + '\n')
    print(text)
    return 0 if report['ready_for_build'] else 2


if __name__ == '__main__':
    sys.exit(main())
