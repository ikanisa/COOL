import assert from 'node:assert/strict';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import {managedSmsFence} from '../src/fence.ts';
import {ManagedGatewayDatabase} from '../src/database.ts';
import {transact,type Pool} from '../src/transactions.ts';
const SOURCE='a'.repeat(64),PROFILE='b'.repeat(64);
function fakePool(options:{wrongRole?:boolean;commitLost?:boolean;rollbackLost?:boolean;registerCommitLost?:boolean;closeCommitLost?:boolean;principalId?:string;allowedKinds?:string;scopes?:string}={}){
 let sequence=0,active:any=null,mutationCount=0;const records:any[]=[],releases:number[]=[];
 const pool={async reserve(){const id=++sequence;let role='collect_sms_edge',verified=false,begun=false,mutated=false,registered=false,closed=false;
  return {async unsafe(sql:string,values:unknown[]=[],opts:any={}){
   records.push({id,sql,values,opts});assert.equal(opts.prepare,true);assert.equal(opts.simple,false);
   if(sql.startsWith('BEGIN')){begun=true;role='collect_sms_edge';verified=false;return [];}
   assert.ok(begun);
   if(sql.includes('AS login_name'))return [{login_name:options.wrongRole?'wrong':'collect_sms_edge',active_name:'collect_sms_edge',login_safe:true,role_safe:true,other_memberships:0,private_usage:false,app_usage:false,public_create:false,database_create:false}];
   if(sql==='SET LOCAL ROLE collect_sms_runtime'){role='collect_sms_runtime';return [];}
   if(sql.includes("set_config('collect.sms_verified'")){verified=true;return [];}
   if(sql.includes('AS active_name')&&sql.includes('sms_usage'))return [{active_name:role,verified:verified?'true':'false',sms_usage:true,sms_create:false,app_usage:false,private_usage:false}];
   if(sql.includes('FROM collect_sms.applications WHERE token_hash='))return [{application_id:options.principalId??'alpha',allowed_kinds:options.allowedKinds??'[\"receipt\"]',scopes:options.scopes??'[\"messages:read\",\"messages:write\"]'}];
   if(sql.includes('collect_sms.work_register')){registered=true;active={contractVersion:1,admissionId:values[0],epoch:1,sourceSha256:values[1],kind:values[2],state:'active',mode:'open'};return [{result:active}];}
   if(sql.includes('collect_sms.work_assert_write'))return [{result:{contractVersion:1,epoch:1,mode:'open'}}];
   if(sql.includes('collect_sms.work_assert('))return [{result:active}];
   if(sql.includes('collect_sms.work_close')){closed=true;active={...active,state:values[3],reason:values[4],externalDispatches:values[5],uncertainDispatches:values[6]};return [{result:active}];}
   if(sql.includes('collect_sms.work_status'))return [{result:{...active,found:true}}];
   if(sql.startsWith('INSERT INTO messages')){mutationCount++;mutated=true;return Object.assign([],{count:1});}
   if(sql==='COMMIT'){if((options.commitLost&&mutated)||(options.registerCommitLost&&registered)||(options.closeCommitLost&&closed))throw Error('lost commit ack');begun=false;return [];}
   if(sql==='ROLLBACK'){if(options.rollbackLost)throw Error('lost rollback ack');begun=false;return [];}
   return [];
  },release(){releases.push(id);}};},async end(){}} as Pool;
 return {pool,records,releases,get mutationCount(){return mutationCount;}};
}
Deno.test('fresh backend transactions re-establish role, GUC and admission before every query',async()=>{
 const f=fakePool(),backend=managedSmsFence(f.pool,PROFILE),work=await (openApplicationWork as any)({backend,sourceSha256:SOURCE,kind:'http_collect'});
 const db=new ManagedGatewayDatabase(f.pool).withApplicationWork(work,{tokenHash:'c'.repeat(64),scope:'messages:write'});
 await db.prepare('INSERT INTO messages(application_id,kind,text) VALUES(?,?,?)').bind('alpha','receipt','fixture').run();
 await db.prepare('INSERT INTO messages(application_id,kind,text) VALUES(?,?,?)').bind('alpha','receipt','fixture2').run();
 assert.equal((await work.finish()).state,'settled');
 const groups=Map.groupBy(f.records,x=>x.id),mutations=[...groups.values()].filter(v=>v.some(x=>x.sql.startsWith('INSERT INTO messages')));
 assert.equal(mutations.length,2);assert.notEqual(mutations[0][0].id,mutations[1][0].id);
 for(const items of mutations){const text=items.map(x=>x.sql);assert.equal(text[0],'BEGIN ISOLATION LEVEL READ COMMITTED');assert.ok(text.indexOf('SET LOCAL ROLE collect_sms_runtime')<text.findIndex(x=>x.includes('collect.fence_admission_id')));assert.ok(text.findIndex(x=>x.includes('work_assert_write'))<text.findIndex(x=>x.startsWith('INSERT INTO messages')));assert.equal(text.at(-1),'COMMIT');}
 const lease=[...groups.values()].find(v=>v.some(x=>x.sql.includes('pg_advisory_xact_lock_shared(7346371,1)')))!;
 assert.ok(lease.filter(x=>x.sql.includes('collect_sms.work_assert(')).length>=2);assert.equal(lease.at(-1).sql,'ROLLBACK');
});
Deno.test('wrong login fails before operation and rolls back',async()=>{const f=fakePool({wrongRole:true});let called=false;await assert.rejects(transact(f.pool,async()=>{called=true;}));assert.equal(called,false);assert.equal(f.records.at(-1).sql,'ROLLBACK');assert.equal(f.releases.length,1);});
Deno.test('lost COMMIT acknowledgement is not retried, rolled back or recycled',async()=>{
 const f=fakePool({commitLost:true}),backend=managedSmsFence(f.pool,PROFILE),work=await (openApplicationWork as any)({backend,sourceSha256:SOURCE,kind:'http_collect'});
 const db=new ManagedGatewayDatabase(f.pool).withApplicationWork(work,{tokenHash:'c'.repeat(64),scope:'messages:write'});await assert.rejects(db.prepare('INSERT INTO messages(application_id,kind,text) VALUES(?,?,?)').bind('alpha','receipt','fixture').run());
 const id=f.records.find(x=>x.sql==='INSERT INTO messages(application_id,kind,text) VALUES($1,$2,$3)').id,statements=f.records.filter(x=>x.id===id).map(x=>x.sql);
 assert.equal(f.mutationCount,1);assert.equal(statements.filter(x=>x==='COMMIT').length,1);assert.equal(statements.includes('ROLLBACK'),false);assert.equal(f.releases.includes(id),false);
 const done=await work.finish();assert.equal(done.state,'unresolved');assert.equal(done.applicationWorkFinished,false);
});
Deno.test('lost rollback acknowledgement quarantines the transaction',async()=>{const f=fakePool({wrongRole:true,rollbackLost:true});await assert.rejects(transact(f.pool,async()=>{}));assert.equal(f.releases.length,0);});

