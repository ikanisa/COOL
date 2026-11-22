// Private in-memory graph handling. The caller owns the transaction and must
// arrange a fenced, exclusively locked target with the owner-only policies.
import {GRAPH,compileTransfer,sourceSnapshotHmac,verifyActorLineage} from './compile.mjs';
import {TARGET_CATALOGUE_SQL} from './graph-catalogue.mjs';

const stable=x=>Array.isArray(x)?'['+x.map(stable).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+stable(x[k])).join(',')+'}':JSON.stringify(x);
const relation=name=>name.split('.').map(x=>'"'+x+'"').join('.');
const columns=cat=>cat.columns.filter(c=>!c.generated).map(c=>c.name);
const selection=cat=>columns(cat).map(name=>'"'+name+'"').join(',');
const preservedStorage=new Set(['private.storage_put_intents','private.storage_upload_attempts','private.storage_objects']);
async function rows(db,table,cat){
 const q=await db.query(`SELECT to_jsonb(r) value FROM (SELECT ${selection(cat)} FROM ONLY ${relation(table)} LIMIT 257) r`);
 if(q.rowCount>256)throw Error('target_graph_row_limit');
 return q.rows.map(x=>x.value);
}
export function validateExistingStorage(baseline,capture,targetCatalog){
 // Preserve the already-committed independent Cloud Storage journals. An
 // overlapping object or operation is never guessed to be the same history.
 for(const table of preservedStorage) for(const field of ['id','operation_id','object_key']){
  if(!targetCatalog[table].columns.some(c=>c.name===field))continue;
  const source=new Set(capture.snapshot.tables[table].map(r=>r[field]).filter(x=>x!=null));
  if(baseline[table].some(r=>r[field]!=null&&source.has(r[field])))throw Error('existing_storage_identifier_overlap');
 }
 const puts=baseline['private.storage_put_intents'],attempts=baseline['private.storage_upload_attempts'],objects=baseline['private.storage_objects'];
 const putsByOp=new Map(puts.map(p=>[p.operation_id,p]));
 if(putsByOp.size!==puts.length || objects.length!==puts.length || attempts.length!==puts.length ||
   new Set(objects.map(o=>o.operation_id)).size!==objects.length || new Set(attempts.map(a=>a.operation_id)).size!==attempts.length ||
   puts.some(p=>p.state!=='committed'||p.active_attempt!==null||p.upload_unresolved!==false||p.delete_tombstone!==false) ||
   objects.some(o=>{const p=putsByOp.get(o.operation_id);return !p||p.object_key!==o.object_key||p.fingerprint!==o.fingerprint||
     p.sha256!==o.sha256||String(p.size)!==String(o.size)||stable(p.scope)!==stable(o.scope)||typeof o.etag!=='string'||!o.etag;}) ||
   attempts.some(a=>!putsByOp.has(a.operation_id)||a.completed_at===null))throw Error('existing_storage_journal_unqualified');
 return true;
}

