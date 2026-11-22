// Validate and redact an SMS before it can be used to build a provider request.
import { validateProviderProfile } from '../momo_pipeline.js';

export const present=(body,text)=>typeof body==='string'&&typeof text==='string'&&text.length>0&&body.includes(text);
export const lower=s=>s.toLocaleLowerCase('en');
export const containsAny=(body,values)=>values.some(value=>lower(body).includes(lower(value)));
export const escape=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');

const defaults={outgoing:['you have sent','you have paid','withdrawal','withdrawn','your payment of','transferred to'],
 reversal:['reversed','reversal','extournée','extournee','yarasubijwe'],
 failed:['failed','cancelled','canceled','declined','unsuccessful','annulé','annulée','annulee','annulation','échec','echec','cyahagaritswe','yahagaritswe','umeghairiwa','imeghairiwa','imeshindwa'],
 pending:['pending','en attente','kirategereje','irategereje','kitaremezwa','inasubiri','inasubiriwa']};
export function markers(profile,kind){
 if(kind==='incoming_receipt')return profile.incoming_prefixes;
 const configured=kind==='outgoing'?profile.outgoing_markers:kind==='reversal'?profile.reversal_markers:kind==='failed'?profile.failure_markers:[];
 return [...(configured??[]),...(defaults[kind]??[])];
}

const AUTH=/(?<![\p{L}\p{N}_])(?:otp|one[ -]?time(?:[ -]?(?:password|passcode|code))?|password|passcode|verification(?:[ -]code)?|activation[ -]code|security[ -]code|login[ -]code|authori[sz]ation[ -]code|(?:your|the|this|enter|use)\s+code|mot\s+de\s+passe|code\s+(?:de\s+)?(?:v[eé]rification|confirmation|s[eé]curit[eé]|activation|connexion|secret)|(?:kode|code)(?:\s+yawe)?\s+y['’]?ibanga|kode\s+(?:yo\s+kwemeza|yemeza)|ijambo\s+ry['’]?ibanga|umubare\s+(?:wawe\s+)?w['’]?ibanga|ijambobanga|pin(?:[ -]code)?)(?![\p{L}\p{N}_])/iu;
const PIN=/\bpin\b/iu;
const WARNING=/^(?:for your (?:security|safety)[,:]?\s*)?(?:please\s+)?(?:(?:never|do not|don't)\s+(?:share|disclose|reveal|give|tell)\b.*\bpin\b|keep\b.*\bpin\b.*\b(?:secret|safe|private)\b)[.!?;]?$/iu;
// Strip only complete, number-free safety advice; any other credential text
// prevents provider dispatch. These are privacy safeguards, not transaction
// classification rules. Unknown security wording remains blocked for review.
const LOCAL_PIN_WARNING=/^(?:ne\s+(?:partagez|communiquez|divulguez|donnez)\s+jamais\s+(?:votre|le)\s+pin(?:\s+(?:[àa]\s+personne|avec\s+quiconque))?|ntugasangize\s+(?:undi(?:\s+muntu)?\s+)?pin\s+yawe|usimpe\s+mtu(?:\s+yeyote)?\s+pin\s+yako)[.!?;]?$/iu;
const BODY_CONTROL=/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u;

function warningOnly(segment){return !/[0-9]/u.test(segment)&&(WARNING.test(segment.trim())||LOCAL_PIN_WARNING.test(segment.trim()));}
function senderCredentialCode(body,sender){
 // A message saying "your [sender] code" can be an authentication code
 // even without the words PIN or OTP. Do not treat a separately labelled
 // "transaction code" as a credential merely because it contains "code".
 const aliases=[sender,'M-Money','M Money'].filter(value=>typeof value==='string'&&value.length>0).map(escape).join('|');
 return new RegExp(`(?<![\\p{L}\\p{N}_])(?:(?:your|the|this|votre|le)\\s+(?:${aliases})\\s+code|(?:votre|le)\\s+code\\s+(?:${aliases}))(?![\\p{L}\\p{N}_])`,'iu').test(body);
}
function safeBody(body,profile,sender){
 if(senderCredentialCode(body,sender))return null;
 if(!AUTH.test(body))return body;
 // Standard advice such as "Never share your PIN" is not a credential. Remove
 // only an entire, number-free warning sentence; all other security language
 // blocks external dispatch, including a PIN or one-time code in the message.
 const parts=body.split(/(?<=[.!?;])\s+/u);
 if(!parts.some(part=>PIN.test(part))||parts.some(part=>AUTH.test(part)&&!warningOnly(part)))return null;
 const redacted=parts.filter(part=>!AUTH.test(part)).join(' ');
 // Do not send a bare numeric message left over from an authentication text.
 if(AUTH.test(redacted)||!/\p{L}/u.test(redacted)||!/[0-9]/u.test(redacted)||!containsAny(redacted,profile.currency_aliases))return null;
 return redacted;
}

export function readNativeAutoSource(source, account) {
 const profile=validateProviderProfile(account);
 if(!profile||!source||!['live','catch_up'].includes(source.source_mode)||typeof source.raw_sender!=='string'||!profile.sender_allowlist.some(s=>lower(s)===lower(source.raw_sender))||
  typeof source.raw_body!=='string'||!source.raw_body.length||new TextEncoder().encode(source.raw_body).length>3000||BODY_CONTROL.test(source.raw_body))
  return {kind:'invalid_source'};
 const body=safeBody(source.raw_body,profile,source.raw_sender);
 if(body===null||!body.trim())return {kind:'security_message'};
 return {kind:'provider', profile, body};
}
