import {auditStatement} from '../core.js';
import {personInsertStatement,membershipWriteStatement} from '../canonical_people.js';
import {canonicalManagedActor} from './postgres-managed-actor.js';
import {authorize} from './policy.js';
import {requirePort,requireThat,BuriError} from './errors.js';
import {canonicalJson,exactKeys,normalizePhone,requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';

const copy=value=>JSON.parse(canonicalJson(value));
const integer=value=>pgInteger(value,{minimum:1,code:'member_contract_violation'});
// Match the same presentation characters accepted by normalizePhone; a
// differently formatted existing MoMo route must not create a second member.
const compactRoute=value=>`replace(replace(replace(replace(coalesce(${value},''),' ',''),'(',''),')',''),'-','')`;

/** The caller owns the admitted transaction and Collect mutation lock. Reuses
 * exactly the person/public-ID and membership statements used by Collect Admin.
 * No Auth user, operator principal, payment, balance or ledger entry is created.
 * Native approval is additional to current shared permission/fresh-email guards.
 * A shared read-only staff role cannot gain writes from a native capability.
 */
export class PostgresCollectMemberCommands {
 constructor({authority}){
  requirePort(authority,['assertOwned','session']);requireId(authority.groupId);
  requirePort(authority.db,['prepare','statement']);
  this.authority=authority;this.db=authority.db;this.groupId=authority.groupId;
 }
 async owned(){await this.authority.assertOwned();}
 async current(sql,cmd,{admin=false}={}){
  await this.owned();const canonical=await canonicalManagedActor(this.authority,sql);
  const actor=await this.authority.session(sql,{id:cmd.sessionId,now:canonical.nowMs});
  authorize(actor,this.groupId,'members.enroll',{now:canonical.nowMs});
  requireThat(actor.id===cmd.actorId&&actor.principalUserId===canonical.userId&&
   cmd.actor?.id===actor.id&&cmd.actor.sessionId===actor.sessionId&&cmd.actor.principalUserId===canonical.userId,
   'access_denied',403);
  if(admin)requireThat(actor.role==='admin','access_denied',403);
  await this.owned();
  return {canonical,native:canonicalJson({id:actor.id,sessionId:actor.sessionId,principalUserId:actor.principalUserId,
   role:actor.role,installationId:actor.installationId,installationProfile:actor.installationProfile,
   capabilities:[...actor.capabilities].sort(),expiresAt:actor.expiresAt})};
 }
 async statement(sql,value){
  await this.owned();const result=await this.db.statement(sql,value);await this.owned();
  requireThat(result?.success===true&&result.meta?.changes===1,'member_contract_violation',503);return result;
 }
 async guard(sql,canonical,permission){
  requireThat(['users.manage','collections.manage'].includes(permission),'collect_adapter_required',503);
  const id=crypto.randomUUID();
  // Generic Collect Admin person/membership commands use global operating
  // grants, not a financial beneficiary membership for the operator. Preserve
  // that exact guard scope. Native session/owner approval and the selected
  // active collection are independently checked before these statements.
  const insert=this.db.prepare(`INSERT INTO app.mutation_guards
   (id,user_id,session_id,now_seconds,collection_id,permission,minimum_assurance,expected_mfa_at,fresh_seconds)
   VALUES(?,?,?,?,?,?,?,?,?)`).bind(id,canonical.userId,canonical.sessionId,canonical.now,
    canonical.authMethod==='phone_pin'?this.groupId:null,permission,canonical.authMethod==='phone_pin'?null:2,canonical.mfa,300);
  try{
   await this.statement(sql,insert);
   await this.statement(sql,this.db.prepare('DELETE FROM app.mutation_guards WHERE id=?').bind(id));
  }catch(error){
   if(['request_not_admitted','application_fenced','application_fence_unavailable'].includes(error?.code))throw error;
   throw new BuriError('access_denied',403);
  }
 }
 input(input,keys){
  const cmd=copy(input);exactKeys(cmd,keys);requireThat(cmd.groupId===this.groupId,'access_denied',403);
  requireRequestId(cmd.actorId);requireRequestId(cmd.sessionId);requireRequestId(cmd.requestId);return cmd;
 }
 async group(sql){
  const rows=await sql.unsafe('SELECT id,status FROM app.collections WHERE id=$1 FOR SHARE',[this.groupId]);
  await this.owned();requireThat(rows.length===1&&rows[0].id===this.groupId&&rows[0].status==='active','scope_unavailable',503);
 }
 async finish(sql,cmd,initial,options){
  const final=await this.current(sql,cmd,options);
  requireThat(final.canonical.nowMs>=initial.canonical.nowMs&&final.canonical.userId===initial.canonical.userId&&
   final.canonical.sessionId===initial.canonical.sessionId&&final.canonical.mfa===initial.canonical.mfa&&
   final.native===initial.native,'access_denied',403);
  return final;
 }
 async createDirectMember(sql,input){
  const cmd=this.input(input,['groupId','name','phone','requestId','actorId','sessionId','actor']);
  requireThat(typeof cmd.name==='string'&&cmd.name===cmd.name.trim()&&cmd.name.length>=2&&cmd.name.length<=100&&
   !/[\u0000-\u001f\u007f]/.test(cmd.name),'invalid_name');
  requireThat(normalizePhone(cmd.phone)===cmd.phone,'invalid_phone');
  const initial=await this.current(sql,cmd);await this.group(sql);
  await this.guard(sql,initial.canonical,'users.manage');await this.guard(sql,initial.canonical,'collections.manage');
  const local='0'+cmd.phone.slice(4),digits=cmd.phone.slice(1),national=cmd.phone.slice(4);
  // Open the existing member only when the canonical MoMo route identifies one
  // unambiguous member. Never create a second beneficiary or reactivate it here.
  const duplicate=await sql.unsafe(`SELECT u.id,u.full_name,u.momo_number,m.active,m.revision,
   coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=u.id),0) AS balance
   FROM app.memberships m JOIN app.users u ON u.id=m.user_id
   WHERE m.collection_id=$1 AND (${compactRoute('u.momo_number')} IN($2,$3,$4,$5,$6) OR
    ${compactRoute('u.phone')} IN($2,$3,$4,$5,$6)) LIMIT 2`,[this.groupId,local,cmd.phone,digits,'00'+digits,national]);
  await this.owned();
  if(duplicate.length){
   requireThat(duplicate.length===1,'duplicate_phone',409);
   const row=duplicate[0];let matched=false;
   try{matched=normalizePhone(row.momo_number)===cmd.phone}catch{/* A login route is not a MoMo identity. */}
   requireThat(matched&&typeof row.full_name==='string'&&row.full_name.length>=1&&row.full_name.length<=100,
    'duplicate_phone',409);
   const active=pgInteger(row.active);requireThat(active===0||active===1,'member_contract_violation',503);
   const response={id:row.id,groupId:this.groupId,name:row.full_name,phone:cmd.phone,
    active:active===1,version:integer(row.revision),balanceRwf:pgInteger(row.balance),existing:true};
   const final=await this.finish(sql,cmd,initial);
   await this.guard(sql,final.canonical,'users.manage');await this.guard(sql,final.canonical,'collections.manage');
   return response;
  }
  const id=crypto.randomUUID(),timestamp=new Date(initial.canonical.nowMs).toISOString();
  await this.statement(sql,personInsertStatement(this.db,{id,name:cmd.name,phone:null,email:null,memberType:'direct',
   provider:'',momo:local,code:'',status:'active',timestamp}));
  await this.statement(sql,membershipWriteStatement(this.db,{create:true,id:crypto.randomUUID(),groupId:this.groupId,userId:id,
   role:'member',active:1,timestamp}));
  const rows=await sql.unsafe(`SELECT u.id,u.full_name,u.momo_number,u.member_type,u.access_status,m.role,m.active,m.revision,
   coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=u.id),0) AS balance
   FROM app.memberships m JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1 AND u.id=$2`,[this.groupId,id]);
  const row=rows[0];requireThat(rows.length===1&&row.id===id&&row.member_type==='direct'&&row.access_status==='active'&&
   row.full_name===cmd.name&&row.role==='member'&&integer(row.active)===1&&integer(row.revision)===1&&normalizePhone(row.momo_number)===cmd.phone,
   'member_contract_violation',503);
  const response={id,groupId:this.groupId,name:row.full_name,phone:cmd.phone,active:true,version:integer(row.revision),balanceRwf:pgInteger(row.balance)};
  await this.statement(sql,auditStatement({DB:this.db},{userId:initial.canonical.userId,sessionId:initial.canonical.sessionId},
   'burimunsi.enroll','user',id,{collection_id:this.groupId,native_actor_id:cmd.actorId,native_session_id:cmd.sessionId},cmd.requestId));
  const final=await this.finish(sql,cmd,initial);
  await this.guard(sql,final.canonical,'users.manage');await this.guard(sql,final.canonical,'collections.manage');
  return response;
 }
 async setMembershipActive(sql,input){
  const cmd=this.input(input,['groupId','memberId','active','expectedVersion','requestId','actorId','sessionId','actor']);
  requireId(cmd.memberId);requireThat(typeof cmd.active==='boolean'&&Number.isSafeInteger(cmd.expectedVersion)&&
   cmd.expectedVersion>0&&cmd.expectedVersion<Number.MAX_SAFE_INTEGER,'invalid_membership_change');
  const initial=await this.current(sql,cmd,{admin:true});await this.group(sql);
  await this.guard(sql,initial.canonical,'collections.manage');
  const rows=await sql.unsafe(`SELECT m.user_id,m.role,m.active,m.revision,u.member_type,u.access_status FROM app.memberships m
   JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1 AND m.user_id=$2 FOR UPDATE OF m,u`,[this.groupId,cmd.memberId]);
  await this.owned();const row=rows[0];
  requireThat(rows.length===1&&row.user_id===cmd.memberId&&['member','admin'].includes(row.role)&&row.member_type!=='operator'&&
   row.access_status==='active'&&integer(row.revision)===cmd.expectedVersion,'membership_changed',409);
  await this.statement(sql,membershipWriteStatement(this.db,{create:false,groupId:this.groupId,userId:cmd.memberId,role:row.role,active:Number(cmd.active)}));
  const changed=await sql.unsafe('SELECT user_id,role,active,revision FROM app.memberships WHERE collection_id=$1 AND user_id=$2',[this.groupId,cmd.memberId]);
  requireThat(changed.length===1&&changed[0].user_id===cmd.memberId&&changed[0].role===row.role&&
   pgInteger(changed[0].active)===Number(cmd.active)&&integer(changed[0].revision)===cmd.expectedVersion+1,'member_contract_violation',503);
  await this.statement(sql,auditStatement({DB:this.db},{userId:initial.canonical.userId,sessionId:initial.canonical.sessionId},
   'burimunsi.membership','membership',this.groupId+'/'+cmd.memberId,
   {collection_id:this.groupId,active:cmd.active,version:cmd.expectedVersion+1,native_actor_id:cmd.actorId,native_session_id:cmd.sessionId},cmd.requestId));
  const final=await this.finish(sql,cmd,initial,{admin:true});await this.guard(sql,final.canonical,'collections.manage');
  return {applied:true,groupId:this.groupId,memberId:cmd.memberId,active:cmd.active,version:cmd.expectedVersion+1};
 }
}
