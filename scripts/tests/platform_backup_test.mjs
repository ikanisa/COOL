import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,createCipheriv,randomBytes} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {mkdtemp,writeFile,readFile,access,mkdir,symlink,link,rm,realpath,chmod,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {seal,unseal,validatePayload,installSql,restoreSql,restorePhases,validateR2Capture,main} from '../cloudflare/platform_backup.mjs';
const database='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
const sha=b=>createHash('sha256').update(b).digest('hex');
function fixture(){const config={name:'collect-platform-api',d1_databases:[{database_id:database}],vars:{BUILD_SOURCE_ID:'f'.repeat(64)}};
 const values={'database.sql':'CREATE TABLE notes(id TEXT PRIMARY KEY,value TEXT); INSERT INTO notes VALUES(\'one\',\'controlled\');','wrangler.json':JSON.stringify(config),'worker-secrets.json':JSON.stringify({AUTH_JWT_SECRET:'a'.repeat(64),AUTH_TOKEN_HASH_SECRET:'b'.repeat(64),DATA_ENCRYPTION_KEY:'c'.repeat(64)})};
 for(let i=1;i<=8;i++)values[`migrations/000${i}_controlled.sql`]='-- controlled migration '+i;
 return {format:'collect.platform.backup.v1',database_id:database,source_id:'f'.repeat(64),captured_at:'2026-10-15T00:00:00.000Z',files:Object.fromEntries(Object.entries(values).map(([name,text])=>{const b=Buffer.from(text);return [name,{sha256:sha(b),bytes:b.length,base64:b.toString('base64')}];}))};}
for(const kind of ['core','turnstile','historical'])test('actual seal command finishes a verifiable private receipt for '+kind+' roles',async t=>{
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-backup-seal-command-')));t.after(()=>rm(root,{recursive:true,force:true}));
 const payload=kind==='historical'?keyringFixture():kind==='turnstile'?turnstileFixture():fixture();
 await mkdir(join(root,'migrations'),{mode:0o700});
 for(const [name,role]of Object.entries(payload.files))await writeFile(join(root,name),Buffer.from(role.base64,'base64'),{mode:0o600});
 const out=join(root,'sealed');await main(['seal','--sql',join(root,'database.sql'),'--config',join(root,'wrangler.json'),'--secrets',join(root,'worker-secrets.json'),'--out',out]);
 const bytes=await readFile(join(out,'platform-backup.json')),key=Buffer.from((await readFile(join(out,'recovery-key.base64'),'utf8')).trim(),'base64'),restored=unseal(JSON.parse(bytes),key),receipt=JSON.parse(await readFile(join(out,'receipt.json')));
 assert.deepEqual(restored.files,payload.files);assert.equal(receipt.archive_sha256,sha(bytes));
 const roles=JSON.parse(validatePayload(restored)['worker-secrets.json']);assert.deepEqual(receipt.worker_secret_roles,Object.keys(roles).sort());
 assert.equal(receipt.full_system_recovery_accepted,false);assert.equal(receipt.r2_objects_included,false);
 for(const value of Object.values(roles))assert.ok(!JSON.stringify(receipt).includes(value));
});
test('a recovered independent key restores exact private role bytes',()=>{const p=fixture(),key=randomBytes(32),envelope=seal(p,key);assert.deepEqual(unseal(envelope,Buffer.from(key.toString('base64'),'base64')),p);assert.equal(JSON.stringify(envelope).includes('controlled'),false);assert.equal(JSON.stringify(envelope).includes('AUTH_JWT_SECRET'),false);});
test('fresh nonces prevent repeated captures revealing equal plaintext',()=>{const p=fixture(),key=randomBytes(32),a=seal(p,key),b=seal(p,key);assert.notEqual(a.nonce,b.nonce);assert.notEqual(a.ciphertext,b.ciphertext);assert.deepEqual(unseal(a,key),unseal(b,key));});
for(const field of ['nonce','ciphertext','tag'])test(`tampered ${field} cannot be restored`,()=>{const key=randomBytes(32),e=seal(fixture(),key),bytes=Buffer.from(e[field],'base64');bytes[0]^=1;e[field]=bytes.toString('base64');assert.throws(()=>unseal(e,key),/could not be verified/);});
test('an unrelated key cannot restore or expose details',()=>{assert.throws(()=>unseal(seal(fixture(),randomBytes(32)),randomBytes(32)),e=>e.message==='The authenticated backup could not be verified.');});
test('an unsupported envelope field is refused',()=>{const key=randomBytes(32);assert.throws(()=>unseal({...seal(fixture(),key),algorithm:'none'},key));});
for(const size of [0,16,31,33])test(`a ${size}-byte key cannot seal a backup`,()=>assert.throws(()=>seal(fixture(),Buffer.alloc(size)),/256-bit/));
test('a database from another service is refused',()=>{const p=fixture();p.database_id='foreign';assert.throws(()=>validatePayload(p),/identity/);});
test('a traversal or substituted file role is refused',()=>{const p=fixture();p.files['../worker-secrets.json']=p.files['worker-secrets.json'];delete p.files['worker-secrets.json'];assert.throws(()=>validatePayload(p),/roles/);});
test('all eight migration identities are required',()=>{const p=fixture();p.files['migrations/0001_other.sql']=p.files['migrations/0008_controlled.sql'];delete p.files['migrations/0008_controlled.sql'];assert.throws(()=>validatePayload(p),/migration/);});
test('the next migration is included in an authenticated archive without dropping the original eight',()=>{const p=fixture();p.files['migrations/0009_operator_notes.sql']=p.files['migrations/0008_controlled.sql'];const key=randomBytes(32);assert.deepEqual(unseal(seal(p,key),key),p);assert.equal(Object.keys(validatePayload(p)).length,12);});
test('an additional migration cannot skip an unpublished number',()=>{const p=fixture();p.files['migrations/0010_gap.sql']=p.files['migrations/0008_controlled.sql'];assert.throws(()=>validatePayload(p),/migration/);});
test('duplicate migration numbers remain invalid after the baseline',()=>{const p=fixture();p.files['migrations/0009_notes.sql']=p.files['migrations/0008_controlled.sql'];p.files['migrations/0009_other.sql']=p.files['migrations/0008_controlled.sql'];assert.throws(()=>validatePayload(p),/migration/);});
test('archive byte or size claims must agree',()=>{for(const field of ['sha256','bytes']){const p=fixture();p.files['database.sql'][field]=field==='bytes'?1:'0'.repeat(64);assert.throws(()=>validatePayload(p),/verification/);}});
test('all runtime encryption and authentication key roles are required',()=>{const p=fixture(),raw=Buffer.from(JSON.stringify({AUTH_JWT_SECRET:'a'.repeat(64)}));p.files['worker-secrets.json']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};assert.throws(()=>validatePayload(p),/key recovery/);});
function replaceRole(p,name,value){const raw=Buffer.from(JSON.stringify(value));p.files[name]={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};}
function turnstileFixture(){const p=fixture(),config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64'));config.vars.TURNSTILE_SITE_KEY='p'.repeat(24);replaceRole(p,'wrangler.json',config);const keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));keys.TURNSTILE_SECRET='s'.repeat(35);replaceRole(p,'worker-secrets.json',keys);return p;}
test('a configured Turnstile key recovers its exact secret with all core keys',()=>{const p=turnstileFixture(),key=randomBytes(32),restored=unseal(seal(p,key),key);assert.deepEqual(restored,p);assert.equal(JSON.parse(validatePayload(restored)['worker-secrets.json']).TURNSTILE_SECRET,'s'.repeat(35));});
test('configured Turnstile cannot be omitted from a successful recovery archive',()=>{const p=turnstileFixture(),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));delete keys.TURNSTILE_SECRET;replaceRole(p,'worker-secrets.json',keys);assert.throws(()=>validatePayload(p),/key recovery/);});
test('legacy empty public key remains readable with its three exact core keys',()=>{const p=fixture(),config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64'));config.vars.TURNSTILE_SITE_KEY='';replaceRole(p,'wrangler.json',config);const key=randomBytes(32);assert.deepEqual(unseal(seal(p,key),key),p);});
test('an orphan or unknown provider secret is not silently admitted',()=>{for(const name of ['TURNSTILE_SECRET','OTP_DELIVERY_TOKEN']){const p=fixture(),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));keys[name]='s'.repeat(35);replaceRole(p,'worker-secrets.json',keys);assert.throws(()=>validatePayload(p),/key recovery/);}});
for(const value of ['',null,35,'short','field Value: '+ 's'.repeat(35)])test(`configured Turnstile refuses a missing, malformed or wrapped secret ${JSON.stringify(value)?.length}`,()=>{const p=turnstileFixture(),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));keys.TURNSTILE_SECRET=value;replaceRole(p,'worker-secrets.json',keys);assert.throws(()=>validatePayload(p),/key recovery/);});
for(const value of [true,' field Value: '+ 'p'.repeat(24),' '.repeat(24)])test(`malformed public Turnstile configuration is not treated as legacy ${JSON.stringify(value).length}`,()=>{const p=fixture(),config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64'));config.vars.TURNSTILE_SITE_KEY=value;replaceRole(p,'wrangler.json',config);assert.throws(()=>validatePayload(p),/Turnstile recovery configuration/);});
test('SQL recovery admits ordinary schema and data',()=>{const db=new DatabaseSync(':memory:');try{installSql(db,Buffer.from(fixture().files['database.sql'].base64,'base64').toString());assert.deepEqual({...db.prepare('SELECT * FROM notes').get()},{id:'one',value:'controlled'});}finally{db.close();}});
for(const sql of ["ATTACH DATABASE ':memory:' AS outside",'PRAGMA writable_schema=ON',"SELECT load_extension('untrusted')"])test(`SQL recovery refuses external or unsafe execution: ${sql.split(' ')[0]}`,()=>{const db=new DatabaseSync(':memory:');try{assert.throws(()=>installSql(db,sql),/authoriz|permitted/);}finally{db.close();}});

test('schema-first restore retains child-first export data, binary values and allocation sequence',()=>{
 const source=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false}),restored=new DatabaseSync(':memory:');
 try{installSql(source,"CREATE TABLE child(id INTEGER PRIMARY KEY AUTOINCREMENT,parent_id INTEGER REFERENCES parent(id),note TEXT,body BLOB); INSERT INTO child VALUES(4,2,'quote'' and Unicode Rwanda 🇷🇼',X'000102'); CREATE TABLE parent(id INTEGER PRIMARY KEY); INSERT INTO parent VALUES(2); UPDATE sqlite_sequence SET seq=9 WHERE name='child';");
  installSql(restored,'BEGIN;'+restoreSql(source)+'COMMIT;');assert.equal(restored.prepare('PRAGMA foreign_key_check').all().length,0);
  assert.deepEqual({...restored.prepare('SELECT * FROM child').get()},{...source.prepare('SELECT * FROM child').get()});assert.equal(restored.prepare('SELECT seq FROM sqlite_sequence').get().seq,9);
 }finally{source.close();restored.close();}
});

