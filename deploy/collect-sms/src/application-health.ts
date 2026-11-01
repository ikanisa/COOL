import type {Context} from "npm:hono@4.13.13";
import type {AppEnv} from "./types.ts";
import {application} from "./auth.ts";
import {ApiError,integer,isoNow,timestamp} from "./util.ts";
/** Counts are application-reported observations, not proof of ledger correctness. */
export async function reportApplicationHealth(c:Context<AppEnv>,b:Record<string,unknown>){
 const p=application(c,'messages:write'),now=isoNow(),sampled=timestamp(b.sampled_at,'sampled_at');
 if(Date.parse(sampled)>Date.now()+30000||Date.parse(sampled)<Date.now()-300000)throw new ApiError(400,'stale_sample','Sample must be within five minutes and no more than 30 seconds ahead');
 const pending=integer(b.pending_count,'pending_count',0,1000000000),failed=integer(b.failed_count,'failed_count',0,1000000000);
 const oldest=pending?timestamp(b.oldest_pending_at,'oldest_pending_at'):null;
 if((!pending&&b.oldest_pending_at!=null)||(oldest&&oldest>sampled))throw new ApiError(400,'invalid_outbox_health','Oldest pending time must agree with the pending count and sample time');
 const result=await c.env.DB.prepare(`INSERT INTO application_outbox_health VALUES(?,?,?,?,?,?) ON CONFLICT(application_id) DO UPDATE SET
 sampled_at=excluded.sampled_at,received_at=excluded.received_at,pending_count=excluded.pending_count,failed_count=excluded.failed_count,oldest_pending_at=excluded.oldest_pending_at
 WHERE excluded.sampled_at>application_outbox_health.sampled_at RETURNING sampled_at`).bind(p.id,sampled,now,pending,failed,oldest).all();
 return c.json({application_id:p.id,accepted:result.results.length>0,sampled_at:sampled});
}
