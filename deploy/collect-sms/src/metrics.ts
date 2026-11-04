import type {Context} from "npm:hono@4.13.13";
import type {AppEnv,Env} from "./types.ts";
import {admin} from "./auth.ts";
import {uid} from "./util.ts";
export async function serviceMetrics(env:Env) {
 const observedMs=Date.now(),now=new Date(observedMs).toISOString(),minute=new Date(observedMs-60000).toISOString(),stale=new Date(observedMs-90000).toISOString();
 const [queue,devices,outcomes,callbacks,outboxes,observations]=await env.DB.batch([
 env.DB.prepare(`SELECT kind,COUNT(*) AS count,MIN(created_at) AS oldest_at FROM messages WHERE state IN('accepted','assigned','phone_accepted','queued') AND cancel_requested=0 AND not_after>? GROUP BY kind`).bind(now),
 env.DB.prepare(`SELECT COUNT(*) AS total,COALESCE(SUM(CASE WHEN ready=1 AND last_seen_at>=? THEN 1 ELSE 0 END),0) AS ready,
 COALESCE(SUM(CASE WHEN last_seen_at IS NULL OR last_seen_at<? OR ready=0 THEN 1 ELSE 0 END),0) AS unavailable,
 COALESCE(SUM(CASE WHEN fcm_last_error IS NOT NULL THEN 1 ELSE 0 END),0) AS fcm_errors FROM devices WHERE revoked_at IS NULL`).bind(stale,stale),
 env.DB.prepare("SELECT kind,state,COUNT(*) AS count FROM messages WHERE state IN('outcome_unknown','partial') OR (kind='otp' AND state IN('expired','failed') AND updated_at>=?) GROUP BY kind,state").bind(minute),
 env.DB.prepare("SELECT state,COUNT(*) AS count,MIN(created_at) AS oldest_at FROM webhook_deliveries WHERE state IN('pending','sending','failed') GROUP BY state"),
 env.DB.prepare('SELECT h.* FROM application_outbox_health h JOIN applications a ON a.application_id=h.application_id WHERE a.revoked_at IS NULL'),
 env.DB.prepare("SELECT state,COUNT(*) AS count FROM messages WHERE state='handoff_started' OR (state IN('accepted','assigned','phone_accepted','queued') AND not_after<=?) GROUP BY state").bind(now)]);
 const counts:Record<string,number>={handoff_started:0,accepted:0,assigned:0,phone_accepted:0,queued:0};
 for(const row of observations!.results){const state=String(row.state),count=row.count;
  if(!Object.hasOwn(counts,state)||typeof count!=='number'||!Number.isSafeInteger(count)||count<0)throw Error('invalid_delivery_observation');
  counts[state]=count;
 }
 return {observed_at:now,dispatch_paused:env.DISPATCH_PAUSED==='true',queue:queue!.results.map(row=>Object.assign({},row,{oldest_age_seconds:Math.max(0,Math.floor((observedMs-Date.parse(String(row.oldest_at)))/1000))})),devices:devices!.results[0],outcomes:outcomes!.results,callbacks:callbacks!.results,
 application_outboxes:outboxes!.results.map(r=>Object.assign({},r,{stale:Date.parse(String(r.sampled_at))<observedMs-300000})),
 delivery_observations:{handoff_started:counts.handoff_started,overdue:{accepted:counts.accepted,assigned:counts.assigned,phone_accepted:counts.phone_accepted,queued:counts.queued}},
 notice:"Queue/radio estimates are not recipient arrival measurements. Outbox counts are application-reported; absent reports mean unknown, not healthy. Unresolved handoff and overdue states are observations, not proof of delivery failure."};
}
export async function evaluateAlerts(env:Env) {
 const m=await serviceMetrics(env),now=m.observed_at,observedMs=Date.parse(now);
 const flags:Record<string,{active:boolean;severity:string}>={
  application_outbox_blocked:{active:m.application_outboxes.some(r=>Number(r.failed_count)>0||(Number(r.pending_count)>0&&Date.parse(String(r.oldest_pending_at))<observedMs-300000)),severity:'critical'},
  application_outbox_stale:{active:m.application_outboxes.some(r=>r.stale),severity:'warning'},
  gateway_unavailable:{active:Number(m.devices?.unavailable??0)>0,severity:'warning'},
  no_ready_gateway:{active:Number(m.devices?.ready??0)===0&&m.queue.length>0,severity:'critical'},
  otp_queue_age:{active:m.queue.some(r=>r.kind==='otp'&&r.oldest_age_seconds>=10),severity:'critical'},
  receipt_queue_age:{active:m.queue.some(r=>r.kind==='receipt'&&r.oldest_age_seconds>=300),severity:'warning'},
  uncertain_delivery:{active:m.outcomes.some(r=>['outcome_unknown','partial'].includes(String(r.state))&&Number(r.count)>0),severity:'warning'},
  otp_expired_or_failed:{active:m.outcomes.some(r=>r.kind==='otp'&&['expired','failed'].includes(String(r.state))&&Number(r.count)>0),severity:'warning'},
  callback_failed:{active:m.callbacks.some(r=>r.state==='failed'&&Number(r.count)>0),severity:'warning'},
  fcm_error:{active:Number(m.devices?.fcm_errors??0)>0,severity:'warning'}
 };
 for(const [key,f]of Object.entries(flags))await env.DB.batch([
  env.DB.prepare(`INSERT INTO metric_alert_events(event_id,alert_key,transition,at) SELECT ?,?,?,?
 WHERE (?=1 AND NOT EXISTS(SELECT 1 FROM metric_alerts WHERE alert_key=? AND active=1))
 OR (?=0 AND EXISTS(SELECT 1 FROM metric_alerts WHERE alert_key=? AND active=1))`).bind(uid('alert'),key,f.active?'opened':'resolved',now,f.active?1:0,key,f.active?1:0,key),
  env.DB.prepare(`INSERT INTO metric_alerts(alert_key,severity,active,first_seen_at,last_seen_at,resolved_at) VALUES(?,?,?,?,?,?)
 ON CONFLICT(alert_key) DO UPDATE SET severity=excluded.severity,active=excluded.active,last_seen_at=excluded.last_seen_at,
 first_seen_at=CASE WHEN metric_alerts.active=0 AND excluded.active=1 THEN excluded.first_seen_at ELSE metric_alerts.first_seen_at END,
 resolved_at=CASE WHEN excluded.active=1 THEN NULL WHEN metric_alerts.active=1 THEN excluded.last_seen_at ELSE metric_alerts.resolved_at END`).bind(key,f.severity,f.active?1:0,now,now,f.active?null:now)]);
 return {evaluated_at:now,conditions:Object.keys(flags).length};
}
export async function metrics(c:Context<AppEnv>){admin(c);return c.json(await serviceMetrics(c.env));}
export async function alerts(c:Context<AppEnv>){admin(c);const [a,e]=await c.env.DB.batch([c.env.DB.prepare('SELECT * FROM metric_alerts ORDER BY active DESC,alert_key'),c.env.DB.prepare('SELECT * FROM metric_alert_events ORDER BY at DESC,event_id DESC LIMIT 250')]);return c.json({alerts:a!.results,events:e!.results});}
