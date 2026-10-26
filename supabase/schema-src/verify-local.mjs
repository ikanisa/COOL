// Explicit isolated PostgreSQL fixture verification. Never targets a provider.
import {readFile,readdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
const connectionString=process.env.COLLECT_SCHEMA_TEST_URL;
if(!connectionString)throw new Error('Set COLLECT_SCHEMA_TEST_URL for a dedicated local *_test database.');
const url=new URL(connectionString);
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||!url.pathname.endsWith('_test'))throw new Error('Only dedicated loopback *_test databases are supported.');
const moduleRoot=process.env.COLLECT_PG_MODULE;
if(!moduleRoot)throw new Error('Set COLLECT_PG_MODULE to the pinned local pg module package.json.');
const require=createRequire(moduleRoot);const {Client}=require('pg');
const client=new Client({connectionString});await client.connect();
try{
 const version=(await client.query('SHOW server_version')).rows[0].server_version;
 if(!version.startsWith('17.'))throw new Error('PostgreSQL17 required.');
 const existing=(await client.query("SELECT count(*)::int n FROM pg_tables WHERE schemaname='app'")).rows[0].n;
 if(existing!==0)throw new Error('Use a fresh isolated database; this verifier never drops existing app data.');
 await client.query(await readFile(new URL('../tests/sql/00_local_auth_fixture.sql',import.meta.url),'utf8'));
 await client.query(await readFile(new URL('./baseline.sql',import.meta.url),'utf8'));
 for(const file of (await readdir(new URL('../tests/sql/',import.meta.url))).filter(name=>/^\d+.*\.sql$/.test(name)&&!name.startsWith('00_')).sort()){
  try{await client.query(await readFile(new URL('../tests/sql/'+file,import.meta.url),'utf8'));}
  catch(error){await client.query('ROLLBACK');throw new Error(file+': '+error.message,{cause:error});}
  process.stdout.write(JSON.stringify({test:file,result:'pass',runtime:version,synthetic_auth_fixture:true})+'\n');
 }
}finally{await client.end();}
