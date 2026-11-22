import {contextualQuote,exactQuotedToken,monetaryTokens,quotePositions} from './native-auto-amount.js';
import {escape,lower} from './native-auto-source.js';

function referenceInEvidence(text,reference,prefixes){
 if(typeof text!=='string'||typeof reference!=='string'||!reference.length||reference.length>160||/\s/u.test(reference))return false;
 const boundary='[\\p{L}\\p{N}\\p{M}_/\\-]';
 return prefixes.some(prefix=>new RegExp(`${escape(prefix)}\\s*${escape(reference)}(?!${boundary}|\\.[\\p{L}\\p{N}])`,'iu').test(text));
}
// A positive provider-ID label must be adjacent to the whole ID. These
// protections qualify financial use; generic extraction can still retain a
// source-grounded identifier with an unfamiliar label for human review.
function explicitTransactionReference(quote,reference,profile){
 if(typeof quote!=='string'||typeof reference!=='string'||!reference.length)return false;
 // Bare "transaction 250" or "transfer 250" could describe a monetary
 // amount, not an ID. Require an identifying word in addition to the event,
 // in either order, unless the operator configured a literal ID prefix.
 const event='(?:transaction|transfer|transfert|op[eé]ration|igikorwa|muamala|shughuli|txn|tx|ft)';
 const identity='(?:id|no|n[°º]|number|num[eé]ro|nimero|nambari|namba|reference|r[eé]f(?:[eé]rence)?|code|#)';
 const label=`(?:${event}\\s*${identity}|${identity}\\s*(?:(?:de\\s+(?:l['’])?|d['’]|y['’])\\s*)?${event})`;
 const end=`${escape(reference)}(?![\\p{L}\\p{N}\\p{M}_/\\-]|\\.[\\p{L}\\p{N}])`;
 return new RegExp(`(?<![\\p{L}\\p{N}_])${label}(?:\\s*[:#=\\-]\\s*|\\s+)${end}`,'iu').test(quote)||
  new RegExp(`(?<![\\p{L}\\p{N}_])${event}\\s*#\\s*${end}`,'iu').test(quote)||
  referenceInEvidence(quote,reference,profile.transaction_id_prefixes);
}
function semanticReference(body,quote,reference,profile){
 if(typeof reference!=='string'||!reference.length||reference.length>160||/\s/u.test(reference)||
  !contextualQuote(body,quote,profile))return false;
 // A phone/party, account, agent, free-text note or security code is not a
 // transaction identifier merely because the model quoted it. Allow numeric
 // IDs even if phone-shaped only when an explicit provider ID label is bound
 // directly to that exact value. Other unfamiliar transaction labels remain
 // supported when the quote does not contain a competing identity context.
 const riskyContext=/(?<![\p{L}\p{N}_])(?:phone|telephone|t[eé]l[eé]phone|mobile|account|compte|konti|konto|wallet|agent|payer|sender|recipient|receiver|customer|client|umukiriya|from|to|customer\s+note|sender\s+note|user\s+note|note\s+(?:du|de|client)|icyitonderwa|umero\s+wa\s+telefone|namba\s+ya\s+simu|otp|pin)(?![\p{L}\p{N}_])/iu.test(quote);
 const phoneLike=/^(?:0?7[2-9][0-9]{7}|\+?2507[2-9][0-9]{7}|\*{2,}[0-9]{3,10})$/u.test(reference);
 const explicit=explicitTransactionReference(quote,reference,profile);
 if((riskyContext||phoneLike)&&!explicit)return false;
 // The identifying context must be more than the model's identifier itself.
 if(!/\p{L}/u.test(quote.replaceAll(reference,'').replace(/[\p{N}\p{P}\p{S}\s]/gu,''))||monetaryTokens(quote,profile).length)return false;
 const identifierPart=char=>Boolean(char)&&/[\p{L}\p{N}\p{M}\p{Cf}_/\-]/u.test(char);
 const wholeAt=(text,at)=>{
  const left=Array.from(text.slice(0,at)),right=Array.from(text.slice(at+reference.length));
  // Identifier boundaries differ from numeric amount boundaries. Hyphens,
  // slashes, letters and internal dots cannot be dropped from either end;
  // a sentence-terminal period remains ordinary punctuation.
  return !identifierPart(left.at(-1))&&!identifierPart(right[0])&&
   !(left.at(-1)==='.'&&identifierPart(left.at(-2)))&&
   !(right[0]==='.'&&identifierPart(right[1]));
 };
 for(const span of quotePositions(body,quote))
  for(let at=quote.indexOf(reference);at!==-1;at=quote.indexOf(reference,at+1))
   if(wholeAt(quote,at)&&wholeAt(body,span.at+at))return true;
 return false;
}
// A model may include the operator-approved ID label in transaction_id_raw.
// Repair that representation only when the entire labelled text appears in
// the SMS and evidence, and the unwrapped identifier is a complete token.
export function normalizePrefixedTransactionId(output,body,original,profile){
 const raw=output.transaction_id_raw,quote=output.evidence.transaction_id;
 if(typeof raw!=='string'||typeof quote!=='string'||!exactQuotedToken(body,quote,raw)||!exactQuotedToken(original,quote,raw))return null;
 for(const prefix of [...profile.transaction_id_prefixes].sort((a,b)=>b.length-a.length)){
  if(!lower(raw).startsWith(lower(prefix)))continue;
  const reference=raw.slice(prefix.length).trimStart();
  if(!reference||reference.length>160||!/^[\p{L}\p{N}](?:[\p{L}\p{N}\p{M}_.\/-]*[\p{L}\p{N}\p{M}])?$/u.test(reference)||
   !referenceInEvidence(body,reference,[prefix])||!referenceInEvidence(original,reference,[prefix])||
   !referenceInEvidence(quote,reference,[prefix]))continue;
  return {...output,transaction_id_raw:reference};
 }
 return null;
}

export function hasStrongProviderReference(source, profile, output, reference) {
 if(reference===output.transaction_id_raw)return explicitTransactionReference(output.evidence.transaction_id,reference,profile);
 return reference===output.payment_reference_raw&&referenceInEvidence(source.raw_body,reference,profile.transaction_id_prefixes);
}

export function readTransactionEvidence(body,output,profile,semantic){
 const reference=output.transaction_id_raw;
 // Some providers label their configured transaction ID as a payment reference.
 // Accept that model field only when the actual message places it immediately
 // after a configured transaction-ID prefix; arbitrary notes stay unassigned.
 const fallback=reference===null?output.payment_reference_raw:null;
 return reference&&(semantic?reference!==output.payer_identifier_raw&&reference!==output.payer_name_raw&&semanticReference(body,output.evidence.transaction_id,reference,profile):referenceInEvidence(output.evidence.transaction_id,reference,profile.transaction_id_prefixes))?reference:
  fallback&&referenceInEvidence(body,fallback,profile.transaction_id_prefixes)?fallback:null;
}
