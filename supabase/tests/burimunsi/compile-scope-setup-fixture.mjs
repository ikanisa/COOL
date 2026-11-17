// QUALIFICATION ONLY. Real setup command/custody source with a synthetic DB
// substitute. Emits hashes/ciphertext only; no DB, provider or plaintext code.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {AdminScopeSetup} from '../../functions/_shared/domain/burimunsi/admin-scope-setup.js';
import {canonicalJson,sha256} from '../../functions/_shared/domain/burimunsi/values.js';
const group='buri-qualification-group',wallet='buri-qualification-wallet';
const actor='f3000000-0000-4000-8000-000000000001',session='f2000000-0000-4000-8000-000000000001';
const installation='fe100000-0000-4000-8000-000000000001',grant='fe100000-0000-4000-8000-000000000002';
const custodian='f7000000-0000-4000-8000-000000000001';
const request=n=>'fe600000-0000-4000-8000-'+String(n).padStart(12,'0');
const entries={deviceHash:await sha256(crypto.randomUUID()+crypto.randomUUID()),
 otherDeviceHash:await sha256(crypto.randomUUID()+crypto.randomUUID())};
if(entries.deviceHash===entries.otherDeviceHash)throw Error('Qualification device proofs must be distinct');
let scope={collectionId:group,receivingAccountId:wallet,enabled:false,version:2,bindingId:null,bindingVersion:null,paired:false,
 receiverKeyId:null,receiverInstallationId:null,pendingReplacement:null};
const db={applicationWork:{assert:async()=>{}},prepare:sql=>({bind:(...args)=>({sql,args})}),batch:async([q])=>{
 let result;
 if(q.sql.includes('setup_lookup'))result={contractVersion:1,collectionId:group,requestId:q.args[5],found:false};
 else if(q.sql.includes('setup_directory'))result={contractVersion:1,collections:[{id:group,title:'QUALIFICATION ONLY',version:1}],
  accounts:[{id:wallet,provider:'mtn_momo',publicCode:'00000',recipientName:'QUALIFICATION ONLY'}],
  scopes:[scope],installations:[]};
 else if(q.sql.includes('setup_apply')){
  const command=JSON.parse(q.args[4]),delivery=q.args[6]===null?null:JSON.parse(q.args[6]);
  const fixture=command.requestId===request(4)?'renew':command.requestId===request(5)?'wrongCustodian':command.operation;
  entries[fixture]={command,fingerprint:q.args[5],delivery};
  result={contractVersion:1,requestId:command.requestId,collectionId:group,operation:command.operation,
   receivingAccountId:wallet,scopeVersion:command.expectedScopeVersion+1,enabled:command.operation==='activate',bindingId:delivery?.bindingId??null,
   ...(delivery?{pairingId:delivery.pairingId,bindingVersion:1,installationId:command.installationId,custodianAccountId:command.custodianAccountId,
    grantId:command.grantId,grantVersion:command.expectedGrantVersion,subscriptionId:command.subscriptionId,deliveryExpiresAt:Date.now()+600000}:{})};
  scope={...scope,version:command.expectedScopeVersion+1,bindingId:delivery?.bindingId??null,enabled:command.operation==='activate'};
 }else throw Error('Unexpected source fixture query');
 return [{success:true,results:[{result}]}];
}};
const env={DB:db,DATA_KEY_ID:'qualification-setup-only',DATA_ENCRYPTION_KEY:Buffer.alloc(32,83).toString('base64'),COLLECT_DEPLOYMENT_PROFILE_SHA256:'1'.repeat(64)};
const setup=new AdminScopeSetup({env,actorArgs:['f4000000-0000-4000-8000-000000000001','a'.repeat(64),'https://admin.collect.example',
 'f5000000-0000-4000-8000-000000000001'],actorId:actor,sessionId:session});
await setup.apply({operation:'prepare',requestId:request(1),collectionId:group,expectedScopeVersion:1,receivingAccountId:wallet,reason:'Synthetic setup qualification only'});
// This source-generated handoff has a matching command/AAD tuple. Actual SQL
// must reject its custodian against the approved grant, independently of format.
const preparedScope=scope;
await setup.apply({...entries.prepare.command,operation:'activate',requestId:request(5),expectedScopeVersion:2,
 installationId:installation,grantId:grant,custodianAccountId:'f7000000-0000-4000-8000-000000000002',expectedGrantVersion:1,subscriptionId:7});
scope=preparedScope;
await setup.apply({...entries.prepare.command,operation:'activate',requestId:request(2),expectedScopeVersion:2,
 installationId:installation,grantId:grant,custodianAccountId:custodian,expectedGrantVersion:1,subscriptionId:7});
await setup.apply({...entries.activate.command,requestId:request(4),expectedScopeVersion:3});
entries.cancelRequest=request(3);entries.cancelGroup='buri-unprepared-qualification-group';
entries.cancelPrepare={...entries.prepare.command,requestId:request(3),collectionId:entries.cancelGroup,expectedScopeVersion:0};
entries.cancelFingerprint=await sha256(canonicalJson(entries.cancelPrepare));
const literal=value=>"'"+value.replaceAll("'","''")+"'";
const setup_inputs=`DO $setup_inputs$ BEGIN\n PERFORM set_config('burimunsi.setup.fixture',${literal(JSON.stringify(entries))},true);\nEND;$setup_inputs$;\n`+
 `CREATE FUNCTION pg_temp.setup_fixture(p_key text) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $fixture$\n`+
 ` SELECT current_setting('burimunsi.setup.fixture',true)::jsonb->p_key\n$fixture$;`;
const sources={};
for(const name of ['integration/burimunsi/scope-setup/proposal.sql',
 'supabase/migrations/20261110052756_burimunsi_dynamic_scope_setup.sql',
 'supabase/functions/_shared/domain/burimunsi/admin-scope-setup.js','supabase/functions/_shared/domain/burimunsi/postgres-scope-discovery.js',
 'supabase/functions/_shared/domain/burimunsi/values.js','supabase/functions/_shared/domain/encryption.js',
 'supabase/tests/burimunsi/scope-setup-contract.sql','supabase/tests/burimunsi/compile-scope-setup-fixture.mjs'])
 sources[name]=createHash('sha256').update(await readFile(new URL('../../../'+name,import.meta.url))).digest('hex');
process.stdout.write(JSON.stringify({format:'collect.burimunsi.scope-setup-sql-fixture.v1',production_acceptance:false,
 scope:'Synthetic original-request setup and protected custody/SQL contract; no provider/native installation or plaintext challenge output',setup_inputs,sources})+'\n');
