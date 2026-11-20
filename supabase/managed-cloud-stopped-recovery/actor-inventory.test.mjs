// Owned, socket-only PG17 fixture. No cloud connection or production mutation.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import pg from '../../scripts/supabase/node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../../scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs';

const inventorySql=await readFile(new URL('./actor-inventory.sql',import.meta.url),'utf8');
const role=(snapshot,name)=>{
 const matches=snapshot.login_roles.filter(value=>value.login_role===name);
 assert.equal(matches.length,1,`fixture role ${name} must be present once`);return matches[0];
};

test('managed admission actor inventory follows SET ROLE and never authorizes cutover',{timeout:120000},async t=>{
 const cluster=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_actor_synthetic_only'});
 const clients=[];
 const connect=async user=>{const client=new pg.Client({host:cluster.socket,port:cluster.port,database:'postgres',user,connectionTimeoutMillis:3000});
  client.on('error',()=>{});await client.connect();clients.push(client);return client;};
 try{
  const db=await connect('fixture_bootstrap');
  const identity=(await db.query("SELECT inet_server_addr() IS NULL AS socket_only,current_setting('server_version_num')::int/10000 AS major")).rows[0];
  assert.deepEqual(identity,{socket_only:true,major:17});
  await db.query(`CREATE SCHEMA private;
   CREATE TABLE private.collect_fence_admissions(secret text);
   INSERT INTO private.collect_fence_admissions VALUES('synthetic-only');
   ALTER TABLE private.collect_fence_admissions ENABLE ROW LEVEL SECURITY;
   CREATE TABLE private.collect_fence_control(singleton boolean);
   CREATE FUNCTION private.collect_fence_register(uuid,text,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.collect_fence_assert_work(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.collect_fence_close(uuid,bigint,text,text,text,integer,integer) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC;
   REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC;
   CREATE ROLE synthetic_target NOLOGIN;
   CREATE ROLE synthetic_bridge NOLOGIN NOINHERIT;
   CREATE ROLE synthetic_transitive LOGIN NOINHERIT;
   CREATE ROLE synthetic_blocked LOGIN NOINHERIT;
   CREATE ROLE synthetic_inherited LOGIN INHERIT;
   CREATE ROLE synthetic_admin_option LOGIN NOINHERIT;
   CREATE ROLE synthetic_expired LOGIN VALID UNTIL '2000-01-01 00:00:00+00';
   GRANT USAGE ON SCHEMA private TO synthetic_target;
   GRANT EXECUTE ON FUNCTION private.collect_fence_register(uuid,text,text) TO synthetic_target;
   GRANT SELECT ON private.collect_fence_admissions TO synthetic_target;
   GRANT synthetic_bridge TO synthetic_transitive WITH SET TRUE, INHERIT FALSE;
   GRANT synthetic_target TO synthetic_bridge WITH SET TRUE, INHERIT FALSE;
   GRANT synthetic_target TO synthetic_blocked WITH SET FALSE, INHERIT FALSE;
   GRANT synthetic_target TO synthetic_inherited WITH SET FALSE, INHERIT TRUE;
   GRANT synthetic_target TO synthetic_admin_option WITH ADMIN TRUE, SET FALSE, INHERIT FALSE;`);
  const capture=async()=>{
   const rows=(await db.query(inventorySql)).rows;assert.equal(rows.length,1);return rows[0].inventory;
  };
  await t.test('transitive SET and inherited grants are considered separately from blocked memberships',async()=>{
   const snapshot=await capture();assert.equal(snapshot.catalogue_targets_present,true);assert.equal(snapshot.postgres_major,17);
   assert.equal(role(snapshot,'synthetic_transitive').reachable_direct_register,true);
   assert.ok(Number(role(snapshot,'synthetic_transitive').reachable_role_count)>=3);
   assert.equal(role(snapshot,'synthetic_inherited').reachable_direct_register,true);
   assert.equal(role(snapshot,'synthetic_blocked').reachable_direct_register,false);
   assert.equal(role(snapshot,'synthetic_admin_option').reachable_direct_register,false);
   assert.equal(role(snapshot,'synthetic_admin_option').reachable_role_admin_option,true);
   const login=await connect('synthetic_transitive');await login.query('SET ROLE synthetic_target');
   await login.query("SELECT private.collect_fence_register(gen_random_uuid(),'synthetic','http_collect')");
   assert.equal((await login.query('SELECT count(*)::int n FROM private.collect_fence_admissions')).rows[0].n,0,
    'a SELECT grant does not bypass RLS');
   await login.query('RESET ROLE');
  });
  await t.test('an expired password is not treated as a stopped role or absent session',async()=>{
   const login=await connect('synthetic_expired');
   assert.equal((await login.query('SELECT current_user AS name')).rows[0].name,'synthetic_expired');
   const snapshot=await capture(),actor=role(snapshot,'synthetic_expired');
   assert.equal(actor.password_expired,true);assert.ok(Number(actor.observed_client_sessions)>=1);
   assert.equal(snapshot.executor_stopped_verified,false);assert.equal(snapshot.provider_issuance_closed,false);
  });
  await t.test('catalogue changes invalidate an earlier point-in-time actor snapshot',async()=>{
   const before=await capture();assert.equal(role(before,'synthetic_blocked').reachable_direct_register,false);
   await db.query('GRANT synthetic_target TO synthetic_blocked WITH SET TRUE');
   const after=await capture();assert.equal(role(after,'synthetic_blocked').reachable_direct_register,true);
   assert.equal(role(before,'synthetic_blocked').reachable_direct_register,false);
   for(const snapshot of [before,after]){
    assert.equal(snapshot.cutover_authorized,false);assert.equal(snapshot.project_identity_verified,false);
    assert.equal(snapshot.session_inventory_complete,false);assert.equal(snapshot.security_definer_paths_complete,false);
   }
  });
  await t.test('temporary credential renewal and grants change a later snapshot',async()=>{
   const before=await capture();assert.equal(role(before,'synthetic_expired').password_expired,true);
   assert.equal(role(before,'synthetic_expired').reachable_direct_register,false);
   await db.query("ALTER ROLE synthetic_expired VALID UNTIL '2099-01-01 00:00:00+00'; GRANT synthetic_target TO synthetic_expired WITH SET TRUE");
   const after=await capture();assert.equal(role(after,'synthetic_expired').password_expired,false);
   assert.equal(role(after,'synthetic_expired').reachable_direct_register,true);
   assert.equal(role(before,'synthetic_expired').password_expired,true);
   assert.equal(after.provider_issuance_closed,false);assert.equal(after.cutover_authorized,false);
  });
  await t.test('a missing fence function is reported as an incomplete catalogue',async()=>{
   await db.query('DROP FUNCTION private.collect_fence_close(uuid,bigint,text,text,text,integer,integer)');
   const snapshot=await capture();assert.equal(snapshot.catalogue_targets_present,false);
   assert.equal(snapshot.cutover_authorized,false);assert.equal(snapshot.executor_stopped_verified,false);
  });
 }finally{
  await Promise.allSettled(clients.map(client=>client.end()));
  const closed=await cluster.close();assert.equal(closed.removed,true,'owned fixture cleanup must be confirmed');
 }
});
