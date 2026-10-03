import hashlib,importlib.util,json,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path.cwd();STAGE=ROOT/'.cache/collect-native-recovery-custody-20261002'
PACKET=STAGE/'check-attempt3';PACKET.mkdir(exist_ok=False)
shutil.copyfile(Path(__file__),PACKET/'check.py')
def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
helper_path=Path('scripts/tests/android_gateway_native_tools.py')
target=PACKET/'source'/helper_path;target.parent.mkdir(parents=True);shutil.copyfile(ROOT/helper_path,target)
spec=importlib.util.spec_from_file_location('current_native',target);helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
suites=['GatewayRecoveryTest','GatewayRecoveryHistoryTest','GatewayRecoveryTransferTest']
products=helper.product_sources(ROOT);apis=helper.api_sources(ROOT);tests=helper.test_sources(ROOT,suites+['GatewayLateRetentionTest'])
paths=list(dict.fromkeys(products+apis+tests+[helper_path,Path('android/app/src/internal_gateway/AndroidManifest.xml'),Path('android/app/src/main/AndroidManifest.xml'),Path('android/app/build.gradle.kts')]))
canonical={str(p):sha(ROOT/p) for p in paths};selected={};source_origin={}
for rel in paths:
    origin=STAGE/'promote'/rel
    if not origin.is_file():origin=ROOT/rel
    captured=PACKET/'source'/rel;captured.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(origin,captured)
    selected[str(rel)]=sha(captured);source_origin[str(rel)]=str(origin)
for name,body in helper.SHIMS.items():
    target=PACKET/'shims'/name;target.parent.mkdir(exist_ok=True);target.write_text(body)
deps=[helper.jar(*parts) for parts in helper.DEPENDENCIES]
embedding=helper.jar('io.flutter','flutter_embedding_debug','1.0.0-'+helper.FLUTTER_ENGINE.read_text().strip());lifecycle=helper.jar('androidx.lifecycle','lifecycle-common-jvm','2.9.4')
binary=sorted({p for p in helper.JBR.rglob('*') if p.is_file()}|set(deps+[helper.ANDROID_API,embedding,lifecycle,helper.FLUTTER_ENGINE]));binary_sha={str(p):sha(p) for p in binary}
report={'status':'failed','scope':'Private custody overlay; synthetic JVM AES/filesystem, real Android36 API compilation; no handset/Keystore/SMS/hosted acceptance','suites':suites,'source_sha256':selected,'canonical_before_sha256':canonical,'source_origin':source_origin,'binary_sha256':binary_sha,'commands':[]}
(PACKET/'inputs.json').write_text(json.dumps(report,indent=2)+'\n')
def run(name,args):
    try:r=subprocess.run(args,capture_output=True,timeout=480)
    except subprocess.TimeoutExpired as e:r=subprocess.CompletedProcess(args,124,e.stdout or b'',(e.stderr or b'')+b'\nBounded command timeout\n')
    (PACKET/(name+'.stdout')).write_bytes(r.stdout);(PACKET/(name+'.stderr')).write_bytes(r.stderr)
    report['commands'].append({'name':name,'argv':args,'exit_code':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
    (PACKET/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(name+' terminal '+str(r.returncode),flush=True)
    return r.returncode
source_cp=os.pathsep.join(str(deps[i]) for i in (1,4,6,7,8));code=0
try:
    with tempfile.TemporaryDirectory(prefix='collect-recovery-custody-') as temp:
        temp=Path(temp);classes=temp/'classes';classes.mkdir();tc=temp/'tests';tc.mkdir();api=temp/'api';api.mkdir()
        compiler=[str(helper.JBR/'bin/java'),'-Xms64m','-Xmx1g','-XX:ActiveProcessorCount=2','-cp',os.pathsep.join(map(str,deps)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17']
        code=run('compile-product',compiler+['-module-name','gateway_product','-classpath',source_cp,'-d',str(classes)]+[str(PACKET/'source'/p) for p in products]+[str(p) for p in sorted((PACKET/'shims').glob('*.kt'))])
        if not code:code=run('compile-tests',compiler+['-module-name','gateway_recovery_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),source_cp]),'-d',str(tc)]+[str(PACKET/'source'/p) for p in tests])
        if not code:
            config=PACKET/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
            code=run('compile-android36-api',compiler+['-classpath',os.pathsep.join([str(helper.ANDROID_API),str(embedding),str(lifecycle),source_cp]),'-d',str(api)]+[str(PACKET/'source'/p) for p in apis]+[str(config)])
        if not code:code=run('affected-recovery-suites',[str(helper.JBR/'bin/java'),'-ea','-Xmx512m','-XX:ActiveProcessorCount=2','-cp',os.pathsep.join([str(classes),str(tc),source_cp]),'org.junit.runner.JUnitCore']+['app.cool.mobile.gateway.'+s for s in suites])
    report['canonical_changes']=[str(p) for p in paths if sha(ROOT/p)!=canonical[str(p)]]
    report['selected_changes']=[p for p,origin in source_origin.items() if sha(Path(origin))!=selected[p]]
    report['binary_changes']=[str(p) for p in binary if sha(p)!=binary_sha[str(p)]]
    report['status']='passed' if not code and not report['canonical_changes'] and not report['selected_changes'] and not report['binary_changes'] else 'failed'
except Exception as e:report['error']=str(e)
(PACKET/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report.get(k) for k in ('status','error','canonical_changes','selected_changes','binary_changes')}),flush=True)
raise SystemExit(0 if report['status']=='passed' else 1)
