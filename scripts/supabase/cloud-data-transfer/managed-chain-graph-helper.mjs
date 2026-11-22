// Use actual managed schema defaults in the disposable database. The source
// rows are rolled back before exercising the import and its postimage checks.
import {randomBytes,randomUUID} from 'node:crypto';
import {GRAPH} from './compile.mjs';
import {TARGET_CATALOGUE_SQL} from './graph-catalogue.mjs';
import {insertGraph,verifyGraph} from './graph-transaction.mjs';
import {rehearseManagedShapeMaintenance} from './maintenance.mjs';

async function captureSyntheticGraph(db){
 const tables=Object.fromEntries(GRAPH.map(name=>[name,[]]));
 const {rows:[catalog]}=await db.query(TARGET_CATALOGUE_SQL);
 if(!catalog||Number(catalog.missing)!==0)throw Error('synthetic_graph_catalogue_incomplete');
 const at='2026-01-01T00:00:00.000Z',sourceOwnerId='synthetic-original-owner',group='synthetic-recovery-group',wallet='synthetic-wallet';
 await db.query('SAVEPOINT collect_synthetic_source');
 try{
  tables['app.users']=(await db.query(`INSERT INTO app.users AS record(id,public_id,created_at,updated_at)
   VALUES($1,'123456',$2,$2) RETURNING to_jsonb(record) AS value`,[sourceOwnerId,at])).rows.map(r=>r.value);
  tables['app.collections']=(await db.query(`INSERT INTO app.collections AS record(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
   VALUES($1,$1,$2,'Synthetic recovery group','community',$3,$3) RETURNING to_jsonb(record) AS value`,[group,sourceOwnerId,at])).rows.map(r=>r.value);
  tables['app.momo_receiving_accounts']=(await db.query(`INSERT INTO app.momo_receiving_accounts AS record(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at)
   VALUES($1,'mtn_momo','123456','Synthetic receiver',$2,'Africa/Kigali',$3) RETURNING to_jsonb(record) AS value`,[wallet,'c'.repeat(64),at])).rows.map(r=>r.value);
  await db.query("SELECT set_config('burimunsi.collection_id',$1,true)",[group]);
  tables['private.burimunsi_scopes']=(await db.query(`INSERT INTO private.burimunsi_scopes AS record(collection_id,receiving_account_id,created_at)
   VALUES($1,$2,1) RETURNING to_jsonb(record) AS value`,[group,wallet])).rows.map(r=>r.value);
  tables['private.burimunsi_accounts']=(await db.query(`INSERT INTO private.burimunsi_accounts AS record
   (id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,active,created_at,updated_at)
   VALUES($1,$2,$3,'+250780000001','Synthetic original owner','admin',ARRAY['records.read'],'{}',false,1,1)
   RETURNING to_jsonb(record) AS value`,[randomUUID(),group,sourceOwnerId])).rows.map(r=>r.value);
 }finally{await db.query('ROLLBACK TO SAVEPOINT collect_synthetic_source');await db.query('RELEASE SAVEPOINT collect_synthetic_source');}
 return {snapshot:{tables},sourceCatalog:catalog.catalogue,sourceOwnerId};
}

export async function exerciseManagedChainGraph(owner){
 const key=randomBytes(32),operationId=randomUUID(),proofHmac='b'.repeat(64);
 const fence=(await owner.query('SELECT operation_id::text,epoch::text,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 let capture,inserted;
 try{
  await rehearseManagedShapeMaintenance(owner,{operationId,fenceOperationId:fence.operation_id,epoch:fence.epoch,sourceSha256:fence.source_sha256},
   async db=>{capture=await captureSyntheticGraph(db);inserted=await insertGraph(db,{capture,key,operationId,cloudPrimaryId:'synthetic-primary',proof:{},proofHmac});},
   async db=>verifyGraph(db,{capture,key,operationId,proofHmac,inserted}));
  return {commands:inserted.plan.summary.commandCount,objects:inserted.counts.objects,sms:inserted.counts.sms};
 }finally{key.fill(0);}
}
