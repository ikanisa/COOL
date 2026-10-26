#!/usr/bin/env node
// Offline authenticated archive and isolated local D1 recovery. Never restores remotely.
import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';
import {readFile,mkdir,lstat,realpath,readdir,open} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {spawn} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {DatabaseSync,constants} from 'node:sqlite';
import {constants as fsConstants} from 'node:fs';
import {readFileSync} from 'node:fs';
import {recoveryQuarantinePlan,applyRecoveryQuarantine,quarantineMutableTables,quarantineSchemaProfiles} from './recovery_quarantine.mjs';
import {identityKeyRing} from '../../deploy/platform-api/src/identity_keys.js';
import {installSnapshotSql,loadLockedSnapshotParser} from './sql_snapshot_import.mjs';
export {installSnapshotSql} from './sql_snapshot_import.mjs';

const FORMAT='collect.platform.backup.v1',AAD=Buffer.from(FORMAT),MAX=64*1024*1024;
const DATABASE_ID='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
const secrets=['AUTH_JWT_SECRET','AUTH_TOKEN_HASH_SECRET','DATA_ENCRYPTION_KEY'];
const retentionApprovalRole='PRIVACY_RETENTION_APPROVAL_SHA256';
const identitySecretRoles=['AUTH_IDENTITY_HASH_KEY','AUTH_IDENTITY_PREVIOUS_KEYS_JSON'];
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const required=(ok,message)=>{if(!ok)throw new Error(message);};
function privateJson(raw,message='Private recovery JSON could not be verified.'){try{return JSON.parse(raw);}catch{throw new Error(message);}}
// Worker roles form a flat string map. JSON.parse alone silently overwrites
// duplicate authority roles, including escaped spellings of the same key.
function privateSecrets(raw){
 const parsed=privateJson(raw);required(parsed&&typeof parsed==='object'&&!Array.isArray(parsed)&&Object.values(parsed).every(v=>typeof v==='string'),'Incomplete worker key recovery');
 try{
  const text=raw.toString(),values=new Map(),token=/"(?:[^"\\\u0000-\u001f]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*"/y;let offset=0;
  const whitespace=()=>{while(offset<text.length&&/[ \t\r\n]/.test(text[offset]))offset++;};
  const string=()=>{token.lastIndex=offset;const match=token.exec(text);required(match,'Invalid private role');offset=token.lastIndex;return JSON.parse(match[0]);};
  whitespace();required(text[offset++]==='{','Invalid private roles');whitespace();
  if(text[offset]!=='}')while(offset<text.length){const key=string();required(!values.has(key),'Duplicate private role');whitespace();required(text[offset++]===':','Invalid private role');whitespace();values.set(key,string());whitespace();if(text[offset]!==',')break;offset++;whitespace();}
  required(text[offset++]==='}','Invalid private roles');whitespace();required(offset===text.length,'Invalid private roles');return Object.fromEntries(values);
 }catch{throw new Error('Private recovery JSON could not be verified.');}
}
const migrationName=/^migrations\/([0-9]{4})_[a-z_]+\.sql$/;
const fileName=name=>name==='database.sql'||name==='wrangler.json'||name==='worker-secrets.json'||migrationName.test(name);
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===keys.length&&keys.every(k=>Object.hasOwn(value,k));
function decode(value,bytes){required(typeof value==='string'&&/^[A-Za-z0-9+/]*={0,2}$/.test(value),'Invalid archive encoding');const raw=Buffer.from(value,'base64');required(raw.toString('base64')===value&&(bytes===undefined||raw.length===bytes),'Invalid archive encoding');return raw;}
function auth17SecretRoles(config,keys,profile){
 const vars=config.vars??{},names=['GOOGLE_CLIENT_SECRET','OTP_DELIVERY_TOKEN'];
 required(names.every(name=>!Object.hasOwn(vars,name)),'Authentication provider secrets cannot be public configuration');
 const configured=names.some(name=>Object.hasOwn(keys,name))||vars.GOOGLE_AUTH_ENABLED==='true'||Boolean(vars.OTP_DELIVERY_URL);
 if(profile!=='candidate17'){required(!configured,'Incomplete worker key recovery');return [];}
 const result=[],bounded=value=>typeof value==='string'&&value.length>=16&&value.length<=4096&&!/[\u0000-\u001f\u007f]/.test(value);
 const https=value=>{try{const url=new URL(value);return url.protocol==='https:'&&!url.username&&!url.password&&!url.hash&&!url.search&&url.hostname!=='localhost'&&!url.hostname.endsWith('.localhost')&&!/^[0-9.]+$/.test(url.hostname)&&!url.hostname.includes(':')?url:null;}catch{return null;}};
 const google=vars.GOOGLE_AUTH_ENABLED==='true'||Object.hasOwn(keys,'GOOGLE_CLIENT_SECRET');
 if(google){const callback=https(vars.GOOGLE_REDIRECT_URI);required(/^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/.test(vars.GOOGLE_CLIENT_ID??'')&&callback?.pathname==='/v1/auth/google/callback'&&bounded(keys.GOOGLE_CLIENT_SECRET),'Google provider recovery configuration could not be verified');result.push('GOOGLE_CLIENT_SECRET');}
 const relay=Boolean(vars.OTP_DELIVERY_URL)||Object.hasOwn(keys,'OTP_DELIVERY_TOKEN');
 if(relay){required(https(vars.OTP_DELIVERY_URL)&&bounded(keys.OTP_DELIVERY_TOKEN),'OTP relay recovery configuration could not be verified');result.push('OTP_DELIVERY_TOKEN');}
 return result;
}
function recoverySecretRoles(config,keys={},profile){
 const siteKey=config.vars?.TURNSTILE_SITE_KEY;
 required(siteKey===undefined||typeof siteKey==='string'&&(siteKey===''||/^[A-Za-z0-9_-]{20,256}$/.test(siteKey)),'Invalid Turnstile recovery configuration');
 required(!Object.hasOwn(config.vars??{},retentionApprovalRole),'Retention approval must be recovered as a separately authorized Worker secret');
 required(identitySecretRoles.every(name=>!Object.hasOwn(config.vars??{},name)),'Identity hash keys must be recovered as Worker secrets');
 if(Object.hasOwn(keys,retentionApprovalRole))required(typeof keys[retentionApprovalRole]==='string'&&/^[a-f0-9]{64}$/.test(keys[retentionApprovalRole]),'Invalid retention approval recovery pin');
 return [...secrets,...(siteKey?['TURNSTILE_SECRET']:[]),...(Object.hasOwn(keys,'DATA_DECRYPTION_KEYS_JSON')?['DATA_DECRYPTION_KEYS_JSON']:[]),...(Object.hasOwn(keys,retentionApprovalRole)?[retentionApprovalRole]:[]),...identitySecretRoles.filter(name=>Object.hasOwn(keys,name)),...auth17SecretRoles(config,keys,profile)];
}
function exactMigrationProfile(payload,migrations){return Object.entries(quarantineSchemaProfiles).find(([,profile])=>migrations.length===Object.keys(profile.digests).length&&migrations.every(name=>payload.files[name].sha256===profile.digests[name]))?.[0];}
function validateIdentityRecovery(config,keys,profile){
 const configured=Object.hasOwn(config.vars??{},'AUTH_IDENTITY_KEY_ID')||identitySecretRoles.some(name=>Object.hasOwn(keys,name));
 if(!['candidate11','candidate12','candidate13','candidate15','candidate17'].includes(profile)){required(!configured,'Identity key recovery requires the exact qualified candidate11, candidate12, candidate13 or candidate15 migrations');return;}
 try{
  required(sha(readFileSync(new URL('../../deploy/platform-api/src/identity_keys.js',import.meta.url)))===quarantineSchemaProfiles[profile].identityValidatorSha256,'Identity validator differs from its qualified profile');
  const ring=identityKeyRing({...config.vars,...keys},keys.AUTH_TOKEN_HASH_SECRET);
  for(const value of ring.keys.values())value.fill(0);
 }catch{throw new Error('Identity-key recovery configuration could not be verified.');}
}

