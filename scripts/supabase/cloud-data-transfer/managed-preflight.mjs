// Read-only eligibility check: no target or source writes, no private rows
// printed or persisted. A successful check is not an import or a release.
import {randomBytes,randomUUID} from 'node:crypto';
import {readFileSync,lstatSync} from 'node:fs';
import {connect,ROOT,PROJECT} from '../cloud-release/access.mjs';
import {isManagedReconciliationPeer} from '../current-pg-transfer/managed-target.mjs';
import {captureLocalSource,TARGET_CATALOGUE_SQL} from './source-reader.mjs';
import {compileTransfer,sourceSnapshotHmac} from './compile.mjs';
const key=randomBytes(32);let db;
try{
 const capture=captureLocalSource();
 if(capture.fenceMode!=='fenced'||capture.effectiveActiveAdmissions!==0)throw Error('source_not_fully_fenced');
 const path=ROOT+'/verified-application-objects.json',s=lstatSync(path);
 if(!s.isFile()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size>4*1024*1024)throw Error('private_object_proof_required');
 const proof=JSON.parse(readFileSync(path,'utf8'));
 db=await connect();
 if(!isManagedReconciliationPeer(db.connectionParameters,db.connection?.stream))throw Error('managed_peer_refused');
 await db.query('BEGIN READ ONLY');
 await db.query("SET LOCAL TIME ZONE 'UTC'");
 const control=await db.query(`SELECT mode,project_ref FROM private.collect_fence_control WHERE singleton`);
 if(control.rowCount!==1||control.rows[0].mode!=='fenced'||control.rows[0].project_ref!==PROJECT)throw Error('target_not_fenced');
 const active=await db.query(`SELECT count(*)::int n FROM private.collect_fence_admissions a
  WHERE a.state IN('active','unresolved') AND private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind) IS NOT TRUE`);
 if(active.rows[0].n!==0)throw Error('target_admissions_active');
 const owners=await db.query(`SELECT i.principal_user_id FROM private.collect_owner_identity i
  JOIN app.admin_users a ON a.id=i.admin_user_id AND a.role='owner' AND a.status='active' AND a.email=i.owner_email
  JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=i.principal_user_id
  JOIN app.users u ON u.id=i.principal_user_id AND u.access_status='active'
  JOIN private.auth_principal_links p ON p.user_id=u.id
  JOIN auth.users actual ON actual.id=p.auth_user_id AND lower(actual.email)=a.email AND actual.email_confirmed_at IS NOT NULL
  WHERE i.singleton`);
 if(owners.rowCount!==1)throw Error('verified_cloud_owner_required');
 const catalogue=await db.query(TARGET_CATALOGUE_SQL);
 if(catalogue.rowCount!==1||Number(catalogue.rows[0].missing)!==0)throw Error('target_graph_catalogue_incomplete');
 const users=(await db.query('SELECT id,phone,email,public_id FROM app.users')).rows;
 const used=new Set([...users,...capture.snapshot.tables['app.users']].map(x=>x.public_id));let alias=100000;while(alias<=999999&&used.has(String(alias)))alias++;
 if(alias>999999)throw Error('alias_public_id_unavailable');
 const op=randomUUID(),hmac=sourceSnapshotHmac(capture.snapshot,key,op);
 const plan=compileTransfer({snapshot:capture.snapshot,sourceCatalog:capture.sourceCatalog,targetCatalog:catalogue.rows[0].catalogue,
  targetUsers:users,sourceOwnerId:capture.sourceOwnerId,cloudPrimaryId:owners.rows[0].principal_user_id,aliasPublicId:String(alias),
  operationId:op,custodyKey:key,expectedSourceHmac:hmac,verifiedTargetObjects:proof});
 if(plan.summary.externalDependencyCount||plan.summary.missingObjectProofCount||Object.keys(proof).length!==plan.summary.objects)throw Error('import_graph_or_object_proof_incomplete');
 await db.query('ROLLBACK');
 console.log(JSON.stringify({status:'read_only_preflight_passed',sourceFenced:true,targetFenced:true,
  effectiveActiveAdmissions:0,commands:plan.summary.commandCount,objects:plan.summary.objects,sms:plan.summary.sms,
  payments:plan.summary.payments,productionWrites:false}));
}catch(e){
 const code=typeof e.code==='string'&&/^[A-Z0-9]{5}$/.test(e.code)?e.code:
  typeof e.message==='string'&&/^[a-z][a-z0-9_]{1,95}$/.test(e.message)?e.message:'preflight_failed';
 console.error(JSON.stringify({status:'read_only_preflight_failed',code,productionWrites:false}));process.exitCode=1;
}finally{key.fill(0);await db?.query('ROLLBACK').catch(()=>{});await db?.end().catch(()=>{});}
