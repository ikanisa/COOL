import {authorize} from './policy.js';
import {requireThat} from './errors.js';
/** Re-read at the transaction boundary, including exact session identity.
 * An account match alone cannot authorize a replaced session's continuation. */
export async function revalidateCommandActor(tx,original,groupId,capability,now) {
  const id=original?.id,sessionId=original?.sessionId;
  const actor=await tx.reloadActor(sessionId);
  authorize(actor,groupId,capability,{now});
  requireThat(actor.id===id&&actor.sessionId===sessionId,'session_unavailable',401);
  return Object.freeze({...actor,capabilities:Object.freeze([...actor.capabilities])});
}
