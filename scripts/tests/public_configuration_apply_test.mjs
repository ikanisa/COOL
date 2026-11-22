import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir,mkdtemp,writeFile,chmod,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {PUBLIC_CONFIGURATION_KEYS,RUNTIME_CONFIG_CAPTURE_SQL,SCHEMA_CAPTURE_SQL,createPublicConfigurationPlan,
 inspectPublicConfigurationReadback,parsePublicConfigurationJson,validatePublicConfigurationPlan,main} from '../cloudflare/public_configuration_apply.mjs';
const sha=value=>createHash('sha256').update(value).digest('hex'),clone=value=>JSON.parse(JSON.stringify(value));
const source='a'.repeat(64),at='2026-10-16T06:30:00.000Z';
const target={account_id:'1'.repeat(32),database_name:'controlled-public-configuration',database_id:'11111111-1111-4111-8111-111111111111',api_source_id:source};
const ddl=`CREATE TABLE users(id TEXT PRIMARY KEY) STRICT;
CREATE TABLE runtime_config(key TEXT PRIMARY KEY,value_json TEXT NOT NULL CHECK(json_valid(value_json)),revision INTEGER NOT NULL DEFAULT 1,updated_by TEXT REFERENCES users(id),updated_at TEXT NOT NULL) STRICT;
CREATE TABLE unrelated(id TEXT PRIMARY KEY) STRICT;`;
function payload(){
 const values={get_public_runtime_config:{brand:{display_name:'Controlled',legal_name:'Controlled legal',public_url:'https://example.invalid',admin_url:'https://admin.example.invalid',app_download_url:'https://example.invalid/app',regulatory_footer_note:'Controlled footer'},support_channels:[{key:'support.whatsapp',value:'synthetic-only'},{key:'support.email',value:'support@example.invalid'}]},
  get_collection_type_catalog:{country_code:'RW',locale:'en',types:['ikimina','sport','church','wedding','other'].map(key=>({key,label:key,short_purpose:'Controlled',icon_key:'groups',default_category_subtype:'default',default_purpose_template_key:'default',subtypes:[{key:'default',label:'Default'}],purpose_templates:[{key:'default',label:'Default'}]}))},
  list_account_request_reasons:[{key:'other',label:'Other'}]};
 for(const kind of ['privacy','terms'])values['policy:'+kind]={kind,title:'Controlled '+kind,version:'controlled (draft)',locale:'en',content_status:'draft_for_legal_review',legal_release_approved:false,source_document_sha256:'b'.repeat(64),source_url:'https://example.invalid/'+kind,sections:[{title:'Controlled policy',body:'Synthetic fixture only. Review draft.'}]};
 return {schema_version:1,kind:'collect_public_configuration_seed',api_source_id:source,legal_release_approved:false,provider_approved:false,retention_policy_activation:false,
  source_inputs:{'controlled/source.json':{sha256:'c'.repeat(64),bytes:100}},records:PUBLIC_CONFIGURATION_KEYS.map(key=>({key,value_json:JSON.stringify(values[key])}))};
}
function schema(rows){return {rows,sha256:sha(JSON.stringify(rows))};}
function sqlite(t){const db=new DatabaseSync(':memory:');db.exec(ddl);t.after(()=>db.close());return db;}
function input(db,p=payload()){return {payload:p,target,schema:schema(db.prepare(SCHEMA_CAPTURE_SQL).all()),preimage:{rows:db.prepare(RUNTIME_CONFIG_CAPTURE_SQL).all()},updated_at:at};}
function observed(db){return {target,schema:schema(db.prepare(SCHEMA_CAPTURE_SQL).all()),rows:db.prepare(RUNTIME_CONFIG_CAPTURE_SQL).all()};}
const code=expected=>error=>error.code===expected;