test('phased restore orders populated parents first without an enclosing transaction',()=>{
 const source=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false}),restored=new DatabaseSync(':memory:');
 try{
  installSql(source,"CREATE TABLE a_child(id INTEGER PRIMARY KEY AUTOINCREMENT,parent_id INTEGER REFERENCES z_parent(id),body BLOB);CREATE TABLE z_parent(id INTEGER PRIMARY KEY,name TEXT);INSERT INTO a_child VALUES(4,2,X'000102');INSERT INTO z_parent VALUES(2,'Rwanda 🇷🇼');UPDATE sqlite_sequence SET seq=9 WHERE name='a_child';CREATE INDEX child_parent ON a_child(parent_id);CREATE TRIGGER immutable_child BEFORE UPDATE ON a_child BEGIN SELECT RAISE(ABORT,'immutable');END;");
  const phases=restorePhases(source);assert.deepEqual(Object.keys(phases),['tables','data','indexes','triggers']);
  for(const sql of Object.values(phases))installSql(restored,sql);
  assert.deepEqual({...restored.prepare('SELECT * FROM a_child').get()},{...source.prepare('SELECT * FROM a_child').get()});
  assert.deepEqual({...restored.prepare('SELECT * FROM z_parent').get()},{...source.prepare('SELECT * FROM z_parent').get()});
  assert.equal(restored.prepare('SELECT seq FROM sqlite_sequence').get().seq,9);assert.equal(restored.prepare('PRAGMA foreign_key_check').all().length,0);
  assert.throws(()=>restored.exec('UPDATE a_child SET parent_id=2'),/immutable/);
 }finally{source.close();restored.close();}
});
test('phased replay refuses populated cycles instead of dropping rows or constraints',()=>{
 const source=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false});
 try{installSql(source,'CREATE TABLE a(id INTEGER PRIMARY KEY,b_id INTEGER REFERENCES b(id));CREATE TABLE b(id INTEGER PRIMARY KEY,a_id INTEGER REFERENCES a(id));INSERT INTO a VALUES(1,1);INSERT INTO b VALUES(1,1);');assert.throws(()=>restorePhases(source),/cyclic populated foreign keys/);assert.equal(source.prepare('SELECT count(*) AS n FROM a').get().n,1);}
 finally{source.close();}
});
test('empty and null-only foreign keys do not invent a populated dependency cycle',()=>{
 const source=new DatabaseSync(':memory:'),restored=new DatabaseSync(':memory:');
 try{installSql(source,'CREATE TABLE a(id INTEGER PRIMARY KEY,b_id INTEGER REFERENCES b(id));CREATE TABLE b(id INTEGER PRIMARY KEY,a_id INTEGER REFERENCES a(id));INSERT INTO a VALUES(1,NULL);INSERT INTO b VALUES(1,NULL);CREATE TABLE empty(id INTEGER PRIMARY KEY);');for(const sql of Object.values(restorePhases(source)))installSql(restored,sql);assert.equal(restored.prepare('SELECT count(*) AS n FROM a').get().n,1);assert.equal(restored.prepare('SELECT count(*) AS n FROM empty').get().n,0);}
 finally{source.close();restored.close();}
});

