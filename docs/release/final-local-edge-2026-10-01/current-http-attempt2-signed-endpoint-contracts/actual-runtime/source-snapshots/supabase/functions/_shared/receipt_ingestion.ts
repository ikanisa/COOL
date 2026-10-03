import {PublicError,boundedJson,boundedText,uuid,zonedInstant,requireReceiptContract,validateReceiptAck,ReceiptAck} from './production_contract.ts';
import {hashPhone,sha256Hex} from './hash.ts';
export interface ReceiptDependencies {
  owner(request:Request):Promise<string>;
  version():Promise<unknown>;
  accept(params:Record<string,unknown>):Promise<unknown>;
  process(id:string):Promise<boolean>;
}
/** Dependency-injected orchestration used by both the deployed handler and tests. */
export async function acceptReceipt(request:Request, dependencies:ReceiptDependencies):Promise<ReceiptAck> {
  const owner=uuid(await dependencies.owner(request),'authentication_required');
  const p=await boundedJson(request,24576);
  const body=boundedText(p.raw_body,'invalid_receipt_body',4096,false);
  const sender=boundedText(p.raw_sender,'invalid_receipt_sender',96);
  const envelope=uuid(p.client_envelope_id,'invalid_envelope');
  const capability=uuid(p.native_capability,'invalid_capability');
  const group=p.collection_id==null?null:uuid(p.collection_id,'invalid_group');
  const receiver=await hashPhone(boundedText(p.receiver_momo_number,'invalid_receiver',40));
  if (!receiver) throw new PublicError('invalid_receiver');
  const time=zonedInstant(p.received_at_device);
  requireReceiptContract(await dependencies.version());
  const bodyHash=await sha256Hex(body);
  const ack=validateReceiptAck(await dependencies.accept({p_native_capability_id:capability,p_receiver_user_id:owner,p_collection_id:group,
    p_raw_sender:sender,p_raw_body:body,p_body_hash:bodyHash,p_client_envelope_id:envelope,p_receiver_momo_number_hash:receiver,p_received_at_device:time}),owner,envelope,bodyHash);
  // An uncertain parse attempt retains the mobile copy for idempotent retry.
  if (!await dependencies.process(ack.raw_sms_id)) throw new PublicError('receipt_stored_processing_retry',503);
  return ack;
}
