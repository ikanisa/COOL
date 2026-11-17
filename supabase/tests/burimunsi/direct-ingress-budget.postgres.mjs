// Socket-only synthetic PostgreSQL fixture using the actual pinned budget SQL.
// Run with node --test; it never connects to an existing database or provider.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../../scripts/supabase/node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../../../scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../../functions/_shared/deployment-profile.js';
import {admitDirectSupabaseNativeIngress} from '../../functions/_shared/native-direct-supabase-ingress.js';

const migration=await readFile(new URL('../../migrations/20261110143000_burimunsi_native_phone_pin.sql',import.meta.url),'utf8');
function extract(start,end){const a=migration.indexOf(start),b=migration.indexOf(end,a);assert(a>=0&&b>a);return migration.slice(a,b+end.length);}
const table=extract('CREATE TABLE private.burimunsi_pin_login_limits(','\n);');
const budget=extract('CREATE FUNCTION private.burimunsi_pin_login_budget(', 'END;$fn$;');
const profile={format:'collect.deployment.v1',id:'direct-budget-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.fixture.invalid',admin_origin:'https://admin.fixture.invalid',
 public_origin:'https://collect.fixture.invalid',google_callback_origin:'https://admin.fixture.invalid'};
const raw=canonicalProfile(profile),hash=s=>createHash('sha256').update(s).digest('hex');
const env={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash(raw),APP_ENVIRONMENT:'qualification',
 SUPABASE_URL:MANAGED_SUPABASE_ORIGIN,BURIMUNSI_NATIVE_ENABLED:'true',COLLECT_NATIVE_INGRESS_MODE:'supabase_direct_v1'};
const request=()=>new Request(MANAGED_SUPABASE_ORIGIN+'/v1/burimunsi/session/login',{method:'POST',body:'{}'});

test('direct global bucket retains the actual account, installation and concurrent global budgets',{timeout:120000},async()=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'}),clients=[];
 try{
  for(let i=0;i<5;i++){const c=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
   c.on('error',()=>{});await c.connect();clients.push(c);}
  const c=clients[0];await c.query("CREATE SCHEMA private; CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN; END$$;");
  await c.query(table);await c.query(budget);
  // Keep the contention assertion inside one real 15-minute window even if
  // the fixture happens to start immediately before its natural rollover.
  const clock=await c.query('SELECT (extract(epoch FROM clock_timestamp())*1000)::bigint AS ms');
  const remaining=900000-Number(clock.rows[0].ms)%900000;
  if(remaining<4000)await new Promise(resolve=>setTimeout(resolve,remaining+100));
  const admitted=await admitDirectSupabaseNativeIngress(request(),env),network=await admitted.networkBucket(admitted.request);
  const call=async(conn,account,installation)=>{
   const q=await conn.query('SELECT private.burimunsi_pin_login_budget($1,$2::uuid,$3,(extract(epoch FROM clock_timestamp())*1000)::bigint) AS allowed',
    [hash(account),installation,network]);return q.rows[0].allowed;
  };
  const sameAccount=Array.from({length:6},()=>randomUUID());
  for(let i=0;i<sameAccount.length;i++)assert.equal(await call(c,'same-account',sameAccount[i]),i<5);
  await c.query('TRUNCATE private.burimunsi_pin_login_limits');
  const sameInstallation=randomUUID();
  for(let i=0;i<11;i++)assert.equal(await call(c,'separate-account-'+i,sameInstallation),i<10);
  await c.query('TRUNCATE private.burimunsi_pin_login_limits');
  for(let i=0;i<49;i++)assert.equal(await call(c,'global-account-'+i,randomUUID()),true);
  const results=await Promise.all(clients.slice(1).map((client,i)=>call(client,'concurrent-account-'+i,randomUUID())));
  assert.equal(results.filter(Boolean).length,1);assert.equal(results.filter(x=>x===false).length,3);
  const rows=await c.query("SELECT attempts,window_start FROM private.burimunsi_pin_login_limits WHERE bucket=$1",['network:'+network]);
  assert.equal(rows.rows.length,1);assert.equal(Number(rows.rows[0].attempts),53);
  assert.equal(Number(rows.rows[0].window_start)%900000,0);
 }finally{
  await Promise.all(clients.map(c=>c.end().catch(()=>{})));const result=await f.close();assert.equal(result.removed,true);
 }
});
