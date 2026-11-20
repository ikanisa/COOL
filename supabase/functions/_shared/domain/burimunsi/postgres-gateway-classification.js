import {BuriError,requirePort,requireThat} from './errors.js';

export const GATEWAY_CLASSIFICATION_SQL='SELECT private.burimunsi_gateway_pair_classify(?) AS classification';
// Root's legacy pairing guard must repeat this condition inside its existing
// mutation-lock batch before claim/credential delivery. The initial classifier
// batch alone cannot close a scope change between two transactions.
export const NON_BURIMUNSI_PAIR_CONDITION=`private.burimunsi_gateway_pair_classify(?) = '{"kind":"non_burimunsi"}'::jsonb`;

/** Server-only routing projection. No route, pool, lease, provider, credential or
 * fallback is installed here. Missing SQL is a closed release prerequisite.
 * Only the explicit non_burimunsi DTO may select root's existing legacy pair;
 * every blocked/error/missing/disabled/wrong configured Buri target throws.
 */
export async function classifyGatewayPair({env,codeHash}){
 requireThat(typeof codeHash==='string'&&codeHash.length===64&&/^[a-f0-9]{64}$/.test(codeHash),'invalid_pairing_code',400);
 const db=env?.DB;requirePort(db,['prepare','batch']);const work=db.applicationWork;
 requirePort(work,['assert']);
 const group=env.BURIMUNSI_COLLECTION_ID,enabled=env.BURIMUNSI_NATIVE_ENABLED;
 const owned=async()=>{
  requireThat(env.DB===db&&db.applicationWork===work,'request_not_admitted',503);
  try{await work.assert();}catch{throw new BuriError('request_not_admitted',503);}
  requireThat(env.DB===db&&db.applicationWork===work&&env.BURIMUNSI_COLLECTION_ID===group&&
   env.BURIMUNSI_NATIVE_ENABLED===enabled,'request_not_admitted',503);
 };
 await owned();let batch;
 try{batch=await db.batch([db.prepare(GATEWAY_CLASSIFICATION_SQL).bind(codeHash)]);}
 catch{await owned();throw new BuriError('gateway_classification_unavailable',503);}
 await owned();
 const valid=(value,keys)=>value&&Object.getPrototypeOf(value)===Object.prototype&&
  Object.keys(value).length===keys.length&&keys.every(key=>Object.hasOwn(value,key));
 requireThat(Array.isArray(batch)&&batch.length===1&&batch[0]?.success===true&&Array.isArray(batch[0].results)&&
  batch[0].results.length===1&&valid(batch[0].results[0],['classification']),'gateway_classification_unavailable',503);
 const value=batch[0].results[0].classification;
 requireThat(value&&Object.getPrototypeOf(value)===Object.prototype,'gateway_classification_unavailable',503);
 if(value.kind==='non_burimunsi'){
  requireThat(valid(value,['kind']),'gateway_classification_unavailable',503);return Object.freeze({kind:value.kind});
 }
 if(value.kind==='blocked'){
  requireThat(valid(value,['kind']),'gateway_classification_unavailable',503);throw new BuriError('pairing_unavailable',401);
 }
 requireThat(value.kind==='burimunsi'&&valid(value,['kind','collectionId'])&&typeof value.collectionId==='string'&&
  value.collectionId.trim()===value.collectionId&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value.collectionId),'gateway_classification_unavailable',503);
 requireThat(enabled==='true'&&(group===undefined||group===''||group===value.collectionId),'native_gateway_unconfigured',503);
 return Object.freeze({kind:value.kind,collectionId:value.collectionId});
}