Deno.test('lost registration acknowledgement is not reissued or recycled',async()=>{
 const f=fakePool({registerCommitLost:true}),backend=managedSmsFence(f.pool,PROFILE);
 await assert.rejects((openApplicationWork as any)({backend,sourceSha256:SOURCE,kind:'http_collect'}));
 const registration=f.records.filter(x=>x.sql.includes('collect_sms.work_register'));assert.equal(registration.length,1);
 const id=registration[0].id,statements=f.records.filter(x=>x.id===id).map(x=>x.sql);assert.equal(statements.filter(x=>x==='COMMIT').length,1);assert.equal(statements.includes('ROLLBACK'),false);assert.equal(f.releases.includes(id),false);
});
Deno.test('lost close acknowledgement is reconciled from original status without closing twice',async()=>{
 const f=fakePool({closeCommitLost:true}),backend=managedSmsFence(f.pool,PROFILE),work=await (openApplicationWork as any)({backend,sourceSha256:SOURCE,kind:'http_collect'});
 const result=await work.finish();assert.equal(result.state,'settled');assert.equal(f.records.filter(x=>x.sql.includes('collect_sms.work_close')).length,1);assert.equal(f.records.filter(x=>x.sql.includes('collect_sms.work_status')).length,1);
});

Deno.test('empty identity, missing receipt kind and missing scope are denied with a confirmed rollback',async()=>{
 for(const option of [{principalId:''},{allowedKinds:'["operation"]'},{scopes:'["messages:read"]'}]){
  const f=fakePool(option),backend=managedSmsFence(f.pool,PROFILE),work=await (openApplicationWork as any)({backend,sourceSha256:SOURCE,kind:'http_collect'});
  const db=new ManagedGatewayDatabase(f.pool).withApplicationWork(work,{tokenHash:'c'.repeat(64),scope:'messages:write'});
  await assert.rejects(db.prepare('INSERT INTO messages(application_id,kind,text) VALUES(?,?,?)').bind('alpha','receipt','fixture').run());
  assert.equal(f.mutationCount,0);assert.equal((await work.finish({failed:true})).state,'settled');
 }
});
