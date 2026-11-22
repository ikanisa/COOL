import {registerHooks} from 'node:module';
import assert from 'node:assert/strict';
import {test} from './helpers/fenced-node-test.js';

// Real route, account guard and command/receipt code; synthetic BFF resolution,
// encryption and storage only. This emits SQL but never executes a database.
const accountModule=new URL('../domain/admin_accounts_legacy.js',import.meta.url).href;
const doubles={
 './admin_accounts.js': `export async function handleAdminAccounts(){return null;}
 export function validateAdminOrigin(){}
 export async function adminAccountSession(){return globalThis.__sponsor.account;}
 export async function adminCanonicalActor(){return globalThis.__sponsor.actor;}
 export {accountDatabase,accountReadDatabase} from ${JSON.stringify(accountModule)};
 export async function adminInternalRequest(){throw Error('unrelated internal request');}`,
 './encryption.js': `export async function encrypt(){return 'synthetic-cipher';}
 export async function decrypt(){throw Error('unrelated decrypt');}`,
 './notification_operator.js': `export async function notificationOperatorRoute(){return null;}`,
 './notification_operator_management.js': `export async function notificationOperatorManagementRoute(){return null;}`,
};
registerHooks({resolve(specifier,context,next){
 if(/\/domain\/admin_(?:bridge|operations|record_mutations|request_history|reconciliation)\.js$/.test(context.parentURL)&&Object.hasOwn(doubles,specifier))
  return {url:'data:text/javascript,'+encodeURIComponent(doubles[specifier]),shortCircuit:true};
 return next(specifier,context);
}});
const {handleAdmin}=await import('../domain/admin_bridge.js');
const {attestAdminEmailAccount,bindAdminEmailActor}=await import('../domain/admin_email_policy.js');
const ids={admin:'30000000-0000-4000-8000-000000000001',principal:'30000000-0000-4000-8000-000000000002',session:'30000000-0000-4000-8000-000000000003',auth:'30000000-0000-4000-8000-000000000004',public:'30000000-0000-4000-8000-000000000005',proof:'30000000-0000-4000-8000-000000000006',person:'30000000-0000-4000-8000-000000000007'};
const permissions=['collections.create','collections.manage','receivers.manage','account.manage'];
const reason='Synthetic explicit platform-sponsored group request';
let sequence=0;
function fixture({role='owner',fresh=true}={}){
 const account={id:ids.admin,principal_id:ids.principal,auth_user_id:ids.auth,auth_session_id:ids.session,
  public_id:ids.public,token_hash:'0'.repeat(64),origin:'https://admin.example.invalid',auth_version:1,role,
  permissions:[...permissions],issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null};
 attestAdminEmailAccount(account,{contract_version:1,public_session_id:ids.public,email_verified_at:Math.floor(Date.now()/1000)-(fresh?1:301),proof_id:ids.proof});
 const actor=bindAdminEmailActor({userId:ids.principal,sessionId:ids.session,surface:'admin',assuranceLevel:1,permissions:new Set(permissions)},account);
 const f={account,actor,batches:[],receipt:null,alias:null,currentOwner:true,hideReceipts:false,loseCommit:false};
 f.DB={prepare(sql){return {sql,bind(...args){return {sql,args,async first(){
  if(sql==='SELECT * FROM request_receipts WHERE user_id=? AND request_id=?')return !f.hideReceipts&&f.receipt?.request_id===args[1]?f.receipt:null;
  throw Error('Unexpected synthetic read: '+sql);
 } };} };},async batch(statements){
  f.batches.push(statements);
  for(const s of statements){
   if(s.sql.startsWith('INSERT INTO admin_account_guards')&&!f.currentOwner)throw Error('admin_account_authority');
   if(s.sql.startsWith('INSERT INTO admin_bridge_guards')&&s.sql.includes("member_type!='operator'")&&s.args[1]!==ids.person)throw Error('admin_bridge_state');
  }
  const result=[];
  for(const s of statements){
   if(s.sql.startsWith('INSERT INTO request_receipts(')){
    const [user_id,request_id,operation,session_id,body_sha256,response_json]=s.args;
    f.receipt={user_id,request_id,operation,session_id,body_sha256,response_json};
   }
   if(s.sql.startsWith('INSERT INTO admin_bridge_requests('))f.alias={request_id:s.args[2],operation:s.args[4]};
   const lookup=s.sql.includes('SELECT a.request_id,a.operation,r.response_json FROM admin_bridge_requests');
   result.push({meta:{changes:1},results:lookup&&f.alias?[{...f.alias,response_json:f.receipt?.response_json??null}]:[]});
  }
  if(f.loseCommit&&statements.some(s=>s.sql.startsWith('INSERT INTO collections('))){f.loseCommit=false;f.hideReceipts=true;throw Error('synthetic lost commit acknowledgment');}
  return result;
 }};
 globalThis.__sponsor=f;return f;
}
function body(){return {title:'Synthetic public group',description:'Recorded synthetic purpose',collection_type:'ikimina',category_subtype:'community',purpose_label:'Synthetic savings',
 receiver:{label:'Synthetic route label',network:'mtn_momo',momo_number_or_code:'0001'},visibility:'public_approved',is_platform_sponsored:true,status:'active',reason};}
