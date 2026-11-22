// Owner-only fenced import transaction. The original rehearsal entrypoint
// remains fixture-only. Managed execution has a separate exact-peer gate.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {GRAPH} from './compile.mjs';
import {isManagedReconciliationPeer} from '../current-pg-transfer/managed-target.mjs';
import {applyInitialBootstrapInFencedTransaction} from '../cloud-release/initial-account-bootstrap.mjs';

const EXPECTED_GUARD = '99fd575d0ddec31880cbe351e46514a34031c863d9be0d4ac06384c414b98df8';
const ANCHOR = "  IF c.mode<>'open' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';END IF;";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[a-f0-9]{64}$/;
const EXTRA = 'private.burimunsi_native_financial_work';
const NAMESPACE = 'private.storage_namespace';
const BOOTSTRAP_RELATIONS = Object.freeze(['private.burimunsi_operator_approvals',
  'private.burimunsi_native_staff_delegations','app.audit_log']);
const EXPECTED_SCRIPTS = Object.freeze({
  lineage:'c20b8a8a0ae13498c285643ea8f284cf55c720ed5ba955048aebd48f988fae5c',
  retention:'2077420a50acf0922626cbfd09f994f39c13a4cd56c5eda31ca8136eda066b75',
  guard:'25010ae47b0b964961e4e24fcf51600c097d661f2c2a1c32f9d5a169b783bf85',
  read:'918821b4f6707c7d807245600f2d92b81f37072cc0a9948dc23ec5a49258f3f1',
});
const rel = name => {
  if (!(GRAPH.includes(name) || name===EXTRA || name===NAMESPACE || BOOTSTRAP_RELATIONS.includes(name)) || !/^(app|private)\.[a-z_][a-z0-9_]*$/.test(name)) throw Error('maintenance_relation_refused');
  return name.split('.').map(part => '"' + part + '"').join('.');
};
const sha = text => createHash('sha256').update(text).digest('hex');
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
function fixtureOnly(client) {
  const cp = client?.connectionParameters;
  if (!cp || cp.user !== 'postgres' || !(cp.database === 'collect_transfer_schema_fixture' || /^collect_archive_[a-f0-9]{24}_test$/.test(cp.database ?? '')) ||
      typeof cp.host !== 'string' || !/^\/private\/tmp\/collect-pg-transfer-[^/]+\/s$/.test(cp.host)) throw Error('managed_execution_closed');
}
function input(x) {
  if (!x || !UUID.test(x.operationId ?? '') || !UUID.test(x.fenceOperationId ?? '') ||
      !/^[1-9][0-9]{0,15}$/.test(x.epoch ?? '') || !HASH.test(x.sourceSha256 ?? '')) throw Error('maintenance_identity_invalid');
}
function predicate(x) {
  return `(session_user='postgres' AND current_user='postgres' AND current_setting('collect.graph_import_operation',true)='${x.operationId}' AND EXISTS(SELECT 1 FROM private.collect_fence_control fence_row WHERE fence_row.singleton AND fence_row.mode='fenced' AND fence_row.epoch=${x.epoch} AND fence_row.operation_id='${x.fenceOperationId}'::uuid AND fence_row.source_sha256='${x.sourceSha256}'))`;
}
function override(original, x) {
  if (sha(original) !== EXPECTED_GUARD || original.split(ANCHOR).length !== 2) throw Error('fence_guard_preimage_changed');
  const lock = "EXISTS(SELECT 1 FROM pg_catalog.pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory' AND database=(SELECT oid FROM pg_database WHERE datname=current_database()) AND classid=7346371::oid AND objid=2::oid AND objsubid=2 AND mode='ExclusiveLock' AND granted)";
  const replacement = `  IF c.mode<>'open' THEN\n   IF ${predicate(x)} AND ${lock} THEN RETURN jsonb_build_object('contractVersion',1,'mode',c.mode,'epoch',c.epoch); END IF;\n   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';\n  END IF;`;
  return original.replace(ANCHOR,replacement);
}
async function guardDefinition(client) {
  const q=await client.query(`SELECT pg_get_functiondef(p.oid) AS definition,p.proacl::text AS acl,
    pg_get_userbyid(p.proowner) AS owner,p.prosecdef AS definer,p.proconfig::text AS config
    FROM pg_proc p WHERE p.oid=to_regprocedure('private.collect_fence_assert_write(uuid,bigint,text)')`);
  if (q.rowCount !== 1) throw Error('fence_guard_unavailable');
  return q.rows[0];
}
async function policies(client, names=GRAPH) {
  const q=await client.query(`SELECT n.nspname||'.'||c.relname AS name,c.relrowsecurity AS rls,c.relforcerowsecurity AS forced,
    c.relacl::text AS acl,pg_get_userbyid(c.relowner) AS owner,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'roles',p.polroles::text,
      'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname)
      FROM pg_policy p WHERE p.polrelid=c.oid),'[]'::jsonb) AS policies,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid),
      'function',pg_get_functiondef(t.tgfoid)) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'[]'::jsonb) AS triggers
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname||'.'||c.relname=ANY($1::text[]) ORDER BY 1`,[names]);
  if (q.rowCount !== names.length) throw Error('target_graph_catalogue_incomplete');
  return q.rows;
}

