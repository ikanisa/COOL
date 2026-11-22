import type {D1PreparedStatement} from "./postgres.ts";
import type { Env } from "./types.ts";
import type { NewMessage } from "./messages.ts";
import { ApiError, integer } from "./util.ts";
/** Estimated dispatch reservations, never a claim of radio delivery capacity. */
export function reserveOtp(env:Env,m:NewMessage):D1PreparedStatement[] {
 const gap=integer(Number(env.OTP_SEGMENT_INTERVAL_MS??10000),"OTP_SEGMENT_INTERVAL_MS",1000,60000);
 const now=Date.parse(m.created_at),deadline=Date.parse(m.not_after),count=m.segments_estimate;
 if(count*gap>deadline-now) throw new ApiError(503,"otp_capacity_unavailable","The OTP cannot fit the configured dispatch budget");
 return [env.DB.prepare(`INSERT INTO otp_capacity_reservations(message_id,installation_id,slot_start,slot_end,dispatch_by,segments)
 SELECT ?,installation_id,start,start+?, ?,? FROM (
 SELECT d.installation_id,MAX(?,COALESCE((SELECT MAX(r.slot_end) FROM otp_capacity_reservations r WHERE r.installation_id=d.installation_id),0))
 + COALESCE((SELECT SUM(m.segments_estimate)*? FROM messages m WHERE m.owner_installation_id=d.installation_id
 AND m.message_id<>? AND m.state IN('assigned','phone_accepted','queued','handoff_started') AND m.cancel_requested=0 AND m.not_after>?
 AND NOT EXISTS(SELECT 1 FROM otp_capacity_reservations r WHERE r.message_id=m.message_id AND r.slot_end>=?)),0) AS start
 FROM devices d WHERE d.ready=1 AND d.revoked_at IS NULL AND d.last_seen_at>=?
 AND EXISTS(SELECT 1 FROM json_each(d.allowed_kinds) WHERE value='otp')
 ) WHERE start+?<=? AND EXISTS(SELECT 1 FROM messages WHERE message_id=?) ORDER BY start,installation_id LIMIT 1`)
 .bind(m.message_id,count*gap,deadline,count,now,gap,m.message_id,m.created_at,now,new Date(now-45000).toISOString(),count*gap,deadline,m.message_id),
 // A constraint failure rolls back challenge, cooldown, message and reservation together.
 env.DB.prepare("INSERT INTO otp_capacity_requirements SELECT message_id FROM messages WHERE message_id=?").bind(m.message_id),
 env.DB.prepare(`UPDATE messages SET owner_installation_id=(SELECT installation_id FROM otp_capacity_reservations WHERE message_id=?),
 assignment_version=1,state='assigned' WHERE message_id=? AND EXISTS(SELECT 1 FROM otp_capacity_reservations WHERE message_id=?)`)
 .bind(m.message_id,m.message_id,m.message_id)];
}
