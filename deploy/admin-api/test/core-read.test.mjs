import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { CORE_READ_PERMISSIONS, CoreReadError, handleCoreRead } from '../src/core.mjs';
import { OPERATIONS_MANAGE_PERMISSIONS, OPERATIONS_CREATE_PERMISSIONS } from '../src/operations.mjs';
import { digest, randomToken } from '../src/security.mjs';
import { prepareTransactionPublicReference,reviewedMemberSmsLinkStatements } from '../src/admin-sms.mjs';
import { receiverFact,memberFact, transactionAdditionalFields } from './transaction-source-fixture.mjs';

const origin = 'https://admin.collect.ikanisa.com';
const endpoints = ['overview', 'groups', 'users', 'members', 'payees', 'transactions', 'ledgers'];
const root = fileURLToPath(new URL('..', import.meta.url));
const timestamp = Math.floor(Date.now() / 1000);
const uuid = () => crypto.randomUUID();
let runtime, db, owner, admin, staff;
const run = (sql, ...bindings) => db.prepare(sql).bind(...bindings).run();
const first = (sql, ...bindings) => db.prepare(sql).bind(...bindings).first();
const permissions = ['overview.read', 'account.manage', ...CORE_READ_PERMISSIONS];

async function actor(role = 'staff') {
  const id = uuid(); const token = randomToken(); const hash = await digest(token);
  await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,'active','test-only-no-login',?,?)", id, role === 'owner' ? 'info@ikanisa.com' : `${id}@example.com`, role, timestamp, timestamp);
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)', hash, uuid(), id, timestamp, timestamp + 3600);
  return { id, role, cookie: `__Host-collect_admin=${token}`, token_hash: hash, auth_version: 1, status: 'active', permissions };
}
async function get(view, account = staff, options = {}) {
  const response = await runtime.dispatchFetch(`${origin}/api/admin/${view.startsWith('core') || view.startsWith('auth') || view.startsWith('team') ? view : `core/${view}`}`, {
    method: options.method || 'GET',
    headers: { Origin: options.origin || origin, ...(account ? { Cookie: account.cookie } : {}), ...options.headers },
  });
  return { status: response.status, body: await response.json(), response };
}

before(async () => {
  const bundle = await build({ entryPoints: [fileURLToPath(new URL('../src/worker.mjs', import.meta.url))], bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
  runtime = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: bundle.outputFiles[0].text, compatibilityDate: '2026-10-04',
    bindings: { ADMIN_ORIGIN: origin, ENVIRONMENT: 'test' }, d1Databases: ['ADMIN_DB'],
  }));
  db = await runtime.getD1Database('ADMIN_DB');
  for (const name of ['0001_admin_accounts.sql', '0002_collect_core.sql', '0003_posted_verification_guard.sql', '0004_operating_actions.sql', '0005_member_cloudflare.sql', '0006_gateway_cloudflare.sql', '0007_email_only_dispatch.sql', '0008_admin_people.sql','0009_admin_reconciliation.sql','0010_admin_sms_facts.sql','0011_admin_transaction_sms_lineage.sql']) {
    const sql = await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8');
    // Wrangler import is isolated from Miniflare's process-wide networking.
    const split = spawnSync(process.execPath, ['-e', "const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"], { cwd: root, input: sql, encoding: 'utf8', timeout: 15000 });
    assert.equal(split.status, 0, split.stderr);
    await db.batch(JSON.parse(split.stdout).map(statement => db.prepare(statement)));
  }
  owner = await actor('owner'); admin = await actor('admin'); staff = await actor('staff');
});
after(async () => { await runtime?.dispose(); });

test('core reads require active same-origin sessions; known roles can read and unknown routes/writes remain unavailable', async () => {
  for (const endpoint of endpoints) {
    assert.equal((await get(endpoint, null)).status, 401);
    for (const account of [owner, admin, staff]) assert.equal((await get(endpoint, account)).status, 200);
  }
  assert.equal((await get('groups', staff, { origin: 'https://attacker.invalid' })).status, 403);
  assert.equal((await get('groups', staff, { headers: { 'Sec-Fetch-Site': 'cross-site' } })).status, 403);
  assert.equal((await get('core/rpc?sql=SELECT%201', staff)).status, 404);
  assert.equal((await get('core/__proto__', staff)).status, 404);
  assert.equal((await get('core/groups/anything', staff)).status, 404);
  assert.equal((await get('core', staff)).status, 404);
  for (const method of ['POST', 'PUT', 'DELETE']) assert.equal((await get('groups', owner, { method })).status, 405);
  const result = await get('groups');
  assert.equal(result.response.headers.get('Cache-Control'), 'no-store');
  assert.equal(result.response.headers.get('Access-Control-Allow-Origin'), null);
});

