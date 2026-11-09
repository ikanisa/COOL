import {authorize} from './policy.js';
import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId,exactKeys,sha256,canonicalJson} from './values.js';
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
  async replace(actor,command){
    exactKeys(command,['installationId','expectedBindingId','expectedVersion','requestId']);
    requireId(command.installationId);requireId(command.expectedBindingId);command.requestId=requireRequestId(command.requestId);
    requireThat(Number.isSafeInteger(command.expectedVersion)&&command.expectedVersion>0,'invalid_version');
    const fingerprint=await sha256(canonicalJson(command));
    return this.store.withAuthorityTransaction(async tx=>{
      requirePort(tx,['reloadActor','lockScope','retainedCommand','retainCommand','revokeGateway','activateGateway','approvedInstallation','audit']);
      const current=await tx.reloadActor(actor.sessionId);
      authorize(current,this.groupId,'staff.manage',{now:this.clock()});requireThat(current.id===actor.id,'session_unavailable',401);
      const old=await tx.retainedCommand(this.groupId,current.id,command.requestId);
      if(old){requireThat(old.fingerprint===fingerprint&&old.sessionId===current.sessionId,'idempotency_conflict',409);return old.response;}
      const scope=await tx.lockScope(this.groupId);
      requireThat(scope?.activeBindingId===command.expectedBindingId&&scope?.bindingVersion===command.expectedVersion,'gateway_changed',409);
      const approved=await tx.approvedInstallation(this.groupId,command.installationId);
      requireThat(approved?.active&&approved.profile==='internal_receiver'&&approved.custodianAccountId===current.id,'installation_not_authorized',403);
      await tx.revokeGateway(scope.activeBindingId,scope.bindingVersion);
      const response=await tx.activateGateway({groupId:this.groupId,installationId:command.installationId,receivingAccountId:scope.receivingAccountId,
        previousBindingId:scope.activeBindingId,expectedScopeVersion:scope.version,actorId:current.id,requestId:command.requestId});
      requireThat(response?.receivingAccountId===scope.receivingAccountId&&response?.installationId===command.installationId,'gateway_contract_violation',503);
      await tx.audit({action:'burimunsi.gateway.replaced',actorId:current.id,oldBindingId:scope.activeBindingId,newBindingId:response.id,requestId:command.requestId});
      await tx.retainCommand({groupId:this.groupId,actorId:current.id,sessionId:current.sessionId,requestId:command.requestId,fingerprint,response});return response;
    });
  }
}
