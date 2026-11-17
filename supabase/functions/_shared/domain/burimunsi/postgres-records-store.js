import {readRecoveryProof} from './postgres-operation-recovery.js';
import {readCommandOutcome} from './postgres-command-outcome.js';
import {requireThat,requirePort,BuriError} from './errors.js';
import {pgInteger} from './postgres-values.js';
import {sha256,canonicalJson,normalizePhone} from './values.js';
import {listOnboardingSuggestions} from './smart-onboarding-suggestions.js';
import {canonicalListingInstant,listingText} from './listing-query.js';

const paymentsSql=auto=>`SELECT t.id,x.collection_id,
 ${auto?"coalesce(native.value->'facts'->>'counterparty_name',t.payer_name)":"t.payer_name"} AS payer_name,
 ${auto?"coalesce(native.value->'facts'->>'counterparty_identifier',t.payer_identifier)":"t.payer_identifier"} AS payer_identifier,
 ${auto?"coalesce((native.value->'facts'->>'amount_minor')::bigint,t.amount_minor)":"t.amount_minor"} AS amount_minor,
 ${auto?"coalesce(native.value->'facts'->>'transaction_at',t.transaction_at)":"t.transaction_at"} AS transaction_at,
 ${auto?"coalesce(native.value->'facts'->>'transaction_timezone',t.transaction_timezone)":"t.transaction_timezone"} AS transaction_timezone,
 ${auto?"coalesce(native.value->'facts'->>'transaction_datetime_raw',t.transaction_datetime_raw)":"t.transaction_datetime_raw"} AS transaction_datetime_raw,
 ${auto?"coalesce(native.value->'facts'->>'provider_transaction_id',t.provider_transaction_id)":"t.provider_transaction_id"} AS provider_transaction_id,
 t.allocation_state,t.has_conflict,t.version,t.created_at,t.event_kind AS canonical_event_kind,u.id AS member_id,u.full_name AS member_full_name,u.momo_number,p.status AS payment_status,credit.posted AS ledger_posted,
 EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AS source_conflict,
 (SELECT min(src.raw_sms_id) FROM app.momo_transaction_sources src WHERE src.transaction_id=t.id AND src.relation='accepted') AS source_id${auto?",x.native_source_id,coalesce(native.value->'facts'->>'event_kind',t.event_kind) AS event_kind,coalesce((native.value->'facts'->>'fee_minor')::bigint,t.fee_minor) AS fee_minor,coalesce((native.value->'facts'->>'wallet_balance_after_minor')::bigint,t.wallet_balance_after_minor) AS wallet_balance_after_minor,native.value AS native_meta":''}
 FROM private.burimunsi_transaction_scopes x
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
 LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
 LEFT JOIN app.memberships pm ON pm.collection_id=x.collection_id AND pm.user_id=coalesce(p.member_id,CASE WHEN p.id IS NOT NULL THEN f.beneficiary_member_id END)
 LEFT JOIN app.users u ON u.id=pm.user_id
 LEFT JOIN LATERAL (SELECT count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor
  AND p.amount_minor=t.amount_minor AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
  AND u.id=p.member_id),false) AS posted
  FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) credit ON true
 LEFT JOIN LATERAL (SELECT regexp_replace(coalesce(u.momo_number,''),'[ ()-]','','g') AS compact) phone_raw ON true
 LEFT JOIN LATERAL (SELECT CASE WHEN phone_raw.compact LIKE '00%' THEN '+'||substr(phone_raw.compact,3) ELSE phone_raw.compact END AS value) phone_input ON true
 LEFT JOIN LATERAL (SELECT CASE WHEN phone_input.value ~ '^0[0-9]{9}$' THEN '+250'||substr(phone_input.value,2)
   WHEN phone_input.value ~ '^[0-9]{9}$' THEN '+250'||phone_input.value
   WHEN phone_input.value ~ '^250[0-9]{9}$' THEN '+'||phone_input.value ELSE phone_input.value END AS normalized) member_phone ON true
 ${auto?'LEFT JOIN LATERAL (SELECT private.burimunsi_auto_projection(x.native_source_id) AS value WHERE x.native_source_id IS NOT NULL) native ON true':''}
 WHERE x.collection_id=$1`;
