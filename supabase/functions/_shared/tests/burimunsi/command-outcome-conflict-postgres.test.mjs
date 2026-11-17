// Optional read-only PostgreSQL regression. All records are synthetic CTEs;
// no live application data is read or changed.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {COMMAND_OUTCOME_SQL} from '../../domain/burimunsi/postgres-command-outcome.js';

const context=process.env.BURI_POSTGRES_FIXTURE_CONTEXT;
test('a conflicting cross-source receipt prevents clean financial outcome on PostgreSQL', {skip:!context},()=>{
 const actor='10000000-0000-4000-8000-000000000001',request='30000000-0000-4000-8000-000000000001',session='20000000-0000-4000-8000-000000000001';
 const response={amountRwf:100,currency:'RWF',memberId:'member',transactionId:'transaction',ledgerEntryId:'ledger'};
 const sources={
  'private.burimunsi_command_receipts':{columns:'collection_id text,actor_id uuid,request_id uuid,session_id uuid,operation text,response jsonb',rows:[{collection_id:'group',actor_id:actor,request_id:request,session_id:session,operation:'burimunsi.allocate',response}]},
  'private.burimunsi_sessions':{columns:'id uuid,account_id uuid,collection_id text,principal_user_id text',rows:[{id:session,account_id:actor,collection_id:'group',principal_user_id:'principal'}]},
  'private.burimunsi_scopes':{columns:'collection_id text,receiving_account_id text',rows:[{collection_id:'group',receiving_account_id:'wallet'}]},
  'private.burimunsi_transaction_scopes':{columns:'transaction_id text,collection_id text,receiving_account_id text',rows:[{transaction_id:'transaction',collection_id:'group',receiving_account_id:'wallet'}]},
  'app.momo_transactions':{columns:'id text,receiving_account_id text,event_kind text,has_conflict integer,allocation_state text,currency text,amount_minor bigint',rows:[{id:'transaction',receiving_account_id:'wallet',event_kind:'incoming_receipt',has_conflict:0,allocation_state:'linked',currency:'RWF',amount_minor:100}]},
  'app.momo_financial_links':{columns:'transaction_id text,payment_id text,beneficiary_member_id text',rows:[{transaction_id:'transaction',payment_id:'payment',beneficiary_member_id:'member'}]},
  'app.payments':{columns:'id text,collection_id text,status text,amount_minor bigint,currency text,rail text,member_id text,evidence_id text',rows:[{id:'payment',collection_id:'group',status:'confirmed',amount_minor:100,currency:'RWF',rail:'rwanda_momo',member_id:'member',evidence_id:'evidence'}]},
  'app.ledger_entries':{columns:'id text,payment_id text,collection_id text,member_id text,kind text,evidence_id text,currency text,amount_minor bigint,reverses_entry_id text',rows:[{id:'ledger',payment_id:'payment',collection_id:'group',member_id:'member',kind:'contribution',evidence_id:'evidence',currency:'RWF',amount_minor:100,reverses_entry_id:null}]},
 };
 let sql=COMMAND_OUTCOME_SQL;const fixtures=[];
 for(const [name,f]of Object.entries(sources)){
  const alias=`fixture_${fixtures.length}`,json=JSON.stringify(f.rows).replaceAll("'","''");
  fixtures.push(`${alias} AS (SELECT * FROM jsonb_to_recordset('${json}'::jsonb) AS rows(${f.columns}))`);sql=sql.replaceAll(name,alias);
 }
 sql=sql.replaceAll('app.momo_transaction_sources','fixture_conflict');
 fixtures.push('fixture_conflict AS (SELECT $5::text AS relation,$6::text AS transaction_id)');
 const prefix=`BEGIN READ ONLY; PREPARE outcome(text,uuid,uuid,text,text,text) AS WITH ${fixtures.join(',')} ${sql};`;
 const run=(relation,source)=>`EXECUTE outcome('group','${actor}','${request}','principal','${relation}','${source}');`;
 const child=spawnSync('docker',['--context',context,'exec','-i','supabase_db_local-app','psql','-U','postgres','-d','postgres','-X','-A','-t','-q','-v','ON_ERROR_STOP=1'],
  {input:prefix+run('duplicate','transaction')+run('conflict','other')+run('conflict','transaction')+'ROLLBACK;',encoding:'utf8',maxBuffer:1024*1024});
 assert.equal(child.status,0,child.stderr);
 const states=child.stdout.trim().split('\n').map(row=>row.split('|').at(-1));
 assert.deepEqual(states,['posted','posted','inconsistent']);
});
