import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {closeSync,copyFileSync,createWriteStream,mkdtempSync,openSync,readFileSync,rmSync,statSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {Readable,Writable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {createSyntheticEncryptor,HEADER_LENGTH} from '../managed-cloud-backup-preparation/stream-archive.mjs';
import {inspectSyntheticWithPinnedBlocks,VerifiedReadError} from './verified-block-reader.mjs';
const code=x=>e=>e instanceof VerifiedReadError&&e.code===x;
test('synthetic authenticated block map excludes changed bytes from parser',{timeout:30000},async t=>{
 const root=mkdtempSync('/private/tmp/collect-block-fixture-'),file=join(root,'archive'),key=randomBytes(32),bytes=3*1024*1024+15,hash=createHash('sha256');
 try{
  async function* source(){let n=0;while(n<bytes){const size=Math.min(512*1024,bytes-n),b=Buffer.alloc(size,(n/4096)%251);hash.update(b);n+=size;yield b;}}
  await pipeline(Readable.from(source()),createSyntheticEncryptor({mode:'synthetic',key}),createWriteStream(file,{flags:'wx',mode:0o600}));const expected=hash.digest('hex'),base={mode:'synthetic',key,signal:null,afterAuthenticated:null};
  await t.test('managed execution is closed before key or consumer access',async()=>{let read=0;const o={mode:'managed'};Object.defineProperty(o,'key',{get(){read++;throw Error();}});await assert.rejects(inspectSyntheticWithPinnedBlocks(o),code('managed_execution_closed'));assert.equal(read,0);});
  await t.test('authenticates all data then streams verified bytes in bounded blocks',async()=>{const fd=openSync(file,'r'),h=createHash('sha256');let count=0;const writable=new Writable({write(b,_e,cb){h.update(b);count+=b.length;cb();}});
   try{const r=await inspectSyntheticWithPinnedBlocks({...base,fd,writable});assert.equal(r.blocks,4);assert.equal(r.archiveBytes,bytes);assert.equal(count,bytes);assert.equal(h.digest('hex'),expected);}finally{closeSync(fd);}});
  await t.test('changed second block is refused before any changed plaintext reaches consumer',async()=>{const altered=join(root,'changed');copyFileSync(file,altered);const fd=openSync(altered,'r+');let delivered=0;
   try{await assert.rejects(inspectSyntheticWithPinnedBlocks({...base,fd,writable:new Writable({write(b,_e,cb){delivered+=b.length;cb();}}),afterAuthenticated:()=>{const b=Buffer.from([readFileSync(altered)[HEADER_LENGTH+1024*1024+5]^1]);writeSync(fd,b,0,1,HEADER_LENGTH+1024*1024+5);}}),code('archive_changed_before_parser'));
    assert.equal(delivered,1024*1024);
   }finally{closeSync(fd);}});
  await t.test('wrong key and header/tag mutation cannot reach consumer',async()=>{const wrong=openSync(file,'r');let n=0;try{await assert.rejects(inspectSyntheticWithPinnedBlocks({...base,fd:wrong,key:randomBytes(32),writable:new Writable({write(b,_e,cb){n+=b.length;cb();}})}),code('archive_authentication_failed'));assert.equal(n,0);}finally{closeSync(wrong);}
   const changed=join(root,'tag');copyFileSync(file,changed);const fd=openSync(changed,'r+'),size=statSync(changed).size;
   try{await assert.rejects(inspectSyntheticWithPinnedBlocks({...base,fd,writable:new Writable({write(b,_e,cb){n+=b.length;cb();}}),afterAuthenticated:()=>{const b=Buffer.from([readFileSync(changed)[size-1]^1]);writeSync(fd,b,0,1,size-1);}}),code('archive_changed_before_parser'));assert.equal(n,0);}finally{closeSync(fd);}});
  await t.test('early parser close still checks the remainder',async()=>{const fd=openSync(file,'r'),writable=new Writable({write(_b,_e,cb){const e=Error('closed');e.code='EPIPE';cb(e);}});
   try{const r=await inspectSyntheticWithPinnedBlocks({...base,fd,writable});assert.equal(r.consumerClosedEarly,true);assert.equal(r.deliveredBytes,0);}finally{closeSync(fd);}});
 }finally{key.fill(0);rmSync(root,{recursive:true,force:true});}
});
