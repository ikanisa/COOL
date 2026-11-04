import {ApiError,integer,rows} from './core.js';

const areasByEntity={
 payment:['payments','ledger','payment_intents'],
 user:['profiles','admin_roles'],
 default:['profiles','collections','members','payment_intents','notifications'],
};
const allowedAreas=new Set(['profiles','collections','members','payment_intents','payments','ledger','admin_roles','audit','feature_flags','settings','system_health','notifications']);

export async function syncEvents(request,env,actor) {
 const url=new URL(request.url),cursor=url.searchParams.get('cursor')??'0';
 if(!/^(0|[1-9][0-9]{0,15})$/.test(cursor)||!Number.isSafeInteger(Number(cursor)))throw new ApiError(400,'invalid_cursor','Invalid synchronization cursor.');
 const limit=integer(Number(url.searchParams.get('limit')??100),'limit',1,100);
 const requested=(url.searchParams.get('areas')??'profiles,collections,members,payment_intents,payments,ledger').split(',');
 if(requested.length>allowedAreas.size||new Set(requested).size!==requested.length||requested.some(area=>!allowedAreas.has(area)))throw new ApiError(400,'invalid_area','Invalid synchronization area.');
 const requestedAreas=new Set(requested);
 const mappings=Object.fromEntries(Object.entries(areasByEntity).map(([type,areas])=>[type,areas.filter(area=>requestedAreas.has(area))]));
 const expansion=Math.max(1,...Object.values(mappings).map(areas=>areas.length));
 // Consume only complete audit rows. Slicing the expanded events would move
 // the cursor past notifications that the client never received.
 if(limit<expansion)throw new ApiError(400,'invalid_limit','Increase the synchronization limit for the selected areas.');
 const auditLimit=Math.floor(limit/expansion);
 const records=await rows(env,`SELECT id,entity_type FROM audit_log WHERE id>? AND (actor_user_id=? OR entity_id=? OR entity_id IN (SELECT collection_id FROM memberships WHERE user_id=? AND active=1) OR entity_id IN (SELECT p.id FROM payments p JOIN memberships m ON m.collection_id=p.collection_id WHERE m.user_id=? AND m.active=1)) ORDER BY id LIMIT ?`,Number(cursor),actor.userId,actor.userId,actor.userId,actor.userId,auditLimit);
 const events=records.flatMap(row=>(mappings[row.entity_type]??mappings.default).map(area=>({id:`${row.id}:${area}`,area})));
 return {events,cursor:records.length?String(records.at(-1).id):cursor};
}
