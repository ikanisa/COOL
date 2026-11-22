import assert from 'node:assert/strict';
import {fixtureRoles, memberId, seedMemberListing} from './fixtures/burimunsi-members.mjs';
import {test} from 'node:test';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {listingSorts, normalizeListingQuery} from '../../../supabase/functions/_shared/domain/burimunsi/listing-query.js';
import {readMemberListing} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-member-listing.js';

const {Client} = pg;

async function seedSearchExamples(client) {
  await client.query(`
    INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
      SELECT 'parity','parity',creator_user_id,'Parity',collection_type,created_at,updated_at FROM app.collections WHERE id='group-1000';
    INSERT INTO app.memberships(id,collection_id,user_id,joined_at,active)
      SELECT 'parity-'||i,'parity',private.fixture_member_id(i),'2026-11-'||lpad((i%8+1)::text,2,'0')||'T08:00:00.000Z',(i%4!=0)::int
      FROM generate_series(1,65) i;
    INSERT INTO app.users(id,public_id,full_name,momo_number,created_at,updated_at)
      VALUES('member-A9','900020','UWÁSE Élise','WalletExtA9','2026-11-01T16:00:00.000Z','2026-11-01T16:00:00.000Z');
    INSERT INTO app.memberships(id,collection_id,user_id,joined_at)
      VALUES('parity-import','parity','member-A9','unknown');
    INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
      SELECT 'balance-'||i,'pay-'||i,'parity',private.fixture_member_id(i),10000+i,'contribution','ev-'||i,'fixture',
        'order-'||i,'2026-11-01T16:20:00.000Z' FROM generate_series(1,65,2) i;`);
}

async function assertSearchParity(client, read) {
  const sorts = {newest:'joined DESC',oldest:'joined ASC',name_asc:'name_key ASC',name_desc:'name_key DESC',
    balance_asc:'balance ASC',balance_desc:'balance DESC',phone_asc:'phone_key ASC',phone_desc:'phone_key DESC'};
  const queries = [
    ...listingSorts('members').map(sort=>({sort,q:'ÉLISE'})),
    {q:'uwáse'}, {q:'WalletExtA9'}, {q:'member-A9'}, {q:'Élise 000004'}, {q:'000001 +250'},
    {q:'0780000001'}, {q:'+250780000001'}, {q:'10001'}, {q:'Élise',active:'inactive'},
    {q:'Élise',minRwf:10008,maxRwf:10056}, {q:'Élise',minRwf:100310}, {q:'unmatched9'},
    {q:'walletExtA9',sort:'balance_desc',minRwf:0,maxRwf:0},
  ];
  for (const query of queries) {
    const listing = normalizeListingQuery('members',{sort:'newest',...query});
    const expected = (await client.query(`
      WITH directory AS (
        SELECT m.user_id AS id,u.full_name,u.momo_number,m.active,
          private.burimunsi_member_joined(m.joined_at) AS joined,private.burimunsi_member_phone(u.momo_number) COLLATE "C" AS phone_key,
          lower(u.full_name COLLATE pg_catalog."en-US-x-icu") COLLATE "C" AS name_key,
          coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id),0) AS balance
        FROM app.memberships m JOIN app.users u ON u.id=m.user_id WHERE m.collection_id='parity'
      ) SELECT id,balance FROM directory WHERE
        strpos(lower(concat_ws(' ',id,full_name,coalesce(phone_key,''),coalesce('0'||substr(phone_key,5),''),momo_number,balance::text)
          COLLATE pg_catalog."en-US-x-icu"),lower($1::text COLLATE pg_catalog."en-US-x-icu"))>0
        AND ($2::bigint IS NULL OR active=$2) AND ($3::numeric IS NULL OR balance>=$3) AND ($4::numeric IS NULL OR balance<=$4)
      ORDER BY ${sorts[listing.sort]} NULLS LAST,id COLLATE "C" ASC`,
    [listing.q,listing.active==='all'?null:Number(listing.active==='active'),listing.minRwf,listing.maxRwf])).rows;
    const actual = [];
    let after = null;
    do {
      const page = await read('parity',{sort:'newest',...query},after);
      assert.equal(page.totalCount,expected.length,JSON.stringify(query));
      actual.push(...page.rows.map(({id,balance})=>({id,balance})));
      after = page.after;
      assert.ok(actual.length<=expected.length,JSON.stringify(query));
    } while (after);
    assert.deepEqual(actual,expected,JSON.stringify(query));
    if (expected.length>25) {
      const anchor=await read('parity',{sort:'newest',...query},null,expected[20].id);
      assert.deepEqual(anchor.rows.map(r=>r.id),expected.slice(20,45).map(r=>r.id));
    }
  }
  assert.equal((await read('parity',{q:'member-A9'})).totalCount,0);
  assert.deepEqual((await read('parity',{q:'WalletExtA9'})).rows.map(r=>r.id),['member-A9']);
}

test('native Members returns bounded PostgreSQL pages with stable anchors across 1k, 10k and 100k member scopes', {timeout:60000}, async t => {
  const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'collect_fixture'});
  const client=new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:fixture.initialUser});
  t.after(async()=>{try{await client.end();}finally{await fixture.close();}});
  await client.connect();
  await client.query(fixtureRoles);
  await seedMemberListing(client, [1000, 10000, 100000]);
  await seedSearchExamples(client);

  let countQueries=0;
  const sql={async unsafe(statement,values){
    if(statement.startsWith('SELECT count(*) AS total'))countQueries++;
    const {rows}=await client.query(statement,values);
    if(statement.includes('ORDER BY')&&statement.includes(' LIMIT '))assert.ok(rows.length<=26);
    return rows;
  }};
  const read = (groupId, query, after = null, anchorId = null) => readMemberListing(sql,{
    groupId,listing:normalizeListingQuery('members',{limit:25,...query}),after,anchorId,
  });
  await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET LOCAL ROLE collect_runtime');
  try{
    for(const size of [1000,10000,100000]){
      const group='group-'+size;
      const before=countQueries,first=await read(group,{sort:'newest'}),second=await read(group,{sort:'newest'},first.after);
      assert.equal(first.totalCount,size);
      assert.equal(first.rows.length,25);assert.equal(second.rows.length,25);
      assert.equal(countQueries-before,1);
      assert.equal(first.rows[0].id,memberId(1));
      assert.equal(second.rows[0].id,memberId(26));
      const anchor=memberId(size-10),last=await read(group,{sort:'newest'},null,anchor);
      assert.equal(last.rows[0].id,anchor);assert.equal(last.rows.length,11);assert.equal(last.after,null);
      assert.equal((await read(group,{sort:'newest'},null,'outside')).rows[0].id,first.rows[0].id);
    }
    const sorted=await read('group-100000',{sort:'balance_desc',minRwf:99500,active:'active'});
    assert.equal(sorted.rows[0].id,memberId(99991));
    assert.equal(String(sorted.rows[0].balance),'99991');
    const names=await read('group-100000',{sort:'name_asc',q:'ÉLISE 099999'});
    assert.deepEqual(names.rows.map(row=>row.id),[memberId(99999)]);
    await assertSearchParity(client,read);
  }finally{await client.query('ROLLBACK');}
  const revisions=async()=>Object.fromEntries((await client.query('SELECT collection_id,revision FROM private.member_history_versions')).rows.map(row=>[row.collection_id,Number(row.revision)]));
  const prior=await revisions();
  await client.query("UPDATE app.users SET full_name='Updated member' WHERE id=$1", [memberId(99999)]);
  assert.deepEqual(await revisions(),{...prior,'group-100000':prior['group-100000']+1});
});
