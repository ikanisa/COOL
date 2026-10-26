import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture,authorization} from './support/auth_fixture.mjs';

async function open(t){const f=await fixture({}, {entrypoint:'index.js'});t.after(()=>f.close());return f;}
async function mark(f){return String((await f.db.prepare('SELECT coalesce(max(id),0) n FROM audit_log').first()).n);}
async function append(f,actor,count,{entity='collection',target=randomUUID()}={}) {
 const at=new Date().toISOString();
 await f.db.batch(Array.from({length:count},()=>f.db.prepare('INSERT INTO audit_log(actor_user_id,action,entity_type,entity_id,details_json,created_at) VALUES(?,?,?,?,?,?)').bind(actor,'synthetic.sync',entity,target,'{"private_receipt":"not_for_sync"}',at)));
 return (await f.db.prepare('SELECT id FROM audit_log WHERE id>? ORDER BY id').bind(Number(await mark(f))-count).all()).results.map(row=>String(row.id));
}
async function page(f,session,cursor,query='limit=100&areas=profiles,collections,members,payment_intents,notifications') {
 const response=await f.mf.dispatchFetch(`https://api.collect.example/v1/sync?cursor=${cursor}&${query}`,{headers:authorization(session)});
 return {status:response.status,body:await response.json()};
}

test('expanded invalidations stay within the client bound and pagination loses no audit-row areas',async t=>{
 const f=await open(t),session=await f.login({phone:'+250788123456'}),start=await mark(f);
 const ids=await append(f,session.user.id,53),seen=[];let cursor=start;
 for(let attempt=0;attempt<4;attempt++){
  const result=await page(f,session,cursor);assert.equal(result.status,200);assert.ok(result.body.events.length<=100);
  assert.ok(BigInt(result.body.cursor)>=BigInt(cursor));
  for(const event of result.body.events){assert.deepEqual(Object.keys(event).sort(),['area','id']);seen.push(event.id);}
  cursor=result.body.cursor;
 }
 const expected=ids.flatMap(id=>['profiles','collections','members','payment_intents','notifications'].map(area=>`${id}:${area}`));
 assert.deepEqual(seen,expected);assert.equal(new Set(seen).size,265);assert.equal(cursor,ids.at(-1));
});

test('small limits reject partial audit rows while a single-area request advances exactly once',async t=>{
 const f=await open(t),session=await f.login({phone:'+250788123456'}),start=await mark(f);const ids=await append(f,session.user.id,2);
 const denied=await page(f,session,start,'limit=1&areas=profiles,collections');assert.equal(denied.status,400);assert.equal(denied.body.code,'invalid_limit');
 const first=await page(f,session,start,'limit=1&areas=profiles');assert.equal(first.status,200);assert.deepEqual(first.body,{events:[{id:`${ids[0]}:profiles`,area:'profiles'}],cursor:ids[0]});
 const second=await page(f,session,first.body.cursor,'limit=1&areas=profiles');assert.deepEqual(second.body,{events:[{id:`${ids[1]}:profiles`,area:'profiles'}],cursor:ids[1]});
});

test('filtered rows advance the cursor and unrelated account events remain private',async t=>{
 const f=await open(t),own=await f.login({phone:'+250788123456'}),other=await f.login({phone:'+250789123456'}),start=await mark(f);
 const ownIds=await append(f,own.user.id,2,{entity:'user'});await append(f,other.user.id,2);
 const filtered=await page(f,own,start,'limit=1&areas=ledger');assert.equal(filtered.status,200);assert.deepEqual(filtered.body,{events:[],cursor:ownIds[0]});
 const next=await page(f,own,filtered.body.cursor,'limit=100&areas=profiles');assert.deepEqual(next.body,{events:[{id:`${ownIds[1]}:profiles`,area:'profiles'}],cursor:ownIds[1]});
 const empty=await page(f,own,next.body.cursor);assert.deepEqual(empty.body,{events:[],cursor:ownIds[1]});
});

test('invalid cursors, duplicate areas and unknown areas fail before consuming audit state',async t=>{
 const f=await open(t),session=await f.login({phone:'+250788123456'}),start=await mark(f);
 for(const cursor of ['-1','01','9007199254740992','not-a-cursor']){const result=await page(f,session,cursor);assert.equal(result.status,400);assert.equal(result.body.code,'invalid_cursor');}
 for(const query of ['areas=profiles,profiles','areas=unknown','areas=']){const result=await page(f,session,start,query);assert.equal(result.status,400);assert.equal(result.body.code,'invalid_area');}
 assert.equal(await mark(f),start);
});
