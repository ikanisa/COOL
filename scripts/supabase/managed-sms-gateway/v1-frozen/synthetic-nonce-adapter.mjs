// The supplied GatewayDatabase must be bound to this exact application work;
// its first() resolves only after the fenced transaction COMMIT acknowledges.
import {applicationWorkTuple} from '../../../supabase/functions/_shared/application-fence.js';
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/,HEX=/^[a-f0-9]{64}$/;
export async function consumeSyntheticSmsNonce(db,work,value){
 applicationWorkTuple(work);
 if(typeof db?.prepare!=='function'||!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!=='issuedAtMs,nonce,policy,profile'||
  !UUID.test(value.nonce??'')||!HEX.test(value.profile??'')||!HEX.test(value.policy??'')||!Number.isSafeInteger(value.issuedAtMs)||value.issuedAtMs<=0)throw Error('sms_nonce_unavailable');
 try{const result=await db.prepare('SELECT collect_sms.consume_ingress_nonce(?::uuid,?::text,?::text,?::bigint) AS claimed')
  .bind(value.nonce,value.profile,value.policy,value.issuedAtMs).first('claimed');
  if(typeof result!=='boolean')throw Error();return result;
 }catch{try{work.abandon('work_lost');}catch{}throw Error('sms_nonce_unavailable');}
}
