// Isolated SQL/adapter contract fixture. This uses a disposable local PostgreSQL
// cluster and synthetic rows only. The schema/auth/RLS are stubbed: this checks
// shapes, not admission, deployment, or production authorization.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname,join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const root=process.env.BURI_TEST_SOURCE_ROOT??fileURLToPath(new URL('../../../',import.meta.url));
const bin=process.env.BURI_TEST_PG_BIN??'/Users/jeanbosco/Library/Caches/collect-supabase-implementation-20261020/pg/bin';
const pgModule=process.env.BURI_TEST_PG_MODULE??'/Users/jeanbosco/Library/Caches/collect-supabase-implementation-20261020/node_modules/pg';
const fixture=join(dirname(fileURLToPath(import.meta.url)),'source-parity.generated.json');
const pins={
 'supabase/migrations/20261020134444_collect_curated_platform_baseline.sql':'0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0',
 'supabase/migrations/20261109234517_burimunsi_native_operator_schema.sql':'c28ec95df7296052d911219c64a8a3d3fbbd60d77cfc222bd2f5de3590dfff2f',
 'supabase/migrations/20261110032620_burimunsi_native_provisioning.sql':'5e9a35580ac9086ffd82f4557a54651a1f1139eac260fd1539b4d8fa689192b7',
 'supabase/migrations/20261110181003_burimunsi_gateway_handoff.sql':'d16e86c128a887059afc7b2c5d4b6e3929850a1068d070bed8eb26616fe9795f',
 'supabase/functions/_shared/domain/burimunsi/admin-scope-setup.js':'ad9042d1a742b535a1aa77d753044cc591cc4f3ff67c66f7e65b1a801259017b',
 'supabase/functions/_shared/domain/burimunsi/admin-provisioning.js':'a216cf3712ca09d8d538a6a1a7a0a16035c125dd5bf940be64803b5f60ab6cbc',
 'supabase/functions/_shared/domain/burimunsi/values.js':'3a2af04ff98054880652cababb2c5847d4bd18fddee697a17e4ef4868004171c',
 'supabase/functions/_shared/domain/burimunsi/policy.js':'de93af959fe41932101499f968744b5f36a60dba19de222f097359473953c2c4',
 'supabase/functions/_shared/domain/core.js':'c95cb47a7b49fd33f82b4e9b4016f679b083603ac8d71c08296bdb786f010b27',
 'supabase/functions/_shared/domain/admin_burimunsi_operators.js':'d815b6ed336ba8fd1531e75c88c839185bb0fd063f0b949cf94da7d3de31d89d',
 'supabase/functions/_shared/domain/admin_burimunsi_provisioning.js':'901d30a38e44cc4daa219acc9baa23a20f596b7b7ed4d769858d6dde35b646d9',
 'supabase/functions/_shared/domain/admin_burimunsi_setup.js':'576253b9176853b22e1aa6a8b7112b815f12839abd896016eee7f62ffd7e2210',
};
for(const [path,expected] of Object.entries(pins))assert.equal(createHash('sha256').update(readFileSync(join(root,path))).digest('hex'),expected,`source drift: ${path}`);
function source(path){return readFileSync(join(root,path),'utf8');}
function functionSql(path,start){const text=source(path),a=text.indexOf(start),b=text.indexOf('END;$fn$;',a);assert(a>=0&&b>a,`missing source function ${start}`);return text.slice(a,b+'END;$fn$;'.length);}
const operator=functionSql('supabase/migrations/20261109234517_burimunsi_native_operator_schema.sql','CREATE FUNCTION private.burimunsi_operator_directory(');
const provisioning=functionSql('supabase/migrations/20261110032620_burimunsi_native_provisioning.sql','CREATE FUNCTION private.burimunsi_provisioning_directory(');
const setup=functionSql('supabase/migrations/20261110181003_burimunsi_gateway_handoff.sql','CREATE OR REPLACE FUNCTION private.burimunsi_setup_directory(');
const {AdminScopeSetup}=await import(pathToFileURL(join(root,'supabase/functions/_shared/domain/burimunsi/admin-scope-setup.js')).href);
const {AdminNativeProvisioning}=await import(pathToFileURL(join(root,'supabase/functions/_shared/domain/burimunsi/admin-provisioning.js')).href);
const {text:sourceText}=await import(pathToFileURL(join(root,'supabase/functions/_shared/domain/core.js')).href);
assert.equal(sourceText('Synthetic\nline','group name',100),'Synthetic\nline');
const {Client}=createRequire(import.meta.url)(pgModule);
const dir=mkdtempSync('/private/tmp/collect-buri-source-parity-'),data=join(dir,'data'),socket=join(dir,'socket');mkdirSync(socket);
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')));let started=false,client;
try{
 execFileSync(join(bin,'initdb'),['-D',data,'-U','postgres','--no-locale','--encoding=UTF8','--auth-local=trust','--auth-host=reject'],{env,stdio:'pipe'});
 execFileSync(join(bin,'pg_ctl'),['-D',data,'-l',join(dir,'postgres.log'),'-o',`-F -c listen_addresses='' -c unix_socket_directories='${socket}' -p 5432`,'-w','start'],{env,stdio:'pipe'});started=true;
 client=new Client({host:socket,port:5432,user:'postgres',database:'postgres'});await client.connect();
 assert.equal((await client.query('SHOW listen_addresses')).rows[0].listen_addresses,'');
 await client.query(`
  CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA api;CREATE SCHEMA auth;
  CREATE TABLE app.collections(id text PRIMARY KEY,status text,title text,receiver_network text,receiver_momo_number text,revision bigint);
  CREATE TABLE app.momo_receiving_accounts(id text PRIMARY KEY,status text,provider text,public_code text,recipient_name text,profile_status text,profile_version bigint);
  CREATE TABLE app.momo_gateway_credentials(binding_id text,id text,installation_id uuid,revoked_at timestamptz);
  CREATE TABLE app.admin_users(id text PRIMARY KEY,email text,display_name text,role text,status text);
  CREATE TABLE app.users(id text PRIMARY KEY,access_status text);
  CREATE TABLE app.admin_principal_links(admin_user_id text,user_id text);
  CREATE TABLE private.auth_principal_links(user_id text,auth_user_id uuid);
  CREATE TABLE auth.users(id uuid,email text,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
  CREATE TABLE private.burimunsi_scopes(collection_id text PRIMARY KEY,receiving_account_id text,enabled boolean,version bigint,active_binding_id text,binding_version bigint);
  CREATE TABLE private.burimunsi_operator_approvals(collection_id text,principal_user_id text,admin_user_id text,phone text,role text,capabilities text[],active boolean,version bigint);
  CREATE TABLE private.burimunsi_accounts(id uuid,collection_id text,principal_user_id text,name text,active boolean,removed boolean,role text,capabilities text[],version bigint,credential_version bigint);
  CREATE TABLE private.burimunsi_device_grants(id uuid,collection_id text,installation_id uuid,version bigint,custodian_account_id uuid,profile text,active boolean,created_at timestamptz);
  CREATE TABLE private.burimunsi_device_accounts(grant_id uuid,collection_id text,account_id uuid);
  CREATE TABLE private.burimunsi_owner_commands(collection_id text,actor_id text,request_id uuid,principal_session_id text,response jsonb);
  CREATE FUNCTION api.current_principal_id() RETURNS text LANGUAGE sql AS $$SELECT 'synthetic-owner'::text$$;
  CREATE FUNCTION private.admin_invitation_actor(text,text,text,text) RETURNS text LANGUAGE sql AS $$SELECT 'synthetic-session'::text$$;
  CREATE FUNCTION private.burimunsi_setup_actor(text,text,text,text) RETURNS jsonb LANGUAGE sql AS $$SELECT '{"principalId":"synthetic-owner"}'::jsonb$$;
  CREATE FUNCTION private.burimunsi_gateway_pending(text) RETURNS jsonb LANGUAGE sql AS $$SELECT NULL::jsonb$$;
  CREATE FUNCTION private.burimunsi_gateway_target_snapshot(text,uuid,uuid,uuid,bigint) RETURNS jsonb LANGUAGE sql AS $$SELECT NULL::jsonb$$;
  CREATE FUNCTION private.burimunsi_operator_is_current(text,text,text,text,text[]) RETURNS boolean LANGUAGE sql AS $$
   SELECT EXISTS(SELECT 1 FROM private.burimunsi_operator_approvals o WHERE o.collection_id=$1 AND o.principal_user_id=$2 AND o.active)
  $$;
  ${operator}\n${provisioning}\n${setup}
 `);
 const sqlResult=async(sql,parameters=[]) => (await client.query(sql,parameters)).rows[0].result;
 const scopeService=Object.create(AdminScopeSetup.prototype);
 const provisioningService=Object.create(AdminNativeProvisioning.prototype);provisioningService.groupId='synthetic-savings';
 async function scope(){const value=await sqlResult("SELECT private.burimunsi_setup_directory('a','b','c','d',NULL) result");scopeService.invoke=async()=>value;return scopeService.directory();}
 async function operatorDirectory(){await client.query("SELECT set_config('burimunsi.collection_id','synthetic-savings',false)");return sqlResult("SELECT private.burimunsi_operator_directory('a','b','c','d','synthetic-savings',NULL) result");}
 async function native(){
  await client.query("SELECT set_config('burimunsi.collection_id','synthetic-savings',false)");
  provisioningService.invoke=async(_name,_args,readResult)=>readResult(await sqlResult("SELECT private.burimunsi_provisioning_directory('a','b','c','d','synthetic-savings') result"));
  return provisioningService.directory();
 }
 const empty={setup:await scope(),operators:await operatorDirectory(),provisioning:await native()};
 await client.query(`
  INSERT INTO app.collections VALUES('synthetic-savings','active','Synthetic savings','mtn_momo',NULL,1),
   ('untitled-other','active','','mtn_momo',NULL,4),('long-title','active',repeat('L',161),'mtn_momo',NULL,2),
   ('multiline','active',E'Synthetic\\nline','mtn_momo',NULL,1);
  INSERT INTO app.momo_receiving_accounts VALUES('synthetic-receiver','active','mtn_momo','test-code','Synthetic recipient','verified',2);
  INSERT INTO private.burimunsi_scopes VALUES('synthetic-savings','synthetic-receiver',false,7,NULL,0),
   ('untitled-other','synthetic-receiver',false,3,NULL,0),('long-title','synthetic-receiver',false,2,NULL,0),
   ('multiline','synthetic-receiver',false,2,NULL,0);
  INSERT INTO app.admin_users VALUES('legacy-staff-42','staff@example.test','Synthetic staff','staff','active'),
   ('legacy-second-43','second@example.test','Synthetic second','staff','active');
  INSERT INTO app.users VALUES('55555555-5555-4555-8555-555555555555','active'),('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','active');
  INSERT INTO app.admin_principal_links VALUES('legacy-staff-42','55555555-5555-4555-8555-555555555555'),('legacy-second-43','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  INSERT INTO private.auth_principal_links VALUES('55555555-5555-4555-8555-555555555555','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  INSERT INTO auth.users VALUES('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','staff@example.test','2025-01-01',NULL,NULL),('cccccccc-cccc-4ccc-8ccc-cccccccccccc','second@example.test','2025-01-01',NULL,NULL);
  INSERT INTO private.burimunsi_operator_approvals VALUES('synthetic-savings','55555555-5555-4555-8555-555555555555','legacy-staff-42','+250780000002','staff',ARRAY['records.read','members.enroll'],true,5),
   ('synthetic-savings','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','legacy-second-43','+250780000003','staff',ARRAY['records.read'],false,3);
  INSERT INTO private.burimunsi_accounts VALUES('99999999-9999-4999-8999-999999999999','synthetic-savings','55555555-5555-4555-8555-555555555555','Synthetic staff',true,false,'staff',ARRAY['records.read','members.enroll'],6,2);
  INSERT INTO private.burimunsi_device_grants VALUES('88888888-8888-4888-8888-888888888888','synthetic-savings','77777777-7777-4777-8777-777777777777',9,NULL,'internal_receiver',true,'2025-01-01');
 `);
 const populated={setup:await scope(),operators:await operatorDirectory(),provisioning:await native()};
 await client.query(`INSERT INTO app.admin_users VALUES('legacy-admin-47','legacy@example.test','Legacy principal','staff','active');
  INSERT INTO app.users VALUES('Legacy-Principal-47','active');
  INSERT INTO app.admin_principal_links VALUES('legacy-admin-47','Legacy-Principal-47');
  INSERT INTO private.auth_principal_links VALUES('Legacy-Principal-47','ffffffff-ffff-4fff-8fff-ffffffffffff');
  INSERT INTO auth.users VALUES('ffffffff-ffff-4fff-8fff-ffffffffffff','legacy@example.test','2025-01-01',NULL,NULL);`);
 const opaquePrincipal=await operatorDirectory();
 await client.query(`INSERT INTO private.burimunsi_operator_approvals VALUES('synthetic-savings','Legacy-Principal-47','legacy-admin-47','+250780000004','staff',ARRAY['records.read'],true,1);`);
 const legacyApproval=await operatorDirectory();
 // The provisioning HTTP adapter itself rejects a non-UUID approved principal.
 // This is a backend boundary; the React parser cannot make that GET succeed.
 await assert.rejects(native(),error=>error?.status===400&&error?.code==='invalid_parameter');
 // A different current principal for the same text admin ID is representable
 // in this simplified schema; the UI must not silently join the two accounts.
 await client.query(`INSERT INTO app.users VALUES('dddddddd-dddd-4ddd-8ddd-dddddddddddd','active');
  INSERT INTO private.auth_principal_links VALUES('dddddddd-dddd-4ddd-8ddd-dddddddddddd','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
  INSERT INTO auth.users VALUES('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','staff@example.test','2025-01-01',NULL,NULL);
  DELETE FROM app.admin_principal_links WHERE admin_user_id='legacy-staff-42';
  INSERT INTO app.admin_principal_links VALUES('legacy-staff-42','dddddddd-dddd-4ddd-8ddd-dddddddddddd');`);
 const mismatched=await operatorDirectory();
 const document={source:'collect-supabase-cloud-source',pins,empty,populated,mismatched,opaquePrincipal,legacyApproval,legacyProvisioningFailure:{status:400,code:'invalid_parameter'}};
 const json=JSON.stringify(document,null,2)+'\n';
 if(process.argv.includes('--write')){writeFileSync(fixture,json);console.log(`Wrote synthetic source parity fixture: ${fixture}`);}
 else {assert.equal(readFileSync(fixture,'utf8'),json,'Stored synthetic fixture differs from pinned source functions');console.log('Pinned synthetic SQL and source-adapter fixtures match.');}
}finally{
 if(client)await client.end().catch(()=>{});
 if(started){const result=spawnSync(join(bin,'pg_ctl'),['-D',data,'-m','fast','-w','stop'],{env,encoding:'utf8'});if(result.status!==0)throw new Error(`Could not stop disposable PostgreSQL: ${dir}`);}
 rmSync(dir,{recursive:true,force:true});
}
