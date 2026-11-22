import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {closeSync,copyFileSync,createWriteStream,mkdtempSync,openSync,readFileSync,rmSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {Readable,Writable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {ArchiveError,authenticateAndInspectArchive,createBackupEncryptor,PROVIDER_ROOT_SHA256} from './archive.mjs';
const code=x=>e=>e instanceof ArchiveError&&e.code===x;
test('authenticated archive binds metadata and pins parser blocks',{timeout:30000},async t=>{
 const root=mkdtempSync('/private/tmp/collect-real-archive-test-'),key=randomBytes(32),file=join(root,'synthetic.enc');
 const metadata={format:'collect.pg-backup.v2',scope:'synthetic',operation_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',plan_sha256:'c'.repeat(64),project_ref:'rrlduytparvsjfmegalh',host:'db.rrlduytparvsjfmegalh.supabase.co',database:'postgres',role:'postgres',provider_ca_sha256:PROVIDER_ROOT_SHA256,snapshot_sha256:'a'.repeat(64),inventory_sha256:'b'.repeat(64),created_at:'2026-01-01T00:00:00.000Z'};
 try{
  await t.test('wrong identity binding is refused',async()=>{assert.throws(()=>createBackupEncryptor({key,metadata:{...metadata,host:'other'}}),code('invalid_metadata'));});
  await t.test('stream stops when its capacity guard rejects further bytes',async()=>{
   let calls=0;const guard=()=>{if(++calls===2)throw Error('synthetic low disk');};
   async function* chunks(){yield Buffer.alloc(1024);yield Buffer.alloc(1024);yield Buffer.alloc(1024);}
   await assert.rejects(pipeline(Readable.from(chunks()),createBackupEncryptor({key,metadata,onProgress:guard}),new Writable({write(_b,_e,cb){cb();}})),code('encryption_failed'));
   assert.equal(calls,2);
  });
  const total=16*1024*1024+11,h=createHash('sha256');async function* content(){let n=0;while(n<total){const b=Buffer.alloc(Math.min(512*1024,total-n),(n/4096)%251);n+=b.length;h.update(b);yield b;}}
  await pipeline(Readable.from(content()),createBackupEncryptor({key,metadata}),createWriteStream(file,{flags:'wx',mode:0o600}));const digest=h.digest('hex');
  await t.test('16 MiB content authenticates and streams without plaintext files',async()=>{const fd=openSync(file,'r');try{let n=0;const hash=createHash('sha256'),writable=new Writable({write(b,_e,cb){hash.update(b);n+=b.length;cb();}});
   const r=await authenticateAndInspectArchive({fd,key,expectedMetadata:metadata,writable});assert.equal(r.dumpBytes,total);assert.equal(n,total);assert.equal(hash.digest('hex'),digest);assert.equal(r.metadata.scope,'synthetic');}finally{closeSync(fd);}});
  await t.test('wrong key and mismatched metadata fail before output',async()=>{const fd=openSync(file,'r');let delivered=0;const out=new Writable({write(b,_e,cb){delivered+=b.length;cb();}});try{
   await assert.rejects(authenticateAndInspectArchive({fd,key:randomBytes(32),expectedMetadata:metadata,writable:out}),code('archive_authentication_failed'));assert.equal(delivered,0);
   await assert.rejects(authenticateAndInspectArchive({fd,key,expectedMetadata:{...metadata,snapshot_sha256:'c'.repeat(64)}}),code('archive_binding_mismatch'));
   await assert.rejects(authenticateAndInspectArchive({fd,key,expectedMetadata:{...metadata,plan_sha256:'e'.repeat(64)}}),code('archive_binding_mismatch'));}finally{closeSync(fd);}});
  await t.test('changed second block is not released to the parser',async()=>{const changed=join(root,'changed');copyFileSync(file,changed);const fd=openSync(changed,'r+');let delivered=0;const prefix=Buffer.byteLength('COLLECTPGBKUP1')+12+4+Buffer.byteLength(JSON.stringify(metadata));
   try{await assert.rejects(authenticateAndInspectArchive({fd,key,expectedMetadata:metadata,writable:new Writable({write(b,_e,cb){delivered+=b.length;cb();}}),afterAuthenticated:()=>{const b=Buffer.from([readFileSync(changed)[prefix+1024*1024+1]^1]);writeSync(fd,b,0,1,prefix+1024*1024+1);}}),code('archive_changed_before_parser'));assert.equal(delivered,1024*1024);}finally{closeSync(fd);}});
 }finally{key.fill(0);rmSync(root,{recursive:true,force:true});}
});