for(const changed of [false,true])test(`offline SQL readback compares the authenticated captured rows changed=${changed}`,async()=>{
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-backup-readback-')));
 try{
  const key=randomBytes(32),payload=fixture(),archive=join(root,'backup.json'),keyFile=join(root,'recovery-key.base64'),sql=join(root,'readback.sql'),out=join(root,'verified');
  await writeFile(archive,JSON.stringify(seal(payload,key)),{mode:0o600});await writeFile(keyFile,key.toString('base64'),{mode:0o600});
  await writeFile(sql,Buffer.from(payload.files['database.sql'].base64,'base64').toString()+(changed?" UPDATE notes SET value='changed';":''),{mode:0o600});
  const action=()=>main(['verify-readback','--archive',archive,'--key',keyFile,'--sql',sql,'--out',out]);
  if(changed)await assert.rejects(action,/differs from the authenticated backup/);else await action();
 }finally{await rm(root,{recursive:true,force:true});}
});

for(const kind of ['symbolic link','hard link','permissive private mode'])test(`archive capture refuses ${kind} before encryption`,async()=>{
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-backup-guard-')));
 try{const payload=fixture(),config=join(root,'wrangler.json');await writeFile(config,Buffer.from(payload.files['wrangler.json'].base64,'base64'),{mode:0o600});
  const original=join(root,'original.sql'),sql=join(root,'database.sql');await writeFile(original,'CREATE TABLE controlled(id TEXT);',{mode:0o600});
  if(kind==='symbolic link')await symlink(original,sql);else if(kind==='hard link')await link(original,sql);else{
   await writeFile(sql,'controlled',{mode:0o644});await chmod(sql,0o644);
   assert.equal((await stat(sql)).mode&0o777,0o644,'The intentionally permissive fixture must survive a restrictive inherited umask');
  }
  const expected=kind==='symbolic link'?/symbolic links/:kind==='hard link'?/independent regular/:/permissions/;
  await assert.rejects(main(['seal','--sql',sql,'--config',config,'--secrets',join(root,'never-read-secret.json'),'--out',join(root,'must-not-exist')]),expected);
 }finally{await rm(root,{recursive:true,force:true});}
});


