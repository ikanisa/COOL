import {authorize} from './policy.js';
import {requirePort,requireThat} from './errors.js';
import {requireRequestId,exactKeys,sha256} from './values.js';
/** No new receiving wallet is created during replacement. The DB adapter must lock
 * the existing scope row; the partial unique index remains the final race barrier. */
export class GatewayRegistry {
  constructor({store,groupId,clock=()=>Date.now()}){requirePort(store,['withAuthorityTransaction','withReadSnapshot']);Object.assign(this,{store,groupId,clock});}
  async status(actor){
    return this.store.withReadSnapshot(async tx=>{
      requirePort(tx,['reloadActor','loadBinding','gatewayHealth']);
      const current=await tx.reloadActor(actor.sessionId),binding=await tx.loadBinding(this.groupId);
      authorize(current,this.groupId,'gateway.manage',{now:this.clock(),binding});
      requireThat(current.id===actor.id,'session_unavailable',401);
      const health=await tx.gatewayHealth(this.groupId,binding.id);
      requireThat(health&&Number.isSafeInteger(health.pending)&&health.pending>=0,'invalid_gateway_health',503);
      return {pending:health.pending,oldest:health.oldest??null,lastCapture:health.lastCapture??null,
        lastUpload:health.lastUpload??null,lastContact:health.lastContact??null,problem:health.problem??null};
    });
  }
  async pair(actor,command){
    exactKeys(command,['pairingCode','replace','requestId']);
    requireThat(/^[a-f0-9]{64}$/.test(command.pairingCode??'')&&command.replace===false,'invalid_pairing_code');
    requireRequestId(command.requestId);requirePort(this.store,['pair']);
    return this.store.pair(actor,command);
  }
  async replace(actor,command){
    exactKeys(command,['replacementCode','requestId']);requireRequestId(command.requestId);
    requireThat(/^[a-f0-9]{64}$/.test(command.replacementCode??''),'invalid_pairing_code');
    requirePort(this.store,['retire']);
    const fingerprint=await sha256('burimunsi.gateway.retire.v1:'+await sha256(command.replacementCode)+':'+command.requestId.toLowerCase());
    return this.store.retire(actor,command,fingerprint);
  }
}
