import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

let runtime, db;
const uuid = () => crypto.randomUUID();
const stamp = Math.floor(Date.now() / 1000);
const hash = 'a'.repeat(64);
const maximum = 9_007_199_254_740_991;
const packageRoot = fileURLToPath(new URL('..', import.meta.url));
function cliSplit(sql) {
  // Isolate Wrangler's process-wide networking setup from Miniflare's D1 proxy.
  const result = spawnSync(process.execPath, ['-e', "const w=require('wrangler'); const fs=require('node:fs'); process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(fs.readFileSync(0,'utf8'))));"], {
    cwd: packageRoot, input: sql, encoding: 'utf8', timeout: 15000,
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}
const run = (sql, ...bindings) => db.prepare(sql).bind(...bindings).run();
const first = (sql, ...bindings) => db.prepare(sql).bind(...bindings).first();
const rejects = (sql, bindings = [], pattern = /constraint|immutable|exceed|requires|require|cannot|Invalid|queued|balanced|integer|no such/i) => assert.rejects(run(sql, ...bindings), pattern);

before(async () => {
  runtime = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: 'export default { fetch() { return new Response("schema test only"); } };',
    compatibilityDate: '2026-10-04', d1Databases: ['ADMIN_DB'],
  }));
  db = await runtime.getD1Database('ADMIN_DB');
  for (const migration of ['0001_admin_accounts.sql', '0002_collect_core.sql']) {
    const sql = await readFile(new URL(`../migrations/${migration}`, import.meta.url), 'utf8');
    // Match Wrangler local migrations: complete unmodified statement text is
    // split by its own parser and submitted in an atomic prepared batch.
    // Do not flatten lines or strip comments: that hid submission differences.
    await db.batch(cliSplit(sql).map(statement => db.prepare(statement)));
  }
});
after(async () => { await runtime?.dispose(); });