const dataKeyId=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const validDataKeyId=value=>typeof value==='string'&&dataKeyId.test(value);
// Match the shipping crypto contract: literal ASCII IDs, canonical base64,
// exact-ID selection, bounded entries, no JSON overwrite or key-material alias.
function historicalDataKeys(config,keys){
 try{
  const currentId=config.vars?.DATA_KEY_ID;required(validDataKeyId(currentId),'Invalid current data-key identity');
  const current=decode(keys.DATA_ENCRYPTION_KEY,32),active=keys.DATA_ENCRYPTION_KEY,raw=keys.DATA_DECRYPTION_KEYS_JSON,result=new Map();current.fill(0);
  if(raw===undefined)return result;
  required(typeof raw==='string'&&Buffer.byteLength(raw)<=4096,'Invalid historical data-key setting');
  if(raw==='')return result;const text=raw.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g,'');
  // Only the four JSON whitespace characters may separate literal entries.
  let offset=0;const whitespace=()=>{while(/[ \t\r\n]/.test(text[offset]??'')&&offset<text.length)offset++;};
  required(text[offset++]==='{','Invalid historical data-key map');whitespace();const ids=new Set(),materials=new Set([active]);
  if(text[offset]==='}'){offset++;required(offset===text.length,'Invalid historical data-key map');return result;}
  while(offset<text.length){
   const match=/^"([A-Za-z0-9][A-Za-z0-9._:-]{0,127})"[ \t\r\n]*:[ \t\r\n]*"([A-Za-z0-9+/]{43}=)"/.exec(text.slice(offset));
   required(match&&!ids.has(match[1])&&ids.size<8,'Invalid or duplicate historical data-key entry');
   const id=match[1],value=match[2],bytes=decode(value,32);ids.add(id);
   required(id===currentId?value===active:!materials.has(value),'Conflicting or aliased historical data-key material');
   if(id!==currentId)materials.add(value);result.set(id,bytes);offset+=match[0].length;whitespace();
   if(text[offset]==='}'){offset++;required(offset===text.length,'Invalid historical data-key map');return result;}
   required(text[offset++ ]===',','Invalid historical data-key map');whitespace();
  }
  throw new Error('Incomplete historical data-key map');
 }catch{throw new Error('Historical data-key recovery configuration could not be verified.');}
}

export function validatePayload(payload){
 required(exact(payload,['format','database_id','source_id','captured_at','files'])&&payload.format===FORMAT&&payload.database_id===DATABASE_ID&&/^[a-f0-9]{64}$/.test(payload.source_id)&&Number.isFinite(Date.parse(payload.captured_at)),'Invalid backup identity');
 required(payload.files&&typeof payload.files==='object'&&!Array.isArray(payload.files),'Invalid backup files');
 const names=Object.keys(payload.files),migrations=names.filter(n=>migrationName.test(n)).sort(),numbers=migrations.map(n=>Number(n.match(migrationName)[1]));
 required(numbers.length>=8&&numbers.every((n,i)=>n===i+1),'Each published migration must be present once, in contiguous order');
 required(names.length===migrations.length+3&&names.includes('database.sql')&&names.includes('wrangler.json')&&names.includes('worker-secrets.json')&&names.every(fileName),'Incomplete backup roles');
 const files={};let total=0;
 for(const name of names){const record=payload.files[name];required(exact(record,['sha256','bytes','base64'])&&/^[a-f0-9]{64}$/.test(record.sha256),'Invalid backup record');const raw=decode(record.base64);total+=raw.length;
  required(total<=MAX&&raw.length===record.bytes&&sha(raw)===record.sha256,'Backup byte verification failed');files[name]=raw;}
 const config=JSON.parse(files['wrangler.json']);required(config.name==='collect-platform-api'&&config.d1_databases?.length===1&&config.d1_databases[0].database_id===DATABASE_ID&&config.vars?.BUILD_SOURCE_ID===payload.source_id,'Unexpected platform configuration');
 const profile=exactMigrationProfile(payload,migrations);
 const keys=privateSecrets(files['worker-secrets.json']),roles=recoverySecretRoles(config,keys,profile);required(exact(keys,roles)&&secrets.every(k=>typeof keys[k]==='string'&&keys[k].length>=32)&&(!roles.includes('TURNSTILE_SECRET')||typeof keys.TURNSTILE_SECRET==='string'&&/^[A-Za-z0-9_-]{32,256}$/.test(keys.TURNSTILE_SECRET)),'Incomplete worker key recovery');
 if(Object.hasOwn(keys,retentionApprovalRole))required(['candidate10','candidate11','candidate12','candidate13','candidate15','candidate17'].includes(profile),'Retention approval recovery requires exact qualified candidate10, candidate11, candidate12 or candidate13 migrations, or the exact qualified candidate15 migrations');
 validateIdentityRecovery(config,keys,profile);
 if(Object.hasOwn(keys,'DATA_DECRYPTION_KEYS_JSON')){const historical=historicalDataKeys(config,keys);for(const value of historical.values())value.fill(0);}
 return files;
}
export function seal(payload,key){required(Buffer.isBuffer(key)&&key.length===32,'A 256-bit recovery key is required');validatePayload(payload);const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,nonce);cipher.setAAD(AAD);
 const ciphertext=Buffer.concat([cipher.update(JSON.stringify(payload)),cipher.final()]);return {format:FORMAT,nonce:nonce.toString('base64'),ciphertext:ciphertext.toString('base64'),tag:cipher.getAuthTag().toString('base64')};}
