import {reserveDatabaseConnection} from '../application-fence.js';
import {ApiError} from '../domain/core.js';
import {lockCollectMutation} from '../postgres-mutation-lock.js';

const readSnapshot = /^BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY$/i;

// The journal must retain a fenced reservation until PostgreSQL acknowledges
// commit or rollback. Releasing the driver reservation alone cannot reset it.
export function storageApplicationPool(db) {
  function connect() {
    const work = db.applicationWork;
    if (!work) throw new ApiError(503, 'application_fence_unavailable', 'The configured service is unavailable.');

    return work.waitUntil((async () => {
      await work.assert();
      const raw = await reserveDatabaseConnection(db.sql);
      let released = false;
      let inTransaction = false;
      let settle;
      const ownsConnection = new Promise(resolve => { settle = resolve; });
      work.waitUntil(ownsConnection);

      function query(text, values = []) {
        return work.waitUntil((async () => {
          const rollback = /^ROLLBACK\b/i.test(text);
          const begin = /^BEGIN\b/i.test(text);
          // A lost work assertion must still permit an attempted rollback.
          if (!rollback) await work.assert();
          if (begin) inTransaction = true;
          let result;
          try {
            // postgres.js serializes JSONB using the inferred PostgreSQL type.
            result = await raw.unsafe(text, values);
          } catch (error) {
            if (rollback) work.abandon('work_lost');
            throw error;
          }
          if (rollback || /^COMMIT\b/i.test(text)) inTransaction = false;
          if (begin) {
            if (readSnapshot.test(text)) await db.readContext(raw);
            else {
              await db.context(raw);
              await lockCollectMutation(raw);
            }
          }
          return {rows: Array.from(result), rowCount: result.count ?? result.length};
        })());
      }

      function release() {
        if (released) return;
        released = true;
        try {
          if (inTransaction) work.abandon('work_lost');
          else raw.release();
        } finally {
          settle();
        }
      }

      return {raw, query, release};
    })());
  }

  async function transaction(run) {
    const client = await connect();
    try {
      await client.query('BEGIN');
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  return {connect, transaction, query: (text, values = []) => transaction(client => client.query(text, values))};
}