test('public session permissions grant operating writes to administrators and preserve owner-only team management', async () => {
  for (const account of [owner, admin, staff]) {
    const session = await get('auth/session', account);
    const expected = [...permissions, ...OPERATIONS_CREATE_PERMISSIONS, 'email.read', 'gateway.read', 'reconciliations.read','reconciliations.propose','sms.read', ...(account.role !== 'staff' ? [...OPERATIONS_MANAGE_PERMISSIONS, 'email.manage', 'gateway.manage','reconciliations.review','sms.extract','sms.reveal','admin_users.read'] : []), ...(account.role === 'owner' ? ['admin_users.manage'] : [])];
    assert.deepEqual([...session.body.user.permissions].sort(),expected.sort());
    assert.ok(!JSON.stringify(session.body).includes(account.cookie.split('=')[1]));
    if (account.role === 'staff') assert.ok(!session.body.user.permissions.some(permission => permission.endsWith('.manage') && permission !== 'account.manage'));
  }
  assert.equal((await get('team', staff)).status, 403);
  assert.equal((await get('team', admin)).status, 200);
  assert.equal((await get('team', owner)).status, 200);
});

test('fresh workspace includes operators with measured empty operating counts and valid windows', async () => {
  const result = await get('overview?country=RW');
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.counts, { users: 3, groups: 0, active_members: 0, payees: 0, transactions: 0, draft_journals: 0, posted_journals: 0,
    app_users: 0, direct_users: 0, admin_users: 2, staff_users: 1, active_payees: 0, unallocated_transactions: 0, sms_receipts: 0, receipts_needing_review: 0 });
  assert.equal(result.body.country_code, 'RW');
  assert.ok(Number.isFinite(Date.parse(result.body.measured_at)));
  assert.equal(result.body.metrics.length,19);
  assert.deepEqual(result.body.amounts,{total_collected_rwf:'0',total_allocated_rwf:'0',total_unallocated_rwf:'0',total_posted_contributions_rwf:'0'});
  assert.ok(result.body.metrics.every(metric => metric.status === 'measured'));
  for (const endpoint of endpoints.slice(1)) {
    assert.deepEqual((await get(`${endpoint}?country=RW&limit=100&offset=100`)).body, { rows: [], total: endpoint==='users'?3:0 });
  }
});

const fixture = { user: uuid(), user2: uuid(), pendingUser: uuid(), group: uuid(), group2: uuid(), payee: uuid(), payee2: uuid(), tx: uuid(), tx2: uuid(), debit: uuid(), credit: uuid(), allocation: uuid(), posted: uuid(), draft: uuid() };
async function operation(scope) {
  const id = uuid();
  await run('INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?)', id, owner.id, scope, uuid(), 'a'.repeat(64), timestamp);
  return id;
}

