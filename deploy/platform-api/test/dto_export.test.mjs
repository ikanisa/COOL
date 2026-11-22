import assert from 'node:assert/strict';
import {mkdtemp,readFile,realpath,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {exportDtos} from './support/dto_export.mjs';

test('routine DTO capture writes nothing without a requested output directory',async()=>{
  assert.equal(await exportDtos('admin-dto-examples.json',{synthetic:true},''),false);
});

test('requested DTO exports are external, exact and never overwrite an earlier capture',async t=>{
  const directory=await mkdtemp(join(await realpath(tmpdir()),'collect-dto-output-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  const value={scope:'Synthetic contract evidence only',rows:[]};
  assert.equal(await exportDtos('admin-dto-examples.json',value,directory),true);
  assert.deepEqual(JSON.parse(await readFile(join(directory,'admin-dto-examples.json'),'utf8')),value);
  await assert.rejects(exportDtos('admin-dto-examples.json',{changed:true},directory),{code:'EEXIST'});
  await assert.rejects(exportDtos('../admin-dto-examples.json',value,directory));
  await assert.rejects(exportDtos('admin-dto-examples.json',value,new URL('../',import.meta.url).pathname));
});
