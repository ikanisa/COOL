import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {test} from 'node:test';
import {createHash,randomUUID} from 'node:crypto';
import {operationInventory,publicRpcNames,dispatchOperation} from '../src/operations.js';
import {buildManifest,assertManifestMetadata} from '../scripts/operation_inventory.mjs';
import {fixture} from './support/auth_fixture.mjs';

const currentManifest=()=>buildManifest({profile:'auth17_candidate'});
async function sealedMomo15(){
 const raw=await readFile(new URL('../operations-manifest-momo15.json',import.meta.url));
 assert.equal(createHash('sha256').update(raw).digest('hex'),'ad11e18f723b8f0bf9bf6c98aa9b59fb71b55629cedc45ac42502112730dc258');
 const manifest=JSON.parse(raw);assert.equal(assertManifestMetadata(manifest,{profile:'momo15_candidate'}),true);return manifest;
}

test('explicit Auth17 source inventory matches the actual current dispatcher,52 sources and17 migrations',async()=>{
  const recorded=JSON.parse(await readFile(new URL('../operations-manifest-auth17.json',import.meta.url),'utf8'));
  assert.deepEqual(recorded,await currentManifest());
  assert.equal(recorded.profile,'auth17_candidate');assert.equal(recorded.metadata_version,3);
  assert.equal(recorded.configuration_source,'wrangler.auth17-source.jsonc');
  const configRaw=await readFile(new URL('../'+recorded.configuration_source,import.meta.url)),config=JSON.parse(configRaw);
  assert.equal(createHash('sha256').update(configRaw).digest('hex'),'1fa3792055ebeb9d14f09563cdc6b30afc127086ee7ebcb2dd482391f2702d40');
  assert.equal(config.ai,undefined);assert.equal(config.triggers,undefined);assert.equal(config.vars.MOMO_PROCESSING_PAUSED,'true');assert.equal(config.vars.GOOGLE_AUTH_ENABLED,'false');assert.equal(Object.hasOwn(config.vars,'BUILD_SOURCE_ID'),false);
  assert.equal(Object.keys(recorded.source_sha256).length,52);assert.equal(Object.keys(recorded.migrations_sha256).length,17);
  for(const [name,pin]of Object.entries(recorded.source_sha256))assert.equal(createHash('sha256').update(await readFile(new URL('../src/'+name,import.meta.url))).digest('hex'),pin,name);
  for(const [name,pin]of Object.entries(recorded.migrations_sha256))assert.equal(createHash('sha256').update(await readFile(new URL('../migrations/'+name,import.meta.url))).digest('hex'),pin,name);
  assert.equal(recorded.registration_is_provider_availability,false);
  assert.equal(recorded.whole_endpoint_acceptance,false);
  assert.ok(Object.keys(recorded.source_sha256).includes('admin_bridge.js'));
  assert.ok(Object.keys(recorded.source_sha256).includes('operations.js'));
  assert.ok(Object.keys(recorded.migrations_sha256).includes('0008_receipt_capture.sql'));
});

test('the dispatch inventory is immutable, unique and separates public configuration from private actions',()=>{
  assert.ok(Object.isFrozen(operationInventory));assert.ok(Object.isFrozen(publicRpcNames));
  assert.equal(new Set(operationInventory.map(row=>row.path)).size,operationInventory.length);
  for(const row of operationInventory){
    assert.ok(Object.isFrozen(row));assert.equal(row.method,'POST');
    assert.equal(row.authentication,publicRpcNames.includes(row.name)?'public':'bearer_session');
    assert.equal(row.path,`/v1/${row.kind==='rpc'?'rpc':'functions'}/${row.name}`);
  }
});

test('unregistered operations never invoke a domain handler or touch the database',async()=>{
  const env={get DB(){throw new Error('Unregistered operation touched data.');}};
  for(const [kind,name] of [['rpc','retired_admin_note'],['function','retired-provider-hook'],['rpc','toString']]){
    await assert.rejects(dispatchOperation(kind,name,{},env,null),error=>error.status===501&&error.code==='operation_unavailable');
  }
});

