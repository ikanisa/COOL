/** Strict wire grammar shared by the two separately versioned contracts.
 * Pure code: no credentials, network, persistence, retries or financial effects. */
export class ContractViolation extends Error {
  constructor(code, path='$') { super(code); this.name='ContractViolation'; this.code=code; this.path=path; }
}
export const fail=(code,path='$')=>{throw new ContractViolation(code,path);};
/** This API profile accepts only an optional, single UTF-8 charset parameter.
 * Unknown parameters and ambiguous/duplicate charset declarations fail closed. */
export function isUtf8JsonMediaType(value) {
  return typeof value === 'string' && value.length <= 256 && !/[\r\n]/.test(value) &&
    /^[ \t]*application\/json[ \t]*(?:;[ \t]*charset[ \t]*=[ \t]*(?:utf-8|"utf-8")[ \t]*)?$/i.test(value);
}
export function parseWire(input,maxBytes=2_000_000) {
  let text;
  if(input instanceof Uint8Array){if(input.byteLength>maxBytes)fail('CONTRACT_SIZE');try{text=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(input);}catch{fail('CONTRACT_UTF8');}}
  else {if(typeof input!=='string')fail('CONTRACT_JSON');text=input;if(new TextEncoder().encode(text).byteLength>maxBytes)fail('CONTRACT_SIZE');}
  let p=0,nodes=0;
  const ws=()=>{while(p<text.length&&' \t\r\n'.includes(text[p]))p++;};
  function str(){
    const start=p++;let escaped=false;
    while(p<text.length){const ch=text[p++];if(ch==='"'&&!escaped){
      let value;try{value=JSON.parse(text.slice(start,p));}catch{fail('CONTRACT_JSON');}
      for(let j=0;j<value.length;j++){const x=value.charCodeAt(j);if(x>=0xd800&&x<=0xdbff){const y=value.charCodeAt(++j);if(!(y>=0xdc00&&y<=0xdfff))fail('CONTRACT_UNICODE');}else if(x>=0xdc00&&x<=0xdfff)fail('CONTRACT_UNICODE');}
      return value;
    } if(ch.charCodeAt(0)<32)fail('CONTRACT_JSON');if(ch==='\\'&&!escaped)escaped=true;else escaped=false;}
    fail('CONTRACT_JSON');
  }
  function value(depth){
    if(depth>64||++nodes>100000)fail('CONTRACT_COMPLEXITY');ws();const ch=text[p];
    if(ch==='"')return str();
    if(ch==='{'){
      p++;ws();const out=Object.create(null);if(text[p]==='}'){p++;return out;}
      for(;;){ws();if(text[p]!=='"')fail('CONTRACT_JSON');const key=str();if(Object.hasOwn(out,key))fail('CONTRACT_DUPLICATE_KEY');ws();if(text[p++]!==':')fail('CONTRACT_JSON');out[key]=value(depth+1);ws();const sep=text[p++];if(sep==='}')return out;if(sep!==',')fail('CONTRACT_JSON');}
    }
    if(ch==='['){p++;ws();const out=[];if(text[p]===']'){p++;return out;}for(;;){out.push(value(depth+1));ws();const sep=text[p++];if(sep===']')return out;if(sep!==',')fail('CONTRACT_JSON');}}
    for(const [literal,v] of [['true',true],['false',false],['null',null]])if(text.startsWith(literal,p)){p+=literal.length;return v;}
    const match=/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.slice(p));
    if(!match)fail('CONTRACT_JSON');p+=match[0].length;
    if(!/^-?(0|[1-9][0-9]*)$/.test(match[0])||match[0]==='-0')fail('CONTRACT_NUMBER');
    const number=Number(match[0]);if(!Number.isSafeInteger(number))fail('CONTRACT_NUMBER');return number;
  }
  const result=value(0);ws();if(p!==text.length)fail('CONTRACT_JSON');return result;
}
const isObject=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
function timestamp(v){
 const m=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|([+-])(\d{2}):(\d{2}))$/.exec(v);if(!m)return false;
 const [y,mo,d,h,mi,se]=m.slice(1,7).map(Number);const leap=y%4===0&&(y%100!==0||y%400===0);
 return mo>=1&&mo<=12&&d>=1&&d<=[31,leap?29:28,31,30,31,30,31,31,30,31,30,31][mo-1]&&h<=23&&mi<=59&&se<=59&&(!m[9]||(Number(m[9])<=18&&Number(m[10])<=59&&(Number(m[9])<18||m[10]==='00')));
}
export function validateSchema(defs,name,v,path='$') {
 const schema=defs[name];if(!schema)fail('CONTRACT_OPERATION');
 function visit(s,x,p){
  if(s.$ref)return visit(defs[s.$ref.substring(8)],x,p);
  if(s.anyOf){if(x===null)return;return visit(s.anyOf[0],x,p);}
  const code=s['x-code'];
  const typeOK=({object:isObject(x),array:Array.isArray(x),string:typeof x==='string',boolean:typeof x==='boolean',integer:typeof x==='number'&&Number.isSafeInteger(x)&&!Object.is(x,-0),null:x===null})[s.type];
  if(!typeOK)fail(code??'CONTRACT_TYPE',p);
  if(Object.hasOwn(s,'const')&&x!==s.const)fail(code??'CONTRACT_VALUE',p);
  if(s.enum&&!s.enum.includes(x))fail(code??'CONTRACT_ENUM',p);
  if(s.type==='object'){
   for(const key of s.required??[])if(!Object.hasOwn(x,key))fail('CONTRACT_MISSING_FIELD',p+'.'+key);
   if(Object.keys(x).some(k=>!Object.hasOwn(s.properties,k)))fail('CONTRACT_UNKNOWN_FIELD',p);
   for(const [key,child] of Object.entries(s.properties))if(Object.hasOwn(x,key))visit(child,x[key],p+'.'+key);
  }
  if(s.type==='array'){
   if(x.length<s.minItems||x.length>s.maxItems)fail('CONTRACT_LENGTH',p);
   if(s.uniqueItems&&new Set(x).size!==x.length)fail('CONTRACT_DUPLICATE',p);
   x.forEach((item,index)=>visit(s.items,item,`${p}[${index}]`));
  }
  if(s.type==='string'){
   // Avoid allocating a second multi-megabyte array for bounded import data.
   let length=0;for(const ignored of x)length++;
   if(length<s.minLength||length>s.maxLength||x.includes('\0'))fail(code??'CONTRACT_STRING',p);
   if(s.pattern&&!new RegExp(s.pattern).test(x))fail(code??'CONTRACT_STRING',p);
   if(s.format==='date-time'&&!timestamp(x))fail('CONTRACT_TIMESTAMP',p);
  }
  if(s.type==='integer'&&(x<s.minimum||x>s.maximum))fail(code??'CONTRACT_RANGE',p);
 }
 visit(schema,v,path);return v;
}
export function checkBinding(actual,expected) {
 for(const key of ['ownerId','installationId','operationId','action','requestId','groupId','actorId'])if(Object.hasOwn(expected,key)&&actual[key]!==expected[key])fail('CONTRACT_IDENTITY','$.binding.'+key);
 if(Object.hasOwn(expected,'generation')&&actual.generation!==expected.generation)fail('CONTRACT_GENERATION','$.binding.generation');
 if(Object.hasOwn(expected,'currentGeneration')&&expected.currentGeneration!==expected.generation)fail('CONTRACT_GENERATION','$.binding.generation');
}
export function semantics(product,operation,r,expected={}) {
 checkBinding(r.binding,expected);
 const data=product==='mmoney'?r:r.data;
 if(product==='mmoney'){
  for(const key of ['installationId','generation'])if(Object.hasOwn(r,key)&&r[key]!==r.binding[key])fail(key==='generation'?'CONTRACT_GENERATION':'CONTRACT_IDENTITY','$.'+key);
  if(r.binding.action!==operation)fail('CONTRACT_IDENTITY','$.binding.action');
  if(operation==='state'&&((r.state==='deleted'&&(!r.receiptId||!r.deletedAt))||(r.state==='active'&&('receiptId'in r||'deletedAt'in r))))fail('CONTRACT_STATE');
  if(operation==='ingest'){
   const seen=new Set();for(const ack of r.acknowledgements){
    if(seen.has(ack.id))fail('CONTRACT_DUPLICATE');seen.add(ack.id);
    if(ack.status==='rejected'?(ack.canonicalId!==null||!ack.code):(ack.canonicalId===null||'code'in ack))fail('CONTRACT_ACK');
   }
   if(!Array.isArray(expected.messageIds))fail('CONTRACT_CONTEXT');
   if(new Set(expected.messageIds).size!==expected.messageIds.length||seen.size!==expected.messageIds.length||expected.messageIds.some(id=>!seen.has(id)))fail('CONTRACT_IDENTITY');
  }
  if(operation==='changes'){
   if(typeof expected.cursor!=='string'||!/^(0|[1-9][0-9]{0,18})$/.test(expected.cursor))fail('CONTRACT_CONTEXT');
   let last=BigInt(expected.cursor);const next=BigInt(r.nextCursor);
   for(const change of r.changes){const step=BigInt(change.cursor);if(step<=last||step>next)fail('CONTRACT_CURSOR');last=step;
    const p=change.projection;const outcome=p.posted?'recorded':p.kind==='balance'?'balance_only':'original_only';
    if(change.outcome!==outcome)fail('CONTRACT_STATUS');
    if(p.posted&&(!['received','payment'].includes(p.kind)||p.amount===null||p.amount==='0'||p.currency!=='RWF'))fail('CONTRACT_PROJECTION');
    if(p.totalDebit!==null&&(p.kind!=='payment'||p.amount===null||BigInt(p.totalDebit)<BigInt(p.amount)))fail('CONTRACT_PROJECTION');
   }
   if(last!==next||(!r.changes.length&&r.hasMore))fail('CONTRACT_CURSOR');
  }
 }else{
  function rows(list){const ids=new Set();for(const row of list){if(row.groupId!==r.binding.groupId)fail('CONTRACT_IDENTITY');if(ids.has(row.id))fail('CONTRACT_DUPLICATE');ids.add(row.id);}}
  if(data.items){rows(data.items);if(data.totalCount<data.items.length||(data.nextCursor!==null&&!data.items.length))fail('CONTRACT_PAGE');}
  if(data.recentPayments)rows(data.recentPayments);
  if(data.groupId!==undefined&&data.groupId!==r.binding.groupId)fail('CONTRACT_IDENTITY');
  if(['payment','member','rawSms'].includes(operation)&&data.id!==expected.recordId)fail('CONTRACT_IDENTITY');
  if(operation==='observation'&&data.requestId!==expected.commandRequestId)fail('CONTRACT_IDENTITY');
  if(operation==='observationConsentSet'&&(data.enabled!==expected.consentEnabled||data.generation!==expected.consentGeneration))fail('CONTRACT_IDENTITY');
  if(operation==='observationProfile'&&data.expiresAt-data.issuedAt!==86400000)fail('CONTRACT_STATE');
  if(operation==='observationPage')for(const item of data.items)if(item.id!==item.sourceId)fail('CONTRACT_IDENTITY');
  if(operation==='observationProcessingStatus'){
   if(!Array.isArray(expected.sourceIds)||data.statuses.length!==expected.sourceIds.length||
    data.statuses.some((row,i)=>row.sourceId!==expected.sourceIds[i]||row.canRetry&&!['retrying','needs_review'].includes(row.status)))fail('CONTRACT_IDENTITY');
  }
  if(operation==='observationProcessingRetry'&&(data.sourceId!==expected.recordId||data.requestId!==expected.commandRequestId))fail('CONTRACT_IDENTITY');
  if(operation==='observationReveal'){
   if(data.sourceId!==expected.recordId||Object.hasOwn(data,'displayHints')!==(expected.displayHintsVersion===1))fail('CONTRACT_IDENTITY');
   if(data.displayHints!==undefined&&data.displayHints!==null){const seen=new Set();
    for(const hint of data.displayHints.hints){
     if(seen.has(hint.kind)||hint.start>=hint.end||hint.end>data.rawBody.length||data.rawBody.slice(hint.start,hint.end)!==hint.text||
      hint.start>0&&/[\uDC00-\uDFFF]/.test(data.rawBody[hint.start])||hint.end<data.rawBody.length&&/[\uDC00-\uDFFF]/.test(data.rawBody[hint.end]))fail('CONTRACT_IDENTITY');
     seen.add(hint.kind);
    }
   }
  }
  if(data.profile){if(data.profile.id!==r.binding.actorId)fail('CONTRACT_IDENTITY');if(expected.phone!==undefined&&data.profile.phone!==expected.phone)fail('CONTRACT_IDENTITY');if(expected.now!==undefined&&data.expiresAt<=expected.now)fail('CONTRACT_EXPIRED');}
  if(operation==='allocate'&&(data.transactionId!==expected.recordId||data.memberId!==expected.memberId))fail('CONTRACT_IDENTITY');
  if(operation==='enroll'&&data.phone!==expected.phone)fail('CONTRACT_IDENTITY');
  if(operation==='onboardingSuggestions')for(const row of data.items)if(row.id!==row.candidateId)fail('CONTRACT_IDENTITY');
  if(operation==='membersImport'){
   const seen=new Set(data.results.map(row=>row.row));
   if(data.requestId!==expected.commandRequestId||!Array.isArray(expected.importRows)||
    seen.size!==data.results.length||seen.size!==expected.importRows.length||
    expected.importRows.some(row=>!seen.has(row))||data.created!==data.results.filter(row=>row.status==='created').length||
    data.results.some(row=>(['created','already_registered'].includes(row.status))!==(row.memberId!==null)))fail('CONTRACT_IDENTITY');
  }
  if(operation==='staffUpdate'&&data.id!==expected.staffId)fail('CONTRACT_IDENTITY');
  if(operation==='replace'&&data.requestId!==expected.commandRequestId)fail('CONTRACT_IDENTITY');
  if(operation==='retirementOutcome'){
   if(data.requestId!==expected.recordId||data.fingerprint!==expected.handoffFingerprint)fail('CONTRACT_IDENTITY');
   if(data.state==='retired'?(data.ack===null||data.ack.requestId!==data.requestId):data.ack!==null)fail('CONTRACT_STATE');
  }
  if(['operation','recovery','staffResolution'].includes(operation)&&data.requestId!==expected.recordId)fail('CONTRACT_IDENTITY');
  if(operation==='operation'){
   if(data.actorId!==r.binding.actorId)fail('CONTRACT_IDENTITY');
   if(data.state==='pending'){
    if(data.financialState!=='unresolved'||Object.hasOwn(data,'operation'))fail('CONTRACT_STATE');
   }else{
    if(typeof data.operation!=='string'||data.financialState==='unresolved'||
       (data.operation==='burimunsi.allocate')===(data.financialState==='not_applicable'))fail('CONTRACT_STATE');
   }
  }
  if(['recovery','staffResolution'].includes(operation)){
   if(data.originDigest!==expected.originDigest||data.actorId!==r.binding.actorId||data.installationId!==r.binding.installationId)fail('CONTRACT_IDENTITY');
   if((data.state==='cancelled')!==Object.hasOwn(data,'operation'))fail('CONTRACT_STATE');
   if(operation==='staffResolution'&&(data.state==='pending'||(data.state==='cancelled'&&data.operation!==expected.staffOperation)))fail('CONTRACT_STATE');
  }
  if(operation==='history')for(const row of data.items){
   if(row.transactionId!==expected.recordId)fail('CONTRACT_IDENTITY');
   if(row.kind==='transaction_recorded'?(row.id!=='transaction:'+row.transactionId||row.amountRwf!==null||row.memberId!==null):(!row.id.startsWith('ledger:')||row.amountRwf===null||row.amountRwf===0||row.memberId===null))fail('CONTRACT_STATE');
  }
 }
 return r;
}
export function decodeResponse(profile,defs,operation,status,contentType,input,expected={}) {
 if(!isUtf8JsonMediaType(contentType))fail('CONTRACT_CONTENT_TYPE');
 if(status!==200&&!(status>=400&&status<=599))fail('CONTRACT_HTTP_STATUS');
 const value=parseWire(input);
 // Version is checked before interpreting product-specific fields, never guessed.
 if(!isObject(value)||value.contractVersion!==profile.contractVersion)fail('CONTRACT_VERSION');
 validateSchema(defs,status===200?operation+'.response':'error',value);
 if(status===200)semantics(profile.product,operation,value,expected);
 return value;
}

