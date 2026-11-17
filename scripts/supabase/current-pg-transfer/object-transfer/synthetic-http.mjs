// Test-only protocol. It accepts only an explicit loopback synthetic plan and
// does not model Supabase authentication, versioning or API semantics.
export function syntheticAdapters(p){
 if(p?.mode!=='synthetic')throw Error('synthetic_only');
 for(const endpoint of [p.source.origin,p.target.origin]){
  const u=new URL(endpoint);if(u.protocol!=='http:'||u.hostname!=='127.0.0.1'||!u.port||u.origin!==endpoint)throw Error('synthetic_only');
 }
 const meta={...p.source,identity_sha256:p.authority.source_identity_sha256,fence_sha256:p.authority.source_fence_sha256};
 const targetMeta={origin:p.target.origin,bucket:p.target.bucket,key:p.target.key,identity_sha256:p.authority.target_identity_sha256,
  fence_sha256:p.authority.target_fence_sha256,namespace_sha256:p.target.namespace_sha256,private_bucket:true};
 const fetchOk=async(url,options)=>{const r=await fetch(url,options);if(r.status!==200)throw Error('synthetic_status');return r;};
 return {
  source:{async read({signal}){const r=await fetchOk(p.source.origin+'/source',{signal});return {...meta,body:Buffer.from(await r.arrayBuffer())};},
   async inspect({signal}){await fetchOk(p.source.origin+'/source-meta',{signal});return {...meta};}},
  target:{async inspect({signal}){const r=await fetch(p.target.origin+'/target',{signal});if(r.status===404)return {...targetMeta,state:'absent',absence_verified:true};
    if(r.status!==200)throw Error('synthetic_status');return {...targetMeta,state:'present',object_id:'synthetic-target',version:'synthetic-version',etag:'synthetic-etag',body:Buffer.from(await r.arrayBuffer())};},
   async createOnly(data,{signal}){const r=await fetch(p.target.origin+'/target',{method:'PUT',headers:{'if-none-match':'*'},body:data,signal});await r.body?.cancel();return {accepted:r.status===201};}}
 };
}