test('every registered private operation rejects missing or malformed authorization through the actual Worker',async t=>{
  const f=await fixture({}, {entrypoint:'index.js'});t.after(()=>f.close());
  for(const operation of operationInventory.filter(row=>row.authentication==='bearer_session')){
    for(const headers of [{},{Authorization:'Bearer invalid.synthetic.token'}]){
      const response=await f.mf.dispatchFetch('https://api.collect.example'+operation.path,
        {method:'POST',headers:{'Content-Type':'application/json',...headers},body:'{}'});
      assert.equal(response.status,401,`${operation.path} must reject unauthorized callers`);
      const body=await response.json();assert.equal(typeof body.code,'string');
    }
  }
});

const oldFields=['kind','name','method','path','authentication','source'];
const projection=row=>Object.fromEntries(oldFields.map(key=>[key,row[key]]));
const sha=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const op=(manifest,name)=>{const found=manifest.operations.find(row=>row.name===name);assert.ok(found,name);return found;};

test('Auth17 preserves all89 pre-existing wires and30 prior families while adding9 explicit authentication leaves',async()=>{
 const manifest=await currentManifest(),newConsent=new Set(['get_assisted_sms_consent_v1','set_assisted_sms_consent_v1','get_current_member_payment_review_request_v1']);
 const old=manifest.operations.filter(row=>!newConsent.has(row.name)).map(projection);
 assert.equal(old.length,89);assert.equal(manifest.operations.length,92);
 assert.equal(sha(old),'a87e7f1d8a04c867b2bbbdf0a504c1053b4a23fae2b89bdd3144c6b0ad76481d');
 assert.equal(manifest.operations.filter(row=>row.kind==='rpc').length,85);
 assert.equal(manifest.operations.filter(row=>row.kind==='function').length,7);
 const familyKeys=['path','source','authentication','methods','actions','permissions','transport_dispatch','target','automatic_activation','historical_decision_only','maximum_records','named_kinds','metadata_only','maximum_source_rows','durable_bounded_request_plan','historical_plan_status_only'];
 const capturePath=row=>row.path.startsWith('/api/admin/sms/receipts')||row.path.startsWith('/api/admin/gateway/receipts');
 const legacyFamilies=manifest.route_families.slice(0,22);assert.equal(manifest.route_families.length,39);
 const preserved=await sealedMomo15(),project=row=>Object.fromEntries(familyKeys.filter(key=>Object.hasOwn(row,key)).map(key=>[key,row[key]]));
 assert.deepEqual(manifest.route_families.slice(0,30).map(project),preserved.route_families.map(project));
 const captureFamilies=legacyFamilies.filter(capturePath);assert.equal(captureFamilies.length,4);assert.ok(captureFamilies.every(row=>row.methods.join(',')==='GET'&&row.permissions.read===(row.path.startsWith('/api/admin/sms/')?'sms.read':'payments.read')&&row.metadata_only===true&&row.transport_dispatch===false));
 assert.equal(captureFamilies.filter(row=>row.source==='admin_member_receipts.js').length,2);
 const families=legacyFamilies.filter(row=>!capturePath(row)).map(row=>Object.fromEntries(familyKeys.filter(key=>Object.hasOwn(row,key)).map(key=>[key,row[key]])));
 // Rebuild source insertion order for the preserved legacy base rather than treating added metadata as old fields.
 const base=JSON.parse(await readFile(new URL('../operations-manifest.json',import.meta.url),'utf8')).route_families.filter(row=>!capturePath(row)).map(row=>Object.fromEntries(Object.entries(row).filter(([key])=>familyKeys.includes(key))));
 assert.deepEqual(families,base);assert.equal(families.length,18);
 assert.equal(sha(base),'d9263b178fc53b58679f90681b5539bdf55ec0f014538cab992f634b22298e26');
 for(const row of manifest.operations.filter(row=>newConsent.has(row.name)))assert.equal(row.authentication,'bearer_session');
});

