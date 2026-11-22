#!/usr/bin/env python3
"""Explicitly obtain pinned Gradle/SDK packages using an owner-provided SDK manager.

Default: print a plan. --execute permits downloads and installation, not licence
acceptance. The owner must install JDK 17 and Android command-line tools first.
No system package manager, root access or production credentials are used.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from native_pipeline import PipelineError, ROOT, command, fresh_dir, now, sdk_path, sdk_tool, write_json

PACKAGES = ('platforms;android-36', 'build-tools;36.0.0', 'platform-tools')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if not args.execute:
        print(json.dumps({'mode': 'plan', 'gradle': '9.1.0', 'packages': PACKAGES,
                          'java_required': 17, 'requires_existing_sdkmanager': True,
                          'accept_licences': False, 'executed': False}, indent=2))
        return 0
    out = fresh_dir(args.output)
    result = {'status': 'BLOCKED', 'started_at': now(), 'licences_accepted_by_script': False,
              'native_build_executed': False, 'packages': PACKAGES}
    try:
        sdk = sdk_path(args.sdk)
        manager = sdk_tool(sdk, 'sdkmanager')
        # No "yes | sdkmanager --licenses". Closed stdin prevents unattended consent.
        cmd = [str(manager), '--sdk_root=' + str(sdk), *PACKAGES]
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=900, check=False)
        text = p.stdout.decode('utf-8', errors='replace')
        (out / 'sdk-install.log').write_text(text)
        if p.returncode or 'not accepted' in text.lower() or 'licenses have not been accepted' in text.lower():
            raise PipelineError('SDK installation failed or needs owner licence acceptance; see sdk-install.log')
        command([sys.executable, str(ROOT / 'scripts/bootstrap_gradle.py'), '--download'], out / 'gradle-bootstrap.log', timeout=300)
        command([str(manager), '--sdk_root=' + str(sdk), '--list_installed'], out / 'sdk-packages.txt')
        command([sys.executable, str(ROOT / 'scripts/build_preflight.py'), '--sdk', str(sdk),
                 '--output', str(out / 'preflight.json')], out / 'preflight.log')
        result['status'] = 'PASS'
    except (PipelineError, OSError, ValueError, subprocess.SubprocessError) as error:
        result['error'] = str(error)
    finally:
        result['finished_at'] = now()
        write_json(out / 'toolchain-result.json', result)
        print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'PASS' else 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (PipelineError, OSError, ValueError) as error:
        print(json.dumps({'status': 'BLOCKED', 'error': str(error)}), file=sys.stderr)
        sys.exit(2)
