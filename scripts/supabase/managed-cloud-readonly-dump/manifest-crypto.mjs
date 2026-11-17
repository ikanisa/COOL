// Small encrypted inventory sidecar. Uses a domain-separated HKDF subkey.
import {createCipheriv,createDecipheriv,hkdfSync,randomBytes} from 'node:crypto';
export class ManifestError extends Error{constructor(code){super(code);this.name='ManifestError';this.code=code;}}
const fail=c=>{throw new ManifestError(c);},MAGIC=Buffer.from('COLLECTPGMETA1'),UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
function derive(key){if(!Buffer.isBuffer(key)||key.length!==32)fail('invalid_input');return Buffer.from(hkdfSync('sha256',key,Buffer.alloc(0),Buffer.from('collect-pg-inventory-sidecar-v1'),32));}
export function sealInventory({key,operationId,inventory}={}){
 if(!UUID.test(operationId??''))fail('invalid_input');const data=Buffer.from(JSON.stringify({format:'collect.pg-inventory.v1',operation_id:operationId,inventory}));let k;
 try{if(data.length>65536)fail('invalid_input');k=derive(key);const iv=randomBytes(12),header=Buffer.concat([MAGIC,iv,Buffer.from(operationId)]);const c=createCipheriv('aes-256-gcm',k,iv);c.setAAD(header);return Buffer.concat([header,c.update(data),c.final(),c.getAuthTag()]);}finally{k?.fill(0);data.fill(0);}
}
export function openInventory({key,operationId,bytes}={}){
 if(!UUID.test(operationId??'')||!Buffer.isBuffer(bytes)||bytes.length<MAGIC.length+12+36+16||bytes.length>131072)fail('invalid_input');
 const headLen=MAGIC.length+12+36,header=bytes.subarray(0,headLen);if(!header.subarray(0,MAGIC.length).equals(MAGIC)||header.subarray(MAGIC.length+12).toString()!==operationId)fail('invalid_input');
 const k=derive(key);let body,last,plain;try{const d=createDecipheriv('aes-256-gcm',k,header.subarray(MAGIC.length,MAGIC.length+12));d.setAAD(header);d.setAuthTag(bytes.subarray(bytes.length-16));body=d.update(bytes.subarray(headLen,bytes.length-16));last=d.final();plain=Buffer.concat([body,last]);const o=JSON.parse(plain.toString());if(o.format!=='collect.pg-inventory.v1'||o.operation_id!==operationId)fail('invalid_input');return o.inventory;}
 catch(e){if(e instanceof ManifestError)throw e;fail('authentication_failed');}finally{k.fill(0);body?.fill(0);last?.fill(0);plain?.fill(0);}
}
