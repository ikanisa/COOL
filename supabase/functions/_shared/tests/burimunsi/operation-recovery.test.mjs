import test from 'node:test';import assert from 'node:assert/strict';
import {projectRecoveredOutcome,requireOriginDigest,OPERATION_RECOVERY_PROTOCOL} from '../../domain/burimunsi/operation-recovery.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
const uuid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const originDigest='a'.repeat(64),groupId='group-1',requestId=uuid(8),now=1794132000000;
const actor={id:uuid(1),sessionId:uuid(3),principalUserId:'principal-1',installationId:uuid(4),groupId,
 role:'staff',active:true,revoked:false,expiresAt:now+60000,capabilities:['records.read']};
function evidence(){
 const current={sessionId:actor.sessionId,actorId:actor.id,groupId,principalUserId:actor.principalUserId,
 installationId:actor.installationId,grantId:uuid(5),grantVersion:1};
 const origin={...current,sessionId:uuid(2),tokenHash:originDigest,createdAt:now-60000};
 return {origin,current,receipt:{groupId,actorId:actor.id,requestId,sessionId:origin.sessionId,operation:'burimunsi.allocate',createdAt:now-1000}};
}
const result=(proof=evidence(),current=actor)=>projectRecoveredOutcome({proof,actor:current,groupId,requestId,originDigest,now});
test('renewed session may read the original committed result',()=>{const v=result();assert.equal(v.state,'committed');assert.equal(v.protocol,OPERATION_RECOVERY_PROTOCOL);assert.equal(v.requestId,requestId)});
test('expired or revoked original session is historical evidence only',()=>{const p=evidence();p.origin.revoked=true;p.origin.expiresAt=now-50000;assert.equal(result(p).state,'committed')});
test('same original session also qualifies',()=>{const p=evidence();p.origin.sessionId=actor.sessionId;p.receipt.sessionId=actor.sessionId;assert.equal(result(p).state,'committed')});
test('no receipt means pending, never rejection',()=>{const p=evidence();p.receipt=null;assert.equal(result(p).state,'pending')});
test('strict public projection does not return private internals',()=>{const p=evidence();p.origin.pin='2468';p.receipt.response={secret:true};assert.deepEqual(Object.keys(result(p)).sort(),['protocol','requestId','state','originDigest','groupId','actorId','installationId'].sort());assert(!JSON.stringify(result(p)).includes('2468'))});
for(const field of ['groupId','actorId','principalUserId','installationId','grantId','grantVersion'])test('original '+field+' must match current identity',()=>{const p=evidence();p.origin[field]=field==='grantVersion'?2:['groupId','principalUserId'].includes(field)?'other':uuid(99);assert.throws(()=>result(p))});
for(const field of ['sessionId','groupId','actorId','principalUserId','installationId'])test('current '+field+' must match trusted fresh actor',()=>{const p=evidence();p.current[field]=['sessionId','actorId','installationId'].includes(field)?uuid(99):'other';assert.throws(()=>result(p))});
for(const [name,change] of [
 ['missing origin',p=>p.origin=null],['missing current',p=>p.current=null],['wrong digest',p=>p.origin.tokenHash='b'.repeat(64)],
 ['fractional grant version',p=>p.origin.grantVersion=1.5],['future origin',p=>p.origin.createdAt=now+1],
 ['negative creation time',p=>p.origin.createdAt=-1],['absent original principal',p=>delete p.origin.principalUserId],['fractional time',p=>p.origin.createdAt=now-0.5]
])test(name+' fails without backfilling identity',()=>{const p=evidence();change(p);assert.throws(()=>result(p))});
for(const field of ['groupId','actorId','requestId','sessionId'])test('receipt '+field+' is origin-bound',()=>{const p=evidence();p.receipt[field]=field==='groupId'?'other':uuid(77);assert.throws(()=>result(p),/invalid_recovery_receipt/)});
for(const [field,value] of [['operation','burimunsi.gateway.replace'],['operation','made_up'],['createdAt',now+1],['createdAt',now-60001],['createdAt','today']])test('receipt rejects '+field+'='+value,()=>{const p=evidence();p.receipt[field]=value;assert.throws(()=>result(p),/invalid_recovery_receipt/)});
for(const value of [null,undefined,'','a'.repeat(63),'b'.repeat(65),'A'.repeat(64),'../x'])test('invalid origin selector '+String(value).slice(0,8),()=>assert.throws(()=>requireOriginDigest(value),/invalid_recovery_origin/));
function fixture(){
 const data={actor:structuredClone(actor),proof:evidence(),reads:0};
 const tx={reloadActor:async()=>data.actor,loadBinding:async()=>null,readRecoveryOutcome:async input=>{data.reads++;assert.equal(input.currentSessionId,actor.sessionId);assert.equal(input.originDigest,originDigest);return data.proof}};
 return {data,service:new RecordsService({store:{withReadSnapshot:fn=>fn(tx),withCommandSnapshot:fn=>fn(tx)},groupId,cursor:{create:async()=>'',read:async()=>{}},clock:()=>now})};
}
test('fresh records.read required, not mutation or SMS capability',async()=>{const{service}=fixture();assert.equal((await service.recoverCommandStatus(actor,requestId,originDigest)).state,'committed')});
for(const [name,patch] of [['revoked',{revoked:true}],['disabled',{active:false}],['expired',{expiresAt:now}],['wrong group',{groupId:'other'}],['no capability',{capabilities:[]}],['operator replaced',{id:uuid(30)}],['session replaced',{sessionId:uuid(40)}]])test(name+' denied before evidence read',async()=>{const{service,data}=fixture();Object.assign(data.actor,patch);await assert.rejects(service.recoverCommandStatus(actor,requestId,originDigest));assert.equal(data.reads,0)});
test('missing original row leaves recovery unavailable',async()=>{const{service,data}=fixture();data.proof=null;await assert.rejects(service.recoverCommandStatus(actor,requestId,originDigest),/operation_recovery_unavailable/)});
function handler(){const f=fixture();return {...f,h:createNativeHandler({auth:{login:async()=>{},authenticate:async()=>f.data.actor,logout:async()=>{},changePasscode:async()=>{},manageStaff:async()=>{throw Error('no mutation')}},records:f.service,contributions:{allocate:async()=>{throw Error('no mutation')}},members:{enroll:async()=>{},setActive:async()=>{}},gateway:{status:async()=>{},replace:async()=>{}},origin:'https://example.test',networkBucket:async()=>''})};}
function req({query='',digest=originDigest,method='GET'}={}){const headers={authorization:'Bearer '+'c'.repeat(64),'x-burimunsi-installation':actor.installationId};if(digest!==null)headers['x-burimunsi-operation-origin']=digest;return new Request(`https://example.test/v1/burimunsi/operations/${requestId}/recovery${query}`,{method,headers});}
test('HTTP recovery route returns no-store evidence',async()=>{const{h}=handler();const r=await h(req());assert.equal(r.status,200);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal((await r.json()).data.protocol,OPERATION_RECOVERY_PROTOCOL)});
for(const query of ['?originDigest='+originDigest,'?actorId='+actor.id,'?groupId=group-1'])test('query identity is refused '+query.slice(0,14),async()=>{const{h,data}=handler();assert.equal((await h(req({query}))).status,400);assert.equal(data.reads,0)});
test('original digest header is mandatory',async()=>{const{h,data}=handler();assert.equal((await h(req({digest:null}))).status,400);assert.equal(data.reads,0)});
test('POST cannot execute through recovery route',async()=>{const{h,data}=handler();assert.equal((await h(req({method:'POST'}))).status,404);assert.equal(data.reads,0)});
function databaseFixture(){
 const p=evidence(),calls=[],data={originRows:1,receiptRows:1};
 const map={sessionId:'session_id',actorId:'actor_id',groupId:'group_id',principalUserId:'principal_id',installationId:'installation_id',grantId:'grant_id',grantVersion:'grant_version',tokenHash:'token_hash',createdAt:'created_at'};
 const sql={unsafe:async(q,params)=>{calls.push({q,params});if(q.includes('FROM private.burimunsi_sessions c')){const row={};for(const[k,v]of Object.entries(p.origin))row['origin_'+map[k]]=v;for(const[k,v]of Object.entries(p.current))row['current_'+map[k]]=v;return Array.from({length:data.originRows},()=>row)}return Array.from({length:data.receiptRows},()=>({collection_id:groupId,actor_id:actor.id,request_id:requestId,session_id:p.origin.sessionId,operation:p.receipt.operation,created_at:p.receipt.createdAt}))}};
 const store=new PostgresRecordsStore({authority:{groupId,read:fn=>fn(sql),session:async()=>actor},sourceReader:{revision:async()=>'',page:async()=>{},detail:async()=>{}},clock:()=>now});
 return {calls,data,read:(g=groupId)=>store.withReadSnapshot(tx=>tx.readRecoveryOutcome({groupId:g,actorId:actor.id,currentSessionId:actor.sessionId,requestId,originDigest}))};
}
test('SQL adapter uses immutable scoped sessions and receipts without mutation or response disclosure',async()=>{const{calls,read}=databaseFixture();assert.equal(result(await read()).state,'committed');assert.equal(calls.length,2);assert.deepEqual(calls[0].params,[groupId,actor.id,actor.sessionId,originDigest]);assert.deepEqual(calls[1].params,[groupId,actor.id,requestId]);assert.match(calls[0].q,/o\.principal_user_id AS origin_principal_id/);assert.match(calls[0].q,/o\.grant_version AS origin_grant_version/);for(const{q}of calls)assert.doesNotMatch(q,/UPDATE|DELETE|INSERT|pin_hash|private\.burimunsi_accounts/i);assert.match(calls[1].q,/response='{}'::jsonb ELSE NULL END AS cancellation_marker_valid/)});
test('SQL wrong group refused before query',async()=>{const{calls,read}=databaseFixture();await assert.rejects(read('other'));assert.equal(calls.length,0)});
test('SQL duplicated origin refuses',async()=>{const{data,read}=databaseFixture();data.originRows=2;await assert.rejects(read(),/invalid_recovery_proof/)});
test('SQL duplicated receipt refuses',async()=>{const{data,read}=databaseFixture();data.receiptRows=2;await assert.rejects(read(),/invalid_recovery_receipt/)});
test('SQL missing receipt is pending',async()=>{const{data,read}=databaseFixture();data.receiptRows=0;assert.equal(result(await read()).state,'pending')});
test('SQL missing original does not search arbitrary receipt',async()=>{const{data,calls,read}=databaseFixture();data.originRows=0;assert.equal(await read(),null);assert.equal(calls.length,1)});
