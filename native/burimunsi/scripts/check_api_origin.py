#!/usr/bin/env python3
"""Read-only protocol probe. No credentials, pairing, SMS upload or money writes.
Run only against an explicitly selected deployment; preserves exact route origin.
"""
import argparse,json,urllib.request,urllib.error,urllib.parse,hashlib,datetime
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None
p=argparse.ArgumentParser();p.add_argument('--origin',required=True);p.add_argument('--path',action='append',required=True);a=p.parse_args()
u=urllib.parse.urlsplit(a.origin)
if u.scheme!='https' or not u.hostname or u.username or u.password or u.query or u.fragment or u.path not in ('','/'):raise SystemExit('Exact HTTPS origin required')
results=[];opener=urllib.request.build_opener(NoRedirect)
for path in a.path:
 if not path.startswith('/') or path.startswith('//') or any(x in path for x in ('\\','#','?')):raise SystemExit('Invalid explicit path')
 target=a.origin.rstrip('/')+path
 try:
  try:response=opener.open(urllib.request.Request(target,headers={'Accept':'application/json'}),timeout=15)
  except urllib.error.HTTPError as e:response=e
  with response:
   body=response.read(65537);ct=response.headers.get('Content-Type','');status=response.status
  valid=False
  if len(body)<=65536 and ct.lower().startswith('application/json'):
   try:json.loads(body);valid=True
   except (ValueError,UnicodeError):pass
  results.append({'path':path,'status':status,'contentType':ct,'json':valid,'htmlFallback':b'<html' in body.lower() or b'<!doctype' in body.lower(),'bodySha256':hashlib.sha256(body).hexdigest(),'qualification':'unauthenticated read only; does not prove pairing/posting'})
 except Exception as e:results.append({'path':path,'transportError':type(e).__name__})
print(json.dumps({'origin':a.origin,'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'results':results},indent=2))
