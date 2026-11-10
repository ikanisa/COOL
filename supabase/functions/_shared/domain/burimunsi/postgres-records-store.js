import {readCommandOutcome} from './postgres-command-outcome.js';
import {requireThat,requirePort,BuriError} from './errors.js';
import {pgInteger} from './postgres-values.js';
import {sha256,canonicalJson,normalizePhone} from './values.js';

const PAYMENTS=`SELECT t.id,x.collection_id,t.payer_name,t.payer_identifier,t.amount_minor,t.transaction_datetime_raw,t.provider_transaction_id,
 t.allocation_state,t.has_conflict,t.version,t.created_at,p.member_id,u.momo_number,p.status AS payment_status,
 (SELECT min(src.raw_sms_id) FROM app.momo_transaction_sources src WHERE src.transaction_id=t.id AND src.relation='accepted') AS source_id
 FROM private.burimunsi_transaction_scopes x
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
 LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
 LEFT JOIN app.users u ON u.id=p.member_id
 WHERE x.collection_id=$1`;
const MEMBERS=`SELECT u.id,m.collection_id,u.full_name,u.momo_number,m.active,m.revision,u.revision AS person_revision,m.joined_at,
 coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id),0) AS balance
 FROM app.memberships m JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1`;
const LEDGER=`SELECT l.id,l.collection_id,l.member_id,l.amount_minor,l.posted_at,t.id AS transaction_id,
 coalesce(t.provider_transaction_id,e.external_reference) AS ft_id,
 coalesce(t.transaction_datetime_raw,e.observed_at) AS source_at,
 coalesce(t.payer_name,p.payer_display_name) AS payer_name,u.momo_number
 FROM app.ledger_entries l JOIN app.payments p ON p.id=l.payment_id AND p.collection_id=l.collection_id
 JOIN app.payment_evidence e ON e.id=l.evidence_id
 JOIN app.users u ON u.id=l.member_id
 LEFT JOIN app.momo_financial_links f ON f.payment_id=p.id
 LEFT JOIN app.momo_transactions t ON t.id=f.transaction_id
 WHERE l.collection_id=$1 AND l.member_id=$2`;
// Collect stores canonical MoMo routes in local 07... form; native DTOs require
// E.164. Normalize only the authoritative member reference, never payer evidence
// or the original SMS. Missing/masked member identity has no login-phone fallback.
const memberPhone=(value,nullable=false)=>{
 if(nullable&&(value===null||value===undefined||value===''))return null;
 try{return normalizePhone(value);}catch{throw new BuriError('invalid_member_projection',503);}
};
const payment=r=>({id:r.id,groupId:r.collection_id,payerNameRaw:r.payer_name??'',payerPhoneRaw:r.payer_identifier??'',amountRwf:pgInteger(r.amount_minor),atRaw:r.transaction_datetime_raw??'',ftId:r.provider_transaction_id,
 state:pgInteger(r.has_conflict)===1?'conflict':r.payment_status==='reversed'?'reversed':['reconciled','confirmed','corrected'].includes(r.payment_status)?'posted':r.allocation_state==='unallocated'?'unallocated':'processing',
 version:pgInteger(r.version),memberId:r.member_id??null,memberPhone:memberPhone(r.momo_number,true),sourceId:r.source_id??null});
const member=r=>({id:r.id,groupId:r.collection_id,name:r.full_name,phone:memberPhone(r.momo_number),balanceRwf:pgInteger(r.balance),active:pgInteger(r.active)===1,version:pgInteger(r.revision)});
const ledger=r=>({id:r.id,groupId:r.collection_id,transactionId:r.transaction_id??null,amountRwf:pgInteger(r.amount_minor),atRaw:r.source_at??'',ftId:r.ft_id??'',payerNameRaw:r.payer_name??'',memberPhone:memberPhone(r.momo_number)});
const safeLike=s=>'%'+s.replaceAll('\\','\\\\').replaceAll('%','\\%').replaceAll('_','\\_')+'%';

/** Reuses canonical app tables, never a client or SMS-derived balance.
 * sourceReader must reuse Collect's admitted decrypt/read command and validate
 * each source's group/transaction lineage inside this same snapshot. It is not
 * replaced with an independent raw-body table or a broad storage credential.
 */
