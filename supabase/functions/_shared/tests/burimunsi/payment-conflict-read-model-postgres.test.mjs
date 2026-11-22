// Optional read-only PostgreSQL qualification: all source tables are replaced
// by synthetic CTEs, so no live customer or ledger data is read or changed.
import test from 'node:test';
import assert from 'node:assert/strict';
import {loadBuriPostgresFixture} from './postgres-fixture.mjs';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';

const fixture=loadBuriPostgresFixture();
test('conflicting sources disappear from unallocated counts and change the page revision', {skip:!fixture},async()=>{
 const queries=[];const sql={unsafe:async(q)=>{queries.push(q);
  if(q.startsWith('SELECT count(*) AS total'))return [{total:0}];
  if(q.startsWith('SELECT coalesce(sum(amount_minor)'))return [{balance:0}];
  if(q.startsWith('SELECT coalesce(sum(c.credited_amount)'))return [{today:0}];
  if(q.includes(' AS unallocated_amount'))return [{members:0,unallocated:0,unallocated_amount:0}];
  return [];
 }};
 const store=new PostgresRecordsStore({authority:{groupId:'group',read:fn=>fn(sql),session:async()=>null},
  sourceReader:{revision:async()=>'',page:async()=>null,detail:async()=>null}});
 await store.withReadSnapshot(async tx=>{
  await tx.readPage({groupId:'group',kind:'payments',memberId:null,q:'',filter:'unallocated',limit:40,after:null});
  await tx.listRevision('group','payments',null);
  await tx.canonicalHome('group');
 });
 const count=queries.find(q=>q.startsWith('SELECT count(*) AS total'));
 const revision=queries.find(q=>q.startsWith('SELECT t.id,t.version,t.has_conflict'));
 const home=queries.find(q=>q.includes(' AS unallocated_amount'));
 assert.ok(count&&revision&&home);
 const tables={
  'private.burimunsi_transaction_scopes':{columns:'collection_id text,transaction_id text,receiving_account_id text',rows:[{collection_id:'group',transaction_id:'tx',receiving_account_id:'wallet'}]},
  'app.momo_transactions':{columns:'id text,receiving_account_id text,payer_name text,payer_identifier text,amount_minor bigint,transaction_at text,transaction_timezone text,transaction_datetime_raw text,provider_transaction_id text,allocation_state text,has_conflict integer,version bigint,created_at text,event_kind text',rows:[{id:'tx',receiving_account_id:'wallet',payer_name:'Synthetic Payer',payer_identifier:'+250780000001',amount_minor:100,transaction_at:'2026-11-13T08:00:00.000Z',transaction_timezone:'Africa/Kigali',transaction_datetime_raw:'synthetic',provider_transaction_id:'ref',allocation_state:'unallocated',has_conflict:0,version:1,created_at:'synthetic',event_kind:'incoming_receipt'}]},
  'app.momo_financial_links':{columns:'transaction_id text,payment_id text,beneficiary_member_id text',rows:[]},
  'app.payments':{columns:'id text,collection_id text,status text,amount_minor bigint,evidence_id text,member_id text,revision bigint',rows:[]},
  'app.memberships':{columns:'id text,collection_id text,user_id text,revision bigint,active bigint',rows:[]},
  'app.users':{columns:'id text,full_name text,momo_number text,phone text,revision bigint',rows:[]},
  'app.ledger_entries':{columns:'id text,payment_id text,collection_id text,kind text,amount_minor bigint,evidence_id text,member_id text',rows:[]},
 };
 function prepared(name,base,relation,source,query,types,args){
  let body=query;const definitions=[];
  const fixtures={...tables,'app.momo_transaction_sources':{columns:'transaction_id text,raw_sms_id text,relation text',rows:[{transaction_id:source,raw_sms_id:'source',relation}]}};
  for(const [table,f]of Object.entries(fixtures)){
   const alias=`fixture_${definitions.length}`,data=JSON.stringify(f.rows).replaceAll("'","''");
   definitions.push(`${alias} AS (SELECT * FROM jsonb_to_recordset('${data}'::jsonb) AS rows(${f.columns}))`);
   body=body.replaceAll(table,alias);
  }
  if(base==='revision')body=`SELECT conflict_count FROM (${body}) result`;
  if(base==='home')body=`SELECT unallocated,unallocated_amount FROM (${body}) result`;
  return `PREPARE ${name}(${types}) AS WITH ${definitions.join(',')} ${body}; EXECUTE ${name}(${args});`;
 }
 let statement='BEGIN READ ONLY;';
 for(const [i,relation,source]of [[0,'duplicate','tx'],[1,'conflict','tx'],[2,'conflict','another']]){
  statement+=prepared(`count_${i}`,'count',relation,source,count,'text,text',"'group','%%'");
  statement+=prepared(`revision_${i}`,'revision',relation,source,revision,'text',"'group'");
  statement+=prepared(`home_${i}`,'home',relation,source,home,'text',"'group'");
 }
 statement+='ROLLBACK;';
 const child=fixture.run('postgres',['-Atq'],statement);
 assert.equal(child.status,0,child.stderr);
 assert.deepEqual(child.stdout.trim().split('\n'),['1','0','1|100','0','1','0|0','1','0','1|100']);
});
