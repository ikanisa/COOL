import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { evaluateAlerts, serviceMetrics } from '../src/metrics.ts';
import type { Env } from '../src/types.ts';

type SqlValue = string | number | null;

class Statement {
  constructor(readonly query: string, readonly values: SqlValue[] = []) {}
  bind(...values: SqlValue[]) { return new Statement(this.query, values); }
}

class SyntheticDatabase {
  readonly sqlite = new DatabaseSync(':memory:');
  afterRead?: () => void;
  constructor() {
    this.sqlite.exec(`
      PRAGMA temp_store=MEMORY;
      CREATE TABLE messages(kind TEXT,state TEXT,not_after TEXT,cancel_requested INTEGER,
        created_at TEXT,updated_at TEXT,to_number TEXT,text TEXT);
      CREATE TABLE devices(ready INTEGER,last_seen_at TEXT,fcm_last_error TEXT,revoked_at TEXT);
      CREATE TABLE webhook_deliveries(state TEXT,created_at TEXT);
      CREATE TABLE applications(application_id TEXT,revoked_at TEXT);
      CREATE TABLE application_outbox_health(application_id TEXT,sampled_at TEXT,
        pending_count INTEGER,failed_count INTEGER,oldest_pending_at TEXT);
      CREATE TABLE metric_alert_events(event_id TEXT,alert_key TEXT,transition TEXT,at TEXT);
      CREATE TABLE metric_alerts(alert_key TEXT PRIMARY KEY,severity TEXT,active INTEGER,
        first_seen_at TEXT,last_seen_at TEXT,resolved_at TEXT);
    `);
  }
  prepare(query: string) { return new Statement(query); }
  async batch(statements: Statement[]) {
    const results = statements.map((statement) => ({
      success: true,
      results: this.sqlite.prepare(statement.query).all(...statement.values).map((row) => ({ ...row })),
      meta: { changes: 0 },
    }));
    this.afterRead?.();
    return results;
  }
  environment(): Env {
    return { DB: this, ROOT_ADMIN_TOKEN: 'synthetic', OTP_HMAC_KEY: 'synthetic' } as unknown as Env;
  }
  close() { this.sqlite.close(); }
}

const instant = Date.UTC(2026, 10, 4, 12);
const iso = (delta: number) => new Date(instant + delta).toISOString();
const privateBody = 'SYNTHETIC_PRIVATE_MESSAGE_BODY';
const privateNumber = 'SYNTHETIC_PRIVATE_NUMBER';

function addMessage(db: SyntheticDatabase, state: string, deadline: number, cancelled = 0, kind = 'receipt') {
  db.sqlite.prepare('INSERT INTO messages VALUES(?,?,?,?,?,?,?,?)').run(
    kind, state, iso(deadline), cancelled, iso(-10000), iso(-1000), privateNumber, privateBody,
  );
}

function messageSnapshot(db: SyntheticDatabase) {
  return db.sqlite.prepare('SELECT * FROM messages ORDER BY rowid').all().map((row) => ({ ...row }));
}

test('observations count handoff and overdue states at one captured instant without exposing messages', async (t) => {
  const db = new SyntheticDatabase();
  t.after(() => db.close());
  addMessage(db, 'accepted', -1);
  addMessage(db, 'accepted', 0, 1);
  addMessage(db, 'accepted', 1);
  addMessage(db, 'assigned', -1, 1);
  addMessage(db, 'assigned', 1);
  addMessage(db, 'phone_accepted', -1, 1);
  addMessage(db, 'queued', -1);
  addMessage(db, 'queued', 1);
  addMessage(db, 'handoff_started', 1000);
  addMessage(db, 'handoff_started', -1, 1);
  for (const state of ['sent', 'delivered', 'delivery_unconfirmed', 'partial', 'expired', 'cancelled', 'failed', 'outcome_unknown']) {
    addMessage(db, state, -1, 1);
  }
  db.sqlite.prepare('INSERT INTO devices VALUES(?,?,?,?)').run(1, iso(-89999), null, null);
  db.sqlite.prepare('INSERT INTO applications VALUES(?,?)').run('synthetic-app', null);
  db.sqlite.prepare('INSERT INTO application_outbox_health VALUES(?,?,?,?,?)').run(
    'synthetic-app', iso(-299999), 1, 0, iso(-299999),
  );
  const before = messageSnapshot(db);
  let clock = instant;
  const dateNow = t.mock.method(Date, 'now', () => clock);
  db.afterRead = () => { clock = instant + 60000; };

  const result = await serviceMetrics(db.environment());

  assert.equal(dateNow.mock.callCount(), 1);
  assert.equal(result.observed_at, iso(0));
  assert.deepEqual(result.delivery_observations, {
    handoff_started: 2,
    overdue: { accepted: 2, assigned: 1, phone_accepted: 1, queued: 1 },
  });
  assert.deepEqual(result.queue.map((row) => ({ kind: row.kind, count: row.count, oldest_age_seconds: row.oldest_age_seconds })),
    [{ kind: 'receipt', count: 3, oldest_age_seconds: 10 }]);
  assert.equal(result.devices?.ready, 1);
  assert.equal(result.application_outboxes[0]?.stale, false);
  assert.deepEqual(result.outcomes.map((row) => row.state).sort(), ['outcome_unknown', 'partial']);
  assert.match(result.notice, /observations, not proof of delivery failure/);
  assert.ok(!JSON.stringify(result).includes(privateBody));
  assert.ok(!JSON.stringify(result).includes(privateNumber));
  assert.deepEqual(messageSnapshot(db), before);
});

test('existing alerts retain their scopes and evaluate against the same observation time', async (t) => {
  const db = new SyntheticDatabase();
  t.after(() => db.close());
  addMessage(db, 'handoff_started', -1, 1);
  addMessage(db, 'assigned', -1, 1);
  addMessage(db, 'outcome_unknown', -1);
  db.sqlite.prepare('INSERT INTO devices VALUES(?,?,?,?)').run(1, iso(-1000), null, null);
  db.sqlite.prepare('INSERT INTO applications VALUES(?,?)').run('synthetic-app', null);
  db.sqlite.prepare('INSERT INTO application_outbox_health VALUES(?,?,?,?,?)').run(
    'synthetic-app', iso(-299999), 1, 0, iso(-299999),
  );
  const before = messageSnapshot(db);
  let clock = instant;
  const dateNow = t.mock.method(Date, 'now', () => clock);
  db.afterRead = () => { clock = instant + 60000; };

  const result = await evaluateAlerts(db.environment());

  assert.equal(dateNow.mock.callCount(), 1);
  assert.equal(result.evaluated_at, iso(0));
  assert.equal(result.conditions, 10);
  const alerts = db.sqlite.prepare('SELECT alert_key,active FROM metric_alerts ORDER BY alert_key').all()
    .map((row) => ({ ...row }));
  assert.deepEqual(alerts.filter((row) => row.active === 1).map((row) => row.alert_key), ['uncertain_delivery']);
  assert.deepEqual(messageSnapshot(db), before);
});
