import hashlib,importlib,json,os,sys,time
from pathlib import Path
config=Path(sys.argv[1]);raw=config.read_bytes()
assert hashlib.sha256(raw).hexdigest()==sys.argv[2], 'Frozen child configuration changed'
c=json.loads(raw);root=Path(c['candidate'])
for rel,pin in c['source_before'].items():
 assert hashlib.sha256((root/rel).read_bytes()).hexdigest()==pin, 'Captured source changed'
sys.path.insert(0,str(root/'scripts/tests'))
replay=importlib.import_module('collect_current_release_upgrade_uat')
replay.DOCKER=c['docker'];replay.IMAGE=c['image_id'];replay.HOSTED=root/c['predecessor']
sql=(root/c['platform']).read_bytes()
assert hashlib.sha256(sql).hexdigest()==c['platform_sha256']
replay.platform_shape=lambda:(sql.decode(),c['platform_provenance'])
original_command=replay.command
def checked_command(args,*a,**kw):
 assert time.monotonic()<c['execution_deadline'], 'Execution deadline reached'
 assert args[0]==c['docker'], 'Only the bound Docker executable is admitted'
 path=Path(c['docker']);assert path.stat().st_size<=128*1024**2, 'Docker exceeds bound'
 assert hashlib.sha256(path.read_bytes()).hexdigest()==c['docker_sha256'], 'Docker bytes drifted'
 return original_command(args,*a,**kw)
replay.command=checked_command
original_init=replay.Target.__init__
def register(self,*args,**kwargs):
 original_init(self,*args,**kwargs)
 with open(c['owned'],'a') as stream:
  stream.write(json.dumps({'name':self.name,'phase':self.phase,'image_id':replay.IMAGE_ID})+'\n')
  stream.flush();os.fsync(stream.fileno())
replay.Target.__init__=register
runner=importlib.import_module('current_ordinary_installer_rehearsal')
sys.argv=[runner.__file__,'--output',c['report']]
runner.main()