const guardRelations = Object.freeze({
  'private.burimunsi_auto_sms_jobs':'collect_imported_native_history_write_guard',
  'private.burimunsi_native_financial_work':'collect_imported_native_history_write_guard',
  'app.momo_financial_links':'collect_imported_native_history_link_guard',
  'app.ledger_entries':'collect_imported_native_history_ledger_guard',
});
function unchangedWithNewGuards(before,after) {
  const a=structuredClone(after);
  for (const row of a) {
    const expected=guardRelations[row.name];
    const found=row.triggers.filter(t=>t.name==='collect_imported_native_history_guard');
    if (expected) {
      if (found.length!==1 || found[0].enabled!=='A' ||
          !found[0].definition.includes('EXECUTE FUNCTION private.'+expected+'()') ||
          !found[0].function.includes('FUNCTION private.'+expected+'(')) return false;
      row.triggers=row.triggers.filter(t=>t.name!=='collect_imported_native_history_guard');
    } else if (found.length) return false;
  }
  return same(before,a);
}

async function scripts() {
  const out={};
  for (const [name,url] of Object.entries({lineage:new URL('./lineage.sql',import.meta.url),
    retention:new URL('../cloud-release/imported-retention.sql',import.meta.url),
    guard:new URL('../cloud-release/imported-history-guard.sql',import.meta.url),
    read:new URL('../cloud-release/imported-history-read.sql',import.meta.url)})) {
    const value=await readFile(url,'utf8');
    if (sha(value)!==EXPECTED_SCRIPTS[name]) throw Error('reviewed_import_script_changed');
    out[name]=value;
  }
  out.migration=await readFile(new URL('../../../supabase/migrations/20261117071343_collect_burimunsi_import_lineage_guard.sql',import.meta.url),'utf8');
  if(out.migration!==[out.lineage,out.retention,out.guard,out.read].join('\n'))throw Error('import_migration_source_changed');
  return out;
}

const PATCHED_FUNCTIONS=[
 'private.burimunsi_auto_snapshot(text)','private.burimunsi_auto_candidates(text)',
 'private.burimunsi_native_work_candidates(uuid,integer)','private.burimunsi_native_sms_post_candidates(integer)',
 'private.burimunsi_observation_history_rows(text)','private.burimunsi_auto_projection(text)'];
async function patchedFunctionSecurity(client) {
  const r=await client.query(`SELECT p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,
    p.proacl::text acl,p.prosecdef definer,p.proconfig::text config FROM pg_proc p
    WHERE p.oid=ANY(ARRAY(SELECT to_regprocedure(x) FROM unnest($1::text[]) x)) ORDER BY 1`,[PATCHED_FUNCTIONS]);
  if(r.rowCount!==PATCHED_FUNCTIONS.length) throw Error('history_function_set_missing');
  return r.rows;
}
async function history(client) {
  return (await client.query(`SELECT version,name,encode(sha256(convert_to(statements[1],'UTF8')),'hex') hash,
    cardinality(statements)::int entries FROM supabase_migrations.schema_migrations ORDER BY version`)).rows;
}

/** Execute a guarded rehearsal on an owned fixture only. `body` is trusted
 * test code. It must compare every transformed postimage before returning.
 * A failed deferred check, body, restore or policy/ACL comparison rolls back.
 */