test('populated Rwanda rows project full authorized identity, precise money and contribution totals', async () => {
  const f = fixture;
  await run("INSERT INTO collect_users(id,email,phone_e164,status,created_at,updated_at) VALUES(?,'alice.private@example.com','+250781234567','active',?,?)", f.user, timestamp, timestamp);
  await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'bob.private@example.com','active',?,?)", f.user2, timestamp, timestamp);
  await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'pending.private@example.com','invited',?,?)", f.pendingUser, timestamp, timestamp);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'123450','Alice Member',?,?)", f.user, timestamp, timestamp);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'654320','Bob Member',?,?)", f.user2, timestamp, timestamp);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'111111','Pending Member',?,?)", f.pendingUser, timestamp, timestamp);
  await run("UPDATE collect_profiles SET momo_provider='mtn_momo',momo_number='0781234567',momo_pay_code='008000' WHERE user_id=?",f.user);
  for (const [id, title, offset] of [[f.group, 'Alpha savings 100%', 200], [f.group2, 'Beta wedding', 100]]) {
    await run("INSERT INTO collect_groups(id,slug,title,collection_type,status,created_by_admin_id,created_at,updated_at) VALUES(?,?,?,'ikimina','active',?,?,?)", id, `group-${id}`, title, owner.id, timestamp - offset, timestamp);
  }
  for (const group of [f.group, f.group2]) await run("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'member','active',?,?,?)", group, f.user, timestamp, timestamp, timestamp);
  await run("INSERT INTO collect_memberships(group_id,user_id,role,status,created_at,updated_at) VALUES(?,?,'member','invited',?,?)", f.group, f.user2, timestamp, timestamp);
  for (const [id, group] of [[f.payee, f.group], [f.payee2, f.group2]]) await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'Official beneficiary','mtn_momo','0787654321',?,'Synthetic test fixture',?)", id, group, owner.id, timestamp);
  for (const [id, group, payee, amount, reference] of [[f.tx, f.group, f.payee, 1200, 'RW-REF-001'], [f.tx2, f.group2, f.payee2, Number.MAX_SAFE_INTEGER, 'RW-REF-002']]) {
    await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,?,?,?)", id, group, payee, reference, amount, timestamp, timestamp);
  }
  const evidenceId=uuid();
  await run("INSERT INTO collect_transaction_evidence(id,transaction_id,kind,reference,artifact_sha256,recorded_by_admin_id,operation_request_id,recorded_at) VALUES(?,?,'receiver_statement','Synthetic original source',?,?,?,?)",evidenceId,f.tx,'a'.repeat(64),owner.id,await operation('payment.evidence'),timestamp);
  await run("INSERT INTO collect_transaction_reviews(id,transaction_id,evidence_id,outcome,transaction_version,reviewed_by_admin_id,operation_request_id,reason,reviewed_at) VALUES(?,?,?,'confirmation_recorded',2,?,?,'Independent source review',?)",uuid(),f.tx,evidenceId,admin.id,await operation('payment.review'),timestamp);
  await run("UPDATE collect_transactions SET verification_status='confirmation_recorded',verified_by_admin_id=?,verified_at=?,version=2 WHERE id=?", admin.id, timestamp, f.tx);
  await run('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,600,?,?,?)', f.allocation, f.tx, f.group, f.user, await operation('payment.allocate'), owner.id, timestamp);
  for (const [id, code, type, side] of [[f.debit, '1000', 'asset', 'debit'], [f.credit, '2000', 'liability', 'credit']]) await run('INSERT INTO collect_ledger_accounts(id,group_id,code,name,account_type,normal_side,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', id, f.group, code, `Account ${code}`, type, side, owner.id, timestamp);
  for (const [id, tx, allocation, description] of [[f.posted, f.tx, f.allocation, 'Posted allocation'], [f.draft, null, null, 'Draft adjustment']]) {
    await run('INSERT INTO collect_journals(id,group_id,transaction_id,allocation_id,operation_request_id,description,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', id, f.group, tx, allocation, await operation('ledger.post'), description, owner.id, timestamp);
    await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,1,?,0)', uuid(), id, f.group, f.debit, id === f.posted ? 600 : 200);
    await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,2,0,?)', uuid(), id, f.group, f.credit, id === f.posted ? 600 : 100);
  }
  await run("UPDATE collect_journals SET status='posted',posted_by_admin_id=?,posted_at=? WHERE id=?", admin.id, timestamp, f.posted);

  const expectedTotals = { groups: 2, users: 6, members: 1, payees: 2, transactions: 2, ledgers: 2 };
  for (const [endpoint, expected] of Object.entries(expectedTotals)) {
    const result = await get(endpoint);
    assert.equal(result.status, 200, JSON.stringify(result.body)); assert.equal(result.body.total, expected);
    assert.equal(result.body.rows.length, expected);
    for (const row of result.body.rows) {
      assert.match(row.id, /^[a-f0-9-]{36}$/); assert.equal(typeof row.amount, 'string');
      assert.equal(row.country_code, 'RW'); assert.equal(row.currency_code, 'RWF');
      assert.ok(Number.isFinite(Date.parse(row.created_at)));
    }
    const serialized = JSON.stringify(result.body);
    for (const secret of ['password_hash', 'token_hash','challenge_version']) assert.ok(!serialized.includes(secret), `${endpoint} leaked ${secret}`);
  }
  const members = (await get('members')).body.rows;
  assert.equal(members[0].id, f.user); assert.equal(members[0].active_groups, 2); assert.equal(members[0].amount, '2 groups');
  assert.equal(members[0].title,'123450');assert.deepEqual(members[0].user_types,['App']);
  assert.equal(members[0].whatsapp_number,'+250781234567');assert.equal(members[0].momo_number,'0781234567');assert.equal(members[0].momo_pay_code,'008000');
  assert.equal(members[0].total_contributed_rwf,600);assert.equal(members[0].posted_contributed_rwf,600);
  const transactions = (await get('transactions')).body.rows;
  assert.equal(transactions.find(row => row.id === f.tx).allocation_status, 'partial');
  assert.equal(transactions.find(row => row.id === f.tx).allocated_amount_rwf, 600);
  assert.equal(transactions.find(row => row.id === f.tx2).amount, String(Number.MAX_SAFE_INTEGER));
  const ledgers = (await get('ledgers')).body.rows;
  assert.equal(ledgers.find(row => row.id === f.posted).balanced, true);
  assert.equal(ledgers.find(row => row.id === f.draft).balanced, false);
  assert.equal(ledgers.find(row => row.id === f.draft).amount, '200');
  const overview = (await get('overview')).body;
  assert.equal(overview.counts.users,6);assert.equal(overview.counts.active_members,1);assert.equal(overview.counts.app_users,3);
  assert.equal(overview.counts.unallocated_transactions,2);
  assert.deepEqual(overview.amounts,{total_collected_rwf:'1200',total_allocated_rwf:'600',total_unallocated_rwf:String(BigInt(Number.MAX_SAFE_INTEGER)+600n),total_posted_contributions_rwf:'600'});
});

