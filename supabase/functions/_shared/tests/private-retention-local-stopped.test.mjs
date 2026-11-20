import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import catalog from '../../../retention-inventory.json' with {type:'json'};
import {privateRetentionCatalogIdentity,inventoryPrivateRetention,assertPrivateRetentionPolicy} from '../private-retention.js';

const local='collect_fence_local_stopped_admissions';
const className='private:'+local;
const sql=readFileSync(new URL('../../../migrations/20261110181002_collect_local_stopped_admission.sql',import.meta.url),'utf8');
const declaration=sql.match(/CREATE TABLE private\.collect_fence_local_stopped_admissions\(([\s\S]*?)\n\);/)[1];
const columns=declaration.split('\n').flatMap(line=>{
 const found=line.trim().match(/^([a-z_][a-z_0-9]*) (uuid|text|bigint|jsonb|boolean|integer|timestamptz)\b/);
 return found?[`${found[1]}:${found[2]==='timestamptz'?'timestamp with time zone':found[2]}:${/NOT NULL|PRIMARY KEY/.test(line)}`]:[];
}).join(',');
const realtime={contract:'collect.member.realtime.inventory.v1',metadata_sha256:'a'.repeat(64),partitions_sha256:'b'.repeat(64)};
function rows(){return catalog.classes.filter(row=>row.relation.startsWith('private.')).map(row=>({
 name:row.relation.slice(8),kind:row.relation==='private.object_metadata'?'v':'r',
 columns:row.relation==='private.'+local?columns:row.relation==='private.collect_sms_fence_admissions'?
  'admission_id:uuid:true,profile_sha256:text:true,created_at:timestamp with time zone:true':'fixture metadata',constraints:'',triggers:''
})).sort((a,b)=>a.name.localeCompare(b.name));}
function environment(schema){
 const queries=[];
 return {queries,DB:{prepare(query){return{query,args:[],bind(...args){this.args=args;return this;}};},
  async batch(statements){return statements.map(({query})=>{
   queries.push(query);
   if(query.includes("n.nspname='private'"))return{results:schema};
   if(query.includes('private.retention_member_realtime_inventory(?)'))return{results:[{inventory:{contract_version:1,schema:realtime,class:{status:'unavailable',count:0,rows:[]}}}]};
   if(query.includes('private.retention_managed_inventory(?)'))return{results:[{inventory:{contract_version:1,schema:{fixture:true},classes:{
    'managed:auth':{status:'unmapped',count:0,rows:[]},'managed:storage':{status:'unavailable',count:0,rows:[]}
   }}}]};
   if(query.includes('pg_get_functiondef'))return{results:[{sha256:'c'.repeat(64)}]};
   return{results:[]};
  });}
 }};
}

test('local stopped shape derives from proposed SQL and preserves the supported predecessor',async()=>{
 assert.equal(columns.split(',').length,18);
 const current=await privateRetentionCatalogIdentity(environment(rows()));
 assert.match(current.schema_profile,/_local_stopped_v1$/);
 const old=await privateRetentionCatalogIdentity(environment(rows().filter(row=>row.name!==local)));
 assert.doesNotMatch(old.schema_profile,/_local_stopped_v1/);
 assert.notEqual(old.schema_sha256,current.schema_sha256);
});

test('a wrong local shape, missing predecessor or arbitrary extra relation fails closed',async()=>{
 for(const mutate of [
  source=>source.map(row=>row.name===local?{...row,kind:'v'}:row),
  source=>source.map(row=>row.name===local?{...row,columns:row.columns+',invented:text:false'}:row),
  source=>source.filter(row=>row.name!=='collect_fence_stopped_admissions'),
  source=>source.filter(row=>row.name!=='collect_sms_fence_admissions'),
  source=>[...source,{name:'unknown_owner_recovery',kind:'r',columns:'',constraints:'',triggers:''}].sort((a,b)=>a.name.localeCompare(b.name))
 ])await assert.rejects(()=>privateRetentionCatalogIdentity(environment(mutate(rows()))),error=>error.code==='privacy_retention_unknown_private_class');
});

test('personal inventory keeps the local obligation unmapped and never reads global proof rows',async()=>{
 const env=environment(rows());const result=await inventoryPrivateRetention(env,'fixture-principal');
 assert.equal(result.classes[className].status,'unmapped');
 assert.deepEqual(result.classes[className].rows,[]);
 assert.equal(result.external_copy_disposition,'blocked');
 assert.ok(!env.queries.some(query=>query.includes('FROM private.'+local)));
 const identity=await privateRetentionCatalogIdentity(env);
 const policy={copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'},
  rules:Object.fromEntries([...catalog.classes.map(row=>row.name),...catalog.unresolved_external_classes].map(name=>[name,{action:'blocked'}]))};
 assert.doesNotThrow(()=>assertPrivateRetentionPolicy(policy,identity));
 policy.rules[className]={action:'retain'};
 assert.throws(()=>assertPrivateRetentionPolicy(policy,identity),error=>error.code==='privacy_retention_shared_fence_unapproved');
});
