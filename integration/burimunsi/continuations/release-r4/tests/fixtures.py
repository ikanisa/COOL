"""Temporary synthetic evidence only. Never represents actual product qualification."""
from pathlib import Path
import datetime as dt
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import release_guard as g

class Fixture:
    def __init__(self,base,product='BuriMunsi',phase='source'):
        self.base=base;self.source=base/'source';self.source.mkdir();self.evidence=base/'evidence';self.evidence.mkdir()
        (self.source/'main.py').write_text('print("synthetic fixture")\n')
        (self.source/'package.json').write_text('{"name":"synthetic","dependencies":{}}\n')
        self.product=product;self.phase=phase;self.version='synthetic-fixture-1';self.now=dt.datetime.now(g.UTC)
        self.t=lambda offset:(self.now+dt.timedelta(seconds=offset)).isoformat().replace('+00:00','Z')
        self.s=g.capture(self.source,product,self.version);self.s['captured_at']=self.t(-60)
        self.sref=self.store('source-manifest.json',self.s);self.dep=g.dependencies(self.s)
        if phase!='source':
            self.dep['resolution_status']='resolved'
            self.dep['components']=[{'id':'synthetic:component','version':'1','artifact':self.store('dependencies/component.txt',b'SYNTHETIC dependency bytes')}]
        self.dref=self.store('dependencies.json',self.dep);policy=g.policy(product,phase)
        self.m={'schema_version':1,'kind':'release-evidence','product':product,'source_version':self.version,
                'phase':phase,'designation':policy['designation'],'policy_sha256':g.policy_sha(product,phase),
                'run_id':'synthetic-run-000001','created_at':self.t(-10),'source_manifest':self.sref,
                'dependency_inventory':self.dref,'artifacts':[],'qualifications':[]}
        for aid in policy['artifact_ids']:
            kind='aab' if aid.endswith('aab') else 'apk';name='base/manifest/AndroidManifest.xml' if kind=='aab' else 'AndroidManifest.xml'
            raw=g.zip_bytes({name:b'SYNTHETIC Android container fixture only'})
            self.m['artifacts'].append({'id':aid,'kind':kind,'file':self.store('artifacts/'+aid+'.'+kind,raw)})
        self.results={}
        for qid,scope in policy['requirements'].items():
            r={'schema_version':1,'kind':'qualification-result','id':qid,'scope':scope,'product':product,'source_version':self.version,
               'run_id':self.m['run_id'],'policy_sha256':self.m['policy_sha256'],'source_tree_sha256':self.s['tree_sha256'],
               'source_manifest_sha256':self.sref['sha256'],'dependency_inventory_sha256':self.dref['sha256'],
               'artifact_sha256s':{a['id']:a['file']['sha256'] for a in self.m['artifacts']},
               'started_at':self.t(-50),'completed_at':self.t(-20),'status':'passed','executed':True,'exit_code':0,
               'counts':{'executed':1,'failed':0,'skipped':0,'blocked':0},'command':['synthetic-fixture-only'],
               'log':self.store('logs/'+qid+'.txt',('SYNTHETIC TEST FIXTURE ONLY: '+qid+'\n').encode())}
            self.results[qid]=r;self.m['qualifications'].append({'id':qid,'result':self.store('results/'+qid+'.json',r)})

    def store(self,name,value):
        raw=value if isinstance(value,bytes) else g.pretty(value);p=self.evidence/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
        return g.ref(name,raw)

    def change_result(self,fn,qid=None):
        qid=qid or next(iter(self.results));fn(self.results[qid])
        for q in self.m['qualifications']:
            if q['id']==qid:q['result']=self.store(q['result']['path'],self.results[qid])

    def check(self):return g.validate_consistency(self.source,self.evidence,self.m,product=self.product,version=self.version,phase=self.phase,now=self.now)