test('provider and custom-authority metadata states real conditional branches without granting configuration or send authority',async()=>{
 const manifest=await currentManifest();assert.equal(assertManifestMetadata(manifest),true);
 const help=op(manifest,'get_current_member_payment_review_request_v1');
 assert.deepEqual(help.supported_callers,['member_app']);assert.equal(help.authentication,'bearer_session');
 assert.match(help.authority_boundary.checks.join(' '),/exact own intent/);
 assert.match(help.authority_boundary.checks.join(' '),/absence is a current snapshot only/);
 assert.match(help.authority_boundary.checks.join(' '),/zero financial or notification effects/);
 const roles=name=>op(manifest,name).conditional_secret_requirements.map(row=>row.role);
 assert.ok(roles('verify-play-integrity').includes('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON'));
 assert.ok(!roles('record_sms_access_consent').includes('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON'));
 assert.equal(op(manifest,'record_sms_access_consent').lifecycle.state,'active');
 assert.ok(roles('prepare-roster-import').includes('OPENAI_API_KEY'));
 assert.ok(!roles('roster-import-upload').includes('OPENAI_API_KEY'));
 const history=op(manifest,'list_current_member_history_page').caller_disposition;
 assert.ok(history.references.includes('lib/shared/repositories/collect_repository_live_reader.dart'));assert.equal(history.reference_is_executed_call_proof,false);
 const indirect=op(manifest,'admin_plan_account_retention_v1').caller_disposition;assert.equal(indirect.state,'registered_contract_without_literal_reference_in_bounded_scope');assert.equal(indirect.dynamic_or_indirect_consumers_excluded,false);
 const ai=op(manifest,'prepare-roster-import').conditional_secret_requirements.find(row=>row.role==='OPENAI_API_KEY');
 assert.match(ai.when,/PDF\/image/);assert.match(ai.when,/deterministic text\/XLSX does not require/);
 assert.ok(roles('admin_plan_account_retention_v1').includes('PRIVACY_RETENTION_APPROVAL_SHA256'));
 assert.ok(!roles('get_assisted_sms_consent_v1').includes('DATA_ENCRYPTION_KEY'));
 assert.ok(roles('set_assisted_sms_consent_v1').includes('DATA_ENCRYPTION_KEY'));
 assert.ok(!op(manifest,'register_notification_device').service_boundary.dependencies.some(row=>/firebase|fcm|apns/i.test(row.name)));
 const operator=manifest.route_families.find(row=>row.path==='/api/admin/notification-operator');
 assert.deepEqual(operator.permissions,{list_pending:'assisted_sms.read',other_actions:'assisted_sms.manage'});
 assert.equal(operator.transport_dispatch,false);assert.match(operator.lifecycle.disposition.join(' '),/No transport sender/);
 const access=manifest.route_families.find(row=>row.path==='/api/admin/notification-operator/access');
 assert.equal(access.automatic_activation,false);assert.match(access.authority_boundary.checks.join(' '),/admin_users.manage/);
 for(const row of [...manifest.operations,...manifest.route_families]){
  assert.equal(row.lifecycle.live_configuration_or_deployment_asserted,false);assert.equal(row.lifecycle.installed_client_acceptance,false);
  assert.equal(row.authority_boundary.metadata_grants_authority,false);assert.equal(row.service_boundary.service_role_or_metadata_bypass,false);
  for(const requirement of row.conditional_secret_requirements)assert.equal(requirement.configured_or_approved_by_manifest,false);
 }
 assert.deepEqual(manifest.runtime_boundaries.handler_exports,['fetch','scheduled']);assert.deepEqual(manifest.runtime_boundaries.configured_crons,[]);
 assert.equal(manifest.runtime_boundaries.configured_ai_binding,null);assert.equal(manifest.runtime_boundaries.processing.automatic_drain_paused,true);assert.equal(manifest.runtime_boundaries.processing.ai.is_api_key_secret,false);
 assert.equal(manifest.runtime_boundaries.processing.financial_posting,false);assert.equal(manifest.runtime_boundaries.processing.outbound_notification_transport,false);
 assert.equal(manifest.runtime_boundaries.processing.ai.model_id,'@cf/meta/llama-3.3-70b-instruct-fp8-fast');
 assert.equal(manifest.runtime_boundaries.processing.actual_processing_or_provider_accuracy_asserted,false);
 assert.ok(!Object.hasOwn(manifest.secret_role_sources,'AI'));
 assert.equal(manifest.runtime_boundaries.functions_are_scheduler_evidence,false);
 assert.equal(manifest.rollout.migration_order.length,17);assert.equal(manifest.rollout.approval_supplied,false);
});

