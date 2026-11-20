// Supabase's public database root, downloaded from the project dashboard's
// HTTPS certificate link. Only this exact DER certificate is accepted.
import {readFileSync} from 'node:fs';
import {createHash, X509Certificate} from 'node:crypto';

export const PROVIDER_ROOT_SHA256='807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa';
const REFUSED='provider_ca_unavailable';

export function validateProviderRoot(pem,now=Date.now()){
 try{
  if(typeof pem!=='string'||Buffer.byteLength(pem)>8192||
   !/^-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\r?\n?$/.test(pem)||
   !Number.isFinite(now))throw Error();
  const cert=new X509Certificate(pem),before=Date.parse(cert.validFrom),after=Date.parse(cert.validTo);
  if(createHash('sha256').update(cert.raw).digest('hex')!==PROVIDER_ROOT_SHA256||
   cert.ca!==true||!cert.checkIssued(cert)||!cert.verify(cert.publicKey)||
   !Number.isFinite(before)||!Number.isFinite(after)||now<before||now>=after)throw Error();
  return pem;
 }catch{throw Error(REFUSED);}
}

export function loadProviderRoot(){
 try{return validateProviderRoot(readFileSync(new URL('./supabase-root-2021.pem',import.meta.url),'utf8'));}
 catch{throw Error(REFUSED);}
}

// Do not accept caller-defined trust stores, client certificates, secure
// contexts, SNI overrides or custom hostname verification callbacks.
export function hasPinnedProviderSSL(value,expectedRoot){
 try{
  if(!value||Object.getPrototypeOf(value)!==Object.prototype||
   Reflect.ownKeys(value).sort().join(',')!=='ca,rejectUnauthorized')return false;
  const root=expectedRoot===undefined?loadProviderRoot():validateProviderRoot(expectedRoot);
  const properties=Object.getOwnPropertyDescriptors(value);
  return Object.hasOwn(properties.ca,'value')&&Object.hasOwn(properties.rejectUnauthorized,'value')&&
   properties.ca.value===root&&properties.rejectUnauthorized.value===true;
 }catch{return false;}
}
