// Explicitly requested local, private rehearsal. Source rows travel only via
// memory into the owned 0700 PG17 fixture, which is removed after confirmed stop.
// This never connects to, writes to, or calls a cloud service or provider.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {captureLocalSource} from './source-reader.mjs';
import {compileTransfer,sourceSnapshotHmac,verifyActorLineage} from './compile.mjs';
import {rehearseMaintenance} from './maintenance.mjs';

const stable = x => Array.isArray(x) ? '['+x.map(stable).join(',')+']' : x && typeof x==='object' ? '{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+stable(x[k])).join(',')+'}' : JSON.stringify(x);
const rel = name => name.split('.').map(s=>'"'+s+'"').join('.');
async function otherCounts(client,excluded) {
  const result=await client.query(`WITH counts AS MATERIALIZED (
    SELECT n.nspname||'.'||c.relname AS name,
      (xpath('/row/c/text()',query_to_xml(format('SELECT count(*) AS c FROM ONLY %I.%I',n.nspname,c.relname),false,true,'')))[1]::text::bigint AS n
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname IN ('app','private')
      AND NOT (n.nspname||'.'||c.relname=ANY($1::text[])))
    SELECT coalesce(jsonb_object_agg(name,n) FILTER(WHERE n<>0),'{}'::jsonb) AS value FROM counts`,[excluded]);
  return result.rows[0].value;
}
test('private source graph against source-schema owned PG fixture', {timeout:180000}, async () => {
  const capture=captureLocalSource();
  const dump=spawnSync('docker',['--context','colima-supabase-local','exec','supabase_db_local-app','pg_dump',
    '-U','postgres','-d','postgres','--schema-only','--no-owner','--no-privileges','--schema=app','--schema=private'],{maxBuffer:16*1024*1024,timeout:30000});
  assert.equal(dump.status,0,'source_schema_unavailable');
  const schema=dump.stdout.toString('utf8').split('\n').filter(line=>!line.startsWith('\\')).join('\n');
  const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_transfer_schema_fixture'});
  const bootstrap=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap'}), key=randomBytes(32);
  let c, observer, phase='setup', currentTable='none', completed=0;
  try {
    await bootstrap.connect();
    await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS; CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE ROLE service_role; CREATE ROLE collect_runtime; CREATE ROLE collect_importer`);
    await bootstrap.query('CREATE DATABASE collect_transfer_schema_fixture OWNER postgres');
    c=new pg.Client({host:f.socket,port:f.port,database:'collect_transfer_schema_fixture',user:'postgres'}); await c.connect();
    await c.query('CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY)');
    await c.query(schema);
    await c.query("SET row_security=on; SET TIME ZONE 'UTC'");
    await c.query(await readFile(new URL('./lineage.sql',import.meta.url),'utf8'));
    observer=new pg.Client({host:f.socket,port:f.port,database:'collect_transfer_schema_fixture',user:'fixture_bootstrap'}); await observer.connect();
    const op=randomUUID(), fenceOp=randomUUID(), primary=randomUUID(), src='a'.repeat(64);
    await c.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
      VALUES(true,'rrlduytparvsjfmegalh','dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',$1,1,'fenced',$2)`,[src,fenceOp]);
    const used=new Set(capture.snapshot.tables['app.users'].map(row=>row.public_id)); let alias=100000; while(used.has(String(alias)))alias++;
    let cloudPublic=alias+1; while(used.has(String(cloudPublic)))cloudPublic++;
    const targetUsers=[{id:primary,phone:null,email:null,public_id:String(cloudPublic)}];
    // Source-derived fake ETags and hashes are fixture inputs, not a provider proof.
    const proof=Object.fromEntries(capture.snapshot.tables['private.storage_objects'].map(o=>[o.object_key,{sha256:o.sha256,size:o.size,etag:'synthetic-fixture-etag'}]));
    const hmac=sourceSnapshotHmac(capture.snapshot,key,op);
    const plan=compileTransfer({snapshot:capture.snapshot,sourceCatalog:capture.sourceCatalog,targetCatalog:capture.sourceCatalog,
      targetUsers,sourceOwnerId:capture.sourceOwnerId,cloudPrimaryId:primary,aliasPublicId:String(alias),operationId:op,custodyKey:key,expectedSourceHmac:hmac,verifiedTargetObjects:proof});
    const excluded=[...Object.keys(capture.sourceCatalog),'private.collect_migration_actor_lineage','private.collect_imported_native_history','private.collect_migration_import_receipts','private.member_history_versions'];
    const beforeOther=await otherCounts(observer,excluded);
    const grouped=new Map();
    for(const cmd of plan.commands) {
      if(!capture.sourceCatalog[cmd.table]) continue;
      const columns=capture.sourceCatalog[cmd.table].columns.filter(x=>!x.generated).map(x=>x.name);
      const row=Object.fromEntries(columns.map((name,i)=>[name,cmd.params[i]]));
      if(!grouped.has(cmd.table))grouped.set(cmd.table,[]); grouped.get(cmd.table).push(stable(row));
    }
    let done=0;
    phase='transaction';
    await rehearseMaintenance(c,{operationId:op,fenceOperationId:fenceOp,epoch:'1',sourceSha256:src},async db=>{
      await db.query('INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES($1,$2,$3,$3)',[primary,String(cloudPublic),'2026-01-01T00:00:00.000Z']);
      for(const cmd of plan.commands){currentTable=cmd.table;if(cmd.context)await db.query("SELECT set_config('burimunsi.collection_id',$1,true)",[cmd.context.collectionId]);await db.query(cmd.sql,cmd.params);done++;completed=done;}
      await db.query(`INSERT INTO private.collect_migration_import_receipts(operation_id,source_actor_id,cloud_primary_id,snapshot_hmac,object_proof_hmac,counts)
        VALUES($1,$2,$3,$4,$5,$6)`,[op,capture.sourceOwnerId,primary,hmac,'b'.repeat(64),{objects:plan.summary.objects}]);
      phase='postimage';
    },async db=>{
      for(const [table,expected] of grouped){
        currentTable=table;
        const columns=capture.sourceCatalog[table].columns.filter(x=>!x.generated).map(x=>x.name);
        const sql='SELECT to_jsonb(r) AS value FROM (SELECT '+columns.map(x=>'"'+x+'"').join(',')+' FROM ONLY '+rel(table)+(table==='app.users'?' WHERE id<>$1':'')+') r';
        const actual=(await db.query(sql,table==='app.users'?[primary]:[])).rows.map(row=>stable(row.value)).sort();
        if(stable(actual)!==stable([...expected].sort())) return false;
      }
      currentTable='lineage_and_markers';
      const markers=await db.query('SELECT count(*)::int n FROM private.collect_imported_native_history');
      const actors=await db.query('SELECT envelope FROM private.collect_migration_actor_lineage');
      const originalUser=capture.snapshot.tables['app.users'].find(u=>u.id===capture.sourceOwnerId);
      const originalAccounts=capture.snapshot.tables['private.burimunsi_accounts'].filter(a=>a.principal_user_id===capture.sourceOwnerId);
      const originalVerified=actors.rowCount===1 && verifyActorLineage({envelope:actors.rows[0].envelope,operationId:op,
        sourceOwnerId:capture.sourceOwnerId,cloudPrimaryId:primary,custodyKey:key,originalUser,originalAccounts});
      const inactive=await db.query(`SELECT
        (SELECT count(*) FROM private.burimunsi_accounts WHERE active OR pin_hash<>'{}'::jsonb)::int accounts,
        (SELECT count(*) FROM private.burimunsi_device_grants WHERE active)::int grants,
        (SELECT count(*) FROM private.burimunsi_sessions WHERE NOT revoked OR pin_renewed_at IS NOT NULL OR pin_lease_expires_at IS NOT NULL)::int sessions`);
      const rebound=await db.query('SELECT count(*)::int n FROM private.burimunsi_accounts WHERE id=$1::uuid AND principal_user_id=$2 AND NOT active',[originalAccounts[0].id,primary]);
      const versions=await db.query('SELECT collection_id,revision::text FROM private.member_history_versions');
      const expectedVersions=capture.snapshot.tables['app.collections'].map(group=>({collection_id:group.id,revision:String(1+
        capture.snapshot.tables['app.memberships'].filter(m=>m.collection_id===group.id).length+
        capture.snapshot.tables['app.ledger_entries'].filter(e=>e.collection_id===group.id).length)}));
      return markers.rows[0].n===plan.summary.sms && originalVerified && rebound.rows[0].n===1 &&
        inactive.rows[0].accounts===0 && inactive.rows[0].grants===0 && inactive.rows[0].sessions===0 &&
        stable(versions.rows.map(stable).sort())===stable(expectedVersions.map(stable).sort());
    });
    assert.equal(done,plan.commands.length);
    assert.equal(plan.summary.missingObjectProofCount,0);
    phase='side_effects';
    const afterOther=await otherCounts(observer,excluded);
    const changed=Object.keys({...beforeOther,...afterOther}).filter(name=>beforeOther[name]!==afterOther[name]);
    if(changed.length) { currentTable=changed.join(','); throw Error('unexpected_side_effects'); }
  } catch(error) {
    // Database exceptions can contain source row values. Emit only safe codes
    // and schema object names, never query parameters, details or row bodies.
    const safeMessage=(error.message??'').match(/^(?:permission denied for (?:table|schema|function) [a-z_]+|new row violates row-level security policy for table "[a-z_]+"|[a-z_]{2,100})$/)?.[0]??'';
    const functions=[...(error.where??'').matchAll(/PL\/pgSQL function ([a-z0-9_.]+)\(/g)].map(x=>x[1]).join(',');
    const words=(error.message??'').split(/[^a-z_]+/i).filter(x=>['permission','denied','relation','table','schema','function','security','policy','role','insert','select','execute','postgres','runtime','row','new'].includes(x.toLowerCase())).join('_');
    throw Error(['graph_rehearsal_failed',phase,currentTable,completed,error.code??'unknown',error.schema??'',error.table??'',error.constraint??'',safeMessage,functions,words].join(':'));
  } finally { key.fill(0); await observer?.end().catch(()=>{}); await c?.end().catch(()=>{}); await bootstrap.end().catch(()=>{}); await f.close(); }
});
