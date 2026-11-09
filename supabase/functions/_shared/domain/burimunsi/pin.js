import {requireThat} from './errors.js';
import {requirePin, normalizePhone} from './values.js';
const bytes=s=>new TextEncoder().encode(s);
const hex=b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
const unhex=s=>Uint8Array.from(s.match(/../g),p=>parseInt(p,16));
export const PIN_ITERATIONS=600000;
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
    if(!record||record.algorithm!=='pbkdf2-sha256+hmac-v1'||record.pepperId!==this.pepperId||
      !/^[a-f0-9]{32}$/.test(record.salt)||!/^[a-f0-9]{64}$/.test(record.hash)||
      !Number.isInteger(record.iterations)||record.iterations<PIN_ITERATIONS||record.iterations>2000000)return false;
    return equalSecret(await this.derive(phone,pin,record.salt,record.iterations),record.hash);
  }
}
export function newBearer() { return hex(crypto.getRandomValues(new Uint8Array(32))); }
