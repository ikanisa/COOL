/** BuriMunsi onboarding domain — independent of Collect's existing table names. */
export class InputError extends Error { constructor(message, code='INVALID_INPUT') { super(message); this.code=code; this.status=400; } }
export const normalizeName = value => String(value ?? '').normalize('NFKC').trim().replace(/\s+/g,' ');
export const searchKey = value => normalizeName(value).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('en');
export function normalizeRwPhone(raw) {
  const s=String(raw??'').replace(/[\s.()\-]/g,'');
  const n=s.startsWith('+250') ? '0'+s.slice(4) : s.startsWith('250') ? '0'+s.slice(3) : s;
  if (!/^07[2389]\d{7}$/.test(n)) throw new InputError('Enter a valid Rwandan mobile number','INVALID_PHONE');
  return n;
}
export const suffix = phone => normalizeRwPhone(phone).slice(-3);
export function suggestionFromEvidence(e) {
  // Only canonical, bank-scope verified received events; no inference from amount, sender or name.
  if (e.scopeVerified !== true || e.kind !== 'MOMO_PAYER' || e.classification !== 'SUPPORTED' || !e.payerName || !e.payerKey) return null;
  const n=normalizeName(e.payerName);
  if (n.length<2 || n.length>150 || !/^\d{3}$/.test(e.last3??'')) return null;
  return { candidateId:e.payerKey, momoName:n, last3:e.last3, latestSeenAt:e.receivedAt, sourceCount:1, status:'suggestion' };
}
export function aggregateSuggestions(events, members, {search='', limit=50}={}) {
  if (!Number.isInteger(limit)||limit<1||limit>100) throw new InputError('Invalid page size');
  const registeredKeys=new Set(members.map(m=>m.payerKey).filter(Boolean));
  const candidates=new Map();
  for (const event of events) {
    const c=suggestionFromEvidence(event);
    if (!c || registeredKeys.has(c.candidateId)) continue;
    const old=candidates.get(c.candidateId);
    if(!old) candidates.set(c.candidateId,c);
    else { old.sourceCount++; if(String(c.latestSeenAt)>String(old.latestSeenAt)){old.latestSeenAt=c.latestSeenAt;old.momoName=c.momoName;old.last3=c.last3;} }
  }
  const q=searchKey(search);
  const filtered=[...candidates.values()].filter(c => !q || searchKey(c.momoName).includes(q)||c.last3.includes(q));
  filtered.sort((a,b)=> String(b.latestSeenAt).localeCompare(String(a.latestSeenAt))||a.momoName.localeCompare(b.momoName));
  return {items:filtered.slice(0,limit),total:filtered.length,hasMore:filtered.length>limit};
}
export function prepareImportRows(rows) {
  if (!Array.isArray(rows)||rows.length>500) throw new InputError('Import must contain at most 500 records');
  const seen=new Set();
  return rows.map((r,index)=>{
    const name=normalizeName(r?.momoName??r?.name);
    let phone=null; let status='ready'; let issue=null;
    if(!name||name.length>150) { status='invalid';issue='Missing or invalid MoMo name'; }
    try { phone=normalizeRwPhone(r?.momoNumber??r?.phone); } catch { status='invalid';issue='Missing or invalid full MoMo number'; }
    if(phone){if(seen.has(phone)){status='duplicate_in_file';issue='Repeated MoMo number in this file';}else seen.add(phone);}
    return {row:index+1,momoName:name,momoNumber:phone,status,issue,selected:status==='ready'};
  });
}
/** Domain boundary: the store must enforce UNIQUE(tenant,normalized_phone), immutable audit and a transactional lock. */
export async function enrollOne({store, actor, tenantId, name, phone, candidateId=null, verifiedOwnership, acceptedTerms, consentRecorded, idempotencyKey}) {
  if(!actor?.id || !actor.canEnroll || actor.tenantId!==tenantId) throw Object.assign(new Error('Not authorized'),{status:403,code:'FORBIDDEN'});
  if(verifiedOwnership!==true || acceptedTerms!==true || consentRecorded!==true) throw new InputError('Identity, ownership and consent checks are required','VERIFICATION_REQUIRED');
  const momoName=normalizeName(name), momoNumber=normalizeRwPhone(phone);
  if(momoName.length<2||momoName.length>150) throw new InputError('Invalid MoMo name');
  if(!/^[a-zA-Z0-9:_-]{12,100}$/.test(idempotencyKey??'')) throw new InputError('Missing or invalid idempotency key');
  return store.transaction(async tx=>{
    const existingRequest=await tx.findRequest(tenantId,idempotencyKey);
    if(existingRequest) {
      if(existingRequest.momoNumber!==momoNumber||existingRequest.momoName!==momoName) throw Object.assign(new Error('Idempotency key conflict'),{status:409,code:'KEY_REUSED'});
      return existingRequest.result;
    }
    if(await tx.findByPhone(tenantId,momoNumber)) throw Object.assign(new Error('Member already exists'),{status:409,code:'MEMBER_EXISTS'});
    if(candidateId) {
      const candidate=await tx.findCandidate(tenantId,candidateId);
      if(!candidate || candidate.scopeVerified!==true || candidate.last3!==momoNumber.slice(-3)) throw Object.assign(new Error('Suggestion is stale or does not match number'),{status:409,code:'CANDIDATE_MISMATCH'});
      // The suffix and name are hints only: never create a financial payer binding here.
    }
    const result=await tx.createMember({tenantId,momoName,momoNumber,createdBy:actor.id,source:candidateId?'sms_suggestion':'manual_or_import',verification:{verifiedOwnership,acceptedTerms,consentRecorded}});
    await tx.audit({tenantId,actorId:actor.id,action:'MEMBER_CREATED',memberId:result.id,sourceCandidateId:candidateId});
    await tx.saveRequest({tenantId,idempotencyKey,momoNumber,momoName,result});
    return result;
  });
}
export async function importVerifiedRows({store,actor,tenantId,rows,batchId}) {
  if(!/^[a-zA-Z0-9:_-]{12,100}$/.test(batchId??'')) throw new InputError('Invalid batch ID');
  if(!Array.isArray(rows)||rows.length>500) throw new InputError('Invalid import rows');
  const seen=new Set(), results=[];
  for(let i=0;i<rows.length;i++) {
    const r=rows[i];
    if(r.selected!==true){results.push({row:i+1,status:'skipped'});continue;}
    let phone;
    try { phone=normalizeRwPhone(r.momoNumber); }catch {results.push({row:i+1,status:'invalid'});continue;}
    if(seen.has(phone)){results.push({row:i+1,status:'duplicate_in_batch'});continue;}
    seen.add(phone);
    try {
      const result=await enrollOne({store,actor,tenantId,name:r.momoName,phone,candidateId:null,verifiedOwnership:r.verifiedOwnership===true,acceptedTerms:r.acceptedTerms===true,consentRecorded:r.consentRecorded===true,idempotencyKey:`${batchId}:${i+1}`});
      results.push({row:i+1,status:'created',memberId:result.id});
    }catch(e){results.push({row:i+1,status:e.code==='MEMBER_EXISTS'?'already_registered':e.code==='VERIFICATION_REQUIRED'?'needs_verification':'failed',code:e.code??'ERROR'});}
  }
  return {results,created:results.filter(x=>x.status==='created').length};
}
