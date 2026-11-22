import { DatabaseSync } from 'node:sqlite';
import {
  decodeJournalRows, decodeJournalValue, encodeJournalValue, journalFailure, journalKey,
  journalTable, MAX_JSON_BYTES, normalizeJournalFailure, runJournalAction, TABLES,
} from './journal-data.mjs';
import { PrivateJournalPath } from './journal-path.mjs';

const APPLICATION_ID = 0x43444a31;
const VERSION = 1;
const DATA_COLUMN = `data TEXT NOT NULL CHECK (length(CAST(data AS BLOB)) BETWEEN 1 AND ${MAX_JSON_BYTES} AND json_valid(data))`;
const SCHEMA = new Map(TABLES.map((table) => [
  table, `CREATE TABLE ${table} (key TEXT PRIMARY KEY NOT NULL, ${DATA_COLUMN}) STRICT`,
]));
SCHEMA.set('events', `CREATE TABLE events (seq INTEGER PRIMARY KEY AUTOINCREMENT, ${DATA_COLUMN}) STRICT`);

export class SqliteDesktopJournal {
  #db;
  #location;
  #busy = false;
  #closed = false;

  get durable() { return true; }

  constructor(path) {
    try {
      this.#location = new PrivateJournalPath(path);
      const initialize = this.#location.emptyAtOpen;
      this.#location.assertCurrent();
      this.#db = new DatabaseSync(path, {
        allowExtension: false, enableDoubleQuotedStringLiterals: false,
        enableForeignKeyConstraints: true, timeout: 500,
      });
      this.#db.exec('PRAGMA busy_timeout=500; PRAGMA trusted_schema=OFF; PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; PRAGMA temp_store=MEMORY');
      this.#location.assertCurrent();
      this.#db.exec('BEGIN');
      this.#checkSchema(initialize);
      this.#db.exec('COMMIT');
      if (this.#db.prepare('PRAGMA journal_mode').get().journal_mode !== 'delete') throw journalFailure('journal_corrupt');
      this.#db.exec('PRAGMA journal_mode=DELETE');
      this.#db.exec('BEGIN IMMEDIATE');
      this.#location.assertCurrent();
      if (this.#checkSchema(initialize)) {
        for (const sql of SCHEMA.values()) this.#db.exec(sql);
        this.#db.exec(`PRAGMA application_id=${APPLICATION_ID}; PRAGMA user_version=${VERSION}`);
      }
      this.#checkSchema(false);
      const check = this.#db.prepare('PRAGMA quick_check(1)').all();
      if (check.length !== 1 || check[0].quick_check !== 'ok') throw journalFailure('journal_corrupt');
      this.#location.assertCurrent();
      this.#db.exec('COMMIT');
      this.#location.syncParent();
      this.#location.assertCurrent();
    } catch (error) {
      this.#dispose();
      throw normalizeJournalFailure(error);
    }
  }

  #checkSchema(initialize) {
    const application = this.#db.prepare('PRAGMA application_id').get().application_id;
    const version = this.#db.prepare('PRAGMA user_version').get().user_version;
    const schema = this.#db.prepare(`SELECT type, name, sql FROM sqlite_schema WHERE substr(name,1,7) <> 'sqlite_' ORDER BY name LIMIT ${SCHEMA.size + 1}`).all();
    // BEGIN IMMEDIATE allocates page 1 before the first table is created.
    if (initialize && application === 0 && version === 0 && schema.length === 0
        && this.#db.prepare('PRAGMA page_count').get().page_count <= (this.#db.isTransaction ? 1 : 0)) return true;
    if (application !== APPLICATION_ID || version !== VERSION || schema.length !== SCHEMA.size
        || schema.some((row) => row.type !== 'table' || SCHEMA.get(row.name) !== row.sql)) {
      throw journalFailure('journal_corrupt');
    }
    return false;
  }

  #rows(sql) {
    return decodeJournalRows((function* (statement) {
      for (const row of statement.iterate()) yield row.data;
    })(this.#db.prepare(sql)));
  }

  #run(action, callback = false) {
    if (this.#closed || this.#busy) throw journalFailure('journal_unavailable');
    this.#busy = true;
    let callbackError;
    try {
      this.#location.assertCurrent();
      this.#db.exec('BEGIN IMMEDIATE');
      this.#location.assertCurrent();
      this.#checkSchema(false);
      let result;
      try {
        result = action();
      } catch (error) {
        if (callback) callbackError = { error };
        throw error;
      }
      this.#location.assertCurrent();
      this.#db.exec('COMMIT');
      this.#location.syncParent();
      this.#location.assertCurrent();
      return result;
    } catch (error) {
      try {
        if (this.#db.isTransaction) this.#db.exec('ROLLBACK');
      } catch {
        this.#dispose();
      }
      if (callbackError) throw callbackError.error;
      throw normalizeJournalFailure(error);
    } finally {
      this.#busy = false;
    }
  }

  transaction(action) {
    return this.#run(() => runJournalAction(action, {
      get: (table, key) => {
        const row = this.#db.prepare(`SELECT data FROM ${journalTable(table)} WHERE key=?`).get(journalKey(key));
        return row ? decodeJournalValue(row.data) : null;
      },
      put: (table, key, value) => {
        const sql = `INSERT INTO ${journalTable(table)} (key, data) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET data=excluded.data`;
        this.#db.prepare(sql).run(journalKey(key), encodeJournalValue(value));
      },
      all: (table) => this.#rows(`SELECT data FROM ${journalTable(table)} ORDER BY key`),
      append: (event) => { this.#db.prepare('INSERT INTO events (data) VALUES (?)').run(encodeJournalValue(event)); },
    }), true);
  }

  events() {
    return this.#run(() => this.#rows('SELECT data FROM events ORDER BY seq'));
  }

  #dispose() {
    this.#closed = true;
    if (this.#db?.isOpen) {
      try { this.#db.close(); } catch { /* Preserve the original safe failure. */ }
    }
    this.#location?.close();
  }

  close() {
    if (this.#busy) throw journalFailure('journal_unavailable');
    if (this.#closed) return;
    this.#dispose();
  }
}

export class MemoryDesktopJournal {
  #tables = new Map(TABLES.map((table) => [table, new Map()]));
  #events = [];
  #closed = false;
  #busy = false;

  get durable() { return false; }

  transaction(action) {
    if (this.#closed || this.#busy) throw journalFailure('journal_unavailable');
    this.#busy = true;
    const tables = new Map([...this.#tables].map(([table, data]) => [table, new Map(data)]));
    const events = [...this.#events];
    try {
      const result = runJournalAction(action, {
        get: (table, key) => {
          const data = tables.get(journalTable(table)).get(journalKey(key));
          return data === undefined ? null : decodeJournalValue(data);
        },
        put: (table, key, value) => { tables.get(journalTable(table)).set(journalKey(key), encodeJournalValue(value)); },
        all: (table) => decodeJournalRows([...tables.get(journalTable(table))].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([, data]) => data)),
        append: (event) => { events.push(encodeJournalValue(event)); },
      });
      this.#tables = tables;
      this.#events = events;
      return result;
    } finally {
      this.#busy = false;
    }
  }

  events() {
    if (this.#closed || this.#busy) throw journalFailure('journal_unavailable');
    return decodeJournalRows(this.#events);
  }

  close() {
    if (this.#busy) throw journalFailure('journal_unavailable');
    this.#closed = true;
  }
}
