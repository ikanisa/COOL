import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {ManifestError,openInventory,sealInventory} from './manifest-crypto.mjs';
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',code=x=>e=>e instanceof ManifestError&&e.code===x;
test('encrypted inventory binds operation and rejects tampering',()=>{const key=randomBytes(32),value={database:'fixture',inventory:[{schema:'auth',kind:'r',count:1}]};
 try{const bytes=sealInventory({key,operationId:id,inventory:value});assert(!bytes.includes(Buffer.from('fixture')));assert.deepEqual(openInventory({key,operationId:id,bytes}),value);
  const changed=Buffer.from(bytes);changed[changed.length-1]^=1;assert.throws(()=>openInventory({key,operationId:id,bytes:changed}),code('authentication_failed'));
  assert.throws(()=>openInventory({key:randomBytes(32),operationId:id,bytes}),code('authentication_failed'));assert.throws(()=>openInventory({key,operationId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',bytes}),code('invalid_input'));
 }finally{key.fill(0);}
});
