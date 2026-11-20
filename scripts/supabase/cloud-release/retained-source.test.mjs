import test from 'node:test';
import assert from 'node:assert/strict';
import {cp,mkdtemp,mkdir,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname,join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const root=resolve(import.meta.dirname,'../../..');
const inputs=[
 'scripts/supabase/cloud-release/migrations.mjs',
 'scripts/supabase/cloud-release/retained-source.mjs',
 'scripts/supabase/cloud-release/managed-lifecycle-candidate.mjs',
 'scripts/supabase/cloud-release/retention-candidate.mjs',
 'scripts/supabase/retention-convergence',
 'supabase/functions/_shared/deployment-profile.js',
 'supabase/migrations',
 'supabase/managed-migration-history',
];

test('managed chain resolves from an isolated copy and rejects retained-input drift',async()=>{
 const fixture=await mkdtemp(join(tmpdir(),'collect-retained-source-'));
 try{
  for(const input of inputs){
   const target=join(fixture,input);await mkdir(dirname(target),{recursive:true});
   await cp(join(root,input),target,{recursive:true,errorOnExist:true});
  }
  const {chain}=await import(pathToFileURL(join(fixture,'scripts/supabase/cloud-release/migrations.mjs')));
  const {retainedLock}=await import(pathToFileURL(join(fixture,'scripts/supabase/cloud-release/retained-source.mjs')));
  const result=await chain();
  assert.equal(result.length,71);
  assert.equal(result.filter(row=>row.file==='20261116163800_collect_storage_lifecycle_retention.sql').length,1);
  const lock=join(fixture,'supabase/managed-migration-history/retained-migrations.lock.json');
  const original=await readFile(lock);await writeFile(lock,Buffer.concat([original,Buffer.from(' ')]));
  await assert.rejects(retainedLock(),/retained_lock_changed/);
  await writeFile(lock,original);
  const migration=join(fixture,'supabase/managed-migration-history/retained/20261116163800_collect_storage_lifecycle_retention.sql');
  await writeFile(migration,Buffer.concat([await readFile(migration),Buffer.from(' ')]));
  await assert.rejects(chain(),/migration_source_changed_20261116163800_collect_storage_lifecycle_retention.sql/);
 }finally{await rm(fixture,{recursive:true,force:true});}
});