test('server paging, stable sort, native statuses and literal public-field searches have exact totals', async () => {
  const firstPage = (await get('groups?country=RW&limit=1&offset=0&sort=created_at_asc')).body;
  const secondPage = (await get('groups?country=RW&limit=1&offset=1&sort=created_at_asc')).body;
  assert.equal(firstPage.total, 2); assert.equal(secondPage.total, 2);
  assert.equal(firstPage.rows[0].id, fixture.group); assert.equal(secondPage.rows[0].id, fixture.group2);
  assert.equal((await get('groups?limit=1&offset=2147483647')).body.rows.length, 0);
  assert.equal((await get('groups?search=%25')).body.total, 1, 'Percent is literal, not a wildcard');
  assert.equal((await get('groups?search=%27%20OR%201%3D1--')).body.total, 0);
  assert.equal((await get('users?search=123450')).body.total, 1);
  assert.equal((await get('users?search=ALICE')).body.total, 1);
  for (const name of ['users', 'members']) {
    assert.equal((await get(`${name}?search=alice.private`)).body.total, 1, 'Authorized contact search');
    assert.equal((await get(`${name}?search=781234`)).body.total, 1, 'Authorized numeric contact search');
  }
  assert.equal((await get('users?status=invited')).body.total, 1);
  assert.equal((await get('transactions?status=confirmation_recorded')).body.total, 1);
  assert.equal((await get('ledgers?status=posted')).body.total, 1);
});

test('invalid or ambiguous filters are rejected without silently broadening country, page or status scope', async () => {
  for (const query of ['country=KE', 'country=rw', 'country=', 'country=RW&country=RW', 'limit=0', 'limit=101', 'limit=1.5', 'limit=01', 'offset=-1', 'offset=2147483648', 'offset=1e3', 'sort=title', 'sort=created_at_desc;DROP%20TABLE%20collect_users', 'status=allocated', 'rpc=admin_list_users', 'sql=SELECT%201', 'limit=1&limit=2', `search=${'x'.repeat(201)}`, 'search=%00']) {
    assert.equal((await get(`groups?${query}`)).status, 400, query);
  }
  assert.equal((await get('overview?search=anything')).status, 400);
  assert.equal((await get('overview?country=KE')).status, 400);
  assert.equal((await get('members?status=admin')).status, 400, 'Platform admin is not an app-user membership state');
});