function listing(objects){
 const copy=value=>JSON.parse(JSON.stringify(value));
 return {prefix:'',delimiter:null,include:['httpMetadata','customMetadata'],pages:[
  {cursor:null,truncated:true,next_cursor:'opaque-next',objects:[]},
  {cursor:'opaque-next',truncated:false,next_cursor:null,objects:copy(objects)},
 ]};
}
function r2Fixture(bodies=[Buffer.from([0,255,1,128,0,33]),Buffer.alloc(0)]){
 const payload=fixture(),config=JSON.parse(Buffer.from(payload.files['wrangler.json'].base64,'base64'));
 config.r2_buckets=[{binding:'PRIVATE_MEDIA',bucket_name:'collect-platform-private'}];replaceRole(payload,'wrangler.json',config);
 const objects=bodies.map((body,i)=>({key:i===0?'private/evidence-é/../retained.bin':'empty-object',size:body.length,etag:'etag-'+i,version:'original-version-'+i,uploaded:'2026-10-15T01:00:00.000Z',httpMetadata:{contentType:'application/octet-stream',cacheControl:'private, no-store'},customMetadata:{key_id:'controlled-data-key',purpose:'retained evidence'},storageClass:'Standard'}));
 const capture={format:'collect.r2.capture.v1',bucket:'collect-platform-private',source_id:payload.source_id,captured_at:'2026-10-15T02:00:00.000Z',before:listing(objects),after:listing(objects),downloads:objects.map((o,i)=>({key:o.key,etag:o.etag,version:o.version,sha256:sha(bodies[i])}))};
 return {payload,capture,bodies,objects};
}
async function r2Harness(t,{bodies,referenced=false,decorate=()=>{}}={}){
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-r2-restore-')));t.after(()=>rm(root,{recursive:true,force:true}));
 const h=r2Fixture(bodies),key=randomBytes(32),archive=join(root,'platform.json'),keyFile=join(root,'key.base64'),inventory=join(root,'capture.json'),source=join(root,'captured-bodies');
 if(referenced){const raw=Buffer.from(Buffer.from(h.payload.files['database.sql'].base64,'base64').toString()+"CREATE TABLE retained_objects(id TEXT PRIMARY KEY,object_key TEXT); INSERT INTO retained_objects VALUES('one','private/evidence-é/../retained.bin');");h.payload.files['database.sql']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};}
 decorate(h);
 await mkdir(source,{mode:0o700});await writeFile(archive,JSON.stringify(seal(h.payload,key)),{mode:0o600});await writeFile(keyFile,key.toString('base64'),{mode:0o600});
 for(let i=0;i<h.objects.length;i++)await writeFile(join(source,sha(Buffer.from(h.objects[i].key))+'.bin'),h.bodies[i],{mode:0o600});
 await writeFile(inventory,JSON.stringify(h.capture),{mode:0o600});
 const common=['--archive',archive,'--key',keyFile],bundle=join(root,'sealed-objects');
 return {...h,root,key,archive,keyFile,inventory,source,common,bundle,seal:()=>main(['seal-r2',...common,'--inventory',inventory,'--objects',source,'--out',bundle])};
}
async function targetCapture(h,{bucket='collect-platform-isolated-restore',mutate=()=>{}}={}){
 const capture=structuredClone(h.capture);capture.bucket=bucket;capture.captured_at='2026-10-15T04:00:00.000Z';
 for(const side of ['before','after'])for(const o of capture[side].pages.flatMap(p=>p.objects)){o.etag='restored-'+o.etag;if(o.version!==null)o.version='restored-'+o.version;o.uploaded='2026-10-15T03:00:00.000Z';}
 for(const o of capture.downloads){o.etag='restored-'+o.etag;if(o.version!==null)o.version='restored-'+o.version;}mutate(capture);
 const inventory=join(h.root,'isolated-readback.json'),source=join(h.root,'isolated-readback-bodies');await mkdir(source,{mode:0o700});
 for(let i=0;i<h.objects.length;i++)await writeFile(join(source,sha(Buffer.from(h.objects[i].key))+'.bin'),h.bodies[i],{mode:0o600});
 await writeFile(inventory,JSON.stringify(capture),{mode:0o600});return {inventory,source,capture};
}
test('complete R2 pagination uses truncated/cursors even when an intermediate page is empty',()=>{const h=r2Fixture();assert.equal(validateR2Capture(h.capture).length,2);});
for(const defect of ['prefix filter','delimiter filter','missing metadata','unfinished page','cursor substitution','repeated cursor','duplicate object','changed version','missing body identity','wrong downloaded version'])test('R2 capture refuses '+defect,()=>{
 const h=r2Fixture(),c=h.capture;
 if(defect==='prefix filter')c.before.prefix='private/';
 if(defect==='delimiter filter')c.before.delimiter='/';
 if(defect==='missing metadata')c.before.include=['httpMetadata'];
 if(defect==='unfinished page')c.before.pages.pop();
 if(defect==='cursor substitution')c.before.pages[1].cursor='substituted';
 if(defect==='repeated cursor'){c.before.pages[1].truncated=true;c.before.pages[1].next_cursor='opaque-next';c.before.pages.push({cursor:'opaque-next',truncated:false,next_cursor:null,objects:[]});}
 if(defect==='duplicate object')c.before.pages[1].objects.push(c.before.pages[1].objects[0]);
 if(defect==='changed version')c.after.pages[1].objects[0].version='later';
 if(defect==='missing body identity')c.downloads.pop();
 if(defect==='wrong downloaded version')c.downloads[0].version='different';
 assert.throws(()=>validateR2Capture(c),/R2|listing|metadata|download/);
});
test('R2 real binary and zero-byte bodies independently restore with exact metadata and no path traversal',async t=>{
 const h=await r2Harness(t,{bodies:[Buffer.concat([randomBytes(2*1024*1024+17),Buffer.from('PRIVATE_OBJECT_CANARY')]),Buffer.alloc(0)],referenced:true});await h.seal();
 const inventoryBytes=await readFile(join(h.bundle,'objects-backup.json'));assert.equal(inventoryBytes.includes(Buffer.from('PRIVATE_OBJECT_CANARY')),false);assert.equal(inventoryBytes.includes(Buffer.from(h.objects[0].key)),false);
 await main(['restore-r2',...h.common,'--bundle',h.bundle,'--out',join(h.root,'independent-restore')]);
 for(let i=0;i<h.objects.length;i++)assert.deepEqual(await readFile(join(h.root,'independent-restore/objects',sha(Buffer.from(h.objects[i].key))+'.bin')),h.bodies[i]);
 const result=JSON.parse(await readFile(join(h.root,'independent-restore/verification.json')));assert.equal(result.object_count,2);assert.equal(result.actual_independent_local_body_restore,true);assert.equal(result.remote_execution_proven_by_this_offline_check,false);assert.equal(result.full_system_recovery_accepted,false);
 const index=JSON.parse(await readFile(join(h.root,'independent-restore/restore-index.json')));assert.deepEqual(index.objects.map(r=>r.metadata),[...h.objects].sort((a,b)=>Buffer.compare(Buffer.from(a.key),Buffer.from(b.key))));
 const target=await targetCapture(h);await main(['verify-r2-readback',...h.common,'--bundle',h.bundle,'--inventory',target.inventory,'--objects',target.source,'--out',join(h.root,'verified-target')]);
 const verified=JSON.parse(await readFile(join(h.root,'verified-target/verification.json')));assert.equal(verified.independent_target_body_readback,true);assert.equal(verified.all_opaque_application_ciphertexts_match,true);assert.equal(verified.provider_version_and_uploaded_fields_intentionally_reissued,true);assert.equal(verified.full_system_recovery_accepted,false);
});
for(const defect of ['body tamper','missing body','extra body','hardlinked body','symlinked body'])test('R2 capture refuses '+defect+' without a successful receipt',async t=>{
 const h=await r2Harness(t),file=join(h.source,sha(Buffer.from(h.objects[0].key))+'.bin');
 if(defect==='body tamper')await writeFile(file,Buffer.alloc(h.bodies[0].length,17),{mode:0o600});
 if(defect==='missing body')await rm(file);
 if(defect==='extra body')await writeFile(join(h.source,'unlisted.bin'),'unlisted',{mode:0o600});
 if(defect==='hardlinked body')await link(file,join(h.root,'alias'));
 if(defect==='symlinked body'){await rm(file);const other=join(h.root,'other-body');await writeFile(other,h.bodies[0],{mode:0o600});await symlink(other,file);}
 await assert.rejects(h.seal,/R2|independent|symbolic/);await assert.rejects(access(join(h.bundle,'receipt.json')));
});
test('a missing database object reference prevents an apparently empty successful bucket backup',async t=>{
 const h=await r2Harness(t,{referenced:true});h.capture.before=listing([]);h.capture.after=listing([]);h.capture.downloads=[];await writeFile(h.inventory,JSON.stringify(h.capture),{mode:0o600});
 await assert.rejects(h.seal,/database object reference is missing/);await assert.rejects(access(h.bundle));
});
for(const defect of ['inventory ciphertext','body ciphertext','extra ciphertext','substituted platform archive'])test('R2 restore refuses '+defect+' without verification',async t=>{
 const h=await r2Harness(t);await h.seal();
 if(defect==='inventory ciphertext'){const path=join(h.bundle,'objects-backup.json'),e=JSON.parse(await readFile(path));const bytes=Buffer.from(e.ciphertext,'base64');bytes[0]^=1;e.ciphertext=bytes.toString('base64');await writeFile(path,JSON.stringify(e),{mode:0o600});}
 if(defect==='body ciphertext'){const path=join(h.bundle,'objects',sha(Buffer.from(h.objects[0].key))+'.aes-gcm'),bytes=await readFile(path);bytes[0]^=1;await writeFile(path,bytes,{mode:0o600});}
 if(defect==='extra ciphertext')await writeFile(join(h.bundle,'objects','f'.repeat(64)+'.aes-gcm'),'extra',{mode:0o600});
 if(defect==='substituted platform archive')await writeFile(h.archive,JSON.stringify(seal(h.payload,h.key)),{mode:0o600});
 const out=join(h.root,'unverified-restore');await assert.rejects(main(['restore-r2',...h.common,'--bundle',h.bundle,'--out',out]),/authenticated R2|missing or unlisted/);await assert.rejects(access(join(out,'verification.json')));
});
for(const defect of ['primary bucket','missing key','extra key','changed metadata','changed body'])test('independent R2 readback refuses '+defect,async t=>{
 const h=await r2Harness(t);await h.seal();
 const target=await targetCapture(h,{bucket:defect==='primary bucket'?h.capture.bucket:undefined,mutate:c=>{
  if(defect==='missing key'){for(const side of ['before','after'])c[side].pages[1].objects.pop();c.downloads.pop();}
  if(defect==='extra key'){const object={...c.before.pages[1].objects[0],key:'unlisted-target'};for(const side of ['before','after'])c[side].pages[1].objects.push(structuredClone(object));c.downloads.push({key:object.key,etag:object.etag,version:object.version,sha256:sha(Buffer.alloc(0))});}
  if(defect==='changed metadata')for(const side of ['before','after'])c[side].pages[1].objects[0].customMetadata.purpose='changed';
 }});
 if(defect==='changed body')await writeFile(join(target.source,sha(Buffer.from(h.objects[0].key))+'.bin'),Buffer.alloc(h.bodies[0].length,99),{mode:0o600});
 const out=join(h.root,'unverified-target');await assert.rejects(main(['verify-r2-readback',...h.common,'--bundle',h.bundle,'--inventory',target.inventory,'--objects',target.source,'--out',out]),/isolated bucket|readback|metadata differ/i);await assert.rejects(access(out));
});
test('an empty complete unreferenced capture remains explicitly local and does not certify the provider bucket',async t=>{
 const h=await r2Harness(t,{bodies:[]});await h.seal();await main(['restore-r2',...h.common,'--bundle',h.bundle,'--out',join(h.root,'empty-restore')]);
 const receipt=JSON.parse(await readFile(join(h.bundle,'receipt.json')));assert.equal(receipt.object_count,0);assert.equal(receipt.remote_execution_proven_by_this_offline_check,false);assert.equal(receipt.full_system_recovery_accepted,false);
});

