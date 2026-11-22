import {ApiError,digest,id,integer,stableJson,uuid} from './core.js';

const exactLimit=9007199254740991n;
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const unavailable=()=>fail(503,'history_unavailable','History is unavailable.');
const changed=()=>fail(409,'history_changed','History changed. Refresh before continuing.');
const fields=new Set(['p_contract_version','p_collection_id','p_query','p_sort','p_cursor','p_limit']);
const orders={
 newest:'l.posted_at DESC,l.id ASC',oldest:'l.posted_at ASC,l.id ASC',
 highest:'l.amount_minor DESC,l.posted_at DESC,l.id ASC',lowest:'l.amount_minor ASC,l.posted_at DESC,l.id ASC',
};
const numeric=value=>{
 if(value>exactLimit||value< -exactLimit)unavailable();
 return Number(value);
};

// A financial event is a retained ledger entry, not the mutable current status
// of its payment. Compensating entries remain visible beside their original.
export async function memberHistoryPage(body,env,actor){
 if(Object.keys(body).some(key=>!fields.has(key))||body.p_contract_version!==2)
  fail(400,'invalid_history_query','Use the supported history contract.');
 const selected=body.p_collection_id==null?null:uuid(body.p_collection_id,'collection_id');
 if(body.p_query!==undefined&&(typeof body.p_query!=='string'||body.p_query.length>80||/[\u0000-\u001f\u007f]/.test(body.p_query)))
  fail(400,'invalid_query','Invalid history search.');
 const search=(body.p_query??'').trim(),sort=body.p_sort??'newest';
 if(!Object.hasOwn(orders,sort))fail(400,'invalid_sort','Invalid history sort.');
 const limit=integer(body.p_limit??50,'limit',1,50),cursor=body.p_cursor??null;
 if(cursor!==null&&(typeof cursor!=='object'||Array.isArray(cursor)||Object.keys(cursor).sort().join(',')!=='after,revision'
  ||typeof cursor.revision!=='string'||!/^[a-f0-9]{32}$/.test(cursor.revision)))changed();
 if(cursor!==null)uuid(cursor.after,'cursor');
 const literal='%'+search.replace(/[\\%_]/g,'\\$&')+'%',collectId=/^#?[0-9]{6}$/.test(search)?search.replace(/^#/,''):null;
 const guard=id();let result;
 try{
  result=await env.DB.batch([
   env.DB.prepare('INSERT INTO mutation_guards(id,user_id,session_id,now_seconds) VALUES(?,?,?,?)')
    .bind(guard,actor.userId,actor.sessionId,Math.floor(Date.now()/1000)),
   env.DB.prepare(`SELECT l.id AS entry_id,l.payment_id,l.collection_id,g.title AS group_title,l.amount_minor,l.currency,p.rail,
    l.posted_at,COALESCE(u.public_id,'Member') AS supporter_label,
    CASE WHEN l.member_id=? THEN 1 ELSE 0 END AS own,l.kind AS entry_kind,l.reverses_entry_id,l.evidence_id,p.status AS payment_status
    FROM ledger_entries l JOIN payments p ON p.id=l.payment_id JOIN collections g ON g.id=l.collection_id
    JOIN payment_evidence e ON e.id=l.evidence_id JOIN memberships m ON m.collection_id=l.collection_id
    LEFT JOIN users u ON u.id=l.member_id
    WHERE m.user_id=? AND m.active=1 AND (? IS NULL OR l.collection_id=?)
    AND (?='' OR g.title LIKE ? ESCAPE '\\'
     OR (? IS NOT NULL AND u.public_id=?) OR l.payment_id=? OR l.id=? OR e.external_reference=?)
    ORDER BY ${orders[sort]} LIMIT 10001`).bind(actor.userId,actor.userId,selected,selected,search,literal,collectId,collectId,search,search,search),
   env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(guard),
  ]);
 }catch(error){
  if(/session_changed|permission_denied/.test(String(error?.message)))
   fail(403,'session_changed','Verify your sign-in before continuing.');
  throw error;
 }
 const source=result[1].results;
 if(source.length>10000)fail(400,'history_filter_required','Choose a group or narrow the history search.');
 let credit=0n,debit=0n,ownCredit=0n,ownDebit=0n;const ownIds=new Set();
 const items=source.map(({own,...row})=>{
  if(!Number.isSafeInteger(row.amount_minor)||row.amount_minor===0||row.currency!=='RWF'||row.rail!=='rwanda_momo'
   ||typeof row.posted_at!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(row.posted_at)
   ||!Number.isFinite(Date.parse(row.posted_at))||new Date(row.posted_at).toISOString()!==row.posted_at
   ||!['contribution','reversal','correction'].includes(row.entry_kind)
   ||(row.entry_kind==='contribution'?(row.amount_minor<0||row.reverses_entry_id!==null):(row.amount_minor>0||typeof row.reverses_entry_id!=='string')))
   unavailable();
  const amount=BigInt(row.amount_minor);
  if(amount>0n){credit+=amount;if(own)ownCredit+=amount;}
  else{debit-=amount;if(own)ownDebit-=amount;}
  if(own)ownIds.add(row.collection_id);
  return {...row,is_current_user_contribution:own===1,provider_confirmation:false,settlement_status:'not_asserted'};
 });
 const revision=(await digest(stableJson({contract_version:2,subject:actor.userId,session:actor.sessionId,
  query:{collection_id:selected,search,sort},items}))).slice(0,32);
 let start=0;
 if(cursor){
  if(cursor.revision!==revision)changed();
  start=items.findIndex(row=>row.entry_id===cursor.after)+1;
  if(start===0||start>=items.length)changed();
 }
 const window=items.slice(start,start+limit);
 return {contract_version:2,contribution_basis:'reconciled_evidence_entries',items:window,total_count:items.length,
  totals:{RWF:numeric(credit-debit)},own_totals:{RWF:numeric(ownCredit-ownDebit)},
  credit_totals:{RWF:numeric(credit)},debit_totals:{RWF:numeric(debit)},
  own_credit_totals:{RWF:numeric(ownCredit)},own_debit_totals:{RWF:numeric(ownDebit)},
  own_collection_ids:[...ownIds].sort(),revision,
  next_cursor:start+window.length<items.length?{revision,after:window.at(-1).entry_id}:null};
}