test('one compact bound statement preserves raw JSON and honest bootstrap metadata',t=>{
 const db=sqlite(t),p=payload();p.records[0].value_json=' \n'+p.records[0].value_json+'\n ';
 const plan=createPublicConfigurationPlan(input(db,p));assert.equal(plan.insert.params.length,8);assert.ok(Buffer.byteLength(plan.insert.sql)<100000);
 assert.equal(db.prepare(plan.insert.sql).run(...plan.insert.params).changes,5);
 for(const row of p.records){const actual=db.prepare('SELECT * FROM runtime_config WHERE key=?').get(row.key);assert.equal(actual.value_json,row.value_json);assert.equal(actual.revision,1);assert.equal(actual.updated_by,null);assert.equal(actual.updated_at,at);}
 assert.equal(inspectPublicConfigurationReadback(plan,observed(db)).outcome,'applied_exact');assert.equal(plan.rollback.execute,false);assert.equal(plan.automatic_apply,false);
});
test('SQL-looking Unicode content is bound data and never executed',t=>{
 const db=sqlite(t),p=payload(),row=p.records.find(row=>row.key==='policy:privacy'),value=JSON.parse(row.value_json);value.sections[0].body="Rwanda 🇷🇼 é '); DROP TABLE users; --\nRetained.";row.value_json=JSON.stringify(value);
 db.prepare('INSERT INTO runtime_config VALUES(?,?,1,NULL,?)').run("old'); DROP TABLE runtime_config; --",'{"old":"kept"}','original');
 const plan=createPublicConfigurationPlan(input(db,p));db.prepare(plan.insert.sql).run(...plan.insert.params);assert.equal(db.prepare('SELECT count(*) AS n FROM users').get().n,0);assert.equal(inspectPublicConfigurationReadback(plan,observed(db)).outcome,'applied_exact');
});
test('schema and entire raw preimage are guarded once for all five rows',t=>{
 const db=sqlite(t);db.exec("INSERT INTO runtime_config VALUES('prior','{\"kept\":true}',1,NULL,'old')");const plan=createPublicConfigurationPlan(input(db));db.prepare("UPDATE runtime_config SET value_json=' {\"kept\":true}' WHERE key='prior'").run();
 assert.throws(()=>db.prepare(plan.insert.sql).run(...plan.insert.params),/malformed JSON/);assert.equal(db.prepare('SELECT count(*) AS n FROM runtime_config').get().n,1);
});
test('duplicate acknowledgement resolves by exact readback before any retry',t=>{
 const db=sqlite(t),plan=createPublicConfigurationPlan(input(db));assert.equal(inspectPublicConfigurationReadback(plan,observed(db)).outcome,'not_applied');db.prepare(plan.insert.sql).run(...plan.insert.params);
 assert.equal(inspectPublicConfigurationReadback(plan,observed(db)).outcome,'applied_exact');assert.throws(()=>db.prepare(plan.insert.sql).run(...plan.insert.params),/malformed JSON/);assert.equal(inspectPublicConfigurationReadback(plan,observed(db)).outcome,'applied_exact');
});
test('rollback removes exactly five matching rows and preserves every prior byte',t=>{
 const db=sqlite(t);db.exec("INSERT INTO runtime_config VALUES('prior','{\"kept\":true}',9223372036854775807,NULL,'old')");const plan=createPublicConfigurationPlan(input(db));assert.equal(plan.input.preimage.rows[0].revision,'9223372036854775807');db.prepare(plan.insert.sql).run(...plan.insert.params);
 const removed=db.prepare(plan.rollback.sql).all(...plan.rollback.params).map(row=>row.key).sort();assert.deepEqual(removed,[...PUBLIC_CONFIGURATION_KEYS].sort());assert.equal(inspectPublicConfigurationReadback(plan,observed(db)).outcome,'not_applied');assert.throws(()=>db.prepare(plan.rollback.sql).all(...plan.rollback.params),/malformed JSON/);
});
test('partial and unrelated changes are diagnosed without blind retry',t=>{
 const db=sqlite(t),plan=createPublicConfigurationPlan(input(db)),first=plan.expected_rows[0];db.prepare('INSERT INTO runtime_config VALUES(?,?,?,?,?)').run(first.key,first.value_json,1,null,at);
 const partial=inspectPublicConfigurationReadback(plan,observed(db));assert.equal(partial.outcome,'partial_or_conflicting');assert.equal(partial.public_rows,1);assert.equal(partial.automatic_retry,false);
 assert.throws(()=>db.prepare(plan.insert.sql).run(...plan.insert.params),/malformed JSON/);assert.throws(()=>db.prepare(plan.rollback.sql).all(...plan.rollback.params),/malformed JSON/);assert.equal(db.prepare('SELECT count(*) AS n FROM runtime_config').get().n,1);
});
test('plan tampering cannot retain a valid digest',t=>{const db=sqlite(t),plan=createPublicConfigurationPlan(input(db));const altered=clone(plan);altered.insert.params[3]='{}';assert.throws(()=>validatePublicConfigurationPlan(altered),code('plan_changed'));});
test('foreign/custom record prototypes are refused',t=>{const db=sqlite(t),value=input(db);value.target=Object.assign(Object.create({extra:true}),value.target);assert.throws(()=>createPublicConfigurationPlan(value),code('target_shape'));});
for(const [name,change,expected]of [
 ['missing record',v=>v.payload.records.pop(),'record_count'],['duplicate record',v=>v.payload.records[4]=v.payload.records[0],'record_key'],
 ['retention key',v=>v.payload.records[4].key='privacy:retention:approved:v1','record_key'],['secret key',v=>v.payload.records[4].key='AUTH_JWT_SECRET','record_key'],
 ['approval true',v=>v.payload.legal_release_approved=true,'payload_approval'],['provider true',v=>v.payload.provider_approved=true,'payload_approval'],['retention true',v=>v.payload.retention_policy_activation=true,'payload_approval'],
 ['source mismatch',v=>v.target.api_source_id='d'.repeat(64),'source_mismatch'],['source traversal',v=>v.payload.source_inputs={'../secret':{sha256:'c'.repeat(64),bytes:1}},'source_path'],
 ['wrapped timestamp',v=>v.updated_at='2026-10-16','timestamp'],['actor injection',v=>v.preimage.rows.push({key:'old',value_json:'{}',revision:'1',updated_by:'wrong',updated_at:'old'}),'row_actor'],
 ['lossy revision',v=>v.preimage.rows.push({key:'old',value_json:'{}',revision:9007199254740992,updated_by:null,updated_at:'old'}),'row_revision'],
 ['revision overflow',v=>v.preimage.rows.push({key:'old',value_json:'{}',revision:'9223372036854775808',updated_by:null,updated_at:'old'}),'row_revision'],
 ['unknown payload field',v=>v.payload.approve=true,'payload_shape'],['bad schema hash',v=>v.schema.sha256='f'.repeat(64),'schema_hash'],
 ['duplicate old row',v=>v.preimage.rows=[{key:'old',value_json:'{}',revision:'1',updated_by:null,updated_at:'old'},{key:'old',value_json:'{}',revision:'1',updated_by:null,updated_at:'old'}],'row_order_or_duplicate'],
 ['NUL raw JSON',v=>v.payload.records[0].value_json='\0{}','record_json'],['oversized value',v=>v.payload.records[0].value_json=' '.repeat(256*1024+1),'record_json'],
 ['wrong runtime type',v=>v.payload.records.find(r=>r.key==='get_public_runtime_config').value_json='[]','runtime_type'],
 ['wrong reason type',v=>v.payload.records.find(r=>r.key==='list_account_request_reasons').value_json='{}','reason_options'],
 ['published policy',v=>{const r=v.payload.records.find(r=>r.key==='policy:privacy'),p=JSON.parse(r.value_json);p.content_status='approved';r.value_json=JSON.stringify(p);},'policy_approval'],
])test('input refuses '+name,t=>{const db=sqlite(t),value=clone(input(db));change(value);assert.throws(()=>createPublicConfigurationPlan(value),code(expected));});
for(const [name,raw]of [['top duplicate','{"a":1,"a":2}'],['escaped alias','{"a":1,"\\u0061":2}'],['nested duplicate','{"a":[{"b":1,"b":2}]}'],['surrogate','{"a":"\\ud800"}'],['control','{"a":"\\u0000"}'],['infinite number','{"a":1e309}'],['trailing','{"a":1} {}']])test('strict JSON refuses '+name,()=>assert.throws(()=>parsePublicConfigurationJson(raw)));
test('CLI rejects invalid UTF8 and never creates a plan',async t=>{
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-public-config-utf8-')));t.after(()=>rm(root,{recursive:true,force:true}));const file=join(root,'input.json');await writeFile(file,Buffer.from([0x7b,0xff,0x7d]),{mode:0o600});await chmod(file,0o600);
 await assert.rejects(()=>main(['plan','--input',file,'--out',join(root,'never')]),code('input_utf8'));
});

