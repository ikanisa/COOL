import type {Context} from "npm:hono@4.13.13";
import type {AppEnv,Env} from "./types.ts";
import {application} from "./auth.ts";
import {getTemplate,locale,renderTemplate} from "./templates.ts";
import {makeMessage,messageInsert} from "./messages.ts";
import {ApiError,canonical,integer,isoNow,object,phone,sha256,string,timestamp,uid} from "./util.ts";
export async function createSchedule(c:Context<AppEnv>,b:Record<string,unknown>){
 const p=application(c,'messages:write','operation'),key=string(c.req.header('Idempotency-Key'),'Idempotency-Key',1,128),lang=locale(b.locale),tk=string(b.template_key,'template_key',1,80),v=integer(b.template_version,'template_version',1,1000000);
 const template=await getTemplate(c.env,p.id,tk,v,lang);if(template.kind!=='operation')throw new ApiError(400,'schedule_kind','Recurring schedules require an operation template and fresh eligibility');
 const vars=object(b.variables,'variables');renderTemplate(template,vars);
 const canonicalInput={name:string(b.name,'name',1,120),to:phone(b.to),template_key:tk,template_version:v,locale:lang,variables:vars,
 interval_seconds:integer(b.interval_seconds,'interval_seconds',60,31536000),ttl_seconds:integer(b.ttl_seconds??300,'ttl_seconds',30,86400),
 starts_at:timestamp(b.starts_at,'starts_at'),ends_at:timestamp(b.ends_at,'ends_at')};
 if(canonicalInput.ends_at<=canonicalInput.starts_at)throw new ApiError(400,'schedule_range','ends_at must follow starts_at');
 const digest=await sha256(canonical(canonicalInput)),old=await c.env.DB.prepare('SELECT * FROM notification_schedules WHERE application_id=? AND request_key=?').bind(p.id,key).first();
 if(old){if(old.request_digest!==digest)throw new ApiError(409,'idempotency_conflict','Schedule key already has different parameters');return c.json({schedule_id:old.schedule_id,active:!!old.active,next_at:old.next_at},201);}
 if(canonicalInput.ends_at<=isoNow())throw new ApiError(400,'expired','Schedule has already ended');
 const id=`schedule_${(await sha256(p.id+'\n'+key)).slice(0,40)}`,now=isoNow();
 try{await c.env.DB.prepare(`INSERT INTO notification_schedules(schedule_id,application_id,request_key,request_digest,name,to_number,template_key,template_version,locale,variables_json,interval_seconds,ttl_seconds,next_at,ends_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
 .bind(id,p.id,key,digest,canonicalInput.name,canonicalInput.to,tk,v,lang,canonical(vars),canonicalInput.interval_seconds,canonicalInput.ttl_seconds,canonicalInput.starts_at,canonicalInput.ends_at,now,now).run();}
 catch(e){const raced=await c.env.DB.prepare('SELECT request_digest FROM notification_schedules WHERE schedule_id=?').bind(id).first();if(raced&&raced.request_digest!==digest)throw new ApiError(409,'idempotency_conflict','Another request already defined this schedule');if(!raced)throw e;}
 return c.json({schedule_id:id,active:false,next_at:canonicalInput.starts_at},201);
}
export async function listSchedules(c:Context<AppEnv>){const p=application(c,'messages:read');const rows=await c.env.DB.prepare('SELECT schedule_id,name,template_key,template_version,locale,interval_seconds,ttl_seconds,next_at,ends_at,active,revision FROM notification_schedules WHERE application_id=? ORDER BY created_at DESC LIMIT 250').bind(p.id).all();return c.json({schedules:rows.results});}
export async function scheduleAction(c:Context<AppEnv>){
 const p=application(c,'messages:write','operation'),id=c.req.param('id'),action=c.req.param('action');if(!['start','pause'].includes(action??''))throw new ApiError(404,'not_found','Unknown schedule action');
 const now=isoNow(),active=action==='start'?1:0;
 const statements=[c.env.DB.prepare('UPDATE notification_schedules SET active=?,updated_at=? WHERE schedule_id=? AND application_id=? AND ends_at>? RETURNING schedule_id,active,next_at').bind(active,now,id,p.id,now)];
 if(!active)statements.push(c.env.DB.prepare(`UPDATE messages SET cancel_requested=1,state=CASE WHEN owner_installation_id IS NULL THEN 'cancelled' ELSE state END,updated_at=?
 WHERE application_id=? AND message_id IN(SELECT o.message_id FROM schedule_occurrences o WHERE o.schedule_id=?) AND state IN('accepted','assigned','phone_accepted','queued')`).bind(now,p.id,id));
 const result=await c.env.DB.batch(statements);if(!result[0]!.results.length)throw new ApiError(404,'not_found','Active-range schedule not found');return c.json(result[0]!.results[0]);
}
/** Fixed intervals anchored to UTC; missed occurrences are skipped, not flooded.
 * The queued operation cannot dispatch without the trusted application's fresh eligibility. */
export async function enqueueSchedules(env:Env,at=Date.now()){
 const now=new Date(at).toISOString();const rows=await env.DB.prepare(`SELECT s.* FROM notification_schedules s JOIN applications a ON a.application_id=s.application_id WHERE s.active=1 AND a.revoked_at IS NULL AND s.next_at<=? AND s.ends_at>? ORDER BY s.next_at,s.schedule_id LIMIT 10`).bind(now,now).all<Record<string,unknown>>();let enqueued=0,skipped=0;
 for(const s of rows.results){
  const id=String(s.schedule_id),due=String(s.next_at),app=String(s.application_id),rev=Number(s.revision),until=new Date(Math.min(Date.parse(due)+Number(s.ttl_seconds)*1000,Date.parse(String(s.ends_at)))).toISOString();
  const step=Number(s.interval_seconds)*1000,next=new Date(Date.parse(due)+(Math.floor((at-Date.parse(due))/step)+1)*step).toISOString();
  const t=await getTemplate(env,app,String(s.template_key),Number(s.template_version),String(s.locale)),rendered=renderTemplate(t,JSON.parse(String(s.variables_json))),messageId=`schedulemsg_${(await sha256(id+'\n'+rev+'\n'+due)).slice(0,40)}`;
  const expired=until<=now;
  const m=await makeMessage({message_id:messageId,application_id:app,kind:'operation',to:String(s.to_number),text:rendered.text,priority:50,request_digest:await sha256(canonical({schedule:id,revision:rev,due,template:t.digest})),idempotency_key:`schedule:${id}:${rev}:${due}`,not_after:until,available_at:due,created_at:now,requires_fresh_decision:true,metadata:{schedule_id:id,due_at:due,template_digest:t.digest}});
  const first=env.DB.prepare(`INSERT INTO schedule_occurrences SELECT schedule_id,revision,?,?,?,? FROM notification_schedules WHERE schedule_id=? AND revision=? AND next_at=? AND active=1 AND ends_at>? AND EXISTS(SELECT 1 FROM applications WHERE application_id=? AND revoked_at IS NULL) ON CONFLICT(schedule_id,revision,due_at) DO NOTHING`).bind(due,messageId,now,expired?'expired':'queued',id,rev,due,now,app);
  const stmts=[first];
  if(!expired){
   // Build a normal parameterized message insert, guard it by a durable occurrence.
   stmts.push(messageInsert(env.DB,m,{occurrenceGuard:messageId,ignoreExisting:true}));
  }
  stmts.push(env.DB.prepare('UPDATE notification_schedules SET next_at=?,updated_at=? WHERE schedule_id=? AND revision=? AND next_at=? AND EXISTS(SELECT 1 FROM schedule_occurrences WHERE message_id=?)').bind(next,now,id,rev,due,messageId));
  const result=await env.DB.batch(stmts);if(result[0]!.meta.changes){if(expired)skipped++;else enqueued++;}
 }
 return {enqueued,skipped};
}

/** Exposes this application's durable occurrences for its business-state resolver.
 * No operation is automatically declared eligible by this endpoint. */
export async function scheduleOccurrences(c:Context<AppEnv>){
 const p=application(c,'messages:read'),id=string(c.req.param('id'),'id',1,200),limit=integer(Number(c.req.query('limit')??100),'limit',1,250);
 const exists=await c.env.DB.prepare('SELECT schedule_id FROM notification_schedules WHERE schedule_id=? AND application_id=?').bind(id,p.id).first();
 if(!exists)throw new ApiError(404,'not_found','Schedule not found');
 const cursor=c.req.query('cursor'),where=['o.schedule_id=?'],args:(string|number)[]=[id];
 if(cursor){let v;try{v=JSON.parse(atob(cursor));}catch{throw new ApiError(400,'invalid_cursor','Invalid occurrence cursor');}
 if(!v||v.schedule_id!==id)throw new ApiError(400,'invalid_cursor','Cursor belongs to another schedule');
 const at=timestamp(v.due_at,'cursor due_at'),mid=string(v.message_id,'cursor message_id',1,200);where.push('(o.due_at<? OR(o.due_at=? AND o.message_id<?))');args.push(at,at,mid);}
 const rows=await c.env.DB.prepare(`SELECT o.message_id,o.due_at,o.outcome,COALESCE(m.state,'expired') AS state,
 CASE WHEN m.requires_fresh_decision=1 AND m.state IN('accepted','assigned','phone_accepted','queued') AND m.cancel_requested=0 THEN 1 ELSE 0 END AS requires_eligibility
 FROM schedule_occurrences o LEFT JOIN messages m ON m.message_id=o.message_id WHERE ${where.join(' AND ')} ORDER BY o.due_at DESC,o.message_id DESC LIMIT ?`).bind(...args,limit+1).all();
 const data=rows.results.slice(0,limit),last=data[data.length-1];return c.json({occurrences:data,next_cursor:rows.results.length>limit&&last?btoa(JSON.stringify({schedule_id:id,due_at:last.due_at,message_id:last.message_id})):null});
}
