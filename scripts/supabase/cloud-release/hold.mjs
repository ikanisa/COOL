// Owner-authorized maintenance hold, retaining exact previous function bodies.
import {writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {connect,management,record,ROOT,PROJECT,sha} from './access.mjs';

const operation=randomUUID(),slugs=['collect-api','admin-api','collect-jobs'];
const before=(await management('functions')).json().filter(x=>slugs.includes(x.slug));
if(before.length!==3||before.some(x=>x.status!=='ACTIVE'))throw Error('unexpected_function_state');
record('hold-intent.json',{operation,project:PROJECT,before,at:new Date().toISOString()});
for(const f of before){
 const body=(await management('functions/'+f.slug+'/body')).bytes;
 writeFileSync(ROOT+'/'+f.slug+'-previous.bundle',body,{flag:'wx',mode:0o600});
 record(f.slug+'-previous.json',{...f,downloadSha256:sha(body)});
}
const c=await connect();
try{
 const status=(await c.query('select private.collect_fence_owner_status_v3() value')).rows[0].value;
 if(status.mode!=='open'||status.epoch!==13||status.schedulerStatus.blocking!==false)throw Error('unexpected_fence_preimage');
 if((await c.query('select count(*)::int n from supabase_migrations.schema_migrations')).rows[0].n!==14)throw Error('history_changed');
 record('hold-fence-before.json',status);
 const quiesce=(await c.query('select private.collect_fence_begin_quiesce($1,$2,$3) value',[operation,status.epoch,status.sourceSha256])).rows[0].value;
 record('hold-fence-committed.json',quiesce);
}finally{await c.end();}
const source=`Deno.serve(() => Response.json({code:"maintenance",message:"BuriMunsi is moving to Supabase Cloud. Please try again shortly.",release:"${operation}"},{status:503,headers:{"Retry-After":"300","Cache-Control":"no-store"}}));`;
record('maintenance-handler.ts',source);
const after=[];
for(const slug of slugs){
 record(slug+'-hold-attempt.json',{operation,slug,sourceSha256:sha(source),at:new Date().toISOString()});
 const form=new FormData();form.append('metadata',JSON.stringify({name:slug,entrypoint_path:'index.ts',verify_jwt:false}));
 form.append('file',new Blob([source],{type:'application/typescript'}),'index.ts');
 const f=(await management('functions/deploy?slug='+slug,{method:'POST',body:form})).json();
 if(f.slug!==slug||f.status!=='ACTIVE'||f.version<=before.find(x=>x.slug===slug).version)throw Error('deployment_unconfirmed');
 record(slug+'-hold-result.json',{...f,observedAt:new Date().toISOString()});after.push(f);
}
const check=(await management('functions')).json();
if(after.some(f=>!check.some(x=>x.slug===f.slug&&x.id===f.id&&x.version===f.version&&x.ezbr_sha256===f.ezbr_sha256)))throw Error('function_readback_mismatch');
const at=new Date().toISOString();
record('hold-complete.json',{operation,project:PROJECT,before,after,verifiedAt:at,maximumWorkerLifetimeSeconds:400,
 retirementNotBefore:new Date(Date.parse(at)+500000).toISOString(),externalEffectsSettled:false});
console.log(JSON.stringify({status:'cloud_maintenance_hold',functions:after.map(x=>({slug:x.slug,version:x.version})),retirementNotBefore:new Date(Date.parse(at)+500000).toISOString(),externalEffectsSettled:false}));
