import hashlib,json,sys,time,urllib.request
start=time.monotonic();h=hashlib.sha256();size=0
try:
 with urllib.request.urlopen(sys.argv[1],timeout=30) as response:
  while True:
   data=response.read(65536)
   if not data:break
   h.update(data);size+=len(data)
 print(json.dumps({'status':'pass' if h.hexdigest()==sys.argv[2] else 'hash_mismatch','bytes':size,'sha256':h.hexdigest(),'elapsed_seconds':round(time.monotonic()-start,3)}))
except Exception as error:
 print(json.dumps({'status':'fail','error_class':type(error).__name__,'bytes':size,'elapsed_seconds':round(time.monotonic()-start,3)}));raise SystemExit(1)
