import {ApiError} from './core.js';
const b64 = bytes => {
  const chunks = [];
  for (let start = 0; start < bytes.length; start += 32768)
    chunks.push(String.fromCharCode(...bytes.subarray(start, start + 32768)));
  return btoa(chunks.join(''));
};
const unb64 = value => Uint8Array.from(atob(value),c=>c.charCodeAt(0));
const encoder=new TextEncoder();
const KEY_ID=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const unavailable=()=>new ApiError(503,'storage_unavailable','Secure storage is unavailable.');
function decoded(value) {
  if(typeof value!=='string'||value.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(value))throw unavailable();
  const bytes=unb64(value);if(b64(bytes)!==value)throw unavailable();return bytes;
}
function keyBytes(value) {
  if(typeof value!=='string'||value.length!==44)throw unavailable();
  const bytes=decoded(value);if(bytes.length!==32)throw unavailable();return bytes;
}
function configuration(env) {
  const activeId=env.DATA_KEY_ID,active=env.DATA_ENCRYPTION_KEY;
  if(typeof activeId!=='string'||!KEY_ID.test(activeId))throw unavailable();
  const keys=new Map([[activeId,keyBytes(active)]]),material=new Set([active]);
  const raw=env.DATA_DECRYPTION_KEYS_JSON;
  if(raw===undefined||raw==='')return {activeId,keys};
  if(typeof raw!=='string'||encoder.encode(raw).length>4096)throw unavailable();
  // Read the bounded flat map directly. JSON.parse would overwrite duplicate
  // IDs before a validator could see them; literal IDs also exclude escaped
  // aliases. No client input can create or select an additional key here.
  let cursor=0,count=0;const seen=new Set();
  const whitespace=()=>{while(/[ \t\r\n]/.test(raw[cursor]??'')&&cursor<raw.length)cursor++;};
  const take=character=>{whitespace();if(raw[cursor++]!==character)throw unavailable();};
  take('{');whitespace();
  if(raw[cursor]==='}')cursor++;
  else while(true){
    whitespace();const label=/^"([A-Za-z0-9][A-Za-z0-9._:-]{0,127})"/.exec(raw.slice(cursor));
    if(!label||seen.has(label[1])||++count>8)throw unavailable();
    const id=label[1];seen.add(id);cursor+=label[0].length;take(':');whitespace();
    const entry=/^"([A-Za-z0-9+/]{43}=)"/.exec(raw.slice(cursor));if(!entry)throw unavailable();
    cursor+=entry[0].length;const value=entry[1],bytes=keyBytes(value);
    if(id===activeId){if(value!==active)throw unavailable();}
    else {if(material.has(value))throw unavailable();material.add(value);keys.set(id,bytes);}
    whitespace();if(raw[cursor]==='}'){cursor++;break;}take(',');
  }
  whitespace();if(cursor!==raw.length)throw unavailable();return {activeId,keys};
}
export async function encrypt(env,bytes,context) {
  try {
    const config=configuration(env);if(typeof context!=='string')throw unavailable();
    const key=await crypto.subtle.importKey('raw',config.keys.get(config.activeId),'AES-GCM',false,['encrypt']);
    const iv=crypto.getRandomValues(new Uint8Array(12)),aad=encoder.encode(context);
    const data=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad},key,bytes);
    return JSON.stringify({v:1,kid:config.activeId,iv:b64(iv),data:b64(new Uint8Array(data))});
  }catch{throw unavailable();}
}
export async function decrypt(env,document,context) {
  try {
    const config=configuration(env);if(typeof document!=='string'||typeof context!=='string')throw unavailable();
    const value=JSON.parse(document);
    if(!value||Array.isArray(value)||value.v!==1||typeof value.kid!=='string'||!KEY_ID.test(value.kid)||Object.keys(value).sort().join(',')!=='data,iv,kid,v')throw unavailable();
    const iv=decoded(value.iv),data=decoded(value.data);if(iv.length!==12||data.length<16)throw unavailable();
    const bytes=config.keys.get(value.kid);if(!bytes)throw new ApiError(503,'key_unavailable','The storage key is unavailable.');
    const key=await crypto.subtle.importKey('raw',bytes,'AES-GCM',false,['decrypt']);
    return new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM',iv,additionalData:encoder.encode(context)},key,data));
  }catch(error){if(error instanceof ApiError&&error.code==='key_unavailable')throw error;throw unavailable();}
}
