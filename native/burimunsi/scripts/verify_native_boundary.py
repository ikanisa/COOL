#!/usr/bin/env python3
"""Source/merged-manifest/APK isolation gates. Does not fabricate a native build.
Source success is distinct from the mandatory post-build APK verification.
"""
import argparse, json, pathlib, re, subprocess, sys, zipfile
import xml.etree.ElementTree as ET
A='{http://schemas.android.com/apk/res/android}'
T='{http://schemas.android.com/tools}'
FORBIDDEN={'android.permission.READ_SMS','android.permission.RECEIVE_SMS','android.permission.SEND_SMS','android.permission.RECEIVE_MMS','android.permission.RECEIVE_WAP_PUSH','android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'}
SMS_NAMES=('receiver_sms','CollectSmsReceiver','MomoGatewayJob','MomoGatewayRecovery','MemberSmsJob','NotificationListenerService')
CONTINUOUS_PERMISSIONS={'android.permission.FOREGROUND_SERVICE','android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    'android.permission.POST_NOTIFICATIONS','android.permission.WAKE_LOCK','android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'}
CONTINUOUS_SERVICE='app.cool.mobile.receiver_sms.BuriContinuousSyncService'
CONTINUOUS_SUBTYPE='Internal receiving-phone SMS monitoring with local inbox observation and bounded authenticated synchronization, controlled by the current authorized administrator and a visible ongoing notification.'

def manifest_failures(xml,variant,*,release=False,qualification=False,native_test=False,strict_components=False):
 root=ET.fromstring(xml);app=root.find('application');errors=[]
 if app is None:return ['application missing']
 permissions={p.get(A+'name') for tag in ('uses-permission','uses-permission-sdk-23') for p in root.findall(tag) if p.get(T+'node')!='remove'}
 if variant=='staff':
  if permissions&FORBIDDEN:errors.append('Staff requests forbidden permissions: '+','.join(sorted(permissions&FORBIDDEN)))
  if permissions&CONTINUOUS_PERMISSIONS:errors.append('Staff requests receiver-only foreground/notification/power permissions')
  for tag in ('receiver','service','provider','activity'):
   for e in app.findall(tag):
    if any(n in e.get(A+'name','') for n in SMS_NAMES) or e.get(A+'permission')=='android.permission.BIND_NOTIFICATION_LISTENER_SERVICE':errors.append('Staff packages SMS/listener component')
 else:
  if not {'android.permission.READ_SMS','android.permission.RECEIVE_SMS'}<=permissions:errors.append('Receiver permissions missing')
  if 'android.permission.SEND_SMS' in permissions:errors.append('Unapproved outbound SMS permission')
  for rec in app.findall('receiver'):
   if rec.get(A+'name','').endswith(('CollectSmsReceiver','ObservationSmsReceiver')) and rec.get(A+'permission')!='android.permission.BROADCAST_SMS':errors.append('Incoming receiver missing system broadcast guard')
 if app.get(A+'usesCleartextTraffic')!='false':errors.append('Cleartext not explicitly disabled')
 if app.get(A+'allowBackup')!='false':errors.append('Application backup not explicitly disabled')
 if (release or qualification) and app.get(A+'debuggable','false')!='false':errors.append('Optimized artifact is debuggable')
 if release and app.get(A+'testOnly','false')!='false':errors.append('Production artifact must not be testOnly')
 if release:
  suffix='.staff.cloud' if variant=='staff' else '.gateway.cloud'
  if root.get('package')!='rw.ikanisa.burimunsi'+suffix:errors.append('Cloud release package identity mismatch')
 if root.get(A+'sharedUserId'):errors.append('App must not use a shared UID')
 if native_test:
  suffix='.gateway.cloud.nativeTest' if variant=='internal_receiver' else '.staff.cloud.nativeTest'
  if root.get('package')!='rw.ikanisa.burimunsi'+suffix:errors.append('Native-test package identity mismatch')
  if app.get(A+'testOnly')!='true':errors.append('Native-test artifact is not testOnly')
  if app.get(A+'debuggable')!='true':errors.append('Native-test artifact must allow instrumentation debugging')
  if 'android.permission.INTERNET' in permissions:errors.append('Offline native-test artifact requests INTERNET')
 if strict_components and variant=='internal_receiver':
  if not CONTINUOUS_PERMISSIONS<=permissions:errors.append('Continuous receiver permissions missing')
  if any(name.startswith('android.permission.FOREGROUND_SERVICE') and name not in CONTINUOUS_PERMISSIONS for name in permissions):errors.append('Unapproved foreground service type permission')
  for name,tag,guard,exported in (
   ('CollectSmsReceiver','receiver','android.permission.BROADCAST_SMS','true'),
   ('MomoGatewayRecoveryReceiver','receiver',None,'false'),
   ('MomoGatewayJobService','service','android.permission.BIND_JOB_SERVICE','true'),
   ('MomoGatewayLocalRecoveryService','service','android.permission.BIND_JOB_SERVICE','true'),
   ('ObservationSmsReceiver','receiver','android.permission.BROADCAST_SMS','true'),
   ('ObservationBootReceiver','receiver',None,'false'),
   ('ObservationJobService','service','android.permission.BIND_JOB_SERVICE','true'),
   ('BuriContinuousSyncService','service',None,'false')):
   matches=[e for e in app if e.tag in ('receiver','service') and e.get(A+'name')=='app.cool.mobile.receiver_sms.'+name]
   if len(matches)!=1 or matches[0].tag!=tag:errors.append('Receiver component absent or duplicated: '+name);continue
   component=matches[0]
   if component.get(A+'exported')!=exported:errors.append('Unexpected exported setting: '+name)
   if component.get(A+'permission')!=guard:errors.append('Unexpected component permission: '+name)
  services=[e for e in app.findall('service') if e.get(A+'name')==CONTINUOUS_SERVICE]
  if len(services)==1:
   service=services[0]
   # apkanalyzer renders compiled flag enums numerically; accept only the exact
   # specialUse value, never a bitmask containing another foreground type.
   if service.get(A+'foregroundServiceType') not in ('specialUse','0x40000000','1073741824') or service.get(A+'stopWithTask')!='false':errors.append('Continuous receiver foreground lifecycle/type wrong')
   properties=service.findall('property')
   if len(properties)!=1 or properties[0].get(A+'name')!='android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE' or properties[0].get(A+'value')!=CONTINUOUS_SUBTYPE:errors.append('Continuous receiver use case property wrong')
  if any(e.get(A+'foregroundServiceType') is not None and e.get(A+'name')!=CONTINUOUS_SERVICE for e in app.findall('service')):errors.append('Unapproved foreground service component')
 if qualification:
  suffix='.staff.cloud.qualification' if variant=='staff' else '.gateway.cloud.qualification'
  if root.get('package')!='rw.ikanisa.burimunsi'+suffix:errors.append('Qualification package identity mismatch')
  if app.get(A+'testOnly')!='true':errors.append('Qualification artifact is not testOnly')
  if 'android.permission.INTERNET' in permissions:errors.append('Offline qualification artifact requests INTERNET')
  if root.get(A+'sharedUserId'):errors.append('Qualification must not share another app UID')
 return errors

def source_checks(root):
 errors=[]
 main=root/'app/src/main';staff=root/'app/src/staff';receiver=root/'app/src/internal_receiver'
 for base in (main,staff):
  for f in base.rglob('*.kt'):
   text=f.read_text()
   if any(n in text for n in ('Telephony.Sms','SmsManager','NotificationListenerService','app.cool.mobile.receiver_sms','android.webkit.WebView')):errors.append(str(f.relative_to(root))+': forbidden code in shared/Staff source')
   if any(n in text for n in ('BMDemo','BMReview','staff@burimunsi','admin@burimunsi')):errors.append(str(f.relative_to(root))+': prototype material')
 for f in (root/'app/src').rglob('*.xml'):
  try:ET.parse(f)
  except ET.ParseError:errors.append(str(f.relative_to(root))+': invalid XML')
 main_tree=ET.parse(main/'AndroidManifest.xml');main_xml=ET.tostring(main_tree.getroot(),encoding='unicode')
 errors.extend(manifest_failures(main_xml,'staff'))
 declared=ET.parse(staff/'AndroidManifest.xml').getroot()
 removed={x.get(A+'name') for x in declared.findall('uses-permission') if x.get(T+'node')=='remove'}
 if not (FORBIDDEN-{'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'})<=removed:errors.append('Staff manifest removal safeguards incomplete')
 if any(main.rglob('*.html')) or any(staff.rglob('*.html')):errors.append('HTML is not native production UI')
 if not (receiver/'kotlin/app/cool/mobile/receiver_sms/BuriCapturePolicy.kt').exists():errors.append('Receiver privacy hook missing')
 return errors

def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]);p.add_argument('--variant',choices=['staff','internal_receiver'],default='staff');p.add_argument('--merged-manifest',type=pathlib.Path);p.add_argument('--apk',type=pathlib.Path);p.add_argument('--apkanalyzer');p.add_argument('--release',action='store_true');p.add_argument('--qualification',action='store_true');a=p.parse_args()
 if a.release and a.qualification:p.error('Choose production release or qualification, not both.')
 errors=source_checks(a.root);checks=['source_sets','XML syntax','shared source SMS exclusion','prototype exclusion']
 if a.merged_manifest:errors+=manifest_failures(a.merged_manifest.read_text(),a.variant,release=a.release,qualification=a.qualification);checks.append('supplied merged manifest')
 if a.apk:
  if not a.apkanalyzer:raise SystemExit('--apk requires --apkanalyzer; binary XML is not plain text')
  manifest=subprocess.run([a.apkanalyzer,'manifest','print',str(a.apk)],text=True,capture_output=True,check=True).stdout
  errors+=manifest_failures(manifest,a.variant,release=a.release,qualification=a.qualification);checks.append('actual APK manifest')
  with zipfile.ZipFile(a.apk) as z:
   if a.variant=='staff':
    for name in z.namelist():
     if name.endswith('.dex') and any(n.encode() in z.read(name) for n in SMS_NAMES):errors.append('Staff DEX contains a prohibited receiver/listener marker')
   if any(name.endswith('.html') for name in z.namelist()):errors.append('APK contains unexpected HTML')
  checks.append('actual APK content')
 report={'ok':not errors,'scope':'apk' if a.apk else 'merged-manifest' if a.merged_manifest else 'source-only','checks':checks,'failures':errors,'limitations':'Source inspection does not establish merged APK permissions, installed-device access or native visual fidelity.'}
 print(json.dumps(report,indent=2));return bool(errors)
if __name__=='__main__':sys.exit(main())
