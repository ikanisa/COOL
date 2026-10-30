import test from 'node:test';
import assert from 'node:assert/strict';
import {auditQuery,auditPage,operationalHealth,diagnosticGroups,OVERSIGHT_TOOLS,callOversightTool} from '../src/oversight.mjs';
import {healthFixture,diagnosticFixture} from './oversight-fixture.mjs';
import {ADMIN_ORIGIN,SafeError} from '../src/config.mjs';

const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`;
const audit=()=>({contract_version:1,scope:'cross_operator_audit_metadata',source:'domain',actor_reference:'canonical_principal',limit:2,next_cursor:{before_id:'10'},rows:['11','10'].map((value,index)=>({id:value,actor_id:id(index+1),action:'sms.raw.revealed',entity_type:'sms_receipt',entity_id:id(7),request_id:null,created_at:new Date().toISOString()})),details_included:false,checked_at:new Date().toISOString()});

test('three oversight tools remain bounded read-only fixed-origin permissioned interfaces',async()=>{
 assert.equal(OVERSIGHT_TOOLS.length,3);for(const tool of OVERSIGHT_TOOLS){assert.equal(tool.annotations.readOnlyHint,true);assert.equal(tool.annotations.destructiveHint,false);assert.equal(tool.inputSchema.additionalProperties,false);}
 const calls=[],api={config:{origin:ADMIN_ORIGIN},async withAuthority(permission,callback){calls.push(permission);return callback({get:async path=>{calls.push(path);return healthFixture();}});}};
 const result=await callOversightTool(api,'collect_admin_health',{expected_source_revision:'a'.repeat(64)});assert.equal(result.read_only,true);assert.equal(result.data.source_matches,true);assert.deepEqual(calls,['system_health.read','/api/admin/oversight/health']);
 await assert.rejects(()=>callOversightTool(api,'collect_admin_health',{url:'https://evil.example'}));
});

test('audit filters and numeric / paired account cursors are typed and size bounded',()=>{
 const q=auditQuery({source:'domain',limit:2,actor_id:id(1),cursor:{before_id:'9223372036854775807'}});assert.ok(q.path.includes('before_id=9223372036854775807'));
 for(const args of [{limit:101},{cursor:{before_id:'1',before_seconds:2}},{source:'accounts',cursor:{before_id:id(1)}},{source:'domain',cursor:{before_id:'9223372036854775808'}},{action:'raw\nsecret'},{details:true},{source:'private'}])assert.throws(()=>auditQuery(args));
 assert.ok(auditQuery({source:'accounts',cursor:{before_id:id(1),before_seconds:100}}).path.includes('before_seconds=100'));
});

test('audit page validates cross-operator metadata cursor and precision and rejects raw additions or ordering faults',()=>{
 const value=audit();assert.deepEqual(auditPage(value,{source:'domain',limit:2}),value);
 for(const mutate of [p=>p.rows.reverse(),p=>p.rows[0].details_json='secret',p=>p.rows[0].actor_session_id=id(1),p=>p.next_cursor.before_id='9',p=>p.details_included=true,p=>p.rows[0].id=11,p=>p.checked_at=new Date(Date.now()-121000).toISOString()]){const candidate=structuredClone(value);mutate(candidate);assert.throws(()=>auditPage(candidate,{source:'domain',limit:2}));}
});

test('health strictly distinguishes queue state, record age and configured bindings from provider confirmation',()=>{
 const value=healthFixture();assert.equal(operationalHealth(value).source_matches,null);assert.equal(operationalHealth(value,'c'.repeat(64)).source_matches,false);
 for(const mutate of [p=>p.queues.momo.pending='2',p=>p.queues.momo.expired_lease=2,p=>p.queues.assisted_sms.automatic_retry=true,p=>p.queues.notifications.raw_body='secret',p=>p.external_services_checked=true,p=>p.worker_heartbeat='healthy',p=>p.queues.momo.oldest_due_seconds=-1,p=>p.configuration.transactional_email='delivered']){const candidate=structuredClone(value);mutate(candidate);assert.throws(()=>operationalHealth(candidate));}
});

test('diagnostics exposes only bounded coarse aggregates with allowed code severity and no identifiers or raw errors',()=>{
 const value=diagnosticFixture();assert.deepEqual(diagnosticGroups(value),value);
 for(const mutate of [p=>p.groups[0].raw_error='secret',p=>p.groups[0].user_id=id(1),p=>p.groups[0].severity='info',p=>p.groups[0].code='customException',p=>p.groups[0].occurrences=1,p=>p.groups.push({...p.groups[0]}),p=>p.groups[0].last_received_hour=new Date(Date.now()-27*3600000).toISOString(),p=>p.truncated=true]){const candidate=structuredClone(value);mutate(candidate);assert.throws(()=>diagnosticGroups(candidate));}
});

test('missing permission and changed current authority withhold every oversight read result',async()=>{
 let accessed=false;const api={config:{origin:ADMIN_ORIGIN},async withAuthority(permission,callback){assert.equal(permission,'system_health.read');await callback({get:async()=>{accessed=true;return diagnosticFixture();}});throw new SafeError('session_changed','changed');}};
 await assert.rejects(()=>callOversightTool(api,'collect_admin_diagnostics',{}),{code:'session_changed'});assert.equal(accessed,true);
});
