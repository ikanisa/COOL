// Bind extracted facts to complete, contextual tokens in the admitted source.
import {containsAny,escape,lower,markers,present} from './native-auto-source.js';
import {
  clauseAt, contextualQuote, exactQuotedToken, exactTokenAt, monetaryTokens, quotedMinor,
  quotePositions, readAmountEvidence, semanticPrincipalCurrency,
} from './native-auto-amount.js';
import {readTransactionEvidence} from './native-auto-reference.js';

export {markers} from './native-auto-source.js';
export {hasStrongProviderReference,normalizePrefixedTransactionId} from './native-auto-reference.js';

function sourceTime(raw,account,profile){
 if(raw===null)return null;
 let local,instant;
 // Explicit offsets are unambiguous regardless of the account's usual date
 // format. For local dates, the configured day-first order or a day > 12 is
 // required; ambiguous DD/MM and MM/DD text is never silently guessed.
 const parts=/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d{1,3})?(Z|([+-])(\d{2}):(\d{2}))$/.exec(raw);
 if(parts){
  const wall=parts[1]+(parts[2]??'.000').padEnd(4,'0'),stamp=Date.parse(wall+'Z');
  if(!Number.isFinite(stamp)||new Date(stamp).toISOString().slice(0,23)!==wall||Number(parts[5]??0)>23||Number(parts[6]??0)>59)return null;
  const offset=parts[3]==='Z'?0:(Number(parts[5])*60+Number(parts[6]))*(parts[4]==='-'?-1:1);
  return new Date(stamp-offset*60000).toISOString();
 }else{
  const yearFirst=/^(\d{4})([-/])(\d{2})\2(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/.exec(raw);
  const dayFirst=/^(\d{2})([-/])(\d{2})\2(\d{4})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/.exec(raw);
  let year,month,day,h,m,s;
  if(yearFirst&&(profile.date_format==='YMD_HMS'||Number(yearFirst[4])>12)){
   [,year,,month,day,h,m,s]=yearFirst;
  }else if(dayFirst&&(profile.date_format==='DMY_HMS'||Number(dayFirst[1])>12)){
   [,day,,month,year,h,m,s]=dayFirst;
  }else return null;
  // A minute-only source is normalized to the start of that stated minute;
  // transaction_datetime_raw separately preserves the actual precision.
  local=`${year}-${month}-${day}T${h}:${m}:${s??'00'}`;
  const utc=Date.parse(local+'Z');if(!Number.isFinite(utc)||new Date(utc).toISOString().slice(0,19)!==local)return null;
  instant=new Date(utc-profile.utc_offset_minutes*60000);
 }
 const p=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:account.timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(instant).map(part=>[part.type,part.value]));
 return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}`===local?instant.toISOString():null;
}
function direction(kind){return kind==='incoming_receipt'?'incoming':kind==='outgoing'?'outgoing':kind==='reversal'?'reversal':'other';}
function completedOutgoing(text){
 return typeof text==='string'&&(/\byour\s+payment\s+of\b[^.!?\r\n]*\bhas\s+been\s+completed\b/iu.test(text)||
  /\btransferred\s+to\b[^.!?\r\n]*\bfrom\b[^.!?\r\n]*\bat\b/iu.test(text));
}
function contradictoryOutcome(body,value,profile){
 const values=[...markers(profile,'failed'),...markers(profile,'pending'),...markers(profile,'reversal')]
  .map(v=>v.trim().replace(/[.!?;]+$/u,'')).filter(Boolean);
 const statusesPattern=new RegExp(`(?<![\\p{L}\\p{N}_])(?:${[...new Set(values)].sort((a,b)=>b.length-a.length).map(escape).join('|')})(?![\\p{L}\\p{N}_])`,'giu');
 for(const text of body.split(/[.!?;\r\n]+/u)){
  const statuses=[...text.matchAll(statusesPattern)];
  if(!statuses.length||/^\s*(?:if|when|unless|should|in case)\b/iu.test(text))continue;
  if(statuses.every(m=>/\b(?:not|never|no longer)\s+(?:been\s+)?$/iu.test(text.slice(0,m.index))))continue;
  const same=/(?:\b(?:this|that|the|above|your)\s+(?:(?:same|current|above)\s+)?(?:payment|transfer|transaction|receipt|deposit)\b|(?<![\p{L}\p{N}_])(?:cette|cette\s+m[eê]me)\s+(?:transaction|op[eé]ration|paiement)|(?:iki|icyo)\s+(?:gikorwa|kikorwa)|(?:muamala|shughuli)\s+(?:huu|hii))(?![\p{L}\p{N}_])/iu.test(text);
  const principal=typeof value.principal_amount_raw==='string'&&exactQuotedToken(body,text,value.principal_amount_raw)&&
   containsAny(text,markers(profile,value.event_kind));
  const other=/\b(?:different|unrelated|another|previous|earlier|prior|other)(?:[\s,]+(?:different|unrelated|another|previous|earlier|prior|other))*[\s,]+(?:payment|transfer|transaction|receipt|deposit)\b/iu.exec(text);
  if(other&&!same&&(!principal||statuses.every(m=>m.index>=other.index+other[0].length)))continue;
  const statusOnly=statuses.length===1&&/^\s*(?:(?:transaction|payment|transfer|status)\s*[: -]?\s*)?$/iu.test(text.slice(0,statuses[0].index))&&
   /^\s*$/u.test(text.slice(statuses[0].index+statuses[0][0].length));
  if(same||statusOnly||principal)return true;
 }
 return false;
}
function supportedKind(value,body,profile,semantic){
 const kind=value.event_kind,outcome=value.payment_outcome;
 const expected={incoming_receipt:'successful',outgoing:'successful',reversal:'successful',failed:'failed',pending:'pending'};
 if(semantic){
  const effect=value.wallet_effect,required={incoming_receipt:['credit'],outgoing:['debit'],reversal:['credit','debit'],failed:['none'],pending:['none']};
  if(!Object.hasOwn(expected,kind))return {event_kind:kind==='other'?'other':'unknown',payment_outcome:'unknown'};
  if(outcome!==expected[kind]||!required[kind].includes(effect)||!contextualQuote(body,value.evidence.incoming_success,profile)||
   ['incoming_receipt','outgoing'].includes(kind)&&contradictoryOutcome(body,value,profile))
   return {event_kind:'unknown',payment_outcome:'unknown'};
  return {event_kind:kind,payment_outcome:outcome};
 }
 if(Object.hasOwn(expected,kind)){
  if(outcome!==expected[kind]||!containsAny(body,markers(profile,kind)))return {event_kind:'unknown',payment_outcome:'unknown'};
  // Bind a contradictory status to this transaction, not an unrelated prior
  // failure or conditional provider advice elsewhere in the SMS.
  if(['incoming_receipt','outgoing'].includes(kind)&&contradictoryOutcome(body,value,profile))
   return {event_kind:'unknown',payment_outcome:'unknown'};
  // Older extractions sometimes place the completed outgoing wording in the
  // principal quote instead of the historically named incoming-success field.
  const quote=value.evidence.incoming_success;
  const special=kind==='outgoing'&&typeof quote==='string'&&/\b(?:your\s+payment\s+of|transferred\s+to)\b/iu.test(quote);
  const ordinary=present(body,quote)&&containsAny(quote,markers(profile,kind))&&(!special||completedOutgoing(quote));
  const outgoing=kind==='outgoing'&&completedOutgoing(body)&&
   (present(body,value.evidence.principal)&&completedOutgoing(value.evidence.principal)||
    present(body,value.evidence.principal)&&present(body,value.evidence.incoming_success)&&
     /\byour\s+payment\s+of\b/iu.test(value.evidence.principal)&&completedOutgoing(value.evidence.incoming_success)&&
     value.evidence.incoming_success.includes(value.evidence.principal));
  if(!ordinary&&!outgoing)
   return {event_kind:'unknown',payment_outcome:'unknown'};
  return {event_kind:kind,payment_outcome:outcome};
 }
 return {event_kind:kind==='other'?'other':'unknown',payment_outcome:'unknown'};
}

export function projectNativeAutoFacts({ source, account, profile, body, output, semantic }) {
 const identity=supportedKind(output,body,profile,semantic),financial=['incoming_receipt','outgoing','reversal','failed','pending'].includes(identity.event_kind);
 const completedPrincipal=['incoming_receipt','outgoing','reversal'].includes(identity.event_kind);
 const principalEvidence=output.evidence.principal;
 const amount=financial?readAmountEvidence(body,output,profile,'principal',identity.event_kind,semantic):null;
 const currencyEvidence=principalEvidence??(semantic&&!completedPrincipal?output.evidence.incoming_success:null);
 const currency=(amount!==null||semantic&&financial&&!completedPrincipal)&&output.currency_raw!==null&&
  profile.currency_aliases.some(alias=>semantic?lower(alias)===lower(output.currency_raw):alias===output.currency_raw)&&
  (semantic?(amount!==null?semanticPrincipalCurrency(body,principalEvidence,output.currency_raw,amount,profile):
   exactQuotedToken(body,currencyEvidence,output.currency_raw)):present(principalEvidence,output.currency_raw))?account.currency:null;
 const id=readTransactionEvidence(body,output,profile,semantic);
 const otherId=output.original_transaction_id_raw&&output.original_transaction_id_raw.length<=160&&
  !/\s/u.test(output.original_transaction_id_raw)?output.original_transaction_id_raw:null;
 const name=output.payer_name_raw&&present(output.evidence.payer,output.payer_name_raw)?output.payer_name_raw:null;
 const counterparty=output.payer_identifier_raw&&present(output.evidence.payer,output.payer_identifier_raw)?output.payer_identifier_raw:null;
 const rawDate=output.transaction_datetime_raw&&present(output.evidence.transaction_datetime,output.transaction_datetime_raw)?output.transaction_datetime_raw:null;
 const fee=readAmountEvidence(body,output,profile,'fee',identity.event_kind,semantic);
 const balance=readAmountEvidence(body,output,profile,'balance',identity.event_kind,semantic);
 // An incomplete/conflicting new semantic response follows the existing retry
 // path; it must not become a completed transaction with silently lost facts.
 if(semantic&&(completedPrincipal&&(amount===null||currency===null)||
  output.principal_amount_raw!==null&&amount===null||output.currency_raw!==null&&currency===null||
  ['incoming_receipt','outgoing','reversal','failed','pending'].includes(output.event_kind)&&identity.event_kind!==output.event_kind||
  output.transaction_id_raw!==null&&id===null||output.fee_amount_raw!==null&&fee===null||
  output.wallet_balance_after_raw!==null&&balance===null||
  !financial&&[output.principal_amount_raw,output.currency_raw,output.transaction_id_raw].some(value=>value!==null)))
  return null;
 const facts={source_mode:source.source_mode,...identity,provider_transaction_id:id,original_transaction_id:otherId,amount_minor:amount,currency,
  counterparty_name:name,counterparty_identifier:counterparty,transaction_at:sourceTime(rawDate,account,profile),transaction_datetime_raw:rawDate,fee_minor:fee,wallet_balance_after_minor:balance};
 return {direction:direction(identity.event_kind), facts};
}

// Payer identifiers must be the maximal phone-like token in the actual SMS,
// not a substring selected by the model. Separators join adjacent digits or
// masks even when they are not accepted as a phone by the matcher; this makes
// unfamiliar formatting fail closed rather than turning its suffix into an
// independent masked identity. Parentheses enclosing the whole token are
// decorative, but internal punctuation remains part of the token.
const PAYER_IDENTIFIER_TOKEN=/(?<![\p{L}\p{N}_])\+?[0-9*•#xX](?:[0-9*•#xX]|[\s()./,_:+\-\u2010-\u2015]+(?=[0-9*•#xX]))*(?![\p{L}\p{N}_])/gu;
function sourceBoundPayerIdentifier(body,quote,raw){
 if(typeof body!=='string'||typeof quote!=='string'||!quote||typeof raw!=='string'||!raw||raw.trim()!==raw)return false;
 const quoteAt=body.indexOf(quote),rawAt=body.indexOf(raw);
 if(quoteAt<0||quoteAt!==body.lastIndexOf(quote)||rawAt<quoteAt||rawAt!==body.lastIndexOf(raw)||
  rawAt+raw.length>quoteAt+quote.length)return false;
 const leading=raw.match(/^\(+/u)?.[0].length??0,trailing=raw.match(/\)+$/u)?.[0].length??0;
 const core=raw.slice(leading,raw.length-trailing);if(!core)return false;
 const tokens=[...body.matchAll(PAYER_IDENTIFIER_TOKEN)].filter(m=>m.index<quoteAt+quote.length&&
  m.index+m[0].length>quoteAt&&m[0].replace(/[^0-9]/gu,'').length>=3);
 return tokens.length===1&&tokens[0].index===rawAt+leading&&tokens[0][0]===core;
}
// A name used for allocation must be the entire source span between one
// unambiguous direction marker and the already-validated payer identifier.
// Unknown or ambiguous wording remains parsed but cannot identify a member.
const PAYER_DIRECTION=/(?<![\p{L}\p{N}_])(?:from|to|by|par|de|du|kwa|kutoka|kuri|kuva|na|avuye)(?![\p{L}\p{N}_])/giu;
function sourceBoundPayerName(body,quote,name,identifier,principal){
 if(typeof name!=='string'||!name||name.trim()!==name||typeof identifier!=='string'||!identifier||
  typeof quote!=='string'||!quote||typeof principal!=='string'||!principal)return false;
 const quoteAt=body.indexOf(quote),nameAt=body.indexOf(name),idAt=body.indexOf(identifier),amountAt=body.indexOf(principal);
 if(quoteAt<0||nameAt<quoteAt||nameAt!==body.lastIndexOf(name)||idAt<nameAt+name.length||
  amountAt<0||amountAt!==body.lastIndexOf(principal)||amountAt+principal.length>nameAt||
  nameAt+name.length>quoteAt+quote.length||idAt+identifier.length>quoteAt+quote.length)return false;
 const word=c=>Boolean(c)&&/[\p{L}\p{N}\p{M}_]/u.test(c);
 if(word(Array.from(body.slice(0,nameAt)).at(-1))||word(String.fromCodePoint(body.codePointAt(nameAt+name.length)??0)))return false;
 if(!/^[\s().:/+\-\u2010-\u2015]*$/u.test(body.slice(nameAt+name.length,idAt)))return false;
 const markers=[...body.matchAll(PAYER_DIRECTION)].filter(m=>m.index>=amountAt+principal.length&&
  (m.index<nameAt||m.index+m[0].length>nameAt+name.length));
 if(markers.length!==1||markers[0].index+markers[0][0].length>nameAt)return false;
 return /^[\s:()\-\u2010-\u2015]*$/u.test(body.slice(markers[0].index+markers[0][0].length,nameAt));
}
// A literal quote and mutually consistent model fields do not prove that the
// addressed wallet was credited. Automatic incoming classification requires a
// conservative, independently checked source cue in the principal's clause.
// The supported forms below are deliberately narrow; an unfamiliar or mixed
// message cannot become an automatically credited contribution. Retrying and
// display status depend on the worker path. These checks do not certify settlement.
const INCOMING_SOURCE_PREFIX=/^\s*["'“‘]?(?<cue>(?:you\s+(?:(?:have|have\s+been)\s+)?received)|(?:you\s+(?:have\s+been|were)\s+credited)|(?:your\s+(?:wallet|account)\s+(?:(?:has\s+been|was|is)\s+)?(?:credited|received))|received|votre\s+(?:portefeuille|compte)\s+(?:est|a\s+[eé]t[eé]|a\s+ete)\s+cr[eé]dit[eé]|wakiriye|umepokea)(?![\p{L}\p{N}_])[^\p{N}]{0,96}$/iu;
const OUTGOING_SOURCE=/(?<![\p{L}\p{N}_])(?:you\s+(?:have\s+)?(?:sent|paid|withdrawn|cashed\s+(?:in|out))|your\s+(?:(?:mobile[- ]money\s+)?wallet|account)\s+(?:(?:has\s+been|was|is)\s+)?debit(?:ed)?|cash|cash[- ]?out|withdraw(?:al|n|ing)?|from\s+your\s+wallet|(?:transferred|transfer)\s+to|your\s+payment\s+of|outgoing\s+(?:payment|transfer|transaction)|vous\s+avez\s+(?:envoy[eé]|transf[eé]r[eé]|retir[eé]|remis|pay[eé])|votre\s+(?:portefeuille|compte)\s+(?:est|a\s+[eé]t[eé])\s+d[eé]bit[eé]|retrait|wohereje|wishyuye|wabikuje|wabikuye|umetuma|umelipa|umetoa)(?![\p{L}\p{N}_])/iu;
// Receiving an instruction, request or notice is not the same as receiving
// wallet value. Unknown wording around the number is not accepted as proof.
const NON_CREDIT_CONTEXT=/(?<![\p{L}\p{N}_])(?:not|never|no|request|requested|requesting|message|sms|notification|notice|instruction|invitation|demand|invoice|send|sending|pay|paying|withdraw|withdrawing|cash|demande|requ[eê]te|invitation|ubusabe|gusaba)(?![\p{L}\p{N}_])/iu;
const ANCILLARY_LABEL=/^\s*(?:(?:(?:remaining|wallet)\s+)?(?:balance|solde|asigaye|salio|fees?|charges?|frais|komisiyo|ada)(?:\s+(?:remaining|restant|restante))?|your\s+(?:wallet\s+)?balance\s+is|balance\s+after\s+this\s+transaction\s+is)\s*[:=]?\s*$/iu;
// These are only the narrow source forms exercised below, not an assertion
// about every carrier message or a proof of actual provider settlement. Bare
// "Received" does not identify a wallet; treating it as a wallet receipt is
// the selected product inference, not verification of settlement.
const RECEIPT_CLAUSES=[
 {lead:/^(?:you\s+(?:have\s+)?received|received)\s*$/iu,connector:/^from\s+/iu},
 {lead:/^your\s+(?:wallet|account)\s+(?:has\s+been|was|is)\s+credited(?:\s+(?:with|by))?\s*$/iu,connector:/^from\s+/iu},
 {lead:/^votre\s+(?:portefeuille|compte)\s+(?:est|a\s+[eé]t[eé]|a\s+ete)\s+cr[eé]dit[eé]\s+de\s*$/iu,connector:/^par\s+/iu},
 {lead:/^wakiriye\s*$/iu,connector:/^uhawe\s+na\s+/iu},
 {lead:/^umepokea\s*$/iu,connector:/^kutoka\s+/iu},
];
const RECEIPT_PARTY_NAME=/^\p{Lu}[\p{L}\p{M}'’\-]*(?:\s+(?:(?:de(?:\s+la)?|van(?:\s+der)?|der)\s+)?\p{Lu}[\p{L}\p{M}'’\-]*){0,3}(?:\s+&\s+Sons)?$/u;
const RECEIPT_PARTY_ID=/^[+0-9*•xX# ().\-]{3,32}$/u;
// The model may omit a later sentence entirely. Reject explicit denials,
// addressed-wallet debits and reversals in the whole source, in the limited
// language forms we can independently recognize. Unrecognized statements are
// also held below; these markers are not a universal language classifier.
const CONTRADICTS_CREDIT=/(?<![\p{L}\p{N}_])(?:(?:not|never|no|without|wasn['’]t|isn['’]t|hasn['’]t|haven['’]t)[^.!?;\r\n]{0,80}(?:credit(?:ed)?|deposit(?:ed)?|receiv(?:ed|e)|funds|money)|(?:credit|deposit|receipt|funds)[^.!?;\r\n]{0,80}(?:was\s+not|were\s+not|not\s+(?:been\s+)?(?:credited|received|applied)|never\s+(?:been\s+)?(?:credited|received|applied))|(?:wallet|account|balance)[^.!?;\r\n]{0,80}(?:debit(?:ed)?|deducted|withdrawn)|reversal|reversed|chargeback|refunded|pas[^.!?;\r\n]{0,80}cr[eé]dit[eé]|(?:portefeuille|compte|solde)[^.!?;\r\n]{0,80}d[eé]bit[eé]|annulation|ntiyashyizwemo|ntiyinjijwemo|ntiwakiriye|ntiyageze|yakuwe\s+kuri\s+konti|yabikujwe|cyarasubijwe|yarasubijwe|haikuongezewa|haijaongezewa|haijapokelewa|limekatwa|imetolewa|imerejeshwa)(?![\p{L}\p{N}_])/iu;
const META_REFERENCE=/^\s*(?:(?:transaction|transfer|transfert|op[eé]ration|igikorwa|muamala|shughuli|txn|tx|ft)\s*(?:id|no|n[°º]|number|num[eé]ro|nimero|nambari|namba|reference|r[eé]f(?:\.|[eé]rence)?|code|#)|(?:id|reference|r[eé]f(?:\.|[eé]rence)?|num[eé]ro\s+d['’]op[eé]ration|n[°º]\s*op[eé]ration|nimero\s+y['’]igikorwa|kumbukumbu))\s*[:#=\-]?\s*(?=[a-z0-9/\-]*[0-9])[a-z0-9]{1,32}(?:[/-][0-9]{1,32})?\s*$/iu;
const META_DATE=/^\s*(?:at|date|time|on)\s+\d{2,4}[-/]\d{2}[-/]\d{2,4}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?\s*$/iu;
function sourceStatements(body){
 const parts=[];const separator=/(?:(?<!r[eé]f)(?:\.(?!\d)|(?<!\d)\.)|[!?;\r\n])+/giu;
 let start=0;for(const m of body.matchAll(separator)){parts.push({start,end:m.index,text:body.slice(start,m.index)});start=m.index+m[0].length;}
 parts.push({start,end:body.length,text:body.slice(start)});return parts;
}
function otherStatementsSupported(body,principalAt,profile){
 const seen=new Set();
 for(const part of sourceStatements(body)){
  const text=part.text.trim();if(!text)continue;
  const amounts=monetaryTokens(text,profile);
  if(CONTRADICTS_CREDIT.test(text))return false;
  if(principalAt>=part.start&&principalAt<part.end){
   if(/\b(?:but|however|instead|except|although|yet|and|also|while)\b/iu.test(text))return false;
   continue;
  }
  if(amounts.length===1){
   const token=amounts[0],label=text.slice(0,token.at);
   if(ANCILLARY_LABEL.test(label)&&/^\s*$/u.test(text.slice(token.end))){
    const role=/\b(?:balance|solde|asigaye|salio)\b/iu.test(label)?'balance':'fee';
    if(seen.has(role))return false;seen.add(role);continue;
   }
  }
  const role=META_REFERENCE.test(text)?'reference':META_DATE.test(text)?'date':null;
  if(role){if(seen.has(role))return false;seen.add(role);continue;}
  return false;
 }
 return true;
}
function conflictingOutgoing(body,profile){
 // Any outgoing source language is unsupported in the incoming grammar,
 // including text that purports to describe a different transaction.
 for(const part of body.split(/(?:\.(?!\d)|(?<!\d)\.|[!?;\r\n])+/u)){
  const configured=(profile.outgoing_markers??[]).filter(s=>typeof s==='string'&&s.trim().length>=5);
  if(OUTGOING_SOURCE.test(part)||containsAny(part,configured))return true;
 }
 return false;
}
function supportedReceiptClause(body,value,token){
 const statement=sourceStatements(body).find(part=>token.at>=part.start&&token.at<part.end);
 if(!statement||token.end>statement.end)return false;
 const lead=body.slice(statement.start,token.at).trim(),tail=body.slice(token.end,statement.end).trim();
 const form=RECEIPT_CLAUSES.find(item=>item.lead.test(lead));if(!form)return false;
 const connection=form.connector.exec(tail);if(!connection)return false;
 const name=value.payer_name_raw,id=value.payer_identifier_raw;
 if(typeof name!=='string'||!RECEIPT_PARTY_NAME.test(name)||name!==name.trim()||
  id!==null&&(typeof id!=='string'||!RECEIPT_PARTY_ID.test(id)||id!==id.trim()))return false;
 const party=tail.slice(connection[0].length);
 if(id===null?party!==name:party!==`${name} ${id}`&&party!==`${name} (${id})`)return false;
 const phrase=connection[0]+party,phraseAt=body.indexOf(phrase,token.end);
 if(phraseAt<token.end||phraseAt+phrase.length>statement.end)return false;
 // The quoted payer must cover the complete source party, so an initial model
 // fragment cannot stand in for an omitted qualifier after a name/number.
 return quotePositions(body,value.evidence.payer).some(span=>span.at<=phraseAt&&span.end>=phraseAt+phrase.length);
}
function supportedIncomingSource(body,value,profile){
 const raw=value.principal_amount_raw,quote=value.evidence.principal,direction=value.evidence.incoming_success;
 const amount=quotedMinor(raw,profile);
 if(amount===null||amount<=0||!present(body,quote)||!present(body,direction)||conflictingOutgoing(body,profile))return false;
 for(const principal of quotePositions(body,quote)){
  for(let i=quote.indexOf(raw);i!==-1;i=quote.indexOf(raw,i+1)){
   const at=principal.at+i;if(!exactTokenAt(quote,i,raw)||!exactTokenAt(body,at,raw))continue;
   const clause=clauseAt(body,at),before=body.slice(clause.start,at);
   const match=INCOMING_SOURCE_PREFIX.exec(before);if(!match||NON_CREDIT_CONTEXT.test(before.slice(before.indexOf(match.groups.cue)+match.groups.cue.length)))continue;
   if(!otherStatementsSupported(body,at,profile))continue;
   // A second unlabelled amount may be a separate transaction or an
   // adversarial quote in another language. Do not guess which event the AI
   // meant. Only standalone labeled fee/balance fields are ancillary.
   const sourceAmounts=monetaryTokens(body,profile);
   const current=sourceAmounts.find(token=>token.at<=at&&token.end>=at+raw.length&&token.value===amount);
   if(!current||!supportedReceiptClause(body,value,current))continue;
   if(sourceAmounts.some(token=>{
    if(token.at===current.at&&token.end===current.end)return false;
    const other=clauseAt(body,token.at),before=body.slice(other.start,token.at),after=body.slice(token.end,other.end);
    // An arbitrary clause containing the word "balance" or "fee" is not
    // enough: only a standalone labelled value is an ancillary amount.
    if(ANCILLARY_LABEL.test(before)&&/^\s*$/u.test(after))return false;
    return true;
   }))continue;
   // The direction quote must actually cover the source prefix in the same
   // clause, not just repeat a similarly worded earlier or later event.
   const cueAt=clause.start+before.indexOf(match.groups.cue);
   if(quotePositions(body,direction).some(span=>span.at<=cueAt&&span.end>=cueAt+match.groups.cue.length))return true;
  }
 }
 return false;
}

// A supported receipt must retain both complete payer spans before and after
// removal of unrelated safety advice. This layer supplies evidence only.
export function proveIncomingSource(body, original, value, profile) {
  const {payer_name_raw: name, payer_identifier_raw: id, principal_amount_raw: amount} = value;
  const quote = value.evidence.payer;
  return supportedIncomingSource(body, value, profile) &&
    sourceBoundPayerIdentifier(body, quote, id) && sourceBoundPayerIdentifier(original, quote, id) &&
    sourceBoundPayerName(body, quote, name, id, amount) && sourceBoundPayerName(original, quote, name, id, amount);
}
