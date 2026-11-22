// SQL compilation only. Imports current reader exports; no DB, provider, Auth,
// credential or application-work registration occurs in this process.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
const {NATIVE_SOURCE_SQL,NATIVE_CURRENT_BINDING_SQL,NATIVE_METADATA_AUTH_SQL}=
 await import('../../functions/_shared/domain/burimunsi/postgres-source-reader.js');
const parameterize=(sql,names)=>sql.replace(/\$(\d+)\b/g,(_,n)=>{
 const value=names[Number(n)-1];if(!value)throw Error('Unexpected source fixture parameter');return value;
});
function jsonFunction(name,args,query){
 if(!query.startsWith('SELECT ')||query.includes(';'))throw Error('Expected single reader SELECT');
 return `CREATE FUNCTION pg_temp.${name}(${args}) RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $reader$\n`+
  `SELECT to_jsonb(actual_row) FROM (${query}) actual_row\n$reader$;`;
}
const sourceFunctions=[
 jsonFunction('buri_source_rows','p_group text',parameterize(NATIVE_SOURCE_SQL,['p_group'])),
 jsonFunction('buri_current_binding_rows','p_group text,p_installation text',parameterize(NATIVE_CURRENT_BINDING_SQL,['p_group','p_installation'])),
 jsonFunction('buri_metadata_authority_rows','',parameterize(NATIVE_METADATA_AUTH_SQL,[]))
].join('\n');
const sources={};
for(const name of ['supabase/functions/_shared/domain/burimunsi/postgres-source-reader.js',
 'supabase/migrations/20261110030800_burimunsi_sms_source_scope.sql',
 'supabase/tests/burimunsi/compile-source-fixture.mjs',
 'supabase/tests/burimunsi/source-scope-contract.sql'])
 sources[name]=createHash('sha256').update(await readFile(new URL('../../../'+name,import.meta.url))).digest('hex');
process.stdout.write(JSON.stringify({format:'collect.burimunsi.source-sql-fixture.v1',production_acceptance:false,
 scope:'Current source-reader SELECTs and source-scope SQL contract; no SQL/storage/GoTrue execution',
 source_functions:sourceFunctions,sources})+'\n');
