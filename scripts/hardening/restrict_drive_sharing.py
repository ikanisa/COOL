#!/usr/bin/env python3
"""Owner-operated, read-only-by-default public-link permission containment.
Uses a separately obtained Google OAuth access token; never prints it.
The ChatGPT delivery did NOT execute --apply or change Drive sharing.
"""
import argparse,json,os,re,urllib.request,urllib.error,urllib.parse
DEFAULT_FOLDER='1Bll7zVmvy4afM3HCIRlI4hQELe7NQRSt'
class Drive:
 def __init__(self,token):self.token=token
 def request(self,method,path):
  req=urllib.request.Request('https://www.googleapis.com/drive/v3/'+path,method=method,headers={'Authorization':'Bearer '+self.token})
  try:
   with urllib.request.urlopen(req,timeout=15) as r:
    body=r.read(2_000_001)
    if len(body)>2_000_000:raise RuntimeError('Response exceeds limit')
    return json.loads(body) if body else {}
  except urllib.error.HTTPError as e:
   if method=='DELETE' and e.code==404:return {}
   raise RuntimeError(f'Google permission request failed ({e.code})') from None
 def metadata(self,folder):return self.request('GET',f'files/{folder}?fields=id,mimeType&supportsAllDrives=true')
 def permissions(self,item):
  rows=[];token=None
  while True:
   q={'fields':'permissions(id,type,role),nextPageToken','pageSize':'100','supportsAllDrives':'true'}
   if token:q['pageToken']=token
   data=self.request('GET',f'files/{item}/permissions?'+urllib.parse.urlencode(q));rows.extend(data.get('permissions',[]));token=data.get('nextPageToken')
   if not token:return rows
 def remove(self,item,permission):self.request('DELETE',f'files/{item}/permissions/{permission}?supportsAllDrives=true')
def public_grants(permissions):
 result=[]
 for p in permissions:
  if p.get('type')=='anyone':
   if not isinstance(p.get('id'),str) or not re.fullmatch(r'[A-Za-z0-9_\-]+',p['id']):raise ValueError('Invalid permission identifier')
   if p.get('role')=='owner':raise ValueError('Unexpected public ownership; manual review required')
   result.append({'id':p['id'],'type':'anyone','role':p.get('role')})
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--folder',default=DEFAULT_FOLDER);p.add_argument('--apply',action='store_true');p.add_argument('--confirm-folder');a=p.parse_args()
 if not re.fullmatch(r'[A-Za-z0-9_\-]+',a.folder):raise SystemExit('Invalid folder')
 if a.apply and a.confirm_folder!=a.folder:raise SystemExit('Explicit matching --confirm-folder is required')
 token=os.environ.get('GOOGLE_ACCESS_TOKEN','')
 if not token:raise SystemExit('Owner OAuth GOOGLE_ACCESS_TOKEN is required in the environment; never save it in this repo')
 client=Drive(token);meta=client.metadata(a.folder)
 if meta.get('id')!=a.folder or meta.get('mimeType')!='application/vnd.google-apps.folder':raise SystemExit('Target folder mismatch')
 before=client.permissions(a.folder);remove=public_grants(before)
 if a.apply:
  for r in remove:client.remove(a.folder,r['id'])
  after=client.permissions(a.folder)
  if public_grants(after):raise SystemExit('Public access remains; review required')
  retained={x['id'] for x in after};expected={x['id'] for x in before if x.get('type')!='anyone'}
  if not expected.issubset(retained):raise SystemExit('Named permission changed during operation; investigate')
 print(json.dumps({'status':'ROOT_PUBLIC_GRANTS_REMOVED' if a.apply else 'PLAN_ONLY','folder':a.folder,'public_grants':remove,
  'descendant_explicit_grants_checked':False,'note':'Audit child-specific sharing separately. No named owner/member grants are removed by this script.'},indent=2))
if __name__=='__main__':main()
