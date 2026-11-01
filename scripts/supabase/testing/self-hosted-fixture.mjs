// Disposable native qualification only. This is never a production installer.
// Original migration bytes are admitted by the maintained historical loader;
// its reviewed SQL10 metadata-only fixture substitution remains unchanged.
import {readFile,writeFile,mkdir,mkdtemp,copyFile,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomBytes,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {EXACT_CURRENT16,loadReviewedPlatformFixture,renderSyntheticSql} from './curated-platform-fixture.mjs';
const require=createRequire(import.meta.url),{Client}=require('pg');
const ROOT=resolve(import.meta.dirname,'../../..');
const need=(ok,code)=>{if(!ok)throw new Error(code);};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
export async function prepareSelfHostedFixture({adminUrl,purpose,output,initialize=true}){
 need(process.env.COLLECT_CI_SYNTHETIC==='true','EXPLICIT_SYNTHETIC_QUALIFICATION_REQUIRED');
 need(['backend','auth','notifications','recovery','gateway','integration'].includes(purpose),'FIXED_FIXTURE_PURPOSE_REQUIRED');
 need(typeof initialize==='boolean'&&(initialize||purpose==='integration'),'EXPLICIT_INTEGRATION_INITIALIZATION_REQUIRED');
 const target=new URL(adminUrl);
 need(target.protocol==='postgres:'&&target.hostname==='127.0.0.1'&&['55439','55443','55444','55445','55446','55447','55448','55449'].includes(target.port)&&target.pathname==='/postgres'&&target.username==='collect_test'&&target.password&&!target.search&&!target.hash,'OWNED_LOOPBACK_ADMIN_REQUIRED');
 need(resolve(output)===output,'ABSOLUTE_PRIVATE_OUTPUT_REQUIRED');
 try{await stat(output);throw new Error('FRESH_PRIVATE_OUTPUT_REQUIRED');}catch(error){if(error.code!=='ENOENT')throw error;}
 const database='collect_selfhost_'+purpose+'_'+randomBytes(12).toString('hex')+'_test';
 const connect=async url=>{const client=new Client({connectionString:url,connectionTimeoutMillis:5000,statement_timeout:60000});await client.connect();return client;};
 const admin=await connect(adminUrl);let setup,owner;
 try{
  const identity=(await admin.query("SELECT current_user,session_user,current_database(),host(inet_server_addr()) AS host,current_setting('server_version_num')::int/10000 AS major,(SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname=current_user) AS bootstrap")).rows[0];
  need(identity.current_user==='collect_test'&&identity.session_user==='collect_test'&&identity.current_database==='postgres'&&identity.host==='127.0.0.1'&&identity.major===17&&identity.bootstrap,'OWNED_PG17_BOOTSTRAP_REQUIRED');
  const prefix=await mkdtemp(join(tmpdir(),'collect-original16-'));
  await mkdir(join(prefix,'supabase/migrations'),{recursive:true});await mkdir(join(prefix,'supabase/tests/sql'),{recursive:true});
  for(const name of EXACT_CURRENT16)await copyFile(join(ROOT,'supabase/migrations',name),join(prefix,'supabase/migrations',name));
  await copyFile(join(ROOT,'supabase/tests/sql/00_local_auth_fixture.sql'),join(prefix,'supabase/tests/sql/00_local_auth_fixture.sql'));
  const fixture=await loadReviewedPlatformFixture(prefix,{includeStoppedAdmissionLifecycleMigration:true});
  await admin.query('CREATE DATABASE "'+database+'" OWNER collect_test TEMPLATE template0 ENCODING \'UTF8\'');
  const setupUrl=new URL(target);setupUrl.pathname='/'+database;setup=await connect(setupUrl.href);
  await setup.query(fixture.auth);
  const role=(await setup.query("SELECT rolcanlogin,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolbypassrls,rolreplication FROM pg_roles WHERE rolname='postgres'")).rows[0];
  need(role&&!role.rolsuper&&!role.rolinherit&&!role.rolcreatedb&&!role.rolbypassrls&&!role.rolreplication&&role.rolcanlogin===role.rolcreaterole,'NORMAL_OR_RESTRICTED_FIXTURE_OWNER_REQUIRED');
  for(const item of fixture.rawMigrations.slice(0,9))await setup.query(item.sql);
  const sqlInterface=await readFile(join(ROOT,'scripts/supabase/testing/member-realtime-interface.sql'),'utf8');
  need(sha(sqlInterface)===fixture.binding.interface_sha256,'REVIEWED_REALTIME_INTERFACE_REQUIRED');await setup.query(sqlInterface);
  let refused=false;try{await setup.query(fixture.rawMigrations[9].sql);}catch(error){refused=error.code==='55000'&&error.message==='member_realtime_metadata_not_reviewed';}finally{await setup.query('ROLLBACK');}
  need(refused,'HOSTED_METADATA_MUST_REFUSE_LOCAL_FIXTURE');
  await setup.query(renderSyntheticSql(fixture.rawMigrations[9].sql,fixture.binding));
  for(const item of fixture.rawMigrations.slice(10,13))await setup.query(item.sql);
  // Only the new disposable database is transferred; no existing database or
  // application row is reset. Runtime never receives bootstrap credentials.
  await setup.query(`DO $owner$ DECLARE r record;BEGIN
   IF current_user<>'collect_test' OR session_user<>'collect_test' OR current_database()<>'${database}' OR host(inet_server_addr())<>'127.0.0.1' THEN RAISE EXCEPTION 'OWNED_NEW_FIXTURE_REQUIRED';END IF;
   FOR r IN SELECT nspname FROM pg_namespace WHERE nspowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND nspname NOT LIKE 'pg_%' AND nspname<>'information_schema' LOOP EXECUTE format('ALTER SCHEMA %I OWNER TO postgres',r.nspname);END LOOP;
   FOR r IN SELECT c.oid::regclass object,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind IN('r','p','v','m','f') LOOP EXECUTE format('ALTER %s %s OWNER TO postgres',CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,r.object);END LOOP;
   FOR r IN SELECT c.oid::regclass object FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO postgres',r.object);END LOOP;
   FOR r IN SELECT p.oid::regprocedure object FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND p.prokind='f' LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.object);END LOOP;
  END;$owner$;`);
  await admin.query('ALTER DATABASE "'+database+'" OWNER TO postgres');
  // A fresh cluster's restricted fixture role becomes a normal owner. Reuse
  // requires the exact existing private descriptor, never a password rotation.
  let password;
  if(!role.rolcanlogin){password=randomBytes(24).toString('hex');await admin.query("ALTER ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION PASSWORD '"+password+"'");}
  else {need(process.env.COLLECT_SELFHOST_FIXTURE_OWNER_FILE,'EXISTING_OWNER_DESCRIPTOR_REQUIRED');const prior=JSON.parse(await readFile(process.env.COLLECT_SELFHOST_FIXTURE_OWNER_FILE,'utf8'));const priorUrl=new URL(prior.url);need(priorUrl.hostname===target.hostname&&priorUrl.port===target.port&&priorUrl.username==='postgres','SAME_CLUSTER_OWNER_REQUIRED');password=decodeURIComponent(priorUrl.password);}
  const ownerUrl=new URL(setupUrl);ownerUrl.username='postgres';ownerUrl.password=password;owner=await connect(ownerUrl.href);
  await owner.query(fixture.stoppedAdmissionLifecycle.sql);await owner.query(fixture.clientDiagnostics.sql);await owner.query(fixture.notificationDelivery.sql);
  const sourceSha256=sha(JSON.stringify(fixture.rawMigrations.map(m=>({name:m.name,sha256:m.sha256})))+fixture.clientDiagnostics.sha256+fixture.notificationDelivery.sha256);
  if(initialize)await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[crypto.randomUUID(),sourceSha256,'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3']);
  await writeFile(output,JSON.stringify({format:'collect.selfhost.fixture.v1',url:ownerUrl.href,database,purpose,migration_count:16,source_sha256:sourceSha256,controller_initialized:initialize,synthetic:true,public_acceptance:false})+'\n',{flag:'wx',mode:0o600});
  return {format:'collect.selfhost.fixture.ready.v1',database,migration_count:16,owner:'normal_non_superuser_no_bypassrls',synthetic:true};
 }finally{await owner?.end();await setup?.end();await admin.end();}
}
