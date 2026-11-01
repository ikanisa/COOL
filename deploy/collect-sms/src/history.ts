import type {Context} from "npm:hono@4.13.13";
import type {AppEnv,MessageRow} from "./types.ts";
import {admin} from "./auth.ts";
import {summary} from "./messages.ts";
import {ApiError,canonical,integer,isoNow,phone,sha256,string,timestamp} from "./util.ts";
function decode(value:string):Record<string,unknown> {
 try { if(value.length>2500) throw new Error(); const p=JSON.parse(atob(value)); if(!p||typeof p!=="object"||Array.isArray(p))throw new Error(); return p; }
 catch {throw new ApiError(400,"invalid_cursor","Invalid history cursor");}
}
export async function history(c:Context<AppEnv>,csv=false) {
 admin(c);
 const f:Record<string,string>={};
 for(const key of ["state","kind","application_id","recipient","reference","from","until"]) {
  const v=c.req.query(key);if(v)f[key]=string(v,key,1,200);
 }
 if(f.recipient)f.recipient=phone(f.recipient);
 if(f.from)f.from=timestamp(f.from,"from");if(f.until)f.until=timestamp(f.until,"until");
 if(f.from&&f.until&&f.from>f.until)throw new ApiError(400,"invalid_range","from must precede until");
 const hash=await sha256(canonical(f)),cursor=c.req.query("cursor"),p=cursor?decode(cursor):null;
 if(p&&p.filter!==hash)throw new ApiError(400,"cursor_filter_mismatch","Keep filters unchanged while paging");
 const ceiling=p?timestamp(p.ceiling,"cursor ceiling"):isoNow();
 const where=["m.created_at<=?"],args:(string|number)[]=[ceiling];
 for(const key of ["state","kind","application_id"])if(f[key]){where.push(`m.${key}=?`);args.push(f[key]!);}
 if(f.recipient){where.push("m.to_number=?");args.push(f.recipient);}
 if(f.reference){where.push("(m.message_id=? OR m.idempotency_key=? OR EXISTS(SELECT 1 FROM contribution_receipts r WHERE r.message_id=m.message_id AND r.event_id=?) OR EXISTS(SELECT 1 FROM ledger_notification_receipts r WHERE r.message_id=m.message_id AND r.event_id=?))");args.push(f.reference,f.reference,f.reference,f.reference);}
 if(f.from){where.push("m.created_at>=?");args.push(f.from);}if(f.until){where.push("m.created_at<=?");args.push(f.until);}
 if(p){const at=timestamp(p.at,"cursor at"),id=string(p.id,"cursor id",1,200);where.push("(m.created_at<? OR (m.created_at=? AND m.message_id<?))");args.push(at,at,id);}
 const limit=integer(Number(c.req.query("limit")??100),"limit",1,250);
 const rows=await c.env.DB.prepare(`SELECT m.*,(SELECT MAX(parts_total) FROM attempts a WHERE a.message_id=m.message_id) AS parts_total
 FROM messages m WHERE ${where.join(" AND ")} ORDER BY m.created_at DESC,m.message_id DESC LIMIT ?`).bind(...args,limit+1).all<MessageRow>();
 const data=rows.results.slice(0,limit),last=data[data.length-1];
 const next_cursor=rows.results.length>limit&&last?btoa(JSON.stringify({filter:hash,ceiling,at:last.created_at,id:last.message_id})):null;
 const messages=data.map(summary);
 if(!csv)return c.json({messages,next_cursor,snapshot_ceiling:ceiling});
 // A bounded page; repeat with next_cursor. Prefix formula-leading CSV cells.
 const fields=["message_id","application_id","kind","to","state","created_at","text"] as const;
 const cell=(v:unknown)=>{let s=String(v??"");if(/^[\s]*[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
 return c.json({csv:[fields.join(","),...messages.map(m=>fields.map(k=>cell(m[k])).join(","))].join("\r\n")+"\r\n",next_cursor,snapshot_ceiling:ceiling,rows:messages.length});
}
export async function auditHistory(c:Context<AppEnv>) {
 admin(c,"audit:read");const limit=integer(Number(c.req.query("limit")??100),"limit",1,250);
 const filters:Record<string,string>={};for(const k of ["actor_id","action","resource_id","from","until"]){const v=c.req.query(k);if(v)filters[k]=string(v,k,1,200);}
 for(const k of ["from","until"])if(filters[k])filters[k]=timestamp(filters[k],k);
 if(filters.from&&filters.until&&filters.from>filters.until)throw new ApiError(400,"invalid_range","from must precede until");
 const hash=await sha256(canonical(filters)),q=c.req.query("cursor"),p=q?decode(q):null;
 if(p&&p.filter!==hash)throw new ApiError(400,"cursor_filter_mismatch","Keep filters unchanged while paging");
 const ceiling=p?timestamp(p.ceiling,"cursor ceiling"):isoNow(),where=["at<=?"],args:(string|number)[]=[ceiling];
 for(const k of ["actor_id","action","resource_id"])if(filters[k]){where.push(`${k}=?`);args.push(filters[k]!);}
 if(filters.from){where.push("at>=?");args.push(filters.from);}if(filters.until){where.push("at<=?");args.push(filters.until);}
 if(p){const at=timestamp(p.at,"cursor at"),id=string(p.id,"cursor id",1,200);where.push("(at<? OR(at=? AND event_id<?))");args.push(at,at,id);}
 const result=await c.env.DB.prepare(`SELECT * FROM audit_events WHERE ${where.join(" AND ")} ORDER BY at DESC,event_id DESC LIMIT ?`).bind(...args,limit+1).all();
 const events=result.results.slice(0,limit),last=events[events.length-1];
 return c.json({events,next_cursor:result.results.length>limit&&last?btoa(JSON.stringify({filter:hash,ceiling,at:last.at,id:last.event_id})):null});
}
