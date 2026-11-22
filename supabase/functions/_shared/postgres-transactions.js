import {applicationWorkTuple,fenceFailure,reserveDatabaseConnection} from './application-fence.js';

// Request-scoped PostgreSQL transactions share the original admission and claims.
// The compatibility adapter translates SQL dialects and statement results.
export class PostgresTransactions {
  constructor(sql, claims = {}, work = null) { this.sql=sql; this.claims=claims; this.applicationWork=work; }
  setApplicationWork(work) { applicationWorkTuple(work); this.applicationWork=work; }
  setClaims(claims) { this.claims=claims; }
  async readContext(tx,{isolation='repeatable read'}={}) {
    // This path cannot grant write authority: the server must already enforce a
    // genuine read-only transaction at the requested closed isolation level
    // before role/claims setup. Existing callers retain repeatable-read.
    if(!['repeatable read','read committed'].includes(isolation))throw fenceFailure(null);
    await this.#readContext(tx,isolation,'on');
  }
  async #readContext(tx,isolation,readOnly) {
    const work=this.applicationWork;if(!work)throw fenceFailure(null);await work.assert();
    const mode=await tx.unsafe("SELECT pg_catalog.current_setting('transaction_read_only') AS transaction_read_only,pg_catalog.current_setting('transaction_isolation') AS transaction_isolation");
    if(mode[0]?.transaction_read_only!==readOnly||mode[0]?.transaction_isolation!==isolation)throw fenceFailure(null);
    await tx`set local role collect_runtime`;
    await tx`select pg_catalog.set_config('search_path','app,public,pg_catalog',true),pg_catalog.set_config('request.jwt.claims',${JSON.stringify(this.claims)},true),pg_catalog.set_config('collect.edge_verified','true',true)`;
    await tx`select pg_catalog.set_config('statement_timeout','15s',true),pg_catalog.set_config('lock_timeout','5s',true)`;
  }
  async context(tx) {
    const work=this.applicationWork;if(!work)throw fenceFailure(null);await work.assert();const tuple=applicationWorkTuple(work);
    await tx`set local role collect_runtime`;
    await tx`select pg_catalog.set_config('search_path','app,public,pg_catalog',true),pg_catalog.set_config('request.jwt.claims',${JSON.stringify(this.claims)},true),pg_catalog.set_config('collect.edge_verified','true',true),pg_catalog.set_config('collect.fence_admission_id',${tuple[0]},true),pg_catalog.set_config('collect.fence_epoch',${String(tuple[1])},true),pg_catalog.set_config('collect.fence_source_sha256',${tuple[2]},true)`;
    try {const rows=await tx`select private.collect_fence_assert_write(${tuple[0]}::uuid,${tuple[1]}::bigint,${tuple[2]}::text) as result`;const result=rows[0]?.result;if(result?.contractVersion!==1||result.epoch!==tuple[1]||!['open','quiescing'].includes(result.mode))throw new Error('collect_fence_unavailable');}catch(error){throw fenceFailure(error);}
    await tx`select pg_catalog.set_config('statement_timeout','15s',true),pg_catalog.set_config('lock_timeout','5s',true)`;
  }
  transaction(fn) {
    return this.#transaction(fn);
  }
  #transaction(fn,lockReadSnapshot=false) {
    const work=this.applicationWork;if(!work)throw fenceFailure(null);
    return work.waitUntil((async()=>{
      await work.assert();const tx=await reserveDatabaseConnection(this.sql);let idleConfirmed=false;
      try {
        await tx.unsafe(lockReadSnapshot?'BEGIN ISOLATION LEVEL REPEATABLE READ READ WRITE':'BEGIN ISOLATION LEVEL READ COMMITTED');
        const result=await fn(tx);
        if(!lockReadSnapshot){await tx.unsafe('COMMIT');idleConfirmed=true;}
        return result;
      } finally {
        if(!idleConfirmed){
          try{await tx.unsafe('ROLLBACK');idleConfirmed=true;}
          catch(error){work.abandon('work_lost');if(lockReadSnapshot)throw fenceFailure(error);}
        }
        // Releasing a postgres.js reservation does not reset its transaction.
        // Keep unconfirmed connections out of the pool.
        if(idleConfirmed)tx.release();
      }
    })());
  }

  // Identity and permission SELECTs take row locks, which require READ WRITE.
  // Use a guarded repeatable-read snapshot without mutation admission and
  // always roll back after materializing the projections.
  withLockedReadSnapshot(read) {
    const work=this.applicationWork;
    return this.#transaction(async tx=>{
      await this.#readContext(tx,'repeatable read','off');
      const result=await read(tx);
      await work.assert();
      if(this.applicationWork!==work)throw fenceFailure(null);
      return result;
    },true);
  }
}
