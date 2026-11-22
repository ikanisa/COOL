import assert from 'node:assert/strict';
import postgres from 'npm:postgres@3.4.7';
import {openApplicationWork} from '../../../../supabase/functions/_shared/application-fence.js';
import {PostgresDatabase} from '../../../../supabase/functions/_shared/postgres.js';
import {accountReadDatabase} from '../../../../supabase/functions/_shared/domain/admin_accounts_legacy.js';
import {list} from '../../../../supabase/functions/_shared/domain/admin_records.js';
import {ScopedCursor} from '../../../../supabase/functions/_shared/domain/burimunsi/cursor.js';
import {COLLECT_MUTATION_LOCK} from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-authority.js';
import {PostgresNativeAuthStore} from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-auth-store.js';
import {PostgresRecordsStore} from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-records-store.js';
import {RecordsService} from '../../../../supabase/functions/_shared/domain/burimunsi/records-service.js';

const [socket, portText, sizeText, samplesText, planFlag] = Deno.args;
const port = Number(portText), size = Number(sizeText), samples = Number(samplesText);
assert.match(socket, /^\/(?:private\/)?tmp\/collect-pg-transfer-[a-zA-Z0-9]+\/s$/);
assert.ok(Number.isInteger(port) && port >= 51000 && port <= 60999 && [1000, 10000, 100000].includes(size));
assert.ok(Number.isInteger(samples) && samples >= 1 && samples <= 100);
const id = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const group = 'group-' + size;
const integer = text => {const value = Number(text); assert.ok(Number.isSafeInteger(value)); return value;};
const options = {host:socket, port, database:'members_' + size, user:'collect_fixture', ssl:false, max:1, prepare:false,
  types:{whole:{to:20,from:[20,1700],serialize:String,parse:integer}}, onnotice() {}};
let capture = null, onSnapshot = null, postings = 0;
const reader = postgres({...options, debug(_connection, query, values) {
  if (!capture) return;
  let kind;
  if (query.startsWith('WITH records AS')) kind = query.includes('SELECT count(*) AS total FROM records') ? 'count' : 'page';
  else if (query.startsWith('SELECT count(*) AS total FROM app.memberships')) kind = 'count';
  else if (query.startsWith('WITH page AS MATERIALIZED') || query.startsWith('SELECT m.user_id AS id,m.collection_id')) kind = 'page';
  else if (query.startsWith('SELECT m.user_id AS id,') && query.includes(' AS sort_key FROM app.memberships')) kind = 'pivot';
  if (kind) capture.push({kind, query, values:[...values]});
}});
const writer = postgres(options);
const metadata = {contractVersion:1,admissionId:id(900012),sourceSha256:'c'.repeat(64),epoch:1,kind:'http_admin',state:'active',mode:'open'};
const backend = {
  async register() {return metadata;},
  async lease() {return {row:metadata, async assert() {return metadata;}, async release() {}};},
  async close() {return {...metadata,state:'settled',reason:'completed',externalDispatches:0,uncertainDispatches:0};},
  async status() {return {...metadata,found:true};},
};

class ProfileDatabase extends PostgresDatabase {
  async readContext(tx, options) {
    await super.readContext(tx, options);
    if (onSnapshot) await onSnapshot(tx);
  }
  async statement(tx, statement) {
    const value = await super.statement(tx, statement);
    if (onSnapshot && statement.sql.endsWith(' AS allowed')) await onSnapshot(tx);
    return value;
  }
}

function distribution(values) {
  const sorted = [...values].sort((a,b) => a-b);
  const at = q => Number(sorted[Math.ceil(q*sorted.length)-1].toFixed(2));
  return [at(.5),at(.95)];
}

function planSummary(plan) {
  const accesses = new Set();
  function walk(node) {
    if (node['Relation Name'] || node['Index Name']) accesses.add(node['Index Name'] ?? node['Node Type'] + ':' + node['Relation Name']);
    for (const child of node.Plans ?? []) walk(child);
  }
  walk(plan.Plan);
  return {ms:plan['Execution Time'],rows:plan.Plan['Actual Rows'],blocks:(plan.Plan['Shared Hit Blocks'] ?? 0)+(plan.Plan['Shared Read Blocks'] ?? 0),
    access:[...accesses]};
}

async function explain(view, workload, page, statements) {
  assert.deepEqual(statements.map(s => s.kind), view === 'native' && page === 'next' ? ['pivot','page'] : ['count','page']);
  const summaries = {};
  await reader.begin('isolation level repeatable read read only', async tx => {
    await tx.unsafe('SET LOCAL ROLE collect_runtime');
    await tx.unsafe('SET LOCAL search_path=app,public,pg_catalog');
    for (const {kind, query, values} of statements) {
      const rows = await tx.unsafe('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) ' + query, values);
      const plan = rows[0]['QUERY PLAN'][0];
      if (planFlag === '--plans') console.log(JSON.stringify({size,view,workload,page,kind,plan}));
      summaries[kind] = planSummary(plan);
      if (kind === 'page') assert.ok(summaries[kind].rows <= (view === 'native' ? 26 : 25));
    }
  });
  console.log(JSON.stringify({size,view,workload,page,plans:summaries}));
}

