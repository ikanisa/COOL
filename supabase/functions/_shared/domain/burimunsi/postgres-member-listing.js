import {requireId} from './values.js';
import {requireThat} from './errors.js';
import {pgInteger} from './postgres-values.js';

const WHO = 'FROM app.memberships m JOIN app.users u ON u.id=m.user_id';
const PERSON = 'm.user_id AS id,m.collection_id,u.full_name,u.momo_number,m.active,m.revision';
const ID = 'm.user_id COLLATE "C"';
const PHONE = 'private.burimunsi_member_phone(u.momo_number)';
const JOINED = 'private.burimunsi_member_joined(m.joined_at)';
const NAME = 'lower(u.full_name COLLATE pg_catalog."en-US-x-icu") COLLATE "C"';
const BALANCE = 'coalesce(b.balance,0)';
const amountForMember = 'coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l'
  + ' WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id),0)';

function orderFor({advanced,sort}) {
  if(!advanced)return {field:'m.joined_at COLLATE "C"',type:'text',direction:'DESC',tie:'DESC'};
  const direction=sort==='newest'||sort.endsWith('_desc')?'DESC':'ASC';
  if(sort.startsWith('balance_'))return {field:BALANCE,type:'numeric',direction,tie:'ASC'};
  if(sort.startsWith('name_'))return {field:NAME,type:'text',direction,tie:'ASC'};
  if(sort.startsWith('phone_'))return {field:`${PHONE} COLLATE "C"`,type:'text',direction,tie:'ASC'};
  return {field:JOINED,type:'timestamptz',direction,tie:'ASC'};
}

function queryPlan(groupId,listing,{balance,order,textToken}) {
  const values=[groupId],predicates=['m.collection_id=$1'];
  const bind=value=>'$'+values.push(value);
  if(listing.active!=='all')predicates.push(`m.active=${bind(listing.active==='active'?1:0)}::bigint`);
  const lower=value=>`lower(${value} COLLATE pg_catalog."en-US-x-icu")`;
  if(listing.q){
    const term=lower(`${bind(listing.q)}::text`);
    if(listing.advanced){
      const number=balance?`${balance}::text`:"''";
      const body=textToken?"concat_ws(' ',m.user_id,u.full_name,u.momo_number)":`concat_ws(' ',m.user_id,u.full_name,coalesce(${PHONE},''),
        coalesce('0'||substr(${PHONE},5),''),u.momo_number,${number})`;
      predicates.push(`strpos(${lower(body)},${term})>0`);
    }else predicates.push(`(strpos(${lower('u.full_name')},${term})>0 OR strpos(${lower('u.momo_number')},${term})>0)`);
  }
  if(listing.minRwf!==null)predicates.push(`${balance}>=${bind(listing.minRwf)}::numeric`);
  if(listing.maxRwf!==null)predicates.push(`${balance}<=${bind(listing.maxRwf)}::numeric`);
  return {values,predicates,bind,order};
}

const where=predicates=>predicates.length?' WHERE '+predicates.join(' AND '):'';
const balanceTotals=` LEFT JOIN (SELECT member_id,sum(amount_minor) AS balance FROM app.ledger_entries
  WHERE collection_id=$1 AND member_id IS NOT NULL GROUP BY member_id) b ON b.member_id=m.user_id`;

function seek(plan,pivot,inclusive,field,idColumn) {
  const {order:{type,direction,tie},bind}=plan;
  const id=bind(pivot.id),tieOp=tie==='DESC'?(inclusive?'<=':'<'):(inclusive?'>=':'>');
  const tieFilter=`${idColumn}${tieOp}${id}::text COLLATE "C"`;
  if(pivot.sort_key===null)return `(${field} IS NULL AND ${tieFilter})`;
  const key=bind(pivot.sort_key)+'::'+type;
  const keyOp=direction==='DESC'?'<':'>';
  return `(${field}${keyOp}${key} OR ${field} IS NULL OR (${field}=${key} AND ${tieFilter}))`;
}