test('metadata refuses stale caller, role, authority, scheduler, migration and runtime-inventory edits',async()=>{
 const valid=await currentManifest();
 const edits=[
  m=>{m.operations.pop();},
  m=>{m.callers.member_app.mode='public';},
  m=>{m.secret_role_sources.AUTH_JWT_SECRET=['notifications.js'];},
  m=>{delete m.operations[0].lifecycle;},
  m=>{m.operations[0].supported_callers=['unreviewed_service_role'];},
  m=>{m.operations[0].caller_disposition.reference_is_executed_call_proof=true;},
  m=>{m.operations[0].authority_boundary.metadata_grants_authority=true;},
  m=>{m.operations[0].service_boundary.service_role_or_metadata_bypass=true;},
  m=>{m.operations[0].conditional_secret_requirements.push({role:'INVENTED_SEND_KEY',when:'always',source:['notifications.js'],configured_or_approved_by_manifest:true});},
  m=>{m.operations[0].lifecycle.live_configuration_or_deployment_asserted=true;},
  m=>{m.operations[0].migration_dependencies.pop();},
  m=>{delete m.migrations_sha256['0012_notification_operator.sql'];},
  m=>{m.route_families[10].permissions.list_pending='notifications.read';},
  m=>{m.runtime_boundaries.handler_exports=['fetch'];},
  m=>{m.runtime_boundaries.configured_crons=['*/5 * * * *'];},
  m=>{m.runtime_boundaries.configured_ai_binding='OTHER_AI';},
  m=>{m.runtime_boundaries.processing.ai.model_id='unreviewed-model';},
  m=>{m.runtime_boundaries.processing.financial_posting=true;},
  m=>{m.runtime_boundaries.processing.dependencies.find(r=>r.name==='AI').availability_or_authority_asserted=true;},
  m=>{m.profile='complete13';},
  m=>{m.predecessor_inventories[0].approval_or_release_acceptance_inherited=true;},
  m=>{m.predecessor_inventories[0].sha256='a'.repeat(64);},
  m=>{m.configuration_sha256='b'.repeat(64);},
  m=>{m.configuration_source='wrangler.jsonc';},
  m=>{m.configuration_source='../unreviewed.json';},
  m=>{m.runtime_boundaries.authentication.actual_google_credentials_verified=true;},
  m=>{m.route_families.find(r=>r.path==='/v1/auth/google/exchange').actions[0].surface='admin';},
  m=>{m.route_families.find(r=>r.path==='/api/admin/team/invite').actions[0].fresh_aal2=false;},
  m=>{delete m.source_sha256['momo_pipeline.js'];},
  m=>{m.migrations_sha256['0014_momo_pipeline.sql']='a'.repeat(64);},
  m=>{m.migrations_sha256['0016_unreviewed.sql']='b'.repeat(64);},
  m=>{m.route_families.find(r=>r.path==='/v1/momo/gateway/ingest').authentication='bearer_session';},
  m=>{m.route_families.find(r=>r.path==='/api/admin/momo/sources/**').actions[1].permissions=['sms.read'];},
  m=>{m.route_families.find(r=>r.path==='/api/admin/momo/transactions/**').transport_dispatch=true;},
  m=>{m.rollout.approval_supplied=true;},
  m=>{m.retired_wire_aliases[0].hosted_denial_acceptance_carried_by_manifest=true;},
  m=>{m.retired_wire_aliases[0].replacements=['/arbitrary-dispatch'];},
 ];
 for(const edit of edits){const candidate=structuredClone(valid);edit(candidate);assert.throws(()=>assertManifestMetadata(candidate));}
 // Existing probe consumers still select the exact POST wire/authentication fields.
 assert.deepEqual(valid.operations.filter(row=>row.authentication==='public').map(row=>row.name).sort(),[...publicRpcNames].sort());
 assert.equal(valid.operations.filter(row=>row.authentication==='bearer_session').length,88);
});

