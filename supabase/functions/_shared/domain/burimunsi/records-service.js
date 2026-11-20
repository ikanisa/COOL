import {COMMAND_OPERATIONS} from './postgres-command-outcome.js';
import {requirePort,requireThat} from './errors.js';
import {authorize} from './policy.js';
import {requireId,requireRequestId,canonicalJson,sha256,normalizePhone} from './values.js';
import {ledgerCsv} from './csv.js';
import {projectRecoveredOutcome,requireOriginDigest} from './operation-recovery.js';
import {projectPaymentHistory,HISTORY_LIMIT} from './payment-history.js';
import {previewSmartOnboardingImport} from './smart-onboarding-import.js';
import {normalizeListingQuery,selectListing,canonicalListingInstant,listingText,listingFilterIdentity} from './listing-query.js';
/** Readers must use the existing ledger snapshot, not SUM(received SMS).
 * Session, membership scope, total and page use the same read snapshot.
 */
export class RecordsService {
  constructor({store,groupId,cursor,clock=()=>Date.now(),smartOnboardingImport=null}) {
    requirePort(store,['withReadSnapshot']);requirePort(cursor,['create','read']);
    if(smartOnboardingImport!==null)requirePort(smartOnboardingImport,['preview']);
    Object.assign(this,{store,groupId,cursor,clock,smartOnboardingImport});
  }
  async within(actor,capability,fn,command=false) {
    const method=command?'withCommandSnapshot':'withReadSnapshot';
    requirePort(this.store,[method]);
    return this.store[method](async tx=>{
      requirePort(tx,['reloadActor','loadBinding']);
      const current=await tx.reloadActor(actor.sessionId);
      authorize(current,this.groupId,capability,{now:this.clock(),binding:await tx.loadBinding(this.groupId,current?.installationId)});
      requireThat(current.id===actor.id&&current.sessionId===actor.sessionId,'session_unavailable',401);
      return fn(tx,current);
    });
  }
  async recoverCommandStatus(actor,requestId,originDigest) {
    requestId=requireRequestId(requestId);originDigest=requireOriginDigest(originDigest);
    return this.within(actor,'records.read',async(tx,current)=>{
      requirePort(tx,['readRecoveryOutcome']);
      const proof=await tx.readRecoveryOutcome({groupId:this.groupId,actorId:current.id,
        currentSessionId:current.sessionId,requestId,originDigest});
      return projectRecoveredOutcome({proof,actor:current,groupId:this.groupId,requestId,originDigest,now:this.clock()});
    },true);
  }
  async commandStatus(actor,requestId) {
    requestId=requireRequestId(requestId);
    return this.within(actor,'records.read',async(tx,current)=>{
      requirePort(tx,['readCommandOutcome']);
      const value=await tx.readCommandOutcome({groupId:this.groupId,actorId:current.id,requestId,principalUserId:current.principalUserId});
      const envelope={contractVersion:2,requestId,groupId:this.groupId,actorId:current.id};
      if(!value)return {...envelope,state:'pending',financialState:'unresolved'};
      // The existing receipt store records commits only. Do not manufacture a
      // durable rejection from a missing row, HTTP failure or in-memory error.
      requireThat(value.groupId===this.groupId&&value.actorId===current.id&&value.requestId===requestId&&
        value.state==='committed'&&COMMAND_OPERATIONS.includes(value.operation)&&
        ['posted','reversed','corrected','not_applicable'].includes(value.financialState)&&
        (value.operation==='burimunsi.allocate')===(value.financialState!=='not_applicable'),
        'command_scope_violation',503);
      return {...envelope,state:'committed',operation:value.operation,financialState:value.financialState};
    },true);
  }

