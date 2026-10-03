from pathlib import Path
import importlib,json,os,runpy,sys
candidate=Path(sys.argv[1]);report=Path(sys.argv[2]);owned=Path(sys.argv[3])
sys.path.insert(0,str(candidate/'scripts/tests'))
replay=importlib.import_module('collect_current_release_upgrade_uat')
original=replay.Target.__init__
def register(self,*args,**kwargs):
 original(self,*args,**kwargs)
 with owned.open('a') as stream:
  stream.write(json.dumps({'name':self.name,'label':'collect.rehearsal.owner='+self.name,'phase':self.phase,'image_id':replay.IMAGE_ID})+'\n');stream.flush();os.fsync(stream.fileno())
replay.Target.__init__=register
sys.argv=[str(candidate/'scripts/tests/current_ordinary_installer_rehearsal.py'),'--output',str(report)]
runpy.run_path(sys.argv[0],run_name='__main__')
