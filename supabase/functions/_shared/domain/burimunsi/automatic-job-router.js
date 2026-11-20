import {requirePort,requireThat} from './errors.js';
import {automaticWork} from './automatic-work.js';
/** Closed work-kind routing; never falls back to another job's authority. */
export function automaticJobRouter(receipts,rematches) {
  requirePort(receipts,['assertPostingLease']);requirePort(rematches,['assertPostingLease','retainAutomaticOutcome']);
  return Object.freeze({
    assertPostingLease(sql,command) {
      const work=automaticWork(command.work);
      return (work.kind==='receipt'?receipts:rematches).assertPostingLease(sql,{...command,work});
    },
    retainAutomaticOutcome(sql,command) {
      const work=automaticWork(command.work);requireThat(work.kind==='rematch','automatic_work_required',503);
      return rematches.retainAutomaticOutcome(sql,{...command,work});
    }
  });
}
