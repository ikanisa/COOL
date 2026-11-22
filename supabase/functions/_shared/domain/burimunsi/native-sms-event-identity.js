// A transport/request identity is not a financial event identity. Derive this
// only from the retained, hash-verified SMS source, never model output, device,
// installation, inbox row, request ID or the time at which we uploaded it.
import {canonicalJson,sha256} from './values.js';
import {requireThat} from './errors.js';

function originalInstant(value){
 if(value===null||value===undefined)return null;
 requireThat(typeof value==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/.test(value),
  'native_auto_source_changed',409);
 const ms=Date.parse(value);
 requireThat(Number.isFinite(ms)&&new Date(ms).toISOString().slice(0,19)===value.slice(0,19),
  'native_auto_source_changed',409);
 return new Date(ms).toISOString();
}

export async function nativeSmsEventAliases(source,expectedBodySha256){
 requireThat(source?.provenance==='native_observation_unverified'&&typeof source.raw_body==='string'&&
  typeof source.raw_sender==='string'&&/^[a-f0-9]{64}$/.test(expectedBodySha256??'')&&
  await sha256(source.raw_body)===expectedBodySha256,'native_auto_source_changed',409);
 // SMSC time survives cross-device delivery and inbox-row changes. Original
 // inbox time is the fallback for inbox-only observations. Captured/upload
 // time cannot distinguish events safely. Without either original timestamp,
 // identical bodies conservatively share an identity rather than double-credit.
 const service=originalInstant(source.service_centre_at),inbox=originalInstant(source.inbox_received_at);
 const identity=(at,kind)=>sha256(canonicalJson({format:'collect.native.sms.event.v3',bodySha256:expectedBodySha256,
  originalSmsAt:at,timeKind:kind}));
 // The server-owned receiving account/provider scope supplies sender identity.
 // Literal sender aliases must not turn a replay into another financial event.
 return {identity:await identity(service??inbox,service!==null?'service_centre':inbox!==null?'inbox':'no_original_time'),
  inboxIdentity:inbox===null?null:await identity(inbox,'inbox'),
  serviceTimePresent:service!==null};
}

export async function nativeSmsEventIdentity(source,expectedBodySha256){
 return (await nativeSmsEventAliases(source,expectedBodySha256)).identity;
}