async function run(client, identity, body, verify, install, bootstrap=false) {
  input(identity); if (typeof body !== 'function' || typeof verify !== 'function') throw Error('maintenance_body_required');
  const reviewed=install?await scripts():null;
  let begun=false, commitAttempted=false;
  try {
    await client.query('BEGIN ISOLATION LEVEL READ COMMITTED'); begun=true;
    await client.query("SET LOCAL TIME ZONE 'UTC'");
    await client.query("SET LOCAL lock_timeout='3s'"); await client.query("SET LOCAL statement_timeout='60s'");
    const session=await client.query("SELECT session_user AS session_user,current_user AS current_user,current_setting('role') AS role,current_setting('row_security') AS row_security");
    if (session.rows[0]?.session_user !== 'postgres' || session.rows[0]?.current_user !== 'postgres' || session.rows[0]?.role !== 'none' || session.rows[0]?.row_security !== 'on') throw Error('maintenance_owner_required');
    if (install) {
      await client.query('SELECT pg_advisory_xact_lock(7346371,11)');
      await client.query('LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE');
    }
    await client.query('SELECT pg_advisory_xact_lock(7346371,1)');
    await client.query('SELECT pg_advisory_xact_lock(7346371,2)');
    const names=install?[...GRAPH,EXTRA,NAMESPACE]:bootstrap?[...GRAPH,...BOOTSTRAP_RELATIONS]:[...GRAPH];
    await client.query('LOCK TABLE ' + names.sort().map(rel).join(',') + ' IN ACCESS EXCLUSIVE MODE');
    const fence=await client.query("SELECT mode,epoch::text,operation_id::text,source_sha256 FROM private.collect_fence_control WHERE singleton FOR UPDATE");
    const v=fence.rows[0];
    if (fence.rowCount !== 1 || v.mode !== 'fenced' || v.epoch !== identity.epoch || v.operation_id !== identity.fenceOperationId || v.source_sha256 !== identity.sourceSha256) throw Error('target_fence_changed');
    const active=await client.query(`SELECT count(*)::int n FROM private.collect_fence_admissions a
      WHERE a.state IN('active','unresolved') AND private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind) IS NOT TRUE`);
    if (active.rows[0]?.n !== 0) throw Error('target_admissions_active');
    const beforeGuard=await guardDefinition(client), beforePolicies=await policies(client,names);
    const beforeFunctions=install?await patchedFunctionSecurity(client):null;
    const beforeHistory=install?await history(client):null;
    if(install && beforeHistory.some(x=>x.version==='20261117071343'))throw Error('import_migration_already_recorded');
    if (beforeGuard.owner !== 'postgres' || beforeGuard.definer !== true) throw Error('fence_guard_owner_changed');
    const patched=override(beforeGuard.definition,identity);
    if (beforePolicies.some(row => row.policies.some(policy => policy.name === 'collect_transfer_maintenance'))) throw Error('maintenance_policy_exists');
    if (install) { await client.query(reviewed.lineage); await client.query(reviewed.retention); }
    await client.query("SELECT set_config('collect.graph_import_operation',$1,true)",[identity.operationId]);
    await client.query(patched);
    const condition=predicate(identity);
    for (const row of beforePolicies) if (row.rls && (GRAPH.includes(row.name)||(install&&row.name===NAMESPACE)||(bootstrap&&BOOTSTRAP_RELATIONS.includes(row.name)))) await client.query(`CREATE POLICY collect_transfer_maintenance ON ${rel(row.name)} TO postgres USING ${condition} WITH CHECK ${condition}`);
    if(install){
      const n=await client.query('SELECT singleton,origin,bucket FROM private.storage_namespace FOR UPDATE');
      if(n.rowCount===0)await client.query(`INSERT INTO private.storage_namespace(singleton,origin,bucket)
        VALUES(true,'https://rrlduytparvsjfmegalh.supabase.co','collect-evidence')`);
      else if(n.rowCount!==1||n.rows[0].singleton!==true||n.rows[0].origin!=='https://rrlduytparvsjfmegalh.supabase.co'||
        n.rows[0].bucket!=='collect-evidence')throw Error('storage_namespace_conflict');
    }
    await client.query('SET CONSTRAINTS ALL DEFERRED');
    await body(client);
    // Fire the actual deferred origin/receipt/marker constraints while the
    // narrowly framed owner policy still exists. PostgreSQL refuses to add a
    // guard trigger while there are pending deferred trigger events.
    await client.query('SET CONSTRAINTS ALL IMMEDIATE');
    if (install) { await client.query(reviewed.guard); await client.query(reviewed.read); }
    if (await verify(client) !== true) throw Error('postimage_unconfirmed');
    if(install){
      const namespace=await client.query(`SELECT count(*)::int n FROM private.storage_namespace WHERE singleton
        AND origin='https://rrlduytparvsjfmegalh.supabase.co' AND bucket='collect-evidence'`);
      if(namespace.rows[0]?.n!==1)throw Error('storage_namespace_postimage_mismatch');
      const catalog=(await client.query('SELECT private._retention_manifest_catalog_v2() value')).rows[0]?.value;
      for(const name of ['private:collect_migration_actor_lineage','private:collect_imported_native_history','private:collect_migration_import_receipts'])
        if(catalog?.private_classes?.filter(x=>x.name===name&&x.blocked===true).length!==1)throw Error('import_retention_catalog_mismatch');
      await client.query('SELECT private._retention_manifest_schema_v2()');
      await client.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',
        ['20261117071343','collect_burimunsi_import_lineage_guard',[reviewed.migration]]);
      const expected=[...beforeHistory,{version:'20261117071343',name:'collect_burimunsi_import_lineage_guard',
        hash:sha(reviewed.migration),entries:1}].sort((a,b)=>a.version.localeCompare(b.version));
      if(!same(expected,await history(client)))throw Error('import_migration_history_mismatch');
    }
    for (const row of beforePolicies) if (row.rls && (GRAPH.includes(row.name)||(install&&row.name===NAMESPACE)||(bootstrap&&BOOTSTRAP_RELATIONS.includes(row.name)))) await client.query(`DROP POLICY collect_transfer_maintenance ON ${rel(row.name)}`);
    await client.query(beforeGuard.definition);
    const after=await policies(client,names);
    if (!same(beforeGuard,await guardDefinition(client)) ||
      !(install?unchangedWithNewGuards(beforePolicies,after):same(beforePolicies,after)) ||
      (install&&!same(beforeFunctions,await patchedFunctionSecurity(client)))) throw Error('maintenance_restore_mismatch');
    commitAttempted=true; await client.query('COMMIT'); begun=false;
    return {guardAndPoliciesRestored:true,historyGuardInstalled:install};
  } catch (error) {
    if (begun&&!commitAttempted) {
      try { await client.query('ROLLBACK'); error.outcome='rolled_back'; }
      catch { error.outcome='rollback_requires_reconciliation'; }
    }
    if (commitAttempted) error.outcome='commit_requires_reconciliation';
    throw error;
  }
}

