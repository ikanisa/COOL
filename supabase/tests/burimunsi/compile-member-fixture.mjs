// SQL-only native qualification. No connection, provider, Auth exchange or
// application admission is fabricated by this compiler. The Python harness
// supplies real SQL fence registration/lease and explicit Auth fixture rows.
import {registerHooks} from 'node:module';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("SQL compilation only")}',shortCircuit:true};
 return next(specifier,context);
}});
const {compileSql}=await import('../../functions/_shared/postgres.js');
const {personInsertStatement,membershipWriteStatement}=await import('../../functions/_shared/domain/canonical_people.js');
const {auditStatement}=await import('../../functions/_shared/domain/core.js');
const {PostgresCollectMemberCommands}=await import('../../functions/_shared/domain/burimunsi/postgres-collect-members.js');
const groupId='buri-qualification-group',memberId='fa000000-0000-4000-8000-000000000001';
const userId='f3000000-0000-4000-8000-000000000001',sessionId='f2000000-0000-4000-8000-000000000001';
const statements=[];
const db={prepare:sql=>({bind:(...values)=>({sql,values})}),statement:async(sql,statement)=>{statements.push(statement);return {success:true,meta:{changes:1}};}};
const authority={db,groupId,assertOwned:async()=>{},session:()=>{throw Error('No synthetic native login from compiler');}};
const adapter=new PostgresCollectMemberCommands({authority});
const literal=value=>value===null?'NULL':typeof value==='number'&&Number.isSafeInteger(value)?String(value):
 typeof value==='string'?"'"+value.replaceAll("'","''")+"'":(()=>{throw Error('Unexpected fixture parameter');})();
function sql(statement,{clock=false}={}){
 const q=compileSql(statement.sql,statement.values);
 return q.text.replace(/\$(\d+)\b/g,(_,n)=>clock&&Number(n)===4?'app.unixepoch()':literal(q.values[Number(n)-1]))+';';
}
for(const permission of ['users.manage','collections.manage'])await adapter.guard({}, {userId,sessionId,now:0,mfa:null},permission);
const timestamp=new Date().toISOString();
const person=sql(personInsertStatement(db,{id:memberId,name:'QUALIFICATION DIRECT MEMBER',phone:null,email:null,memberType:'direct',
 provider:'',momo:'0789444111',code:'',status:'active',timestamp}));
const membership=sql(membershipWriteStatement(db,{create:true,id:'fa000000-0000-4000-8000-000000000002',groupId,userId:memberId,role:'member',active:1,timestamp}));
const change=sql(membershipWriteStatement(db,{create:false,groupId,userId:memberId,role:'member',active:0}));
const audit=sql(auditStatement({DB:db},{userId,sessionId},'burimunsi.enroll','user',memberId,{collection_id:groupId,qualification_only:true},'fa000000-0000-4000-8000-000000000003'));
const sources={};
for(const name of ['functions/_shared/postgres.js','functions/_shared/application-fence.js','functions/_shared/domain/canonical_people.js',
 'functions/_shared/domain/burimunsi/postgres-collect-members.js','functions/_shared/domain/burimunsi/postgres-managed-actor.js'])
 sources['supabase/'+name]=createHash('sha256').update(await readFile(new URL('../../'+name,import.meta.url))).digest('hex');
process.stdout.write(JSON.stringify({format:'collect.burimunsi.member-sql-fixture.v1',scope:'Actual statement/guard compilation; no database or native-login execution',
 production_acceptance:false,memberId,guards:statements.map(s=>sql(s,{clock:s.sql.startsWith('INSERT')})).join('\n'),person,membership,change,audit,sources})+'\n');
