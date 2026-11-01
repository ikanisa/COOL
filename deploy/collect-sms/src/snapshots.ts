import type {Context} from "npm:hono@4.13.13";
import type {AppEnv} from './types.ts';
import {application} from './auth.ts';
import {makeMessage,messageInsert} from './messages.ts';
import {ApiError,canonical,integer,isoNow,object,phone,sha256,string,timestamp,uid} from './util.ts';
/** Notification facts must come from the caller's committed ledger transaction.
 * This endpoint does not infer available funds from incoming SMS or credits.
 */
export async function ledgerSnapshot(c:Context<AppEnv>,b:Record<string,unknown>){
 const p=application(c,'contributions','receipt'),eventId=string(b.event_id,'event_id',1,128),recipient=phone(b.recipient);
 const entry=object(b.entry,'entry'),s=object(b.snapshot,'snapshot');
 const type=string(entry.type,'entry.type',1,24),basis=string(s.basis,'snapshot.basis',1,32),scope=string(s.scope,'snapshot.scope',1,16);
 if(!['contribution','refund','payout','correction'].includes(type)||!['cumulative_contributions','available_balance'].includes(basis))throw new ApiError(400,'invalid_snapshot','Specify the entry type and exact accounting basis');
 if((basis==='available_balance'&&scope!=='as_of')||(basis==='cumulative_contributions'&&!['all_time','cycle'].includes(scope)))throw new ApiError(400,'invalid_scope','Available funds use as_of; contributions use all_time or cycle');
 if(b.currency!=='RWF')throw new ApiError(400,'invalid_currency','This reference contract uses integer RWF');
 const period=scope==='cycle'?string(s.period_id,'period_id',1,80):null;
 if(scope!=='cycle'&&s.period_id!==undefined)throw new ApiError(400,'invalid_scope','A period_id is only valid for cycle contributions');
 const amount=integer(entry.amount_rwf,'entry.amount_rwf',type==='correction'?-Number.MAX_SAFE_INTEGER:0),member=integer(s.member_total_rwf,'member_total_rwf',-Number.MAX_SAFE_INTEGER),group=integer(s.group_total_rwf,'group_total_rwf',-Number.MAX_SAFE_INTEGER);
 const name=string(b.collection_name,'collection_name',1,80);if(/[\x00-\x1f\x7f]/.test(name))throw new ApiError(400,'invalid_snapshot','Collection name contains control characters');
 const facts={event_id:eventId,collection_id:string(b.collection_id,'collection_id',1,100),collection_name:name,member_id:string(b.member_id,'member_id',1,100),currency:'RWF',entry:{type,amount_rwf:amount},snapshot:{basis,scope,period_id:period,member_total_rwf:member,group_total_rwf:group,posted_at:timestamp(s.posted_at,'posted_at'),ledger_version:string(s.ledger_version,'ledger_version',1,100)}};
 const digest=await sha256(canonical(facts));const old=await c.env.DB.prepare('SELECT * FROM ledger_notification_events WHERE application_id=? AND event_id=?').bind(p.id,eventId).first();
 if(old&&old.facts_digest!==digest)throw new ApiError(409,'snapshot_conflict','Create a new correction event instead of rewriting posted facts');
 const existing=await c.env.DB.prepare('SELECT r.message_id,m.state FROM ledger_notification_receipts r JOIN messages m ON m.message_id=r.message_id WHERE r.application_id=? AND r.event_id=? AND r.recipient=?').bind(p.id,eventId,recipient).first();
 if(existing)return c.json({message_id:existing.message_id,state:'existing'},202);
 if(old?.redacted_at)throw new ApiError(409,'source_facts_redacted','The prior notification facts were redacted; no new recipient can be silently added');
 const n=(x:number)=>String(x).replace(/\B(?=(\d{3})+(?!\d))/g,',');const label=basis==='available_balance'?'available':'contributions';
 const scopeLabel=scope==='cycle'?` Cycle ${period}.`:scope==='all_time'?' All-time.':'';
 const text=`COLLECT ${name}: ${type} RWF ${n(amount)}. Your ${label}: RWF ${n(member)}. Group ${label}: RWF ${n(group)}.${scopeLabel} As of ${facts.snapshot.posted_at.slice(0,16).replace('T',' ')} UTC. Ref ${eventId}.`;
 if(text.length>2000)throw new ApiError(413,'too_large','Receipt is too long');
 const key=`ledger:${eventId}:${recipient}`,id=`ledger_${(await sha256(p.id+'\n'+key)).slice(0,48)}`,now=isoNow();
 const msg=await makeMessage({message_id:id,application_id:p.id,kind:'receipt',to:recipient,text,priority:80,request_digest:digest,idempotency_key:key,available_at:now,not_after:new Date(Date.now()+86400000).toISOString(),created_at:now,metadata:{ledger_event_id:eventId,basis,scope,ledger_version:facts.snapshot.ledger_version,posted_at:facts.snapshot.posted_at}});
 try{await c.env.DB.batch([
  c.env.DB.prepare('INSERT INTO ledger_notification_events(application_id,event_id,facts_json,facts_digest,created_at) VALUES(?,?,?,?,?) ON CONFLICT(application_id,event_id) DO UPDATE SET facts_digest=excluded.facts_digest').bind(p.id,eventId,canonical(facts),digest,now),
  messageInsert(c.env.DB,msg,{ignoreExisting:true}),
  c.env.DB.prepare('INSERT INTO ledger_notification_receipts(application_id,event_id,recipient,message_id) VALUES(?,?,?,?) ON CONFLICT(application_id,event_id,recipient) DO NOTHING').bind(p.id,eventId,recipient,id)
 ]);}catch(e){const check=await c.env.DB.prepare('SELECT facts_digest FROM ledger_notification_events WHERE application_id=? AND event_id=?').bind(p.id,eventId).first();if(String(e).includes('source_facts_redacted'))throw new ApiError(409,'source_facts_redacted','Notification facts were redacted before this recipient was committed');if(check&&check.facts_digest!==digest)throw new ApiError(409,'snapshot_conflict','Another request already recorded different ledger facts');throw e;}
 return c.json({message_id:id,state:'accepted'},202);
}
