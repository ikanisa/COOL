import {PublicError, boundedBody, objectValue} from './production_contract.ts';
/** Standard Webhooks v1 HMAC-SHA256. Persistent id replay control is separate. */
export async function verifySmsHook(request: Request, secrets: readonly string[], now = Math.floor(Date.now()/1000)) {
  const id=request.headers.get('webhook-id') ?? '';
  const time=request.headers.get('webhook-timestamp') ?? '';
  const signatures=request.headers.get('webhook-signature') ?? '';
  if (!/^[A-Za-z0-9_:.\-]{1,256}$/.test(id) || !/^\d{1,12}$/.test(time) || signatures.length>2048 || Math.abs(now-Number(time))>300) throw new PublicError('invalid_hook_signature',401);
  if (!secrets.length || secrets.length>2) throw new PublicError('hook_configuration_unavailable',503);
  const body=await boundedBody(request,16384);
  const signed=new TextEncoder().encode(`${id}.${time}.${body}`);
  const candidates=signatures.trim().split(/\s+/).slice(0,8).filter(s=>/^v1,[A-Za-z0-9+/]+={0,2}$/.test(s));
  let valid=false;
  for (const secret of secrets) {
    let bytes: Uint8Array<ArrayBuffer>;
    try {bytes=new Uint8Array(Uint8Array.from(atob(secret.replace(/^v1,whsec_/,'').replace(/^whsec_/,'')),c=>c.charCodeAt(0)));}
    catch {throw new PublicError('hook_configuration_unavailable',503);}
    if (bytes.length<32) throw new PublicError('hook_configuration_unavailable',503);
    const key=await crypto.subtle.importKey('raw',bytes,{name:'HMAC',hash:'SHA-256'},false,['verify']);
    for (const signature of candidates) {
      let sig: Uint8Array<ArrayBuffer>;
      try {sig=new Uint8Array(Uint8Array.from(atob(signature.slice(3)),c=>c.charCodeAt(0)));} catch {continue;}
      if (sig.length===32 && await crypto.subtle.verify('HMAC',key,sig,signed)) valid=true;
    }
  }
  if (!valid) throw new PublicError('invalid_hook_signature',401);
  try {return {id,body,payload:objectValue(JSON.parse(body))};} catch {throw new PublicError('invalid_hook_payload');}
}
