import test from 'node:test';
import assert from 'node:assert/strict';
import {cp,mkdtemp,realpath,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';

// Execute an actual entrypoint from a physical path containing URI-reserved
// characters. The source verifier and its production inputs are not mocked.
test('CLI in a path with spaces runs and refuses missing arguments; import stays silent',async()=>{
 const base=await realpath(await mkdtemp(join(tmpdir(),'collect history # ')));
 try{
  const names=['admit-self-hosted-history.mjs','self-hosted-member-history.mjs',
   'self-hosted-current-schema.mjs','curated-platform-fixture.mjs','reviewed-self-hosted-migrations.mjs'];
  for(const name of names)await cp(fileURLToPath(new URL(name,import.meta.url)),join(base,name));
  const entry=join(base,names[0]);
  const cli=spawnSync(process.execPath,[entry],{encoding:'utf8'});
  assert.equal(cli.status,1);assert.equal(cli.stdout,'');
  assert.deepEqual(JSON.parse(cli.stderr),{status:'FAIL',code:'ARTIFACT_AND_FRESH_DEFINES_REQUIRED'});
  const imported=spawnSync(process.execPath,['--input-type=module','-e',`await import(${JSON.stringify(pathToFileURL(entry).href)})`],{encoding:'utf8'});
  assert.equal(imported.status,0);assert.equal(imported.stdout,'');assert.equal(imported.stderr,'');
 }finally{await rm(base,{recursive:true,force:true});}
});
