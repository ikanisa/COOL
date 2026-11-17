"""Observe a bound, naturally scheduled successful tick without dispatching one."""
import json,re,time
from pathlib import Path
import candidate_guard as c
import scheduler_wrapper

def complete_receipt(path,*,configuration,after_ns,launch_stdout,release,wrapper):
 try:
  value=json.loads(c.private(Path(path)))
  runs=re.findall(rb'^\truns = ([0-9]+)\s*$',launch_stdout,re.M)
  exits=re.findall(rb'^\tlast exit code = ([0-9]+)\s*$',launch_stdout,re.M)
  active=re.findall(rb'^\tactive count = ([0-9]+)\s*$',launch_stdout,re.M)
  return bool(value.get('format')==scheduler_wrapper.FORMAT and value.get('status')=='complete'
   and value.get('source_sha256')==c.SOURCE and value.get('configuration_sha256')==configuration
   and value.get('scheduler_script_sha256')==scheduler_wrapper.SCRIPT_SHA256
   and type(value.get('started_ns')) is int and type(value.get('finished_ns')) is int
   and value['finished_ns']>=value['started_ns']>=after_ns
   and len(runs)==1 and int(runs[0])>=1 and len(exits)==1 and exits[0]==b'0'
   and len(active)==1 and active[0]==b'0' and str(release).encode() in launch_stdout
   and str(wrapper).encode() in launch_stdout)
 except (OSError,KeyError,ValueError,TypeError):return False

def wait_for_tick(path,*,configuration,after_ns,probe,release,wrapper,timeout=50):
 deadline=time.monotonic()+timeout
 while time.monotonic()<deadline:
  result=probe()
  if result.returncode==0 and complete_receipt(path,configuration=configuration,after_ns=after_ns,launch_stdout=result.stdout,release=release,wrapper=wrapper):return
  time.sleep(.25)
 raise ValueError('natural_scheduler_tick_unconfirmed')
