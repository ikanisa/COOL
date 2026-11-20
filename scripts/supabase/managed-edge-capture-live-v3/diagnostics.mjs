// Private, allowlisted progress only: never persists response or credential bytes.
import {constants as FS} from 'node:fs';
import {open} from 'node:fs/promises';
import {resolve} from 'node:path';
import {SLUGS} from './seal.mjs';
const PHASES=new Set(['KEY_CREATE','TOKEN_READ','PROJECT_GET','PROJECT_IDENTITY','METADATA_BEFORE_GET','METADATA_BEFORE_VALIDATE','BODY_GET','BODY_VALIDATE','METADATA_AFTER_GET','METADATA_AFTER_COMPARE','ARCHIVE_SEAL','ARCHIVE_WRITE','ARCHIVE_READBACK','RECEIPT_WRITE']);
const REASONS=new Set(['CAPTURE_INTERRUPTED','PROVIDER_HTTP_STATUS','PROVIDER_TIMEOUT','PROVIDER_TRANSPORT_ERROR','PROVIDER_RESPONSE_ERROR','PROVIDER_UNSUPPORTED_ENCODING','PROVIDER_DECLARED_LENGTH_INVALID','PROVIDER_SIZE_BOUND','PROVIDER_BODY_TRUNCATED','PROVIDER_RESPONSE_INVALID','PROJECT_IDENTITY_INVALID','METADATA_INVALID','BODY_INVALID','UNSUPPORTED_PROVIDER_BODY','DEPLOYMENT_CHANGED','ARCHIVE_CHANGED','ARCHIVE_INVALID','ARCHIVE_AUTHENTICATION_FAILED','TOKEN_INVALID','SOURCE_PINS_REFUSED']);
const SHAPES=new Set(['MIME_TYPE_UNSUPPORTED','MIME_BOUNDARY_INVALID','MIME_OPENING_INVALID','MIME_HEADER_INVALID','MIME_DISPOSITION_INVALID','MIME_BODY_INCOMPLETE','MIME_METADATA_INVALID','MIME_NO_FILES','MIME_EMPTY_FILE','MIME_OTHER']);
const safeCode=e=>{try{return typeof e?.code==='string'&&REASONS.has(e.code)?e.code:'UNCLASSIFIED';}catch{return 'UNCLASSIFIED';}};
const shapeCode=e=>{try{return typeof e?.shape==='string'&&SHAPES.has(e.shape)?e.shape:null;}catch{return null;}};
function media(v){if(typeof v!=='string'||v.length>512)return 'missing_or_invalid';const m=v.split(';',1)[0].trim().toLowerCase();return m==='multipart/form-data'?'multipart_form_data':m==='application/json'?'json':m==='application/octet-stream'?'octet_stream':m.startsWith('text/')?'text':'other';}
function encoding(v){if(v===undefined)return 'missing';if(typeof v!=='string'||v.length>64)return 'other';const x=v.toLowerCase();return ['identity','gzip','br','deflate'].includes(x)?x:'other';}
function lengthCategory(v,cap){if(v===undefined)return 'missing';if(typeof v!=='string'||v.length>20||!/^\d+$/.test(v))return 'invalid';return Number(v)>cap?'above_limit':'within_limit';}
function bodyShape(b){
 if(!Buffer.isBuffer(b)||b.length===0)return 'empty';let i=0;while(i<Math.min(b.length,64)&&[9,10,13,32].includes(b[i]))i++;
 if(b.subarray(i,i+2).equals(Buffer.from('--')))return 'multipart_like';if(b[i]===123||b[i]===91)return 'json_like';if(b[i]===60)return 'html_like';
 if(b.subarray(i,i+5).equals(Buffer.from('ESZIP')))return 'eszip_like';if(b.subarray(i,i+4).equals(Buffer.from('EZBR')))return 'ezbr_like';
 return b.subarray(i,Math.min(b.length,i+32)).every(x=>x>=32&&x<=126)?'other_text':'other_binary';
}
async function writeNew(path,bytes){const fd=await open(path,FS.O_WRONLY|FS.O_CREAT|FS.O_EXCL|FS.O_NOFOLLOW,0o600);try{await fd.writeFile(bytes);await fd.sync();}finally{await fd.close();}}
async function syncDir(path){const fd=await open(path,FS.O_RDONLY);try{await fd.sync();}finally{await fd.close();}}
export class PhaseJournal{
 constructor({archiveDir,scope,operationId,planSha256}){if(typeof archiveDir!=='string'||!archiveDir.startsWith('/')||!['managed','synthetic'].includes(scope)||
  !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(operationId??'')||!/^[0-9a-f]{64}$/.test(planSha256??''))throw Error('invalid diagnostic state');
  this.dir=archiveDir;this.scope=scope;this.operation=operationId;this.pin=planSha256;this.sequence=0;this.current=null;}
 async start(phase,slot=null){if(!PHASES.has(phase)||slot!==null&&!SLUGS.includes(slot))throw Error('invalid phase');
  this.current={phase,slot,http_status:null,content_type:'not_observed',content_encoding:'not_observed',content_length:'not_observed',body_shape:'not_observed'};await this.write('STARTED',null,null);}
 response(status,type,enc,length,cap){if(!this.current)return;this.current.http_status=Number.isInteger(status)&&status>=100&&status<=599?status:null;
  this.current.content_type=media(type);this.current.content_encoding=encoding(enc);this.current.content_length=lengthCategory(length,cap);}
 body(b){if(this.current)this.current.body_shape=bodyShape(b);}
 async complete(){await this.write('COMPLETED',null,null);}
 async failed(error){await this.write('FAILED',safeCode(error),shapeCode(error));}
 async write(event,reason,shape){if(!this.current||!['STARTED','COMPLETED','FAILED'].includes(event)||++this.sequence>128)throw Error('invalid diagnostic state');
  const record={format:'collect.edge-capture.progress.v1',scope:this.scope,operation_id:this.operation,plan_sha256:this.pin,sequence:this.sequence,event,
   ...this.current,reason,shape_reason:shape};
  const bytes=Buffer.from(JSON.stringify(record)+'\n');if(bytes.length>2048)throw Error('diagnostic bound');
  const path=resolve(this.dir,'EDGE-CAPTURE-PROGRESS-'+String(this.sequence).padStart(3,'0')+'.json');await writeNew(path,bytes);await syncDir(this.dir);
 }
}