test('the12 old-prefix aliases have explicit source-only disposition and genuine local Worker denial',async t=>{
 const manifest=await currentManifest(),expected=['auth-send-whatsapp-otp','collect-android-gateway','collect-notification-operator','collect-receipt-exception-worker','collect-receipt-supervisor','dispatch-notifications','ingest-payment-sms','parse-payment-sms','prepare-roster-import','reconciliation-finalize','send-notification','verify-play-integrity'];
 assert.deepEqual(manifest.retired_wire_aliases.map(row=>row.name),expected);
 assert.equal(new Set(manifest.retired_wire_aliases.map(row=>row.path)).size,12);
 const f=await fixture({}, {entrypoint:'index.js'});t.after(()=>f.close());
 const session=await f.login();
 for(const alias of manifest.retired_wire_aliases){
  assert.equal(alias.capability_equivalence,'not_asserted');assert.equal(alias.capability_removed_by_metadata,false);
  assert.equal(alias.hosted_denial_acceptance_carried_by_manifest,false);assert.equal(alias.old_Supabase_project_state_asserted,false);
  assert.equal(alias.historical_inventory_provenance.sha256,'87e899985450a429d3384bcc2abefb51ae10788bed48d6226c33c23a6405a923');
  for(const headers of [{},{Authorization:'Bearer '+session.access_token}]){
   const response=await f.mf.dispatchFetch('https://api.collect.example'+alias.path,{method:alias.method,headers:{'Content-Type':'application/json',...headers},body:'{}'});
   assert.equal(response.status,headers.Authorization?404:401,alias.path);
   const body=await response.json();assert.equal(body.code,headers.Authorization?'not_found':'authentication_required');
  }
 }
 assert.ok(f.trace.every(row=>row.url==='https://trusted-relay.example/otp'||row.url==='https://challenges.cloudflare.com/turnstile/v0/siteverify'));
});

