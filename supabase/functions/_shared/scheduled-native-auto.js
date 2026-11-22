// The jobs endpoint returns bounded metadata, never a message, identity or
// extracted facts. Unknown outcomes cannot be reported as completed work.
export function nativeAutoProcessingResult(result){
 const allowed=new Set(['completed','security_message','not_claimed','retry','failed']);
 if(!result||result.status!=='complete'||!Number.isSafeInteger(result.processed)||result.processed<0||result.processed>1||
  !Array.isArray(result.results)||result.results.length!==result.processed||
  result.results.some(item=>!item||!allowed.has(item.state)||item.state==='completed'&&!['accepted','duplicate','conflict'].includes(item.relation)))
  return {status:'unconfirmed',code:'native_auto_processing_unconfirmed'};
 if(result.results.some(item=>item.state==='failed'))
  return {status:'unconfirmed',code:'native_auto_provider_unconfirmed',processed:result.processed,results:result.results.map(item=>({state:item.state}))};
 return {status:'complete',processed:result.processed,results:result.results.map(item=>({state:item.state,...(item.state==='completed'?{relation:item.relation}:{})}))};
}
