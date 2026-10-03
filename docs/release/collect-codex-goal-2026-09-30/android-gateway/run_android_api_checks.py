#!/usr/bin/env python3
"""Compile actual gateway Kotlin against cached Android36/Flutter APIs offline.

BuildConfig is a clearly labeled flavor stub. This is no APK/handset acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from run_native_checks import ROOT, JBR, jar, digest

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet',required=True,type=Path)
    args=parser.parse_args()
    packet=args.packet.resolve(); packet.mkdir(parents=True,exist_ok=False)
    paths=sorted((ROOT/'android/app/src/main/kotlin/app/cool/mobile/gateway').glob('*.kt'))
    hashes={str(p.relative_to(ROOT)):digest(p) for p in paths}
    for path in paths:
        target=packet/'source'/path.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(path,target);assert digest(target)==hashes[str(path.relative_to(ROOT))]
    stub=packet/'BuildConfig.kt'
    stub.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
    deps=[jar('org.jetbrains.kotlin','kotlin-compiler-embeddable','2.3.20'),
          jar('org.jetbrains.kotlin','kotlin-stdlib','2.3.20'),
          jar('org.jetbrains.kotlin','kotlin-script-runtime','2.3.20'),
          jar('org.jetbrains.kotlin','kotlin-reflect','1.6.10'),
          jar('org.jetbrains','annotations','13.0'),
          jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.8.1'),
          jar('androidx.annotation','annotation-jvm','1.8.1'),
          jar('androidx.lifecycle','lifecycle-common','2.7.0'),
          jar('io.flutter','flutter_embedding_debug','1.0.0-a10d8ac38de835021c8d2f920dbf50a920ccc030'),
          Path.home()/'Library/Android/sdk/platforms/android-36/android.jar']
    classes=Path(tempfile.mkdtemp(prefix='collect-gateway-api-'))
    cp=os.pathsep.join(str(p) for p in deps)
    source_cp=os.pathsep.join(str(deps[index]) for index in (1,4,6,7,8,9))
    argv=[str(JBR/'bin/java'),'-Xms64m','-Xmx1g','-XX:ReservedCodeCacheSize=128m','-XX:ActiveProcessorCount=2','-cp',cp,
          'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17','-classpath',source_cp,'-d',str(classes),
          *[str(packet/'source'/p.relative_to(ROOT)) for p in paths],str(stub)]
    try: result=subprocess.run(argv,capture_output=True,timeout=360)
    except subprocess.TimeoutExpired as error: result=subprocess.CompletedProcess(argv,124,error.stdout or b'',(error.stderr or b'')+b'\nBounded compiler timeout.\n')
    (packet/'compile.stdout').write_bytes(result.stdout);(packet/'compile.stderr').write_bytes(result.stderr)
    drift=[str(p.relative_to(ROOT)) for p in paths if digest(p)!=hashes[str(p.relative_to(ROOT))]]
    report={'status':'pass' if not result.returncode and not drift else 'fail','command':argv,'exit_code':result.returncode,
            'source_sha256':hashes,'source_changes':drift,'dependencies_sha256':{str(p):digest(p) for p in deps},
            'buildconfig_stub_sha256':digest(stub),'scope':'Actual gateway Kotlin compile against Android36/Flutter same cached engine API. BuildConfig flavor stub only; no APK, Android execution, enrolled identity, endpoint, carrier or production proof.'}
    (packet/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'exit_code':result.returncode,'source_changes':drift}))
    raise SystemExit(0 if report['status']=='pass' else 1)

if __name__=='__main__': main()
