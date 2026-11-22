import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

const packageRoot = fileURLToPath(new URL('..', import.meta.url));
const migrations = ['0001_admin_accounts.sql', '0002_collect_core.sql', '0003_posted_verification_guard.sql'];
const uuid = () => crypto.randomUUID();
const stamp = Math.floor(Date.now() / 1000);
let runtime, db;

function cliSplit(sql) {
  // Keep Wrangler's process-wide networking setup outside the D1 proxy process.
  const result = spawnSync(process.execPath, ['-e', "const w=require('wrangler'); const fs=require('node:fs'); process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(fs.readFileSync(0,'utf8'))));"], {
    cwd: packageRoot, input: sql, encoding: 'utf8', timeout: 15000,
    env: { ...process.env, CI: '1', WRANGLER_SEND_METRICS: 'false' },
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}
const run = (sql, ...args) => db.prepare(sql).bind(...args).run();
const first = (sql, ...args) => db.prepare(sql).bind(...args).first();

before(async () => {
  runtime = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: 'export default { fetch() { return new Response("local storage invariant test"); } };',
    compatibilityDate: '2026-10-04', d1Databases: ['ADMIN_DB'],
  }));
  db = await runtime.getD1Database('ADMIN_DB');
  for (const migration of migrations) {
    const sql = await readFile(new URL(`../migrations/${migration}`, import.meta.url), 'utf8');
    await db.batch(cliSplit(sql).map(statement => db.prepare(statement)));
  }
});
after(async () => { await runtime?.dispose(); });

async function fixture() {
  const f = { actor: uuid(), otherActor: uuid(), group: uuid(), payee: uuid(), transaction: uuid() };
  // These are synthetic FK identities, not authenticated operational actors.
  for (const actor of [f.actor, f.otherActor]) {
    await run("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,?,'admin','invited',?,?)", actor, `${actor}@example.com`, stamp, stamp);
  }
  await run("INSERT INTO collect_groups(id,slug,title,collection_type,created_by_admin_id,created_at,updated_at) VALUES(?,?,'Local verification fixture','ikimina',?,?,?)", f.group, `test-${f.group}`, f.actor, stamp, stamp);
  await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'Local fixture','mtn_momo','0781234567',?,'Synthetic local evidence',?)", f.payee, f.group, f.actor, stamp);
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,100,?,?)", f.transaction, f.group, f.payee, uuid(), stamp, stamp);
  return f;
}
async function operation(f, scope) {
  const id = uuid();
  await run('INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?)', id, f.actor, scope, uuid(), 'a'.repeat(64), stamp);
  return id;
}
async function draft(f) {
  const allocation = uuid(), journal = uuid(), debit = uuid(), credit = uuid();
  await run('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,100,?,?,?)', allocation, f.transaction, f.group, await operation(f, 'payment.allocate'), f.actor, stamp);
  await run('INSERT INTO collect_journals(id,group_id,transaction_id,allocation_id,operation_request_id,description,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', journal, f.group, f.transaction, allocation, await operation(f, 'journal.post'), 'Local verification fixture', f.actor, stamp);
  for (const [id, side, kind] of [[debit, 'debit', 'asset'], [credit, 'credit', 'liability']]) {
    await run('INSERT INTO collect_ledger_accounts(id,group_id,code,name,account_type,normal_side,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)', id, f.group, id, 'Local fixture', kind, side, f.actor, stamp);
  }
  await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,1,100,0)', uuid(), journal, f.group, debit);
  await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,2,0,100)', uuid(), journal, f.group, credit);
  return journal;
}
async function verify(f, status = 'confirmation_recorded', actor = f.actor, at = stamp) {
  await run('UPDATE collect_transactions SET verification_status=?,verified_by_admin_id=?,verified_at=? WHERE id=?', status, actor, at, f.transaction);
}
const post = (f, journal) => run("UPDATE collect_journals SET status='posted',posted_by_admin_id=?,posted_at=? WHERE id=?", f.actor, stamp, journal);
const evidence = f => first('SELECT verification_status,verified_by_admin_id,verified_at FROM collect_transactions WHERE id=?', f.transaction);
const resetSql = "UPDATE collect_transactions SET verification_status='pending',verified_by_admin_id=NULL,verified_at=NULL WHERE id=?";
const immutable = /Posted transaction verification evidence is immutable/;

