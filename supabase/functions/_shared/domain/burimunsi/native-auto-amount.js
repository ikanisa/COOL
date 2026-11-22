import {exactMinor} from '../momo_pipeline.js';
import {containsAny,escape,lower,markers,present} from './native-auto-source.js';

const amountFields={
 principal:['principal_amount_raw','principal'],
 fee:['fee_amount_raw','fee'],
 balance:['wallet_balance_after_raw','wallet_balance_after'],
};

function onePrincipalAmount(body,evidence,raw,profile){
 const expected=quotedMinor(raw,profile);
 if(expected===null||!exactQuotedToken(body,evidence,raw))return false;
 const matches=monetaryTokens(evidence,profile);
 if(matches.length!==1)return false;
 const match=matches[0];
 return exactQuotedToken(body,evidence,match.raw)&&match.value===expected;
}
export function clauseAt(body,at){
 let start=at,end=at;
 while(start>0&&!/[.!?;\r\n]/u.test(body[start-1]))start--;
 while(end<body.length&&!/[.!?;\r\n]/u.test(body[end]))end++;
 return {text:body.slice(start,end),start,end};
}
// Rwanda francs are represented as integer units. A formatted zero fractional
// part can be removed exactly; a nonzero fraction is never rounded. Dotted
// thousands require an explicit comma-zero fraction so an ambiguous token
// such as 1.250 is not silently reinterpreted. Space groupings must consist
// exclusively of complete three-digit groups and remain source-bound.
const WHOLE_RWF_NUMBER='(?:(?:[1-9][0-9]{0,2}(?:\\.[0-9]{3})+|[1-9][0-9]{0,2}(?:[ \\u00a0\\u202f][0-9]{3})+|0|[1-9][0-9]*),0{1,2}|(?:[1-9][0-9]{0,2}(?:,[0-9]{3})+|0|[1-9][0-9]*)\\.0{1,2}|(?:[1-9][0-9]{0,2}(?:[ \\u00a0\\u202f][0-9]{3})+|[1-9][0-9]{0,2}(?:,[0-9]{3})+|0|[1-9][0-9]*))';
function exactWholeRwf(raw){
 const integer=exactMinor(raw);if(integer!==null)return integer;
 if(typeof raw!=='string'||!(new RegExp('^'+WHOLE_RWF_NUMBER+'$','u')).test(raw))return null;
 const whole=raw.replace(/[.,]0{1,2}$/u,'').replace(/[., \u00a0\u202f]/gu,'');
 return exactMinor(whole);
}
export function monetaryTokens(text,profile){
 const aliases=profile.currency_aliases.map(escape).join('|');
 const number=WHOLE_RWF_NUMBER;
 const pattern=new RegExp(`(?:(${aliases})\\s*(${number})(?![0-9]|,[0-9]|\\.[0-9])|(${number})\\s*(${aliases}))`,'giu');
 const tokens=[];
 for(const match of text.matchAll(pattern)){
  const raw=match[0];
  if(!exactTokenAt(text,match.index,raw))continue;
  const value=exactWholeRwf(match[2]??match[3]);
  if(value===null)continue;
  tokens.push({at:match.index,end:match.index+raw.length,value,currency:match[1]??match[4],raw});
 }
 return tokens;
}
function roleBefore(text,at,profile){
 const before=text.slice(0,at),labels=[...before.matchAll(/(?<![\p{L}\p{N}_])(?:balance|fees?|charges?|solde|frais|asigaye|komisiyo|salio|ada)(?![\p{L}\p{N}_])/giu)];
 const label=labels.at(-1);
 let lastDirection=-1;
 for(const marker of [...markers(profile,'incoming_receipt'),...markers(profile,'outgoing')])
  lastDirection=Math.max(lastDirection,lower(before).lastIndexOf(lower(marker)));
 if(label&&label.index>lastDirection)return {role:['balance','solde','asigaye','salio'].includes(lower(label[0]))?'balance':'fee',at:label.index,end:label.index+label[0].length};
 return {role:'principal',at:lastDirection,end:lastDirection};
}
/** A quotation proves existence, not the financial role of its numbers. Check
 * the actual source clause too, so a shortened quote cannot hide a label. */