export function unseal(envelope,key){
 try{required(exact(envelope,['format','nonce','ciphertext','tag'])&&envelope.format===FORMAT&&Buffer.isBuffer(key)&&key.length===32,'Invalid archive');const nonce=decode(envelope.nonce,12),tag=decode(envelope.tag,16),ciphertext=decode(envelope.ciphertext);required(ciphertext.length<=2*MAX,'Archive exceeds its byte bound');
  const decipher=createDecipheriv('aes-256-gcm',key,nonce);decipher.setAAD(AAD);decipher.setAuthTag(tag);const raw=Buffer.concat([decipher.update(ciphertext),decipher.final()]);required(raw.length<=2*MAX,'Archive exceeds its byte bound');const payload=JSON.parse(raw);validatePayload(payload);return payload;
 }catch{throw new Error('The authenticated backup could not be verified.');}
}
async function physical(path){let part='/';for(const name of resolve(path).split('/').filter(Boolean)){part=join(part,name);required(!(await lstat(part)).isSymbolicLink(),'Recovery inputs cannot traverse symbolic links');}return realpath(path);}
async function regular(path,{privateFile=false,maxBytes=2*MAX}={}){
 const p=await physical(resolve(path));required(Number.isInteger(fsConstants.O_NOFOLLOW),'No-follow file reads are required');
 const file=await open(p,fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW);
 try{const s=await file.stat();required(s.isFile()&&s.nlink===1&&s.size<=maxBytes,'Expected a bounded independent regular file');if(privateFile)required((s.mode&0o077)===0,'Private input permissions must exclude group and other access');
  const raw=await file.readFile(),after=await file.stat(),named=await lstat(p);
  required([after,named].every(v=>s.dev===v.dev&&s.ino===v.ino&&s.size===v.size&&s.mtimeMs===v.mtimeMs&&s.ctimeMs===v.ctimeMs&&v.nlink===1)&&!named.isSymbolicLink(),'Input changed during capture');return raw;
 }finally{await file.close();}
}
async function exclusive(path,raw){const file=await open(path,'wx',0o600);try{await file.writeFile(raw);await file.sync();}finally{await file.close();}}
async function freshDirectory(path){const p=resolve(path);await physical(dirname(p));await mkdir(p,{mode:0o700});required(((await lstat(p)).mode&0o077)===0,'Recovery directory must be private and physical');return physical(p);}
function options(argv){const result={};for(let i=0;i<argv.length;i+=2){required(argv[i]?.startsWith('--')&&argv[i+1]&&!result[argv[i]],'Use unique named options');result[argv[i]]=argv[i+1];}return result;}
async function command(args,log,seconds=120){const file=await open(log,'wx',0o600);try{return await new Promise((yes,no)=>{const child=spawn(process.execPath,args,{stdio:['ignore',file.fd,file.fd],detached:true,env:{...process.env,CI:'true',WRANGLER_SEND_METRICS:'false'}});const timer=setTimeout(()=>{process.kill(-child.pid,'SIGTERM');no(new Error('Local recovery command exceeded its deadline'));},seconds*1000);child.on('error',e=>{clearTimeout(timer);no(e);});child.on('close',code=>{clearTimeout(timer);code===0?yes():no(new Error('Local recovery command failed; private diagnostics retained'));});});}finally{await file.close();}}
export function installSql(db,sql){db.setAuthorizer((code,a,b)=>{if(code===constants.SQLITE_ATTACH||code===constants.SQLITE_DETACH||code===constants.SQLITE_FUNCTION&&(a==='load_extension'||b==='load_extension')||code===constants.SQLITE_PRAGMA&&a==='writable_schema')return constants.SQLITE_DENY;return constants.SQLITE_OK;});db.exec(sql);}
function restoreParts(db,{parentFirst=false}={}){
 const schema=db.prepare("SELECT type,name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY type,name").all();
 const quoted=name=>{required(/^[a-z][a-z0-9_]*$/.test(name),'Unexpected database identifier');return '"'+name+'"';};
 const literal=value=>{if(value===null)return 'NULL';if(value instanceof Uint8Array)return "X'"+Buffer.from(value).toString('hex')+"'";if(typeof value==='string')return "CAST(X'"+Buffer.from(value).toString('hex')+"' AS TEXT)";required(typeof value==='number'&&Number.isFinite(value)&&(!Number.isInteger(value)||Number.isSafeInteger(value)),'Database number exceeds the supported exact range');return String(value);};
 const tables=schema.filter(r=>r.type==='table'),rows=new Map(tables.map(t=>[t.name,db.prepare('SELECT * FROM '+quoted(t.name)).all()]));
 let ordered=tables;
 if(parentFirst){
  // A hosted import need not keep a deferred-constraint transaction open
  // between statements or phases. Restore referenced records first.
  const nonempty=tables.filter(t=>rows.get(t.name).length),names=new Set(nonempty.map(t=>t.name)),done=new Set();ordered=[];
  const parents=new Map(nonempty.map(t=>[t.name,new Set(db.prepare('PRAGMA foreign_key_list('+quoted(t.name)+')').all().filter(f=>names.has(f.table)&&rows.get(t.name).some(r=>r[f.from]!==null)).map(f=>f.table))]));
  while(done.size<nonempty.length){const ready=nonempty.filter(t=>!done.has(t.name)&&[...parents.get(t.name)].every(n=>done.has(n)));required(ready.length,'Parent-first replay cannot safely restore cyclic populated foreign keys; use an explicitly qualified transaction-aware recovery');for(const t of ready){ordered.push(t);done.add(t.name);}}
 }
 const data=['PRAGMA defer_foreign_keys=TRUE'];
 for(const table of ordered){for(const row of rows.get(table.name))data.push('INSERT INTO '+quoted(table.name)+'('+Object.keys(row).map(quoted).join(',')+') VALUES('+Object.values(row).map(literal).join(',')+')');}
 const sequence=db.prepare("SELECT 1 FROM sqlite_schema WHERE name='sqlite_sequence'").get();if(sequence){data.push('DELETE FROM sqlite_sequence');for(const row of db.prepare('SELECT name,seq FROM sqlite_sequence').all())data.push('INSERT INTO sqlite_sequence(name,seq) VALUES('+literal(row.name)+','+literal(row.seq)+')');}
 return {tables:tables.map(t=>t.sql),data,indexes:schema.filter(r=>r.type==='index').map(r=>r.sql),triggers:schema.filter(r=>r.type==='trigger').map(r=>r.sql),views:schema.filter(r=>r.type==='view').map(r=>r.sql)};
}
const statementsSql=statements=>statements.map(s=>s.replace(/;\s*$/,'')+';').join('\n')+'\n';
export function restoreSql(db){const p=restoreParts(db);return statementsSql([...p.tables,...p.data,...p.indexes,...p.triggers,...p.views]);}
export function restorePhases(db){const p=restoreParts(db,{parentFirst:true});required(p.views.length===0,'Views require a separately qualified dependency order');return Object.fromEntries(['tables','data','indexes','triggers'].map(name=>[name,statementsSql(p[name])]));}
// Same exact stored SQL already reviewed for the backend migration reader.
// Historical profiles retain their protocol; current12 never treats a prefix
// as permission to omit an unknown object from schema/data recovery checks.
const providerBookkeepingSchemas=Object.freeze({
 // Exact pinned local Miniflare form; distinct from hosted _cf_KV.
 _cf_METADATA:"CREATE TABLE _cf_METADATA (\n        key INTEGER PRIMARY KEY,\n        value BLOB\n      )",
 _cf_KV:'CREATE TABLE _cf_KV (\n        key TEXT PRIMARY KEY,\n        value BLOB\n      ) WITHOUT ROWID',
 d1_migrations:'CREATE TABLE "d1_migrations"(\n\t\tid         INTEGER PRIMARY KEY AUTOINCREMENT,\n\t\tname       TEXT UNIQUE,\n\t\tapplied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL\n)',
});
function currentProviderObjects(db){
 for(const row of db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*'").all()){
  if(Object.hasOwn(providerBookkeepingSchemas,row.name)||Object.hasOwn(providerBookkeepingSchemas,row.tbl_name)||/^_cf_/i.test(row.name)||/^_cf_/i.test(row.tbl_name))
   required(row.type==='table'&&row.name===row.tbl_name&&row.sql===providerBookkeepingSchemas[row.name],'Unreviewed provider bookkeeping object or schema');
 }
 if(db.prepare("SELECT 1 FROM sqlite_schema WHERE name='sqlite_sequence'").get())for(const row of db.prepare('SELECT name FROM sqlite_sequence').all())required(!/^_cf_/i.test(row.name),'Unreviewed provider-prefix sequence');
}
const currentSnapshot=payload=>['candidate12','candidate13','candidate15','candidate17'].includes(exactMigrationProfile(payload,Object.keys(payload.files).filter(n=>migrationName.test(n)).sort()));
function fingerprint(db,current=false){
 if(current)currentProviderObjects(db);
 const filter=current?"name NOT IN('_cf_KV','_cf_METADATA')":"name NOT LIKE '_cf_%'",internal=current?"name NOT GLOB 'sqlite_*'":"name NOT LIKE 'sqlite_%'";
 const tables=db.prepare("SELECT name,sql FROM sqlite_schema WHERE type='table' AND ("+internal+" OR name='sqlite_sequence') AND "+filter+" ORDER BY name").all(),result={};
 for(const table of tables){required(/^[a-z][a-z0-9_]*$/.test(table.name),'Unexpected table identifier');const rows=db.prepare('SELECT * FROM "'+table.name+'"').all().map(row=>JSON.stringify(row,(_,v)=>v instanceof Uint8Array?Buffer.from(v).toString('hex'):v)).sort();result[table.name]={count:rows.length,sha256:sha(Buffer.from(JSON.stringify([table.sql,rows])))};}
 const schema=db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND "+internal+" AND "+filter+" ORDER BY type,name").all();return {tables:result,schema_sha256:sha(Buffer.from(JSON.stringify(schema)))};
}
function qualifyQuarantineSchema(db,files){
 const names=Object.keys(files).filter(n=>migrationName.test(n)).sort();
 const matched=Object.entries(quarantineSchemaProfiles).filter(([,profile])=>JSON.stringify(names)===JSON.stringify(Object.keys(profile.digests).sort())&&names.every(n=>sha(files[n])===profile.digests[n]));
 required(matched.length===1,'Recovery quarantine requires an explicitly qualified schema profile (published9,candidate10,candidate11,candidate12,candidate13,candidate15 or candidate17)');
 const schemaProfile=matched[0][0];
 const reference=new DatabaseSync(':memory:');
 try{
  for(const name of names)installSql(reference,files[name].toString());
  if(['candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile))currentProviderObjects(db);
  const catalog=['candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile)?"SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT IN('_cf_KV','_cf_METADATA','d1_migrations') ORDER BY type,name":"SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name!='d1_migrations' ORDER BY type,name";
  required(JSON.stringify(reference.prepare(catalog).all())===JSON.stringify(db.prepare(catalog).all()),'Recovery snapshot catalog differs from the qualified application schema');
 }finally{reference.close();}
 return schemaProfile;
}
async function sqliteFiles(root){const result=[];for(const e of await readdir(root,{withFileTypes:true})){const p=join(root,e.name);required(!e.isSymbolicLink(),'Recovery state cannot contain aliases');if(e.isDirectory())result.push(...await sqliteFiles(p));else if(e.name.endsWith('.sqlite'))result.push(p);}return result;}

// R2 bodies are streamed separately: the SQL/key archive's 64 MiB limit must
// neither omit bucket contents nor force large objects into process memory.
const OBJECT_FORMAT='collect.platform.objects.v1';
const CAPTURE_FORMAT='collect.r2.capture.v1';
const MAX_OBJECT=5*1024*1024*1024,MAX_OBJECTS=10000;
const canonical=value=>JSON.stringify(value,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
const objectId=key=>sha(Buffer.from(key));
const canonicalTime=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value;
const safeText=(value,limit)=>typeof value==='string'&&Buffer.byteLength(value)<=limit&&Buffer.from(value).toString()===value&&!/[\x00-\x1f\x7f]/.test(value);
function metadataRecord(value){
 required(exact(value,['key','size','etag','version','uploaded','httpMetadata','customMetadata','storageClass'])&&safeText(value.key,1024)&&value.key.length>0&&Number.isSafeInteger(value.size)&&value.size>=0&&value.size<=MAX_OBJECT&&safeText(value.etag,256)&&value.etag.length>0&&(value.version===null||safeText(value.version,256)&&value.version.length>0)&&canonicalTime(value.uploaded)&&['Standard','InfrequentAccess'].includes(value.storageClass),'Invalid R2 object observation');
 const allowed=['contentType','contentLanguage','contentDisposition','contentEncoding','cacheControl','cacheExpiry'];
 required(value.httpMetadata&&typeof value.httpMetadata==='object'&&!Array.isArray(value.httpMetadata)&&Object.keys(value.httpMetadata).every(k=>allowed.includes(k)&&(k==='cacheExpiry'?canonicalTime(value.httpMetadata[k]):safeText(value.httpMetadata[k],2048))),'Invalid R2 HTTP metadata');
 required(value.customMetadata&&typeof value.customMetadata==='object'&&!Array.isArray(value.customMetadata)&&Object.entries(value.customMetadata).every(([k,v])=>safeText(k,1024)&&safeText(v,2048))&&Buffer.byteLength(canonical(value.customMetadata))<=16384,'Invalid R2 custom metadata');
 return value;
}
function completeListing(listing){
 required(exact(listing,['prefix','delimiter','include','pages'])&&listing.prefix===''&&listing.delimiter===null&&canonical(listing.include)===canonical(['httpMetadata','customMetadata'])&&Array.isArray(listing.pages)&&listing.pages.length>0&&listing.pages.length<=MAX_OBJECTS,'A complete unfiltered metadata listing is required');
 const rows=[],keys=new Set(),cursors=new Set();let cursor=null;
 for(let i=0;i<listing.pages.length;i++){
  const page=listing.pages[i],last=i===listing.pages.length-1;
  required(exact(page,['cursor','truncated','next_cursor','objects'])&&page.cursor===cursor&&typeof page.truncated==='boolean'&&page.truncated===!last&&Array.isArray(page.objects),'R2 listing pagination is incomplete');
  for(const value of page.objects){const object=metadataRecord(value);required(!keys.has(object.key)&&rows.length<MAX_OBJECTS,'R2 listing contains duplicate or excessive keys');keys.add(object.key);rows.push(object);}
  if(last)required(page.next_cursor===null,'R2 terminal cursor must be empty');
  else{required(safeText(page.next_cursor,4096)&&page.next_cursor.length>0&&!cursors.has(page.next_cursor),'R2 listing cursor is invalid or repeated');cursors.add(page.next_cursor);cursor=page.next_cursor;}
 }
 return rows.sort((a,b)=>Buffer.compare(Buffer.from(a.key),Buffer.from(b.key)));
}
export function validateR2Capture(capture){
 required(exact(capture,['format','bucket','source_id','captured_at','before','after','downloads'])&&capture.format===CAPTURE_FORMAT&&/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(capture.bucket)&&/^[a-f0-9]{64}$/.test(capture.source_id)&&canonicalTime(capture.captured_at),'Invalid R2 capture identity');
 const before=completeListing(capture.before),after=completeListing(capture.after);
 required(canonical(before)===canonical(after),'R2 objects changed between complete capture listings');
 required(Array.isArray(capture.downloads)&&capture.downloads.length===before.length,'Every listed R2 object requires a full-body download');
 const downloads=new Map();
 for(const row of capture.downloads){required(exact(row,['key','version','etag','sha256'])&&safeText(row.key,1024)&&/^[a-f0-9]{64}$/.test(row.sha256)&&!downloads.has(row.key),'Invalid or duplicate R2 download identity');downloads.set(row.key,row);}
 for(const object of before){const row=downloads.get(object.key);required(row&&row.version===object.version&&row.etag===object.etag,'R2 download does not identify the listed version');}
 return before.map(metadata=>({metadata,sha256:downloads.get(metadata.key).sha256,id:objectId(metadata.key)}));
}
function privateBucket(files){
 const config=JSON.parse(files['wrangler.json']);
 required(config.r2_buckets?.length===1&&config.r2_buckets[0].binding==='PRIVATE_MEDIA'&&config.r2_buckets[0].bucket_name==='collect-platform-private','The authenticated private R2 binding is not qualified');
 return config.r2_buckets[0].bucket_name;
}
function referenceCounts(files,keys,installSnapshot){
 const db=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false}),counts={};
 try{
  installSnapshot(db,files['database.sql'].toString());
  required(db.prepare('PRAGMA integrity_check').get().integrity_check==='ok'&&db.prepare('PRAGMA foreign_key_check').all().length===0,'Captured database is inconsistent');
  const tables=db.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'").all();
  for(const {name} of tables){
   required(/^[a-z][a-z0-9_]*$/.test(name),'Unexpected object reference table');
   for(const column of db.prepare('PRAGMA table_info("'+name+'")').all().filter(c=>c.name==='object_key'||c.name.endsWith('_object_key'))){
    required(/^[a-z][a-z0-9_]*$/.test(column.name),'Unexpected object reference column');
    const rows=db.prepare('SELECT "'+column.name+'" AS object_key FROM "'+name+'" WHERE "'+column.name+'" IS NOT NULL').all();
    for(const row of rows)required(keys.has(row.object_key),'A captured database object reference is missing from the R2 inventory');
    counts[name+'.'+column.name]=rows.length;
   }
  }
  return counts;
 }finally{db.close();}
}

async function verifyApplicationObjectKeys(files,objects,installSnapshot){
 const db=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false}),checks=[];
 try{
  installSnapshot(db,files['database.sql'].toString());
  for(const table of ['payment_evidence','sms_receipts','roster_imports']){
   if(!db.prepare("SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?").get(table))continue;
   for(const row of db.prepare('SELECT * FROM "'+table+'"').all()){
    const roster=table==='roster_imports',key=roster?row.source_object_key:row.object_key,plainSha=roster?row.source_sha256:row.object_sha256,bytes=roster?row.source_size:row.size_bytes;
    required(safeText(row.id,200)&&row.id.length>0&&safeText(key,1024)&&/^[a-f0-9]{64}$/.test(plainSha??'')&&Number.isSafeInteger(bytes)&&bytes>=0&&bytes<=8*1024*1024,'Application object reference is not qualified');
    checks.push({table,key,bytes,sha256:plainSha,document_sha256:roster?row.object_sha256:null,context:roster?'roster-source:'+row.id:(table==='sms_receipts'?'sms:':'evidence:')+row.id+':'+plainSha});
   }
  }
 }finally{db.close();}
 const counts=Object.fromEntries(['payment_evidence','sms_receipts','roster_imports'].map(name=>[name,checks.filter(r=>r.table===name).length]));
 if(checks.length===0)return counts;
 const config=JSON.parse(files['wrangler.json']),keyId=config.vars?.DATA_KEY_ID,keys=privateJson(files['worker-secrets.json']);
 required(validDataKeyId(keyId),'Application data-key identity is unavailable');let key;
 try{key=decode(keys.DATA_ENCRYPTION_KEY,32);}catch{throw new Error('The recovered application data key is invalid.');}
 const historical=historicalDataKeys(config,keys);
 try{
  for(const row of checks){
   const raw=await regular(join(objects,objectId(row.key)+'.bin'),{privateFile:true,maxBytes:12*1024*1024});let plaintext;
   try{
    const document=JSON.parse(raw);required(exact(document,['v','kid','iv','data'])&&document.v===1&&validDataKeyId(document.kid),'Invalid encrypted application object');
    if(row.document_sha256!==null)required(/^[a-f0-9]{64}$/.test(row.document_sha256??'')&&sha(raw)===row.document_sha256,'Application ciphertext identity differs');
    const data=decode(document.data);required(data.length>=16&&data.length<=8*1024*1024+16,'Invalid application object size');
    const selected=document.kid===keyId?key:historical.get(document.kid);required(selected,'Unknown retained application key identity');const decipher=createDecipheriv('aes-256-gcm',selected,decode(document.iv,12));decipher.setAAD(Buffer.from(row.context));decipher.setAuthTag(data.subarray(-16));plaintext=Buffer.concat([decipher.update(data.subarray(0,-16)),decipher.final()]);
    required(plaintext.length===row.bytes&&sha(plaintext)===row.sha256,'Application plaintext identity differs');
   }catch{throw new Error('A retained application object could not be verified with the recovered data key and database reference.');}
   finally{plaintext?.fill(0);}
  }
 }finally{key.fill(0);for(const value of historical.values())value.fill(0);}
 return counts;
}

