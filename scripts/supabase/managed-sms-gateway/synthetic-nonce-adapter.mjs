// The supplied GatewayDatabase must be bound to this exact application work;
// its first() resolves only after the fenced transaction COMMIT acknowledges.
import {applicationWorkTuple} from '../../../supabase/functions/_shared/application-fence.js';
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/,HEX=/^[a-f0-9]{64}$/;
export async function consumeSyntheticSmsNonce(db,work,value){
 applicationWorkTuple(work);
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!=='issuedAtMs,nonce,policy,profile'||
  !UUID.test(value.nonce??'')||!HEX.test(value.profile??'')||!HEX.test(value.policy??'')||!Number.isSafeInteger(value.issuedAtMs)||value.issuedAtMs<=0)throw Error('sms_nonce_unavailable');
 try{const {GatewayDatabase}=await import('../../../deploy/collect-sms/src/postgres.ts');
  if(!(db instanceof GatewayDatabase))throw Error();
  // Never trust a wrapper that may already carry another work admission. The
  // actual GatewayDatabase implementation constructs a fresh wrapper bound to
  // the caller's exact work and retains the original SQL pool/capacity.
  const bound=Object.freeze(GatewayDatabase.prototype.withApplicationWork.call(db,work));
  const result=await bound.prepare('SELECT collect_sms.consume_ingress_nonce(?::uuid,?::text,?::text,?::bigint) AS claimed')
  .bind(value.nonce,value.profile,value.policy,value.issuedAtMs).first('claimed');
  if(typeof result!=='boolean')throw Error();return result;
 }catch{try{work.abandon('work_lost');}catch{}throw Error('sms_nonce_unavailable');}
}
