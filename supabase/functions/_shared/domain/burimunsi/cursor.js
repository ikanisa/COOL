import {requireThat} from './errors.js';
import {canonicalJson} from './values.js';
const bytes=s=>new TextEncoder().encode(s);
const b64=b=>btoa(String.fromCharCode(...new Uint8Array(b))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
function unb64(s){requireThat(typeof s==='string'&&/^[A-Za-z0-9_-]+$/.test(s),'invalid_cursor');return Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));}
export class ScopedCursor {
  constructor(secret){requireThat(secret instanceof Uint8Array&&secret.length>=32,'cursor_secret_required',503);this.secret=secret;}
  async key(){return crypto.subtle.importKey('raw',this.secret,{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);}
  async create({groupId,actorId,snapshot,filterHash,sort,after,expiresAt}){
    const data={v:1,groupId,actorId,snapshot,filterHash,sort,after,expiresAt};
    const payload=b64(bytes(canonicalJson(data))),signature=b64(await crypto.subtle.sign('HMAC',await this.key(),bytes(payload)));
    return payload+'.'+signature;
  }
  async read(token,scope,now=Date.now()){
    requireThat(typeof token==='string'&&token.length<=2048,'invalid_cursor');
    const parts=token.split('.');requireThat(parts.length===2,'invalid_cursor');
    let data;try{
      requireThat(await crypto.subtle.verify('HMAC',await this.key(),unb64(parts[1]),bytes(parts[0])),'invalid_cursor');
      data=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(unb64(parts[0])));
    }catch{requireThat(false,'invalid_cursor');}
    requireThat(data.v===1&&Number.isSafeInteger(data.expiresAt)&&data.expiresAt>now,'cursor_expired',409);
    for(const key of ['groupId','actorId','snapshot','filterHash','sort'])requireThat(data[key]===scope[key],'cursor_scope_changed',409);
    return data.after;
  }
}
