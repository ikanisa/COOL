// QUALIFICATION ONLY. Emits actual route/guard/receipt SQL, never executes SQL,
// creates an Auth session, calls a provider or reads production credentials.
import {registerHooks} from 'node:module';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("No database connection in source compiler");}',shortCircuit:true};
 return next(specifier,context);
}});
const {genericMutation,requestEnvironment,requestId,operatingRead}=await import('../../functions/_shared/domain/admin_bridge.js');
const {accountDatabase}=await import('../../functions/_shared/domain/admin_accounts_legacy.js');
const {attestAdminEmailAccount,bindAdminEmailActor}=await import('../../functions/_shared/domain/admin_email_policy.js');
const {compileSql}=await import('../../functions/_shared/postgres.js');
const {PostgresRecordsStore}=await import('../../functions/_shared/domain/burimunsi/postgres-records-store.js');
const principal='f3000000-0000-4000-8000-000000000001',session='f2000000-0000-4000-8000-000000000001';
const person='fd300000-0000-4000-8000-000000000001';
const permission=['collections.create','collections.manage','receivers.manage','account.manage'];
const literal=value=>value===null?'NULL':typeof value==='string'?"'"+value.replaceAll("'","''")+"'":
 Number.isSafeInteger(value)?String(value):(()=>{throw Error('Unsupported compiled SQL value');})();
function bind(text,values){
 let out='';
 for(let i=0;i<text.length;){
  if(text[i]==="'"||text[i]==='"'){
   const quote=text[i];out+=text[i++];
   while(i<text.length){const c=text[i++];out+=c;if(c===quote){if(text[i]===quote){out+=text[i++];}else break;}}
  }else{
   const match=/^\$(\d+)\b/.exec(text.slice(i));
   if(match){const n=Number(match[1]);if(n<1||n>values.length)throw Error('Missing actual SQL parameter');out+=literal(values[n-1]);i+=match[0].length;}
   else out+=text[i++];
  }
 }
 return out;
}
function account(overrides={}){
 const a={id:'f4000000-0000-4000-8000-000000000001',principal_id:principal,auth_user_id:'f1000000-0000-4000-8000-000000000001',
  auth_session_id:session,public_id:'f5000000-0000-4000-8000-000000000001',token_hash:'a'.repeat(64),origin:'https://admin.collect.example',
  auth_version:1,role:'owner',permissions:permission,issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,...overrides};
 attestAdminEmailAccount(a,{contract_version:1,public_session_id:a.public_id,email_verified_at:Math.floor(Date.now()/1000)-1,proof_id:'fd500000-0000-4000-8000-000000000001'});
 return a;
}
function collector(){
 const state={receipt:null,alias:null,statements:[]};
 state.DB={prepare(sql){return {sql,bind(...args){return {sql,args,async first(){
  if(sql==='SELECT * FROM request_receipts WHERE user_id=? AND request_id=?')return state.receipt?.request_id===args[1]?state.receipt:null;
  throw Error('Unexpected source compiler lookup: '+sql);
 } };} };},async batch(statements){
  const result=[];
  for(const statement of statements){
   const q=compileSql(statement.sql,statement.args??[]);
   state.statements.push({sql:bind(q.text,q.values),kind:statement.sql.startsWith('SELECT a.request_id,a.operation,r.response_json')?'outcome_lookup':'statement'});
   if(statement.sql.startsWith('INSERT INTO request_receipts(')){
    const [user_id,request_id,operation,session_id,body_sha256,response_json]=statement.args;
    state.receipt={user_id,request_id,operation,session_id,body_sha256,response_json};
   }
   if(statement.sql.startsWith('INSERT INTO admin_bridge_requests('))state.alias={request_id:statement.args[2],operation:statement.args[4]};
   const lookup=statement.sql.startsWith('SELECT a.request_id,a.operation,r.response_json');
   result.push({success:true,meta:{changes:1},results:lookup&&state.alias?[{...state.alias,response_json:state.receipt?.response_json??null}]:[]});
  }
  return result;
 }};return state;
}
const cases={},key='qualification-platform-public-original';
const body={title:'QUALIFICATION Sponsored Public',description:'Disposable source-generated sponsored command',collection_type:'ikimina',
 category_subtype:'qualification',purpose_label:'QUALIFICATION ONLY',status:'active',visibility:'public_approved',is_platform_sponsored:true,
 receiver:{label:'QUALIFICATION route label',network:'mtn_momo',momo_number_or_code:'0001'},reason:'Synthetic explicit sponsored public group qualification'};