test('system people use explicit App/Direct and operator links with stable searchable aliases', async () => {
  const direct=uuid();
  await run("INSERT INTO collect_users(id,phone_e164,status,member_type,created_at,updated_at) VALUES(?,'+250782501234','active','direct',?,?)",direct,timestamp,timestamp);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,momo_number,momo_pay_code,created_at,updated_at) VALUES(?,'345678','Émilie Nyiramana','0782501234','000123',?,?)",direct,timestamp,timestamp);
  await run("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'member','active',?,?,?)",fixture.group,direct,timestamp,timestamp,timestamp);
  const staffId=(await first('SELECT public_id FROM collect_public_identities WHERE admin_user_id=?',staff.id)).public_id;
  const before=(await get('users')).body.total;
  await run('UPDATE collect_users SET operator_admin_id=? WHERE id=?',staff.id,direct);
  const people=(await get('users')).body;
  assert.equal(people.total,before-1);
  const person=people.rows.find(x=>x.id===direct);
  assert.deepEqual(person.user_types,['Staff','Direct']);assert.equal(person.member_type,'direct');
  assert.equal(person.operator_admin_id,staff.id);assert.equal(person.operator_public_id,staffId);
  assert.equal(person.public_id,'345678');assert.equal(person.phone_e164,'+250782501234');assert.equal(person.whatsapp_number,null);
  assert.equal(person.momo_number,'0782501234');assert.equal(person.momo_pay_code,'000123');
  assert.equal(people.rows.some(x=>x.id===staff.id),false);
  for (const query of [staffId,'emilie nyiramana','+250 782 501 234','(0782) 501-234','000123','type:direct Nyiramana','type:staff status:active Nyiramana','direct members']) {
    const result=await get(`users?search=${encodeURIComponent(query)}`);
    assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.total,1,query);assert.equal(result.body.rows[0].id,direct,query);
  }
  assert.equal((await get('users?search=type%3Aapp%20Nyiramana')).body.total,0);
  assert.equal((await get('users?search=group%3ABeta%20role%3Amember')).body.total,1);
  assert.equal((await get('users?search=group%3ABeta%20Nyiramana')).body.total,0);
  assert.equal((await get('users?search=type%3Adirect%20role%3Amember%20group%3AAlpha')).body.total,1);
  assert.equal((await get('users?search=type%3Aunknown')).status,400);
  assert.equal((await get('users?search=users%20without%20groups')).body.rows.every(x=>x.active_groups===0),true);
  const overview=(await get('overview')).body;
  assert.equal(overview.counts.users,6);assert.equal(overview.counts.active_members,2);assert.equal(overview.counts.direct_users,1);
  assert.equal(overview.counts.staff_users,1);assert.equal(overview.counts.admin_users,2);
});

test('unknown App names are absent in directory facts until a name is actually recorded',async()=>{
  const person=uuid();await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'unknown-name@example.com','active',?,?)",person,timestamp,timestamp);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,display_name_recorded,created_at,updated_at) VALUES(?,'123991','Collect member',0,?,?)",person,timestamp,timestamp);
  const row=(await get('users?search=123991')).body.rows[0];assert.equal(row.display_name,null);assert.equal(row.display_name_recorded,false);assert.equal(row.name_verification,'not_recorded');
  assert.equal((await get('users?search=123991%20Collect%20member')).body.total,0);
});

test('revoked, expired or reset sessions cannot use a stale pre-query identity to read rows or overview', async () => {
  for (const [endpoint, mutate] of [
    ['groups', async account => run("UPDATE admin_users SET status='revoked' WHERE id=?", account.id)],
    ['overview', async account => run('UPDATE admin_users SET auth_version=auth_version+1 WHERE id=?', account.id)],
    ['transactions', async account => run('DELETE FROM admin_sessions WHERE token_hash=?', account.token_hash)],
    ['users', async account => run('UPDATE admin_sessions SET expires_at=? WHERE token_hash=?', timestamp - 1, account.token_hash)],
  ]) {
    const account = await actor();
    assert.equal((await get(endpoint, account)).status, 200);
    // Model the exact race after Worker session() lookup but before core SQL.
    const staleIdentity = { ...account };
    await mutate(account);
    await assert.rejects(handleCoreRead(new Request(`${origin}/api/admin/core/${endpoint}`), { ADMIN_DB: db }, staleIdentity), error => error instanceof CoreReadError && error.status === 401);
    assert.equal((await get(endpoint, account)).status, 401);
  }
  await assert.rejects(handleCoreRead(new Request(`${origin}/api/admin/core/groups`), { ADMIN_DB: db }, { ...staff, permissions: [] }), error => error instanceof CoreReadError && error.status === 403);
});

