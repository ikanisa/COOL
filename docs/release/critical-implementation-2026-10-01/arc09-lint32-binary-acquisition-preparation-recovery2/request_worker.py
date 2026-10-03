"""Private streamed curl transport. Executed only by the reviewed parent controller."""
import argparse,json,os,subprocess,sys,threading,time
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--url',required=True);p.add_argument('--body',required=True,type=Path);p.add_argument('--max-bytes',required=True,type=int);p.add_argument('--seconds',required=True,type=float);a=p.parse_args()
 argv=['/usr/bin/curl','--disable','--proxy','','--noproxy','*','--proto','=https','--proto-redir','=https','--connect-timeout',str(min(10,a.seconds)),'--max-time',str(a.seconds),'--retry','0','--silent','--show-error','--include','--output','-',a.url]
 env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LC_ALL':'C','TMPDIR':str(a.body.parent)}
 started=time.monotonic();child=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env);stderr=bytearray();stderr_excess=False
 def drain():
  nonlocal stderr_excess
  while True:
   chunk=child.stderr.read(4096)
   if not chunk:return
   if len(stderr)+len(chunk)>65536:stderr_excess=True
   stderr.extend(chunk[:max(0,65536-len(stderr))])
 thread=threading.Thread(target=drain,daemon=True);thread.start();headers=[];header_bytes=0;size=0;error=None;status=None
 try:
  while True:
   line=child.stdout.readline(65537);header_bytes+=len(line)
   if header_bytes>65536 or len(line)>65536:raise ValueError('64KiB HTTP header bound')
   first=line.decode('iso-8859-1').strip().split()
   if len(first)<2 or not first[0].startswith('HTTP/') or not first[1].isdigit():raise ValueError('Unsupported HTTP status line')
   status=int(first[1]);headers=[]
   while True:
    line=child.stdout.readline(65537);header_bytes+=len(line)
    if header_bytes>65536 or len(line)>65536:raise ValueError('64KiB HTTP header bound')
    if line in [b'\r\n',b'\n']:break
    if not line or b':' not in line or line[:1] in [b' ',b'\t']:raise ValueError('Unsupported HTTP header')
    key,value=line.decode('iso-8859-1').strip().split(':',1);headers.append([key.lower(),value.strip()])
   if status<200 and status!=101:continue
   break
  with a.body.open('xb') as target:
   while True:
    chunk=child.stdout.read(65536)
    if not chunk:break
    if size+len(chunk)>a.max_bytes:raise ValueError('HTTP body byte bound exceeded')
    target.write(chunk);size+=len(chunk)
   target.flush();os.fsync(target.fileno())
  cleanup_deadline=time.monotonic()+2;child.wait(timeout=max(0.001,cleanup_deadline-time.monotonic()));thread.join(timeout=max(0.001,cleanup_deadline-time.monotonic()))
  if thread.is_alive() or stderr_excess:raise ValueError('HTTP stderr bound/reader incomplete')
 except BaseException as exc:
  error={'type':type(exc).__name__,'error':str(exc)}
  if child.poll() is None:
   cleanup_deadline=time.monotonic()+2;child.terminate()
   try:child.wait(timeout=min(1,max(0.001,cleanup_deadline-time.monotonic())))
   except subprocess.TimeoutExpired:
    child.kill()
    try:child.wait(timeout=max(0.001,cleanup_deadline-time.monotonic()))
    except subprocess.TimeoutExpired:error={'type':'TimeoutError','error':'Owned curl child remains unreaped after bounded cleanup'}
 finally:
  if child.poll() is not None and not thread.is_alive():child.stdout.close();child.stderr.close()
 print(json.dumps({'curl_argv':argv,'curl_PID':child.pid,'curl_exit_code':child.returncode,'HTTP_status':status,'headers':headers,'HTTP_header_bytes':header_bytes,'HTTP_body_bytes':size,'curl_stderr':stderr.decode(errors='replace'),'stderr_bytes_retained':len(stderr),'error':error,'actual_seconds':time.monotonic()-started,'no_auth_config_proxy_redirect_retry':True,'curl_certificate_validation':'installed curl default TLS verification; no insecure/custom-CA flags or inherited CA/proxy environment; not a synthetic ssl_verify_result field','curl_child_reaped':child.poll() is not None}))
 return 1 if error or child.returncode else 0
if __name__=='__main__':raise SystemExit(main())