export class PostgresRecordsStore {
  constructor({authority,sourceReader,clock=()=>Date.now()}){
    requirePort(authority,['read','session']);requirePort(sourceReader,['revision','page','detail']);
    Object.assign(this,{authority,sourceReader,clock});this.groupId=authority.groupId;
  }
  withCommandSnapshot(fn){return this.withReadSnapshot(fn,{primary:true});}
  async withReadSnapshot(fn,{primary=false}={}){
    return this.authority.read(async sql=>{
      if(primary){
        const check=(await sql.unsafe('SELECT pg_is_in_recovery() AS replica'))[0];
        requireThat(check?.replica===false,'command_primary_required',503);
      }
      const at=new Date(this.clock()).toISOString(),group=this.groupId;
      const scope=g=>requireThat(g===group,'access_denied',403);
      const ops={
        reloadActor:id=>this.authority.session(sql,{id}),
        loadBinding:async g=>{
          scope(g);const r=(await sql.unsafe(`SELECT b.id,b.version,b.status,c.installation_id,c.revoked_at,s.enabled,s.binding_version
            FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id AND b.receiving_account_id=s.receiving_account_id
            JOIN app.momo_gateway_credentials c ON c.binding_id=b.id
            WHERE s.collection_id=$1`,[g]))[0];
          return r?{id:r.id,groupId:g,installationId:r.installation_id,active:r.enabled&&r.status==='active'&&!r.revoked_at&&pgInteger(r.version)===pgInteger(r.binding_version)}:null;
        },
        canonicalHome:async g=>{
          scope(g);
          const totals=(await sql.unsafe(`SELECT coalesce(sum(amount_minor),0) AS balance,
            coalesce(sum(CASE WHEN posted_at::timestamptz>=date_trunc('day',$2::timestamptz AT TIME ZONE 'Africa/Kigali') AT TIME ZONE 'Africa/Kigali' THEN amount_minor ELSE 0 END),0) AS today
            FROM app.ledger_entries WHERE collection_id=$1`,[g,at]))[0];
          const counts=(await sql.unsafe(`SELECT
            (SELECT count(*) FROM app.memberships WHERE collection_id=$1 AND active=1) AS members,
            (SELECT count(*) FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id WHERE x.collection_id=$1 AND t.allocation_state='unallocated' AND t.has_conflict=0) AS unallocated`,[g]))[0];
          const recent=await sql.unsafe(PAYMENTS+' ORDER BY t.transaction_at DESC NULLS LAST,t.id DESC LIMIT 3',[g]);
          return {groupBalanceRwf:pgInteger(totals.balance),todayRwf:pgInteger(totals.today),memberCount:pgInteger(counts.members),unallocatedCount:pgInteger(counts.unallocated),recentPayments:recent.map(payment),asOf:at};
        },
        listRevision:async(g,kind,memberId)=>{
          scope(g);let rows;
          if(kind==='payments')rows=await sql.unsafe(`SELECT t.id,t.version,p.revision AS payment_revision,p.status FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id WHERE x.collection_id=$1 ORDER BY t.id LIMIT 100001`,[g]);
          else if(kind==='members')rows=await sql.unsafe('SELECT m.id,m.revision,u.revision AS person_revision,(SELECT count(*) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id) AS entries FROM app.memberships m JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1 ORDER BY m.id LIMIT 100001',[g]);
          else if(kind==='ledger'){requireThat(memberId,'member_required');rows=await sql.unsafe('SELECT id FROM app.ledger_entries WHERE collection_id=$1 AND member_id=$2 ORDER BY id LIMIT 100001',[g,memberId]);}
          else if(kind==='staff')rows=await sql.unsafe('SELECT id,version FROM private.burimunsi_accounts WHERE collection_id=$1 AND role=\'staff\' ORDER BY id LIMIT 100001',[g]);
          else if(kind==='audit')rows=await sql.unsafe('SELECT id FROM private.burimunsi_audit WHERE collection_id=$1 ORDER BY id LIMIT 100001',[g]);
          else return this.sourceReader.revision(sql,g);
          requireThat(rows.length<=100000,'snapshot_limit',413);return sha256(canonicalJson(Array.from(rows)));
        },
        readPage:async query=>{
          const {groupId:g,kind,memberId,q,filter,limit,after}=query;scope(g);
          // Cursor contains only an integer offset authenticated against the full revision.
          const offset=after?.offset??0;requireThat(Number.isSafeInteger(offset)&&offset>=0&&offset<=100000,'invalid_cursor');
          let rows,total,read;
          if(kind==='payments'){
            let where=PAYMENTS+" AND (t.payer_name ILIKE $2 ESCAPE '\\' OR t.provider_transaction_id ILIKE $2 ESCAPE '\\')";
            if(filter==='unallocated')where+=" AND t.allocation_state='unallocated' AND t.has_conflict=0";
            if(filter==='allocated')where+=" AND p.status IN ('reconciled','confirmed','corrected')";
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM ('+where+') AS scoped',[g,safeLike(q)]))[0].total);
            rows=await sql.unsafe(where+' ORDER BY t.transaction_at DESC NULLS LAST,t.id DESC LIMIT $3 OFFSET $4',[g,safeLike(q),limit,offset]);read=payment;
          }else if(kind==='members'){
            const where=MEMBERS+" AND (u.full_name ILIKE $2 ESCAPE '\\' OR u.momo_number ILIKE $2 ESCAPE '\\')";
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM ('+where+') AS scoped',[g,safeLike(q)]))[0].total);
            rows=await sql.unsafe(where+' ORDER BY m.joined_at DESC,u.id DESC LIMIT $3 OFFSET $4',[g,safeLike(q),limit,offset]);read=member;
          }else if(kind==='ledger'){
            requireThat(memberId,'member_required');await this.memberExists(sql,g,memberId);
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM app.ledger_entries WHERE collection_id=$1 AND member_id=$2',[g,memberId]))[0].total);
            rows=await sql.unsafe(LEDGER+' ORDER BY l.posted_at DESC,l.id DESC LIMIT $3 OFFSET $4',[g,memberId,limit,offset]);read=ledger;
          }else if(kind==='staff'){
            total=pgInteger((await sql.unsafe("SELECT count(*) AS total FROM private.burimunsi_accounts WHERE collection_id=$1 AND role='staff' AND NOT removed",[g]))[0].total);
            rows=await sql.unsafe("SELECT id,collection_id,name,phone,active,version,capabilities FROM private.burimunsi_accounts WHERE collection_id=$1 AND role='staff' AND NOT removed ORDER BY name,id LIMIT $2 OFFSET $3",[g,limit,offset]);
            read=r=>({id:r.id,groupId:r.collection_id,name:r.name,phone:r.phone,active:r.active,version:pgInteger(r.version),capabilities:r.capabilities});
          }else if(kind==='audit'){
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM private.burimunsi_audit WHERE collection_id=$1',[g]))[0].total);
            rows=await sql.unsafe('SELECT id,collection_id,action,at_ms FROM private.burimunsi_audit WHERE collection_id=$1 ORDER BY at_ms DESC,id DESC LIMIT $2 OFFSET $3',[g,limit,offset]);
            read=r=>({id:r.id,groupId:r.collection_id,action:r.action,at:new Date(pgInteger(r.at_ms)).toISOString()});
          }else return this.sourceReader.page(sql,query);
          return {items:rows.map(read),totalCount:total,after:offset+rows.length<total?{offset:offset+rows.length}:null,asOf:at};
        },
        readDetail:async({groupId:g,kind,id})=>{
          scope(g);if(kind==='sms')return this.sourceReader.detail(sql,g,id);
          const rows=await sql.unsafe((kind==='payment'?PAYMENTS:MEMBERS)+(kind==='payment'?' AND t.id=$2':' AND u.id=$2'),[g,id]);
          return rows[0]?(kind==='payment'?payment:member)(rows[0]):null;
        },
        readPaymentHistory:async(g,transactionId,max)=>{
          scope(g);requireThat(Number.isInteger(max)&&max>=1&&max<=1001,'invalid_history_limit');
          // Uses only already-present canonical fields. No second audit/ledger or
          // reconstructed approval, allocation or reversal events are introduced.
          const rows=await sql.unsafe(`SELECT * FROM (
            SELECT t.id AS canonical_record_id,x.collection_id,t.id AS transaction_id,
              'transaction_recorded' AS kind,t.created_at::timestamptz AS recorded_at,
              NULL::bigint AS amount_minor,NULL::text AS member_id
            FROM private.burimunsi_transaction_scopes x
            JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
            WHERE x.collection_id=$1 AND t.id=$2
            UNION ALL
            SELECT l.id,x.collection_id,t.id,'ledger_entry',l.posted_at::timestamptz,l.amount_minor,l.member_id::text
            FROM private.burimunsi_transaction_scopes x
            JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
            JOIN app.momo_financial_links f ON f.transaction_id=t.id
            JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
            JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=x.collection_id
            WHERE x.collection_id=$1 AND t.id=$2
          ) AS history ORDER BY recorded_at,kind,canonical_record_id LIMIT $3`,[g,transactionId,max]);
          return rows.map(r=>({canonicalRecordId:r.canonical_record_id,groupId:r.collection_id,
            transactionId:r.transaction_id,kind:r.kind,
            recordedAt:r.recorded_at instanceof Date?r.recorded_at.toISOString():r.recorded_at,
            amountRwf:r.amount_minor===null?null:pgInteger(r.amount_minor),memberId:r.member_id??null}));
        },
        readAllLedger:async(g,memberId,max)=>{
          scope(g);await this.memberExists(sql,g,memberId);return (await sql.unsafe(LEDGER+' ORDER BY l.posted_at,l.id LIMIT $3',[g,memberId,max])).map(ledger);
        },
        readRecoveryOutcome:async({groupId:g,actorId,currentSessionId,requestId,originDigest})=>{
          scope(g);
          // Current session was freshly admitted by within/reloadActor. The old
          // session supplies identity snapshots only, even after expiry/revocation.
          const rows=await sql.unsafe(`SELECT
            o.id AS origin_session_id,o.collection_id AS origin_group_id,o.account_id AS origin_actor_id,
            o.principal_user_id AS origin_principal_id,o.installation_id AS origin_installation_id,
            o.grant_id AS origin_grant_id,o.grant_version AS origin_grant_version,
            o.token_hash AS origin_token_hash,o.created_at AS origin_created_at,
            c.id AS current_session_id,c.collection_id AS current_group_id,c.account_id AS current_actor_id,
            c.principal_user_id AS current_principal_id,c.installation_id AS current_installation_id,
            c.grant_id AS current_grant_id,c.grant_version AS current_grant_version
            FROM private.burimunsi_sessions c
            JOIN private.burimunsi_sessions o ON o.collection_id=c.collection_id AND o.account_id=c.account_id
            WHERE c.collection_id=$1 AND c.account_id=$2::uuid AND c.id=$3::uuid AND o.token_hash=$4
            LIMIT 2`,[g,actorId,currentSessionId,originDigest]);
          requireThat(rows.length<=1,'invalid_recovery_proof',503);
          if(!rows.length)return null;
          const r=rows[0];
          const origin={sessionId:r.origin_session_id,groupId:r.origin_group_id,actorId:r.origin_actor_id,
            principalUserId:r.origin_principal_id,installationId:r.origin_installation_id,
            grantId:r.origin_grant_id,grantVersion:pgInteger(r.origin_grant_version),
            tokenHash:r.origin_token_hash,createdAt:pgInteger(r.origin_created_at)};
          const current={sessionId:r.current_session_id,groupId:r.current_group_id,actorId:r.current_actor_id,
            principalUserId:r.current_principal_id,installationId:r.current_installation_id,
            grantId:r.current_grant_id,grantVersion:pgInteger(r.current_grant_version)};
          const receipts=await sql.unsafe(`SELECT collection_id,actor_id,request_id,session_id,operation,created_at
            FROM private.burimunsi_command_receipts
            WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid LIMIT 2`,[g,actorId,requestId]);
          requireThat(receipts.length<=1,'invalid_recovery_receipt',503);
          const x=receipts[0];
          return {origin,current,receipt:x?{groupId:x.collection_id,actorId:x.actor_id,requestId:x.request_id,
            sessionId:x.session_id,operation:x.operation,createdAt:pgInteger(x.created_at)}:null};
        },
        readCommandOutcome:async query=>{
          scope(query.groupId);return readCommandOutcome(sql,query);
        }
      };
      return fn(ops);
    });
  }
  async memberExists(sql,group,id){requireThat((await sql.unsafe('SELECT id FROM app.memberships WHERE collection_id=$1 AND user_id=$2',[group,id])).length===1,'member_unavailable',404);}
}
