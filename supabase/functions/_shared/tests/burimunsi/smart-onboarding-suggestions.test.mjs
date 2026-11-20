import test from 'node:test';
import assert from 'node:assert/strict';
import {listOnboardingSuggestions,findOnboardingCandidate,SMART_SUGGESTIONS_CTE} from '../../domain/burimunsi/smart-onboarding-suggestions.js';

const id='a4c5d6e7-f809-4123-8567-abcdef123456';
const row={candidate_id:id,momo_name:'Synthetic Person',last3:'123',latest_seen_at:'2026-11-13T08:00:00.000Z',source_count:'2',total_count:'1',payer_phone:'+250780001123'};
test('suggestions expose only the opaque candidate, name and suffix',async()=>{
 let args;const sql={unsafe:async(q,a)=>{args=a;assert.match(q,/x\.native_source_id IS NULL/);assert.match(q,/a\.source_body_sha256=r\.body_sha256/);return [row];}};
 const result=await listOnboardingSuggestions(sql,{groupId:'group-1',q:' Person ',limit:20});
 assert.deepEqual(args,['group-1','Person',21,0]);
 assert.deepEqual(result.items,[{candidateId:id,momoName:'Synthetic Person',last3:'123',latestSeenAt:row.latest_seen_at,sourceCount:2}]);
 assert.equal(JSON.stringify(result).includes('+250'),false);assert.equal(result.after,null);
});
test('the database query is bounded and carries the matching cursor',async()=>{
 let args;const rows=[row,{...row,candidate_id:'a4c5d6e7-f809-4123-8567-abcdef123457'}];
 const result=await listOnboardingSuggestions({unsafe:async(_q,a)=>{args=a;return rows;}},{groupId:'group-1',limit:1,after:{offset:4}});
 assert.deepEqual(args,['group-1','',2,4]);assert.equal(result.items.length,1);assert.deepEqual(result.after,{offset:5});
});
test('candidate lookup reuses the same scoped, registered-member exclusion',async()=>{
 let statement;const sql={unsafe:async(q,args)=>{statement=q;assert.deepEqual(args,['group-1','',id,'+250780001123']);return [row];}};
 assert.deepEqual(await findOnboardingCandidate(sql,{groupId:'group-1',candidateId:id,phone:'0780001123'}),{last3:'123'});
 assert.ok(statement.startsWith(SMART_SUGGESTIONS_CTE));assert.match(statement,/app\.memberships/);
 assert.match(statement,/payer_phone=\$4/);
 assert.equal(await findOnboardingCandidate({unsafe:async()=>[]},{groupId:'group-1',candidateId:id,phone:'0781001123'}),null);
});
test('invalid query, cursor and malformed database projection are rejected',async()=>{
 const sql={unsafe:async()=>[row]};
 await assert.rejects(listOnboardingSuggestions(sql,{groupId:'group-1',limit:101}));
 await assert.rejects(listOnboardingSuggestions(sql,{groupId:'group-1',q:'bad\nquery'}));
 await assert.rejects(listOnboardingSuggestions(sql,{groupId:'group-1',after:{offset:-1}}));
 await assert.rejects(listOnboardingSuggestions({unsafe:async()=>[{...row,last3:'1234'}]},{groupId:'group-1'}));
});
