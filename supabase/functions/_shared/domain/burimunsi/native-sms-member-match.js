// Match the product-defined payer identity only within the captured collection.
// No phone or name is returned from this helper or used as an external proof.
import {normalizePhone} from './values.js';
const normalizeName=value=>typeof value==='string'?value.normalize('NFKC').toLocaleLowerCase('en')
 .replace(/[^\p{L}\p{N}]+/gu,' ').trim().replace(/\s+/gu,' '):'';
const digits=value=>typeof value==='string'&&/^[+0-9*•xX#() .-]+$/.test(value.trim())&&/[0-9]{3}$/.test(value.trim())?
 value.replace(/[^0-9]/g,''):'';

export function nativeSmsPayerKey(name,identifier){
 const normalized=normalizeName(name),number=digits(identifier);
 if(!normalized||number.length<3)return null;
 return Object.freeze({name:normalized,last3:number.slice(-3)});
}

/** Caller supplies server-loaded member rows from the receipt's own group.
 * An absent or non-unique match is retained for automatic later reconsideration. */
export function matchNativeSmsMember({groupId,payerName,payerIdentifier,members}){
 const key=nativeSmsPayerKey(payerName,payerIdentifier);
 if(typeof groupId!=='string'||!groupId||!key||!Array.isArray(members))return null;
 // Full unmasked identifiers must match as complete Rwandan phone numbers.
 // Keep the existing name/suffix rule only for incomplete or masked evidence.
 // A number long enough to be complete that fails normalization is not a suffix.
 const number=digits(payerIdentifier),masked=/[*•xX#]/.test(payerIdentifier);
 let fullPhone=null;
 if(!masked&&number.length>=9){
  try{fullPhone=normalizePhone(payerIdentifier.replace(/\./g,''));}catch{return null;}
 }
 const matches=members.filter(member=>member?.groupId===groupId&&member.active===true&&
  member.eligible===true&&member.memberType!=='operator'&&typeof member.id==='string'&&member.id&&
  (()=>{let phone;try{phone=normalizePhone(member.momoNumber);}catch{return false;}
   const candidate=nativeSmsPayerKey(member.name,phone);return candidate&&
   candidate.name===key.name&&(fullPhone!==null?phone===fullPhone:candidate.last3===key.last3);})());
 return matches.length===1?matches[0].id:null;
}