// Exact current13 source evidence; this is not a deployed grant observation.
test('preserved complete13 artifact retains exact bytes,0013,63-role and fetch-only contract and rejects the future source tree',async()=>{
 const raw=await readFile(new URL('../operations-manifest.json',import.meta.url));assert.equal(createHash('sha256').update(raw).digest('hex'),'968bb1754e4c9f425e173b7548ce5dafe2daec57ef7e3f827272818ce7a6ca29');
 const manifest=JSON.parse(raw),review=manifest.rollout.additive_migration_review,name='0013_sms_receipt_metadata_read.sql';assert.equal(assertManifestMetadata(manifest),true);
 assert.ok(!manifest.operations.some(row=>row.name==='get_current_member_payment_review_request_v1'));
 assert.equal(manifest.profile,undefined);assert.equal(manifest.metadata_version,1);assert.deepEqual(manifest.runtime_boundaries.handler_exports,['fetch']);assert.deepEqual(manifest.runtime_boundaries.configured_crons,[]);
 await assert.rejects(buildManifest({profile:'complete13'}),/reviewed complete13-schema prefix and exact0013/);
 assert.equal(review.sha256,'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b');
 assert.equal(manifest.migrations_sha256[name],review.sha256);assert.equal(review.expected_fresh_capability_definitions,63);
 assert.equal(review.new_tables,0);assert.equal(review.retention_classes,91);assert.equal(review.raw_extract_or_assisted_access_granted,false);assert.equal(review.actual_target_migration_or_grants_observed,false);assert.equal(review.approval_supplied,false);
 const db=new DatabaseSync(':memory:');try{for(const name of manifest.rollout.migration_order){const raw=await readFile(new URL('../migrations/'+name,import.meta.url));assert.equal(createHash('sha256').update(raw).digest('hex'),manifest.migrations_sha256[name]);db.exec(raw.toString());}
  assert.equal(db.prepare('SELECT count(*) AS n FROM admin_account_role_capabilities').get().n,63);assert.equal(db.prepare('SELECT count(*) AS n FROM admin_grants').get().n,0);
  assert.deepEqual(db.prepare("SELECT role,permission FROM admin_account_role_capabilities WHERE permission='sms.read' ORDER BY role").all().map(r=>({...r})),[{role:'admin',permission:'sms.read'},{role:'owner',permission:'sms.read'},{role:'staff',permission:'sms.read'}]);
  assert.equal(db.prepare("SELECT tbl_name FROM sqlite_schema WHERE type='index' AND name='sms_receipts_metadata_order'").get().tbl_name,'sms_receipts');
 }finally{db.close();}
 for(const edit of [m=>{delete m.migrations_sha256[name];},m=>{m.migrations_sha256[name]='a'.repeat(64);},m=>{m.migrations_sha256['0014_unreviewed.sql']='b'.repeat(64);},m=>{m.rollout.additive_migration_review.actual_target_migration_or_grants_observed=true;},m=>{m.rollout.additive_migration_review.raw_extract_or_assisted_access_granted=true;}]){const changed=structuredClone(manifest);edit(changed);assert.throws(()=>assertManifestMetadata(changed));}
});

test('MoMo15 metadata describes scoped native leaves and explicit Admin capabilities without inventing a member token or send authority',async()=>{
 const manifest=await sealedMomo15(),families=manifest.route_families.slice(22);
 assert.equal(families.length,8);assert.ok(families.every(row=>row.transport_dispatch===false));
 const native=families.filter(row=>row.source==='momo_gateway.js');assert.equal(native.length,4);
 assert.deepEqual(native.map(row=>[row.path,row.methods]),[
  ['/v1/momo/gateway/pair',['POST']],['/v1/momo/gateway/ingest',['POST']],
  ['/v1/momo/gateway/status',['GET']],['/v1/momo/gateway/heartbeat',['POST']],
 ]);
 assert.ok(native.every(row=>row.supported_callers.join(',')==='native_android_gateway'));
 assert.ok(native.every(row=>!row.conditional_secret_requirements.some(r=>r.role==='AUTH_JWT_SECRET')));
 const family=path=>families.find(row=>row.path===path),sources=family('/api/admin/momo/sources/**'),transactions=family('/api/admin/momo/transactions/**');
 assert.deepEqual(sources.actions.find(row=>row.path.endsWith('/content')).permissions,['sms.read','sms.reveal']);
 assert.ok(sources.actions.find(row=>row.path.endsWith('/content')).fresh_aal2);
 assert.deepEqual(sources.actions.find(row=>row.path.endsWith('/reparse')).permissions,['sms.read','sms.extract']);
 assert.deepEqual(transactions.actions.find(row=>row.path.endsWith('/candidates')).permissions,['payments.read','users.read','collections.read']);
 assert.deepEqual(transactions.actions.find(row=>row.path.endsWith('/assign')).permissions,['payments.read','payments.write']);
 for(const row of families){assert.equal(row.authority_boundary.metadata_grants_authority,false);assert.equal(row.lifecycle.live_configuration_or_deployment_asserted,false);}
});