// Only an actual positive net ledger contribution in the same collection is a
// credit. A receipt, a payment status alone, or another group's ledger is not.
const CREDITED=`SELECT x.transaction_id,sum(l.amount_minor) AS credited_amount
 FROM private.burimunsi_transaction_scopes x
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 JOIN app.momo_financial_links f ON f.transaction_id=t.id
 JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
 JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=x.collection_id
 WHERE x.collection_id=$1 AND t.event_kind='incoming_receipt' AND t.has_conflict=0
  AND p.status IN ('reconciled','confirmed')
 GROUP BY x.transaction_id HAVING count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor
  AND p.amount_minor=t.amount_minor AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
  AND EXISTS(SELECT 1 FROM app.memberships m WHERE m.collection_id=x.collection_id AND m.user_id=p.member_id)),false)`;
const MEMBERS=`SELECT u.id,m.collection_id,u.full_name,u.momo_number,m.active,m.revision,u.revision AS person_revision,m.joined_at,
 coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id),0) AS balance
 FROM app.memberships m JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1`;
const LEDGER=`SELECT l.id,l.collection_id,l.member_id,l.amount_minor,l.posted_at,t.id AS transaction_id,
 coalesce(t.provider_transaction_id,e.external_reference) AS ft_id,
 coalesce(t.transaction_datetime_raw,e.observed_at) AS source_at,
 coalesce(t.payer_name,p.payer_display_name) AS payer_name,u.momo_number,p.status AS payment_status,t.allocation_state,t.has_conflict
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
const payment=r=>{
 const native=r.native_source_id!==undefined&&r.native_source_id!==null;
 requireThat(typeof r.source_conflict==='boolean','invalid_transaction_projection',503);
 if(native)requireThat(r.native_meta?.sourceId===r.native_source_id&&typeof r.native_meta?.canReveal==='boolean'&&['successful','failed','pending','unknown'].includes(r.native_meta?.outcome),
  'invalid_transaction_projection',503);
 return {id:r.id,groupId:r.collection_id,payerNameRaw:r.payer_name??'',payerPhoneRaw:r.payer_identifier??'',amountRwf:r.amount_minor===null?null:pgInteger(r.amount_minor),atRaw:r.transaction_datetime_raw??'',ftId:r.provider_transaction_id,
 state:native?(r.payment_status==='reversed'?'reversed':r.payment_status==='corrected'?'corrected':
  r.ledger_posted===true&&['reconciled','confirmed'].includes(r.payment_status)?'posted':'recorded'):pgInteger(r.has_conflict)===1||r.source_conflict?'conflict':r.payment_status==='reversed'?'reversed':r.payment_status==='corrected'?'corrected':
  ['reconciled','confirmed'].includes(r.payment_status)&&r.ledger_posted===true?'posted':r.allocation_state==='unallocated'?'unallocated':'processing',
 version:pgInteger(r.version),memberId:r.member_id??null,memberPhone:memberPhone(r.momo_number,true),sourceId:native?(r.native_meta.canReveal?r.native_source_id:null):r.source_id??null,
 ...(native?{direction:r.event_kind==='incoming_receipt'?'incoming':r.event_kind==='outgoing'?'outgoing':r.event_kind==='reversal'?'reversal':'other',
  outcome:r.native_meta.outcome,sourceKind:'observation',feeRwf:r.fee_minor===null?null:pgInteger(r.fee_minor),
  walletBalanceAfterRwf:r.wallet_balance_after_minor===null?null:pgInteger(r.wallet_balance_after_minor)}:{})};
};
const member=r=>({id:r.id,groupId:r.collection_id,name:r.full_name,phone:memberPhone(r.momo_number),balanceRwf:pgInteger(r.balance),active:pgInteger(r.active)===1,version:pgInteger(r.revision)});
const ledger=r=>({id:r.id,groupId:r.collection_id,transactionId:r.transaction_id??null,amountRwf:pgInteger(r.amount_minor),atRaw:r.source_at??'',ftId:r.ft_id??'',payerNameRaw:r.payer_name??'',memberPhone:memberPhone(r.momo_number),
 state:r.has_conflict!==null&&r.has_conflict!==undefined&&pgInteger(r.has_conflict)===1?'conflict':r.payment_status==='reversed'?'reversed':
  r.payment_status==='corrected'?'corrected':['reconciled','confirmed'].includes(r.payment_status)?'posted':r.allocation_state==='unallocated'?'unallocated':r.payment_status?'processing':null});
const safeLike=s=>'%'+s.replaceAll('\\','\\\\').replaceAll('%','\\%').replaceAll('_','\\_')+'%';
const localPhone=phone=>typeof phone==='string'&&phone.startsWith('+250')?'0'+phone.slice(4):phone;

/** Reuses canonical app tables, never a client or SMS-derived balance.
 * sourceReader must reuse Collect's admitted decrypt/read command and validate
 * each source's group/transaction lineage inside this same snapshot. It is not
 * replaced with an independent raw-body table or a broad storage credential.
 */
export class PostgresRecordsStore {
  constructor({authority,sourceReader,clock=()=>Date.now(),nativeAutoRecordsEnabled=false}){
    requirePort(authority,['read','session']);requirePort(sourceReader,['revision','page','detail']);
    requireThat(typeof nativeAutoRecordsEnabled==='boolean','invalid_worker_config',503);
    Object.assign(this,{authority,sourceReader,clock,nativeAutoRecordsEnabled});this.groupId=authority.groupId;
  }
  withCommandSnapshot(fn){return this.withReadSnapshot(fn,{primary:true});}
  async revealSms(actor,request){
    requireThat(request?.groupId===this.groupId,'access_denied',403);
    requirePort(this.sourceReader,['revealSms']);
    return this.sourceReader.revealSms(actor,request);
  }
  async withReadSnapshot(fn,{primary=false}={}){
    return this.authority.read(async sql=>{
      if(primary){
        const check=(await sql.unsafe('SELECT pg_is_in_recovery() AS replica'))[0];
        requireThat(check?.replica===false,'command_primary_required',503);
      }
      const at=new Date(this.clock()).toISOString(),group=this.groupId,auto=this.nativeAutoRecordsEnabled,
        PAYMENTS=paymentsSql(auto),managedOnly=auto?' AND x.native_source_id IS NULL':'';
      let snapshotActor=null;
      const scope=g=>requireThat(g===group,'access_denied',403);
      const ops={
        reloadActor:async id=>{snapshotActor=await this.authority.session(sql,{id});return snapshotActor;},
        onboardingSuggestions:async query=>{
          scope(query.groupId);return listOnboardingSuggestions(sql,query);
        },
        loadBinding:async(g,installationId)=>{
          scope(g);const r=(await sql.unsafe(`SELECT b.id,b.version,b.status,c.installation_id,c.revoked_at,s.enabled,s.binding_version
            FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id AND b.receiving_account_id=s.receiving_account_id
            JOIN app.momo_gateway_credentials c ON c.binding_id=b.id
            WHERE s.collection_id=$1 AND c.installation_id=$2`,[g,installationId]))[0];
          return r?{id:r.id,groupId:g,installationId:r.installation_id,active:r.enabled&&r.status==='active'&&!r.revoked_at&&pgInteger(r.version)===pgInteger(r.binding_version)}:null;
        },
        canonicalHome:async g=>{
          scope(g);
          const totals=(await sql.unsafe('SELECT coalesce(sum(amount_minor),0) AS balance FROM app.ledger_entries WHERE collection_id=$1',[g]))[0];
          // A missing, malformed or timezone-less receipt timestamp never
          // becomes today's receipt by substituting posting or capture time.
          const today=(await sql.unsafe(`SELECT coalesce(sum(c.credited_amount),0) AS today FROM (${CREDITED}) c
            JOIN app.momo_transactions t ON t.id=c.transaction_id
            WHERE CASE WHEN t.transaction_at ~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
             AND pg_input_is_valid(t.transaction_at,'timestamp with time zone')
             AND EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name=t.transaction_timezone)
            THEN t.transaction_at::timestamptz >= (date_trunc('day',$2::timestamptz AT TIME ZONE t.transaction_timezone) AT TIME ZONE t.transaction_timezone)
             AND t.transaction_at::timestamptz < ((date_trunc('day',$2::timestamptz AT TIME ZONE t.transaction_timezone)+interval '1 day') AT TIME ZONE t.transaction_timezone)
             AND t.transaction_at::timestamptz <= $2::timestamptz ELSE false END`,[g,at]))[0];
          const counts=(await sql.unsafe(`SELECT
            (SELECT count(*) FROM app.memberships WHERE collection_id=$1 AND active=1) AS members,
            (SELECT count(*) FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id
             LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
             LEFT JOIN LATERAL (SELECT count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor AND p.amount_minor=t.amount_minor
              AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
              AND EXISTS(SELECT 1 FROM app.memberships m WHERE m.collection_id=x.collection_id AND m.user_id=p.member_id)),false) AS posted
              FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) credit ON true
             WHERE x.collection_id=$1${managedOnly} AND t.event_kind='incoming_receipt' AND t.allocation_state='unallocated' AND t.has_conflict=0 AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AND p.status IS DISTINCT FROM 'reversed' AND p.status IS DISTINCT FROM 'corrected'
              AND NOT (coalesce(p.status IN ('reconciled','confirmed'),false) AND credit.posted)) AS unallocated,
            (SELECT coalesce(sum(t.amount_minor),0) FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id
             LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
             LEFT JOIN LATERAL (SELECT count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor AND p.amount_minor=t.amount_minor
              AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
              AND EXISTS(SELECT 1 FROM app.memberships m WHERE m.collection_id=x.collection_id AND m.user_id=p.member_id)),false) AS posted
              FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) credit ON true
             WHERE x.collection_id=$1${managedOnly} AND t.event_kind='incoming_receipt' AND t.allocation_state='unallocated' AND t.has_conflict=0 AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AND p.status IS DISTINCT FROM 'reversed' AND p.status IS DISTINCT FROM 'corrected'
              AND NOT (coalesce(p.status IN ('reconciled','confirmed'),false) AND credit.posted)) AS unallocated_amount`,[g]))[0];
          // Only project ledger-verified credits; keep the lateral lookup
          // correlated before the role-checked native source projection.
          const recent=await sql.unsafe(`WITH credited AS MATERIALIZED (${CREDITED})
            SELECT q.*,c.credited_amount FROM credited c
            JOIN LATERAL (${PAYMENTS} AND t.id=c.transaction_id OFFSET 0) q ON true
            WHERE CASE WHEN q.transaction_at ~ '(Z|[+-][0-9]{2}:[0-9]{2})$' AND pg_input_is_valid(q.transaction_at,'timestamp with time zone')
              AND EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name=q.transaction_timezone)
              THEN q.transaction_at::timestamptz <= $2::timestamptz ELSE false END
            ORDER BY q.transaction_at::timestamptz DESC,q.id DESC LIMIT 3`,[g,at]);
          return {groupBalanceRwf:pgInteger(totals.balance),todayRwf:pgInteger(today.today),memberCount:pgInteger(counts.members),unallocatedCount:pgInteger(counts.unallocated),unallocatedAmountRwf:pgInteger(counts.unallocated_amount),recentPayments:recent.map(r=>payment({...r,amount_minor:r.credited_amount})),asOf:at};
        },
        listRevision:async(g,kind,memberId)=>{
          scope(g);let rows;
          if(kind==='payments')rows=await sql.unsafe(`SELECT t.id,t.version,t.has_conflict,p.revision AS payment_revision,p.status,p.member_id,
            f.beneficiary_member_id,pm.revision AS membership_revision,u.revision AS member_revision,
            (SELECT count(*) FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AS conflict_count,
            (SELECT count(*) FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) AS ledger_count${auto?',x.native_source_id,private.burimunsi_auto_projection(x.native_source_id) AS native_meta':''}
            FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
            LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
            LEFT JOIN app.memberships pm ON pm.collection_id=x.collection_id AND pm.user_id=coalesce(p.member_id,CASE WHEN p.id IS NOT NULL THEN f.beneficiary_member_id END)
            LEFT JOIN app.users u ON u.id=pm.user_id WHERE x.collection_id=$1 ORDER BY t.id LIMIT 100001`,[g]);
          else if(kind==='members')rows=await sql.unsafe('SELECT m.id,m.revision,u.revision AS person_revision,(SELECT count(*) FROM app.ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id) AS entries FROM app.memberships m JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1 ORDER BY m.id LIMIT 100001',[g]);
          else if(kind==='ledger'){requireThat(memberId,'member_required');rows=await sql.unsafe('SELECT id FROM app.ledger_entries WHERE collection_id=$1 AND member_id=$2 ORDER BY id LIMIT 100001',[g,memberId]);}
          else if(kind==='staff')rows=await sql.unsafe('SELECT id,version FROM private.burimunsi_accounts WHERE collection_id=$1 AND role=\'staff\' ORDER BY id LIMIT 100001',[g]);
          else if(kind==='audit')rows=await sql.unsafe('SELECT id FROM private.burimunsi_audit WHERE collection_id=$1 ORDER BY id LIMIT 100001',[g]);
          else return this.sourceReader.revision(sql,g,snapshotActor);
          requireThat(rows.length<=100000,'snapshot_limit',413);return sha256(canonicalJson(Array.from(rows)));
        },
        readListingSnapshot:async({groupId:g,kind,memberId})=>{
          scope(g);let rows,entries;
          if(kind==='payments'){
            const args=[g];let extra='';
            if(memberId!==null){await this.memberExists(sql,g,memberId);args.push(memberId);extra=' AND u.id=$2';}
            rows=await sql.unsafe(PAYMENTS+extra+' ORDER BY t.id LIMIT 100001',args);
            entries=rows.map(r=>{
              const item=payment(r),conflict=pgInteger(r.has_conflict)===1||r.source_conflict===true;
              if(item.sourceKind!=='observation'){
                item.direction=(r.canonical_event_kind??r.event_kind)==='reversal'?'reversal':'incoming';
                item.outcome='successful';
              }
              const credited=['reconciled','confirmed'].includes(r.payment_status)&&r.ledger_posted===true;
              const normal=!conflict&&!['reversed','corrected'].includes(r.payment_status);
              const filters=['unallocated','processing'].includes(item.state)?[]:[item.state];
              if(normal&&credited)filters.push('allocated');
              if(normal&&!credited&&r.native_source_id==null&&(r.canonical_event_kind??r.event_kind)==='incoming_receipt')filters.push(r.allocation_state==='unallocated'?'unallocated':'processing');
              return {item,at:canonicalListingInstant(r.transaction_at),amount:item.amountRwf,
                direction:item.direction??(r.event_kind==='reversal'?'reversal':'incoming'),outcome:item.outcome??'successful',filters,
                search:listingText([item.id,item.payerNameRaw,item.payerPhoneRaw,item.ftId,item.amountRwf,item.atRaw,r.member_full_name,r.momo_number,item.memberPhone,localPhone(item.memberPhone)].join(' '))};
            });
          }else if(kind==='members'){
            rows=await sql.unsafe(MEMBERS+' ORDER BY u.id LIMIT 100001',[g]);
            entries=rows.map(r=>{const item=member(r);return {item,at:canonicalListingInstant(r.joined_at),amount:item.balanceRwf,name:listingText(item.name),phone:item.phone,
              search:listingText([item.id,item.name,item.phone,localPhone(item.phone),r.momo_number,item.balanceRwf].join(' '))};});
          }else if(kind==='ledger'){
            requireThat(memberId,'member_required');await this.memberExists(sql,g,memberId);
            rows=await sql.unsafe(LEDGER+' ORDER BY l.id LIMIT 100001',[g,memberId]);
            entries=rows.map(r=>{const item=ledger(r);return {item,at:canonicalListingInstant(r.posted_at),amount:item.amountRwf,
              search:listingText([item.id,item.ftId,item.payerNameRaw,item.memberPhone,item.amountRwf,item.atRaw,r.posted_at].join(' '))};});
          }else if(kind==='staff'){
            rows=await sql.unsafe("SELECT id,collection_id,name,phone,active,version,capabilities,created_at FROM private.burimunsi_accounts WHERE collection_id=$1 AND role='staff' AND NOT removed ORDER BY id LIMIT 100001",[g]);
            entries=rows.map(r=>{const item={id:r.id,groupId:r.collection_id,name:r.name,phone:r.phone,active:r.active,version:pgInteger(r.version),capabilities:r.capabilities};
              return {item,at:new Date(pgInteger(r.created_at)).toISOString(),name:listingText(item.name),phone:item.phone,search:listingText([item.id,item.name,item.phone,localPhone(item.phone)].join(' '))};});
          }else if(kind==='audit'){
            rows=await sql.unsafe('SELECT id,collection_id,action,at_ms FROM private.burimunsi_audit WHERE collection_id=$1 ORDER BY id LIMIT 100001',[g]);
            entries=rows.map(r=>{const item={id:r.id,groupId:r.collection_id,action:r.action,at:new Date(pgInteger(r.at_ms)).toISOString()};return {item,at:item.at,action:listingText(item.action),search:listingText([item.id,item.action,item.at].join(' '))};});
          }else{
            requireThat(kind==='sms','invalid_list');requirePort(this.sourceReader,['listingSnapshot']);
            return this.sourceReader.listingSnapshot(sql,g,snapshotActor);
          }
          requireThat(rows.length<=100000,'snapshot_limit',413);
          return {entries,asOf:at};
        },
        readPage:async query=>{
          const {groupId:g,kind,memberId,q,filter,limit,after}=query;scope(g);
          // Cursor contains only an integer offset authenticated against the full revision.
          const offset=after?.offset??0;requireThat(Number.isSafeInteger(offset)&&offset>=0&&offset<=100000,'invalid_cursor');
          let rows,total,read;
          if(kind==='payments'){
            const fields=['t.payer_name','t.payer_identifier','t.provider_transaction_id','t.amount_minor::text',
              't.transaction_datetime_raw','u.full_name','u.momo_number','member_phone.normalized'];
            let where=PAYMENTS+' AND ('+fields.map(field=>`coalesce(${field},'')`+" ILIKE $2 ESCAPE '\\'").join(' OR ')+')';
            const args=[g,safeLike(q)];
            if(memberId!==null){await this.memberExists(sql,g,memberId);args.push(memberId);where+=' AND u.id=$'+args.length;}
            if(filter==='unallocated')where+=managedOnly+" AND t.event_kind='incoming_receipt' AND t.allocation_state='unallocated' AND t.has_conflict=0 AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AND p.status IS DISTINCT FROM 'reversed' AND p.status IS DISTINCT FROM 'corrected' AND NOT (coalesce(p.status IN ('reconciled','confirmed'),false) AND credit.posted)";
            if(filter==='allocated')where+=" AND t.has_conflict=0 AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AND p.status IN ('reconciled','confirmed') AND credit.posted";
            if(filter==='processing')where+=managedOnly+" AND t.allocation_state<>'unallocated' AND t.has_conflict=0 AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AND p.status IS DISTINCT FROM 'reversed' AND p.status IS DISTINCT FROM 'corrected' AND NOT (coalesce(p.status IN ('reconciled','confirmed'),false) AND credit.posted)";
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM ('+where+') AS scoped',args))[0].total);
            rows=await sql.unsafe(where+' ORDER BY t.transaction_at DESC NULLS LAST,t.id DESC LIMIT $'+(args.length+1)+' OFFSET $'+(args.length+2),[...args,limit,offset]);read=payment;
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
          }else return this.sourceReader.page(sql,query,snapshotActor);
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
        readRecoveryOutcome:async query=>{scope(query.groupId);return readRecoveryProof(sql,query);},
        readCommandOutcome:async query=>{
          scope(query.groupId);return readCommandOutcome(sql,query);
        }
      };
      return fn(ops);
    });
  }
  async memberExists(sql,group,id){requireThat((await sql.unsafe('SELECT id FROM app.memberships WHERE collection_id=$1 AND user_id=$2',[group,id])).length===1,'member_unavailable',404);}
}
