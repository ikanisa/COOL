#!/usr/bin/env python3
"""Bind source-derived artifact names to primary public object metadata only."""
import concurrent.futures,datetime,hashlib,json,urllib.error,urllib.parse,urllib.request
from pathlib import Path
P=Path(__file__).resolve().parent
O=P/"public-origin"
engine=(O/"engine.version").read_text().strip()
assert engine=="a10d8ac38de835021c8d2f920dbf50a920ccc030"
# Exact archive names follow pinned source branches; no latest/cache guessing.
names=["sky_engine.zip","flutter_gpu.zip","flutter_patched_sdk.zip","flutter_patched_sdk_product.zip","darwin-arm64/artifacts.zip","darwin-arm64/font-subset.zip"]
names += ["android-"+arch+"-"+mode+"/darwin-x64.zip" for arch in ["arm","arm64","x64"] for mode in ["profile","release"]]
def fetch(name):
 object_name="flutter/"+engine+"/"+name
 url="https://storage.googleapis.com/storage/v1/b/flutter_infra_release/o/"+urllib.parse.quote(object_name,safe="")
 file="engine-object-"+name.replace("/","_").replace(".zip","")+".json"
 row={"artifact_url":"https://storage.googleapis.com/flutter_infra_release/"+object_name,"object_metadata_url":url,"source_archive_name":name,"fetched_utc":datetime.datetime.now(datetime.timezone.utc).isoformat()}
 try:
  with urllib.request.urlopen(urllib.request.Request(url,headers={"User-Agent":"COOL-public-origin-audit/1"}),timeout=35) as r:
   body=r.read(65537)
   if len(body)>65536:raise ValueError("metadata exceeds bound")
   obj=json.loads(body);assert obj["name"]==object_name and obj["bucket"]=="flutter_infra_release"
   (O/file).write_bytes(body)
   row.update({"http_status":r.status,"retained_file":file,"bytes":len(body),"sha256":hashlib.sha256(body).hexdigest(),"metadata":{"generation":obj.get("generation"),"size":obj.get("size"),"md5Hash":obj.get("md5Hash"),"crc32c":obj.get("crc32c"),"custom_metadata":obj.get("metadata")}})
 except Exception as e:
  row.update({"error_type":type(e).__name__,"error":str(e),"http_status":getattr(e,"code",None)})
 return name,row
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 rows=dict(pool.map(fetch,names))
result={"engine_revision":engine,"source_commit":"ad70ec4617166f1c38e5d2bfd388af71fda14f06","source_bindings":{"base_url":"cache.dart:1033-1046","packages":"flutter_cache.dart:264","common_host":"flutter_cache.dart:266-282","font_subset":"flutter_cache.dart:775-790","android_gen_snapshot":"flutter_cache.dart:388-400,896-902"},"host_branch":"macOS arm64; all-platform override disabled; Android snapshot host archives intentionally darwin-x64 per exact upstream source","objects":rows,"scope":"Primary object metadata only; standalone bodies not downloaded or authenticated. MD5/CRC32C fields are publisher metadata, not independent SHA256/signature proof or execution/ABI acceptance."}
(P/"engine-artifact-origin-map.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
print(json.dumps({"objects":len(rows),"http_200":sum(r.get("http_status")==200 for r in rows.values()),"errors":[n for n,r in rows.items() if "error" in r]}))