test('unaltered migration files apply through the real Wrangler CLI and record each migration exactly once', async () => {
  const generated = path.join(packageRoot, 'test/.generated');
  await mkdir(generated, { recursive: true });
  const directory = await mkdtemp(path.join(generated, 'core-migrations-'));
  const config = path.join(directory, 'wrangler.json');
  const wrangler = path.join(packageRoot, 'node_modules/wrangler/bin/wrangler.js');
  const command = args => {
    const result = spawnSync(process.execPath, [wrangler, ...args], {
      cwd: directory, encoding: 'utf8', timeout: 30000,
      env: { ...process.env, CI: '1', WRANGLER_SEND_METRICS: 'false' },
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return result.stdout;
  };
  try {
    const isolatedMigrations=path.join(directory,'migrations');await mkdir(isolatedMigrations);
    for(const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql'])await writeFile(path.join(isolatedMigrations,name),await readFile(path.join(packageRoot,'migrations',name)));
    await writeFile(config, JSON.stringify({
      name: 'collect-core-migration-test', compatibility_date: '2026-10-04',
      d1_databases: [{ binding: 'ADMIN_DB', database_name: 'core-migration-test', database_id: uuid(), migrations_dir: isolatedMigrations }],
    }));
    command(['d1', 'migrations', 'apply', 'ADMIN_DB', '--local', '--config', config]);
    const secondApply = command(['d1', 'migrations', 'apply', 'ADMIN_DB', '--local', '--config', config]);
    assert.match(secondApply, /No migrations to apply/);
    const query = "SELECT name FROM d1_migrations ORDER BY id";
    const history = JSON.parse(command(['d1', 'execute', 'ADMIN_DB', '--local', '--config', config, '--command', query, '--json']));
    assert.deepEqual(history[0].results, [{ name: '0001_admin_accounts.sql' }, { name: '0002_collect_core.sql' }, { name: '0003_posted_verification_guard.sql' }]);
    const shape = JSON.parse(command(['d1', 'execute', 'ADMIN_DB', '--local', '--config', config, '--command', "SELECT (SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'collect_%') AS triggers,(SELECT count(*) FROM collect_groups) AS groups,(SELECT count(*) FROM admin_users) AS admins", '--json']));
    assert.equal(shape[0].results[0].triggers, 28);
    assert.equal(shape[0].results[0].groups, 0);
    assert.equal(shape[0].results[0].admins, 0);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('remote-query trigger syntax avoids the known unparenthesized CASE END splitter defect', async () => {
  const sql = await readFile(new URL('../migrations/0002_collect_core.sql', import.meta.url), 'utf8');
  assert.equal(sql.includes('\r'), false, 'Keep remote migration line endings as LF');
  const triggers = cliSplit(sql).filter(statement => /^CREATE TRIGGER\b/.test(statement));
  assert.equal(triggers.length, 27);
  for (const trigger of triggers) {
    assert.match(trigger, /\bBEGIN\b/);
    assert.doesNotMatch(trigger, /\bSELECT\s+CASE\b/i, 'D1 can mistake CASE END for trigger END; parenthesize CASE');
    assert.match(trigger, /\bEND$/);
  }
});

async function fixture() {
  const actor = uuid(), user = uuid(), outsider = uuid(), group = uuid(), otherGroup = uuid(), payee = uuid(), otherPayee = uuid();
  await run("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,?,'admin','invited',?,?)", actor, `${actor}@example.com`, stamp, stamp);
  for (const id of [user, outsider]) {
    await run("INSERT INTO collect_users(id,email,created_by_admin_id,created_at,updated_at) VALUES(?,?,?,?,?)", id, `${id}@example.com`, actor, stamp, stamp);
  }
  for (const id of [group, otherGroup]) {
    await run("INSERT INTO collect_groups(id,slug,title,collection_type,created_by_admin_id,created_at,updated_at) VALUES(?,?,'Test savings group','ikimina',?,?,?)", id, `test-${id}`, actor, stamp, stamp);
  }
  await run("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'member','active',?,?,?)", group, user, stamp, stamp, stamp);
  for (const [id, groupId] of [[payee, group], [otherPayee, otherGroup]]) {
    await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'Test route','mtn_momo','0781234567',?,'Verified test-only fixture',?)", id, groupId, actor, stamp);
  }
  return { actor, user, outsider, group, otherGroup, payee, otherPayee };
}
async function operation(f, scope = 'ledger.post', key = uuid()) {
  const id = uuid();
  await run('INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?)', id, f.actor, scope, key, hash, stamp);
  return id;
}
async function transaction(f, amount = 1000) {
  const id = uuid();
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,?,?,?)", id, f.group, f.payee, uuid(), amount, stamp, stamp);
  return id;
}
async function allocation(f, tx, amount = 1000) {
  const id = uuid();
  await run('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', id, tx, f.group, f.user, amount, await operation(f, 'payment.allocate'), f.actor, stamp);
  return id;
}
async function accounts(f) {
  const debit = uuid(), credit = uuid();
  await run("INSERT INTO collect_ledger_accounts(id,group_id,code,name,account_type,normal_side,created_by_admin_id,created_at) VALUES(?,?,'1000','MoMo control','asset','debit',?,?)", debit, f.group, f.actor, stamp);
  await run("INSERT INTO collect_ledger_accounts(id,group_id,code,name,account_type,normal_side,created_by_admin_id,created_at) VALUES(?,?,'2000','Member contributions','liability','credit',?,?)", credit, f.group, f.actor, stamp);
  return { debit, credit };
}
async function journal(f, tx = null, alloc = null) {
  const id = uuid();
  await run('INSERT INTO collect_journals(id,group_id,transaction_id,allocation_id,operation_request_id,description,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', id, f.group, tx, alloc, await operation(f), 'Test fixture posting', f.actor, stamp);
  return id;
}
async function entry(f, j, account, number, debit, credit) {
  const id = uuid();
  await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,?,?,?)', id, j, f.group, account, number, debit, credit);
  return id;
}
const postSql = "UPDATE collect_journals SET status='posted',posted_by_admin_id=?,posted_at=? WHERE id=?";

test('sequential migrations create an empty fresh database with foreign keys enabled and no seeded identity', async () => {
  assert.equal((await first('PRAGMA foreign_keys')).foreign_keys, 1);
  const tables = await db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'collect_%' OR name='admin_users') ORDER BY name").all();
  assert.equal(tables.results.length, 15);
  for (const { name } of tables.results) assert.equal((await first(`SELECT count(*) AS total FROM ${name}`)).total, 0, name);
});

test('Rwanda profiles, membership uniqueness, stable IDs and immutable receiver routes reject malformed relationships', async () => {
  const f = await fixture();
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'123456','Test member',?,?)", f.user, stamp, stamp);
  await rejects("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'123456','Other member',?,?)", [f.outsider, stamp, stamp]);
  await rejects("INSERT INTO collect_profiles(user_id,public_id,display_name,country_code,created_at,updated_at) VALUES(?,'654321','Other member','KE',?,?)", [f.outsider, stamp, stamp]);
  await rejects("INSERT INTO collect_users(id,email,phone_e164,created_at,updated_at) VALUES(?,'bad@example.com','+254712345678',?,?)", [uuid(), stamp, stamp]);
  await rejects("INSERT INTO collect_users(id,email,created_at,updated_at) VALUES('momo:legacy','bad@example.com',?,?)", [stamp, stamp]);
  await rejects("INSERT INTO collect_memberships(group_id,user_id,role,status,created_at,updated_at) VALUES(?,?,'member','invited',?,?)", [f.group, uuid(), stamp, stamp]);
  await rejects("INSERT INTO collect_memberships(group_id,user_id,role,status,created_at,updated_at) VALUES(?,?,'member','invited',?,?)", [f.group, f.user, stamp, stamp]);
  await rejects("UPDATE collect_payees SET momo_number_or_code='0789999999' WHERE id=?", [f.payee]);
  await rejects('DELETE FROM collect_payees WHERE id=?', [f.payee], /Deactivate/i);
  await run("UPDATE collect_payees SET status='inactive' WHERE id=?", f.payee);
});

test('RWF money is exact and bounded; transactions cannot use another group receiver or duplicate provider references', async () => {
  const f = await fixture(); const tx = await transaction(f);
  const insert = "INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,?,?,?)";
  for (const amount of [1.5, 0, -1, maximum + 1]) await rejects(insert, [uuid(), f.group, f.payee, uuid(), amount, stamp, stamp]);
  await rejects(insert, [uuid(), f.otherGroup, f.payee, uuid(), 1000, stamp, stamp]);
  const reference = (await first('SELECT provider_reference FROM collect_transactions WHERE id=?', tx)).provider_reference;
  await rejects(insert, [uuid(), f.otherGroup, f.otherPayee, reference, 1000, stamp, stamp]);
  await rejects('UPDATE collect_transactions SET amount_rwf=2000 WHERE id=?', [tx]);
  await rejects("UPDATE collect_transactions SET currency='USD' WHERE id=?", [tx]);
  const op = await operation(f, 'payment.allocate');
  await rejects('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', [uuid(), tx, f.group, f.outsider, 1000, op, f.actor, stamp]);
  await allocation(f, tx, 700);
  await assert.rejects(allocation(f, tx, 301), /exceed/i);
  const remaining = await allocation(f, tx, 300);
  await rejects('UPDATE collect_payment_allocations SET amount_rwf=301 WHERE id=?', [remaining]);
});

test('request keys prevent replay and conflicting payload replacement; operational audit is append-only with real admin references', async () => {
  const f = await fixture(); const key = uuid(); const op = await operation(f, 'group.create', key);
  await assert.rejects(operation(f, 'group.create', key), /UNIQUE constraint/i);
  await rejects("UPDATE collect_operation_requests SET request_sha256=? WHERE id=?", ['b'.repeat(64), op]);
  await rejects("UPDATE collect_operation_requests SET status='succeeded',response_json='{}',completed_at=NULL WHERE id=?", [op]);
  await run("UPDATE collect_operation_requests SET status='succeeded',response_json='{}',completed_at=? WHERE id=?", stamp, op);
  await rejects("UPDATE collect_operation_requests SET response_json='{\"changed\":true}' WHERE id=?", [op]);
  await rejects('DELETE FROM collect_operation_requests WHERE id=?', [op]);
  const audit = uuid();
  await run("INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,group_id,subject_type,subject_id,evidence_json,occurred_at) VALUES(?,?,?,'group.created',?,'group',?,'{}',?)", audit, f.actor, op, f.group, f.group, stamp);
  await rejects('UPDATE collect_operations_audit SET action=\'other.event\' WHERE id=?', [audit], /append-only/i);
  await rejects('DELETE FROM collect_operations_audit WHERE id=?', [audit], /append-only/i);
  await rejects("INSERT INTO collect_operations_audit(id,actor_admin_id,action,subject_type,subject_id,evidence_json,occurred_at) VALUES(?,?,'group.created','group',?,'{}',?)", [uuid(), uuid(), f.group, stamp]);
});

test('journal posting requires actual balance and confirmed exact allocation; all posted financial evidence remains immutable', async () => {
  const f = await fixture(), tx = await transaction(f), alloc = await allocation(f, tx), a = await accounts(f), j = await journal(f, tx, alloc);
  await rejects(postSql, [f.actor, stamp, j]);
  const debitLine = await entry(f, j, a.debit, 1, 1000, 0);
  await rejects(postSql, [f.actor, stamp, j]);
  const creditLine = await entry(f, j, a.credit, 2, 0, 900);
  await rejects(postSql, [f.actor, stamp, j]);
  await run('UPDATE collect_journal_entries SET credit_rwf=1000 WHERE id=?', creditLine);
  await rejects(postSql, [f.actor, stamp, j], /confirmed transaction/i);
  await run("UPDATE collect_transactions SET verification_status='confirmation_recorded',verified_by_admin_id=?,verified_at=? WHERE id=?", f.actor, stamp, tx);
  await run(postSql, f.actor, stamp, j);
  const balance = await first('SELECT sum(debits_rwf) AS debit,sum(credits_rwf) AS credit FROM collect_posted_account_balances WHERE group_id=?', f.group);
  assert.deepEqual(balance, { debit: 1000, credit: 1000 });
  await rejects("UPDATE collect_journals SET status='draft',posted_at=NULL,posted_by_admin_id=NULL WHERE id=?", [j]);
  await rejects('DELETE FROM collect_journals WHERE id=?', [j]);
  await rejects('UPDATE collect_journal_entries SET debit_rwf=999 WHERE id=?', [debitLine]);
  await rejects('DELETE FROM collect_journal_entries WHERE id=?', [creditLine]);
  await assert.rejects(entry(f, j, a.credit, 3, 0, 1), /immutable/i);
  await rejects('UPDATE collect_payment_allocations SET amount_rwf=999 WHERE id=?', [alloc]);
  await rejects("UPDATE collect_ledger_accounts SET code='changed' WHERE id=?", [a.debit]);
  await rejects('UPDATE collect_transactions SET amount_rwf=999 WHERE id=?', [tx]);
});

test('posting and group boundaries cannot be bypassed by direct inserts or cross-group accounts/allocations', async () => {
  const f = await fixture(), a = await accounts(f), j = await journal(f);
  const other = { ...f, group: f.otherGroup, payee: f.otherPayee };
  const otherAccounts = await accounts(other);
  await assert.rejects(entry(f, j, otherAccounts.debit, 1, 100, 0), /FOREIGN KEY constraint/i);
  await rejects('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,1,1.25,0)', [uuid(), j, f.group, a.debit]);
  await rejects("INSERT INTO collect_journals(id,group_id,operation_request_id,description,status,created_by_admin_id,created_at,posted_by_admin_id,posted_at) VALUES(?,?,?,'Skip validation','posted',?,?,?,?)", [uuid(), f.group, await operation(f), f.actor, stamp, f.actor, stamp], /draft/i);
  const tx = await transaction(f), alloc = await allocation(f, tx);
  await assert.rejects(journal(other, tx, alloc), /FOREIGN KEY constraint/i);
  const payment = await journal(f, tx, alloc);
  await entry(f, payment, a.debit, 1, 999, 0); await entry(f, payment, a.credit, 2, 0, 999);
  await run("UPDATE collect_transactions SET verification_status='confirmation_recorded',verified_by_admin_id=?,verified_at=? WHERE id=?", f.actor, stamp, tx);
  await rejects(postSql, [f.actor, stamp, payment], /exact allocation/i);
});

test('journal and cumulative account totals stay inside exact-integer range without overflow or hidden draft balances', async () => {
  const f = await fixture(), a = await accounts(f), j = await journal(f);
  await entry(f, j, a.debit, 1, maximum, 0);
  await assert.rejects(entry(f, j, a.debit, 2, 1, 0), /exact integer range/i);
  await entry(f, j, a.credit, 2, 0, maximum);
  assert.equal((await first('SELECT debits_rwf FROM collect_posted_account_balances WHERE account_id=?', a.debit)).debits_rwf, 0);
  await run(postSql, f.actor, stamp, j);
  assert.equal((await first('SELECT debits_rwf FROM collect_posted_account_balances WHERE account_id=?', a.debit)).debits_rwf, maximum);
  const overflow = await journal(f);
  await entry(f, overflow, a.debit, 1, 1, 0); await entry(f, overflow, a.credit, 2, 0, 1);
  await rejects(postSql, [f.actor, stamp, overflow], /exact integer range/i);
});

test('receipt ingress deduplicates immutable source bytes and cannot link a different receiver transaction', async () => {
  const f = await fixture(), id = uuid(), tx = await transaction(f), source = uuid(), external = uuid();
  const insert = 'INSERT INTO collect_receipt_ingress(id,source_key,external_message_id,payee_id,payload_sha256,payload_object_key,received_at) VALUES(?,?,?,?,?,?,?)';
  await run(insert, id, source, external, f.payee, hash, 'test/receipt-object', stamp);
  await rejects(insert, [uuid(), source, external, f.payee, hash, 'test/other-object', stamp]);
  await rejects('UPDATE collect_receipt_ingress SET payload_sha256=? WHERE id=?', ['b'.repeat(64), id]);
  const other = await transaction({ ...f, group: f.otherGroup, payee: f.otherPayee });
  await rejects("UPDATE collect_receipt_ingress SET parse_status='parsed',parser_version='1',transaction_id=?,parsed_at=? WHERE id=?", [other, stamp, id]);
  await run("UPDATE collect_receipt_ingress SET parse_status='parsed',parser_version='1',transaction_id=?,parsed_at=? WHERE id=?", tx, stamp, id);
  await rejects('DELETE FROM collect_receipt_ingress WHERE id=?', [id]);
});

test('durable outbox requires leases and evidence, prevents duplicates and refuses retry of an uncertain send', async () => {
  const f = await fixture(), id = uuid(), dedup = uuid();
  const insert = "INSERT INTO collect_notification_outbox(id,recipient_user_id,group_id,channel,notification_type,deduplication_key,payload_json,created_at,updated_at) VALUES(?,?,?,'sms','contribution_receipt',?,'{}',?,?)";
  await run(insert, id, f.user, f.group, dedup, stamp, stamp);
  await rejects(insert, [uuid(), f.user, f.group, dedup, stamp, stamp]);
  await rejects("UPDATE collect_notification_outbox SET status='delivered',provider_reference='fake',accepted_at=?,delivered_at=? WHERE id=?", [stamp, stamp, id]);
  await run("UPDATE collect_notification_outbox SET status='leased',attempt_count=1,lease_token_sha256=?,lease_until=? WHERE id=?", hash, stamp + 60, id);
  await rejects("UPDATE collect_notification_outbox SET status='send_started',lease_token_sha256=? WHERE id=?", ['b'.repeat(64), id], /lease identity/i);
  await run("UPDATE collect_notification_outbox SET status='send_started' WHERE id=?", id);
  await run("UPDATE collect_notification_outbox SET status='uncertain',lease_token_sha256=NULL,lease_until=NULL,outcome_evidence_key='test/unknown-send' WHERE id=?", id);
  await rejects("UPDATE collect_notification_outbox SET status='queued' WHERE id=?", [id], /uncertain sends/i);
  await run("UPDATE collect_notification_outbox SET status='accepted',provider_reference='test-provider-message',accepted_at=? WHERE id=?", stamp, id);
  await run("UPDATE collect_notification_outbox SET status='delivered',delivered_at=? WHERE id=?", stamp, id);
  await rejects("UPDATE collect_notification_outbox SET status='queued' WHERE id=?", [id]);
  await rejects('DELETE FROM collect_notification_outbox WHERE id=?', [id]);
  const expired = uuid();
  await run(insert, expired, f.user, f.group, uuid(), stamp - 120, stamp - 120);
  await run("UPDATE collect_notification_outbox SET status='leased',attempt_count=1,lease_token_sha256=?,lease_until=? WHERE id=?", hash, stamp - 60, expired);
  await rejects("UPDATE collect_notification_outbox SET status='send_started' WHERE id=?", [expired], /expired notification lease/i);
});
