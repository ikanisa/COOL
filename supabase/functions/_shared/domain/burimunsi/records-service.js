import {COMMAND_OPERATIONS} from './postgres-command-outcome.js';
import {requirePort,requireThat} from './errors.js';
import {authorize} from './policy.js';
import {requireId,requireRequestId,canonicalJson,sha256,normalizePhone} from './values.js';
import {ledgerCsv} from './csv.js';
import {projectRecoveredOutcome,requireOriginDigest} from './operation-recovery.js';
import {projectPaymentHistory,HISTORY_LIMIT} from './payment-history.js';
/** Readers must use the existing ledger snapshot, not SUM(received SMS).
 * Session, membership scope, total and page use the same read snapshot.
 */
export class RecordsService {
  constructor({store,groupId,cursor,clock=()=>Date.now()}) {
    requirePort(store,['withReadSnapshot']);requirePort(cursor,['create','read']);
    Object.assign(this,{store,groupId,cursor,clock});
  }
  async within(actor,capability,fn,command=false) {
    const method=command?'withCommandSnapshot':'withReadSnapshot';
    requirePort(this.store,[method]);
    return this.store[method](async tx=>{
      requirePort(tx,['reloadActor','loadBinding']);
      const current=await tx.reloadActor(actor.sessionId);
      authorize(current,this.groupId,capability,{now:this.clock(),binding:await tx.loadBinding(this.groupId)});
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
      return {groupBalanceRwf:value.groupBalanceRwf,todayRwf:value.todayRwf,memberCount:value.memberCount,unallocatedCount:value.unallocatedCount,asOf:value.asOf,recentPayments:this.projectRows(value.recentPayments??[],'payments')};
    });
  }
  async page(actor,kind,query={}) {
    requireThat(['payments','members','ledger','sms','staff','audit'].includes(kind),'invalid_list');
    const capability=kind==='sms'?'sms.read':['staff','audit'].includes(kind)?'staff.manage':'records.read';
    const q=query.q??'',filter=query.filter??'all',limit=query.limit??40,memberId=query.memberId??null;
    requireThat(typeof q==='string'&&q.length<=80&&Number.isInteger(limit)&&limit>=1&&limit<=100,'invalid_query');
    requireThat((kind==='sms'?['all','queued','duplicate','synced','rejected']:['all','unallocated','allocated']).includes(filter),'invalid_filter');
    if(memberId!==null)requireId(memberId);
    const filterHash=await sha256(canonicalJson({q,filter,memberId,kind}));
    return this.within(actor,capability,async(tx,current)=>{
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
      requirePort(tx,['readDetail']);const row=await tx.readDetail({groupId:this.groupId,kind,id});
      requireThat(row && row.groupId===this.groupId,'record_unavailable',404);
      return this.projectRows([row],kind==='member'?'members':kind==='sms'?'rawSms':'payments')[0];
    });
  }
  async paymentHistory(actor,transactionId,query={}) {
    requireId(transactionId);
    requireThat(query&&Object.keys(query).every(k=>['limit','cursor'].includes(k)),'invalid_query');
    const limit=query.limit??40;
    requireThat(Number.isInteger(limit)&&limit>=1&&limit<=100,'invalid_query');
    requireThat(query.cursor===undefined||(typeof query.cursor==='string'&&query.cursor.length>0),'invalid_cursor');
    return this.within(actor,'records.read',async(tx,current)=>{
      requirePort(tx,['readDetail','readPaymentHistory']);
      const payment=await tx.readDetail({groupId:this.groupId,kind:'payment',id:transactionId});
      requireThat(payment&&payment.groupId===this.groupId&&payment.id===transactionId,'record_unavailable',404);
      requireThat(Number.isSafeInteger(payment.version)&&payment.version>=0&&typeof payment.state==='string','invalid_snapshot',503);
      const events=projectPaymentHistory(await tx.readPaymentHistory(this.groupId,transactionId,HISTORY_LIMIT+1),this.groupId,transactionId);
      const revision=await sha256(canonicalJson({version:payment.version,state:payment.state,events}));
      const scope={groupId:this.groupId,actorId:current.id,snapshot:revision,
        filterHash:await sha256(canonicalJson({kind:'payment_history',transactionId,limit})),sort:'oldest'};
      const after=query.cursor?await this.cursor.read(query.cursor,scope,this.clock()):null;
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
      payments:['id','groupId','payerNameRaw','payerPhoneRaw','amountRwf','atRaw','ftId','state','version','memberId','memberPhone','sourceId'],
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
      if(['payments','ledger'].includes(kind))requireThat(Number.isSafeInteger(row.amountRwf)&&row.amountRwf!==0&&typeof row.ftId==='string'&&row.ftId.length>0&&typeof row.atRaw==='string'&&typeof row.payerNameRaw==='string','invalid_transaction_projection',503);
      if(kind==='members')requireThat(normalizePhone(row.phone)===row.phone&&Number.isSafeInteger(row.balanceRwf),'invalid_member_projection',503);
      // Staff/ordinary readers may never carry retained raw body or secret credential material.
      if(!['sms','rawSms'].includes(kind))requireThat(!['rawBody','raw_body','pinHash','tokenHash','gateway_token'].some(k=>Object.hasOwn(row,k)),'sensitive_projection_violation',503);
    }
  }
}
