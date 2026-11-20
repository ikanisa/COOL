// Exact, non-active history retained for managed migration qualification.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';

export const HISTORY=resolve(import.meta.dirname,'../../../supabase/managed-migration-history');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const RETAINED_LOCK_SHA='bbd73745ca1151fe847234739bc3127cd1c7f7d1f57b056d54f70ba699510e90';
const RETAINED_MIGRATION='20261116163800_collect_storage_lifecycle_retention.sql';
export async function retainedLock(){
 const bytes=await readFile(HISTORY+'/retained-migrations.lock.json');
 if(sha(bytes)!==RETAINED_LOCK_SHA)throw Error('retained_lock_changed');
 return JSON.parse(bytes).migrations;
}
export async function migrationBytes(root,item){
 let bytes;
 try{bytes=await readFile(root+'/supabase/migrations/'+item.name);}
 catch(error){
  if(error.code!=='ENOENT'||item.name!==RETAINED_MIGRATION)throw error;
  bytes=await readFile(HISTORY+'/retained/'+item.name);
 }
 if(sha(bytes)!==item.sha256)throw Error('migration_source_changed_'+item.name);
 return bytes;
}
export async function historyFixture(name,expectedSha){
 if(!['lifecycle-source-schema.sql','storage-vendor-history.json'].includes(name))throw Error('history_fixture_refused');
 const bytes=await readFile(HISTORY+'/fixtures/'+name);
 if(sha(bytes)!==expectedSha)throw Error('history_fixture_changed');
 return bytes.toString('utf8');
}
