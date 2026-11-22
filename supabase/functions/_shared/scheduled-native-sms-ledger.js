// A jobs response reports bounded outcomes, never payer or source content.
export function nativeSmsLedgerResult(result){
 const states=new Set(['posted','unmatched','already_posted','not_financial']);
 if(!result||result.status!=='complete'||!Number.isSafeInteger(result.processed)||
  result.processed<0||result.processed>1||!Array.isArray(result.results)||
  result.results.length!==result.processed||result.results.some(item=>!item||!states.has(item.state)))
  return {status:'unconfirmed',code:'native_sms_ledger_unconfirmed'};
 return {status:'complete',processed:result.processed,results:result.results.map(item=>({state:item.state}))};
}
