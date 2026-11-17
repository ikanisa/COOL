import {requirePort,requireThat} from './errors.js';
import {requireId} from './values.js';
import {applyPhonePinContext} from './phone-pin-request.js';

// This is the lock used by Collect PostgresDatabase.batch at the pinned source.
// Keep it until a reviewed change covers ALL financial and authority writers.
export const COLLECT_MUTATION_LOCK='734636924058501';

/** Scoped transaction context over Collect's existing PostgresDatabase.
 * No new pool, service key, fake actor, SECURITY DEFINER, or nested transaction.
 * The existing db.transaction owns COMMIT/ROLLBACK and connection quarantine.
 */
export class PostgresNativeAuthority {
  constructor({db,groupId}) {
    requirePort(db,['transaction','context','readContext']);requireId(groupId);
    requirePort(db.applicationWork,['assert']);
    this.db=db;this.groupId=groupId;this.work=db.applicationWork;
  }
  async assertOwned() {
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
    await this.work.assert();
    // The admission can be replaced while its asynchronous assertion settles.
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
  }
  async run(readOnly,fn) {
    requireThat(typeof fn==='function','collect_adapter_required',503);
    await this.assertOwned();
    return this.db.transaction(async tx=>{
      requirePort(tx,['unsafe']);await this.assertOwned();
      if(readOnly) {
        await tx.unsafe('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');
        await this.db.readContext(tx,{isolation:'repeatable read'});
      } else {
        await this.db.context(tx);
        await tx.unsafe(`SELECT pg_advisory_xact_lock(${COLLECT_MUTATION_LOCK}::bigint)`);
      }
      await tx.unsafe("SELECT set_config('burimunsi.collection_id',$1,true)",[this.groupId]);
      await applyPhonePinContext(this.db,tx,this.groupId);
      await this.assertOwned();
      const result=await fn(tx);
      // A revoked/replaced admission must roll back, not publish callback success.
      await this.assertOwned();return result;
    });
  }
  write(fn){return this.run(false,fn);}
  read(fn){return this.run(true,fn);}
}