let runtime;
async function d1(t,{full=false,noCheck=false,lateTrigger=false}={}){
 if(!runtime){
  const require=createRequire(new URL('../../deploy/platform-api/package.json',import.meta.url));
  const mf=await import(process.env.COLLECT_MINIFLARE_MODULE??require.resolve('miniflare'));
  const parser=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler').unstable_splitSqlQuery;
  runtime={...mf,parser};
 }
 const {Miniflare,convertV4MiniflareOptions,parser}=runtime;
 const mf=new Miniflare((convertV4MiniflareOptions??(v=>v))({modules:true,script:'export default {fetch(){return new Response("controlled local test")}}',compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false}));t.after(()=>mf.dispose());const db=await mf.getD1Database('DB');
 if(full){const folder=new URL('../../deploy/platform-api/migrations/',import.meta.url),names=(await readdir(folder)).filter(name=>/^\d+.*\.sql$/.test(name)).sort();assert.ok(names.length>=11);const statements=[];for(const name of names)statements.push(...parser(await readFile(new URL(name,folder),'utf8')));await db.batch(statements.map(sql=>db.prepare(sql)));}
 else for(const sql of parser(noCheck?ddl.replace(' CHECK(json_valid(value_json))',''):ddl))await db.prepare(sql).run();
 if(lateTrigger)await db.prepare("CREATE TRIGGER controlled_late_publication BEFORE INSERT ON runtime_config WHEN NEW.key='policy:terms' BEGIN SELECT RAISE(ABORT,'controlled_late_publication_failure'); END").run();
 await db.prepare("INSERT INTO runtime_config(key,value_json,revision,updated_by,updated_at) VALUES('prior','{\"keep\":true}',9223372036854775807,NULL,'original')").run();
 const capture=async()=>({target,schema:schema((await db.prepare(SCHEMA_CAPTURE_SQL).all()).results),rows:(await db.prepare(RUNTIME_CONFIG_CAPTURE_SQL).all()).results});
 const first=await capture(),plan=createPublicConfigurationPlan({payload:payload(),target,schema:first.schema,preimage:{rows:first.rows},updated_at:at});
 return {db,plan,capture,apply:()=>db.prepare(plan.insert.sql).bind(...plan.insert.params).run(),rollback:()=>db.prepare(plan.rollback.sql).bind(...plan.rollback.params).all()};
}
test('actual D1 current full schema exceeds100KB yet bound five-row insertion is exact',async t=>{
 const h=await d1(t,{full:true});assert.ok(Buffer.byteLength(h.plan.insert.params[0])>100000);assert.ok(Buffer.byteLength(h.plan.insert.sql)<100000);assert.equal(h.plan.insert.params.length,8);
 assert.equal((await h.apply()).meta.changes,5);const after=await h.capture();assert.equal(inspectPublicConfigurationReadback(h.plan,after).outcome,'applied_exact');assert.equal(after.rows.find(row=>row.key==='prior').revision,'9223372036854775807');
 assert.equal((await h.db.prepare('PRAGMA foreign_keys').first()).foreign_keys,1);assert.deepEqual((await h.db.prepare('PRAGMA foreign_key_check').all()).results,[]);
});
for(const [name,sql]of [
 ['raw value whitespace',"UPDATE runtime_config SET value_json=' {\"keep\":true}' WHERE key='prior'"],
 ['old revision',"UPDATE runtime_config SET revision=9223372036854775806 WHERE key='prior'"],
 ['old timestamp',"UPDATE runtime_config SET updated_at='concurrent' WHERE key='prior'"],
 ['unrelated key',"INSERT INTO runtime_config VALUES('concurrent','{}',1,NULL,'concurrent')"],
 ['unrelated schema',"CREATE INDEX controlled_unrelated_schema ON unrelated(id)"],
])test('actual D1 stale guard aborts all rows after '+name,async t=>{
 const h=await d1(t,{noCheck:true});await h.db.prepare(sql).run();const before=(await h.capture()).rows;await assert.rejects(()=>h.apply(),/malformed JSON/);assert.deepEqual((await h.capture()).rows,before);
});
test('actual D1 last-row trigger abort rolls back every earlier public insertion',async t=>{
 const h=await d1(t,{lateTrigger:true}),before=(await h.capture()).rows;await assert.rejects(()=>h.apply(),/controlled_late_publication_failure/);assert.deepEqual((await h.capture()).rows,before);
});
test('actual D1 lost acknowledgement and duplicate attempt resolve through exact readback',async t=>{
 const h=await d1(t);await h.apply();const before=(await h.capture()).rows;assert.equal(inspectPublicConfigurationReadback(h.plan,await h.capture()).outcome,'applied_exact');await assert.rejects(()=>h.apply(),/malformed JSON/);assert.deepEqual((await h.capture()).rows,before);
});
test('actual D1 malformed preimage guard aborts instead of silently selecting zero rows',async t=>{
 const h=await d1(t,{noCheck:true}),params=[...h.plan.insert.params];params[1]='malformed';const before=(await h.capture()).rows;
 await assert.rejects(()=>h.db.prepare(h.plan.insert.sql).bind(...params).run(),/malformed JSON/);assert.deepEqual((await h.capture()).rows,before);
});
test('actual D1 partial prior outcome blocks apply and conditional rollback',async t=>{
 const h=await d1(t),row=h.plan.expected_rows.find(row=>row.key===PUBLIC_CONFIGURATION_KEYS[0]);await h.db.prepare('INSERT INTO runtime_config VALUES(?,?,1,NULL,?)').bind(row.key,row.value_json,at).run();const before=(await h.capture()).rows;
 const result=inspectPublicConfigurationReadback(h.plan,await h.capture());assert.equal(result.outcome,'partial_or_conflicting');assert.equal(result.public_rows,1);await assert.rejects(()=>h.apply(),/malformed JSON/);await assert.rejects(()=>h.rollback(),/malformed JSON/);assert.deepEqual((await h.capture()).rows,before);
});
test('actual D1 rollback is exact and stale rollback never removes changed or prior rows',async t=>{
 const h=await d1(t),before=(await h.capture()).rows;await h.apply();assert.equal((await h.rollback()).results.length,5);assert.deepEqual((await h.capture()).rows,before);await assert.rejects(()=>h.rollback(),/malformed JSON/);
 await h.apply();await h.db.prepare("UPDATE runtime_config SET revision=2 WHERE key='policy:terms'").run();const changed=(await h.capture()).rows;await assert.rejects(()=>h.rollback(),/malformed JSON/);assert.deepEqual((await h.capture()).rows,changed);
});
test('readback distinguishes exact five rows from concurrent unrelated configuration',async t=>{
 const h=await d1(t);await h.apply();await h.db.prepare("INSERT INTO runtime_config VALUES('unrelated_new','{}',1,NULL,'later')").run();const result=inspectPublicConfigurationReadback(h.plan,await h.capture());assert.equal(result.outcome,'applied_rows_present_configuration_changed');assert.equal(result.applied_exact,false);assert.equal(result.automatic_retry,false);
});