function appObject(table,{defect,historical=false}={}){
 const id='11111111-1111-4111-8111-111111111111',plaintext=Buffer.from('PRIVATE_APP_OBJECT_CANARY Rwanda 🇷🇼'),dataKey=randomBytes(32),keyId=historical?'controlled-old-v1':'controlled-v1';
 const plainSha=sha(plaintext),context=table==='roster_imports'?'roster-source:'+id:(table==='sms_receipts'?'sms:':'evidence:')+id+':'+plainSha;
 const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',dataKey,iv);cipher.setAAD(Buffer.from(context));const encrypted=Buffer.concat([cipher.update(plaintext),cipher.final(),cipher.getAuthTag()]);
 if(defect==='object tag')encrypted[encrypted.length-1]^=1;
 const document=Buffer.from(JSON.stringify({v:1,kid:keyId,iv:iv.toString('base64'),data:encrypted.toString('base64')}));
 return {bodies:[document],decorate:h=>{
  const config=JSON.parse(Buffer.from(h.payload.files['wrangler.json'].base64,'base64'));config.vars.DATA_KEY_ID=defect==='data key id'?'different-key-id':historical?'controlled-current-v2':keyId;replaceRole(h.payload,'wrangler.json',config);
  const keys=JSON.parse(Buffer.from(h.payload.files['worker-secrets.json'].base64,'base64'));keys.DATA_ENCRYPTION_KEY=(historical||defect==='data key'?randomBytes(32):dataKey).toString('base64');if(historical)keys.DATA_DECRYPTION_KEYS_JSON=JSON.stringify({[keyId]:dataKey.toString('base64')});replaceRole(h.payload,'worker-secrets.json',keys);
  const rowId=defect==='context id'?'22222222-2222-4222-8222-222222222222':id,length=defect==='plaintext size'?plaintext.length+1:plaintext.length,expectedSha=defect==='plaintext digest'?'0'.repeat(64):plainSha;
  const create=table==='roster_imports'?`CREATE TABLE roster_imports(id TEXT,source_object_key TEXT,object_sha256 TEXT,source_sha256 TEXT,source_size INTEGER);INSERT INTO roster_imports VALUES('${rowId}','${h.objects[0].key}','${sha(document)}','${expectedSha}',${length});`:`CREATE TABLE ${table}(id TEXT,object_key TEXT,object_sha256 TEXT,size_bytes INTEGER);INSERT INTO ${table} VALUES('${rowId}','${h.objects[0].key}','${expectedSha}',${length});`;
  const raw=Buffer.from(Buffer.from(h.payload.files['database.sql'].base64,'base64').toString()+create);h.payload.files['database.sql']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};
 }};
}
for(const table of ['payment_evidence','sms_receipts','roster_imports'])test('independent '+table+' object restore verifies recovered data key, AAD, plaintext bytes and DB hash',async t=>{
 const h=await r2Harness(t,appObject(table));await h.seal();const out=join(h.root,'app-object-restore');await main(['restore-r2',...h.common,'--bundle',h.bundle,'--out',out]);
 const receipt=JSON.parse(await readFile(join(out,'verification.json')));assert.equal(receipt.application_data_key_verified_counts[table],1);assert.equal(receipt.remote_execution_proven_by_this_offline_check,false);
 const target=await targetCapture(h),verified=join(h.root,'verified-app-target');await main(['verify-r2-readback',...h.common,'--bundle',h.bundle,'--inventory',target.inventory,'--objects',target.source,'--out',verified]);assert.equal(JSON.parse(await readFile(join(verified,'verification.json'))).application_data_key_verified_counts[table],1);
 const envelope=await readFile(join(h.bundle,'objects-backup.json'));assert.equal(envelope.includes(Buffer.from('PRIVATE_APP_OBJECT_CANARY')),false);assert.equal(JSON.stringify(receipt).includes('PRIVATE_APP_OBJECT_CANARY'),false);
});
for(const defect of ['data key','data key id','context id','plaintext size','plaintext digest','object tag'])test('R2 recovery cannot claim application readability with wrong '+defect,async t=>{
 const h=await r2Harness(t,appObject('payment_evidence',{defect}));await assert.rejects(h.seal,/retained application object could not be verified/);await assert.rejects(access(h.bundle));
});

