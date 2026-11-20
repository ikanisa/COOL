// A distinct, authenticated format for migration key material and evidence.
// It is deliberately not labelled as a PostgreSQL database archive.
import {createCipheriv,createDecipheriv,createHash,hkdfSync,randomBytes} from 'node:crypto';
const MAGIC=Buffer.from('COLLECTRC1'),FORMAT='collect.migration-recovery-capsule.v1';
const TYPE='migration-lineage-key-and-cutover-evidence',MAX=2_000_000;
const fail=()=>{throw Error('recovery_capsule_invalid');};
const sha=b=>createHash('sha256').update(b).digest('hex');
function b64(s,n){if(typeof s!=='string')fail();const b=Buffer.from(s,'base64');if(b.length!==n||b.toString('base64')!==s)fail();return b;}
function check(h){
 if(!h||Object.keys(h).join(',')!=='format,payloadType,project,operationId,keyId,plaintextSize,plaintextSha256,salt,nonce'||
  h.format!==FORMAT||h.payloadType!==TYPE||!/^[a-z]{20}$/.test(h.project??'')||
  !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(h.operationId??'')||
  !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(h.keyId??'')||!Number.isSafeInteger(h.plaintextSize)||
  h.plaintextSize<1||h.plaintextSize>MAX||!/^[a-f0-9]{64}$/.test(h.plaintextSha256??''))fail();
 b64(h.salt,32);b64(h.nonce,12);
}
function subkey(key,salt){if(!Buffer.isBuffer(key)||key.length!==32)fail();return Buffer.from(hkdfSync('sha256',key,salt,Buffer.from(FORMAT),32));}
export function sealRecoveryCapsule(plain,key,{project,operationId,keyId}){
 if(!Buffer.isBuffer(plain)||plain.length<1||plain.length>MAX)fail();
 const h={format:FORMAT,payloadType:TYPE,project,operationId,keyId,plaintextSize:plain.length,plaintextSha256:sha(plain),
  salt:randomBytes(32).toString('base64'),nonce:randomBytes(12).toString('base64')};check(h);
 const hb=Buffer.from(JSON.stringify(h)),n=Buffer.alloc(4);n.writeUInt32BE(hb.length);const k=subkey(key,b64(h.salt,32));
 try{const c=createCipheriv('aes-256-gcm',k,b64(h.nonce,12));c.setAAD(hb);return Buffer.concat([MAGIC,n,hb,c.update(plain),c.final(),c.getAuthTag()]);}finally{k.fill(0);}
}
export function openRecoveryCapsule(archive,key){
 if(!Buffer.isBuffer(archive)||archive.length>MAX+4096||archive.length<MAGIC.length+4+16||!archive.subarray(0,MAGIC.length).equals(MAGIC))fail();
 const n=archive.readUInt32BE(MAGIC.length),start=MAGIC.length+4;if(n<2||n>2048||archive.length<start+n+16)fail();
 const hb=archive.subarray(start,start+n);let h;try{h=JSON.parse(hb.toString('utf8'));}catch{fail();}check(h);
 if(JSON.stringify(h)!==hb.toString('utf8'))fail();const encrypted=archive.subarray(start+n,-16);
 if(encrypted.length!==h.plaintextSize)fail();const k=subkey(key,b64(h.salt,32));let plain;
 try{const d=createDecipheriv('aes-256-gcm',k,b64(h.nonce,12));d.setAAD(hb);d.setAuthTag(archive.subarray(-16));
  plain=Buffer.concat([d.update(encrypted),d.final()]);if(sha(plain)!==h.plaintextSha256)fail();return {header:h,plaintext:plain};}
 catch{plain?.fill(0);fail();}finally{k.fill(0);}
}