test('transaction columns expose stable numeric identity and honest unknown source facts without provider-reference inference',async()=>{
  const transaction=uuid(),reference='CORE-UNLINKED-FACT';
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,700,?,?)",transaction,fixture.group,fixture.payee,reference,timestamp,timestamp);
  // Merely sharing a provider reference must never attach this extracted fact.
  await receiverFact(db,{actorId:owner.id,payeeId:fixture.payee,reference,time:timestamp});
  const response=await get(`transactions?search=${reference}`),row=response.body.rows[0];
  assert.equal(response.status,200,JSON.stringify(response.body));assert.equal(response.body.total,1);
  for(const field of transactionAdditionalFields)assert.ok(Object.hasOwn(row,field),field);
  assert.match(row.transaction_reference,/^000000[0-9]{12}$/);assert.equal(row.reference_random_source,'sqlite_prng');
  assert.equal(row.title,row.transaction_reference);assert.equal(row.provider_reference,reference);
  assert.equal(row.reference_payer_last3_known,false);assert.equal(row.reference_payee_last3_known,false);
  assert.equal(row.source_fact_id,null);assert.equal(row.reference_source_fact_id,null);
  assert.equal(row.source_link_basis,'not_recorded');assert.equal(row.source_review_id,null);
  for(const field of ['payer_name','payer_phone','payer_masked_phone','payer_last3','source_kind','source_amount_rwf','wallet_balance_rwf','momo_transaction_reference','momo_timestamp_local','momo_timezone_offset','payee_momo_number','payee_momo_code','is_payment'])assert.equal(row[field],null,field);
  assert.equal(row.payee_momo_number_or_code,'0787654321');assert.equal(row.payer_last3_known,false);assert.equal(row.timezone_known,false);
  assert.equal(row.provider_confirmation,false);assert.equal(row.settlement_status,'not_asserted');
  assert.equal(row.payer_source_match_status,'not_recorded');assert.equal(row.payer_insights_status,'not_attributed');
  const repeated=(await get(`transactions?search=${row.transaction_reference}`)).body.rows[0];assert.deepEqual(repeated,row);
  for(const field of ['public_reference','payer_source_match_count','allocated_member_count','public_reference_source_fact_id'])assert.equal(Object.hasOwn(row,field),false,field);
});

test('transaction source columns and search use the explicitly linked preserved fact and retain full authorized numbers',async()=>{
  const transaction=uuid(),reference='CORE-LINKED-FACT';
  const fact=await receiverFact(db,{actorId:owner.id,payeeId:fixture.payee,reference,payerPhone:'+250781234567',suffix:'receiver code 0041258 to +250787654321',time:timestamp});
  const prepared=await prepareTransactionPublicReference({ADMIN_DB:db},{transaction_id:transaction,payee_id:fixture.payee,source_fact_id:fact.id});
  await db.batch([...prepared.statements,db.prepare("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,700,?,?)").bind(transaction,fixture.group,fixture.payee,reference,timestamp,timestamp)]);
  const row=(await get(`transactions?search=${reference}`)).body.rows[0];
  assert.match(row.transaction_reference,/^567321[0-9]{12}$/);assert.equal(row.reference_random_source,'crypto_get_random_values');
  assert.equal(row.reference_payer_last3_known,true);assert.equal(row.reference_payee_last3_known,true);
  assert.equal(row.source_fact_id,fact.id);assert.equal(row.reference_source_fact_id,fact.id);assert.equal(row.source_kind,'receiver');
  assert.equal(row.source_link_basis,'public_reference');assert.equal(row.source_review_id,null);
  assert.equal(row.source_body_sha256,fact.source_body_sha256);assert.equal(row.source_payload_sha256,fact.source_payload_sha256);
  assert.equal(row.source_parsed_at,new Date(timestamp*1000).toISOString());assert.equal(row.parser_version,fact.parser_version);assert.equal(row.source_extraction_status,'parsed');
  assert.equal(row.payer_name,'ALICE UMUHOZA');assert.equal(row.payer_phone,'+250781234567');assert.equal(row.payer_masked_phone,null);assert.equal(row.payer_last3,'567');
  assert.equal(row.payee_momo_number,'+250787654321');assert.equal(row.payee_momo_code,'0041258');
  assert.equal(row.momo_transaction_reference,reference);assert.equal(row.momo_timestamp_local,'2026-10-05T12:35:45');assert.equal(row.momo_timezone_offset,'+02:00');
  assert.equal(row.source_amount_rwf,700);assert.equal(row.amount_rwf,700);assert.equal(row.wallet_balance_rwf,50000);assert.equal(row.source_network,'mtn_momo');assert.equal(row.direction,'incoming');assert.equal(row.is_payment,true);
  assert.equal(row.payer_source_match_status,'unique_recorded_match');assert.equal(row.payer_insights_status,'available');
  for(const query of [row.transaction_reference,'ALICE UMUHOZA',reference,'0041258']){const result=await get(`transactions?search=${encodeURIComponent(query)}`);assert.equal(result.status,200);assert.ok(result.body.rows.some(x=>x.id===transaction),query);}
  assert.deepEqual((await get(`transactions?search=${reference}`,owner)).body.rows[0],row);
});

