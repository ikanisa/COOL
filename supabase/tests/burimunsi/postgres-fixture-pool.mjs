// Test-only adapter for the PostgreSQL wire interface used by the native stores.
import assert from 'node:assert/strict';
import {readFileSync, realpathSync, statSync} from 'node:fs';
import {join} from 'node:path';
import pg from '../../../scripts/supabase/node_modules/pg/lib/index.js';

const integerTypes = {
  getTypeParser(oid, format) {
    if ((oid === 20 || oid === 1700) && (format === 'text' || format === undefined)) {
      return value => {
        const number = Number(value);
        if (!/^-?\d+(?:\.0+)?$/.test(value) || !Number.isSafeInteger(number)) {
          throw Error('integer_out_of_range');
        }
        return number;
      };
    }
    return pg.types.getTypeParser(oid, format);
  },
};

export async function ownedFixturePool({root, socket, port, database, user, clusterName}) {
  assert.match(root, /^\/(?:private\/)?tmp\/collect-pg-transfer-[a-zA-Z0-9]+$/);
  assert.equal(realpathSync(root), root);
  assert.equal(realpathSync(socket), join(root, 's'));
  for (const path of [root, socket]) {
    const info = statSync(path);
    assert(info.isDirectory() && info.uid === process.getuid() && (info.mode & 0o777) === 0o700);
  }
  assert(Number.isInteger(port) && port > 0 && port <= 65535);
  const [,data,,reportedPort,reportedSocket] = readFileSync(join(root,'db','postmaster.pid'),'utf8').split('\n');
  assert.deepEqual([data,reportedPort,reportedSocket],[join(root,'db'),String(port),socket]);
  assert.match(database, /^[a-z][a-z0-9_]{0,62}$/);
  assert.match(user, /^(?:postgres|fixture_bootstrap|collect_fixture)$/);
  assert.match(clusterName, /^[a-z_]+$/);
  const pool = new pg.Pool({
    host: socket, port, database, user, password: '', ssl: false,
    max: 6, connectionTimeoutMillis: 5000, statement_timeout: 15000,
    lock_timeout: 5000, types: integerTypes,
  });
  pool.on('error', () => {});
  const reservations = new Set();
  try {
    const {rows} = await pool.query(`SELECT current_database() AS database, session_user AS actor,
      current_setting('cluster_name') AS cluster,
      current_setting('server_version_num')::int / 10000 AS major,
      inet_server_addr() IS NULL AND current_setting('listen_addresses') = '' AS socket_only`);
    assert.deepEqual(rows, [{database, actor:user, cluster:clusterName, major:17, socket_only:true}]);
  } catch (error) {
    await pool.end();
    throw error;
  }
  async function reserve() {
    const client = await pool.connect();
    const unsafe = async (statement, values = []) => {
      const result = await client.query(statement, values);
      assert(!Array.isArray(result), 'Use fixtureScript for multiple SQL statements');
      Object.defineProperty(result.rows, 'count', {value:result.rowCount ?? 0});
      return result.rows;
    };
    const sql = (parts, ...values) => unsafe(parts.reduce((text, part, i) => text + (i ? '$' + i : '') + part, ''), values);
    sql.unsafe = unsafe;
    sql.fixtureScript = text => client.query(text);
    sql.release = discard => {
      if (reservations.delete(sql)) client.release(discard);
    };
    reservations.add(sql);
    return sql;
  }
  return {
    reserve,
    async begin(options, operation) {
      if (typeof options === 'function') {
        operation = options;
        options = '';
      }
      const sql = await reserve();
      let discard = false;
      try {
        await sql.unsafe('BEGIN ' + options);
        const value = await operation(sql);
        await sql.unsafe('COMMIT');
        return value;
      } catch (error) {
        try { await sql.unsafe('ROLLBACK'); } catch { discard = true; }
        throw error;
      } finally {
        sql.release(discard);
      }
    },
    async end() {
      for (const sql of reservations) sql.release(true);
      await pool.end();
    },
  };
}
