// The handler still runs its production ingress and dispatch SQL adapters.
// Only these three statements can reach this in-memory database.
const state = () => globalThis.__nativeHandlerIntegration;
const nonceSql = 'SELECT private.collect_native_ingress_consume(?::uuid,?::text,?::text,?::bigint) AS claimed';
const claimSql = 'SELECT private.collect_managed_job_claim(?::uuid,?::text,?::text::jsonb,?::text) AS accepted';
const completeSql = 'SELECT private.collect_managed_job_complete(?::uuid,?::text,?::text) AS accepted';

export function connection() {
  state().events.push('connection');
  return {};
}
export const fenceConnection = () => ({});
export class PostgresDatabase {
  constructor() {
    state().events.push('database');
    this.sql = {};
  }
  setApplicationWork(work) {
    this.applicationWork = work;
    state().events.push('bind');
  }
  prepare(sql) {
    const h = state();
    h.events.push('prepare');
    if (![nonceSql, claimSql, completeSql].includes(sql)) throw Error('unexpected synthetic SQL');
    return {bind: (...args) => ({first: column => this.read(sql, args, column)})};
  }
  async read(sql, [id, source, value], column) {
    const h = state();
    if (sql === nonceSql) {
      if (this.applicationWork?.kind !== 'http_collect' || column !== 'claimed') throw Error('unexpected nonce context');
      h.events.push('claim');
      if (h.mode === 'error') throw Error('synthetic private error');
      if (h.mode === 'invalid') return 1;
      if (h.nonces.has(id)) return false;
      h.nonces.add(id);
      if (h.mode === 'hang') return new Promise(() => {});
      if (h.mode === 'lost') throw Error('synthetic lost commit acknowledgement');
      return true;
    }
    if (this.applicationWork?.kind !== 'jobs' || column !== undefined) throw Error('unexpected jobs context');
    if (sql === claimSql) {
      h.events.push('job_claim');
      if (h.jobs.has(id) || JSON.parse(value).dispatch_id !== id) return {accepted:false};
      h.jobs.set(id, {source});
      return {accepted:true};
    }
    h.events.push('job_complete');
    const job = h.jobs.get(id);
    if (!job || job.source !== source || job.digest || !/^[a-f0-9]{64}$/.test(value)) return {accepted:false};
    job.digest = value;
    return {accepted:true};
  }
}