test('reviewed member facts populate dedicated core columns while original reference-source provenance remains unchanged',async()=>{
  const transaction=uuid(),reference='CORE-REVIEWED-MEMBER',review=uuid(),evidence=uuid();
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,700,?,?)",transaction,fixture.group,fixture.payee,reference,timestamp,timestamp);
  const original=await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?',transaction);
  const fact=await memberFact(db,{actorId:owner.id,userId:fixture.user,reference,payerPhone:'+250781234567',time:timestamp});
  assert.equal((await get(`transactions?search=${reference}`)).body.rows[0].source_fact_id,null);
  const request=await operation('receipt.review');
  await db.batch([
    db.prepare("INSERT INTO collect_transaction_evidence(id,transaction_id,kind,reference,artifact_sha256,recorded_by_admin_id,operation_request_id,recorded_at) VALUES(?,?,'payer_receipt','Explicit member review fixture',?,?,?,?)").bind(evidence,transaction,fact.source_body_sha256,owner.id,request,timestamp),
    db.prepare("INSERT INTO collect_member_receipt_reviews(id,submission_id,outcome,transaction_id,evidence_id,actor_admin_id,operation_request_id,reason,reviewed_at) VALUES(?,?,'reviewed',?,?,?,?,'Explicit matching source review',?)").bind(review,fact.submission,transaction,evidence,owner.id,request,timestamp),
    db.prepare("UPDATE member_receipt_submissions SET status='reviewed',version=2 WHERE id=?").bind(fact.submission),
    ...reviewedMemberSmsLinkStatements({ADMIN_DB:db},{submission_id:fact.submission,actor_admin_id:owner.id,operation_request_id:request,created_at:timestamp}),
  ]);
  const row=(await get(`transactions?search=${reference}`)).body.rows[0];
  for(const field of transactionAdditionalFields)assert.ok(Object.hasOwn(row,field),field);
  assert.equal(row.source_link_basis,'reviewed_member_receipt');assert.equal(row.source_review_id,review);assert.equal(row.source_kind,'member');assert.equal(row.source_fact_id,fact.id);
  assert.equal(row.transaction_reference,original.public_reference);assert.equal(row.reference_source_fact_id,null);assert.equal(row.reference_payer_last3_known,false);assert.equal(row.reference_payee_last3_known,false);
  assert.equal(row.payer_phone,'+250781234567');assert.equal(row.payer_last3,'567');assert.equal(row.payer_last3_known,true);assert.equal(row.source_amount_rwf,700);assert.equal(row.provider_reference,reference);
  assert.equal(row.provider_confirmation,false);assert.equal(row.settlement_status,'not_asserted');assert.equal(row.payer_source_match_status,'unique_recorded_match');
  assert.deepEqual(await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?',transaction),original);
});


test('smart tables sort the whole query and interpret bounded concepts without writes', async()=>{
  const before=await first('SELECT count(*) AS n FROM collect_operation_requests');
  const alpha=await get('groups?sort=title_asc&limit=1&offset=0');
  const beta=await get('groups?sort=title_asc&limit=1&offset=1');
  assert.equal(alpha.status,200);assert.equal(alpha.body.rows[0].id,fixture.group);
  assert.equal(beta.body.rows[0].id,fixture.group2);assert.equal(beta.body.total,2);
  assert.equal((await get('groups?search='+encodeURIComponent('active private groups Alpha'))).body.total,1);
  assert.equal((await get('groups?search='+encodeURIComponent('public groups'))).body.total,0);
  assert.equal((await get('transactions?search='+encodeURIComponent('partial transactions'))).body.rows[0].id,fixture.tx);
  assert.equal((await get('transactions?search='+encodeURIComponent('unallocated transactions reference:RW-REF'))).body.rows[0].id,fixture.tx2);
  assert.equal((await get('transactions?search=RW-REF&sort=amount_rwf_desc&limit=1')).body.rows[0].id,fixture.tx2);
  assert.equal((await get('transactions?search=RW-REF&sort=amount_rwf_desc&limit=1&offset=1')).body.rows[0].id,fixture.tx);
  assert.equal((await get('ledgers?search='+encodeURIComponent('balanced posted journals'))).body.rows[0].id,fixture.posted);
  assert.equal((await get('ledgers?search='+encodeURIComponent('unbalanced journals'))).body.rows[0].id,fixture.draft);
  const staffRows=(await get('users?search='+encodeURIComponent('staff users'))).body.rows;assert.ok(staffRows.some(row=>row.operator_admin_id===staff.id));assert.ok(staffRows.every(row=>row.user_types.includes('Staff')));
  assert.equal((await get('payees?search='+encodeURIComponent('momo:0787654321 active payees'))).body.total,2);
  assert.equal((await get('groups?search='+encodeURIComponent('name:"Alpha savings"'))).body.total,1);
  for(const query of ['sort=amount_rwf_desc','sort=constructor_asc','sort=title_desc%3BDROP%20TABLE%20admin_users','search=private_field:secret'])assert.equal((await get('groups?'+query)).status,400);
  assert.deepEqual(await first('SELECT count(*) AS n FROM collect_operation_requests'),before);
});

