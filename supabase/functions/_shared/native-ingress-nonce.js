// The caller must verify the signed ingress witness before calling this module.
// PostgresDatabase resolves first() only after its fenced transaction commits.
const UUID_V4=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const SHA256=/^[a-f0-9]{64}$/;
export const NATIVE_INGRESS_CLAIM_TIMEOUT_MS=8000;
const unavailable=()=>new Error('native_ingress_store_unavailable');

export async function consumeNativeIngressNonce(db,work,values){
 if(typeof db?.prepare!=='function'||typeof work?.abandon!=='function'||!values||typeof values!=='object'||Array.isArray(values)||
  Object.keys(values).sort().join(',')!=='issuedAtMs,nonce,policy,profile'||
  typeof values.nonce!=='string'||!UUID_V4.test(values.nonce)||
  typeof values.profile!=='string'||!SHA256.test(values.profile)||typeof values.policy!=='string'||!SHA256.test(values.policy)||
  !Number.isSafeInteger(values.issuedAtMs)||values.issuedAtMs<=0)throw unavailable();
 const operation=Promise.resolve().then(()=>db.prepare(
  'SELECT private.collect_native_ingress_consume(?::uuid,?::text,?::text,?::bigint) AS claimed'
 ).bind(values.nonce,values.profile,values.policy,values.issuedAtMs).first('claimed'));
 let timer;
 try{
  const claimed=await Promise.race([operation,new Promise((_,reject)=>{
   timer=setTimeout(()=>reject(unavailable()),NATIVE_INGRESS_CLAIM_TIMEOUT_MS);
  })]);
  if(typeof claimed!=='boolean')throw unavailable();
  return claimed;
 }catch{
  // A lost or late commit acknowledgement may have consumed the nonce. The
  // tracked original operation is never retried and this work is abandoned.
  try{work.abandon('work_lost');}catch{}
  throw unavailable();
 }finally{clearTimeout(timer);}
}