async function call(f,bodyValue,{key='synthetic-sponsor-'+(++sequence),method='POST',path='/api/admin/operations/groups'}={}){
 const response=await handleAdmin(new Request('https://admin.example.invalid'+path,{method,headers:{'Content-Type':'application/json','Idempotency-Key':key},...(method==='GET'?{}:{body:JSON.stringify(bodyValue)})}),{DB:f.DB},{});
 return {status:response.status,body:await response.json()};
}
function inserts(f,table){return f.batches.flat().filter(s=>s.sql.startsWith(`INSERT INTO ${table}(`));}

test('Owner-sponsored create derives the actual actor and emits no financial membership or person',async()=>{
 const f=fixture(),result=await call(f,body());assert.equal(result.status,200);assert.equal(result.body.resource_type,'groups');assert.equal(result.body.version,1);
 const rows=inserts(f,'collections');assert.equal(rows.length,1);const args=rows[0].args;
 assert.equal(args[2],ids.principal);assert.match(args[1],/^collect-[0-9a-f-]{36}$/);assert.equal(args[6],'0001');assert.equal(args[7],'mtn_momo');assert.equal(args[8],'Synthetic route label');
 assert.equal(args[9],'public_approved');assert.equal(args[10],1);assert.deepEqual(JSON.parse(args[13]),{purpose_label:'Synthetic savings',category_subtype:'community'});
 for(const table of ['memberships','users','payments','ledger_entries','momo_financial_links'])assert.equal(inserts(f,table).length,0,table);
 const guards=inserts(f,'admin_account_guards');assert.ok(guards.length>=2);assert.ok(guards.some(s=>s.args.at(-3)===1));assert.ok(guards.every(s=>s.sql.includes('private.assert_admin_email_context(300)')));
 const owner=inserts(f,'admin_bridge_guards').find(s=>s.sql.includes("a.role='owner'"));assert.ok(owner);assert.deepEqual(owner.args.slice(1),[ids.principal,ids.admin]);
});

test('public flags cannot promote Admin, Staff or an unverified/changed Owner',async()=>{
 for(const role of ['admin','staff']){
  const f=fixture({role}),r=await call(f,body());assert.equal(r.status,403);assert.equal(inserts(f,'collections').length,0);
 }
 let f=fixture({fresh:false}),r=await call(f,body());assert.equal(r.status,403);assert.equal(r.body.error.code,'recent_email_sign_in_required');assert.equal(inserts(f,'collections').length,0);
 f=fixture();f.currentOwner=false;r=await call(f,body());assert.equal(r.status,403);assert.equal(f.receipt,null);
 for(const missing of permissions.slice(0,3)){
  f=fixture();f.actor.permissions.delete(missing);f.account.permissions=f.account.permissions.filter(p=>p!==missing);r=await call(f,body());assert.equal(r.status,403,missing);assert.equal(inserts(f,'collections').length,0);
 }
});

test('ordinary private owners keep strict person validation and their original owner membership',async()=>{
 const f=fixture(),ordinary={title:'Synthetic private group',slug:'synthetic-private',collection_type:'ikimina',owner_user_id:ids.person,
  receiver:{label:'Synthetic person receiver',network:'mtn_momo',momo_number_or_code:'0788123456'},visibility:'private',is_platform_sponsored:false,reason};
 const r=await call(f,ordinary);assert.equal(r.status,200);assert.equal(inserts(f,'collections')[0].args[2],ids.person);assert.equal(inserts(f,'memberships')[0].args[2],ids.person);
 const missing=fixture(),without={...ordinary};delete without.owner_user_id;assert.equal((await call(missing,without)).status,400);assert.equal(inserts(missing,'collections').length,0);
 const operator=fixture(),sponsor=body();delete sponsor.category_subtype;sponsor.owner_user_id=ids.principal;sponsor.slug='synthetic-operator-owner';assert.equal((await call(operator,sponsor)).status,409);assert.equal(operator.receipt,null);
});

test('mismatched public flags, unsupported receivers and authority overposting refuse before create',async()=>{
 for(const change of [{visibility:'private'},{is_platform_sponsored:false},{owner_user_id:null},{creator_user_id:ids.principal},{status:'suspended'}]){
  const f=fixture(),r=await call(f,{...body(),...change});assert.notEqual(r.status,200,JSON.stringify(change));assert.equal(inserts(f,'collections').length,0);
 }
 for(const route of ['00012345678','0001\n']){
  const f=fixture(),b=body();b.receiver.momo_number_or_code=route;assert.equal((await call(f,b)).status,400);assert.equal(inserts(f,'collections').length,0);
 }
});

test('same original key/body returns exactly one canonical receipt; altered input conflicts',async()=>{
 const f=fixture(),b=body(),key='synthetic-exact-sponsor-key';const first=await call(f,b,{key}),again=await call(f,b,{key});
 assert.equal(first.status,200);assert.deepEqual(again,first);assert.equal(inserts(f,'collections').length,1);
 const conflict=await call(f,{...b,title:'Different synthetic title'},{key});assert.equal(conflict.status,409);assert.equal(conflict.body.error.code,'request_conflict');assert.equal(inserts(f,'collections').length,1);
});

test('lost commit acknowledgment is recovered by original GET without another create',async()=>{
 const f=fixture(),key='synthetic-unknown-sponsor-key';f.loseCommit=true;
 const lost=await call(f,body(),{key});assert.notEqual(lost.status,200);assert.equal(inserts(f,'collections').length,1);
 f.hideReceipts=false;
 const outcome=await call(f,null,{method:'GET',path:'/api/admin/operations/requests/'+key});
 assert.equal(outcome.status,200);assert.equal(outcome.body.status,'succeeded');assert.equal(outcome.body.receipt.resource_type,'groups');assert.equal(inserts(f,'collections').length,1);
});