  async home(actor) {
    return this.within(actor,'records.read',async tx=>{
      requirePort(tx,['canonicalHome']);
      const value=await tx.canonicalHome(this.groupId);
      requireThat(value && Number.isSafeInteger(value.groupBalanceRwf)&&Number.isSafeInteger(value.todayRwf)&&Number.isSafeInteger(value.memberCount)&&Number.isSafeInteger(value.unallocatedCount)&&typeof value.asOf==='string','invalid_snapshot',503);
      if(value.unallocatedAmountRwf!==undefined)requireThat(Number.isSafeInteger(value.unallocatedAmountRwf),'invalid_snapshot',503);
      return {groupBalanceRwf:value.groupBalanceRwf,todayRwf:value.todayRwf,memberCount:value.memberCount,unallocatedCount:value.unallocatedCount,
        ...(value.unallocatedAmountRwf===undefined?{}:{unallocatedAmountRwf:value.unallocatedAmountRwf}),asOf:value.asOf,recentPayments:this.projectRows(value.recentPayments??[],'payments')};
    });
  }
  async onboardingSuggestions(actor,query={}) {
    const q=query.q??'',limit=query.limit??40;
    requireThat(typeof q==='string'&&q.length<=80&&Number.isSafeInteger(limit)&&limit>=1&&limit<=100,'invalid_query');
    return this.within(actor,'members.enroll',async(tx,current)=>{
      requirePort(tx,['listRevision','onboardingSuggestions']);
      const revision=await sha256(canonicalJson({payments:await tx.listRevision(this.groupId,'payments',null),
        members:await tx.listRevision(this.groupId,'members',null)}));
      const scope={groupId:this.groupId,actorId:current.id,snapshot:revision,
        filterHash:await sha256(canonicalJson({kind:'onboarding_suggestions',q,limit})),sort:'newest'};
      const after=query.cursor?await this.cursor.read(query.cursor,scope,this.clock()):null;
      const result=await tx.onboardingSuggestions({groupId:this.groupId,q,limit,after});
      requireThat(result&&Array.isArray(result.items)&&result.items.length<=limit&&Number.isSafeInteger(result.totalCount),
        'invalid_page',503);
      const items=result.items.map(value=>({...value,id:value.candidateId,groupId:this.groupId}));
      const nextCursor=result.after?await this.cursor.create({...scope,after:result.after,expiresAt:this.clock()+15*60*1000}):null;
      return {items,totalCount:result.totalCount,nextCursor,revision,asOf:new Date(this.clock()).toISOString()};
    });
  }
  async onboardingPreview(actor,{bytes,mimeType,externalOcrConsent}) {
    // The default has no external dependencies and remains CSV-only.
    if(!this.smartOnboardingImport)return this.within(actor,'members.enroll',async()=>
      previewSmartOnboardingImport({bytes,mimeType,ocr:{consent:externalOcrConsent}}));
    // Close the database snapshot before any decoder or provider I/O. The
    // importer rechecks current authority at each durable dispatch boundary.
    const authorize=()=>this.within(actor,'members.enroll',async(_tx,current)=>current);
    await authorize();
    return this.smartOnboardingImport.preview({actor,groupId:this.groupId,bytes,mimeType,
      externalOcrConsent,authorize});
  }
  async page(actor,kind,query={}) {
    requireThat(['payments','members','ledger','sms','staff','audit'].includes(kind),'invalid_list');
    const capability=kind==='sms'?'sms.read':['staff','audit'].includes(kind)?'staff.manage':'records.read';
    const listing=normalizeListingQuery(kind,query),{q,filter,limit}=listing,memberId=query.memberId??null;
    if(memberId!==null)requireId(memberId);
    const filterHash=await sha256(canonicalJson(listing.advanced?{...listingFilterIdentity(listing),memberId,kind}:{q,filter,memberId,kind}));
    return this.within(actor,capability,async(tx,current)=>{
      if(listing.advanced){
        requirePort(tx,['readListingSnapshot']);
        const full=await tx.readListingSnapshot({groupId:this.groupId,kind,memberId});
        requireThat(full&&Array.isArray(full.entries)&&full.entries.length<=100000&&typeof full.asOf==='string','invalid_snapshot',503);
        this.checkRows(full.entries.map(entry=>entry.item),kind);
        // Bind every projected/sort/search value, so a renamed member or
        // changed financial projection cannot be mixed into an earlier page.
        const revision=await sha256(canonicalJson(full.entries));
        const scope={groupId:this.groupId,actorId:current.id,snapshot:revision,filterHash,sort:listing.sort};
        const after=query.cursor?await this.cursor.read(query.cursor,scope,this.clock()):null;
        const result=selectListing(full.entries,kind,listing,after,full.asOf);
        const items=this.projectRows(result.items,kind);
        const nextCursor=result.after?await this.cursor.create({...scope,after:result.after,expiresAt:this.clock()+15*60*1000}):null;
        return {items,totalCount:result.totalCount,nextCursor,revision,asOf:result.asOf};
      }
      requirePort(tx,['listRevision','readPage']);
      const revision=await tx.listRevision(this.groupId,kind,memberId);
      requireThat(typeof revision==='string'&&revision.length>0,'snapshot_unavailable',503);
      const scope={groupId:this.groupId,actorId:current.id,snapshot:revision,filterHash,sort:'newest'};
      const after=query.cursor?await this.cursor.read(query.cursor,scope,this.clock()):null;
      const result=await tx.readPage({groupId:this.groupId,kind,memberId,q,filter,limit,after});
      requireThat(result && Array.isArray(result.items)&&result.items.length<=limit&&Number.isSafeInteger(result.totalCount)&&result.totalCount>=0,'invalid_page',503);
      const items=this.projectRows(result.items,kind);
      if(kind==='sms'&&filter!=='all')requireThat(items.every(row=>row.state===filter),'receipt_filter_contract_violation',503);
      const nextCursor=result.after?await this.cursor.create({...scope,after:result.after,expiresAt:this.clock()+15*60*1000}):null;
      return {items,totalCount:result.totalCount,nextCursor,revision,asOf:result.asOf};
    });
  }
  async detail(actor,kind,id) {
    requireId(id);requireThat(['payment','member','sms'].includes(kind),'invalid_record');
    return this.within(actor,kind==='sms'?'sms.read':'records.read',async tx=>{
      // Original content is an explicit audited disclosure, never an ordinary
      // read, background refresh or cache-backed GET.
      requireThat(kind!=='sms','review_reason_required',400);
      requirePort(tx,['readDetail']);const row=await tx.readDetail({groupId:this.groupId,kind,id});
      requireThat(row && row.groupId===this.groupId,'record_unavailable',404);
      return this.projectRows([row],kind==='member'?'members':kind==='sms'?'rawSms':'payments')[0];
    });
  }
  async revealSms(actor,id,input){
    requireId(id);requireRequestId(actor?.id);requireRequestId(actor?.sessionId);
    requireThat(actor?.groupId===this.groupId,'access_denied',403);
    const reason=typeof input?.reason==='string'?input.reason.trim():'';
    requireThat([...reason].length>=8&&[...reason].length<=1000&&!/[\u0000-\u001f\u007f-\u009f]/.test(reason),
      'review_reason_required',400);
    const requestId=requireRequestId(input?.requestId);
    // The closed source adapter owns both short authority phases around IO;
    // do not nest a READ ONLY transaction around its guarded audit mutation.
    requirePort(this.store,['revealSms']);
    const row=await this.store.revealSms({id:actor.id,sessionId:actor.sessionId},
      {groupId:this.groupId,id,reason,requestId});
    requireThat(row?.id===id&&row.groupId===this.groupId,'reader_scope_violation',503);
    return this.projectRows([row],'rawSms')[0];
  }
  async paymentHistory(actor,transactionId,query={}) {
    requireId(transactionId);
    const listing=normalizeListingQuery('history',query),limit=listing.limit;
    requireThat(query.cursor===undefined||(typeof query.cursor==='string'&&query.cursor.length>0),'invalid_cursor');
    return this.within(actor,'records.read',async(tx,current)=>{
      requirePort(tx,['readDetail','readPaymentHistory']);
      const payment=await tx.readDetail({groupId:this.groupId,kind:'payment',id:transactionId});
      requireThat(payment&&payment.groupId===this.groupId&&payment.id===transactionId,'record_unavailable',404);
      requireThat(Number.isSafeInteger(payment.version)&&payment.version>=0&&typeof payment.state==='string','invalid_snapshot',503);
      const events=projectPaymentHistory(await tx.readPaymentHistory(this.groupId,transactionId,HISTORY_LIMIT+1),this.groupId,transactionId);
      const revision=await sha256(canonicalJson({version:payment.version,state:payment.state,events}));
      const scope={groupId:this.groupId,actorId:current.id,snapshot:revision,
        filterHash:await sha256(canonicalJson(listing.advanced?{kind:'payment_history',transactionId,...listingFilterIdentity(listing)}:{kind:'payment_history',transactionId,limit})),sort:listing.sort};
      const after=query.cursor?await this.cursor.read(query.cursor,scope,this.clock()):null;
      if(listing.advanced){
        const entries=events.map(item=>({item,at:canonicalListingInstant(item.recordedAt),amount:item.amountRwf,
          search:listingText([item.id,item.kind,item.recordedAt,item.amountRwf,item.memberId].join(' '))}));
        const selected=selectListing(entries,'history',listing,after,new Date(this.clock()).toISOString());
        const nextCursor=selected.after?await this.cursor.create({...scope,after:selected.after,expiresAt:this.clock()+15*60*1000}):null;
        return {items:selected.items,totalCount:selected.totalCount,nextCursor,revision,asOf:selected.asOf};
      }
      const offset=after?.offset??0;
      requireThat(Number.isSafeInteger(offset)&&offset>=0&&(offset===0||offset<events.length),'invalid_cursor');
      const items=events.slice(offset,offset+limit),next=offset+items.length;
      const nextCursor=next<events.length?await this.cursor.create({...scope,after:{offset:next},expiresAt:this.clock()+15*60*1000}):null;
      return {items,totalCount:events.length,nextCursor,revision,asOf:new Date(this.clock()).toISOString()};
    });
  }
  async exportLedger(actor,memberId) {
    requireId(memberId);
    return this.within(actor,'records.read',async tx=>{
      requirePort(tx,['readAllLedger']);
      // Adapter provides one transaction-consistent authorized ledger, bounded before materializing.
      const rows=await tx.readAllLedger(this.groupId,memberId,100001);
      requireThat(Array.isArray(rows)&&rows.length<=100000,'export_filter_required',413);
      return ledgerCsv(this.projectRows(rows,'ledger'));
    });
  }
  projectRows(rows,kind) {
    this.checkRows(rows,kind);
    const fields={
      payments:['id','groupId','payerNameRaw','payerPhoneRaw','amountRwf','atRaw','ftId','state','version','memberId','memberPhone','sourceId',
        'direction','outcome','sourceKind','feeRwf','walletBalanceAfterRwf'],
      members:['id','groupId','name','phone','balanceRwf','active','version'],
      ledger:['id','groupId','transactionId','amountRwf','atRaw','ftId','payerNameRaw','memberPhone'],
      sms:['id','groupId','sender','at','preview','state','transactionId'],
      rawSms:['id','groupId','sender','at','rawBody','transactionId'],
      staff:['id','groupId','name','phone','active','version','capabilities'],
      audit:['id','groupId','action','at'],
    }[kind];
    requireThat(fields,'invalid_projection',503);
    return rows.map(row=>Object.fromEntries(fields.filter(k=>Object.hasOwn(row,k)).map(k=>[k,row[k]])));
  }
  checkRows(rows,kind) {
    requireThat(Array.isArray(rows),'invalid_snapshot',503);
    for(const row of rows){
      requireThat(row && row.groupId===this.groupId,'reader_scope_violation',503);
      if(['payments','ledger'].includes(kind)){
        const native=kind==='payments'&&row.sourceKind==='observation';
        const amount=native&&row.amountRwf===null||Number.isSafeInteger(row.amountRwf)&&row.amountRwf!==0;
        const reference=native&&row.ftId===null||typeof row.ftId==='string'&&row.ftId.length>0;
        requireThat(amount&&reference&&typeof row.atRaw==='string'&&typeof row.payerNameRaw==='string','invalid_transaction_projection',503);
        if(native){
          // The canonical adapter owns financial state and adjustment history.
          // Reversed/corrected receipts remain readable without presenting a
          // new credit. Unposted observations carry no member identity.
          const recorded=row.state==='recorded'&&row.memberId==null&&row.memberPhone==null;
          const linked=['posted','reversed','corrected'].includes(row.state)&&row.direction==='incoming'&&row.outcome==='successful'&&
            Number.isSafeInteger(row.amountRwf)&&row.amountRwf>0&&typeof row.memberId==='string'&&
            /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(row.memberId)&&
            (row.memberPhone===null||typeof row.memberPhone==='string'&&/^\+2507[2389][0-9]{7}$/.test(row.memberPhone));
          requireThat(['incoming','outgoing','reversal','other'].includes(row.direction)&&
            ['successful','failed','pending','unknown'].includes(row.outcome)&&(recorded||linked)&&
            [row.feeRwf,row.walletBalanceAfterRwf].every(v=>v===null||Number.isSafeInteger(v)&&v>=0),
            'invalid_transaction_projection',503);
        }
      }
      if(kind==='members')requireThat(normalizePhone(row.phone)===row.phone&&Number.isSafeInteger(row.balanceRwf),'invalid_member_projection',503);
      // Staff/ordinary readers may never carry retained raw body or secret credential material.
      if(!['sms','rawSms'].includes(kind))requireThat(!['rawBody','raw_body','pinHash','tokenHash','gateway_token'].some(k=>Object.hasOwn(row,k)),'sensitive_projection_violation',503);
    }
  }
}
