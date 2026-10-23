import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createCipheriv,createDecipheriv,randomBytes,randomUUID} from 'node:crypto';
import {fixture as authFixture,admin,authorization,claims,totp} from './support/auth_fixture.mjs';

const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??'miniflare');
const root=new URL('../',import.meta.url),active=Buffer.from(Array.from({length:32},(_,i)=>i+1)),old=Buffer.from(Array.from({length:32},(_,i)=>i+101));
const keyEnv={DATA_KEY_ID:'current-v2',DATA_ENCRYPTION_KEY:active.toString('base64')},oldEnv={DATA_KEY_ID:'retained-v1',DATA_ENCRYPTION_KEY:old.toString('base64')};
const context='controlled-retained-evidence:object-id:exact-source-sha256',plaintext='Controlled retained object for independent key selection.';
const ring=entries=>JSON.stringify(entries),historical=ring({[oldEnv.DATA_KEY_ID]:oldEnv.DATA_ENCRYPTION_KEY});
function independentEnvelope(bytes=Buffer.from(plaintext),{key=old,kid=oldEnv.DATA_KEY_ID,aad=context}={}){
 const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(Buffer.from(aad));const data=Buffer.concat([cipher.update(bytes),cipher.final(),cipher.getAuthTag()]);
 return JSON.stringify({v:1,kid,iv:iv.toString('base64'),data:data.toString('base64')});
}
function independentDecrypt(document,key,aad=context){
 const value=JSON.parse(document),data=Buffer.from(value.data,'base64'),cipher=createDecipheriv('aes-256-gcm',key,Buffer.from(value.iv,'base64'));
 cipher.setAAD(Buffer.from(aad));cipher.setAuthTag(data.subarray(-16));return Buffer.concat([cipher.update(data.subarray(0,-16)),cipher.final()]);
}
async function fixture(t,configurations=[keyEnv]){
 const modules=[{type:'ESModule',path:fileURLToPath(new URL('test/keyring-worker.mjs',root)),contents:`
  import {encrypt,decrypt} from '../src/encryption.js';
  import {ApiError,json} from '../src/core.js';
  export default {async fetch(request,env){
   const input=await request.json(),configurations=JSON.parse(env.TEST_CONFIGURATIONS_JSON),config=configurations[input.configuration??0];
   try {
    if(input.action==='encrypt')return json({document:await encrypt(config,new TextEncoder().encode(input.plaintext),input.context)});
    return json({plaintext:new TextDecoder('utf-8',{fatal:true}).decode(await decrypt(config,input.document,input.context))});
   }catch(error){return error instanceof ApiError?json({error:{code:error.code,message:error.message}},error.status):json({error:{code:'unexpected_fixture_error'}},500);}
  }};`},...await Promise.all(['encryption.js','core.js'].map(async name=>({type:'ESModule',path:fileURLToPath(new URL('src/'+name,root)),contents:await readFile(new URL('src/'+name,root),'utf8')})))];
 const mf=new Miniflare(convertV4MiniflareOptions({modules,modulesRoot:fileURLToPath(root),compatibilityDate:'2026-10-14',cf:false,bindings:{TEST_CONFIGURATIONS_JSON:JSON.stringify(configurations)}}));t.after(()=>mf.dispose());
 const call=async(action,input={})=>{const response=await mf.dispatchFetch('https://keyring.test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,context,plaintext,...input})});return {status:response.status,body:await response.json()};};
 return {call,encrypt:input=>call('encrypt',input),decrypt:(document,input={})=>call('decrypt',{document,...input})};
}
function unavailable(result,code='storage_unavailable'){
 assert.equal(result.status,503,JSON.stringify(result));assert.equal(result.body.error.code,code);
 assert.equal(result.body.error.message,code==='key_unavailable'?'The storage key is unavailable.':'Secure storage is unavailable.');
 assert.ok(!JSON.stringify(result).includes(keyEnv.DATA_ENCRYPTION_KEY));assert.ok(!JSON.stringify(result).includes(oldEnv.DATA_ENCRYPTION_KEY));
}

test('current-key writes retain exact v1 encoding and AAD and are independently decryptable',async t=>{
 const f=await fixture(t),result=await f.encrypt();assert.equal(result.status,200,JSON.stringify(result));const value=JSON.parse(result.body.document);
 assert.deepEqual(Object.keys(value),['v','kid','iv','data']);assert.equal(value.v,1);assert.equal(value.kid,keyEnv.DATA_KEY_ID);assert.equal(Buffer.from(value.iv,'base64').length,12);
 assert.equal(independentDecrypt(result.body.document,active).toString(),plaintext);assert.equal((await f.decrypt(result.body.document)).body.plaintext,plaintext);
});

test('historical reads select the exact old key while every new write uses only the active key',async t=>{
 const f=await fixture(t,[{...keyEnv,DATA_DECRYPTION_KEYS_JSON:historical}]),document=independentEnvelope();
 assert.equal((await f.decrypt(document)).body.plaintext,plaintext);const written=await f.encrypt();assert.equal(written.status,200);assert.equal(JSON.parse(written.body.document).kid,keyEnv.DATA_KEY_ID);
 assert.equal(independentDecrypt(written.body.document,active).toString(),plaintext);assert.throws(()=>independentDecrypt(written.body.document,old));
});

test('omitted or unknown valid key IDs fail closed without trying the active key',async t=>{
 const f=await fixture(t),document=independentEnvelope();unavailable(await f.decrypt(document),'key_unavailable');
 unavailable(await f.decrypt(independentEnvelope(Buffer.from(plaintext),{key:active,kid:'unconfigured-but-valid-id'})),'key_unavailable');
});

test('wrong AAD, invalid documents, noncanonical base64, invalid IV and tampered ciphertext have one fixed public failure',async t=>{
 const f=await fixture(t),document=independentEnvelope(Buffer.from(plaintext),{key:active,kid:keyEnv.DATA_KEY_ID}),value=JSON.parse(document);
 unavailable(await f.decrypt(document,{context:'different-object'}));
 const cases=['not JSON','null','[]',JSON.stringify({...value,v:2}),JSON.stringify({...value,kid:'escaped id invalid'}),JSON.stringify({...value,iv:'AAAA'}),JSON.stringify({...value,iv:value.iv+'='}),JSON.stringify({...value,data:'AAAA'}),JSON.stringify({...value,data:'!'+value.data.slice(1)}),JSON.stringify({...value,data:Buffer.alloc(32).toString('base64')}),JSON.stringify({...value,extra:'unexpected'})];
 for(const candidate of cases)unavailable(await f.decrypt(candidate));
});

test('literal duplicate keys and escaped aliases are rejected before a JSON parser could overwrite them',async t=>{
 const maps=[`{"retained-v1":"${oldEnv.DATA_ENCRYPTION_KEY}","retained-v1":"${active.toString('base64')}"}`,
  `{"current-v2":"${keyEnv.DATA_ENCRYPTION_KEY}","current-v2":"${keyEnv.DATA_ENCRYPTION_KEY}"}`,
  String.raw`{"retained-v1":"${oldEnv.DATA_ENCRYPTION_KEY}","retained\u002dv1":"${oldEnv.DATA_ENCRYPTION_KEY}"}`,
  String.raw`{"current\u002dv2":"${keyEnv.DATA_ENCRYPTION_KEY}"}`];
 const f=await fixture(t,maps.map(value=>({...keyEnv,DATA_DECRYPTION_KEYS_JSON:value})));
 for(let configuration=0;configuration<maps.length;configuration++)unavailable(await f.encrypt({configuration}));
});

test('distinct IDs cannot alias active or historical key material and active-ID conflicts are rejected',async t=>{
 const maps=[ring({'historical-alias':keyEnv.DATA_ENCRYPTION_KEY}),ring({'old-one':oldEnv.DATA_ENCRYPTION_KEY,'old-two':oldEnv.DATA_ENCRYPTION_KEY}),ring({[keyEnv.DATA_KEY_ID]:oldEnv.DATA_ENCRYPTION_KEY})];
 const f=await fixture(t,maps.map(value=>({...keyEnv,DATA_DECRYPTION_KEYS_JSON:value})));
 for(let configuration=0;configuration<maps.length;configuration++){
  unavailable(await f.encrypt({configuration}));unavailable(await f.decrypt(independentEnvelope(Buffer.from(plaintext),{key:active,kid:keyEnv.DATA_KEY_ID}),{configuration}));
 }
});

test('absent, empty and empty-object rings and one identical active-ID entry remain compatible',async t=>{
 const maps=[undefined,'','{}',ring({[keyEnv.DATA_KEY_ID]:keyEnv.DATA_ENCRYPTION_KEY}),ring({[keyEnv.DATA_KEY_ID]:keyEnv.DATA_ENCRYPTION_KEY,[oldEnv.DATA_KEY_ID]:oldEnv.DATA_ENCRYPTION_KEY})];
 const f=await fixture(t,maps.map(value=>({...keyEnv,...(value===undefined?{}:{DATA_DECRYPTION_KEYS_JSON:value})})));
 for(let configuration=0;configuration<maps.length;configuration++){const written=await f.encrypt({configuration});assert.equal(written.status,200,JSON.stringify(written));assert.equal((await f.decrypt(written.body.document,{configuration})).body.plaintext,plaintext);}
});

test('eight unique ring entries and 4096 UTF-8 bytes are accepted; oversized maps and IDs are refused',async t=>{
 const entries=Object.fromEntries(Array.from({length:8},(_,index)=>['historical-'+index,Buffer.alloc(32,index+80).toString('base64')])),eight=ring(entries),bounded=eight+' '.repeat(4096-eight.length);
 const maps=[eight,bounded,ring({...entries,'historical-nine':Buffer.alloc(32,90).toString('base64')}),bounded+' ',ring({['a'.repeat(128)]:oldEnv.DATA_ENCRYPTION_KEY}),ring({['a'.repeat(129)]:oldEnv.DATA_ENCRYPTION_KEY})];
 const f=await fixture(t,maps.map(value=>({...keyEnv,DATA_DECRYPTION_KEYS_JSON:value})));
 for(const configuration of [0,1,4])assert.equal((await f.encrypt({configuration})).status,200);
 for(const configuration of [2,3,5])unavailable(await f.encrypt({configuration}));
 const document=independentEnvelope(Buffer.from(plaintext),{key:Buffer.alloc(32,87),kid:'historical-7'});assert.equal((await f.decrypt(document)).body.plaintext,plaintext);
});

test('malformed maps and noncanonical key encodings deny current-key reads as well as new writes',async t=>{
 const noncanonical=oldEnv.DATA_ENCRYPTION_KEY.slice(0,-2)+'R=',maps=['null','[]','{"retained-v1":null}',`{"retained-v1":{"key":"${oldEnv.DATA_ENCRYPTION_KEY}"}}`,`{"retained-v1":"${oldEnv.DATA_ENCRYPTION_KEY}",}`,ring({'retained-v1':oldEnv.DATA_ENCRYPTION_KEY.slice(0,-1)}),ring({'retained-v1':noncanonical}),ring({'retained-v1':oldEnv.DATA_ENCRYPTION_KEY+'\n'}),'{} trailing'];
 const f=await fixture(t,maps.map(value=>({...keyEnv,DATA_DECRYPTION_KEYS_JSON:value}))),document=independentEnvelope(Buffer.from(plaintext),{key:active,kid:keyEnv.DATA_KEY_ID});
 for(let configuration=0;configuration<maps.length;configuration++){unavailable(await f.decrypt(document,{configuration}));unavailable(await f.encrypt({configuration}));}
});

test('historical map presence never makes an invalid active key configuration usable',async t=>{
 const configurations=[{DATA_KEY_ID:keyEnv.DATA_KEY_ID,DATA_DECRYPTION_KEYS_JSON:historical},{...keyEnv,DATA_KEY_ID:'',DATA_DECRYPTION_KEYS_JSON:historical},{...keyEnv,DATA_ENCRYPTION_KEY:keyEnv.DATA_ENCRYPTION_KEY.slice(0,-1),DATA_DECRYPTION_KEYS_JSON:historical},{...keyEnv,DATA_DECRYPTION_KEYS_JSON:null}];
 const f=await fixture(t,configurations);for(let configuration=0;configuration<configurations.length;configuration++)unavailable(await f.decrypt(independentEnvelope(),{configuration}));
});

test('changing an envelope key ID cannot bypass exact-key selection or unique-material configuration',async t=>{
 const document=JSON.parse(independentEnvelope()),f=await fixture(t,[{...keyEnv,DATA_DECRYPTION_KEYS_JSON:historical}]);
 document.kid=keyEnv.DATA_KEY_ID;unavailable(await f.decrypt(JSON.stringify(document)));
});

test('real authenticator verification can read its retained old-key secret after a key change',async t=>{
 const f=await authFixture({...keyEnv,DATA_DECRYPTION_KEYS_JSON:historical});t.after(()=>f.close());const operator=await admin(f),session=await f.login(operator.identity),factorId=randomUUID(),sessionID=claims(session.access_token).session_id;
 const secret=Buffer.from('12345678901234567890'),base32='GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
 const document=independentEnvelope(secret,{aad:`collect-mfa-factor:${operator.id}:${factorId}`}),at=Math.floor(Date.now()/1000);
 await f.db.prepare("INSERT INTO auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id) VALUES(?,?,?,?,'pending',?,?)").bind(factorId,operator.id,'Retained authenticator',document,at,sessionID).run();
 const challenge=await f.call('/v1/auth/mfa/challenge',{factor_id:factorId},authorization(session));assert.equal(challenge.status,200,JSON.stringify(challenge));
 const verified=await f.call('/v1/auth/mfa/verify',{factor_id:factorId,challenge_id:challenge.body.id,code:totp(base32)},authorization(session));assert.equal(verified.status,200,JSON.stringify(verified.body));assert.equal(claims(verified.body.access_token).aal,'aal2');
});
