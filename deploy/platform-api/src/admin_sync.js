import {ApiError,integer,id} from './core.js';

// Invalidation metadata only. Each area is capped by the same capability as
// its authoritative read; no audit payload, actor or resource ID is returned.
const areas={
 profiles:['users.read',['user','profile','membership','roster_import']],
 collections:['collections.read',['collection','membership','roster_import']],
 members:['users.read',['user','profile','membership','collection','payment','reconciliation','roster_import']],
 receivers:['receivers.read',['collection']],
 payment_intents:['payments.read',['payment_intent','collection','user']],
 payments:['payments.read',['payment','reconciliation','support_request']],
 ledger:['ledger.read',['payment','reconciliation']],
 reconciliations:['reconciliations.read',['payment','reconciliation']],
 overview:['overview.read',['user','profile','collection','membership','payment','reconciliation','roster_import']],
 requests:['account.manage',[]],
};
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};

export async function adminSyncEvents(request,env,account){
 const query=new URL(request.url).searchParams;
 if([...query.keys()].some(k=>!['cursor','limit','areas'].includes(k)||query.getAll(k).length!==1))fail(400,'invalid_sync_query','Invalid update filters.');
 const cursor=query.get('cursor')??'0',rawLimit=query.get('limit')??'100';
 if(!/^(0|[1-9][0-9]{0,15})$/.test(cursor)||!Number.isSafeInteger(Number(cursor)))fail(400,'invalid_cursor','Invalid update cursor.');
 if(!/^[1-9][0-9]{0,2}$/.test(rawLimit))fail(400,'invalid_limit','Invalid update limit.');
 const limit=integer(Number(rawLimit),'limit',1,100),requested=(query.get('areas')??Object.keys(areas).filter(k=>account.permissions.includes(areas[k][0])).join(',')).split(',');
 if(!requested.length||requested.length>Object.keys(areas).length||new Set(requested).size!==requested.length||requested.some(k=>!Object.hasOwn(areas,k)))fail(400,'invalid_area','Invalid update area.');
 if(requested.some(k=>!account.permissions.includes(areas[k][0])))fail(403,'permission_required','This update area is unavailable.');
 // Consume complete source rows, so a full page never advances past an
 // expansion that has not reached the client.
 if(limit<requested.length)fail(400,'invalid_limit','Increase the update limit for these areas.');
 const types=[...new Set(requested.flatMap(k=>areas[k][1]))],own=requested.includes('requests'),caps=[...new Set(requested.map(k=>areas[k][0]))],guard=id();
 const statement=env.DB.prepare(`INSERT INTO admin_account_guards(id,passed) SELECT ?,(CASE WHEN
 (SELECT count(DISTINCT c.permission) FROM admin_account_role_capabilities c JOIN admin_grants g ON g.permission=c.permission
 WHERE c.role=? AND g.user_id=? AND c.permission IN (${caps.map(()=>'?').join(',')}))=? THEN 1 ELSE 0 END)`)
 .bind(guard,account.role,account.principal_id,...caps,caps.length);
 const where=[...(types.length?[`entity_type IN (${types.map(()=>'?').join(',')})`]:[]),...(own?['actor_user_id=?']:[])].join(' OR ');
 // env is already accountDatabase-scoped: original cookie, role, MFA/session
 // and these read capabilities are rechecked in this same atomic batch.
 const result=await env.DB.batch([statement,
  env.DB.prepare(`SELECT id,entity_type,actor_user_id FROM audit_log WHERE id>? AND (${where}) ORDER BY id LIMIT ?`).bind(Number(cursor),...types,...(own?[account.principal_id]:[]),Math.floor(limit/requested.length)),
  env.DB.prepare('DELETE FROM admin_account_guards WHERE id=?').bind(guard)]);
 const records=result[1].results;
 const events=records.flatMap(row=>requested.filter(area=>area==='requests'?row.actor_user_id===account.principal_id:areas[area][1].includes(row.entity_type)).map(area=>({id:`${row.id}:${area}`,area})));
 return {contract_version:1,events,cursor:records.length?String(records.at(-1).id):cursor};
}