// Resolve only a visible pivot. The signed cursor stores an ID and exact total,
// so normalized names and phone numbers never travel in a readable token.
export async function readMemberListing(sql,{groupId,listing,after,anchorId}) {
  if(after!==null){
    requireThat(after&&Object.keys(after).length===2&&Number.isSafeInteger(after.total)&&after.total>0,'invalid_cursor');
    requireId(after.id);
  }
  const order=orderFor(listing);
  // A single token with a letter cannot span the space between fields or
  // occur in a normalized phone or integer amount. Keep the original phone
  // text searchable for imported records and retain the full phrase path.
  const textToken=listing.advanced&&/\p{L}/u.test(listing.q)&&!/\s/u.test(listing.q);
  const planFor=balance=>queryPlan(groupId,listing,{balance,order,textToken});
  // A text-only search cannot match any new characters from a signed integer.
  // Name, date and phone pages without a money filter need sums only for the
  // selected rows. Amount sorts and filters aggregate the group once in SQL.
  const balanceFilter=listing.minRwf!==null||listing.maxRwf!==null||listing.advanced&&!textToken&&/[0-9-]/.test(listing.q);
  const usesBalances=balanceFilter||order.type==='numeric';
  let pivot=null;
  if(after||anchorId){
    const balance=usesBalances?amountForMember:null;
    const plan=planFor(balance);
    plan.predicates.push(`m.user_id=${plan.bind(after?.id??anchorId)}`);
    const key=order.type==='numeric'?amountForMember:order.field;
    pivot=(await sql.unsafe(`SELECT m.user_id AS id,${key} AS sort_key ${WHO}${where(plan.predicates)}`,plan.values))[0]??null;
    if(after)requireThat(pivot,'cursor_scope_changed',409);
  }
  // A cursor names this exact group revision and filter. Reuse its count;
  // count only first/anchored pages, independent of the selected sort.
  let totalCount=after?.total;
  if(totalCount===undefined){
    const count=planFor(balanceFilter?BALANCE:null);
    const result=await sql.unsafe(`SELECT count(*) AS total ${WHO}${balanceFilter?balanceTotals:''}${where(count.predicates)}`,count.values);
    totalCount=pgInteger(result[0].total);
  }
  const page=planFor(usesBalances?BALANCE:null);
  const resultKey=`sort_key${order.type==='text'?' COLLATE "C"':''}`;
  let select=`SELECT ${PERSON},${order.field} AS sort_key${usesBalances?`,${BALANCE} AS balance`:''}
    ${WHO}${usesBalances?balanceTotals:''}`;
  let predicates=page.predicates,field=order.field,idColumn=ID;
  // For a text result that fits in one maximum-size API page, filter first.
  // Walking a date index to find a few matches late in a large group is expensive.
  if(textToken&&!usesBalances&&totalCount<=100){
    select=`WITH matches AS MATERIALIZED (${select}${where(predicates)}) SELECT * FROM matches`;
    predicates=[];
    field=resultKey;
    idColumn='id COLLATE "C"';
  }
  if(pivot)predicates.push(seek(page,pivot,after===null,field,idColumn));
  const limit=page.bind(listing.limit+1);
  const selected=`${select}${where(predicates)} ORDER BY ${field} ${order.direction} NULLS LAST,${idColumn} ${order.tie} LIMIT ${limit}`;
  const sqlPage=usesBalances?selected:`WITH page AS MATERIALIZED (${selected})
    SELECT page.*,coalesce((SELECT sum(l.amount_minor) FROM app.ledger_entries l
      WHERE l.collection_id=page.collection_id AND l.member_id=page.id),0) AS balance
    FROM page ORDER BY page.${resultKey} ${order.direction} NULLS LAST,page.id COLLATE "C" ${order.tie}`;
  const rows=await sql.unsafe(sqlPage,page.values);
  const hasMore=rows.length>listing.limit,items=rows.slice(0,listing.limit);
  return {rows:items,totalCount,after:hasMore?{id:items.at(-1).id,total:totalCount}:null};
}
