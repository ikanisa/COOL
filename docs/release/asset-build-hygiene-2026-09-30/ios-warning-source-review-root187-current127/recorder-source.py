#!/usr/bin/env python3
"""Bind each current iOS compiler warning to actual bytes and a reviewed rationale."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import re
import shutil
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30'
OUT=BASE/'ios-warning-source-review-root187-current127'
OLD=BASE/'ios-warning-source-review-attempt29/review.json'
BUILD=BASE/'native-export-attempt127-ios-continuation4'
ACCEPT=BASE/'native-export-attempt127-ios-postbuild-verification1/artifact-verification.json'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt127-ios')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def key(m):
 match=re.match(r'(.+?):(\d+):(\d+): warning:(.*)',m)
 if match:return (Path(match[1]).name,match[2],match[3],match[4])
 if 'appintentsmetadataprocessor[' in m:return ('AppIntents',m.split('warning:',1)[1])
 return ('rendering',m)
prior=json.loads(OLD.read_bytes());execution=json.loads((BUILD/'execution.json').read_bytes());artifact=json.loads(ACCEPT.read_bytes())
assert next(c for c in execution['commands'] if c['name']=='unsigned-ios-build')['exit_code']==0
assert artifact['status']=='pass'
log=BUILD/'unsigned-ios-build.stdout'; raw=sorted(set(line.strip() for line in log.read_text().splitlines() if 'warning:' in line))
old={key(row['message']):row for row in prior['rows']};assert len(old)==len(prior['rows'])
assert all(key(m) in old for m in raw),'Novel diagnostic requires a separate individual review'
assert not OUT.exists();OUT.mkdir(mode=0o700);snap=OUT/'source-snapshot';snap.mkdir()
(OUT/'recorder-source.py').write_bytes(Path(__file__).read_bytes())
rows=[];sources={}
for n,m in enumerate(raw,1):
 priorrow=old[key(m)];row={k:v for k,v in priorrow.items() if k not in {'id','message','source','source_sha256','preserved_source','source_excerpt','line','duplicates_primary_id'}}
 row.update(id=n,message=m,prior_review_id=priorrow['id'],warning_suppressed=False,runtime_acceptance_claimed=False)
 match=re.match(r'(.+?):(\d+):\d+: warning:',m)
 if match:
  src=Path(match[1]);line=int(match[2]);assert src.resolve().is_relative_to(EXPORT)
  if sha(src)!=priorrow['source_sha256']:
   assert src.name=='Dialog.swift','Unreviewed warned source drift: '+str(src)
   before=(ROOT/priorrow['preserved_source']).read_text()
   replacements={'print(error.localizedDescription)':'print("FileSaver temporary file cleanup failed")',
     'print("in didPickDocumentAt " + url.path)':'print("FileSaver document selection completed")',
     'print("in didPickDocumentAt " + urls[0].path)':'print("FileSaver document selection completed")'}
   expected=before
   for old,new in replacements.items():
    assert expected.count(old)==1
    expected=expected.replace(old,new)
   assert src.read_text()==expected,'Dialog contains a change beyond the three reviewed logging redactions'
   row.update(source_delta_review='Exact three logging replacements remove private paths and localized errors. No picker, keyWindow, callback or return statement changed; prior window-selection rationale remains applicable.',
     prior_source_sha256=priorrow['source_sha256'],source_diff_limited_to_reviewed_log_redaction=True)
   import difflib
   (OUT/'Dialog-log-redaction.diff').write_text('\n'.join(difflib.unified_diff(before.splitlines(),src.read_text().splitlines(),fromfile='prior-reviewed-Dialog.swift',tofile='current-compiled-Dialog.swift'))+'\n')
  target=snap/f'{n:02d}-{src.name}';shutil.copy2(src,target);assert sha(src)==sha(target)
  text=src.read_text().splitlines();row.update(source=str(src),source_sha256=sha(src),preserved_source=str(target.relative_to(ROOT)),line=line,source_excerpt=[{'line':i+1,'text':text[i]}for i in range(max(0,line-5),min(len(text),line+5))]);sources[str(target.relative_to(ROOT))]=sha(target)
 rows.append(row)
for row in rows:
 if row['disposition']=='duplicate_swift_diagnostic_rendering':
  oldrow=old[key(row['message'])];wanted=oldrow['duplicates_primary_id'];matched=[r for r in rows if r['prior_review_id']==wanted];assert len(matched)==1;row['duplicates_primary_id']=matched[0]['id']
# Bind prerequisites used by the individual existing rationales; none is inferred from the artifact name.
extra={'captured-Podfile':EXPORT/'ios/Podfile','captured-Info.plist':EXPORT/'ios/Runner/Info.plist','captured-share_screen.dart':EXPORT/'lib/features/collections/share_screen.dart','captured-FileSaverPlugin.swift':EXPORT/'third_party/file_saver/ios/file_saver/Sources/file_saver/FileSaverPlugin.swift'}
for name,src in extra.items():
 target=snap/name;shutil.copy2(src,target);assert sha(src)==sha(target);sources[str(target.relative_to(ROOT))]=sha(target)
assert '15.5' in extra['captured-Podfile'].read_text()
assert 'FileSaver.instance.saveFile' in extra['captured-share_screen.dart'].read_text()
result=dict(status='pass',kind='actual_current_ios_individual_warning_review',captured_at=dt.datetime.now(dt.timezone.utc).isoformat(),source_build=str(BUILD.relative_to(ROOT)),build_execution_sha256=sha(BUILD/'execution.json'),actual_build_exit_code=0,artifact_verification_sha256=sha(ACCEPT),preserved_build_stdout_sha256=sha(log),prior_review=str(OLD.relative_to(ROOT)),prior_review_sha256=sha(OLD),raw_unique_warning_strings=len(raw),primary_diagnostics=sum(r['disposition']!='duplicate_swift_diagnostic_rendering' for r in rows),duplicate_renderings=sum(r['disposition']=='duplicate_swift_diagnostic_rendering' for r in rows),every_diagnostic_matched_by_exact_file_line_message=True,every_source_byte_difference_individually_reviewed=True,novel_diagnostics=[],prior_diagnostics_not_emitted=[r['id'] for r in prior['rows'] if key(r['message']) not in {key(m)for m in raw}],rows=rows,preserved_sources=sources,blanket_warning_suppression=False,firebase_scene_return_correction='Corrected BOOL implementation compiled; prior incompatible callback warning remains absent',native_runtime_or_release_accepted=False,scope='Actual current127 generic-device compilation diagnostics, individually retained by exact message/source bytes and bound prerequisite snapshots; no camera/picker/provider/device runtime acceptance')
save(OUT/'review.json',result);print(json.dumps({k:result[k]for k in ['status','raw_unique_warning_strings','primary_diagnostics','duplicate_renderings']}))
