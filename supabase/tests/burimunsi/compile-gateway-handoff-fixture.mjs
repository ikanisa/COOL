// Exact current native Pair SQL compilation only. No DB, credentials, work
// admission, Auth/provider call or actual SQL execution takes place here.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {NATIVE_PIN_PAIR_SQL,NATIVE_PIN_CUSTODY_SQL} from '../../functions/_shared/domain/burimunsi/postgres-collect-gateway.js';
const hash=value=>createHash('sha256').update(value).digest('hex');
function compiled(name,args,sql,names){
 if(!sql.startsWith('SELECT ')||sql.includes(';'))throw Error('Exact single native SELECT required');
 const body=sql.replace(/\$(\d+)\b/g,(_,n)=>{
  const value=names[Number(n)-1];if(!value)throw Error('Unexpected native Pair argument');return value;
 });
 return `CREATE FUNCTION pg_temp.${name}(${args}) RETURNS SETOF jsonb LANGUAGE sql VOLATILE SECURITY INVOKER AS $nativepair$\nSELECT to_jsonb(actual) FROM (${body}) actual\n$nativepair$;`;
}
const native_pair_inputs=[
 compiled('h_native_pair','p_hash text,p_group text,p_installation text',NATIVE_PIN_PAIR_SQL,['p_hash','p_group','p_installation']),
 compiled('h_native_custody','p_group text,p_session text,p_installation text,p_account text',NATIVE_PIN_CUSTODY_SQL,['p_group','p_session','p_installation','p_account'])
].join('\n');
const sources={};
for(const name of ['supabase/functions/_shared/domain/burimunsi/postgres-collect-gateway.js',
 'supabase/functions/_shared/domain/burimunsi/postgres-authority.js','supabase/functions/_shared/domain/burimunsi/phone-pin-request.js',
 'supabase/tests/burimunsi/compile-gateway-handoff-fixture.mjs','supabase/tests/sql/02_financial_authority.sql','supabase/tests/burimunsi/gateway-handoff-support.sql',
 'supabase/tests/burimunsi/gateway-handoff-contract.sql','supabase/tests/burimunsi/gateway-handoff-readonly-contract.sql',
 'supabase/migrations/20261110181003_burimunsi_gateway_handoff.sql'])sources[name]=hash(await readFile(new URL('../../../'+name,import.meta.url)));
process.stdout.write(JSON.stringify({format:'collect.burimunsi.gateway-handoff-sql-fixture.v1',production_acceptance:false,
 scope:'Exact exported native guard/claim/pair SELECT contract on synthetic disposable SQL fixtures, no actual secret delivery',native_pair_inputs,sources})+'\n');
