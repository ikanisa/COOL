// SQL compilation only. Imports exact current gateway SELECTs; no DB, provider,
// Auth exchange, pairing credential or application-work admission is created.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {registerHooks} from 'node:module';
import {GATEWAY_READ_PERMISSION_SQL,CANONICAL_PAIR_SQL} from '../../functions/_shared/domain/burimunsi/postgres-collect-gateway.js';
import {GATEWAY_CLASSIFICATION_SQL,NON_BURIMUNSI_PAIR_CONDITION} from '../../functions/_shared/domain/burimunsi/postgres-gateway-classification.js';
registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("SQL compilation only")}',shortCircuit:true};
 return next(specifier,context);
}});
const {compileSql}=await import('../../functions/_shared/postgres.js');

const parameterize=(query,names)=>query.replace(/\$(\d+)\b/g,(_,n)=>{
 const value=names[Number(n)-1];if(!value)throw Error('Unexpected gateway fixture parameter');return value;
});
function jsonFunction(name,args,query,volatility){
 if(!/^(?:SELECT |WITH )/.test(query)||query.includes(';'))throw Error('Expected single gateway SELECT');
 if(!['STABLE','VOLATILE'].includes(volatility))throw Error('Unexpected gateway fixture volatility');
 return `CREATE FUNCTION pg_temp.${name}(${args}) RETURNS SETOF jsonb LANGUAGE sql ${volatility} SECURITY INVOKER AS $gateway$\n`+
  `SELECT to_jsonb(actual_row) FROM (${query}) actual_row\n$gateway$;`;
}
// A synthetic canonical-format code is hashed exactly as the production route.
// Only its hash enters SQL; no plaintext pairing code or gateway token is output.
const hash=value=>createHash('sha256').update(value).digest('hex');
const codeHash=hash(hash('QUALIFICATION ONLY BuriMunsi gateway pairing code'));
const gateway_inputs=[
 jsonFunction('buri_gateway_permission_rows','p_principal text,p_session text',
  parameterize(GATEWAY_READ_PERMISSION_SQL,['p_principal','p_session']),'STABLE'),
 // The actual canonical owner-proof view takes row locks. This wrapper preserves
 // those real semantics; it must not pretend to be a read-only health query.
 jsonFunction('buri_gateway_pair_rows','p_hash text,p_group text,p_installation text',
  parameterize(CANONICAL_PAIR_SQL,['p_hash','p_group','p_installation']),'VOLATILE'),
 jsonFunction('buri_gateway_classification_rows','p_hash text',
  parameterize(compileSql(GATEWAY_CLASSIFICATION_SQL,['qualification-placeholder']).text,['p_hash']),'VOLATILE'),
 jsonFunction('buri_gateway_legacy_guard_rows','p_hash text',
  parameterize(compileSql('SELECT ('+NON_BURIMUNSI_PAIR_CONDITION+') AS allowed',['qualification-placeholder']).text,['p_hash']),'VOLATILE'),
 `SELECT set_config('burimunsi.gateway.fixture_code_sha256','${codeHash}',true);`
].join('\n');
const sources={};
for(const name of [
 'supabase/functions/_shared/domain/burimunsi/postgres-collect-gateway.js',
 'supabase/functions/_shared/domain/burimunsi/postgres-authority.js',
 'supabase/functions/_shared/domain/burimunsi/postgres-managed-sessions.js',
 'supabase/functions/_shared/domain/burimunsi/postgres-gateway-classification.js',
 'supabase/functions/_shared/domain/momo_gateway.js',
 'supabase/functions/_shared/postgres.js',
 'integration/burimunsi/gateway-classification/proposal.sql',
 'supabase/migrations/20261020134444_collect_curated_platform_baseline.sql',
 'supabase/migrations/20261023002500_collect_admin_recent_email_source_upgrade.sql',
 'supabase/migrations/20261109234517_burimunsi_native_operator_schema.sql',
 'supabase/migrations/20261110030800_burimunsi_sms_source_scope.sql',
 'supabase/migrations/20261110040728_burimunsi_gateway_classification.sql',
 'supabase/tests/burimunsi/operator-seed.sql',
 'supabase/tests/burimunsi/compile-gateway-fixture.mjs',
 'supabase/tests/burimunsi/gateway-contract.sql'
])sources[name]=hash(await readFile(new URL('../../../'+name,import.meta.url)));
process.stdout.write(JSON.stringify({format:'collect.burimunsi.gateway-sql-fixture.v1',production_acceptance:false,
 scope:'Exact gateway SELECTs over rollback-only synthetic SQL fixtures; no SQL execution, GoTrue, pairing, credential delivery, upload or production acceptance',
 gateway_inputs,sources})+'\n');
