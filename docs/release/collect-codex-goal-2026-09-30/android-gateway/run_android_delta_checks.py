#!/usr/bin/env python3
"""Recompile only changed native sources against the retained passing API compile.

Checks every unchanged source hash; this is type compilation, not APK packaging.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from run_native_checks import ROOT, JBR, digest

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base',required=True,type=Path)
    parser.add_argument('--packet',required=True,type=Path)
    args=parser.parse_args();base=args.base.resolve();packet=args.packet.resolve();packet.mkdir(parents=True,exist_ok=False)
    prior=json.loads((base/'validation.json').read_text())
    if prior['status']!='pass':raise SystemExit('Base API compile did not pass')
    cmd=prior['command'];base_classes=Path(cmd[cmd.index('-d')+1])
    if not base_classes.is_dir():raise SystemExit('Retained base classes unavailable')
    source_hashes=prior['source_sha256'];current={path:digest(ROOT/path) for path in source_hashes}
    changed=[path for path in source_hashes if current[path]!=source_hashes[path]]
    if not changed:raise SystemExit('No changed sources to compile')
    for path in changed:
        target=packet/'source'/path;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/path,target)
        assert digest(target)==current[path]
    for path,expected in prior['dependencies_sha256'].items():
        if digest(Path(path))!=expected:raise SystemExit('Pinned API dependency changed')
    classes=Path(tempfile.mkdtemp(prefix='collect-gateway-api-delta-'))
    compiler_cp=cmd[cmd.index('-cp')+1]
    source_cp=cmd[cmd.index('-classpath')+1]+os.pathsep+str(base_classes)
    argv=[str(JBR/'bin/java'),'-Xms64m','-Xmx1g','-XX:ReservedCodeCacheSize=128m','-XX:ActiveProcessorCount=2',
          '-cp',compiler_cp,'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17',
          '-classpath',source_cp,'-Xfriend-paths='+str(base_classes),'-d',str(classes),
          *[str(packet/'source'/path) for path in changed]]
    try:result=subprocess.run(argv,capture_output=True,timeout=300)
    except subprocess.TimeoutExpired as error:result=subprocess.CompletedProcess(argv,124,error.stdout or b'',(error.stderr or b'')+b'\nBounded delta compiler timeout.\n')
    (packet/'compile.stdout').write_bytes(result.stdout);(packet/'compile.stderr').write_bytes(result.stderr)
    drift=[path for path,expected in current.items() if digest(ROOT/path)!=expected]
    report={'status':'pass' if not result.returncode and not drift else 'fail','command':argv,'exit_code':result.returncode,
            'base_report':str(base/'validation.json'),'base_report_sha256':digest(base/'validation.json'),
            'source_sha256':current,'changed_paths':changed,'unchanged_verified_count':len(current)-len(changed),
            'source_changes':drift,'dependencies_sha256':prior['dependencies_sha256'],
            'scope':'Current changed native sources compiled against retained passing Android36/Flutter API classes; every unchanged source and API dependency hash verified. Same explicit base BuildConfig stub. Not a clean full rebuild, APK, device, gateway key, carrier or production acceptance.'}
    (packet/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'exit_code':result.returncode,'changed_paths':changed,'source_changes':drift}))
    raise SystemExit(0 if report['status']=='pass' else 1)

if __name__=='__main__':main()
