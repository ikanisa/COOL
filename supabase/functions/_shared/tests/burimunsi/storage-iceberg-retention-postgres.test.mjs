// Runs only against a prepared, owner-labelled, networkless synthetic PG17
// fixture. The checked-in SQL wraps all census/policy writes in a rollback.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';

const name=process.env.COLLECT_ICEBERG_RETENTION_TEST_CONTAINER;
const context=process.env.COLLECT_SYNTHETIC_DOCKER_CONTEXT;
const admission=process.env.COLLECT_ICEBERG_TEST_ADMISSION;
const source='a'.repeat(64);
const docker=(args,input)=>spawnSync('docker',[...(context?['--context',context]:[]),...args],{input,encoding:'utf8',maxBuffer:1000000});
function safeContainer(){
 assert.match(name??'',/^codex-iceberg-census-[0-9a-f]{8}$/);
 assert.match(admission??'',/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
 const result=docker(['inspect',name]);assert.equal(result.status,0,'Synthetic fixture is not available');
 const info=JSON.parse(result.stdout)[0],label=info.Config.Labels?.['io.collect.iceberg-census'];
 assert.match(label??'',/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
 assert.equal(name,'codex-iceberg-census-'+label.slice(0,8));
 assert.equal(info.Name,'/'+name);assert.equal(info.State.Running,true);
 assert.equal(info.HostConfig.NetworkMode,'none');assert.equal(info.HostConfig.Privileged,false);
 assert(info.HostConfig.Memory>0&&info.HostConfig.Memory<=768*1024*1024);
 assert.deepEqual(info.Mounts,[]);assert.equal(Object.keys(info.HostConfig.PortBindings??{}).length,0);
 assert.equal(info.Config.Image,'public.ecr.aws/supabase/postgres:17.11.0.006');
}
function sql(input){
 safeContainer();const result=docker(['exec','-i',name,'psql','-h','/tmp','-U','postgres','-d','postgres','-XAtq','-v','ON_ERROR_STOP=1'],input);
 assert.equal(result.status,0,(result.stderr||'Synthetic fixture failed').slice(-3000));return result.stdout.trim();
}

test('captured Iceberg inventory remains unknown and cannot authorize disposition',{skip:!name},()=>{
 const ready=sql(`SELECT current_database()='postgres' AND current_user='postgres'
  AND (SELECT mode='open' AND source_sha256='${source}' FROM private.collect_fence_control WHERE singleton)
  AND (SELECT count(*)=2 AND bool_and(email LIKE '%@synthetic.invalid') FROM app.users)
  AND (SELECT count(*)=1 FROM app.deletion_requests)
  AND (SELECT count(*)=1 FROM storage.buckets_analytics)
  AND (SELECT count(*)=1 FROM storage.iceberg_namespaces)
  AND (SELECT count(*)=1 FROM storage.iceberg_tables);`);
 assert.equal(ready,'t','Fixture does not match the prepared synthetic census');
 const path=new URL('../../../../tests/burimunsi/storage-iceberg-retention-contract.sql',import.meta.url);
 const contract=readFileSync(path,'utf8').replaceAll('__ADMIN_ADMISSION__',admission).replaceAll('__SOURCE__',source);
 assert.equal(sql(contract).split('\n').at(-1),'synthetic_census_and_policy_pass');
});