test('malformed private inventory rejects with a fixed message and no object-key content',async t=>{
 const h=await r2Harness(t);await writeFile(h.inventory,'{"PRIVATE_INVENTORY_CANARY":', {mode:0o600});await assert.rejects(h.seal,e=>e.message==='Private recovery JSON could not be verified.'&&!e.message.includes('PRIVATE_INVENTORY_CANARY'));await assert.rejects(access(h.bundle));
});
test('malformed recovered secret JSON cannot leak a key value in validation errors',()=>{
 const p=fixture(),raw=Buffer.from('{"DATA_ENCRYPTION_KEY":"PRIVATE_SECRET_CANARY"');p.files['worker-secrets.json']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};assert.throws(()=>validatePayload(p),e=>e.message==='Private recovery JSON could not be verified.'&&!e.message.includes('PRIVATE_SECRET_CANARY'));
});
test('an output path through a symbolic parent is refused before creating a directory',async t=>{
 const h=await r2Harness(t),outside=join(h.root,'outside'),alias=join(h.root,'alias');await mkdir(outside,{mode:0o700});await symlink(outside,alias);await assert.rejects(main(['seal-r2',...h.common,'--inventory',h.inventory,'--objects',h.source,'--out',join(alias,'must-not-exist')]),/symbolic links/);await assert.rejects(access(join(outside,'must-not-exist')));
});

