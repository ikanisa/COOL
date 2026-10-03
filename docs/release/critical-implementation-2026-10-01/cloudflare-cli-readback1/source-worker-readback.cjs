'use strict';
// Independent read of the source-named Worker after account discovery succeeded.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const OUT=__dirname,ROOT='/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL';
const previous=JSON.parse(fs.readFileSync(path.join(OUT,'readback.json'),'utf8'));
const account=previous.providerReads[0]?.facts?.accountIds?.[0];
if(!/^[a-f0-9]{32}$/.test(account)) throw new Error('verified_account_required');
const text=fs.readFileSync('/Users/jeanbosco/Library/Preferences/.wrangler/config/default.toml','utf8');
const token=(text.match(/^\s*oauth_token\s*=\s*"([^"\n]+)"/m)||[])[1];
const expiration=(text.match(/^\s*expiration_time\s*=\s*"([^"\n]+)"/m)||[])[1];
if(!token || Date.parse(expiration)<=Date.now()) throw new Error('unexpired_existing_credential_required');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const clean=s=>String(s).replaceAll(token,'[REDACTED]').replace(/[\w.+-]+@[\w.-]+\.[a-z]{2,}/gi,'[EMAIL REDACTED]').slice(0,300);
const started=Date.now(),deadline=started+45000;
const inputs=previous.sourceInputsBefore.map(x=>({path:x.path,sha256:sha(fs.readFileSync(path.join(ROOT,x.path)))}));
const report={schema:'collect-source-worker-readonly-v1',startedAt:new Date(started).toISOString(),accountId:account,accountDiscoveryReceiptSha256:sha(fs.readFileSync(path.join(OUT,'readback.json'))),service:'collect-public',targetHostname:'collect.ikanisa.com',priorDomainRead:'403 Authentication error code10000',existingOAuthUnexpiredAtStart:true,tokenCaptured:false,authRefreshed:false,readOnly:true,runtime:{path:process.execPath,version:process.version,sha256:sha(fs.readFileSync(process.execPath)),scriptSha256:sha(fs.readFileSync(__filename))},sourceInputsBefore:inputs,providerReads:[],criteriaRetained:previous.criteriaRetained,status:'pending',limitations:[]};
async function get(endpoint,filter){
 const receipt={method:'GET',endpoint,startedAt:new Date().toISOString()};report.providerReads.push(receipt);
 try{
  const remaining=deadline-Date.now();if(remaining<=0)throw new Error('total_deadline_reached');
  const res=await fetch('https://api.cloudflare.com/client/v4'+endpoint,{method:'GET',redirect:'error',headers:{Authorization:'Bearer '+token,Accept:'application/json'},signal:AbortSignal.timeout(Math.min(10000,remaining))});
  receipt.httpStatus=res.status;const chunks=[];let bytes=0;for await(const c of res.body){bytes+=c.length;if(bytes>524288)throw new Error('response_byte_bound_exceeded');chunks.push(c);}
  const body=Buffer.concat(chunks);receipt.responseBytes=body.length;receipt.responseSha256=sha(body);
  const data=JSON.parse(body.toString('utf8'));receipt.providerSuccess=data.success===true;receipt.errors=(data.errors||[]).slice(0,5).map(e=>({code:e.code,message:clean(e.message)}));
  if(res.ok&&data.success===true)receipt.facts=filter(data.result);
 }catch(e){receipt.error={name:clean(e.name),message:clean(e.message)};}
 receipt.finishedAt=new Date().toISOString();return receipt;
}
(async()=>{
 const [deployments,zones]=await Promise.all([
  get(`/accounts/${account}/workers/scripts/collect-public/deployments?per_page=5`,r=>({deployments:(r?.deployments||[]).slice(0,5).map(d=>({id:d.id,createdOn:d.created_on,source:d.source,strategy:d.strategy,versions:(d.versions||[]).map(v=>({versionId:v.version_id,percentage:v.percentage}))}))})),
  get('/zones?name=ikanisa.com&per_page=50',r=>({zones:(Array.isArray(r)?r:[]).filter(z=>z.name==='ikanisa.com').map(z=>({id:z.id,name:z.name,status:z.status,accountId:z.account?.id}))}))
 ]);
 report.activeDeployment=deployments.facts?.deployments?.[0]||null;
 report.routeMappings=[];
 for(const zone of (zones.facts?.zones||[]).slice(0,2)){
  if(zone.accountId!==account || !/^[a-f0-9]{32}$/.test(zone.id))continue;
  const routes=await get(`/zones/${zone.id}/workers/routes`,r=>({targetRelevantRoutes:(Array.isArray(r)?r:[]).filter(x=>typeof x.pattern==='string'&&(x.pattern.includes('collect.ikanisa.com')||x.pattern.includes('*.ikanisa.com')||x.pattern.includes('*ikanisa.com'))).map(x=>({id:x.id,pattern:x.pattern,script:x.script||null}))}));
  report.routeMappings.push({zoneId:zone.id,...routes.facts});
 }
 report.status=report.activeDeployment?'source_worker_active_deployment_read_back':'source_worker_deployment_unverified';
 report.limitations.push('Worker deployment identity alone cannot bind the collect.ikanisa.com hostname or establish local batch4 asset equality.');
 report.limitations.push('The preceding custom-domain API read was403. Any route records here are independently read, not a replacement claim of custom-domain success.');
})().catch(e=>{report.status='readback_error';report.limitations.push(clean(e.message));}).finally(()=>{
 report.finishedAt=new Date().toISOString();report.durationMilliseconds=Date.now()-started;
 report.sourceInputsAfter=inputs.map(x=>({path:x.path,sha256:sha(fs.readFileSync(path.join(ROOT,x.path)))}));
 report.selectedInputsByteStable=JSON.stringify(inputs)===JSON.stringify(report.sourceInputsAfter);
 report.providerStateMutated=false;report.bounds={maximumRequestMilliseconds:10000,totalDeadlineMilliseconds:45000,responseBytes:524288,method:'GET only',redirects:false,retries:false,zoneLimit:2};
 fs.writeFileSync(path.join(OUT,'source-worker-readback.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({status:report.status,activeDeployment:report.activeDeployment,routeMappings:report.routeMappings,providerReads:report.providerReads.map(x=>({endpoint:x.endpoint,httpStatus:x.httpStatus,providerSuccess:x.providerSuccess,errors:x.errors})),selectedInputsByteStable:report.selectedInputsByteStable,durationMilliseconds:report.durationMilliseconds},null,2));
});
