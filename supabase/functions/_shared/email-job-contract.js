const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const exact=(value,keys)=>object(value)&&Object.keys(value).sort().join(',')===[...keys].sort().join(',');
const sha=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
export function parseEmailJobDispatch(value){
 if(!exact(value,['dispatch_id','email_admission'])||! /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value.dispatch_id??''))throw new TypeError('Invalid email dispatch');
 const a=value.email_admission;
 if(!exact(a,['contract','source_sha256','approval_sha256','admitted_from','batch_limit'])||a.contract!=='collect.contribution-email.v1'||!sha(a.source_sha256)||!sha(a.approval_sha256)||!Number.isSafeInteger(a.admitted_from)||a.admitted_from<1||a.batch_limit!==1)throw new TypeError('Invalid email admission');
 return {dispatchId:value.dispatch_id,admission:{...a}};
}
export function emailJobResult(result){
 if(!object(result)||result.status!=='complete'||!Number.isSafeInteger(result.processed)||result.processed<0||result.processed>1||!Array.isArray(result.results)||result.results.length!==result.processed||result.results.some(row=>!object(row)||!['accepted','unknown','suppressed'].includes(row.state)))return {status:'unconfirmed',processed:0,results:[]};
 return {status:'complete',processed:result.processed,results:result.results.map(row=>({state:row.state,delivery_confirmed:false}))};
}