test('REST observations without provider version IDs remain explicit and verify actual complete body readback',async t=>{
 const h=await r2Harness(t);for(const side of ['before','after'])for(const o of h.capture[side].pages.flatMap(p=>p.objects))o.version=null;for(const o of h.capture.downloads)o.version=null;
 await writeFile(h.inventory,JSON.stringify(h.capture),{mode:0o600});await h.seal();const target=await targetCapture(h),out=join(h.root,'rest-target');await main(['verify-r2-readback',...h.common,'--bundle',h.bundle,'--inventory',target.inventory,'--objects',target.source,'--out',out]);const receipt=JSON.parse(await readFile(join(out,'verification.json')));assert.equal(receipt.source_provider_version_ids_observed,0);assert.equal(receipt.source_provider_version_ids_unavailable,2);assert.equal(receipt.bucket_version_history_restored,false);
});

for(const table of ['payment_evidence','sms_receipts','roster_imports'])test('authenticated optional historical keyring restores retained '+table+' ciphertext without changing its kid',async t=>{
 const h=await r2Harness(t,appObject(table,{historical:true}));await h.seal();const out=join(h.root,'historical-object-restore');await main(['restore-r2',...h.common,'--bundle',h.bundle,'--out',out]);assert.equal(JSON.parse(await readFile(join(out,'verification.json'))).application_data_key_verified_counts[table],1);
 const platform=unseal(JSON.parse(await readFile(h.archive)),h.key);assert.deepEqual(JSON.parse(validatePayload(platform)['worker-secrets.json']),JSON.parse(Buffer.from(h.payload.files['worker-secrets.json'].base64,'base64')));
});

