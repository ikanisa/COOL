import { digest, normalizeEmail, randomToken } from './security.mjs';
import { sendMemberEmail } from './member-email.mjs';
import { AVAILABLE_PERSON_PUBLIC_ID_SQL } from './core.mjs';
export class MemberError extends Error { constructor(status, code, message) { super(message); this.status=status;this.code=code; } }
const fail=(status,code,message)=>{throw new MemberError(status,code,message);};
const now=()=>Math.floor(Date.now()/1000), iso=t=>t==null?null:new Date(t*1000).toISOString(), micro=t=>iso(t).replace('Z','000Z');
const q=(env,sql,...values)=>env.ADMIN_DB.prepare(sql).bind(...values);
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(v);
const checkId=v=>{if(!uuid(v))fail(400,'invalid_request','Invalid record identifier.');return v;};
const str=(v,min=0,max=1000)=>{if(typeof v!=='string'||v.trim().length<min||v.length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(v))fail(400,'invalid_request','Check the entered values.');return v.trim();};
const amount=v=>{if(!Number.isSafeInteger(v)||v<1)fail(400,'invalid_amount','Enter a positive whole RWF amount.');return v;};
const safe=v=>{if(!Number.isSafeInteger(v))fail(503,'amount_unavailable','The exact total is unavailable.');return v;};
const response=(data,status=200,headers={})=>new Response(JSON.stringify({ok:true,...data}),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...headers}});
const isNative=r=>r.headers.get('X-Collect-Client')==='native'&&!r.headers.has('Origin')&&!r.headers.has('Sec-Fetch-Site');
const cookieName=(env,refresh=false)=>(env.ENVIRONMENT==='local'?'collect_member_dev':'__Host-collect_member')+(refresh?'_refresh':'');
const cookie=(env,value,refresh=false,age=0)=>`${cookieName(env,refresh)}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}${env.ENVIRONMENT==='local'?'':'; Secure'}`;
function origin(r,env){
 const u=new URL(r.url), expected=env.MEMBER_ORIGIN||env.ADMIN_ORIGIN;
 if(!env.ADMIN_DB||!expected||new URL(expected).origin!==expected)fail(503,'service_unavailable','Collect is unavailable.');
 if(u.origin!==expected||(u.protocol!=='https:'&&!(env.ENVIRONMENT==='local'&&['localhost','127.0.0.1'].includes(u.hostname))))fail(403,'origin_rejected','Open the configured Collect app.');
 if(!isNative(r)&&((r.method!=='GET'&&r.headers.get('Origin')!==expected)||(r.headers.has('Origin')&&r.headers.get('Origin')!==expected)||r.headers.get('Sec-Fetch-Site')==='cross-site'))fail(403,'origin_rejected','This request is not allowed.');
}
async function body(r,maximum=32768){
 if(!r.headers.get('Content-Type')?.startsWith('application/json'))fail(415,'invalid_request','Send JSON.');
 const reader=r.body?.getReader(); if(!reader)fail(400,'invalid_request','Request is empty.');
 let size=0,raw='';const decoder=new TextDecoder('utf-8',{fatal:true});
 for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>maximum){await reader.cancel();fail(413,'invalid_request','Request is too large.');}raw+=decoder.decode(value,{stream:true});}raw+=decoder.decode();
 // Money, revisions and page sizes use integer wire tokens. Inspect before
 // JSON.parse can round a fractional or exponential value into a safe integer.
 const lexemes=raw.match(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/g)||[];
 if(lexemes.some(value=>value[0]!=='"'&&(/[.eE]/.test(value)||!Number.isSafeInteger(Number(value)))))fail(400,'invalid_number','Use exact whole numbers without decimals or exponents.');
 let data;try{data=JSON.parse(raw);}catch{fail(400,'invalid_request','Invalid JSON.');}
 if(!data||Array.isArray(data)||typeof data!=='object')fail(400,'invalid_request','Invalid request.');return data;
}
function token(r,env,refresh=false){
 if(isNative(r)){const value=refresh?r.headers.get('X-Collect-Refresh'):r.headers.get('Authorization')?.replace(/^Bearer /,'');return /^[a-f0-9]{64}$/.test(value||'')?value:null;}
 const name=cookieName(env,refresh),matches=(r.headers.get('Cookie')||'').split(';').map(v=>v.trim()).filter(v=>v.startsWith(name+'='));
 return matches.length===1&&new RegExp('^'+name+'=[a-f0-9]{64}$').test(matches[0])?matches[0].slice(name.length+1):null;
}
async function session(r,env,optional=false,refresh=false){
 const value=token(r,env,refresh);const hash=value?await digest(value):'';
 const row=await q(env,`SELECT s.*,u.email FROM member_sessions s JOIN collect_users u ON u.id=s.user_id WHERE s.${refresh?'refresh_hash':'token_hash'}=? AND s.${refresh?'refresh_until':'expires_at'}>? AND u.status='active'`,hash,now()).first();
 if(row&&r.headers.has('X-Collect-Session')&&r.headers.get('X-Collect-Session')!==row.id)fail(401,'account_changed','Account changed.');
 if(!row&&!optional)fail(401,'unauthenticated','Sign in to continue.');return row;
}
async function signOut(r,env){
 const expected=r.headers.get('X-Collect-Session');if(expected!==null)checkId(expected);
 const access=token(r,env),refresh=token(r,env,true);
 const accessHash=access?await digest(access):'',refreshHash=refresh?await digest(refresh):'';
 // Expired or already absent credentials can be signed out. A captured old
 // intent must never delete a different session carried by newer cookies.
 const match='(token_hash=? OR refresh_hash=?)';
 try{await env.ADMIN_DB.batch([
  guard(env,`(SELECT count(*) FROM member_sessions WHERE ${match})<=1 AND NOT EXISTS(SELECT 1 FROM member_sessions WHERE ${match} AND ? IS NOT NULL AND id!=?)`,[accessHash,refreshHash,accessHash,refreshHash,expected,expected]),
  q(env,`DELETE FROM member_sessions WHERE ${match}`,accessHash,refreshHash),
  q(env,'DELETE FROM member_command_guards'),
 ]);}catch(e){if(String(e).includes('member_command_guards')||String(e).includes('allowed=1'))fail(401,'account_changed','Account changed.');throw e;}
 const out=response({signedOut:true});
 if(!isNative(r)){out.headers.append('Set-Cookie',cookie(env,'',false));out.headers.append('Set-Cookie',cookie(env,'',true));}
 return out;
}
const authWhere=`EXISTS(SELECT 1 FROM member_sessions s JOIN collect_users u ON u.id=s.user_id WHERE s.id=? AND s.token_hash=? AND s.expires_at>? AND u.status='active')`;
function guard(env,predicate,args=[]){return q(env,`INSERT INTO member_command_guards(id,allowed) VALUES(?,CASE WHEN ${predicate} THEN 1 ELSE 0 END)`,crypto.randomUUID(),...args);}
async function batch(env,s,statements,checks=[]){
 const statementsAll=[guard(env,authWhere,[s.id,s.token_hash,now()]),...checks,...statements,q(env,'DELETE FROM member_command_guards')];
 try{const result=await env.ADMIN_DB.batch(statementsAll);return result.slice(1+checks.length,-1);}catch(e){if(String(e).includes('member_command_guards')||String(e).includes('allowed=1'))fail(409,'state_changed','Account or group access changed. Refresh and try again.');throw e;}
}
async function limit(env,key,maximum,seconds){const bucket=Math.floor(now()/seconds);const row=await q(env,'INSERT INTO member_rate_limits(key_hash,bucket,count) VALUES(?,?,1) ON CONFLICT(key_hash,bucket) DO UPDATE SET count=count+1 RETURNING count',await digest(key),bucket).first();if(row.count>maximum)fail(429,'rate_limited','Too many attempts. Try again later.');}
async function otpHash(env,id,code){if(typeof env.MEMBER_AUTH_PEPPER!=='string'||env.MEMBER_AUTH_PEPPER.length<32)fail(503,'service_unavailable','Email sign-in is unavailable.');const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env.MEMBER_AUTH_PEPPER),{name:'HMAC',hash:'SHA-256'},false,['sign']);return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(id+':'+code)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
async function issue(r,env,data,purpose='login',s=null){
 const email=normalizeEmail(data.email);if(!email)fail(400,'invalid_email','Enter a valid email address.');
 if(purpose==='privacy'&&email!==s.email)fail(403,'account_changed','Use your signed-in email.');
 await limit(env,`email:${email}`,5,900);await limit(env,`ip:${r.headers.get('CF-Connecting-IP')||'unknown'}`,20,900);
 const id=crypto.randomUUID(),numbers=new Uint32Array(1);crypto.getRandomValues(numbers);const code=String(numbers[0]%1000000).padStart(6,'0');
 const hash=await otpHash(env,id,code);await q(env,"INSERT INTO member_email_challenges(id,email,code_hash,purpose,session_id,created_at,expires_at,state) VALUES(?,?,?,?,?,?,?,'pending')",id,email,hash,purpose,s?.id||null,now(),now()+600).run();
 try{const provider=await sendMemberEmail(env,{to:email,subject:purpose==='privacy'?'Confirm your Collect account request':'Your Collect sign-in code',text:`Your Collect code is ${code}.\n\nIt expires in 10 minutes and can be used once. If you did not request it, ignore this email.`});await q(env,"UPDATE member_email_challenges SET state='accepted',provider_reference=? WHERE id=? AND state='pending'",provider,id).run();}
 catch{await q(env,"UPDATE member_email_challenges SET state='failed' WHERE id=?",id).run();fail(503,'email_unavailable','Email delivery could not be confirmed. Please try again later.');}
 return response({challengeId:id,expiresIn:600,emailStatus:'accepted'});
}
const publicSession=s=>s?{id:s.user_id,email:s.email,sessionId:s.id,expiresAt:iso(s.expires_at)}:null;
function sessionResponse(r,env,s,access,refresh){
 const result={user:publicSession(s)};if(isNative(r)){result.accessToken=access;result.refreshToken=refresh;}
 const out=response(result);if(!isNative(r)){out.headers.append('Set-Cookie',cookie(env,access,false,3600));out.headers.append('Set-Cookie',cookie(env,refresh,true,30*86400));}return out;
}
async function verify(r,env,d,purpose='login',current=null){
 const email=normalizeEmail(d.email);checkId(d.challengeId);if(!email||typeof d.code!=='string'||!/^\d{6}$/.test(d.code))fail(400,'invalid_code','Enter the six digit email code.');
 await limit(env,`verify-ip:${r.headers.get('CF-Connecting-IP')||'unknown'}`,50,900);
 const c=await q(env,"UPDATE member_email_challenges SET attempts=attempts+1 WHERE id=? AND email=? AND purpose=? AND state='accepted' AND expires_at>? AND attempts<8 RETURNING *",d.challengeId,email,purpose,now()).first();
 if(!c||c.code_hash!==await otpHash(env,c.id,d.code)||(purpose==='privacy'&&c.session_id!==current.id))fail(400,'invalid_code','The code is invalid or expired.');
 const user=await q(env,'SELECT * FROM collect_users WHERE email=?',email).first();if(user&&(user.member_type!=='app'||!['active','invited'].includes(user.status)))fail(403,'account_unavailable','This account cannot sign in.');
 const userId=user?.id||crypto.randomUUID(),sid=crypto.randomUUID(),access=randomToken(),refresh=randomToken(),at=now();
 const statements=[guard(env,"EXISTS(SELECT 1 FROM member_email_challenges WHERE id=? AND state='accepted' AND attempts<=8 AND expires_at>?)",[c.id,at]),q(env,"UPDATE member_email_challenges SET state='consumed' WHERE id=?",c.id)];
 if(purpose==='privacy')statements.push(guard(env,authWhere,[current.id,current.token_hash,at]));
 if(user)statements.push(guard(env,"EXISTS(SELECT 1 FROM collect_users WHERE id=? AND email=? AND status IN ('active','invited'))",[user.id,email]),q(env,"UPDATE collect_users SET status='active',version=version+1,updated_at=? WHERE id=? AND status='invited'",at,user.id));
 if(!user){
  statements.push(q(env,"INSERT INTO collect_users(id,email,member_type,status,created_at,updated_at) VALUES(?,?,'app','active',?,?)",userId,email,at,at));
  // Allocate inside the guarded batch so operator and app IDs share one immutable namespace.
  statements.push(q(env,`INSERT INTO collect_profiles(user_id,public_id,display_name,display_name_recorded,created_at,updated_at) SELECT ?,(${AVAILABLE_PERSON_PUBLIC_ID_SQL}),?,0,?,?`,userId,'Collect member',at,at),q(env,'INSERT INTO member_notification_preferences(user_id) VALUES(?)',userId));
 }
 statements.push(q(env,'INSERT OR IGNORE INTO member_notification_preferences(user_id) VALUES(?)',userId));
 statements.push(q(env,'INSERT INTO member_sessions(id,user_id,token_hash,refresh_hash,created_at,expires_at,refresh_until,verified_at) VALUES(?,?,?,?,?,?,?,?)',sid,userId,await digest(access),await digest(refresh),at,at+3600,at+30*86400,at));
 if(purpose==='privacy')statements.push(q(env,'DELETE FROM member_sessions WHERE id=?',current.id));
 statements.push(q(env,'DELETE FROM member_command_guards'));
 try{await env.ADMIN_DB.batch(statements);}catch{fail(409,'state_changed','The account changed. Request a new code.');}
 return sessionResponse(r,env,{id:sid,user_id:userId,email,expires_at:at+3600},access,refresh);
}
function memberCheck(env,s,id,owner=false){return guard(env,`EXISTS(SELECT 1 FROM collect_memberships m JOIN collect_groups g ON g.id=m.group_id WHERE m.group_id=? AND m.user_id=? AND m.status='active' ${owner?"AND m.role='owner' AND g.creator_user_id=m.user_id AND g.is_platform_sponsored=0 AND g.visibility='private' AND g.status='active'":''})`,[id,s.user_id]);}
const profileSql='SELECT p.*,u.email FROM collect_profiles p JOIN collect_users u ON u.id=p.user_id WHERE p.user_id=?';
const profileDto=p=>({id:p.user_id,email:p.email,public_id:p.public_id,whatsapp_phone:'',country_code:'RW',currency_code:'RWF',momo_provider:p.momo_provider,momo_number:p.momo_number,momo_pay_code:p.momo_pay_code});
const groupsSql=`SELECT g.*,p.momo_number_or_code,p.label AS payee_label,p.network,m.user_id AS member_user FROM collect_groups g LEFT JOIN collect_payees p ON p.group_id=g.id AND p.status='active' LEFT JOIN collect_memberships m ON m.group_id=g.id AND m.user_id=? AND m.status='active'`;
const groupDto=async(env,g)=>({id:g.id,slug:g.slug,creator_user_id:g.creator_user_id,title:g.title,description:g.description,collection_type:g.collection_type,category_subtype:g.category_subtype,purpose_label:g.purpose_label,receiver_momo_number:g.momo_number_or_code,receiver_display_label:g.payee_label,receiver_network:g.network||'unknown',payment_rail:g.network?'rwanda_momo':'unavailable',settlement_currency:'RWF',image_url:await imageUrl(env,g.image_url),accent_color_hex:g.accent_color_hex,is_public:g.visibility==='public_approved',is_platform_sponsored:!!g.is_platform_sponsored,is_current_user_member:!!g.member_user,is_recurring:!!g.recurring_cadence,recurring_cadence:g.recurring_cadence||'monthly',visibility_status:g.visibility,moderation_status:g.status==='archived'?'archived':g.visibility==='public_approved'?'approved':'not_requested',suggested_amount_rwf:g.suggested_amount_rwf,created_at:iso(g.created_at)});
const prefsDto=p=>({contribution_confirmations:!!p.contribution_confirmations,payment_reminders:!!p.payment_reminders,group_updates:!!p.group_updates,security_notices:!!p.security_notices});
const intentSql=`SELECT i.*,p.momo_number_or_code,p.label,p.network FROM member_contribution_intents i JOIN collect_payees p ON p.id=i.payee_id WHERE i.user_id=?`;
const intentDto=i=>({id:i.id,collection_id:i.group_id,amount_minor:i.amount_rwf,expected_amount_rwf:i.amount_rwf,rail:'rwanda_momo',currency:'RWF',status:i.status==='pending'&&i.expires_at<=now()?'expired':i.status,created_at:iso(i.created_at),expires_at:iso(i.expires_at),receiver_momo_number:i.momo_number_or_code,receiver_label:i.label,network:i.network,receiver_momo_number_hash:'',sender_phone_hash:i.sender_phone_hash||''});
const financialSql=`SELECT a.id,a.group_id,a.member_user_id,a.amount_rwf,j.posted_at,t.provider_reference,g.title,p.public_id FROM collect_payment_allocations a JOIN collect_journals j ON j.allocation_id=a.id AND j.status='posted' JOIN collect_transactions t ON t.id=a.transaction_id JOIN collect_groups g ON g.id=a.group_id LEFT JOIN collect_profiles p ON p.user_id=a.member_user_id WHERE EXISTS(SELECT 1 FROM collect_memberships m WHERE m.group_id=a.group_id AND m.user_id=? AND m.status='active') ORDER BY j.posted_at DESC,a.id`;
async function financial(env,s){
 const rows=await batch(env,s,[q(env,financialSql,s.user_id)]);
 return rows[0].results;
}
function sums(rows,s){let total=0,own=0;const ids=new Set();for(const r of rows){total=safe(total+r.amount_rwf);if(r.member_user_id===s.user_id){own=safe(own+r.amount_rwf);ids.add(r.group_id);}}return{total,own,ids:[...ids].sort()};}
function notice(env,userId,type,title,text,groupId=null,key=crypto.randomUUID()) {
 const event=crypto.randomUUID(),dedup=`member:${type}:${key}`,at=now();
 const column=type==='payment_reminder'?'payment_reminders':type==='security_notice'?'security_notices':type==='contribution_confirmation'?'contribution_confirmations':'group_updates';
 return [q(env,`INSERT INTO member_notification_events(id,user_id,group_id,type,title,body,deep_link,created_at)
 SELECT ?,u.id,?,?,?,?,?,? FROM collect_users u JOIN member_notification_preferences p ON p.user_id=u.id
 WHERE u.id=? AND u.status='active' AND u.email IS NOT NULL AND p.${column}=1
 AND NOT EXISTS(SELECT 1 FROM collect_notification_outbox WHERE recipient_user_id=u.id AND channel='email' AND deduplication_key=?)`,
 event,groupId,type,title,text,groupId?`/groups/${groupId}`:'/home',at,userId,dedup),
 q(env,`INSERT INTO collect_notification_outbox(id,recipient_user_id,group_id,channel,notification_type,deduplication_key,payload_json,created_at,updated_at)
 SELECT ?,e.user_id,e.group_id,'email',?,?,json_object('to',u.email,'subject',e.title,'text',e.body,'member_event_id',e.id),?,?
 FROM member_notification_events e JOIN collect_users u ON u.id=e.user_id WHERE e.id=?`,crypto.randomUUID(),type,dedup,at,at,event)];
}
async function imageUrl(env,reference) {
 if(!reference?.startsWith('member-media:'))return reference;
 const id=reference.slice(13),until=now()+600,signature=await otpHash(env,`media:${id}`,String(until));
 return `${env.MEMBER_ORIGIN||env.ADMIN_ORIGIN}/api/member/media/${id}?until=${until}&signature=${signature}`;
}
async function imageReference(env,s,value,groupId=null) {
 if(value==null||value==='')return null;
 if(typeof value!=='string'||value.length>1000)fail(400,'invalid_media','Choose a Collect group photo.');
 if(/^collect-cover:[a-z0-9_-]+:v[1-9][0-9]*$/.test(value))return value;
 let url;try{url=new URL(value);}catch{fail(400,'invalid_media','Choose a Collect group photo.');}
 const id=url.pathname.split('/').at(-1);if(url.origin!==(env.MEMBER_ORIGIN||env.ADMIN_ORIGIN)||!url.pathname.startsWith('/api/member/media/')||!uuid(id))fail(400,'invalid_media','Choose a Collect group photo.');
 const media=await q(env,`SELECT id FROM member_media WHERE id=? AND (user_id=? OR EXISTS(SELECT 1 FROM collect_groups WHERE id=? AND image_url=?))`,id,s.user_id,groupId,`member-media:${id}`).first();if(!media)fail(403,'invalid_media','This photo belongs to another account.');return `member-media:${id}`;
}
async function command(env,s,name,p){
 const uid=s.user_id,at=now();
 switch(name){
 case 'get_current_member_profile':case 'ensure_current_member_profile':{const r=await batch(env,s,[q(env,profileSql,uid)]);return profileDto(r[0].results[0]);}
 case 'update_current_member_profile':{
  const network=p.p_momo_provider,number=str(p.p_momo_number,10,10),code=str(p.p_momo_pay_code||'',0,9);
  if(p.p_country_code!=='RW'||!(network==='mtn_momo'?/^07[89]\d{7}$/:network==='airtel_money'?/^07[23]\d{7}$/:/$a/).test(number)||(code&&!/^\d{4,9}$/.test(code)))fail(400,'invalid_profile','Check your Rwanda MoMo details.');
  const r=await batch(env,s,[q(env,'UPDATE collect_profiles SET momo_provider=?,momo_number=?,momo_pay_code=?,updated_at=? WHERE user_id=?',network,number,code,at,uid),q(env,'UPDATE collect_users SET version=version+1,updated_at=? WHERE id=?',at,uid),q(env,'UPDATE member_sms_consent SET enabled=0,updated_at=? WHERE user_id=?',at,uid),q(env,profileSql,uid),...notice(env,uid,'security_notice','Your Collect profile was updated','Your Rwanda MoMo profile details changed. If this was not you, contact Collect support.')]);return profileDto(r[3].results[0]);}
 case 'list_current_user_collections':{
  const id=p.p_collection_id;if(id)checkId(id);const r=await batch(env,s,[q(env,groupsSql+` WHERE (m.user_id IS NOT NULL OR g.visibility='public_approved')${id?' AND g.id=?':''} ORDER BY g.created_at DESC,g.id`,uid,...id?[id]:[])]);return Promise.all(r[0].results.map(g=>groupDto(env,g)));}
 case 'list_notification_events':{const r=await batch(env,s,[q(env,'SELECT * FROM member_notification_events WHERE user_id=? ORDER BY created_at DESC,id LIMIT 100',uid)]);return r[0].results.map(x=>({id:x.id,user_id:uid,collection_id:x.group_id,type:x.type,title:x.title,body:x.body,deep_link:x.deep_link,status:x.status,created_at:iso(x.created_at),sent_at:iso(x.sent_at),read_at:iso(x.read_at)}));}
 case 'get_notification_preferences_v2':{const r=await batch(env,s,[q(env,'SELECT * FROM member_notification_preferences WHERE user_id=?',uid)]);const pref=r[0].results[0];return{contract_version:2,ok:true,user_id:uid,revision:pref.revision,exists:true,preferences:prefsDto(pref)};}
 case 'set_notification_preferences_v2':{
  const pref=p.p_preferences,keys=['contribution_confirmations','payment_reminders','group_updates','security_notices'];if(!pref||Object.keys(pref).length!==4||keys.some(k=>typeof pref[k]!=='boolean')||!Number.isSafeInteger(p.p_expected_revision))fail(400,'invalid_request','Invalid email preferences.');
  const r=await batch(env,s,[q(env,`UPDATE member_notification_preferences SET ${keys.map(k=>k+'=?').join(',')},revision=revision+1 WHERE user_id=? RETURNING revision`,...keys.map(k=>Number(pref[k])),uid)],[guard(env,'EXISTS(SELECT 1 FROM member_notification_preferences WHERE user_id=? AND revision=?)',[uid,p.p_expected_revision])]);return{contract_version:2,ok:true,user_id:uid,previous_revision:p.p_expected_revision,revision:r[0].results[0].revision,changed:true,updated_at:iso(at)};}
 case 'mark_notification_event_read':await batch(env,s,[q(env,"UPDATE member_notification_events SET status='read',read_at=? WHERE id=? AND user_id=?",at,checkId(p.p_event_id),uid)]);return null;
 case 'register_notification_device':case 'unregister_notification_device':fail(410,'email_only','Collect uses email notifications.');
 case 'record_sms_access_consent':{
  if(typeof p.enabled!=='boolean'||(p.momo_number_hash!=null&&!/^[a-f0-9]{64}$/.test(p.momo_number_hash)))fail(400,'invalid_request','Invalid receipt consent.');
  await batch(env,s,[q(env,'INSERT INTO member_sms_consent(user_id,enabled,momo_number_hash,updated_at) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET enabled=excluded.enabled,momo_number_hash=excluded.momo_number_hash,updated_at=excluded.updated_at',uid,Number(p.enabled),p.momo_number_hash||null,at)]);return null;}
 case 'create_private_group_with_owner_media_attested':case 'create_private_group':{
  const id=crypto.randomUUID(),title=str(p.group_name,3,160),description=str(p.group_description||'',0,1000),receiver=str(p.receiver_momo_number,10,10),network=/^07[89]\d{7}$/.test(receiver)?'mtn_momo':/^07[23]\d{7}$/.test(receiver)?'airtel_money':null;
  if(!network||!['ikimina','sport','church','wedding','other'].includes(p.group_collection_type))fail(400,'invalid_group','Check the group and MoMo receiver details.');
  // Shipped cover assets or own-origin uploaded media only; never arbitrary remote tracking URLs.
  const image=await imageReference(env,s,p.group_image_url);
  const color=p.group_accent_color_hex==null?null:str(p.group_accent_color_hex,7,9);if(color&&!/^#[a-fA-F0-9]{6}$/.test(color))fail(400,'invalid_media','Invalid group colour.');
  await batch(env,s,[q(env,`INSERT INTO collect_groups(id,slug,title,description,collection_type,category_subtype,purpose_label,status,creator_user_id,recurring_cadence,share_code,image_url,accent_color_hex,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'active',?,'monthly',?,?,?,?,?)`,id,'g-'+id,title,description,p.group_collection_type,p.group_category_subtype==null?null:str(p.group_category_subtype,0,80),p.group_purpose_label==null?null:str(p.group_purpose_label,0,160),uid,crypto.randomUUID(),image,color,at,at),q(env,"INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'owner','active',?,?,?)",id,uid,at,at,at),q(env,'INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_member_id,creation_reason,created_at) VALUES(?,?,?,?,?,?,?,?)',crypto.randomUUID(),id,str(p.receiver_label||'MoMo receiver',2,120),network,receiver,uid,'Member selected group receiver',at),...notice(env,uid,'group_update','Your Collect group is ready',`You created ${title}. Contributions are recorded only after payment review.`,id,id)]);return id;}
 case 'update_rwanda_momo_group_profile':{
  const id=checkId(p.p_collection_id);if(p.p_group_is_public===true)fail(403,'review_required','Public groups require an administrator review.');
  const image=await imageReference(env,s,p.p_group_image_url,id);
  const type=p.p_group_collection_type||'other',cadence=p.p_group_is_recurring===false?null:p.p_group_recurring_cadence||'monthly';if(!['ikimina','sport','church','wedding','other'].includes(type)||(cadence&&!['weekly','monthly','quarterly','annually'].includes(cadence)))fail(400,'invalid_group','Invalid group category.');
  await batch(env,s,[q(env,'UPDATE collect_groups SET title=?,description=?,image_url=?,accent_color_hex=?,collection_type=?,category_subtype=?,purpose_label=?,recurring_cadence=?,version=version+1,updated_at=? WHERE id=?',str(p.p_group_name,3,160),str(p.p_group_description||'',0,1000),image,p.p_group_accent_color_hex||null,type,p.p_group_category_subtype||null,p.p_group_purpose_label||null,cadence,at,id)],[memberCheck(env,s,id,true)]);return null;}
 case 'join_group_by_share_code':{
  const code=str(p.p_group_code,6,100);const rows=await batch(env,s,[q(env,"SELECT id FROM collect_groups WHERE (share_code=? OR (slug=? AND visibility='public_approved')) AND status='active'",code,code)]);const g=rows[0].results[0];if(!g)fail(404,'link_expired','This invitation is unavailable.');
  await batch(env,s,[q(env,"INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'member','active',?,?,?) ON CONFLICT(group_id,user_id) DO UPDATE SET status='active',joined_at=excluded.joined_at,version=collect_memberships.version+1,updated_at=excluded.updated_at WHERE collect_memberships.status IN ('invited','left')",g.id,uid,at,at,at),...notice(env,uid,'group_update','You joined a Collect group','Your group membership is now active.',g.id,`${g.id}:${uid}`)],[guard(env,"EXISTS(SELECT 1 FROM collect_groups WHERE id=? AND status='active' AND (share_code=? OR (slug=? AND visibility='public_approved')))",[g.id,code,code]),guard(env,"NOT EXISTS(SELECT 1 FROM collect_memberships WHERE group_id=? AND user_id=? AND status='removed')",[g.id,uid])]);return g.id;}
 case 'get_group_share_code':{const id=checkId(p.p_collection_id);const rows=await batch(env,s,[q(env,'SELECT share_code FROM collect_groups WHERE id=?',id)],[memberCheck(env,s,id)]);return rows[0].results[0].share_code;}
 case 'rotate_group_share_code_v2':{
  const id=checkId(p.p_collection_id),rid=checkId(p.p_request_id),hash=await digest(JSON.stringify({id}));const replay=await batch(env,s,[q(env,'SELECT * FROM member_requests WHERE id=? AND user_id=? AND scope=?',rid,uid,name)],[memberCheck(env,s,id,true)]),existing=replay[0].results[0];if(existing){if(existing.request_hash!==hash)fail(409,'request_conflict','This request changed.');return JSON.parse(existing.result_json);}
  const value={contract_version:1,ok:true,collection_id:id,request_id:rid,share_code:crypto.randomUUID()};
  await batch(env,s,[q(env,'UPDATE collect_groups SET share_code=?,version=version+1,updated_at=? WHERE id=?',value.share_code,at,id),q(env,'INSERT INTO member_requests(id,user_id,scope,request_hash,result_json,created_at) VALUES(?,?,?,?,?,?)',rid,uid,name,hash,JSON.stringify(value),at)],[memberCheck(env,s,id,true)]);return value;}
 case 'list_current_member_group_roster':{
  const id=checkId(p.p_collection_id),r=await batch(env,s,[q(env,'SELECT m.*,p.public_id FROM collect_memberships m JOIN collect_profiles p ON p.user_id=m.user_id WHERE m.group_id=? AND m.status=\'active\' ORDER BY p.public_id',id),q(env,financialSql,uid)],[memberCheck(env,s,id)]);
  const own=sums(r[1].results.filter(x=>x.group_id===id&&x.member_user_id===uid),s).own;
  return r[0].results.map(m=>({public_id:m.public_id,role:m.role,status:m.status,joined_at:iso(m.joined_at),amount_scope:m.user_id===uid?'own':'hidden',contributions:m.user_id===uid&&own>0?[{currency:'RWF',amount_minor:own}]:[]}));}
 case 'add_group_admin':case 'transfer_group_ownership':{
  const id=checkId(p.collection),pid=str(name==='add_group_admin'?p.member_public_id:p.new_owner_public_id,6,6);if(!/^\d{6}$/.test(pid))fail(400,'invalid_member','Enter a six digit Collect ID.');
  const target=await q(env,"SELECT p.user_id FROM collect_profiles p JOIN collect_users u ON u.id=p.user_id AND u.status='active' JOIN collect_memberships m ON m.user_id=p.user_id WHERE m.group_id=? AND p.public_id=? AND m.status='active' AND p.user_id!=?",id,pid,uid).first();if(!target)fail(400,'invalid_member','Choose another active group member.');
  const statements=name==='add_group_admin'?[q(env,"UPDATE collect_memberships SET role='admin',version=version+1,updated_at=? WHERE group_id=? AND user_id=?",at,id,target.user_id)]:[q(env,"UPDATE collect_memberships SET role='admin',version=version+1,updated_at=? WHERE group_id=? AND user_id=?",at,id,uid),q(env,"UPDATE collect_memberships SET role='owner',version=version+1,updated_at=? WHERE group_id=? AND user_id=?",at,id,target.user_id),q(env,'UPDATE collect_groups SET creator_user_id=?,version=version+1,updated_at=? WHERE id=?',target.user_id,at,id)];
  await batch(env,s,[...statements,...notice(env,target.user_id,'group_update',name==='add_group_admin'?'Your Collect group role changed':'You now own a Collect group',name==='add_group_admin'?'You are now an administrator of this group.':'The previous owner transferred this group to you.',id)],[memberCheck(env,s,id,true),guard(env,"EXISTS(SELECT 1 FROM collect_memberships m JOIN collect_users u ON u.id=m.user_id AND u.status='active' WHERE m.group_id=? AND m.user_id=? AND m.status='active')",[id,target.user_id])]);return name==='add_group_admin'?{collection_id:id,public_id:pid,role:'admin',status:'active'}:null;}
 case 'archive_group':{const id=checkId(p.collection);await batch(env,s,[q(env,"UPDATE collect_groups SET status='archived',version=version+1,updated_at=? WHERE id=?",at,id)],[memberCheck(env,s,id,true)]);return null;}
 case 'get_owner_group_health':{
  const id=checkId(p.p_collection_id||p.collection);const r=await batch(env,s,[q(env,"SELECT (SELECT count(*) FROM collect_payees WHERE group_id=? AND status='active') AS receiver,(SELECT count(*) FROM member_contribution_intents WHERE group_id=? AND status='pending' AND expires_at>?) AS pending,(SELECT count(*) FROM member_receipt_submissions WHERE user_id=? AND status='needs_review') AS review",id,id,at,uid),q(env,'SELECT * FROM member_sms_consent WHERE user_id=?',uid)],[memberCheck(env,s,id,true)]);return{collection_id:id,sms_access_enabled:r[1].results[0]?.enabled===1,receiver_configured:r[0].results[0].receiver>0,pending_payment_intents:r[0].results[0].pending,needs_review_events:r[0].results[0].review,last_synced_at:null};}
 case 'create_contribution_intent':{
  const id=crypto.randomUUID(),group=checkId(p.collection),value=amount(p.p_expected_amount_rwf);
  if(p.p_sender_phone_hash!=null&&!/^[a-f0-9]{64}$/.test(p.p_sender_phone_hash))fail(400,'invalid_request','Invalid sender profile.');
  const admission=()=>guard(env,"EXISTS(SELECT 1 FROM collect_groups g WHERE g.id=? AND g.status='active' AND (g.visibility='public_approved' OR EXISTS(SELECT 1 FROM collect_memberships m WHERE m.group_id=g.id AND m.user_id=? AND m.status='active')) AND NOT EXISTS(SELECT 1 FROM collect_memberships m WHERE m.group_id=g.id AND m.user_id=? AND m.status='removed'))",[group,uid,uid]);
  const rows=await batch(env,s,[q(env,"SELECT p.* FROM collect_payees p JOIN collect_groups g ON g.id=p.group_id WHERE p.group_id=? AND p.status='active' AND g.status='active'",group)],[admission()]);const payee=rows[0].results[0];if(!payee)fail(409,'receiver_unavailable','The group receiver is unavailable.');
  const r=await batch(env,s,[q(env,"INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) SELECT id,?,'member','active',?,?,? FROM collect_groups WHERE id=? AND visibility='public_approved' ON CONFLICT(group_id,user_id) DO UPDATE SET status='active',joined_at=excluded.joined_at,version=collect_memberships.version+1,updated_at=excluded.updated_at WHERE collect_memberships.status IN ('invited','left')",uid,at,at,at,group),memberCheck(env,s,group),q(env,"INSERT INTO member_contribution_intents(id,user_id,group_id,payee_id,amount_rwf,sender_phone_hash,status,created_at,expires_at) VALUES(?,?,?,?,?,?,'pending',?,?)",id,uid,group,payee.id,value,p.p_sender_phone_hash||null,at,at+86400),q(env,intentSql+' AND i.id=?',uid,id)],[admission(),guard(env,"EXISTS(SELECT 1 FROM collect_groups g JOIN collect_payees p ON p.group_id=g.id WHERE g.id=? AND g.status='active' AND p.id=? AND p.status='active')",[group,payee.id])]);return intentDto(r[3].results[0]);}
 case 'list_current_member_recent_intents':{
  const id=p.p_intent_id;if(id)checkId(id);const r=await batch(env,s,[q(env,intentSql+(id?' AND i.id=?':'')+' ORDER BY i.created_at DESC,i.id LIMIT 50',uid,...id?[id]:[]),q(env,"SELECT count(*) AS count FROM member_contribution_intents WHERE user_id=? AND status='pending' AND expires_at>?",uid,at)]);return{items:r[0].results.map(intentDto),pending_count:r[1].results[0].count};}
 case 'list_current_member_history_page':{
  if(p.p_collection_id)checkId(p.p_collection_id);const search=str(p.p_query||'',0,80).toLowerCase(),sort=p.p_sort||'newest';if(!['newest','oldest','highest','lowest'].includes(sort))fail(400,'invalid_request','Invalid history sort.');
  const all=(await financial(env,s)).filter(r=>(!p.p_collection_id||r.group_id===p.p_collection_id)&&(!search||r.title.toLowerCase().includes(search)||r.provider_reference.toLowerCase().includes(search)));
  all.sort((a,b)=>(sort==='highest'?b.amount_rwf-a.amount_rwf:sort==='lowest'?a.amount_rwf-b.amount_rwf:0)||(sort==='oldest'?a.posted_at-b.posted_at:b.posted_at-a.posted_at)||a.id.localeCompare(b.id));
  const revision=(await digest(JSON.stringify(all.map(x=>[x.id,x.amount_rwf,x.posted_at])))).slice(0,32),cursor=p.p_cursor;let start=0;if(cursor){if(cursor.revision!==revision||!uuid(cursor.after))fail(409,'history_changed','History changed. Refresh to continue.');start=all.findIndex(x=>x.id===cursor.after)+1;if(start===0||start>=all.length)fail(409,'history_changed','History changed. Refresh to continue.');}
  const limit=p.p_limit||50;if(!Number.isSafeInteger(limit)||limit<1||limit>50)fail(400,'invalid_request','Invalid history window.');const page=all.slice(start,start+limit),totals=sums(all,s);
  return{items:page.map(x=>({payment_id:x.id,collection_id:x.group_id,rail:'rwanda_momo',currency:'RWF',amount_minor:x.amount_rwf,amount_rwf:x.amount_rwf,posted_at:iso(x.posted_at),supporter_label:x.member_user_id===uid?'You':'Collect member',contributor_public_id:x.member_user_id===uid?x.public_id:null,transaction_id:x.provider_reference,is_current_user_contribution:x.member_user_id===uid})),total_count:all.length,totals:{RWF:totals.total},own_totals:{RWF:totals.own},own_collection_ids:totals.ids,revision,next_cursor:start+page.length<all.length?{revision,after:page.at(-1).id}:null};}
 case 'list_current_member_collection_balances':{
  const r=await batch(env,s,[q(env,"SELECT group_id FROM collect_memberships WHERE user_id=? AND status='active'",uid),q(env,financialSql,uid)]);return r[0].results.map(g=>{const entries=r[1].results.filter(x=>x.group_id===g.group_id),total=sums(entries,s);return{collection_id:g.group_id,currency:'RWF',balances:[{currency:'RWF',amount_raised_minor:total.total,current_user_balance_minor:total.own}],supporter_count:new Set(entries.map(x=>x.member_user_id).filter(Boolean)).size};});}
 case 'create_mobile_support_request':await batch(env,s,[q(env,'INSERT INTO member_support_requests(id,user_id,subject,message,created_at) VALUES(?,?,?,?,?)',crypto.randomUUID(),uid,str(p.request_subject,3,160),str(p.request_message,5,4000),at)]);return null;
 default:fail(404,'unknown_command','This operation is unavailable.');
 }
}
function privacyReceipt(row,submission=null,replay=false){return{contract_version:1,request_id:row.id,scope:'own_account_eligible_data',state:'pending_review',reason_code:'account_deletion_requested',reason_supplied:!!row.reason,accepted_at:micro(row.created_at),policy_review_pending:true,subject_scope_review_pending:true,erasure_completed:false,account_access_restricted:false,auth_removed:false,retention_approval_granted:false,processor_operation_started:false,...submission?{submission_id:submission,replay,equivalent_active_request:replay||row.id!==submission}:{}};}
async function privacy(env,s,path,p){
 if(path==='submit'){
  const id=checkId(p.p_request_id),reason=p.p_reason==null?null:str(p.p_reason,0,500);if(s.verified_at<now()-600)fail(403,'fresh_verification_required','Confirm your email again.');
  const replay=await batch(env,s,[q(env,"SELECT * FROM member_privacy_requests WHERE user_id=? AND (id=? OR status='awaiting_review') ORDER BY created_at LIMIT 1",s.user_id,id)]),existing=replay[0].results[0];if(existing){if(existing.id===id&&existing.reason!==reason)fail(409,'request_conflict','The request was already submitted with another reason.');return privacyReceipt(existing,id,existing.id===id);}
  const row={id,reason,created_at:now()};await batch(env,s,[q(env,'INSERT INTO member_privacy_requests(id,user_id,reason,created_at) VALUES(?,?,?,?)',id,s.user_id,reason,row.created_at)]);return privacyReceipt(row,id);
 }
 const rows=await batch(env,s,[q(env,`SELECT * FROM member_privacy_requests WHERE user_id=?${p.p_request_id?' AND id=?':''} ORDER BY created_at DESC LIMIT 1`,s.user_id,...p.p_request_id?[checkId(p.p_request_id)]:[])]);const row=rows[0].results[0];if(!row){if(path==='current')return null;fail(404,'not_found','No account request was found.');}
 if(path==='review')return{contract_version:1,scope:'own_account_privacy_review',request_id:row.id,checked_at:micro(now()),revision:0,review_state:'awaiting_review',outcome_code:null,outcome_recorded_at:null,completion:'blocked',blocking_reason:'policy_authority_unavailable',policy_acceptance_granted:false,subject_scope_review_pending:true,legal_hold_review_pending:true,copy_dispositions_verified:false,destructive_execution_available:false,erasure_completed:false,account_access_restricted:false,auth_removed:false,processor_operation_started:false};
 return privacyReceipt(row);
}
export async function handleMember(request,env,ctx){
 const url=new URL(request.url);if(!url.pathname.startsWith('/api/member/'))return null;origin(request,env);
 const path=url.pathname.slice('/api/member/'.length);
 if(path==='auth/session'&&request.method==='GET')return response({user:publicSession(await session(request,env,true))});
 const p=request.method==='POST'?await body(request,path==='media/upload'?8*1024*1024:32768):{};
 if(path==='auth/sign-out'&&request.method==='POST')return signOut(request,env);
 if(path==='auth/request-code'&&request.method==='POST')return issue(request,env,p);
 if(path==='auth/verify-code'&&request.method==='POST')return verify(request,env,p);
 if(path==='auth/refresh'&&request.method==='POST'){
  const old=await session(request,env,false,true),access=randomToken(),refresh=randomToken(),at=now();
  const result=await q(env,'UPDATE member_sessions SET token_hash=?,refresh_hash=?,expires_at=? WHERE id=? AND refresh_hash=? AND refresh_until>? AND EXISTS(SELECT 1 FROM collect_users WHERE id=member_sessions.user_id AND status=\'active\') RETURNING *',await digest(access),await digest(refresh),Math.min(at+3600,old.refresh_until),old.id,old.refresh_hash,at).first();if(!result)fail(401,'unauthenticated','Sign in again.');return sessionResponse(request,env,{...result,email:old.email},access,refresh);
 }
 if(path==='public/collections'&&request.method==='GET'){const r=await q(env,groupsSql+" WHERE g.visibility='public_approved' AND g.status='active' ORDER BY g.created_at DESC,g.id",null).all();return response({data:await Promise.all(r.results.map(g=>groupDto(env,g)))});}
 if(path==='public/content'&&request.method==='POST'){
  const name=str(p.name,1,100),params=p.params||{},key=name==='get_active_policy_document'?'policy:'+str(params.p_kind,1,30):name;const row=await q(env,'SELECT payload_json FROM member_content WHERE kind=?',key).first();if(!row)fail(503,'content_unavailable','This content is awaiting publication.');return response({data:JSON.parse(row.payload_json)});
 }
 if(path.startsWith('media/')&&path!=='media/upload'&&request.method==='GET'){
  const id=checkId(path.slice(6)),until=Number(url.searchParams.get('until')),signature=url.searchParams.get('signature');
  if(!Number.isSafeInteger(until)||until<now()||until>now()+600||signature!==await otpHash(env,`media:${id}`,String(until)))fail(403,'media_expired','Refresh the group photo.');
  const record=await q(env,'SELECT * FROM member_media WHERE id=?',id).first(),object=record&&env.MEMBER_MEDIA?.get?await env.MEMBER_MEDIA.get(record.object_key):null;if(!object)fail(404,'not_found','Photo unavailable.');
  return new Response(object.body,{headers:{'Content-Type':record.content_type,'Cache-Control':'private, max-age=120','X-Content-Type-Options':'nosniff'}});
 }
 const s=await session(request,env);
 if(path==='media/upload'&&request.method==='POST'){
  if(!env.MEMBER_MEDIA?.put)fail(503,'media_unavailable','Photo storage is unavailable.');
  if(typeof p.image!=='string')fail(400,'invalid_media','Choose a photo.');const match=/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/.exec(p.image);if(!match)fail(400,'invalid_media','Choose a JPEG, PNG or WebP photo.');
  let bytes;try{bytes=Uint8Array.from(atob(match[2]),c=>c.charCodeAt(0));}catch{fail(400,'invalid_media','Invalid photo.');}
  const valid=match[1]==='image/jpeg'?bytes[0]===255&&bytes[1]===216&&bytes[2]===255:match[1]==='image/png'?bytes.slice(0,8).join(',')==='137,80,78,71,13,10,26,10':new TextDecoder().decode(bytes.slice(0,4))==='RIFF'&&new TextDecoder().decode(bytes.slice(8,12))==='WEBP';
  if(!valid||bytes.length<12||bytes.length>5*1024*1024)fail(400,'invalid_media','Choose a valid photo smaller than 5 MB.');
  const id=crypto.randomUUID(),key=`member-media/${s.user_id}/${id}`;await env.MEMBER_MEDIA.put(key,bytes,{httpMetadata:{contentType:match[1]}});
  const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');
  await batch(env,s,[q(env,'INSERT INTO member_media(id,user_id,object_key,content_type,body_hash,created_at) VALUES(?,?,?,?,?,?)',id,s.user_id,key,match[1],hash,now())]);return response({data:{image_url:await imageUrl(env,'member-media:'+id)}});
 }
 if(path==='privacy/request-code'&&request.method==='POST')return issue(request,env,{email:s.email},'privacy',s);
 if(path==='privacy/verify-code'&&request.method==='POST')return verify(request,env,{...p,email:s.email},'privacy',s);
 if(path.startsWith('privacy/')&&request.method==='POST')return response({data:await privacy(env,s,path.slice(8),p)});
 if(path==='command'&&request.method==='POST')return response({data:await command(env,s,str(p.name,1,100),p.params||{})});
 if(path==='receipts'&&request.method==='POST'){
  const id=checkId(p.client_envelope_id),sender=str(p.raw_sender,1,80);str(p.raw_body,1,16000);
  // The body hash covers the exact received UTF-8 text, including surrounding whitespace.
  const raw=p.raw_body,hash=await digest(raw),key=`member-receipts/${s.user_id}/${id}`;
  const replay=await batch(env,s,[q(env,'SELECT * FROM member_receipt_submissions WHERE id=? AND user_id=?',id,s.user_id)]),old=replay[0].results[0];if(old){if(old.body_hash!==hash||old.raw_sender!==sender)fail(409,'receipt_conflict','Receipt identity does not match.');return response({data:{ok:true,receipt:{contract_version:2,client_envelope_id:id,raw_sms_id:id,stored:true,owner_user_id:s.user_id,body_sha256:hash},evidence_level:'member_submitted',processing:'needs_review'}});}
  if(!env.MEMBER_MEDIA?.put)fail(503,'receipt_storage_unavailable','Receipt storage is unavailable.');
  const consent=await batch(env,s,[q(env,'SELECT enabled FROM member_sms_consent WHERE user_id=?',s.user_id)]);if(consent[0].results[0]?.enabled!==1)fail(403,'consent_required','Enable receipt access first.');
  // Private immutable object namespace: no public download route and no financial finality.
  const stored=await env.MEMBER_MEDIA.put(key,JSON.stringify({raw_sender:sender,raw_body:raw}),{onlyIf:{etagDoesNotMatch:'*'},httpMetadata:{contentType:'application/json'}});
  if(!stored){const previous=await env.MEMBER_MEDIA.get(key);let payload;try{payload=await previous?.json();}catch{}if(!payload||payload.raw_body!==raw||payload.raw_sender!==sender)fail(409,'receipt_conflict','Receipt identity does not match.');}
  await batch(env,s,[q(env,'INSERT OR IGNORE INTO member_receipt_submissions(id,user_id,body_hash,raw_sender,payload_object_key,received_at,created_at) VALUES(?,?,?,?,?,?,?)',id,s.user_id,hash,sender,key,now(),now()),guard(env,'EXISTS(SELECT 1 FROM member_receipt_submissions WHERE id=? AND user_id=? AND body_hash=? AND raw_sender=?)',[id,s.user_id,hash,sender])],[guard(env,'EXISTS(SELECT 1 FROM member_sms_consent WHERE user_id=? AND enabled=1)',[s.user_id])]);
  return response({data:{ok:true,receipt:{contract_version:2,client_envelope_id:id,raw_sms_id:id,stored:true,owner_user_id:s.user_id,body_sha256:hash},evidence_level:'member_submitted',processing:'needs_review'}});
 }
 fail(404,'not_found','This operation is unavailable.');
}
