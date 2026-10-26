import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {retentionSchema,retentionSnapshot} from '../src/privacy_retention_catalog.js';
import {retentionFixture,authorization,sourceId,sha} from './support/retention_fixture.mjs';

test('exact MoMo schema profile covers beneficiary-linked private sources and blocks unsupported erasure',async t=>{
 const f=await retentionFixture(t),member=await f.login(),operator=await f.operator(),at=new Date().toISOString(),owner=operator.user.id,subject=member.user.id;
 const ids=Object.fromEntries(['account','binding','raw','attempt','transaction','group','evidence','payment','entry','resolution'].map(k=>[k,randomUUID()]));
 const session=await f.db.prepare("SELECT id FROM auth_sessions WHERE user_id=? AND surface='admin' ORDER BY created_at DESC LIMIT 1").bind(owner).first();assert.ok(session);
 const rawBody='SYNTHETIC RETENTION SOURCE',rawKey='sms/'+ids.raw,evidenceKey='evidence/'+ids.evidence;
 // Declared synthetic object bytes test retention coverage, not SMS acceptance.
 await f.bucket.put(rawKey,rawBody);await f.bucket.put(evidenceKey,rawBody);
 await f.db.batch([
  f.db.prepare("INSERT INTO momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,created_at) VALUES(?,'mtn_momo','123456','Synthetic Receiver',?,'RWF','Africa/Kigali',?)").bind(ids.account,sha('123456'),at),
  f.db.prepare('INSERT INTO momo_gateway_bindings(id,owner_user_id,receiving_account_id,created_at) VALUES(?,?,?,?)').bind(ids.binding,owner,ids.account,at),
  f.db.prepare('INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)').bind(ids.raw,owner,session.id,randomUUID(),sha(rawBody),sha('123456'),rawKey,sha(rawBody),rawBody.length,at),
  f.db.prepare("INSERT INTO momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at) VALUES(?,?,1,?,'live','completed',0,?,?)").bind(ids.raw,ids.binding,ids.account,at,at),
  f.db.prepare("INSERT INTO momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at) VALUES(?,?,1,'synthetic-model','synthetic-schema','synthetic-prompt','synthetic-parser','synthetic-profile','{}',?,'{}','[]','accepted',?)").bind(ids.attempt,ids.raw,sha(rawBody),at),
  f.db.prepare("INSERT INTO momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,transaction_timezone,transaction_time_source,parse_attempt_id,mode,created_at,updated_at) VALUES(?,?,'mtn_momo','00123','incoming_receipt',5000,'RWF',0,'Africa/Kigali','synthetic',?,'live',?,?)").bind(ids.transaction,ids.account,ids.attempt,at,at),
  f.db.prepare("INSERT INTO momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at) VALUES(?,?,?,'accepted',?)").bind(ids.transaction,ids.raw,ids.attempt,at),
  f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,'Synthetic Group','ikimina',?,?)").bind(ids.group,'privacy-'+ids.group,owner,at,at),
  f.db.prepare("INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,amount_minor,observed_at,created_at) VALUES(?,?,?,?,?,?,'text/plain','operator_recorded',5000,?,?)").bind(ids.evidence,ids.group,owner,evidenceKey,sha(rawBody),rawBody.length,at,at),
  f.db.prepare("INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES(?,?,?,?,5000,'reconciled',?)").bind(ids.payment,ids.group,subject,ids.evidence,at),
  f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,5000,'contribution',?,?,?,?)").bind(ids.entry,ids.payment,ids.group,subject,ids.evidence,owner,randomUUID(),at),
  f.db.prepare('INSERT INTO momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,created_at) VALUES(?,?,?,?,?,?)').bind(ids.transaction,ids.payment,subject,owner,'Synthetic reviewed relationship',at),
  f.db.prepare('INSERT INTO contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at) VALUES(?,?,5000,5000,?)').bind(ids.entry,ids.payment,at),
  f.db.prepare('INSERT INTO momo_source_resolutions(id,raw_sms_id,receiving_account_id,source_body_sha256,reviewed_by,evidence_reference,reason,created_at) VALUES(?,?,?,?,?,?,?,?)').bind(ids.resolution,ids.raw,ids.account,sha(rawBody),owner,'SYNTHETIC EVIDENCE ONLY','Synthetic historical source relationship',at)
 ]);
 const schema=await retentionSchema({DB:f.db});assert.equal(schema.profile,'auth17');assert.ok(schema.classes.includes('momo_source_resolutions'));
 const sourceRequest=randomUUID();await f.db.batch([
  f.db.prepare('INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(?,?,?,?,?,?,?)').bind(owner,sourceRequest,'momo.sources.reparse',session.id,sha('SYNTHETIC REQUEST'),JSON.stringify({raw_sms_id:ids.raw}),at),
  f.db.prepare("INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at) VALUES(?,?,'momo.source.revealed','sms_receipt',?,'{}',?)").bind(owner,session.id,ids.raw,at)
 ]);
 const before=await retentionSnapshot({DB:f.db,PRIVATE_MEDIA:f.bucket},subject);
 for(const table of ['momo_receiving_accounts','momo_gateway_bindings','momo_processing_jobs','momo_parse_attempts','momo_transactions','momo_transaction_sources','momo_financial_links','momo_source_resolutions','contribution_posting_snapshots','sms_receipts','payment_evidence'])assert.equal(before.rows[table].length,1,table);
 assert.ok(before.summary.objects.some(o=>o.key===rawKey));assert.equal(before.summary.balances[ids.group+':'+subject],'5000');
 assert.ok(before.rows.request_receipts.some(r=>r.request_id===sourceRequest));assert.ok(before.rows.audit_log.some(r=>r.entity_id===ids.raw));
 const intake=await f.call('/v1/rpc/request_account_deletion_v1',{p_request_id:randomUUID(),p_reason:null},authorization(member));assert.equal(intake.status,200);f.scopeRequest=intake.body.request_id;
 const p=await f.policy(operator);p.rules.momo_parse_attempts={action:'erase',basis_reference:'SYNTHETIC ONLY',deadline:new Date(Date.now()-60000).toISOString()};await f.policy(operator,{rules:p.rules});
 const planned=await f.retention(operator,'plan',{operation_id:randomUUID(),request_id:f.scopeRequest,expected_review_revision:0,expected_source_id:sourceId,policy_sha256:f.policySha});assert.equal(planned.status,200,JSON.stringify(planned.body));assert.equal(planned.body.tasks.length,schema.classes.length);
 const execute=async name=>{const task=planned.body.tasks.find(v=>v.class_name===name),claim=await f.retention(operator,'claim',{operation_id:randomUUID(),plan_id:planned.body.plan_id,task_id:task.task_id,expected_task_revision:0,lease_seconds:120});assert.equal(claim.status,200,JSON.stringify(claim.body));const result=await f.retention(operator,'execute',{operation_id:randomUUID(),claim_id:claim.body.claim_id,fence:claim.body.fence});assert.equal(result.status,200,JSON.stringify(result.body));return result.body;};
 assert.equal((await execute('access')).disposition,'access_quarantined');const blocked=await execute('momo_parse_attempts');assert.equal(blocked.verified,false);assert.equal(blocked.reason,'immutable_or_unimplemented_class_adapter');assert.equal(blocked.erasure_completed,false);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM momo_parse_attempts').first()).n,1);assert.equal((await f.db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,5000);
 // Whole known extensions are required. Familiar names do not permit extra fields.
 await f.db.prepare('ALTER TABLE momo_parse_attempts ADD COLUMN unreviewed_copy TEXT').run();await assert.rejects(retentionSchema({DB:f.db}),e=>e.code==='privacy_retention_schema_changed');
});