test('directory contribution totals retain exact person, verification and posting boundaries across whole-query sorting', async () => {
  const f=fixture,extra=uuid(),other=uuid(),unassigned=uuid(),draft=uuid();
  await run("UPDATE collect_memberships SET status='active',joined_at=?,version=version+1 WHERE group_id=? AND user_id=?",timestamp,f.group,f.user2);
  for(const [id,member,amount] of [[extra,f.user,400],[other,f.user2,100],[unassigned,null,100]]) {
    await run('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)',id,f.tx,f.group,member,amount,await operation('payment.allocate'),owner.id,timestamp);
  }
  await run('INSERT INTO collect_journals(id,group_id,transaction_id,allocation_id,operation_request_id,description,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)',draft,f.group,f.tx,extra,await operation('journal.create'),'Directory contribution fixture draft',owner.id,timestamp);
  for(const [account,line,debit,credit] of [[f.debit,1,400,0],[f.credit,2,0,400]]) {
    await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,?,?,?)',uuid(),draft,f.group,account,line,debit,credit);
  }
  // A formerly confirmed allocation remains evidence after rejection; it must
  // contribute to neither person total. No posted journal prevents that review.
  const rejected=uuid(),evidence=uuid(),excluded=uuid();
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,recorded_by_admin_id,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,50,?,?,?)",rejected,f.group,f.payee,'DIRECTORY-EXCLUDED-'+rejected,owner.id,timestamp,timestamp);
  await run("INSERT INTO collect_transaction_evidence(id,transaction_id,kind,reference,artifact_sha256,recorded_by_admin_id,operation_request_id,recorded_at) VALUES(?,?,'receiver_statement','Directory independent source fixture',?,?,?,?)",evidence,rejected,'c'.repeat(64),owner.id,await operation('payment.evidence'),timestamp);
  for(const [version,outcome,time] of [[2,'confirmation_recorded',timestamp],[3,'rejection_recorded',timestamp+1]]) {
    await run('INSERT INTO collect_transaction_reviews(id,transaction_id,evidence_id,outcome,transaction_version,reviewed_by_admin_id,operation_request_id,reason,reviewed_at) VALUES(?,?,?,?,?,?,?,\'Independent directory fixture review\',?)',uuid(),rejected,evidence,outcome,version,admin.id,await operation('payment.review'),time);
    await run('UPDATE collect_transactions SET verification_status=?,verified_by_admin_id=?,verified_at=?,version=? WHERE id=?',outcome,admin.id,time,version,rejected);
    if(version===2) await run('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,50,?,?,?)',excluded,rejected,f.group,f.user,await operation('payment.allocate'),owner.id,timestamp);
  }
  const before=await first('SELECT count(*) AS n FROM collect_operation_requests');
  for(const area of ['users','members']) {
    const result=await get(`${area}?sort=total_contributed_rwf_desc&limit=1`);
    assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.rows[0].id,f.user);
    assert.equal(result.body.rows[0].total_contributed_rwf,1000);assert.equal(result.body.rows[0].posted_contributed_rwf,600);
    const next=await get(`${area}?sort=total_contributed_rwf_desc&limit=1&offset=1`);
    assert.equal(next.body.rows[0].id,f.user2);assert.equal(next.body.rows[0].total_contributed_rwf,100);assert.equal(next.body.rows[0].posted_contributed_rwf,0);
    const posted=await get(`${area}?search=group:Alpha&sort=posted_contributed_rwf_desc&limit=100`);
    assert.equal(posted.status,200);assert.equal(posted.body.rows[0].id,f.user);
    assert.equal(posted.body.rows.filter(row=>row.id===f.user).length,1);
    assert.ok(posted.body.rows.filter(row=>row.id!==f.user).every(row=>row.posted_contributed_rwf===0));
  }
  const empty=(await get('users?search=type:admin')).body.rows;
  assert.ok(empty.length>0);assert.ok(empty.every(row=>row.total_contributed_rwf===0&&row.posted_contributed_rwf===0));
  const overview=(await get('overview')).body;
  assert.equal(overview.amounts.total_allocated_rwf,'1200');assert.equal(overview.amounts.total_posted_contributions_rwf,'600');
  assert.deepEqual(await first('SELECT count(*) AS n FROM collect_operation_requests'),before,'Directory reads remain nonmutating');
});
