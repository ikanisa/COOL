import hashlib,json,pathlib,time
here=pathlib.Path(__file__).resolve().parent;release=here.parent
paths=[here/'admit_verified_blobs.py',here/'admission_fixtures.py',
 release/'arc09-aab-driver-preparation1/argv-unavailable-recovery3/run_selected_aab.py',
 release/'kotlin-sdk-native-native-stage-preparation1/publisher_metadata.py',
 release/'kotlin-sdk-native-native-stage-preparation1/proposed-commands.json',
 release/'arc09-lint32-binary-acquisition-preparation1/plan.json',
 release/'arc09-lint32-binary-acquisition-preparation-recovery2/source-fences.json',
 release/'root-lint32-combined-publisher-binaries1/readback.json',
 release/'root-lint32-combined-publisher-binaries1/packet-files.json',
 release/'root-lint32-kotlin-compiler-binary-recovery1/readback.json',
 release/'root-lint32-kotlin-compiler-binary-recovery1/packet-files.json',
 pathlib.Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/lint32-selected-publisher-binaries1/readback.json'),
 pathlib.Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/lint32-selected-publisher-binaries1/packet-files.json'),
 pathlib.Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/lint32-selected-publisher-kotlin-compiler-recovery1/packet-files.json'),
 release/'root-lint32-tooling-metadata-resolution3/selected-tooling-graph.json',
 release/'root-lint32-tooling-metadata-resolution3/prior-selected-metadata-parity.json',
 pathlib.Path('/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'),
 pathlib.Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java')]
rows=[]
for path in paths:
 raw=path.read_bytes();st=path.stat();rows.append({'path':str(path),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'captured_mode':st.st_mode&0o777,'physical_regular_nlink1':path.resolve()==path and st.st_nlink==1 and path.is_file()})
 assert rows[-1]['physical_regular_nlink1']
config_path=str(release/'kotlin-sdk-native-native-stage-preparation1/proposed-commands.json');python_path='/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
record={'schema_version':1,'Python':next(r for r in rows if r['path']==python_path),'config_sha256':next(r['sha256'] for r in rows if r['path']==config_path),'inputs':rows,'fixed_pool':'/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/gradle-home/caches/modules-2/files-2.1','source_readbacks_sealed_before_capture':True,'only67_exact_publisher_JAR_blobs_copyable':True,'global_work_seconds':180,'full_graph_admission':False}
with (here/'inputs.json').open('x') as f:json.dump(record,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps({'input_count':len(rows),'inputs_sha256':hashlib.sha256((here/'inputs.json').read_bytes()).hexdigest(),'code_sha256':rows[0]['sha256'],'runtime_bytes':record['Python']['bytes']}))
