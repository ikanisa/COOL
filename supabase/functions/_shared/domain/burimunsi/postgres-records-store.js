import {readRecoveryProof} from './postgres-operation-recovery.js';
import {readCommandOutcome} from './postgres-command-outcome.js';
import {requireThat,requirePort} from './errors.js';
import {pgInteger} from './postgres-values.js';
import {sha256,canonicalJson} from './values.js';
import {listOnboardingSuggestions} from './smart-onboarding-suggestions.js';
import {canonicalListingInstant,listingText} from './listing-query.js';
import {readMemberListing} from './postgres-member-listing.js';
import {paymentAllocationFilterSql,paymentReferenceSql,paymentsSql,readCanonicalHome} from './postgres-payment-reads.js';
import {projectLedger,projectMember,projectPayment} from './postgres-record-projections.js';

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
        PAYMENTS=paymentsSql(auto);
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
          scope(g);return readCanonicalHome(sql,g,at,auto);
        },
        memberListingRevision:async g=>{
          scope(g);
          const [row]=await sql.unsafe('SELECT revision FROM private.member_history_versions WHERE collection_id=$1',[g]);
          requireThat(row,'snapshot_unavailable',503);
          return `members.v2:${pgInteger(row.revision)}`;
        },
        readMemberPage:async query=>{
          scope(query.groupId);
          const {rows,totalCount,after}=await readMemberListing(sql,query);
          return {items:rows.map(projectMember),totalCount,after,asOf:at};
        },
        listRevision:async(g,kind,memberId,paymentReference=null)=>{
          scope(g);let rows;
          if(kind==='payments')rows=await sql.unsafe(`SELECT t.id,t.version,t.has_conflict,p.revision AS payment_revision,p.status,p.member_id,
            f.beneficiary_member_id,pm.revision AS membership_revision,u.revision AS member_revision,${paymentReference?`(${paymentReferenceSql}=$2) AS reference_match,`:''}
            (SELECT count(*) FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AS conflict_count,
            (SELECT count(*) FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) AS ledger_count${auto?',x.native_source_id,private.burimunsi_auto_projection(x.native_source_id) AS native_meta':''}
            FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
            LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
            LEFT JOIN app.memberships pm ON pm.collection_id=x.collection_id AND pm.user_id=coalesce(p.member_id,CASE WHEN p.id IS NOT NULL THEN f.beneficiary_member_id END)
            LEFT JOIN app.users u ON u.id=pm.user_id WHERE x.collection_id=$1 ORDER BY t.id LIMIT 100001`,paymentReference?[g,paymentReference]:[g]);
          else if(kind==='ledger'){requireThat(memberId,'member_required');rows=await sql.unsafe('SELECT id FROM app.ledger_entries WHERE collection_id=$1 AND member_id=$2 ORDER BY id LIMIT 100001',[g,memberId]);}
          else if(kind==='staff')rows=await sql.unsafe('SELECT id,version FROM private.burimunsi_accounts WHERE collection_id=$1 AND role=\'staff\' ORDER BY id LIMIT 100001',[g]);
          else if(kind==='audit')rows=await sql.unsafe('SELECT id FROM private.burimunsi_audit WHERE collection_id=$1 ORDER BY id LIMIT 100001',[g]);
          else return this.sourceReader.revision(sql,g,snapshotActor);
          requireThat(rows.length<=100000,'snapshot_limit',413);return sha256(canonicalJson(Array.from(rows)));
        },
        readListingSnapshot:async({groupId:g,kind,memberId,paymentReference=null})=>{
          scope(g);let rows,entries;
          if(kind==='payments'){
            const args=[g];let extra='';
            if(memberId!==null){await this.memberExists(sql,g,memberId);args.push(memberId);extra=' AND u.id=$2';}
            rows=await sql.unsafe((paymentReference?paymentsSql(auto,true):PAYMENTS)+extra+' ORDER BY t.id LIMIT 100001',args);
            entries=rows.map(r=>{
              const item=projectPayment(r),conflict=pgInteger(r.has_conflict)===1||r.source_conflict===true;
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
                search:listingText([item.id,item.payerNameRaw,item.payerPhoneRaw,item.ftId,item.amountRwf,item.atRaw,r.member_full_name,r.momo_number,item.memberPhone,localPhone(item.memberPhone),
                  ...(paymentReference&&r.display_reference===paymentReference?[paymentReference]:[])].join(' '))};
            });
          }else if(kind==='ledger'){
            requireThat(memberId,'member_required');await this.memberExists(sql,g,memberId);
            rows=await sql.unsafe(LEDGER+' ORDER BY l.id LIMIT 100001',[g,memberId]);
            entries=rows.map(r=>{const item=projectLedger(r);return {item,at:canonicalListingInstant(r.posted_at),amount:item.amountRwf,
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
            const args=[g,safeLike(q)];
            const matches=fields.map(field=>`coalesce(${field},'')`+" ILIKE $2 ESCAPE '\\'");
            if(query.paymentReference)matches.push(`(${paymentReferenceSql})=$${args.push(query.paymentReference)}`);
            let where=PAYMENTS+' AND ('+matches.join(' OR ')+')';
            if(memberId!==null){await this.memberExists(sql,g,memberId);args.push(memberId);where+=' AND u.id=$'+args.length;}
            where+=paymentAllocationFilterSql(auto,filter);
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM ('+where+') AS scoped',args))[0].total);
            rows=await sql.unsafe(where+' ORDER BY t.transaction_at DESC NULLS LAST,t.id DESC LIMIT $'+(args.length+1)+' OFFSET $'+(args.length+2),[...args,limit,offset]);read=projectPayment;
          }else if(kind==='ledger'){
            requireThat(memberId,'member_required');await this.memberExists(sql,g,memberId);
            total=pgInteger((await sql.unsafe('SELECT count(*) AS total FROM app.ledger_entries WHERE collection_id=$1 AND member_id=$2',[g,memberId]))[0].total);
            rows=await sql.unsafe(LEDGER+' ORDER BY l.posted_at DESC,l.id DESC LIMIT $3 OFFSET $4',[g,memberId,limit,offset]);read=projectLedger;
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
        readDetail:async({groupId:g,kind,id,includePaymentReference=false})=>{
          scope(g);if(kind==='sms')return this.sourceReader.detail(sql,g,id);
          const readPayment=kind==='payment';
          const query=readPayment?(includePaymentReference?paymentsSql(auto,true):PAYMENTS):MEMBERS;
          const [row]=await sql.unsafe(query+(readPayment?' AND t.id=$2':' AND u.id=$2'),[g,id]);
          if(!row)return null;
          if(!readPayment)return projectMember(row);
          const record=projectPayment(row);
          return includePaymentReference?{...record,paymentReference:row.display_reference??null}:record;
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
          scope(g);await this.memberExists(sql,g,memberId);return (await sql.unsafe(LEDGER+' ORDER BY l.posted_at,l.id LIMIT $3',[g,memberId,max])).map(projectLedger);
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
