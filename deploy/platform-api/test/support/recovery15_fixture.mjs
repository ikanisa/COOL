// GENERATED SYNTHETIC current15 recovery cohort. Existing populated13 state is
// upgraded with exact14/15, then real scoped pairing/ingestion/parser calls add
// MoMo evidence. No hosted source, real credential, provider send or acceptance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {current13Fixture} from './recovery13_fixture.mjs';
import {captureD1,sha,dataKeys} from './recovery12_fixture.mjs';
import {quarantineSchemaProfiles,momoRecoveryTables} from '../../../../scripts/cloudflare/recovery_quarantine.mjs';
import {momoGatewayRoute} from '../../src/momo_gateway.js';
import {processMomoJob} from '../../src/momo_pipeline.js';
const projectRequire=createRequire(new URL('../../package.json',import.meta.url));
const synthetic=JSON.parse(await readFile(new URL('../fixtures/momo-synthetic.json',import.meta.url)));
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r));return r.body.result??r.body;};
const date=()=>new Date().toISOString();
export async function current15Fixture(t){
 const c=await current13Fixture(t),db=c.f.db,{unstable_splitSqlQuery}=projectRequire(process.env.COLLECT_WRANGLER_MODULE??'wrangler'),profile=quarantineSchemaProfiles.candidate15,migrationBytes={};
 for(const name of ['migrations/0014_momo_pipeline.sql','migrations/0015_momo_gateway_allocation.sql']){const raw=await readFile(new URL('../../'+name,import.meta.url));assert.equal(sha(raw),profile.digests[name]);migrationBytes[name]=raw;await db.batch(unstable_splitSqlQuery(raw.toString()).map(sql=>db.prepare(sql)));}
 const action=(path,data)=>c.f.call('/api/admin/momo/'+path,{cookie:c.operator.cookie,headers:{'Idempotency-Key':randomUUID()},data});
 const account=ok(await action('accounts',{provider:'mtn_momo',public_code:'+250788123456',recipient_name:'SYNTHETIC recovery account only',reason:'Generated local recovery qualification cohort'}));
 ok(await action('accounts/'+account.id+'/profile',{profile:synthetic.profile,profile_version:'SYNTHETIC-recovery15-v1',reason:'Invented local parser fixture only, no provider approval'}));
 const env={DB:db,PRIVATE_MEDIA:c.bucket,...dataKeys,MOMO_PROCESSING_PAUSED:'true'};
 async function enroll(){const binding=ok(await action('bindings',{receiving_account_id:account.id,reason:'Generated isolated gateway recovery authority'})),installation=randomUUID(),pair=ok(await c.f.call('/v1/momo/gateway/pair',{origin:null,data:{pairing_code:binding.pairing_code,installation_id:installation}}));return {binding,pair,installation};}
 const gateway=await enroll(),revoked=await enroll();ok(await action('bindings/'+revoked.binding.binding_id+'/revoke',{reason:'Preexisting revoked authority must remain byte identical'}));
 const unclaimed=ok(await action('bindings',{receiving_account_id:account.id,reason:'Unclaimed positive pairing code must expire at recovery'}));
 async function ingest(label,body=synthetic.body){const capture={client_envelope_id:randomUUID(),raw_sender:synthetic.sender,raw_body:body,gateway_binding_id:gateway.pair.binding.id,gateway_binding_version:gateway.pair.binding.version,service_centre_at:date(),captured_at:date(),inbox_received_at:null,source_mode:'live',subscription_id:null,complete:true};const response=await momoGatewayRoute(new Request('https://api.collect.example/v1/momo/gateway/ingest',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+gateway.pair.gateway_token},body:JSON.stringify(capture)}),env);const reply=await response.json();assert.equal(response.status,200,JSON.stringify(reply));return {label,rawId:reply.receipt.raw_sms_id,capture,reply};}
 const originalBody=synthetic.body.replace('5,000','1,250'),output=structuredClone(synthetic.output);output.principal_amount_raw='1,250';output.evidence.incoming_success=output.evidence.incoming_success.replace('5,000','1,250');output.evidence.principal=output.evidence.principal.replace('5,000','1,250');
 const completed=await ingest('completed',originalBody),parseEnv={...env,MOMO_PROCESSING_PAUSED:'false',AI:{run:async()=>({response:output})}};
 const parsed=await processMomoJob(parseEnv,completed.rawId);assert.equal(parsed.state,'completed');const transactionId=parsed.transaction_id;
 const duplicate=await ingest('duplicate',originalBody);assert.equal((await processMomoJob(parseEnv,duplicate.rawId)).state,'completed');
 const conflictOutput=structuredClone(output);conflictOutput.principal_amount_raw='1,251';conflictOutput.evidence.incoming_success=conflictOutput.evidence.incoming_success.replace('1,250','1,251');conflictOutput.evidence.principal=conflictOutput.evidence.principal.replace('1,250','1,251');
 const conflict=await ingest('conflict',originalBody.replace('1,250','1,251'));await processMomoJob({...parseEnv,AI:{run:async()=>({response:conflictOutput})}},conflict.rawId);
 const jobs={completed:completed.rawId,duplicate:duplicate.rawId,conflict:conflict.rawId};
 for(const [i,state]of ['pending','retry','processing','needs_review'].entries()){const raw=await ingest(state,'SYNTHETIC retained '+state+' raw evidence');jobs[state]=raw.rawId;await db.prepare('UPDATE momo_processing_jobs SET state=?,attempt_count=?,max_attempts=?,available_at=?,lease_token=?,lease_until=?,last_error=? WHERE raw_sms_id=?').bind(state,i,4+i,1700000000+i,state==='processing'?'synthetic-old-lease':null,state==='processing'?1900000000:null,state==='needs_review'?'synthetic_existing_review':'synthetic_existing_error',raw.rawId).run();}
 // Preserve both unmapped history and a reviewed historical source. Their
 // immutable capture rows remain attached to their original credential.
 for(const label of ['source_unresolved','resolved']){const raw=await ingest(label,'SYNTHETIC historical '+label);jobs[label]=raw.rawId;await db.prepare('DELETE FROM momo_processing_jobs WHERE raw_sms_id=?').bind(raw.rawId).run();}
 ok(await action('sources/backfill',{reason:'Generated historical inventory for recovery qualification',limit:100}));
 ok(await action('sources/'+jobs.resolved+'/resolve',{receiving_account_id:account.id,evidence_reference:'SYNTHETIC preserved receiving-account history',reason:'Generated reviewed historical mapping without financial effects'}));
 // Link an already posted1250 contribution as historical evidence, without
 // creating money, intent, notification or a second financial writer.
 const payment=c.payments[0],posted=await db.prepare('SELECT posted_at FROM ledger_entries WHERE id=?').bind(payment.entry).first();
 await db.batch([
  db.prepare('INSERT INTO momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at) VALUES(?,?,?,?,?,1,?)').bind(transactionId,payment.id,c.recipient,c.account.userId,'SYNTHETIC reviewed historical same-amount link',date()),
  db.prepare("UPDATE momo_transactions SET allocation_state='linked' WHERE id=?").bind(transactionId),
  db.prepare('INSERT INTO contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at) VALUES(?,?,1250,1250,?)').bind(payment.entry,payment.id,posted.posted_at),
  db.prepare('INSERT INTO momo_processing_guards(id,passed) VALUES(?,1)').bind('synthetic-restored-transient'),
 ]);
 const counts={...c.counts};for(const name of momoRecoveryTables)counts[name]=(await db.prepare('SELECT count(*) AS n FROM '+name).first()).n;assert.ok(momoRecoveryTables.every(name=>counts[name]>0));
 const sql=await captureD1(db),payload=structuredClone(c.payload),config=JSON.parse(Buffer.from(payload.files['wrangler.json'].base64,'base64')),capturedAt=date(),recoveryAt=new Date(Math.ceil(Date.now()/1000)*1000).toISOString();
 config.synthetic_fixture_provenance.kind='GENERATED synthetic current15 local Miniflare state after exact13-to15 D1 upgrade';payload.captured_at=capturedAt;
 for(const [name,value]of Object.entries({'database.sql':sql,'wrangler.json':JSON.stringify(config),...migrationBytes})){const bytes=Buffer.from(value);payload.files[name]={sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')};}
 const momo={accountId:account.id,transactionId,gateway,revoked,unclaimed,jobs,env,completed,duplicate,conflict,action};
 return {...c,momo,counts,sql,payload,capturedAt,recoveryAt,upgrade15:{migration_sha256:Object.fromEntries(Object.entries(migrationBytes).map(([name,raw])=>[name,sha(raw)])),tables:momoRecoveryTables,actual_provider_source_database_id:null}};
}
