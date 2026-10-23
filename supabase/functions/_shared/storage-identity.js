import {decrypt} from './domain/encryption.js';
import {ApiError,digest} from './domain/core.js';
// Entity identity is deterministic for one authenticated semantic command.
// Encryption keeps its independently random, durably reserved nonce.
export async function storageEntity(operation,owner,request){const h=await digest('collect.storage.entity.v1\n'+operation+'\n'+owner+'\n'+request);return `${h.slice(0,8)}-${h.slice(8,12)}-5${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`;}

export async function verifyRetainedObject(env,row,kind='sms'){
 const object=await env.PRIVATE_MEDIA.get(row.object_key);if(!object)throw new ApiError(503,'receipt_unavailable','Retained receipt storage is unavailable.');
 const bytes=await decrypt(env,await object.text(),`${kind}:${row.id}:${row.object_sha256}`);if(bytes.length!==row.size_bytes||await digest(bytes)!==row.object_sha256)throw new ApiError(503,'receipt_integrity_failed','Retained receipt verification failed.');return bytes;
}
