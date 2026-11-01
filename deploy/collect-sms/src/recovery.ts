import type {Context} from "npm:hono@4.13.13";import type{AppEnv}from './types.ts';import{admin}from './auth.ts';import{ApiError,integer,isoNow,string}from './util.ts';
/** Metadata-only, keyset-paginated evidence. Never exposes message bodies,
 * recipients, OTP verifiers, credentials or raw callback details. */
export async function recoveryExport(c:Context<AppEnv>){
 admin(c,'audit:read');const after=c.req.query('after')??'',limit=integer(Number(c.req.query('limit')??100),'limit',1,250);
 if(after.length>200)throw new ApiError(400,'invalid_cursor','Invalid evidence cursor');
 const rows=await c.env.DB.prepare(`SELECT message_id,payload_digest,owner_installation_id,assignment_version,state,cancel_requested,created_at,updated_at FROM messages WHERE message_id>? ORDER BY message_id LIMIT ?`).bind(after,limit+1).all();
 const page=rows.results.slice(0,limit),ids=JSON.stringify(page.map(r=>r.message_id));
 const devices=await c.env.DB.prepare('SELECT installation_id,revoked_at,last_seen_at,app_version FROM devices ORDER BY installation_id LIMIT 1001').all();
 if(devices.results.length>1000)throw new ApiError(413,'fleet_too_large','Export the fleet from a paginated administrative inventory before reconciliation');
 return c.json({schema_version:1,source:'collect-sms-server',exported_at:isoNow(),dispatch_paused:c.env.DISPATCH_PAUSED==='true',messages:page,devices:devices.results,next_cursor:rows.results.length>limit?String(page.at(-1)?.message_id):null,
 notice:'Paginate to completion while dispatch is paused. This live metadata export is not a transactionally consistent database backup.'});
}
