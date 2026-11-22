import {BuriError,requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId,sha256} from './values.js';

export const INSTALLATION_SCOPE_SQL='SELECT private.burimunsi_resolve_installation_scope(?::uuid,?::text) AS scope';
export async function resolveNativeCollection({env,installationId,deviceToken}){
 requireThat(requireRequestId(installationId)===installationId&&typeof deviceToken==='string'&&deviceToken.length===64&&
  /^[a-f0-9]{64}$/.test(deviceToken),'managed_scope_required',403);
 const db=env?.DB,work=db?.applicationWork;requirePort(db,['prepare','batch']);requirePort(work,['assert']);
 const owned=async()=>{requireThat(env.DB===db&&db.applicationWork===work,'request_not_admitted',503);await work.assert();
  requireThat(env.DB===db&&db.applicationWork===work,'request_not_admitted',503);};
 await owned();let out;
 try{out=await db.batch([db.prepare(INSTALLATION_SCOPE_SQL).bind(installationId,await sha256(deviceToken))]);}
 catch{await owned();throw new BuriError('managed_scope_required',403);}
 await owned();const value=out?.[0]?.results?.[0]?.scope;
 requireThat(Array.isArray(out)&&out.length===1&&out[0]?.success===true&&out[0].results?.length===1&&value&&
  Object.getPrototypeOf(value)===Object.prototype&&Object.keys(value).length===1&&Object.hasOwn(value,'collectionId'),'managed_scope_required',403);
 requireId(value.collectionId);
 const filter=env.BURIMUNSI_COLLECTION_ID;
 requireThat(filter===undefined||filter===''||filter===value.collectionId,'managed_scope_required',403);
 return value.collectionId;
}
