// The ordinary Edge source suite does not start PostgreSQL. The six native
// cases remain a separate, explicit qualification that fails without its
// synthetic PG17 prerequisites; this source test must not claim that coverage.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {fixtureTableNames,parseFixtureOptions} from '../../../../scripts/supabase/testing/http-admission-pg/fixture.mjs';

const native=new URL('../../../../scripts/supabase/testing/http-admission-pg/native.test.mjs',import.meta.url);
const migration=new URL('../../../migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url);

test('the Edge source suite identifies the separate native PostgreSQL qualification',async t=>{
 const source=await readFile(native,'utf8');
 for(const name of ['cancellation after register COMMIT','timeout with late original COMMIT acknowledgement',
  'lost registration acknowledgement','cancelled close with lost acknowledgement',
  'duplicate registration cannot close','acknowledgement after the bounded cleanup window'])assert.ok(source.includes(name),name);
 assert.equal(/\btest\.(?:skip|todo)\s*\(/.test(source),false);
 t.diagnostic('Native PostgreSQL was not run by the Edge source suite; run scripts/supabase/testing/http-admission-pg/native.test.mjs with its explicit PG17 prerequisites.');
});
test('native qualification needs explicit synthetic opt-in and an absolute local binary directory',()=>{
 assert.throws(()=>parseFixtureOptions({}),/HTTP_ADMISSION_SYNTHETIC_OPT_IN_REQUIRED/);
 for(const bin of [undefined,'','relative','postgres://remote.example/db','/tmp/pg;echo'])
  assert.throws(()=>parseFixtureOptions({COLLECT_HTTP_ADMISSION_PG_QUALIFY:'true',COLLECT_HTTP_ADMISSION_PG_BIN_DIR:bin}),/HTTP_ADMISSION_PHYSICAL_PG_BIN_REQUIRED/);
 assert.throws(()=>parseFixtureOptions({COLLECT_HTTP_ADMISSION_PG_QUALIFY:'true',COLLECT_HTTP_ADMISSION_PG_BIN_DIR:'/synthetic/bin',COLLECT_HTTP_ADMISSION_PG_TMP_ROOT:'relative'}),/HTTP_ADMISSION_PHYSICAL_TEMP_ROOT_REQUIRED/);
 assert.deepEqual(parseFixtureOptions({COLLECT_HTTP_ADMISSION_PG_QUALIFY:'true',COLLECT_HTTP_ADMISSION_PG_BIN_DIR:'/synthetic/bin',
  COLLECT_HTTP_ADMISSION_PG_TMP_ROOT:'/synthetic/tmp',PGHOST:'untrusted.example',HTTP_FENCE_FIXTURE_RECEIPT:'unused'}),
  {bin:'/synthetic/bin',requestedTemp:'/synthetic/tmp'});
});
test('the isolated fixture requires the exact reviewed fence migration and 110-table scope',async()=>{
 const sql=await readFile(migration,'utf8'),names=fixtureTableNames(sql);assert.equal(names.length,110);assert.equal(new Set(names).size,110);
 assert.throws(()=>fixtureTableNames(sql+'\n'),/HTTP_ADMISSION_FENCE_SOURCE_CHANGED/);
});
test('the native qualification fails rather than silently skipping when its prerequisites are absent',()=>{
 const child=spawnSync(process.execPath,['--test','--test-concurrency=1',fileURLToPath(native)],
  {env:{PATH:'/usr/bin:/bin:/usr/sbin:/sbin'},encoding:'utf8',timeout:10000,maxBuffer:1048576});
 assert.ifError(child.error);assert.notEqual(child.status,0);
 assert.match(child.stdout+child.stderr,/HTTP_ADMISSION_SYNTHETIC_OPT_IN_REQUIRED/);
});