function amountHasRole(body,evidence,raw,profile,role,kind){
 const value=quotedMinor(raw,profile);if(value===null||!present(body,evidence))return false;
 for(let quoteAt=body.indexOf(evidence);quoteAt!==-1;quoteAt=body.indexOf(evidence,quoteAt+1)){
  for(let rawAt=evidence.indexOf(raw);rawAt!==-1;rawAt=evidence.indexOf(raw,rawAt+1)){
   const at=quoteAt+rawAt;
   if(!exactTokenAt(evidence,rawAt,raw)||!exactTokenAt(body,at,raw))continue;
   const clause=clauseAt(body,at),local=at-clause.start,prior=roleBefore(clause.text,local,profile);
   if(prior.role!==role)continue;
   const tokens=monetaryTokens(clause.text,profile),token=tokens.find(t=>t.at<=local&&t.end>=local+raw.length&&t.value===value);
   if(role==='principal'){
    if(!token||!onePrincipalAmount(body,evidence,raw,profile))continue;
    const principalTokens=tokens.filter(t=>roleBefore(clause.text,t.at,profile).role==='principal');
    const before=clause.text.slice(0,token.at),after=clause.text.slice(token.end);
    const anchored=containsAny(before,markers(profile,kind))||kind!=='incoming_receipt'&&containsAny(after,markers(profile,kind));
    if(anchored&&principalTokens.length===1&&!/\b(?:if|when|unless|should)\b/iu.test(before))return true;
   }else{
    if(prior.at<0||!new RegExp(role==='fee'?'\\b(?:fees?|charges?)\\b':'\\bbalance\\b','iu').test(evidence))continue;
    const rest=clause.text.slice(prior.end),next=rest.search(/\b(?:balance|fees?|charges?)\b/iu);
    const end=next<0?clause.text.length:prior.end+next,segment=clause.text.slice(prior.end,end);
    if(local>=end||role==='fee'&&/\b(?:transaction|transfer|payment)\s+(?:(?:of|for|amount)\s+)*$/iu.test(clause.text.slice(prior.end,local)))continue;
    const segmentTokens=monetaryTokens(segment,profile);
    if(token){if(segmentTokens.length===1)return true;}
    else if(exactMinor(raw)!==null){
     const numbers=[...segment.matchAll(/[0-9][0-9,]*/gu)].filter(m=>exactMinor(m[0])!==null&&exactTokenAt(segment,m.index,m[0]));
     const left=body[at-1]??'',right=body[at+raw.length]??'';
     if(!/[\p{L}\p{N}_]/u.test(left+right)&&numbers.length===1&&exactMinor(numbers[0][0])===value)return true;
    }
   }
  }
 }
 return false;
}
// Models sometimes quote the currency together with the amount. Accept one
// exact integer with an optional configured currency prefix or suffix; never
// strip arbitrary text or combine multiple numbers into a financial value.
export function quotedMinor(raw,profile){
 if(typeof raw!=='string')return null;
 const value=raw.trim(),bare=exactWholeRwf(value);if(bare!==null)return bare;
 const aliases=profile.currency_aliases.map(escape).join('|');
 if(!aliases)return null;
 const number=WHOLE_RWF_NUMBER;
 const match=new RegExp(`^(?:(?:${aliases})\\s*(${number})|(${number})\\s*(?:${aliases}))$`,'iu').exec(value);
 return match?exactWholeRwf(match[1]??match[2]):null;
}
export function exactTokenAt(text,i,raw){
 if(exactWholeRwf(raw)!==null){
  const before=i?text[i-1]:'',beforePrevious=i>1?text[i-2]:'',after=text[i+raw.length]??'',afterNext=text[i+raw.length+1]??'';
  const splitBefore=/(?:^|[^0-9])[0-9]{1,3}[ \u00a0\u202f]+$/u.test(text.slice(0,i));
  const splitAfter=/^[ \u00a0\u202f]+[0-9]/u.test(text.slice(i+raw.length));
  return !splitBefore&&!splitAfter&&!/[0-9,]/.test(before)&&!/[0-9,]/.test(after)&&!(before==='.'&&/[0-9]/.test(beforePrevious))&&!(after==='.'&&/[0-9]/.test(afterNext));
 }
 const token=c=>Boolean(c)&&/[\p{L}\p{N}\p{M}_]/u.test(c);
 const before=i?Array.from(text.slice(0,i)).at(-1):'',after=String.fromCodePoint(text.codePointAt(i+raw.length)??0);
 const beforePrevious=i>1?Array.from(text.slice(0,i-1)).at(-1):'',afterNext=String.fromCodePoint(text.codePointAt(i+raw.length+1)??0);
 return !token(before)&&!token(after)&&
  !(/^[0-9]/.test(raw)&&/[,.]/.test(before)&&/[0-9]/.test(beforePrevious))&&
  !(/[0-9]$/.test(raw)&&/[,.]/.test(after)&&/[0-9]/.test(afterNext));
}
export function exactQuotedToken(body,evidence,raw){
 if(typeof body!=='string'||typeof evidence!=='string'||typeof raw!=='string'||!raw.length)return false;
 for(let start=body.indexOf(evidence);start!==-1;start=body.indexOf(evidence,start+1)){
  for(let at=evidence.indexOf(raw);at!==-1;at=evidence.indexOf(raw,at+1)){
   if(exactTokenAt(evidence,at,raw)&&exactTokenAt(body,start+at,raw))return true;
  }
 }
 return false;
}
export function contextualQuote(body,quote,profile){
 if(!present(body,quote))return false;
 let context=quote;
 for(const alias of profile.currency_aliases)context=context.replace(new RegExp(escape(alias),'giu'),'');
 return /\p{L}/u.test(context.replace(/[\p{N}\p{P}\p{S}\s]/gu,''));
}
export function quotePositions(body,quote){
 const positions=[];
 if(typeof quote!=='string'||!quote.length)return positions;
 for(let at=body.indexOf(quote);at!==-1;at=body.indexOf(quote,at+1))positions.push({at,end:at+quote.length});
 return positions;
}
function unsignedSourceAmount(body,at,raw,profile){
 let left=body.slice(0,at).trimEnd(),right=body.slice(at+raw.length).trimStart();
 for(const alias of profile.currency_aliases){
  if(lower(left).endsWith(lower(alias)))left=left.slice(0,-alias.length).trimEnd();
  if(lower(right).startsWith(lower(alias)))right=right.slice(alias.length).trimStart();
 }
 // A sign, accounting brackets or an adjacent grouped-number fragment is part
 // of the source token. A model cannot drop it to manufacture a positive value.
 const previous=Array.from(left).at(-1)??'';
 return !/[\p{N}\p{Sm}\p{Pd}\p{Sc}]/u.test(previous)&&
  !(/[.,]$/u.test(left)&&/\p{N}[.,]$/u.test(left))&&
  !(previous==='('&&right.startsWith(')'))&&!/^\p{N}/u.test(right);
}
/** AI supplies the semantic role; code binds it to one complete, contextual
 * source token and refuses overlap with another financial role. No direction,
 * currency or transaction-ID label is extracted by a keyword fallback. */
