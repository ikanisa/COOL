import {requireThat} from './errors.js';

export const LISTING_QUERY_KEYS=Object.freeze(['q','filter','limit','memberId','cursor','sort','fromAt','untilAt','minRwf','maxRwf','active','direction','outcome','credit','anchorId']);
const financial=new Set(['payments','ledger','history']),people=new Set(['members','staff']);
const added=['sort','fromAt','untilAt','minRwf','maxRwf','active','direction','outcome','credit'];
const legacyFilters=['all','unallocated','allocated','processing'];
export const listingSorts=kind=>['newest','oldest',...(financial.has(kind)?['amount_asc','amount_desc']:kind==='members'?['name_asc','name_desc','phone_asc','phone_desc','balance_asc','balance_desc']:kind==='staff'?['name_asc','name_desc','phone_asc','phone_desc']:kind==='audit'?['action_asc','action_desc']:[])];
function at(value){
 requireThat(typeof value==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(value),'invalid_query');
 const stamp=Date.parse(value);requireThat(Number.isFinite(stamp)&&new Date(stamp).toISOString().slice(0,19)===value.slice(0,19),'invalid_query');
 return new Date(stamp).toISOString();
}
function amount(value){
 requireThat(typeof value==='number'&&Number.isSafeInteger(value)||typeof value==='string'&&/^-?(?:0|[1-9][0-9]{0,15})$/.test(value),'invalid_query');
 const n=Number(value);requireThat(Number.isSafeInteger(n)&&Math.abs(n)<=9007199254740991,'invalid_query');return n;
}
export function normalizeListingQuery(kind,query={}){
 requireThat(['payments','members','ledger','sms','observations','staff','audit','history'].includes(kind)&&query&&typeof query==='object'&&!Array.isArray(query)&&Object.keys(query).every(k=>LISTING_QUERY_KEYS.includes(k)),'invalid_query');
 requireThat(query.anchorId===undefined||kind==='members'&&query.cursor===undefined,'invalid_query');
 const q=query.q??'',filter=query.filter??'all',limit=query.limit??40,sort=query.sort??(kind==='history'?'oldest':'newest');
 requireThat(typeof q==='string'&&q.length<=80&&!/[\u0000-\u001f\u007f-\u009f]/.test(q)&&Number.isInteger(limit)&&limit>=1&&limit<=100&&listingSorts(kind).includes(sort),'invalid_query');
 const filters=kind==='sms'?['all','queued','duplicate','synced','rejected']:kind==='observations'?['all']:kind==='history'?['all','transaction_recorded','ledger_entry']:kind==='payments'?[...legacyFilters,'recorded','posted','reversed','corrected','conflict']:legacyFilters;
 requireThat(filters.includes(filter),'invalid_filter');
 const active=query.active??'all',direction=query.direction??'all',outcome=query.outcome??'all',credit=query.credit??'all';
 requireThat(['all','active','inactive'].includes(active)&&(active==='all'||people.has(kind))&&
  ['all','incoming','outgoing','reversal','other'].includes(direction)&&(direction==='all'||kind==='payments')&&
  ['all','successful','failed','pending','unknown'].includes(outcome)&&(outcome==='all'||kind==='payments')&&
  ['all','credited','uncredited','reversed','corrected'].includes(credit)&&(credit==='all'||kind==='payments'),'invalid_filter');
 const fromAt=query.fromAt===undefined?null:at(query.fromAt),untilAt=query.untilAt===undefined?null:at(query.untilAt);
 requireThat((fromAt===null&&untilAt===null||!people.has(kind))&&(fromAt===null||untilAt===null||fromAt<untilAt),'invalid_query');
 const minRwf=query.minRwf===undefined?null:amount(query.minRwf),maxRwf=query.maxRwf===undefined?null:amount(query.maxRwf);
 requireThat((minRwf===null&&maxRwf===null||financial.has(kind)||kind==='members')&&
  (kind!=='payments'||[minRwf,maxRwf].every(n=>n===null||n>=0))&&(minRwf===null||maxRwf===null||minRwf<=maxRwf),'invalid_query');
 return {q,filter,limit,sort,fromAt,untilAt,minRwf,maxRwf,active,direction,outcome,credit,
  advanced:added.some(k=>Object.hasOwn(query,k))||kind==='payments'&&!legacyFilters.includes(filter)||['staff','audit','ledger','history'].includes(kind)&&q.length>0||kind==='history'&&filter!=='all'};
}
export const listingFilterIdentity=query=>Object.fromEntries(Object.entries(query).filter(([key])=>!['advanced','limit'].includes(key)));
const lower=value=>String(value??'').toLocaleLowerCase('en');
const compare=(a,b)=>a===b?0:a===null||a===undefined?1:b===null||b===undefined?-1:a<b?-1:1;
/** Entries contain only already-authorized projections plus canonical sort
 * metadata. Filter/sort the entire bounded snapshot before selecting a page. */
