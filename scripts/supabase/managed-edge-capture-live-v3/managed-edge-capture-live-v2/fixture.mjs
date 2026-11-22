// Invented responses only. This module has no network access.
import {createHash} from 'node:crypto';
import {CaptureError,SLUGS} from './seal.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
export function fixtureTransport(behavior,signal){
 let calls=0;const bodies=SLUGS.map(s=>Buffer.from(`--fixture-boundary\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n{"entrypoint_path":"index.ts"}\r\n--fixture-boundary\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\n\r\nsynthetic-private-source-${s}\r\n--fixture-boundary--\r\n`));
 return {bodies,transport:{
  async project(){
   if(behavior==='hang'||behavior==='ignore_abort')await new Promise((resolve,reject)=>{
    const timer=setInterval(()=>{},1000);if(behavior==='hang'){const stop=()=>{clearInterval(timer);reject(new CaptureError('CAPTURE_INTERRUPTED'));};
     if(signal?.aborted)stop();else signal?.addEventListener('abort',stop,{once:true});}
   });
   return {id:'rrlduytparvsjfmegalh',ref:behavior==='wrong_project'?'wrong':'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'};
  },
  async metadata(slug){const i=SLUGS.indexOf(slug);calls++;let text=JSON.stringify({slug,status:'ACTIVE',id:['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc'][i],
   version:1,updated_at:100+i,verify_jwt:behavior==='metadata_drift'&&calls===2?false:true,ezbr_sha256:sha(bodies[i]),unselected:behavior==='other_metadata_drift'&&calls===2?'changed-canary':'synthetic-canary'});
   if(behavior==='numeric_precision_drift')text=text.slice(0,-1)+',"other_number":900719925474099'+(calls===2?'3':'2')+'}';return Buffer.from(text);},
  async body(slug){if(behavior==='error_body')return {body:Buffer.from('{"error":"synthetic"}'),contentType:'application/json'};
   return {body:bodies[SLUGS.indexOf(slug)],contentType:'multipart/form-data; boundary=fixture-boundary'};}
 }};
}