async function verifyMigrationEffects(manifest,expectedTables){
 const review=manifest.rollout.additive_migration_review;
 assert.equal(review.previous_fresh_application_tables,81);assert.equal(review.expected_fresh_application_tables,expectedTables);
 assert.equal(review.previous_fresh_capability_definitions,63);assert.equal(review.expected_fresh_capability_definitions,67);
 assert.equal(review.assisted_sms_authority_added,false);assert.equal(review.actual_target_migration_or_grants_observed,false);assert.equal(review.approval_supplied,false);
 const db=new DatabaseSync(':memory:');
 try{
  const names=manifest.rollout.migration_order;
  for(const name of names.slice(0,13))db.exec(await readFile(new URL('../migrations/'+name,import.meta.url),'utf8'));
  const previousDefinitions=db.prepare('SELECT role,permission FROM admin_account_role_capabilities ORDER BY role,permission').all().map(row=>JSON.stringify(row));assert.equal(previousDefinitions.length,63);
  const cases=[
   {role:'owner',status:'active',access:'active',linked:true,adopted:true},
   {role:'admin',status:'active',access:'active',linked:true,adopted:true},
   {role:'staff',status:'active',access:'active',linked:true,adopted:false},
   {role:'admin',status:'invited',access:'active',linked:true,adopted:false},
   {role:'staff',status:'invited',access:'active',linked:true,adopted:false},
   {role:'admin',status:'revoked',access:'active',linked:true,adopted:false},
   {role:'admin',status:'active',access:'suspended',linked:true,adopted:false},
   {role:'admin',status:'active',access:'active',linked:false,adopted:false},
  ],date=new Date().toISOString();
  for(const [index,c] of cases.entries()){
   c.adminId=randomUUID();c.userId=randomUUID();
   db.prepare('INSERT INTO users(id,public_id,full_name,access_status,created_at,updated_at) VALUES(?,?,?,?,?,?)')
    .run(c.userId,'70000'+index,'Synthetic migration boundary',c.access,date,date);
   db.prepare('INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,?,?,1,1)')
    .run(c.adminId,c.role==='owner'?'info@ikanisa.com':`momo15-${index}@example.test`,c.role,c.status,'synthetic-credential-never-used-for-auth');
   if(c.linked)db.prepare('INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(?,?,?,?)')
    .run(c.adminId,c.userId,'synthetic-migration-test',date);
  }
  for(const name of names.slice(13)){
   const raw=await readFile(new URL('../migrations/'+name,import.meta.url));
   assert.equal(createHash('sha256').update(raw).digest('hex'),manifest.migrations_sha256[name]);db.exec(raw.toString());
  }
  assert.equal(db.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'").get().n,expectedTables);
  assert.equal(db.prepare('SELECT count(*) AS n FROM admin_account_role_capabilities').get().n,67);
  const added=db.prepare('SELECT role,permission FROM admin_account_role_capabilities ORDER BY role,permission').all().filter(row=>!previousDefinitions.includes(JSON.stringify(row))).map(row=>({...row}));
  assert.deepEqual(added,[{role:'admin',permission:'sms.extract'},{role:'admin',permission:'sms.reveal'},{role:'owner',permission:'sms.extract'},{role:'owner',permission:'sms.reveal'}]);
  for(const c of cases)assert.deepEqual({...db.prepare('SELECT role,status FROM admin_users WHERE id=?').get(c.adminId)},{role:c.role,status:c.status});
  for(const name of ['auth_sessions','admin_sessions',...(expectedTables===97?['auth_google_flows','auth_google_identities','admin_email_otp_challenges']:[])])assert.equal(db.prepare('SELECT count(*) AS n FROM '+name).get().n,0,name);
  for(const c of cases){const permissions=db.prepare("SELECT permission FROM admin_grants WHERE user_id=? AND permission IN('sms.reveal','sms.extract') ORDER BY permission").all(c.userId).map(row=>row.permission);
   assert.deepEqual(permissions,c.adopted?['sms.extract','sms.reveal']:[]);}
  assert.equal(db.prepare('SELECT count(*) AS n FROM ledger_entries').get().n,0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM contribution_posting_snapshots').get().n,0);
  assert.deepEqual(db.prepare('PRAGMA foreign_key_check').all(),[]);assert.equal(db.prepare('PRAGMA integrity_check').get().integrity_check,'ok');
 }finally{db.close();}
}

// Historical metadata is pinned evidence, not a claim that historical source bodies
// equal the current tree. Applying its exact15 SQL is a separate positive control.
test('sealed MoMo15 metadata remains exact while default and explicit historical producers reject the current17 tree',async()=>{
 const manifest=await sealedMomo15();assert.equal(manifest.profile,'momo15_candidate');assert.equal(manifest.metadata_version,2);assert.equal(manifest.rollout.migration_order.length,15);
 assert.equal(manifest.predecessor_inventory.sha256,'968bb1754e4c9f425e173b7548ce5dafe2daec57ef7e3f827272818ce7a6ca29');assert.equal(manifest.predecessor_inventory.approval_or_release_acceptance_inherited,false);
 for(const build of [()=>buildManifest(),()=>buildManifest({profile:'momo15_candidate'})])await assert.rejects(build(),/MoMo candidate requires (its exact source configuration|the exact complete15-schema prefix)/);
});

test('exact historical15 and explicit17 SQL each retain bounded4-definition owner/admin adoption without activating staff or financial/session writes',async t=>{
 await t.test('sealed exact15 schema has94 application tables',async()=>verifyMigrationEffects(await sealedMomo15(),94));
 await t.test('explicit current17 schema has97 application tables',async()=>verifyMigrationEffects(await currentManifest(),97));
});

test('nine explicit Auth17 leaves retain member-only Google, recipient-bound approved Admin OTP and fresh-owner invitations',async()=>{
 const manifest=await currentManifest(),leaves=manifest.route_families.slice(30),family=path=>{const row=leaves.find(r=>r.path===path);assert.ok(row,path);return row;};
 assert.deepEqual(leaves.map(r=>[r.path,r.methods]),[
  ['/v1/auth/otp',['POST']],['/v1/auth/verify',['POST']],['/v1/auth/google/start',['POST']],['/v1/auth/google/callback',['GET']],['/v1/auth/google/exchange',['POST']],['/api/admin/auth/otp',['POST']],['/api/admin/auth/verify',['POST']],['/api/admin/team/invite',['POST']],['/api/admin/team/:id/resend',['POST']],
 ]);
 const callback=family('/v1/auth/google/callback'),exchange=family('/v1/auth/google/exchange');assert.equal(callback.actions[0].session_tokens_returned,false);assert.equal(callback.actions[0].ambient_cookie_authority,false);assert.equal(exchange.actions[0].surface,'member');assert.equal(exchange.actions[0].admin_grants_issued,false);assert.equal(exchange.actions[0].assurance_level,1);assert.match(exchange.authority_boundary.checks.join(' '),/RS256/);
 assert.ok(exchange.conditional_secret_requirements.some(r=>r.role==='GOOGLE_CLIENT_SECRET'&&!r.configured_or_approved_by_manifest));
 const otp=family('/api/admin/auth/otp'),verify=family('/api/admin/auth/verify');assert.equal(otp.actions[0].automatic_registration,false);assert.equal(otp.actions[0].unknown_account_exception,'admin_access_not_approved');assert.equal(verify.actions[0].assurance_level,1);assert.match(verify.authority_boundary.checks.join(' '),/recipient-email/);
 for(const path of ['/api/admin/team/invite','/api/admin/team/:id/resend']){const action=family(path).actions[0];assert.equal(action.owner_only,true);assert.equal(action.fresh_aal2,true);assert.equal(action.invitation_is_session,false);assert.deepEqual(action.permissions,['admin_users.manage']);}
 for(const name of ['ingest-client-sms','ingest-payment-sms']){const row=op(manifest,name),ordinary=row.admission_branches.ordinary_member_capture,legacy=row.admission_branches.legacy_receiver_capability;assert.equal(ordinary.receiver_wallet_required,false);assert.equal(ordinary.group_required,false);assert.equal(ordinary.provider_or_native_integrity_required,false);assert.deepEqual(ordinary.budgets,{per_minute:60,per_day:1000});assert.equal(ordinary.financial_effects,0);assert.equal(legacy.verified_receiver_required,true);assert.equal(legacy.one_use_capability,'sms.ingest');}
});