async function privateObjectDirectory(path,ids,suffix){
 const root=await physical(path),s=await lstat(root);required(s.isDirectory()&&(s.mode&0o077)===0,'R2 object directory must be private and physical');
 const actual=(await readdir(root)).sort(),expected=ids.map(id=>id+suffix).sort();required(canonical(actual)===canonical(expected),'R2 object files are missing or unlisted');return root;
}
async function stableObject(path,work){
 const p=await physical(path),file=await open(p,fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW);
 try{
  const before=await file.stat();required(before.isFile()&&before.nlink===1&&before.size<=MAX_OBJECT&&(before.mode&0o077)===0,'Expected a bounded private independent R2 object');
  const value=await work(file,before),after=await file.stat(),named=await lstat(p);
  required([after,named].every(v=>before.dev===v.dev&&before.ino===v.ino&&before.size===v.size&&before.mtimeMs===v.mtimeMs&&before.ctimeMs===v.ctimeMs&&v.nlink===1)&&!named.isSymbolicLink(),'R2 object changed during recovery');return value;
 }finally{await file.close();}
}
async function writeChunk(file,chunk){let offset=0;while(offset<chunk.length){const {bytesWritten}=await file.write(chunk,offset,chunk.length-offset);required(bytesWritten>0,'R2 recovery write did not advance');offset+=bytesWritten;}}
async function hashObject(path){return stableObject(path,async(file,s)=>{const h=createHash('sha256');for await(const chunk of file.createReadStream({autoClose:false}))h.update(chunk);return {bytes:s.size,sha256:h.digest('hex')};});}
const manifestAad=identity=>Buffer.from(OBJECT_FORMAT+':manifest:'+identity);
const objectAad=(identity,bucket,row)=>Buffer.from(canonical([OBJECT_FORMAT,identity,bucket,row.metadata]));
function sealObjectManifest(value,key,identity){const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,nonce);cipher.setAAD(manifestAad(identity));const raw=Buffer.from(canonical(value));required(raw.length<=MAX,'Object inventory exceeds its control-file bound');const bytes=Buffer.concat([cipher.update(raw),cipher.final()]);return {format:OBJECT_FORMAT,nonce:nonce.toString('base64'),ciphertext:bytes.toString('base64'),tag:cipher.getAuthTag().toString('base64')};}
function openObjectManifest(envelope,key,identity){
 try{required(exact(envelope,['format','nonce','ciphertext','tag'])&&envelope.format===OBJECT_FORMAT,'Invalid object archive');const ciphertext=decode(envelope.ciphertext);required(ciphertext.length<=MAX,'Object inventory is too large');const decipher=createDecipheriv('aes-256-gcm',key,decode(envelope.nonce,12));decipher.setAAD(manifestAad(identity));decipher.setAuthTag(decode(envelope.tag,16));return JSON.parse(Buffer.concat([decipher.update(ciphertext),decipher.final()]));}
 catch{throw new Error('The authenticated R2 inventory could not be verified.');}
}
async function objectArchiveContext(archivePath,keyPath){const archive=await regular(archivePath,{privateFile:true}),key=decode((await regular(keyPath,{privateFile:true})).toString().trim(),32),payload=unseal(JSON.parse(archive),key),files=validatePayload(payload);return {key,payload,files,identity:sha(archive),bucket:privateBucket(files)};}
async function loadedObjectBundle(directory,context,installSnapshot){
 const root=await physical(directory),s=await lstat(root);required(s.isDirectory()&&(s.mode&0o077)===0,'R2 bundle must be private and physical');
 const envelope=await regular(join(root,'objects-backup.json'),{privateFile:true}),value=openObjectManifest(JSON.parse(envelope),context.key,context.identity);
 required(exact(value,['format','platform_archive_sha256','database_id','source_id','bucket','capture','objects'])&&value.format===OBJECT_FORMAT&&value.platform_archive_sha256===context.identity&&value.database_id===DATABASE_ID&&value.source_id===context.payload.source_id&&value.bucket===context.bucket,'R2 archive does not identify this authenticated platform capture');
 const rows=validateR2Capture(value.capture);required(value.capture.source_id===value.source_id&&value.capture.bucket===value.bucket,'R2 archive capture binding differs');
 referenceCounts(context.files,new Set(rows.map(r=>r.metadata.key)),installSnapshot);
 required(Array.isArray(value.objects)&&value.objects.length===rows.length,'R2 encrypted body inventory is incomplete');
 const byId=new Map();
 for(const r of value.objects){required(exact(r,['id','nonce','tag','ciphertext_sha256'])&&/^[a-f0-9]{64}$/.test(r.id)&&/^[a-f0-9]{64}$/.test(r.ciphertext_sha256)&&!byId.has(r.id),'Invalid encrypted R2 body identity');decode(r.nonce,12);decode(r.tag,16);byId.set(r.id,r);}
 for(const row of rows)required(byId.has(row.id),'Missing encrypted R2 body');
 const objects=await privateObjectDirectory(join(root,'objects'),rows.map(r=>r.id),'.aes-gcm');return {root,objects,rows,byId,envelope_sha256:sha(envelope),capture:value.capture};
}
async function recoverObjectBody(path,record,row,context,output){
 const outputFile=output?await open(output,'wx',0o600):null;
 try{return await stableObject(path,async(file,s)=>{
  required(s.size===row.metadata.size,'R2 encrypted body length differs');const h=createHash('sha256'),plain=createHash('sha256'),decipher=createDecipheriv('aes-256-gcm',context.key,decode(record.nonce,12));decipher.setAAD(objectAad(context.identity,context.bucket,row));decipher.setAuthTag(decode(record.tag,16));let bytes=0;
  try{for await(const chunk of file.createReadStream({autoClose:false})){h.update(chunk);const value=decipher.update(chunk);plain.update(value);bytes+=value.length;if(outputFile)await writeChunk(outputFile,value);}const end=decipher.final();plain.update(end);bytes+=end.length;if(outputFile){await writeChunk(outputFile,end);await outputFile.sync();}}
  catch{throw new Error('An authenticated R2 body could not be recovered.');}
  required(bytes===row.metadata.size&&plain.digest('hex')===row.sha256&&h.digest('hex')===record.ciphertext_sha256,'R2 recovered body verification failed');return {bytes};
 });}finally{await outputFile?.close();}
}
function objectProof(context,bundle,extra={}){return {format:OBJECT_FORMAT,platform_archive_sha256:context.identity,source_id:context.payload.source_id,bucket:context.bucket,object_count:bundle.rows.length,total_object_bytes:bundle.rows.reduce((n,r)=>n+r.metadata.size,0),encrypted_inventory_sha256:bundle.envelope_sha256,source_provider_version_ids_observed:bundle.rows.filter(r=>r.metadata.version!==null).length,source_provider_version_ids_unavailable:bundle.rows.filter(r=>r.metadata.version===null).length,all_object_body_bytes_and_metadata_verified:true,remote_execution_proven_by_this_offline_check:false,bucket_version_history_restored:false,bucket_policy_or_lifecycle_recreated:false,accepted_RPO_RTO:false,full_system_recovery_accepted:false,...extra};}
async function r2Action(action,o,installSnapshot){
 const keys=action==='seal-r2'?['--archive','--key','--inventory','--objects','--out']:action==='restore-r2'?['--archive','--key','--bundle','--out']:['--archive','--key','--bundle','--inventory','--objects','--out'];
 required(Object.keys(o).length===keys.length&&keys.every(k=>o[k]),`${action} requires ${keys.join(' ')}`);
 const context=await objectArchiveContext(o['--archive'],o['--key']);
 if(action==='seal-r2'){
  const raw=await regular(o['--inventory'],{privateFile:true,maxBytes:MAX}),capture=privateJson(raw),rows=validateR2Capture(capture);
  required(capture.bucket===context.bucket&&capture.source_id===context.payload.source_id&&Date.parse(capture.captured_at)>=Date.parse(context.payload.captured_at),'R2 capture does not identify the platform archive');
  const references=referenceCounts(context.files,new Set(rows.map(r=>r.metadata.key)),installSnapshot),source=await privateObjectDirectory(o['--objects'],rows.map(r=>r.id),'.bin'),applicationKeyChecks=await verifyApplicationObjectKeys(context.files,source,installSnapshot),out=await freshDirectory(o['--out']);await mkdir(join(out,'objects'),{mode:0o700});const encrypted=[];
  for(const row of rows){
   const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',context.key,nonce);cipher.setAAD(objectAad(context.identity,context.bucket,row));const target=await open(join(out,'objects',row.id+'.aes-gcm'),'wx',0o600),body=createHash('sha256'),ciphertext=createHash('sha256');let bytes=0;
   try{await stableObject(join(source,row.id+'.bin'),async(file,s)=>{required(s.size===row.metadata.size,'R2 captured body length differs');for await(const chunk of file.createReadStream({autoClose:false})){body.update(chunk);bytes+=chunk.length;const value=cipher.update(chunk);ciphertext.update(value);await writeChunk(target,value);}const end=cipher.final();ciphertext.update(end);await writeChunk(target,end);await target.sync();});}finally{await target.close();}
   required(bytes===row.metadata.size&&body.digest('hex')===row.sha256,'R2 captured body verification failed');encrypted.push({id:row.id,nonce:nonce.toString('base64'),tag:cipher.getAuthTag().toString('base64'),ciphertext_sha256:ciphertext.digest('hex')});
  }
  await privateObjectDirectory(source,rows.map(r=>r.id),'.bin');
  const value={format:OBJECT_FORMAT,platform_archive_sha256:context.identity,database_id:DATABASE_ID,source_id:context.payload.source_id,bucket:context.bucket,capture,objects:encrypted},envelope=Buffer.from(JSON.stringify(sealObjectManifest(value,context.key,context.identity))+'\n');
  await exclusive(join(out,'objects-backup.json'),envelope);const bundle=await loadedObjectBundle(out,context,installSnapshot);for(const row of bundle.rows)await recoverObjectBody(join(bundle.objects,row.id+'.aes-gcm'),bundle.byId.get(row.id),row,context);
  await exclusive(join(out,'receipt.json'),Buffer.from(JSON.stringify(objectProof(context,bundle,{sealed:true,all_new_ciphertexts_independently_decrypted:true,capture_sha256:sha(raw),database_reference_counts:references,application_data_key_verified_counts:applicationKeyChecks}),null,2)+'\n'));
  console.log(JSON.stringify({sealed:true,object_count:rows.length,remote_execution_proven:false,full_system_recovery_accepted:false}));return;
 }
 const bundle=await loadedObjectBundle(o['--bundle'],context,installSnapshot);
 if(action==='restore-r2'){
  const out=await freshDirectory(o['--out']);await mkdir(join(out,'objects'),{mode:0o700});
  for(const row of bundle.rows)await recoverObjectBody(join(bundle.objects,row.id+'.aes-gcm'),bundle.byId.get(row.id),row,context,join(out,'objects',row.id+'.bin'));
  // Metadata remains private. Original provider versions/timestamps are
  // provenance; a new R2 upload necessarily receives a different version.
  await exclusive(join(out,'restore-index.json'),Buffer.from(JSON.stringify({format:OBJECT_FORMAT,source_id:context.payload.source_id,bucket:context.bucket,objects:bundle.rows},null,2)+'\n'));
  await exclusive(join(out,'verification.json'),Buffer.from(JSON.stringify(objectProof(context,bundle,{actual_independent_local_body_restore:true,application_data_key_verified_counts:await verifyApplicationObjectKeys(context.files,join(out,'objects'),installSnapshot)}),null,2)+'\n'));
  console.log(JSON.stringify({restored:true,object_count:bundle.rows.length,remote_execution_proven:false,full_system_recovery_accepted:false}));return;
 }
 const raw=await regular(o['--inventory'],{privateFile:true,maxBytes:MAX}),capture=privateJson(raw),rows=validateR2Capture(capture);
 required(capture.source_id===context.payload.source_id&&capture.bucket!==context.bucket&&Date.parse(capture.captured_at)>=Date.parse(bundle.capture.captured_at),'R2 readback must identify a later separately named isolated bucket');
 const recoverable=row=>({key:row.metadata.key,size:row.metadata.size,httpMetadata:row.metadata.httpMetadata,customMetadata:row.metadata.customMetadata,storageClass:row.metadata.storageClass,sha256:row.sha256});
 required(canonical(rows.map(recoverable))===canonical(bundle.rows.map(recoverable)),'Isolated R2 readback keys, bytes or recoverable metadata differ');
 const source=await privateObjectDirectory(o['--objects'],rows.map(r=>r.id),'.bin');
 for(const row of bundle.rows)await recoverObjectBody(join(bundle.objects,row.id+'.aes-gcm'),bundle.byId.get(row.id),row,context);
 for(const row of rows){const value=await hashObject(join(source,row.id+'.bin'));required(value.bytes===row.metadata.size&&value.sha256===row.sha256,'Isolated R2 body readback differs');}
 const out=await freshDirectory(o['--out']);await exclusive(join(out,'verification.json'),Buffer.from(JSON.stringify(objectProof(context,bundle,{isolated_bucket:capture.bucket,independent_target_body_readback:true,all_opaque_application_ciphertexts_match:true,application_data_key_verified_counts:await verifyApplicationObjectKeys(context.files,source,installSnapshot),provider_version_and_uploaded_fields_intentionally_reissued:true}),null,2)+'\n'));
 console.log(JSON.stringify({verified:true,object_count:rows.length,remote_execution_proven:false,full_system_recovery_accepted:false}));
}