function keyringFixture(raw){
 const p=fixture(),config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64')),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));
 config.vars.DATA_KEY_ID='active-v2';keys.DATA_ENCRYPTION_KEY=Buffer.alloc(32,1).toString('base64');keys.DATA_DECRYPTION_KEYS_JSON=raw===undefined?JSON.stringify({'old-v1':Buffer.alloc(32,2).toString('base64')}):raw;
 replaceRole(p,'wrangler.json',config);replaceRole(p,'worker-secrets.json',keys);return p;
}
for(const raw of ['', '{}', ' { "old-v1" : "'+Buffer.alloc(32,2).toString('base64')+'" } '])test('qualified optional keyring preserves its exact private source string length '+raw.length,()=>{
 const p=keyringFixture(raw),key=randomBytes(32);assert.deepEqual(unseal(seal(p,key),key),p);assert.equal(JSON.parse(validatePayload(p)['worker-secrets.json']).DATA_DECRYPTION_KEYS_JSON,raw);
});
test('eight distinct key identities including the identical active entry remain qualified',()=>{
 const entries=[['active-v2',Buffer.alloc(32,1).toString('base64')],...Array.from({length:7},(_,i)=>['historical-'+i,Buffer.alloc(32,i+2).toString('base64')])];assert.ok(validatePayload(keyringFixture(JSON.stringify(Object.fromEntries(entries)))));
});
const ringOld=Buffer.alloc(32,2).toString('base64'),ringActive=Buffer.alloc(32,1).toString('base64');
for(const [defect,raw] of [
 ['duplicate ID','{"old-v1":"'+ringOld+'","old-v1":"'+Buffer.alloc(32,3).toString('base64')+'"}'],
 ['escaped alias','{"old\\u002dv1":"'+ringOld+'"}'],
 ['escaped value','{"old-v1":"\\u0041'+ringOld.slice(1)+'"}'],
 ['historical alias to active key',JSON.stringify({'old-v1':ringActive})],
 ['historical aliases share material',JSON.stringify({'old-v1':ringOld,'old-v0':ringOld})],
 ['conflicting active entry',JSON.stringify({'active-v2':ringOld})],
 ['nine entries',JSON.stringify(Object.fromEntries(Array.from({length:9},(_,i)=>['historical-'+i,Buffer.alloc(32,i+2).toString('base64')])) )],
 ['oversize setting',' '.repeat(4096)+'{}'],
 ['nested key',JSON.stringify({'old-v1':{key:ringOld}})],
 ['non-string key',JSON.stringify({'old-v1':23})],
 ['array','[]'],['null','null'],['whitespace only',' '],
 ['non-JSON whitespace','\u00a0{}'],['trailing comma','{"old-v1":"'+ringOld+'",}'],
 ['invalid key ID',JSON.stringify({'old key':ringOld})],['oversize key ID',JSON.stringify({['k'.repeat(129)]:ringOld})],
 ['unpadded key',JSON.stringify({'old-v1':ringOld.slice(0,-1)})],['noncanonical key',JSON.stringify({'old-v1':ringOld.slice(0,-2)+'J='})],
 ['wrapped key',JSON.stringify({'old-v1':'Value: '+ringOld})],
])test('historical recovery keyring refuses '+defect+' before sealing',()=>{assert.throws(()=>validatePayload(keyringFixture(raw)),e=>e.message==='Historical data-key recovery configuration could not be verified.'&&!e.message.includes(ringOld)&&!e.message.includes(ringActive));});
test('optional keyring requires a valid active key and ID even when empty',()=>{
 for(const [field,value] of [['DATA_KEY_ID',23],['DATA_KEY_ID','bad key'],['DATA_ENCRYPTION_KEY','not canonical base64']]){
  const p=keyringFixture('{}'),role=field==='DATA_KEY_ID'?'wrangler.json':'worker-secrets.json',body=JSON.parse(Buffer.from(p.files[role].base64,'base64'));
  if(field==='DATA_KEY_ID')body.vars.DATA_KEY_ID=value;else body[field]=value;replaceRole(p,role,body);assert.throws(()=>validatePayload(p),/key recovery|Historical data-key/);
 }
});
