// Projection/approval unit only. Real SQL attribution is a separate native gate.
import test from 'node:test';
import assert from 'node:assert/strict';
import {memberRealtimeRetentionIdentity,inventoryMemberRealtime,memberRealtimeRetentionGuards} from '../member-realtime-retention.js';
const HASH='a'.repeat(64),schema={contract:'collect.member.realtime.inventory.v1',metadata_sha256:HASH,partitions_sha256:HASH};
function fixture(entry={status:'observed',count:0,rows:[],scope:'retained_member_topics_only',provider_logs_backups:'blocked',erasure_verified:false}){
 const calls=[];const env={DB:{prepare(sql){const s={sql,values:[],bind(...values){this.values=values;return this;},async first(key){calls.push({sql,values:this.values});const value=sql.includes('pg_get_functiondef')?{sha256:HASH}:{inventory:{contract_version:1,schema,class:entry}};return key?value[key]:value;}};return s;}}};return{env,calls};
}
test('managed Realtime uses the exact fresh-scoped helper and exposes no raw topic/session/message values',async()=>{
 const row={key_sha256:'b'.repeat(64),row_sha256:'c'.repeat(64),identity_sha256:'c'.repeat(64),lifecycle:{managed_copy:true,erasure_verified:false}};
 const f=fixture({status:'observed',count:1,rows:[row],scope:'retained_member_topics_only',provider_logs_backups:'blocked',erasure_verified:false});
 const identity=await memberRealtimeRetentionIdentity(f.env),observed=await inventoryMemberRealtime(f.env,'synthetic-subject',identity);
 assert.equal(observed.count,1);assert.deepEqual(observed.rows,[row]);assert.ok(f.calls.some(c=>c.sql==='SELECT private.retention_member_realtime_inventory(?) AS inventory'&&c.values[0]==='synthetic-subject'));assert.ok(!JSON.stringify(observed).includes('collect:member:'));
 const statements=memberRealtimeRetentionGuards(f.env,{id:'synthetic-plan',subject_id:'synthetic-subject'},'managed:realtime_messages',observed,identity);assert.equal(statements.length,1);assert.ok(statements[0].sql.includes("private.retention_member_realtime_inventory(?)->'class'=?::jsonb"));assert.ok(statements[0].values.some(v=>v&&typeof v==='object'&&!Array.isArray(v)&&v.count===1));
});
test('unavailable attribution stays unavailable rather than becoming shared unmapped global absence',async()=>{
 const f=fixture({status:'unavailable',count:0,rows:[],reason:'principal_attribution_unavailable'}),identity=await memberRealtimeRetentionIdentity(f.env),value=await inventoryMemberRealtime(f.env,'missing-principal',identity);assert.equal(value.status,'unavailable');assert.equal(value.reason,'principal_attribution_unavailable');
});
test('changed schema, malformed descriptors and over-cap/truncated observations fail closed',async()=>{
 for(const entry of [{status:'unmapped',count:0,rows:[]},{status:'observed',count:1,rows:[]},{status:'observed',count:501,rows:Array(501).fill({key_sha256:HASH,row_sha256:HASH})},{status:'observed',count:1,rows:[{key_sha256:'raw-topic',row_sha256:HASH}]}]){const f=fixture(entry),identity=await memberRealtimeRetentionIdentity(f.env);await assert.rejects(inventoryMemberRealtime(f.env,'subject',identity),{code:'privacy_retention_realtime_changed'});}
 const f=fixture(),identity=await memberRealtimeRetentionIdentity(f.env);await assert.rejects(inventoryMemberRealtime(f.env,'subject',{...identity,schema:{...schema,partitions_sha256:'f'.repeat(64)}}),{code:'privacy_retention_realtime_changed'});
});
