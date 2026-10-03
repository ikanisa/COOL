import hashlib,json,os,subprocess,time,datetime,threading,http.server,urllib.parse
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-routes-attempt159'
BUILD=ROOT/'.cache/public-website-build-attempt158';OUT=ROOT/'.cache/public-browser-routes-attempt159'
PRIOR=ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-website-rebuild-attempt158'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert json.loads((PRIOR/'verification.json').read_text())['status']=='pass'
assert json.loads((ROOT/'docs/release/asset-build-hygiene-2026-09-30/public-browser-local-network-attempt144/validation.json').read_text())['status']=='pass'
manifest=json.loads((PRIOR/'build-manifest.json').read_text());source=json.loads((PRIOR/'source-before.json').read_text())
tooling=['scripts/public_website_route_rendered_qa.js','scripts/qa/public_browser_local_network.cjs']
source.update({n:sha(ROOT/n) for n in tooling})
for n,h in manifest.items():assert sha(BUILD/n)==h,n
for n,h in source.items():assert sha(ROOT/n)==h,n
P.mkdir(exist_ok=False);OUT.mkdir(exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
(P/'source-before.json').write_text(json.dumps(source,indent=2,sort_keys=True)+'\n');(P/'build-before.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
served={};server_errors=[]
class Handler(http.server.SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(BUILD),**kwargs)
 def log_message(self,*args):pass
 def do_GET(self):
  actual=Path(self.translate_path(self.path))
  if actual.is_dir():actual=actual/'index.html'
  if actual.is_file():
   try:
    n=actual.resolve().relative_to(BUILD.resolve()).as_posix();h=sha(actual)
    assert n in manifest and h==manifest[n],'Served bytes differ from accepted static build'
    served[n]=h
   except Exception as e:server_errors.append(str(e));self.send_error(500);return
  super().do_GET()
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'PUBLIC_BUILD_DIR':str(BUILD),'PUBLIC_WEBSITE_QA_OUT':str(OUT),'PUBLIC_WEBSITE_QA_URL':'http://127.0.0.1:'+str(server.server_port)+'/', 'PLAYWRIGHT_CORE_PATH':'/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js','PUBLIC_WEBSITE_CHROME_PATH':'/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'})
argv=['/Volumes/PRO-G40/Development/Node/bin/node','scripts/public_website_route_rendered_qa.js'];started=time.monotonic();code=None;exception=None
(P/'execution.json').write_text(json.dumps({'status':'running','command':argv,'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
try:
 with (P/'browser.stdout').open('wb') as out,(P/'browser.stderr').open('wb') as err:
  try:code=subprocess.run(argv,cwd=ROOT,env=env,stdout=out,stderr=err,timeout=1200).returncode
  except subprocess.TimeoutExpired:exception='bounded1200second observation timeout'
finally:server.shutdown();server.server_close()
reportfile=OUT/'route_rendered_qa.json';report=json.loads(reportfile.read_text()) if reportfile.is_file() else None
if report:(P/'route_rendered_qa.json').write_bytes(reportfile.read_bytes())
images={p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*.png')) if p.is_file() and not p.is_symlink()}
(P/'capture-sha256.json').write_text(json.dumps(images,indent=2,sort_keys=True)+'\n')
source_drift={n:{'before':h,'after':sha(ROOT/n) if (ROOT/n).is_file() else None} for n,h in source.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
current={p.relative_to(BUILD).as_posix():sha(p) for p in BUILD.rglob('*') if p.is_file() and not p.is_symlink()}
verified=code==0 and report and report['status']=='pass' and not source_drift and manifest==current and not server_errors and not report['blockedNetworkRequests']
receipt={'status':'pass' if verified else 'fail','exit_code':code,'exception':exception,'elapsed_seconds':round(time.monotonic()-started,2),'completed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':argv,'source_inputs':len(source),'source_drift':source_drift,'accepted_static_build_files':len(manifest),'static_build_unchanged':manifest==current,'served_resources':served,'server_integrity_errors':server_errors,'route_viewport_cases':len(report['results']) if report else 0,'share_viewport_cases':len(report['shareResults']) if report else 0,'capture_count':len(images),'capture_manifest_sha256':sha(P/'capture-sha256.json'),'browser_receipt_sha256':sha(P/'route_rendered_qa.json') if report else None,'browser_stdout_sha256':sha(P/'browser.stdout'),'browser_stderr_sha256':sha(P/'browser.stderr'),'scope':'Actual local Chrome marketing15routes at4viewports and4share states at4viewports, focus/menu/geometry/media/landmarks checks on exact static142bytes. Page HTTP exact-loopback fenced; no external service/store/physical device/signing, legal or comprehensive Revolut visual approval.'}
(P/'validation.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print('PUBLIC ROUTE QA',receipt['status'],receipt['route_viewport_cases'],receipt['share_viewport_cases'],flush=True)
raise SystemExit(0 if verified else 1)