export async function main(argv,{splitSqlQuery=null}={}){const [action,...rest]=argv,o=options(rest);
 const snapshotActions=new Set(['verify-local','prepare-quarantine','verify-readback','verify-quarantine-readback','seal-r2','restore-r2','verify-r2-readback']);
 required(!Object.hasOwn(o,'--wrangler')||snapshotActions.has(action),'The SQL parser option is available only to snapshot consumers');
 const parserDirectory=o['--wrangler']??process.env.COLLECT_WRANGLER_MODULE;
 if(action!=='verify-local')delete o['--wrangler'];
 let parser=splitSqlQuery;const installSnapshot=(db,sql)=>{parser??=loadLockedSnapshotParser(parserDirectory);return installSnapshotSql(db,sql,parser);};
 if(['seal-r2','restore-r2','verify-r2-readback'].includes(action))return r2Action(action,o,installSnapshot);
 if(action==='seal'){
  required(Object.keys(o).length===4&&['--sql','--config','--secrets','--out'].every(k=>o[k]),'seal requires --sql --config --secrets --out');
  const configRaw=await regular(o['--config']),config=JSON.parse(configRaw),files={};
  const add=(name,raw)=>{files[name]={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};};
  add('database.sql',await regular(o['--sql'],{privateFile:true}));add('wrangler.json',configRaw);add('worker-secrets.json',await regular(o['--secrets'],{privateFile:true}));
  for(const name of (await readdir(join(dirname(resolve(o['--config'])),'migrations'))).sort()){if(migrationName.test('migrations/'+name))add('migrations/'+name,await regular(join(dirname(resolve(o['--config'])),'migrations',name)));}
  const payload={format:FORMAT,database_id:DATABASE_ID,source_id:config.vars?.BUILD_SOURCE_ID,captured_at:new Date().toISOString(),files},decoded=validatePayload(payload);
  const out=await freshDirectory(o['--out']),key=randomBytes(32),envelope=seal(payload,key),archive=Buffer.from(JSON.stringify(envelope)+'\n');
  await exclusive(join(out,'recovery-key.base64'),Buffer.from(key.toString('base64')+'\n'));await exclusive(join(out,'platform-backup.json'),archive);
  await exclusive(join(out,'receipt.json'),Buffer.from(JSON.stringify({format:FORMAT,database_id:DATABASE_ID,source_id:payload.source_id,archive_sha256:sha(archive),authenticated_encryption:'AES-256-GCM',private_roles:Object.keys(files).length,worker_secret_roles:recoverySecretRoles(config,privateJson(decoded['worker-secrets.json']),exactMigrationProfile(payload,Object.keys(payload.files).filter(n=>migrationName.test(n)).sort())).sort(),r2_objects_included:false,full_system_recovery_accepted:false},null,2)+'\n'));
  console.log(JSON.stringify({sealed:true,directory:out,archive_sha256:sha(archive),full_system_recovery_accepted:false}));return;
 }
 if(action==='verify-local'){
  required(Object.keys(o).length===4&&['--archive','--key','--out','--wrangler'].every(k=>o[k]),'verify-local requires --archive --key --out --wrangler');
  const key=decode((await regular(o['--key'],{privateFile:true})).toString().trim(),32),payload=unseal(JSON.parse(await regular(o['--archive'],{privateFile:true})),key),files=validatePayload(payload),out=await freshDirectory(o['--out']);
  const runtime=resolve(o['--wrangler']);required(JSON.parse(await regular(join(runtime,'package.json'))).version==='4.151.0','Use the qualified locked Wrangler 4.151.0 runtime');
  for(const [name,raw] of Object.entries(files)){const p=join(out,name);await mkdir(dirname(p),{recursive:true,mode:0o700});await exclusive(p,raw);}
  const baseline=new DatabaseSync(join(out,'baseline.sqlite'),{enableForeignKeyConstraints:false});installSnapshot(baseline,files['database.sql'].toString());const before=fingerprint(baseline,currentSnapshot(payload));required(baseline.prepare('PRAGMA integrity_check').get().integrity_check==='ok'&&baseline.prepare('PRAGMA foreign_key_check').all().length===0,'Captured database is inconsistent');const normalized=restoreSql(baseline);await exclusive(join(out,'restore.sql'),Buffer.from(normalized));
  let restoreMode='parent_first_phases_available',qualifiedViewsSchemaProfile;
  try{for(const [name,sql] of Object.entries(restorePhases(baseline)))await exclusive(join(out,'restore-'+name+'.sql'),Buffer.from(sql));}
  catch(error){
   const cyclic=String(error.message).startsWith('Parent-first replay cannot safely restore cyclic populated foreign keys;');
   const schemaProfile=exactMigrationProfile(payload,Object.keys(payload.files).filter(n=>migrationName.test(n)).sort());
   const qualifiedViewsProfile=['candidate13','candidate17'].includes(schemaProfile);
   const knownViews=error.message==='Views require a separately qualified dependency order'&&qualifiedViewsProfile;
   if(!cyclic&&!knownViews)throw error;
   if(knownViews||(cyclic&&qualifiedViewsProfile)){
    // Exact authenticated13/17 catalogs qualify these two independent final
    // views. Both cyclic and acyclic cases receive the same catalog guard;
    // other historical profiles keep their existing behavior. No SQL is sent
    // until the complete known application catalog comparison succeeds.
    required(qualifyQuarantineSchema(baseline,files)===schemaProfile,'Views require the exact qualified candidate13 or candidate17 application schema');
    if(knownViews)qualifiedViewsSchemaProfile=schemaProfile;
   }
   // Genuine Auth/MFA rows may reference each other. Locked Wrangler4.151.0
   // execute --local --file submits the complete file as one D1 batch. Keep
   // its deferred-FK transaction intact; never emit unsafe split data phases.
   restoreMode='single_D1_batch_with_deferred_foreign_keys';
   await exclusive(join(out,'restore-transaction.json'),Buffer.from(JSON.stringify({mode:restoreMode,...(qualifiedViewsSchemaProfile?{qualified_views_schema_profile:qualifiedViewsSchemaProfile}:{}),requires_same_D1_batch:true,split_phase_import_supported:false,foreign_keys_disabled:false,qualified_locked_wrangler:'4.151.0'},null,2)+'\n'));
  }
  baseline.close();
  await command([join(runtime,'bin/wrangler.js'),'d1','execute','collect-platform','--local','--config',join(out,'wrangler.json'),'--persist-to',join(out,'isolated-state'),'--file',join(out,'restore.sql'),'--yes'],join(out,'local-import.log'));
  const databases=await sqliteFiles(join(out,'isolated-state')),domain=[];for(const path of databases){const db=new DatabaseSync(path,{readOnly:true});try{const names=db.prepare("SELECT name FROM sqlite_schema WHERE type='table'").all().map(r=>r.name);if(names.includes('auth_sessions')&&names.includes('admin_bridge_requests'))domain.push(path);else required(names.every(n=>n==='_cf_ALARM'),'Unexpected additional recovery database');}finally{db.close();}}required(domain.length===1,'Expected one authenticated domain D1');const restored=new DatabaseSync(domain[0],{readOnly:true}),after=fingerprint(restored,currentSnapshot(payload));required(restored.prepare('PRAGMA integrity_check').get().integrity_check==='ok'&&restored.prepare('PRAGMA foreign_key_check').all().length===0&&JSON.stringify(before)===JSON.stringify(after),'Isolated D1 does not match the authenticated backup');restored.close();
  const record={format:FORMAT,database_id:DATABASE_ID,source_id:payload.source_id,actual_local_D1_import:true,provider_bootstrap_metadata_databases:databases.length-domain.length,independent_SQLite_comparison:true,restore_order:'all authenticated table schemas before exact data, indexes, triggers and views',restore_mode:restoreMode,...(qualifiedViewsSchemaProfile?{qualified_views_schema_profile:qualifiedViewsSchemaProfile}:{}),foreign_keys_disabled:false,all_table_rows_and_schema_match:true,all_indexes_triggers_and_views_match:true,tables:Object.fromEntries(Object.entries(after.tables).map(([name,r])=>[name,r.count])),foreign_key_errors:0,integrity_check:'ok',worker_keys_recovered:true,worker_secret_roles:Object.keys(JSON.parse(files['worker-secrets.json'])).sort(),remote_restore_executed:false,r2_objects_recovered:false,accepted_RPO_RTO:false,full_system_recovery_accepted:false};
  await exclusive(join(out,'verification.json'),Buffer.from(JSON.stringify(record,null,2)+'\n'));console.log(JSON.stringify({verified:true,tables:Object.keys(after.tables).length,foreign_key_errors:0,remote_restore_executed:false,full_system_recovery_accepted:false}));return;
 }
 if(action==='prepare-quarantine'){
  required(Object.keys(o).length===5&&['--archive','--key','--operation','--at','--out'].every(k=>o[k]),'prepare-quarantine requires --archive --key --operation --at --out');
  const key=decode((await regular(o['--key'],{privateFile:true})).toString().trim(),32),archive=await regular(o['--archive'],{privateFile:true}),payload=unseal(JSON.parse(archive),key),files=validatePayload(payload);
  required(Date.parse(o['--at'])>=Date.parse(payload.captured_at),'Recovery quarantine cannot predate the authenticated capture');
  const db=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false});
  try{
   installSnapshot(db,files['database.sql'].toString());const schemaProfile=qualifyQuarantineSchema(db,files);
   const plan=recoveryQuarantinePlan({archiveSha256:sha(archive),sourceId:payload.source_id,operationId:o['--operation'],createdAt:o['--at'],schemaProfile});
   const before=fingerprint(db,currentSnapshot(payload));applyRecoveryQuarantine(db,plan);const after=fingerprint(db,currentSnapshot(payload));
   required(before.schema_sha256===after.schema_sha256,'Recovery quarantine changed the database schema');
   const changed=Object.keys(before.tables).filter(name=>JSON.stringify(before.tables[name])!==JSON.stringify(after.tables[name]));
   required(changed.every(name=>quarantineMutableTables.has(name)),'Recovery quarantine changed a protected data table');
   // This complete snapshot is a local transactional replay artifact. Hosted
   // D1 recovery uses the separately qualified import followed by one batch.
   const out=await freshDirectory(o['--out']),restore=Buffer.from('BEGIN;\n'+restoreSql(db)+'COMMIT;\n');
   await exclusive(join(out,'quarantine-plan.json'),Buffer.from(JSON.stringify(plan,null,2)+'\n'));
   await exclusive(join(out,'quarantined-restore.sql'),restore);
   const record={format:plan.format,database_id:DATABASE_ID,archive_sha256:plan.archive_sha256,source_id:payload.source_id,operation_id:plan.operation_id,created_at:plan.created_at,
    ...(['candidate11','candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile)?{identity_alias_history_retained:true,identity_key_configuration_recovered:true}:{}),
    ...(['candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile)?{assisted_sms_history_retained:true,decision_receipt_heads_preserved:true,assisted_sms_send_authority_restored:false}:{}),...(['candidate15','candidate17'].includes(schemaProfile)?{momo_history_retained:true,momo_gateway_authority_restored:false,momo_processing_recovery_review_required:true,momo_processing_budgets_retained:true,transient_momo_guards_drained:true}:{}),...(schemaProfile==='candidate17'?{google_identity_history_retained:true,google_pending_handoffs_disabled:true,admin_email_otp_authority_restored:false}:{}),schema_profile:schemaProfile,offline_preparation_only:true,remote_execution:false,all_captured_financial_and_object_rows_unchanged:true,schema_unchanged:true,changed_tables:changed,
    ...(['candidate10','candidate11','candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile)?{retained_retention_control_rows_unchanged:true,transient_retention_guards_drained:true,subject_retention_barriers_released:false,retention_policy_repinned:false}:{}),
    all_restored_principals_require_reapproval:true,restored_passwords_and_factors_disabled:true,quarantined_sql_sha256:sha(restore),foreign_key_errors:0,integrity_check:'ok',
    provider_sends_disabled_by_this_SQL:false,independent_key_custody_accepted:false,post_snapshot_revocations_reconciled:false,production_cutover_accepted:false,full_system_recovery_accepted:false};
   await exclusive(join(out,'preparation.json'),Buffer.from(JSON.stringify(record,null,2)+'\n'));
   console.log(JSON.stringify({prepared:true,offline_only:true,directory:out,remote_execution:false,production_cutover_accepted:false}));return;
  }finally{db.close();}
 }
 if(action==='verify-readback'||action==='verify-quarantine-readback'){
  const quarantine=action==='verify-quarantine-readback',keys=['--archive','--key','--sql','--out',...(quarantine?['--plan']:[])];
  required(Object.keys(o).length===keys.length&&keys.every(k=>o[k]),`${action} requires ${keys.join(' ')}`);
  const key=decode((await regular(o['--key'],{privateFile:true})).toString().trim(),32),archive=await regular(o['--archive'],{privateFile:true}),payload=unseal(JSON.parse(archive),key),files=validatePayload(payload),sql=await regular(o['--sql'],{privateFile:true});
  const baseline=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false}),readback=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false});
  try{
   installSnapshot(baseline,files['database.sql'].toString());try{installSnapshot(readback,sql.toString());}catch(error){throw new Error('Readback differs from the authenticated backup: invalid constrained snapshot',{cause:error});}
   let plan;
   let schemaProfile;
   if(quarantine){schemaProfile=qualifyQuarantineSchema(baseline,files);plan=JSON.parse(await regular(o['--plan'],{privateFile:true}));required(plan.archive_sha256===sha(archive)&&plan.source_id===payload.source_id&&Date.parse(plan.created_at)>=Date.parse(payload.captured_at)&&(plan.schema_profile??'published9')===schemaProfile,'Recovery plan does not identify this authenticated archive/profile');applyRecoveryQuarantine(baseline,plan);}
   const before=fingerprint(baseline,currentSnapshot(payload)),after=fingerprint(readback,currentSnapshot(payload)),integrity=readback.prepare('PRAGMA integrity_check').get().integrity_check,foreignKeys=readback.prepare('PRAGMA foreign_key_check').all();
   required(baseline.prepare('PRAGMA integrity_check').get().integrity_check==='ok'&&baseline.prepare('PRAGMA foreign_key_check').all().length===0&&integrity==='ok'&&foreignKeys.length===0&&JSON.stringify(before)===JSON.stringify(after),'Recovery readback differs from the authenticated backup');
   const out=await freshDirectory(o['--out']),record={format:quarantine?plan.format:FORMAT,database_id:DATABASE_ID,source_id:payload.source_id,sql_sha256:sha(sql),authenticated_snapshot_match:!quarantine,authenticated_quarantined_snapshot_match:quarantine,...(quarantine?{schema_profile:schemaProfile,...(['candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile)?{assisted_sms_history_retained:true,decision_receipt_heads_preserved:true,assisted_sms_send_authority_restored:false}:{}),...(['candidate15','candidate17'].includes(schemaProfile)?{momo_history_retained:true,momo_gateway_authority_restored:false,momo_processing_recovery_review_required:true,momo_processing_budgets_retained:true}:{}),...(schemaProfile==='candidate17'?{google_identity_history_retained:true,google_pending_handoffs_disabled:true,admin_email_otp_authority_restored:false}:{}),operation_id:plan.operation_id,archive_sha256:plan.archive_sha256,all_restored_principals_require_reapproval:true,production_cutover_accepted:false,...(['candidate10','candidate11','candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile)?{retained_retention_control_rows_unchanged:true,subject_retention_barriers_released:false,retention_policy_repinned:false}:{})}:{}),table_count:Object.keys(after.tables).length,all_table_rows_and_schema_match:true,all_indexes_triggers_and_views_match:true,sqlite_sequence_match:true,worker_secret_roles:Object.keys(JSON.parse(files['worker-secrets.json'])).sort(),foreign_key_errors:0,integrity_check:integrity,remote_execution_proven_by_this_offline_check:false,full_system_recovery_accepted:false};
   await exclusive(join(out,'verification.json'),Buffer.from(JSON.stringify(record,null,2)+'\n'));console.log(JSON.stringify({verified:true,tables:record.table_count,remote_execution_proven:false,full_system_recovery_accepted:false}));return;
  }finally{baseline.close();readback.close();}
 }
 throw new Error('Use seal, verify-local, verify-readback, prepare-quarantine, verify-quarantine-readback, seal-r2, restore-r2 or verify-r2-readback. This tool has no remote restore operation.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main(process.argv.slice(2)).catch(e=>{console.error(e.message);process.exitCode=1;});
