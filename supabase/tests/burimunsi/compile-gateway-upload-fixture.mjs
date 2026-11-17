// Compilation only: exact production SQL + real AES over synthetic receipt bytes.
// No SQL, Auth user, provider, object upload or application-work registration.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {registerHooks} from 'node:module';
import {encrypt} from '../../functions/_shared/domain/encryption.js';
import {GATEWAY_UPLOAD_AUTHORITY_SQL,GATEWAY_UPLOAD_MATCH_SQL,GATEWAY_UPLOAD_SOURCE_SQL,
 GATEWAY_UPLOAD_READ_SQL,GATEWAY_UPLOAD_SNAPSHOT_FIELDS} from '../../functions/_shared/domain/burimunsi/postgres-gateway-upload.js';
registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("SQL compilation only")}',shortCircuit:true};
 return next(specifier,context);
}});
const {compileSql}=await import('../../functions/_shared/postgres.js');
const hash=value=>createHash('sha256').update(value).digest('hex');
const literal=value=>"'"+String(value).replaceAll("'","''")+"'";
const compile=(sql,names)=>compileSql(sql,names.map(()=>null)).text.replace(/\$(\d+)\b/g,(_,n)=>{
 if(!names[Number(n)-1])throw Error('Unexpected upload fixture parameter');return names[Number(n)-1];
});
const snapshot=field=>`(p_snapshot->>${literal(field)})`+(['grant_id','custodian_account_id'].includes(field)?'::uuid':'');
const current=compile(GATEWAY_UPLOAD_AUTHORITY_SQL,['p_credential','p_hash','p_group']);
const matching=compile('SELECT '+GATEWAY_UPLOAD_MATCH_SQL,['p_snapshot->>\'credential_id\'','p_snapshot->>\'token_sha256\'','p_snapshot->>\'collection_id\'',...GATEWAY_UPLOAD_SNAPSHOT_FIELDS.map(snapshot)]);
const associated=compile('SELECT '+GATEWAY_UPLOAD_SOURCE_SQL,["p_snapshot->>'collection_id'",'p_source',"p_snapshot->>'owner_user_id'",
 "p_snapshot->>'receiving_account_id'","p_snapshot->>'credential_id'","p_snapshot->>'binding_id'","(p_snapshot->>'binding_version')::bigint",
 "p_snapshot->>'installation_id'",'p_body','p_object',"p_snapshot->>'custodian_account_id'","p_snapshot->>'grant_id'",
 "(p_snapshot->>'grant_version')::bigint",'p_subscription','p_identity']);
const lookup=compile(GATEWAY_UPLOAD_READ_SQL,['p_owner','p_envelope']);
const functions=[
 `CREATE FUNCTION pg_temp.upload_authority(p_credential text,p_hash text,p_group text) RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $upload$ SELECT to_jsonb(actual) FROM (${current}) actual $upload$;`,
 `CREATE FUNCTION pg_temp.upload_matches(p_snapshot jsonb) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $upload$ ${matching} $upload$;`,
 `CREATE FUNCTION pg_temp.upload_associated(p_snapshot jsonb,p_source text,p_body text,p_object text,p_subscription bigint,p_identity text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $upload$ ${associated} $upload$;`,
 `CREATE FUNCTION pg_temp.upload_lookup(p_owner text,p_envelope text) RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $upload$ SELECT to_jsonb(actual) FROM (${lookup}) actual $upload$;`,
];
const profile={sender_allowlist:['M-Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],transaction_id_prefixes:['FT Id:'],date_format:'YMD_HMS',utc_offset_minutes:120};
const payload=JSON.stringify({raw_sender:'M-Money',normalized_sender:'M-Money',raw_body:'You have received 1,000 RWF from EXAMPLE PAYER (*****001) at 2026-11-07 12:00:00. Balance: 2,000 RWF. FT Id: 123456789.',
 received_at_device:null,receiver_momo_number:'00000',service_centre_at:null,captured_at:'2026-11-10T00:00:00Z',inbox_received_at:'2026-11-10T00:00:00Z',source_mode:'live',gateway_binding_id:'upload-contract-binding',gateway_binding_version:1,subscription_id:7,completeness:'complete'});
const objectSha=hash(payload),bodySha=hash(JSON.parse(payload).raw_body),identity=hash(payload),inputs={};
const env={DATA_KEY_ID:'qualification-upload-key',DATA_ENCRYPTION_KEY:Buffer.alloc(32,42).toString('base64')};
for(let i=1;i<=5;i++){
 const id='fc910000-0000-4000-8000-'+String(i).padStart(12,'0'),sealed=await encrypt(env,new TextEncoder().encode(payload),`sms:${id}:${objectSha}`);
 inputs[id]={sealed,object_sha256:objectSha,body_sha256:bodySha,identity_sha256:identity,
  ciphertext_sha256:hash(sealed),ciphertext_size:Buffer.byteLength(sealed),plaintext_size:Buffer.byteLength(payload)};
}
functions.push(`SELECT set_config('burimunsi.upload.fixture.inputs',${literal(JSON.stringify(inputs))},true);`,
 `SELECT set_config('burimunsi.upload.fixture.token_hash',${literal(hash(hash('QUALIFICATION ONLY upload gateway token')))},true);`,
 `SELECT set_config('burimunsi.upload.fixture.code_hash',${literal(hash(hash('QUALIFICATION ONLY upload pairing code')))},true);`,
 `SELECT set_config('burimunsi.upload.fixture.profile',${literal(JSON.stringify(profile))},true);`);
const sources={};
for(const name of ['supabase/functions/_shared/gateway-upload-hold.js','supabase/functions/_shared/domain/momo_gateway.js',
 'supabase/functions/_shared/domain/burimunsi/postgres-gateway-upload.js','supabase/functions/_shared/domain/burimunsi/receipt.js',
 'supabase/functions/_shared/domain/burimunsi/postgres-authority.js','supabase/functions/_shared/domain/burimunsi/postgres-gateway-classification.js',
 'supabase/functions/_shared/domain/momo_pipeline.js',
 'supabase/functions/_shared/domain/encryption.js','supabase/functions/_shared/postgres.js',
 'supabase/migrations/20261110030800_burimunsi_sms_source_scope.sql','supabase/migrations/20261110040728_burimunsi_gateway_classification.sql',
 'supabase/tests/burimunsi/operator-seed.sql','supabase/tests/burimunsi/compile-gateway-upload-fixture.mjs','supabase/tests/burimunsi/gateway-upload-contract.sql'])
 sources[name]=hash(await readFile(new URL('../../../'+name,import.meta.url)));
process.stdout.write(JSON.stringify({format:'collect.burimunsi.gateway-upload-sql-fixture.v1',production_acceptance:false,
 scope:'Exact upload authority/match/association SQL and real synthetic AES; no DB, carrier, storage transport, lost-network COMMIT or production acceptance',
 gateway_upload_inputs:functions.join('\n'),sources})+'\n');
