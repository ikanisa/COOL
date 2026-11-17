import {requireThat} from './errors.js';
import {requirePin, normalizePhone} from './values.js';
const bytes=s=>new TextEncoder().encode(s);
const hex=b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
const unhex=s=>Uint8Array.from(s.match(/../g),p=>parseInt(p,16));
export const PIN_ITERATIONS=600000;
const validHashRecord=r=>r&&r.algorithm==='pbkdf2-sha256+hmac-v1'&&typeof r.pepperId==='string'&&r.pepperId.length>0&&
  typeof r.salt==='string'&&/^[a-f0-9]{32}$/.test(r.salt)&&typeof r.hash==='string'&&/^[a-f0-9]{64}$/.test(r.hash)&&
  Number.isInteger(r.iterations)&&r.iterations>=PIN_ITERATIONS&&r.iterations<=2000000;
const canonicalPhone=value=>{try{return typeof value==='string'&&normalizePhone(value)===value;}catch{return false;}};
/** Preserve only server-held PIN derivation identity during an authorized
 * phone edit. The presented login must still equal currentPhone. */
export function retainPhoneBoundPin(record,oldPhone,newPhone) {
  requireThat(validHashRecord(record)&&canonicalPhone(oldPhone)&&canonicalPhone(newPhone)&&oldPhone!==newPhone,'credential_unavailable',503);
  let derivationPhone=oldPhone;
  if(Object.hasOwn(record,'phoneBinding')){
    const b=record.phoneBinding;
    requireThat(b&&typeof b==='object'&&!Array.isArray(b)&&b.version===1&&canonicalPhone(b.derivationPhone)&&
      b.currentPhone===oldPhone,'credential_unavailable',503);
    derivationPhone=b.derivationPhone;
  }
  return {...record,phoneBinding:{version:1,derivationPhone,currentPhone:newPhone}};
}
export function equalSecret(a,b) {
  if(typeof a!=='string'||typeof b!=='string'||a.length!==b.length)return false;
  let different=0;for(let i=0;i<a.length;i++)different|=a.charCodeAt(i)^b.charCodeAt(i);return different===0;
}
export class PinHasher {
  constructor({pepper,pepperId,iterations=PIN_ITERATIONS}) {
    requireThat(pepper instanceof Uint8Array && pepper.byteLength>=32 && typeof pepperId==='string' && pepperId.length>0,'pin_secret_required',503);
    requireThat(Number.isInteger(iterations) && iterations>=PIN_ITERATIONS && iterations<=2000000,'invalid_pin_work_factor',503);
    this.pepper=pepper.slice();this.pepperId=pepperId;this.iterations=iterations;
  }
  async derive(phone,pin,salt,iterations=this.iterations) {
    const key=await crypto.subtle.importKey('raw',this.pepper,{name:'HMAC',hash:'SHA-256'},false,['sign']);
    const prehash=await crypto.subtle.sign('HMAC',key,bytes('burimunsi-pin-v1\0'+normalizePhone(phone)+'\0'+requirePin(pin)));
    const input=await crypto.subtle.importKey('raw',prehash,'PBKDF2',false,['deriveBits']);
    return hex(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:unhex(salt),iterations},input,256));
  }
  async commandFingerprint(value) {
    requireThat(typeof value==='string'&&new TextEncoder().encode(value).length<=8192,'invalid_credential_command');
    const key=await crypto.subtle.importKey('raw',this.pepper,{name:'HMAC',hash:'SHA-256'},false,['sign']);
    return hex(await crypto.subtle.sign('HMAC',key,bytes('burimunsi-credential-command-v1\0'+value)));
  }
  async hash(phone,pin) {
    const salt=hex(crypto.getRandomValues(new Uint8Array(16)));
    return {algorithm:'pbkdf2-sha256+hmac-v1',pepperId:this.pepperId,iterations:this.iterations,salt,hash:await this.derive(phone,pin,salt)};
  }
  async verify(phone,pin,record) {
    if(!validHashRecord(record)||record.pepperId!==this.pepperId)return false;
    let derivationPhone=phone;
    if(Object.hasOwn(record,'phoneBinding')){
      const b=record.phoneBinding;
      if(!b||typeof b!=='object'||Array.isArray(b)||b.version!==1||!canonicalPhone(b.derivationPhone)||
        !canonicalPhone(b.currentPhone)||!canonicalPhone(phone)||b.currentPhone!==phone)return false;
      derivationPhone=b.derivationPhone;
    }
    return equalSecret(await this.derive(derivationPhone,pin,record.salt,record.iterations),record.hash);
  }
}
export function newBearer() { return hex(crypto.getRandomValues(new Uint8Array(32))); }