async function withPosting(fn) {
  await writer.begin(async tx => {
    await tx.unsafe('SELECT pg_advisory_xact_lock($1::bigint)', [COLLECT_MUTATION_LOCK]);
    await tx.unsafe('SELECT private.fixture_post($1,$2,$3,1)', ['concurrent-' + (++postings), group, id(1)]);
    await fn();
  });
}

const unused = () => {throw Error('unrelated fixture capability');};
let work;
try {
  const [instance] = await writer.unsafe("SELECT current_setting('cluster_name') AS name, inet_server_addr() IS NULL AS socket, current_database() AS db");
  assert.deepEqual({...instance},{name:'collect_members_profile',socket:true,db:'members_' + size});
  work = await openApplicationWork({backend,sourceSha256:metadata.sourceSha256,kind:metadata.kind,id:metadata.admissionId});
  const db = new ProfileDatabase(reader,{},work);
  const authority = new PostgresNativeAuthStore({db,groupId:group,createOperatorPrincipal:unused});
  const store = new PostgresRecordsStore({authority,sourceReader:{revision:unused,page:unused,detail:unused}});
  const records = new RecordsService({store,groupId:group,cursor:new ScopedCursor(crypto.getRandomValues(new Uint8Array(32)))});
  const actor = {id:id(900005),sessionId:id(900008)};
  const account = {id:id(900009),public_id:id(900011),principal_id:id(900004),auth_session_id:id(900010),auth_user_id:id(900004),
    token_hash:'a'.repeat(64),origin:'https://members.fixture.invalid',auth_version:1,role:'staff',
    issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null};
  const admin = accountReadDatabase({DB:db},account,'users.read');
  const readNative = (params, cursor) => records.page(actor,'members',{limit:25,sort:'newest',...params,...(cursor ? {cursor} : {})});
  const readAdmin = (params, offset) => {
    const url = new URL('/api/admin/core/members',account.origin);
    url.search = new URLSearchParams({country:'RW',limit:'25',sort:'created_at_desc',offset:String(offset),...params}).toString();
    return list(admin,'members',url);
  };
  const directoryTotal = size - size/100 + 1;
  const lastOffset = Math.floor((directoryTotal-1)/25)*25;
  const deepOffset = lastOffset-25;
  const nativeSearch = {active:'active',q:'mugisha'};
  const adminSearch = {search:'mugisha'};
  const selectiveIds = Array.from({length:99},(_,i) => id(size-99+i));
  // The lowest numbered members are all eligible and tied on creation time.
  const tailSize = directoryTotal-deepOffset;
  const tailIds = Array.from({length:tailSize},(_,i) => id(tailSize-i));
  for (const [view, read, cases] of [
    ['native',readNative,[
      {workload:'browse',params:{},total:size},
      {workload:'active-name',params:{active:'active',q:'Élise'},total:size-size/100},
      {workload:'selective-name',params:nativeSearch,total:selectiveIds.length,expected:selectiveIds},
    ]],
    ['admin',readAdmin,[
      {workload:'browse',params:{},total:directoryTotal},
      {workload:'active-name',params:{status:'active',search:'Élise'},total:size-size/100-size/40+size/200},
      {workload:'selective-name',params:adminSearch,total:selectiveIds.length,expected:[...selectiveIds].reverse()},
      {workload:'deep-offset',params:{},total:directoryTotal,offset:deepOffset,expected:tailIds},
    ]],
  ]) {
    onSnapshot = async tx => {
      const [mode] = await tx.unsafe("SELECT current_user AS role,current_setting('transaction_isolation') AS isolation,current_setting('transaction_read_only') AS read_only");
      assert.deepEqual({...mode},{role:'collect_runtime',isolation:'repeatable read',read_only:view==='native'?'on':'off'});
    };
    await read({},view === 'native' ? null : 0);
    onSnapshot = null;
    for (const {workload,params,total,offset=0,expected} of cases) {
      const pair = async (trace = false) => {
        if (trace) capture = [];
        const t0 = performance.now();
        const first = await read(params,view === 'native' ? null : offset);
        const t1 = performance.now();
        const firstSql = capture;
        if (trace) capture = [];
        const next = await read(params,view === 'native' ? first.nextCursor : offset+25);
        const t2 = performance.now();
        const nextSql = capture;
        capture = null;
        const a = first.items ?? first.rows, b = next.items ?? next.rows;
        assert.equal(first.totalCount ?? first.total,total);
        assert.equal(next.totalCount ?? next.total,total);
        assert.equal(a.length,25); assert.equal(b.length,Math.min(25,total-offset-25));
        const ids = [...a,...b].map(row => row.id);
        assert.equal(new Set(ids).size,ids.length);
        if (expected) assert.deepEqual(ids,expected.slice(0,50));
        if (view === 'native') {
          assert.ok([...a,...b].every(row => row.groupId===group));
          if (!expected) {assert.equal(a[0].id,id(1)); assert.equal(b[0].id,id(26));}
        } else if (workload === 'browse') assert.equal(a[0].id,id(900001));
        if (trace) {await explain(view,workload,'first',firstSql); await explain(view,workload,'next',nextSql);}
        return [t1-t0,t2-t1];
      };
      await pair(true);
      await pair(); await pair();
      for (const load of ['idle','writer-open']) {
        const first = [], next = [];
        const timed = async () => {const [a,b] = await pair(); first.push(a); next.push(b);};
        for (let i=0; i<samples; i++) {
          if (load === 'idle') await timed();
          else await withPosting(timed);
        }
        console.log(JSON.stringify({size,view,workload,load,samples,total,...(view==='admin'?{offsets:[offset,offset+25]}:{}),
          firstMs:distribution(first),nextMs:distribution(next)}));
      }
    }
  }

  // Check the page after the directory and the largest page accepted by CorePages.
  for (const offset of [lastOffset+25,(85899346-1)*25]) {
    const empty = await readAdmin({},offset);
    assert.equal(empty.total,directoryTotal); assert.deepEqual(empty.rows,[]);
  }
  const before = await readNative({},null);
  onSnapshot = () => withPosting(async () => {});
  const stable = await readNative({},before.nextCursor);
  onSnapshot = null;
  assert.equal(stable.revision,before.revision);
  await assert.rejects(readNative({},before.nextCursor),err => err.code === 'cursor_scope_changed' && err.status === 409);
  const fresh = await readNative({},null);
  assert.equal(fresh.items[0].balanceRwf,1 + postings);
  assert.notEqual(fresh.revision,before.revision);
  const exactName = {search:'"Élise 000001"'};
  const selected = await readAdmin(exactName,0);
  assert.equal(selected.total,1); assert.equal(selected.rows[0].id,id(1));
  assert.equal(selected.rows[0].active_groups,2);
  assert.equal(selected.rows[0].total_contributed_rwf,701 + postings);
  onSnapshot = async () => {
    await assert.rejects(writer.begin(tx => tx.unsafe("SELECT 1 FROM app.admin_grants WHERE permission='users.read' FOR UPDATE NOWAIT")),e => e.code === '55P03');
    await withPosting(async () => {});
  };
  const held = await readAdmin(exactName,0);
  onSnapshot = null;
  assert.equal(held.rows[0].total_contributed_rwf,700 + postings);
  assert.equal((await readAdmin(exactName,0)).rows[0].total_contributed_rwf,701 + postings);
  const directory = await readAdmin({},0);
  onSnapshot = () => writer.begin(async tx => {
    await tx.unsafe('SELECT pg_advisory_xact_lock($1::bigint)',[COLLECT_MUTATION_LOCK]);
    await tx.unsafe(`INSERT INTO app.users(id,public_id,full_name,momo_number,created_at,updated_at)
      VALUES($1,'900020','New fixture member','+250780000020','2026-11-02T16:00:00.000Z','2026-11-02T16:00:00.000Z')`,[id(900020)]);
    await tx.unsafe(`INSERT INTO app.memberships(id,collection_id,user_id,joined_at) VALUES('new-fixture',$1,$2,'2026-11-02T16:00:00.000Z')`,[group,id(900020)]);
  });
  assert.equal((await readAdmin({},0)).total,directory.total);
  onSnapshot = null;
  const registered = await readAdmin({},0);
  assert.equal(registered.total,directory.total+1); assert.equal(registered.rows[0].id,id(900020));
  assert.equal((await readNative({},null)).totalCount,size+1);
  await writer.unsafe("DELETE FROM app.admin_grants WHERE user_id=$1 AND permission='users.read'",[account.principal_id]);
  await assert.rejects(readAdmin({},0),e => e.code === 'admin_access_changed' && e.status === 403);
  await assert.rejects(readAdmin(adminSearch,deepOffset),e => e.code === 'admin_access_changed' && e.status === 403);
  await writer.unsafe('UPDATE private.burimunsi_device_grants SET active=false WHERE id=$1',[id(900006)]);
  await assert.rejects(readNative({},null),e => e.code === 'session_unavailable' && e.status === 401);
  await assert.rejects(readNative(nativeSearch,null),e => e.code === 'session_unavailable' && e.status === 401);
  console.log(JSON.stringify({size,committedPostings:postings,registrationDuringAdminRead:'committed',scopeAndSnapshotChecks:'passed',
    deniedAfterRevocation:['users.read','native device']}));
} finally {
  try {if (work) await work.finish();} finally {await Promise.all([reader.end(),writer.end()]);}
}