function semanticAmountHasRole(body,output,profile,role){
 const [rawKey,evidenceKey]=amountFields[role],raw=output[rawKey],quote=output.evidence[evidenceKey];
 if(!contextualQuote(body,quote,profile)||!onePrincipalAmount(body,quote,raw,profile))return false;
 const others=Object.entries(amountFields).filter(([key])=>key!==role).flatMap(([,keys])=>quotePositions(body,output.evidence[keys[1]]));
 for(const span of quotePositions(body,quote)){
  for(let at=quote.indexOf(raw);at!==-1;at=quote.indexOf(raw,at+1)){
   const start=span.at+at,end=start+raw.length;
   if(!exactTokenAt(body,start,raw)||!exactTokenAt(quote,at,raw)||!unsignedSourceAmount(body,start,raw,profile)||
    others.some(other=>other.at<end&&other.end>start))continue;
   const clause=clauseAt(body,start),before=clause.text.slice(0,start-clause.start),known=roleBefore(clause.text,start-clause.start,profile);
   // Known contradictory role labels remain a guard; unfamiliar source-language
   // wording is established by the structured semantic response and quotations.
   if(known.role!=='principal'&&known.role!==role||role!=='principal'&&known.role==='principal'&&known.at>=0)continue;
   if(role==='principal'&&/\b(?:if|when|unless|should)\b/iu.test(before))continue;
   return true;
  }
 }
 return false;
}
export function semanticPrincipalCurrency(body,quote,currency,amount,profile){
 // A currency token may touch its amount (RWF2750 / 2750RWF). Bind it to
 // the already validated complete monetary token, not a generic word boundary
 // that treats the neighbouring amount digit as an invalid currency suffix.
 return present(body,quote)&&monetaryTokens(quote,profile).some(token=>
  token.value===amount&&token.currency===currency&&exactQuotedToken(body,quote,token.raw));
}
export function readAmountEvidence(body,output,profile,role,kind,semantic){
 const [field,evidenceField]=amountFields[role];
 const raw=output[field],quote=output.evidence[evidenceField],amount=quotedMinor(raw,profile);
 if(amount===null||role==='principal'&&amount<=0||!present(body,quote))return null;
 return (semantic?semanticAmountHasRole(body,output,profile,role):amountHasRole(body,quote,raw,profile,role,kind))?amount:null;
}