/** Parse the original query once. URLSearchParams repairs malformed UTF-8, so it
 * must not be the authority at a strict boundary. Values are never logged. */
export function parseQuery(raw) {
 if(typeof raw!=='string')fail('CONTRACT_QUERY');
 if(new TextEncoder().encode(raw).byteLength>8192)fail('CONTRACT_QUERY_SIZE');
 const out=Object.create(null);if(raw==='')return out;
 for(const pair of raw.split('&')){
  const at=pair.indexOf('=');if(at<=0)fail('CONTRACT_QUERY');
  let key,value;try{key=decodeURIComponent(pair.slice(0,at).replaceAll('+',' '));value=decodeURIComponent(pair.slice(at+1).replaceAll('+',' '));}
  catch{fail('CONTRACT_QUERY_ENCODING');}
  for(const valueToCheck of [key,value])for(let i=0;i<valueToCheck.length;i++){
   const ch=valueToCheck.charCodeAt(i);
   if(ch>=0xd800&&ch<=0xdbff){const low=valueToCheck.charCodeAt(++i);if(!(low>=0xdc00&&low<=0xdfff))fail('CONTRACT_QUERY_ENCODING');}
   else if(ch>=0xdc00&&ch<=0xdfff)fail('CONTRACT_QUERY_ENCODING');
  }
  if(Object.hasOwn(out,key))fail('CONTRACT_QUERY_DUPLICATE');
  out[key]=value;
 }
 return out;
}
export function validateQuery(defs,operation,raw) {
 const query=parseQuery(raw);
 try{validateSchema(defs,operation+'.query',query);}
 catch(error){if(error instanceof ContractViolation)fail('CONTRACT_QUERY');throw error;}
 // Existing RecordsService uses UTF-16 code units for its 80-character bound.
 if(typeof query.q==='string'&&query.q.length>80)fail('CONTRACT_QUERY');
 return query;
}
