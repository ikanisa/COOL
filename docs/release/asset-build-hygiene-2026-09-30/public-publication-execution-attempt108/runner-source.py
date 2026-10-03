import hashlib,json,datetime,subprocess
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-publication-execution-attempt108'
TARGET=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-media-publication-attempt106'
REPORT=ROOT/'.cache/public-app-media-attempt105/capture-report.json'
REVIEW=ROOT/'.cache/public-app-media-attempt105/visual-review.json'
TOOL=ROOT/'scripts/assets/publish_public_app_media.py'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-graph-current-attempt103/validation.json').read_text())['status']=='pass'
accepted=json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-graph-current-attempt103/inputs.json').read_text())
assert sha(TOOL)==accepted['scripts/assets/publish_public_app_media.py']
P.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes());(P/'publisher-source.py').write_bytes(TOOL.read_bytes())
base={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'publisher_sha256':sha(TOOL),'capture_report_sha256':sha(REPORT),'review_sha256':sha(REVIEW),'publication_packet':str(TARGET.relative_to(ROOT)),'scope':'Byte-identical local preview/provenance publication only; prior media preserved, no hosting/native release acceptance.'}
argv=['python3',str(TOOL),'--capture-report',str(REPORT),'--visual-review',str(REVIEW),'--packet',str(TARGET)]
(P/'execution.json').write_text(json.dumps({**base,'status':'running','command':argv},indent=2)+'\n')
with (P/'publication.stdout').open('wb') as out,(P/'publication.stderr').open('wb') as err:r=subprocess.run(argv,cwd=ROOT,stdout=out,stderr=err)
assert sha(TOOL)==base['publisher_sha256']
receipt=TARGET/'publication.json'
(P/'execution.json').write_text(json.dumps({**base,'status':'pass' if r.returncode==0 else 'fail','exit_code':r.returncode,'stdout_sha256':sha(P/'publication.stdout'),'stderr_sha256':sha(P/'publication.stderr'),'publication_receipt_sha256':sha(receipt) if receipt.is_file() else None,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
print('PUBLIC PREVIEW PUBLICATION',r.returncode,flush=True)
raise SystemExit(r.returncode)
