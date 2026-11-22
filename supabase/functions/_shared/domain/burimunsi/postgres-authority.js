import {requirePort,requireThat} from './errors.js';
import {requireId} from './values.js';
import {applyPhonePinContext,hasPhonePinContext} from './phone-pin-request.js';
import {lockCollectMutation} from '../../postgres-mutation-lock.js';

export {COLLECT_MUTATION_LOCK} from '../../postgres-mutation-lock.js';

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
  async #run(mode,fn) {
    requireThat(typeof fn==='function','collect_adapter_required',503);
    await this.assertOwned();
    return this.db.transaction(async tx=>{
      requirePort(tx,['unsafe']);await this.assertOwned();
      if(mode==='read') {
        await tx.unsafe('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');
        await this.db.readContext(tx,{isolation:'repeatable read'});
      } else {
        await this.db.context(tx);
        if(mode!=='attempts'||hasPhonePinContext(this.db)){
          await lockCollectMutation(tx);
        }
      }
      await tx.unsafe("SELECT set_config('burimunsi.collection_id',$1,true)",[this.groupId]);
      await applyPhonePinContext(this.db,tx,this.groupId);
      await this.assertOwned();
      const result=await fn(tx);
      // A revoked/replaced admission must roll back, not publish callback success.
      await this.assertOwned();return result;
    });
  }
  write(fn){return this.#run('write',fn);}
  read(fn){return this.#run('read',fn);}

  async consumeAttempts(buckets,now) {
    requireThat(Array.isArray(buckets)&&buckets.length>=1&&buckets.length<=8&&Number.isSafeInteger(now),'invalid_rate_policy',503);
    const windows=buckets.map(({key,limit,windowMs})=>{
      requireThat(typeof key==='string'&&key.length<=200&&Number.isInteger(limit)&&limit>0&&Number.isSafeInteger(windowMs)&&windowMs>=1000,
        'invalid_rate_policy',503);
      return {key,limit,windowMs,start:Math.floor(now/windowMs)*windowMs};
    });
    // The unique counter rows serialize overlapping requests. Take their locks
    // in key and window order across callers. Phone-PIN proof still uses the
    // shared authority lock to coordinate with concurrent session changes.
    windows.sort((a,b)=>{
      if(a.key===b.key)return a.start-b.start;
      return a.key<b.key?-1:1;
    });
    return this.#run('attempts',async tx=>{
      let admitted=true;
      for(const {key,limit,windowMs,start} of windows){
        const result=await tx.unsafe(`INSERT INTO private.burimunsi_rate_limits(collection_id,bucket,window_start,window_ms,attempts,expires_at)
          VALUES($1,$2,$3,$4,1,$5) ON CONFLICT(collection_id,bucket,window_start)
          DO UPDATE SET attempts=private.burimunsi_rate_limits.attempts+1 RETURNING attempts`,[this.groupId,key,start,windowMs,start+windowMs]);
        if(Number(result[0].attempts)>limit)admitted=false;
      }
      return admitted; // Charge denied requests as well.
    });
  }
}