export function selectListing(entries,kind,query,after=null,asOf=new Date().toISOString()){
 requireThat(Array.isArray(entries)&&entries.length<=100000,'snapshot_limit',413);
 const x=normalizeListingQuery(kind,Object.fromEntries(Object.entries(query).filter(([key,value])=>key!=='advanced'&&value!==null))),offset=after?.offset??0;
 requireThat(Number.isSafeInteger(offset)&&offset>=0&&offset<=100000,'invalid_cursor');
 const ids=new Set();for(const e of entries){requireThat(e?.item&&typeof e.item.id==='string'&&!ids.has(e.item.id),'invalid_snapshot',503);ids.add(e.item.id);}
 const rows=entries.filter(e=>{
  const item=e.item,value=e.amount??null,date=e.at??null;
  if(x.q&&!lower(e.search??item.id).includes(lower(x.q)))return false;
  if(x.filter!=='all'){
   if(kind==='payments'&&!(e.filters??[item.state]).includes(x.filter))return false;
   if(kind==='sms'&&item.state!==x.filter)return false;
   if(kind==='history'&&item.kind!==x.filter)return false;
  }
  if(x.fromAt!==null&&(date===null||date<x.fromAt)||x.untilAt!==null&&(date===null||date>=x.untilAt))return false;
  if(x.minRwf!==null&&(value===null||value<x.minRwf)||x.maxRwf!==null&&(value===null||value>x.maxRwf))return false;
  if(x.active!=='all'&&item.active!==(x.active==='active'))return false;
  if(x.direction!=='all'&&e.direction!==x.direction||x.outcome!=='all'&&e.outcome!==x.outcome)return false;
  if(x.credit==='credited'&&item.state!=='posted'||x.credit==='uncredited'&&['posted','reversed','corrected'].includes(item.state)||['reversed','corrected'].includes(x.credit)&&item.state!==x.credit)return false;
  return true;
 });
 const field=x.sort.startsWith('amount_')||x.sort.startsWith('balance_')?'amount':x.sort.startsWith('name_')?'name':x.sort.startsWith('phone_')?'phone':x.sort.startsWith('action_')?'action':'at';
 const descending=x.sort==='newest'||x.sort.endsWith('_desc');
 rows.sort((a,b)=>{
  let first=compare(a[field],b[field]);if(a[field]!==null&&a[field]!==undefined&&b[field]!==null&&b[field]!==undefined&&descending)first=-first;
  return first||compare(a.item.id,b.item.id);
 });
 requireThat(offset===0||offset<rows.length,'invalid_cursor');
 const items=rows.slice(offset,offset+x.limit).map(e=>e.item),next=offset+items.length;
 return {items,totalCount:rows.length,after:next<rows.length?{offset:next}:null,asOf};
}
export function canonicalListingInstant(value){
 if(value instanceof Date)value=value.toISOString();
 if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(Z|[+-]\d\d:\d\d)$/.test(value))return null;
 const wall=Date.parse(value.slice(0,19)+'Z');
 if(!Number.isFinite(wall)||new Date(wall).toISOString().slice(0,19)!==value.slice(0,19))return null;
 const zone=/([+-])(\d\d):(\d\d)$/.exec(value);
 if(zone&&(Number(zone[2])>23||Number(zone[3])>59))return null;
 const n=Date.parse(value);return Number.isFinite(n)?new Date(n).toISOString():null;
}
export const listingText=value=>lower(value);
