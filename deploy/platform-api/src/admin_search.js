import {ApiError} from './core.js';

// All identifiers originate here; user input only becomes bound SQL values.
export const coreSorts = Object.freeze({
 groups:{created_at:'created_at',status:'status',title:'title',slug:'slug',collection_type:'collection_type',visibility_status:'visibility_status',active_members:'active_members'},
 users:{created_at:'created_at',status:'status',public_id:'public_id',full_name:'full_name',email:'email',member_type:'member_type',phone:'phone',momo_number:'momo_number',momo_pay_code:'momo_pay_code',active_groups:'active_groups',net_contributed_rwf:'net_contributed_rwf'},
 members:{created_at:'created_at',status:'status',public_id:'public_id',full_name:'full_name',email:'email',member_type:'member_type',phone:'phone',momo_number:'momo_number',momo_pay_code:'momo_pay_code',active_groups:'active_groups',net_contributed_rwf:'net_contributed_rwf'},
 payees:{created_at:'created_at',status:'status',label:'label',group_title:'group_title',momo_number_or_code:'momo_number_or_code'},
 transactions:{created_at:'created_at',status:'status',amount_minor:'amount_minor',net_amount:'net_amount',payer_display_name:'payer_display_name',receiver_momo_number:'receiver_momo_number',external_reference:'external_reference',group_title:'group_title',observed_at:'observed_at'},
 ledgers:{created_at:'posted_at',status:'status',amount_minor:'amount_minor',group_title:'group_title',payment_id:'payment_id',evidence_id:'evidence_id'},
});
export const coreStatuses=Object.freeze({groups:['active','suspended','archived'],users:['active','suspended','deleted'],members:['active','suspended','deleted'],payees:['active','inactive'],transactions:['recorded','reconciled','confirmed','ambiguous','corrected','reversed'],ledgers:['contribution','reversal','correction']});
const invalid=message=>{throw new ApiError(400,'invalid_filter',message);};
export function coreOrdering(type,sort){
 const match=/^([a-z_]+)_(asc|desc)$/.exec(sort),column=match&&coreSorts[type]?.[match[1]];
 if(!column)invalid('This ordering is unavailable for these records.');
 return `${column} ${match[2].toUpperCase()},id ${match[2].toUpperCase()}`;
}

export function coreSearch(type,input,fields){
 const predicates=[],args=[],person=type==='users'||type==='members';
 let query=input.trim();
 const add=(condition,...values)=>{predicates.push(condition);args.push(...values);};
 if(person){
  query=query.replace(/\bwithout\s+groups?\b/gi,()=>{add('active_groups=0');return ' ';})
   .replace(/\bwith\s+groups?\b/gi,()=>{add('active_groups>0');return ' ';});
 }
 const terms=[...query.matchAll(/"([^"]+)"|(\S+)/g)];
 if(terms.length>24)invalid('Use at most 24 search terms.');
 const filler=new Set(['group','groups','user','users','member','members','person','people','payee','payees','transaction','transactions','payment','payments','ledger','ledgers','entry','entries']);
 for(const match of terms){
  const term=(match[1]??match[2]).toLowerCase();
  if(match[1]===undefined){
   const status=term.startsWith('status:')?term.slice(7):term;
   if(coreStatuses[type]?.includes(status)){add('status=?',status);continue;}
   if(type==='groups'&&['private','public','public_pending','public_approved'].includes(term)){
    add('visibility_status=?',term==='public'?'public_approved':term);continue;
   }
   const memberType=term.startsWith('type:')?term.slice(5):term;
   if(person&&['staff','admin','owner','app','direct','operator'].includes(memberType)){
    if(memberType==='operator')add("member_type='operator' AND operator_admin_id IS NULL");
    else if(['staff','admin','owner'].includes(memberType))add('operator_role=?',memberType);
    else add('member_type=?',memberType);
    continue;
   }
   if(type==='transactions'&&['unallocated','allocated','partial'].includes(term)){
    add(term==='unallocated'?'net_amount=0':term==='allocated'?'net_amount=amount_minor':'net_amount>0 AND net_amount<amount_minor');continue;
   }
   if(type==='ledgers'&&['reversals','corrections','contributions'].includes(term)){add('kind=?',term.slice(0,-1));continue;}
   if(filler.has(term))continue;
   if(term.startsWith('status:')||person&&term.startsWith('type:'))invalid('This search filter is unavailable for these records.');
  }
  add(`(${fields.map(field=>`instr(lower(COALESCE(${field},'')),lower(?))>0`).join(' OR ')})`,...fields.map(()=>match[1]??match[2]));
 }
 return {predicates,args};
}
