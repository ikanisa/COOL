import test from 'node:test';
import assert from 'node:assert/strict';
import {withOwnedArchiveFixture} from '../../managed-migration-next/synthetic-fixture.mjs';
const wait=ms=>new Promise(r=>setTimeout(r,ms));

test('a previously cached absence must be cleared before deciding whether a marker exists',{timeout:180000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const marker='fixture_v3_stats_probe',present=async c=>(await c.query('SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name=$1) p',[marker])).rows[0].p;
  await f.watcher.query('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');
  try{
   assert.equal(await present(f.watcher),false);await f.owner.query("SELECT set_config('application_name',$1,false)",[marker]);
   const end=Date.now()+5000;let separate=false;while(Date.now()<end&&!separate){separate=await present(f.admin);if(!separate)await wait(25);}
   assert.equal(separate,true);assert.equal(await present(f.watcher),false);
   await f.watcher.query('SELECT pg_stat_clear_snapshot()');assert.equal(await present(f.watcher),true);
  }finally{await f.watcher.query('ROLLBACK');}
 });
});

test('a previously cached presence must be cleared before deciding whether a backend ended',{timeout:180000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const present=async c=>(await c.query('SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=$1) p',[f.backendPid])).rows[0].p;
  await f.watcher.query('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');
  try{
   assert.equal(await present(f.watcher),true);await f.owner.end();
   const end=Date.now()+5000;let separate=true;while(Date.now()<end&&separate){separate=await present(f.admin);if(separate)await wait(25);}
   assert.equal(separate,false);assert.equal(await present(f.watcher),true);
   await f.watcher.query('SELECT pg_stat_clear_snapshot()');assert.equal(await present(f.watcher),false);
  }finally{await f.watcher.query('ROLLBACK');}
 });
});