export async function rehearseMaintenance(client, identity, body, verify) {
  fixtureOnly(client); return {...await run(client,identity,body,verify,false),fixtureOnly:true};
}

export async function rehearseManagedShapeMaintenance(client, identity, body, verify) {
  fixtureOnly(client); return {...await run(client,identity,body,verify,true),fixtureOnly:true};
}

export async function executeManagedMaintenance(client, identity, body, verify) {
  if (!isManagedReconciliationPeer(client?.connectionParameters,client?.connection?.stream)) throw Error('managed_peer_refused');
  return run(client,identity,body,verify,true);
}

async function verifyBootstrap(client,prepared){
 const p=prepared.row();
 const q=await client.query(`SELECT
  (SELECT count(*) FROM private.burimunsi_accounts WHERE id=$1 AND collection_id=$3 AND principal_user_id=$4
    AND role='admin' AND active AND NOT removed AND pin_hash=$5::jsonb)::int AS admin_account,
  (SELECT count(*) FROM private.burimunsi_accounts WHERE id=$2 AND collection_id=$3 AND role='staff'
    AND active AND NOT removed AND pin_hash=$6::jsonb)::int AS staff_account,
  (SELECT count(*) FROM private.burimunsi_operator_approvals WHERE collection_id=$3 AND principal_user_id=$4 AND phone=$7 AND active)::int AS approval,
  (SELECT count(*) FROM private.burimunsi_native_staff_delegations d JOIN private.burimunsi_accounts a
    ON a.principal_user_id=d.principal_user_id AND a.collection_id=d.collection_id WHERE a.id=$2
    AND d.collection_id=$3 AND d.parent_account_id=$1 AND d.active)::int AS delegation,
  (SELECT count(*) FROM app.audit_log WHERE action='burimunsi.migration.initial_accounts'
    AND request_id=$8 AND actor_user_id=$4 AND actor_session_id IS NULL)::int AS audit,
  (SELECT count(*) FROM private.burimunsi_sessions WHERE collection_id=$3 AND account_id IN($1,$2) AND NOT revoked)::int AS sessions,
  (SELECT count(*) FROM private.burimunsi_device_accounts da JOIN private.burimunsi_device_grants d ON d.id=da.grant_id
    WHERE da.collection_id=$3 AND da.account_id IN($1,$2) AND d.active)::int AS grants`,
  [p.adminAccountId,p.staffAccountId,p.collectionId,p.ownerPrincipalId,JSON.stringify(p.adminPinHash),JSON.stringify(p.staffPinHash),p.adminPhone,p.operationId]);
 const r=q.rows[0];return q.rowCount===1 && r.admin_account===1 && r.staff_account===1 && r.approval===1 && r.delegation===1 && r.audit===1 && r.sessions===0 && r.grants===0;
}

export async function rehearseBootstrapMaintenance(client,identity,prepared){
 fixtureOnly(client);
 return {...await run(client,identity,db=>applyInitialBootstrapInFencedTransaction(db,prepared),db=>verifyBootstrap(db,prepared),false,true),fixtureOnly:true};
}

export async function executeManagedBootstrapMaintenance(client,identity,prepared){
 if(!isManagedReconciliationPeer(client?.connectionParameters,client?.connection?.stream))throw Error('managed_peer_refused');
 return run(client,identity,db=>applyInitialBootstrapInFencedTransaction(db,prepared),db=>verifyBootstrap(db,prepared),false,true);
}
