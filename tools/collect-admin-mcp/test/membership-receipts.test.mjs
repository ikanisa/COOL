import test from 'node:test';
import assert from 'node:assert/strict';
import {callTool,canonicalRequestId} from '../src/tools.mjs';
const P='33333333-3333-4333-8333-333333333333',G='44444444-4444-4444-8444-444444444444',U='55555555-5555-4555-8555-555555555555',K='membership-original-1234';
const M={contract_version:2,model:'canonical_evidence_ledger'};
const receipt=(overrides={})=>({status:'succeeded',request_id:canonicalRequestId(P,K),resource_type:'memberships',resource_id:G+'/'+U,version:1,...overrides});
function fixture(value){const requests=[],permissions=[];return {requests,permissions,api:{config:{origin:'https://platform-admin.collect.ikanisa.com'},withAuthority:async(permission,perform)=>{permissions.push(permission);return perform({user:{principalId:P},get:async(path)=>{requests.push({method:'GET',path});return typeof value==='function'?value(path):value;}});}}};}
const statusValue=r=>({...M,status:'succeeded',request_id:canonicalRequestId(P,K),receipt:r});
const listValue=r=>({...M,total:1,rows:[{id:canonicalRequestId(P,K),idempotency_key:K,status:'succeeded',scope:'memberships.post',receipt:r}]});
const read=async(value,list=false)=>{const f=fixture(value);return {result:await callTool(f.api,list?'collect_admin_list_requests':'collect_admin_get_request_status',list?{limit:1}:{idempotency_key:K}),...f};};
const rejected=async(value,list=false)=>{await assert.rejects(()=>read(value,list),e=>e.code==='service_unavailable');};

test('membership status accepts the canonical group/member composite and retains read-only recovery',async()=>{
 const f=await read(statusValue(receipt()));assert.equal(f.result.data.receipt.resource_id,G+'/'+U);assert.equal(f.result.read_only,true);assert.equal(f.result.data.recovery.write_permitted,false);assert.equal(f.result.data.recovery.automatic_retry,false);assert.deepEqual(f.permissions,['account.manage']);assert.deepEqual(f.requests,[{method:'GET',path:'/api/admin/operations/requests/'+K}]);
});
test('own mixed history preserves single IDs and composite membership IDs',async()=>{
 const k2='group-original-1234',id2=canonicalRequestId(P,k2),r2={...receipt(),request_id:id2,resource_type:'groups',resource_id:G};
 const value={...M,total:2,rows:[listValue(receipt()).rows[0],{id:id2,idempotency_key:k2,status:'succeeded',scope:'groups.post',receipt:r2}]};
 const f=fixture(value),result=await callTool(f.api,'collect_admin_list_requests',{limit:2});assert.deepEqual(result.data.rows.map(r=>r.receipt.resource_id),[G+'/'+U,G]);assert.equal(f.requests.length,1);assert.match(f.requests[0].path,/limit=2/);assert.equal(f.requests[0].path.includes('account_id'),false);
});
test('membership receipts reject malformed or coerced composites in status and history',async()=>{
 for(const id of ['',G,'/'+U,G+'/',G+'/'+U+'/',G+'/'+U+'/'+G,G+'.'+U,G+'%2F'+U,G+'//'+U,' '+G+'/'+U,G+'/'+U+' ',G.replace(/^4/,'A')+'/'+U,null,{},[G+'/'+U],42])for(const list of[false,true])await rejected(list?listValue(receipt({resource_id:id})):statusValue(receipt({resource_id:id})),list);
});
test('other receipt resource types retain exact single UUIDs and reject composite or array IDs',async()=>{
 for(const type of['groups','users','payees','transactions','reconciliation_proposals','operator_notes']){
  for(const list of[false,true]){const good=receipt({resource_type:type,resource_id:G});await read(list?listValue(good):statusValue(good),list);
   for(const id of[G+'/'+U,[G]]){const bad=receipt({resource_type:type,resource_id:id});await rejected(list?listValue(bad):statusValue(bad),list);}}
 }
});
test('membership recovery still rejects wrong principal, key, receipt identity, status or version',async()=>{
 for(const override of[{request_id:canonicalRequestId(G,K)},{resource_type:'membership'},{status:'unconfirmed'},{version:0},{version:1.5},{version:'1'}])for(const list of[false,true]){const r=receipt(override);await rejected(list?listValue(r):statusValue(r),list);}
 const wrong=statusValue(receipt());wrong.request_id=canonicalRequestId(G,K);await rejected(wrong);
 const badList=listValue(receipt());badList.rows[0].idempotency_key='different-original-key';await rejected(badList,true);
});
test('recovery uncertainty remains an exact original-key GET with no replay, cancel or replacement key',async()=>{
 for(const status of['unconfirmed','cancelled','not_found']){
  const value={...M,status,...(status==='not_found'?{}:{request_id:canonicalRequestId(P,K),receipt:null})};const f=await read(value);assert.equal(f.result.data.recovery.write_permitted,false);assert.equal(f.result.data.recovery.automatic_retry,false);assert.deepEqual(f.requests,[{method:'GET',path:'/api/admin/operations/requests/'+K}]);
 }
});