async function create(name,value,{requestKey=key,retained=null,overrides={}}={}){
 const a=account(overrides),actor=bindAdminEmailActor({userId:principal,sessionId:session,surface:'admin',assuranceLevel:1,permissions:new Set(permission)},a);
 const state=collector();state.receipt=retained;
 const env={DB:state.DB,DATA_KEY_ID:'qualification-public-group',DATA_ENCRYPTION_KEY:Buffer.alloc(32,73).toString('base64')};
 const request=new Request('https://admin.collect.example/api/admin/operations/groups',{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':requestKey},body:JSON.stringify(value)});
 const rid=await requestId(a,requestKey),source={method:'POST',path:'/api/admin/operations/groups',body:value};
 const base=accountDatabase(env,a),scoped=requestEnvironment(base,a,requestKey,rid,'operations.groups.POST',source);
 const result=await genericMutation(request,scoped,a,actor,['groups'],value,rid,source);
 cases[name]={statements:state.statements,result,requestKey,requestId:rid,receipt:state.receipt};return state;
}
const sponsor=await create('sponsor',body);
await create('replay',body,{retained:sponsor.receipt});
// Real race path: a concurrent preflight did not see the original receipt. Its
// same-key/different-body alias guard must reject in the actual PG transaction.
await create('race_conflict',{...body,title:'QUALIFICATION conflicting public title'});
await create('private',{title:'QUALIFICATION Private',slug:'qualification-platform-private',collection_type:'ikimina',
 owner_user_id:person,receiver:{label:'QUALIFICATION private owner',network:'mtn_momo',momo_number_or_code:'0780000003'},
 visibility:'private',is_platform_sponsored:false,reason:'Synthetic ordinary private owner regression'}, {requestKey:'qualification-private-original'});
await create('wrong_cookie',body,{requestKey:'qualification-wrong-cookie',overrides:{token_hash:'c'.repeat(64)}});
const lookup=collector();lookup.receipt=sponsor.receipt;lookup.alias={request_id:cases.sponsor.requestId,operation:'operations.groups.POST'};
const a=account(),actor=bindAdminEmailActor({userId:principal,sessionId:session,surface:'admin',assuranceLevel:1,permissions:new Set(permission)},a);
const url=new URL('https://admin.collect.example/api/admin/operations/requests/'+key);
const outcome=await operatingRead(new Request(url),{DB:lookup.DB},a,['requests',key],url);
cases.lookup={statements:lookup.statements,result:outcome};

// Capture actual Members count/page SQL and empty DTO projection without
// introducing an operator membership or a second hand-authored query.
const nativeSql=[];
const records=new PostgresRecordsStore({authority:{groupId:cases.sponsor.result.resource_id,
 session:async()=>{throw Error('No synthetic native session minted by compiler');},
 read:async fn=>fn({unsafe:async(sql,values)=>{nativeSql.push({sql:bind(sql,values),kind:'native_members'});return sql.startsWith('SELECT count(*)')?[{total:0}]:[];}})},
 sourceReader:{revision:async()=>{},page:async()=>{},detail:async()=>{}}});
const nativeEmpty=await records.withReadSnapshot(ops=>ops.readPage({groupId:cases.sponsor.result.resource_id,kind:'members',q:'',filter:'all',limit:10,after:null}));
cases.native_members={statements:nativeSql,result:nativeEmpty};
const inputs={cases,person,principal,session};
const encoded=literal(JSON.stringify(inputs));
const setup_inputs=`SELECT set_config('collect.platform_public.fixture',${encoded},true);\n`+
 `CREATE FUNCTION pg_temp.platform_public_fixture(p_key text) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $fixture$ SELECT current_setting('collect.platform_public.fixture',true)::jsonb->p_key $fixture$;\n`;
const sources={};
for(const name of ['supabase/functions/_shared/domain/admin_bridge.js','supabase/functions/_shared/domain/admin_accounts_legacy.js',
 'supabase/functions/_shared/domain/admin_operation_fields.js','supabase/functions/_shared/domain/admin_operations.js',
 'supabase/functions/_shared/domain/admin_record_mutations.js','supabase/functions/_shared/domain/admin_request_aliases.js',
 'supabase/functions/_shared/domain/admin_request_history.js',
 'supabase/functions/_shared/domain/admin_email_policy.js','supabase/functions/_shared/domain/mutations.js','supabase/functions/_shared/domain/core.js',
 'supabase/functions/_shared/domain/encryption.js','supabase/functions/_shared/postgres.js','supabase/functions/_shared/domain/burimunsi/postgres-records-store.js',
 'supabase/tests/burimunsi/compile-platform-public-group-fixture.mjs','supabase/tests/burimunsi/platform-public-group-contract.sql'])
 sources[name]=createHash('sha256').update(await readFile(new URL('../../../'+name,import.meta.url))).digest('hex');
process.stdout.write(JSON.stringify({format:'collect.platform-sponsored.sql-fixture.v1',production_acceptance:false,
 scope:'Actual source-generated group/guard/receipt SQL and empty native Members projection only; synthetic existing operator-seed identity, no SQL execution, provider, native session or passcode.',
 setup_inputs,sources})+'\n');