test('initial confirmation permits posting and an unchanged verification update stays harmless', async () => {
  const f = await fixture(), journal = await draft(f);
  await assert.rejects(post(f, journal), /confirmed transaction/);
  await verify(f);
  await post(f, journal);
  const before = await evidence(f);
  await verify(f);
  assert.deepEqual(await evidence(f), before);
  assert.equal((await first('SELECT status FROM collect_journals WHERE id=?', journal)).status, 'posted');
});

test('posted transaction verification cannot be reversed or cleared', async () => {
  const f = await fixture(), journal = await draft(f);
  await verify(f); await post(f, journal);
  const before = await evidence(f);
  for (const status of ['rejection_recorded', 'evidence_conflict']) {
    await assert.rejects(verify(f, status), immutable);
  }
  await assert.rejects(run(resetSql, f.transaction), immutable);
  assert.deepEqual(await evidence(f), before);
});

test('posted transaction verifier and verification timestamp are immutable individually and together', async () => {
  const f = await fixture(), journal = await draft(f);
  await verify(f); await post(f, journal);
  const before = await evidence(f);
  await assert.rejects(run('UPDATE collect_transactions SET verified_by_admin_id=? WHERE id=?', f.otherActor, f.transaction), immutable);
  await assert.rejects(run('UPDATE collect_transactions SET verified_at=? WHERE id=?', stamp + 1, f.transaction), immutable);
  await assert.rejects(verify(f, 'confirmation_recorded', f.otherActor, stamp + 1), immutable);
  assert.deepEqual(await evidence(f), before);
});

test('verification changes remain possible before posting, with no journal or only a draft', async () => {
  const f = await fixture();
  await verify(f, 'rejection_recorded');
  await run(resetSql, f.transaction);
  assert.equal((await evidence(f)).verification_status, 'pending');
  const journal = await draft(f);
  await verify(f);
  await verify(f, 'evidence_conflict', f.otherActor, stamp + 1);
  await assert.rejects(post(f, journal), /confirmed transaction/);
  await run(resetSql, f.transaction);
  await verify(f, 'confirmation_recorded', f.otherActor, stamp + 1);
  await post(f, journal);
  await assert.rejects(run(resetSql, f.transaction), immutable);
});

test('an unrelated posted transaction does not freeze another transaction verification', async () => {
  const f = await fixture(), journal = await draft(f);
  await verify(f); await post(f, journal);
  const other = { ...f, transaction: uuid() };
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at) VALUES(?,?,?,'mtn_momo',?,100,?,?)", other.transaction, f.group, f.payee, uuid(), stamp, stamp);
  await verify(other, 'rejection_recorded', f.otherActor);
  await run(resetSql, other.transaction);
  assert.equal((await evidence(other)).verification_status, 'pending');
  assert.equal((await evidence(f)).verification_status, 'confirmation_recorded');
});

test('Wrangler applies the original three migration files locally and a second apply is a no-op', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'collect-posted-verification-'));
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
    const isolatedMigrations=path.join(directory,'migrations');
    await mkdir(isolatedMigrations);
    for(const name of migrations)await writeFile(path.join(isolatedMigrations,name),await readFile(path.join(packageRoot,'migrations',name)));
    await writeFile(config, JSON.stringify({
      name: 'collect-posted-verification-test', compatibility_date: '2026-10-04',
      d1_databases: [{ binding: 'ADMIN_DB', database_name: 'posted-verification-test', database_id: uuid(), migrations_dir: isolatedMigrations }],
    }));
    command(['d1', 'migrations', 'apply', 'ADMIN_DB', '--local', '--config', config]);
    assert.match(command(['d1', 'migrations', 'apply', 'ADMIN_DB', '--local', '--config', config]), /No migrations to apply/);
    const query = sql => JSON.parse(command(['d1', 'execute', 'ADMIN_DB', '--local', '--config', config, '--command', sql, '--json']))[0].results;
    assert.deepEqual(query('SELECT name FROM d1_migrations ORDER BY id'), migrations.map(name => ({ name })));
    assert.deepEqual(query("SELECT name FROM sqlite_master WHERE type='trigger' AND name='collect_transaction_posted_verification'"), [{ name: 'collect_transaction_posted_verification' }]);
    assert.deepEqual(query('SELECT count(*) AS total FROM collect_transactions'), [{ total: 0 }]);
  } finally { await rm(directory, { recursive: true, force: true }); }
});
