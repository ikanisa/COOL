// A registered ancillary function is external to the three-function runtime
// snapshot. Its exact provider metadata is accepted only against a reviewed,
// digest-addressed private proof. Registration does not enable the function.
import {constants,closeSync,fstatSync,openSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT,PROJECT,sha} from './access.mjs';

export const CORE_FUNCTIONS=Object.freeze(['collect-api','admin-api','collect-jobs']);
const ANCILLARY=new Set(['collect-sms','send-sms-hook']);
const HASH=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const fields=['slug','id','status','version','verify_jwt','ezbr_sha256'];
const exactKeys=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&
 Object.keys(value).sort().join('|')===[...keys].sort().join('|');
const metadata=row=>Object.fromEntries(fields.map(k=>[k,row[k]]));
const valid=row=>row&&typeof row.slug==='string'&&UUID.test(row.id??'')&&row.status==='ACTIVE'&&
 Number.isSafeInteger(row.version)&&row.version>=1&&typeof row.verify_jwt==='boolean'&&HASH.test(row.ezbr_sha256??'');
function compactJson(text){
 let out='',quoted=false,escaped=false;
 for(const char of text){
  if(quoted){out+=char;if(escaped)escaped=false;else if(char==='\\')escaped=true;else if(char==='"')quoted=false;}
  else if(char==='"'){quoted=true;out+=char;}else if(!/\s/.test(char))out+=char;
 }
 return out;
}

export function decodeAncillaryRegistration(bytes,digest){
 if(!Buffer.isBuffer(bytes)||bytes.length<2||bytes.length>16384||!HASH.test(digest??'')||sha(bytes)!==digest)
  throw Error('ancillary_proof_invalid');
 let value;try{const raw=bytes.toString('utf8');value=JSON.parse(raw);
  // Duplicate keys and alternative ambiguous encodings are not reviewable.
  if(compactJson(raw)!==JSON.stringify(value))throw Error();
 }catch{throw Error('ancillary_proof_invalid');}
 if(!exactKeys(value,['format','project','reviewedEvidenceSha256','functions'])||
  value.format!=='collect.cloud-ancillary-inventory.v1'||value.project!==PROJECT||
  !HASH.test(value.reviewedEvidenceSha256??'')||!Array.isArray(value.functions)||value.functions.length>2)
  throw Error('ancillary_proof_invalid');
 const seen=new Set();
 const entries=value.functions.map(item=>{
  if(!exactKeys(item,[...fields,'sourceSha256'])||!valid(item)||!ANCILLARY.has(item.slug)||
   seen.has(item.slug)||!HASH.test(item.sourceSha256??''))throw Error('ancillary_proof_invalid');
  seen.add(item.slug);return Object.freeze({...metadata(item),sourceSha256:item.sourceSha256});
 }).sort((a,b)=>a.slug.localeCompare(b.slug));
 return Object.freeze({digest,entries:Object.freeze(entries),reviewedEvidenceSha256:value.reviewedEvidenceSha256});
}

export function readAncillaryRegistration({root=ROOT,digest=process.env.COLLECT_ANCILLARY_INVENTORY_SHA256}={}){
 if(digest===undefined||digest==='')return null;
 if(!HASH.test(digest))throw Error('ancillary_proof_invalid');
 const path=join(root,'ancillary-inventory-'+digest+'.json');let fd;
 try{
  fd=openSync(path,constants.O_RDONLY|constants.O_NOFOLLOW);const s=fstatSync(fd);
  if(!s.isFile()||s.nlink!==1||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size<2||s.size>16384)
   throw Error('ancillary_proof_invalid');
  return decodeAncillaryRegistration(readFileSync(fd),digest);
 }catch{throw Error('ancillary_proof_invalid');}finally{if(fd!==undefined)closeSync(fd);}
}

// All provider rows are classified. Unknown, duplicate, missing, unreviewed or
// changed ancillary functions cannot be hidden by extracting the core subset.
export function scopedInventory(rows,registration=null){
 if(!Array.isArray(rows))throw Error('ancillary_inventory_changed');
 const expected=registration?.entries??[];
 if(registration!==null&&(!exactKeys(registration,['digest','entries','reviewedEvidenceSha256'])||
  !HASH.test(registration.digest??'')||!HASH.test(registration.reviewedEvidenceSha256??'')||!Array.isArray(expected)||expected.length>2||
  new Set(expected.map(x=>x?.slug)).size!==expected.length||expected.some(x=>!exactKeys(x,[...fields,'sourceSha256'])||
   !valid(x)||!ANCILLARY.has(x.slug)||!HASH.test(x.sourceSha256??''))))throw Error('ancillary_proof_invalid');
 if(rows.length!==CORE_FUNCTIONS.length+expected.length||new Set(rows.map(x=>x?.slug)).size!==rows.length)
  throw Error('ancillary_inventory_changed');
 const core=CORE_FUNCTIONS.map(slug=>{
  const found=rows.filter(x=>x?.slug===slug);if(found.length!==1||!valid(found[0])||found[0].verify_jwt!==false)
   throw Error('ancillary_inventory_changed');
  return metadata(found[0]);
 });
 const ancillary=expected.map(proof=>{
  const found=rows.filter(x=>x?.slug===proof.slug);
  if(found.length!==1||!valid(found[0])||fields.some(k=>found[0][k]!==proof[k]))throw Error('ancillary_inventory_changed');
  return metadata(found[0]);
 });
 if(rows.some(row=>!CORE_FUNCTIONS.includes(row?.slug)&&!expected.some(entry=>entry.slug===row?.slug)))
  throw Error('ancillary_inventory_changed');
 return {core,ancillary};
}

// Older evidence names exactly the core. A reviewed registration separately
// accounts for present extras without retroactively rewriting that evidence.
export function evidenceCore(rows,registration=null){
 if(Array.isArray(rows)&&rows.length===CORE_FUNCTIONS.length)return scopedInventory(rows).core;
 return scopedInventory(rows,registration).core;
}

export function registrationSnapshot(registration){
 return registration===null?null:{digest:registration.digest,entries:registration.entries.map(x=>({...x})),
  reviewedEvidenceSha256:registration.reviewedEvidenceSha256};
}

export function requireSameRegistration(expected,actual){
 if(JSON.stringify(registrationSnapshot(expected))!==JSON.stringify(registrationSnapshot(actual)))
  throw Error('ancillary_proof_changed');
}

// A fresh review may accept a provider version increase after a known global
// secret update. Every authority, executable and source pin must be unchanged.
export function requireVersionOnlyRequalification(previous,current){
 if(!previous||!current||previous.digest===current.digest||!Array.isArray(previous.entries)||!Array.isArray(current.entries)||
  previous.entries.length===0||previous.entries.length!==current.entries.length||
  new Set(previous.entries.map(x=>x?.slug)).size!==previous.entries.length||
  new Set(current.entries.map(x=>x?.slug)).size!==current.entries.length)
  throw Error('ancillary_requalification_invalid');
 let advanced=false;
 for(const old of previous.entries){
  const next=current.entries.filter(x=>x?.slug===old.slug);
  if(next.length!==1||!valid(old)||!valid(next[0])||!ANCILLARY.has(old.slug)||!HASH.test(old.sourceSha256??'')||
   ['slug','id','status','verify_jwt','ezbr_sha256','sourceSha256'].some(k=>old[k]!==next[0][k])||next[0].version<old.version)
   throw Error('ancillary_requalification_invalid');
  advanced||=next[0].version>old.version;
 }
 if(!advanced)throw Error('ancillary_requalification_invalid');
}
