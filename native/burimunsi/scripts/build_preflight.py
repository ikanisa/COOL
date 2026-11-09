#!/usr/bin/env python3
"""Read-only local build prerequisites. Never accepts SDK licences, downloads or builds."""
import argparse,json,os,pathlib,shutil,subprocess,sys,zipfile
from bootstrap_gradle import VERSION,SHA256,install

def inspect(sdk=None):
 checks=[]
 def add(name,ok,detail):checks.append({'name':name,'ok':bool(ok),'detail':detail})
 java=pathlib.Path(os.environ['JAVA_HOME'])/'bin/java' if os.environ.get('JAVA_HOME') else shutil.which('java')
 try:
  r=subprocess.run([str(java),'-version'],text=True,capture_output=True,timeout=10)
  import re
  version=re.search(r'version "(\d+)',r.stderr+r.stdout)
  add('java',r.returncode==0 and version and int(version[1]) == 17,'Run with JDK 17: core explicitly requests jvmToolchain(17); JDK 21 alone is insufficient.')
 except (OSError,subprocess.SubprocessError):add('java',False,'Java launcher unavailable.')
 sdk=pathlib.Path(sdk or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or '/__missing_android_sdk__')
 add('android_platform_36',(sdk/'platforms/android-36/android.jar').is_file(),'Android SDK platform 36 required.')
 for tool in ('aapt2','apksigner','zipalign'):
  add('build_tools_'+tool,(sdk/'build-tools/36.0.0'/tool).is_file(),'Android build-tools 36.0.0 required.')
 add('platform_tools',(sdk/'platform-tools/adb').is_file(),'adb required for installation/device evidence.')
 add('sdkmanager',any(sdk.glob('cmdline-tools/*/bin/sdkmanager')),'Existing licensed Android command-line tools required for package inventory/setup.')
 add('apkanalyzer',any(sdk.glob('cmdline-tools/*/bin/apkanalyzer')),'Android command-line tools required for artifact boundary checks.')
 cache=pathlib.Path(os.environ.get('BURI_GRADLE_CACHE',str(pathlib.Path.home()/'.cache/burimunsi/gradle')))
 archive=pathlib.Path(os.environ.get('BURI_GRADLE_ARCHIVE',str(cache/f'gradle-{VERSION}-bin.zip')))
 # Do not install even from a local archive in a read-only preflight.
 from bootstrap_gradle import checked_entries,verify_tree
 try:
  entries=checked_entries(archive);verify_tree(archive,cache,entries);add('gradle',True,'Verified Gradle '+VERSION+' distribution and extracted bytes.')
 except (OSError,ValueError,zipfile.BadZipFile):add('gradle',False,'Bootstrap the checksum-pinned Gradle '+VERSION+' distribution.')
 return {'ready_for_build':all(c['ok'] for c in checks),'checks':checks,'gradle_sha256':SHA256,'sdk_licences_accepted':None,'native_build_executed':False,'scope':'Local prerequisites only; dependency resolution, compilation and device qualification are separate.'}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--sdk');p.add_argument('--output',type=pathlib.Path);a=p.parse_args();report=inspect(a.sdk);text=json.dumps(report,indent=2)
 if a.output:a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(text+'\n')
 print(text);sys.exit(0 if report['ready_for_build'] else 2)
