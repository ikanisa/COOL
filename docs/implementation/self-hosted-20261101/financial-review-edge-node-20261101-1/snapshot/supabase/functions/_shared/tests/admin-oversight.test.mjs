import test from 'node:test';
import assert from 'node:assert/strict';
import {adminOversightRead,oversightHealthSql} from '../domain/admin_oversight.js';

const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`;
function fixture({permission='system_health.read',denied=false,selects}={}){
 const account={id:id(1),principal_id:id(2),auth_user_id:id(3),auth_session_id:id(4),public_id:id(5),token_hash:'a'.repeat(64),origin:'https://admin.example',auth_version:1,role:'owner',issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,permissions:[permission]};
 const actor={surface:'admin',userId:account.principal_id,sessionId:account.auth_session_id,permissions:new Set([permission])};
 const calls=[];const env={BUILD_SOURCE_ID:'b'.repeat(64),PRIVATE_MEDIA:{},MOMO_PROCESSING_PAUSED:'false',MOMO_AI_ENABLED:'true',AI:{run(){}},DB:{prepare(sql){return {sql,args:[],bind(...args){return {...this,args};}};},async batch(items){calls.push(items);assert.match(items[0].sql,/set_admin_email_context/);assert.match(items[1].sql,/INSERT INTO admin_account_guards/);assert.equal(items[1].args.includes(permission),true);assert.match(items.at(-1).sql,/DELETE FROM admin_account_guards/);if(denied)throw Error('admin_account_guards');return items.map((item,index)=>({results:index<2||index===items.length-1?[]:selects[index-2]}));}}};
 const read=(path,method='GET')=>{const url=new URL('https://admin.example/api/admin/oversight/'+path);return adminOversightRead(new Request(url,{method}),env,account,actor,url.pathname.split('/').slice(4),url);};
 return {env,actor,account,calls,read};
}
const seconds=()=>Math.floor(Date.now()/1000);
const healthRows=()=>{const at=seconds();return [[{observed_seconds:at}],[{pending:2,retry:1,processing:3,expired_lease:1,needs_review:4,source_unresolved:5,attempt_exhausted:1,records_with_error:8,oldest_due_at:at-100,last_changed_at:at-3}],[{queued:2,claimed:1,expired_claim:1,send_started:1,observed_sent:4,failed_no_send:2,uncertain:1,oldest_queued_at:at-400,oldest_unobserved_send_at:at-90,last_created_at:at-10}],[{pending:1,sent:0,failed:0,read:2,oldest_pending_at:at-40,last_created_at:at-20}],[{pending:0,accepted:2,failed:1,oldest_pending_at:null,last_changed_at:at-80}],[{reserved:1,dispatching:1,accepted:3,rejected:1,unknown:2,already_registered:0,oldest_unconfirmed_at:at-120,last_changed_at:at-10}],[{pending:2,retry:1,claimed:1,sending:1,accepted:3,rejected:1,suppressed:1,unknown:2,expired_lease:1,due:2,records_with_error:3,oldest_due_at:at-60,oldest_pending_at:at-70,last_changed_at:at-10}]];};

test('health exposes exact guarded bounded aggregate states and ages without inferring delivery or heartbeat',async()=>{
 const f=fixture({selects:healthRows()}),value=await f.read('health');
 assert.equal(f.calls.length,1);assert.equal(f.calls[0].length,oversightHealthSql.length+3);
 assert.equal(value.queues.momo.oldest_due_seconds,100);assert.equal(value.queues.momo.expired_lease,1);
 assert.equal(value.queues.assisted_sms.oldest_unobserved_send_seconds,90);assert.equal(value.queues.assisted_sms.automatic_retry,false);
 assert.equal(value.queues.notifications.semantics,'persisted_in_app_events');assert.equal(value.queues.admin_email.semantics,'legacy_email_records');
 assert.equal(value.queues.invitations.accepted_means,'provider_accepted');assert.equal(value.queues.invitations.oldest_unconfirmed_seconds,120);
 assert.equal(value.queues.push_delivery.unknown_is_retryable,false);assert.equal(value.queues.push_delivery.accepted_means,'provider_accepted');assert.equal(value.queues.push_delivery.oldest_pending_seconds,70);
 assert.equal(value.external_services_checked,false);assert.equal(value.worker_heartbeat,'not_recorded');
 assert.equal(value.configuration.momo_extractor,'configured');assert.equal(value.configuration.transactional_email,'missing');
 assert.equal(JSON.stringify(value).includes('token_hash'),false);assert.equal(JSON.stringify(value).includes('raw_body'),false);
 for(const sql of oversightHealthSql)assert.doesNotMatch(sql,/SELECT\s+\*|details_json|destination_ciphertext|body_ciphertext|provider_message_id/i);
});

test('missing or changed grant and malformed health results fail closed',async()=>{
 const f=fixture({selects:healthRows()});f.actor.permissions.clear();await assert.rejects(()=>f.read('health'),{code:'permission_required'});assert.equal(f.calls.length,0);
 await assert.rejects(()=>fixture({denied:true}).read('health'),{code:'admin_access_changed'});
 const rows=healthRows();rows[1][0].pending='2';await assert.rejects(()=>fixture({selects:rows}).read('health'),{code:'oversight_unavailable'});
 const age=healthRows();age[2][0].oldest_unobserved_send_at=seconds()+100;await assert.rejects(()=>fixture({selects:age}).read('health'),{code:'oversight_unavailable'});
 await assert.rejects(()=>fixture().read('health?limit=1'),{code:'invalid_oversight_query'});
 await assert.rejects(()=>fixture().read('health','POST'),{code:'method_not_allowed'});
});

test('domain audit includes other operators as metadata, stable numeric cursor and bound filters',async()=>{
 const at=new Date().toISOString(),rows=[11,10,9].map(n=>({id:String(n),actor_user_id:id(n),action:'sms.raw.revealed',entity_type:'sms_receipt',entity_id:id(8),request_id:id(9),created_at:at}));
 const f=fixture({permission:'audit.read',selects:[rows]});const value=await f.read('audit/domain?limit=2&actor_id='+id(11)+'&action=sms.raw.revealed');
 assert.deepEqual(value.rows.map(r=>r.id),['11','10']);assert.deepEqual(value.next_cursor,{before_id:'10'});assert.equal(value.details_included,false);assert.equal(value.actor_reference,'canonical_principal');
 const query=f.calls[0][2];assert.match(query.sql,/ORDER BY audit_log.id DESC/);assert.equal(query.args.at(-1),3);assert.ok(query.args.includes(id(11)));assert.doesNotMatch(query.sql,/details_json|actor_session_id/);
});

test('account audit cursor uses paired epoch and UUID and removes non-UUID references',async()=>{
 const at=seconds(),row={id:id(9),actor_id:'not-public-reference',subject_id:id(3),action:'supabase_signed_in',occurred_at:at};
 const f=fixture({permission:'audit.read',selects:[[row]]});const value=await f.read('audit/accounts?limit=1&before_id='+id(10)+'&before_seconds='+at);
 assert.equal(value.rows[0].actor_id,null);assert.equal(value.rows[0].request_id,null);assert.equal(value.next_cursor,null);assert.equal(value.actor_reference,'admin_account');
 await assert.rejects(()=>f.read('audit/accounts?before_id='+id(1)),{code:'invalid_oversight_query'});
 await assert.rejects(()=>f.read('audit/domain?before_id=9223372036854775808'),{code:'invalid_oversight_query'});
 await assert.rejects(()=>f.read('audit/domain?limit=1&limit=2'),{code:'invalid_oversight_query'});
 await assert.rejects(()=>f.read('audit/domain?details=true'),{code:'invalid_oversight_query'});
});
