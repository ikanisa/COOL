// Actual production wrapper and retention readers, with transaction I/O doubled.
// Native current16 separately proves the real PostgreSQL context and denial.
import test from 'node:test';
import assert from 'node:assert/strict';
import catalog from '../../../retention-inventory.json' with {type:'json'};
import {privateRetentionCatalogIdentity,inventoryPrivateRetention} from '../private-retention.js';
import {accountDatabase} from '../domain/admin_accounts_legacy.js';
import {attestAdminEmailAccount} from '../domain/admin_email_policy.js';
const HASH='a'.repeat(64),uuid=n=>String(n).padStart(8,'0')+'-1111-4111-8111-111111111111';
function fixture({stale=false,revoked=false}={}){
 const account={id:uuid(1),principal_id:uuid(2),auth_user_id:uuid(3),auth_session_id:uuid(4),public_id:uuid(5),token_hash:HASH,origin:'https://synthetic-admin.example.invalid',auth_version:1,role:'owner',issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null};
 attestAdminEmailAccount(account,{contract_version:1,public_session_id:account.public_id,email_verified_at:Math.floor(Date.now()/1000)-(stale?301:0),proof_id:uuid(6)});
 const schemas=catalog.classes.filter(item=>item.relation.startsWith('private.')).map(item=>({name:item.relation.slice(8),kind:'r',columns:'synthetic',constraints:'synthetic',triggers:'synthetic'})).sort((a,b)=>a.name.localeCompare(b.name));
 const managed={contract_version:1,schema:{fixture:'synthetic-managed-schema'},classes:{'managed:auth':{status:'observed',count:0,rows:[]},'managed:storage':{status:'observed',count:0,rows:[]}}};
 const realtime={contract_version:1,schema:{contract:'collect.member.realtime.inventory.v1',metadata_sha256:HASH,partitions_sha256:HASH},class:{status:'observed',count:0,rows:[],erasure_verified:false}};
 const calls=[],transactions=[];
 const DB={prepare(sql){return {sql,values:[],bind(...values){return {...this,values};},all(){throw Error('UNGUARDED_STANDALONE_INVENTORY_READ');},first(){throw Error('UNGUARDED_STANDALONE_INVENTORY_READ');}};},async batch(statements){
  const transaction=[];transactions.push(transaction);let context=false,guard=false;
  const results=[];for(const item of statements){transaction.push(item.sql);
   if(item.sql.startsWith('SELECT private.set_admin_email_context(')){
    assert.deepEqual(item.values,[account.id,account.token_hash,account.origin,account.public_id]);context=true;results.push({results:[{result:true}]});continue;
   }
   if(item.sql.startsWith('INSERT INTO admin_account_guards')){
    assert(context);assert(item.values.includes('privacy.review'));if(revoked)throw Error('admin_account_authority');guard=true;results.push({results:[]});continue;
   }
   if(item.sql.startsWith('DELETE FROM admin_account_guards')){assert(guard);guard=false;results.push({results:[]});continue;}
   assert(context&&guard,'Each reader must share its current-account/email transaction');calls.push(item);
   const rows=item.sql.includes("n.nspname='private'")?schemas:
    item.sql.startsWith('SELECT private.retention_managed_inventory')?[{inventory:managed}]:
    item.sql.startsWith('SELECT private.retention_member_realtime_inventory')?[{inventory:realtime}]:
    item.sql.includes('pg_get_functiondef')?[{sha256:HASH}]:[];
   results.push({results:rows});
  }assert.equal(guard,false);return results;
 }};
 return {env:accountDatabase({DB},account,'privacy.review',{mfa:true,fresh:true}),calls,transactions};
}
test('shipping wrapper supplies current email/account context to both managed inventory helpers',async()=>{
 const f=fixture();const identity=await privateRetentionCatalogIdentity(f.env),inventory=await inventoryPrivateRetention(f.env,'synthetic-subject');
 assert.equal(identity.schema_profile,'stopped_admission14');assert.equal(inventory.classes['managed:realtime_messages'].status,'observed');
 for(const helper of ['retention_managed_inventory','retention_member_realtime_inventory'])assert(f.calls.some(row=>row.sql.startsWith('SELECT private.'+helper)));
 assert(f.transactions.length>5);assert(f.transactions.every(tx=>tx[0].startsWith('SELECT private.set_admin_email_context(')&&tx[1].startsWith('INSERT INTO admin_account_guards')&&tx.at(-1).startsWith('DELETE FROM admin_account_guards')));
});
test('current grant/session refusal aborts the shipping inventory before reading any rows',async()=>{
 const f=fixture({revoked:true});await assert.rejects(privateRetentionCatalogIdentity(f.env),error=>error.code==='admin_access_changed'&&error.status===403);
 assert.equal(f.calls.length,0);assert.equal(f.transactions.length,1);
});
test('expired email proof cannot start a retention inventory transaction',async()=>{
 const f=fixture({stale:true});await assert.rejects(privateRetentionCatalogIdentity(f.env),error=>error.code==='recent_email_sign_in_required'&&error.status===403);
 assert.equal(f.calls.length,0);assert.equal(f.transactions.length,0);
});