export async function insertGraph(db,{capture,key,operationId,cloudPrimaryId,proof,proofHmac}){
 const catalog=await db.query(TARGET_CATALOGUE_SQL);
 if(catalog.rowCount!==1 || Number(catalog.rows[0].missing)!==0)throw Error('target_graph_catalogue_incomplete');
 const targetCatalog=catalog.rows[0].catalogue;
 const baseline={};
 for(const table of GRAPH){
  baseline[table]=await rows(db,table,targetCatalog[table]);
  if(table!=='app.users' && !preservedStorage.has(table) && baseline[table].length)throw Error('target_business_graph_not_empty');
 }
 validateExistingStorage(baseline,capture,targetCatalog);
 const existing=baseline['app.users'];
 const used=new Set([...existing,...capture.snapshot.tables['app.users']].map(x=>x.public_id));
 let alias=100000;while(alias<=999999&&used.has(String(alias)))alias++;
 if(alias>999999)throw Error('alias_public_id_unavailable');
 const hmac=sourceSnapshotHmac(capture.snapshot,key,operationId);
 const plan=compileTransfer({snapshot:capture.snapshot,sourceCatalog:capture.sourceCatalog,targetCatalog,
  targetUsers:existing,sourceOwnerId:capture.sourceOwnerId,cloudPrimaryId,aliasPublicId:String(alias),operationId,
  custodyKey:key,expectedSourceHmac:hmac,verifiedTargetObjects:proof});
 if(plan.summary.externalDependencyCount || plan.summary.missingObjectProofCount ||
    Object.keys(proof).length!==plan.summary.objects)throw Error('import_graph_or_object_proof_incomplete');
 const expected=Object.fromEntries(GRAPH.map(t=>[t,baseline[t].map(stable)]));
 for(const cmd of plan.commands){
  if(targetCatalog[cmd.table]){
   const names=columns(targetCatalog[cmd.table]);
   expected[cmd.table].push(stable(Object.fromEntries(names.map((n,i)=>[n,cmd.params[i]]))));
  }
  if(cmd.context)await db.query("SELECT set_config('burimunsi.collection_id',$1,true)",[cmd.context.collectionId]);
  await db.query(cmd.sql,cmd.params);
 }
 const counts={sms:plan.summary.sms,evidence:plan.summary.evidence,payments:plan.summary.payments,
  ledgerEntries:plan.summary.ledgerEntries,objects:plan.summary.objects,commands:plan.summary.commandCount};
 await db.query(`INSERT INTO private.collect_migration_import_receipts
  (operation_id,source_actor_id,cloud_primary_id,snapshot_hmac,object_proof_hmac,counts) VALUES($1,$2,$3,$4,$5,$6)`,
  [operationId,capture.sourceOwnerId,cloudPrimaryId,hmac,proofHmac,counts]);
 return {plan,expected,targetCatalog,counts,hmac,cloudPrimaryId};
}

export async function verifyGraph(db,{capture,key,operationId,proofHmac,inserted}){
 for(const table of GRAPH){
  const actual=(await rows(db,table,inserted.targetCatalog[table])).map(stable).sort();
  if(stable(actual)!==stable([...inserted.expected[table]].sort())) {
    const expected=inserted.expected[table].map(JSON.parse),received=actual.map(JSON.parse);
    const changed=columns(inserted.targetCatalog[table]).filter(k=>stable(expected.map(x=>stable(x[k])).sort())!==stable(received.map(x=>stable(x[k])).sort()));
    throw Error('import_graph_postimage_mismatch:'+table+':'+changed.join(','));
  }
 }
 const actors=await db.query('SELECT source_actor_id,cloud_primary_id,operation_id::text,snapshot_hmac,envelope FROM private.collect_migration_actor_lineage');
 const old=capture.snapshot.tables['app.users'].find(u=>u.id===capture.sourceOwnerId);
 const accounts=capture.snapshot.tables['private.burimunsi_accounts'].filter(a=>a.principal_user_id===capture.sourceOwnerId);
 const a=actors.rows[0];
 if(actors.rowCount!==1 || a.source_actor_id!==capture.sourceOwnerId || a.cloud_primary_id!==inserted.cloudPrimaryId ||
    a.operation_id!==operationId || a.snapshot_hmac!==inserted.hmac ||
    !verifyActorLineage({envelope:a.envelope,operationId,sourceOwnerId:capture.sourceOwnerId,
      cloudPrimaryId:inserted.cloudPrimaryId,custodyKey:key,originalUser:old,originalAccounts:accounts}))throw Error('actor_lineage_postimage_mismatch');
 const markers=await db.query('SELECT count(*)::int n FROM private.collect_imported_native_history WHERE operation_id=$1',[operationId]);
 if(markers.rows[0]?.n!==inserted.counts.sms)throw Error('historical_marker_count_mismatch');
 const receipt=await db.query(`SELECT source_actor_id,cloud_primary_id,snapshot_hmac,object_proof_hmac,counts
  FROM private.collect_migration_import_receipts WHERE operation_id=$1`,[operationId]);
 const r=receipt.rows[0];
 if(receipt.rowCount!==1 || r.source_actor_id!==capture.sourceOwnerId || r.cloud_primary_id!==inserted.cloudPrimaryId ||
  r.snapshot_hmac!==inserted.hmac || r.object_proof_hmac!==proofHmac || stable(r.counts)!==stable(inserted.counts))throw Error('import_receipt_postimage_mismatch');
 return true;
}
