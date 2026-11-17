import {requirePort,requireThat} from './errors.js';
import {normalizePhone,requireId} from './values.js';
import {pgInteger} from './postgres-values.js';

// Accepted managed and native SMS sources supply suggestions. A masked native
// identifier remains a name/suffix hint; it never invents a full phone number.
// Full phone numbers remain inside PostgreSQL.
const phone = value => {
 const compact=`regexp_replace(${value},'[ ()-]','','g')`;
 return `CASE WHEN length(${value})<=40 AND ${value} ~ '^[+0-9 ()-]+$' THEN CASE
  WHEN ${compact} ~ '^\\+2507[2389][0-9]{7}$' THEN ${compact}
  WHEN ${compact} ~ '^002507[2389][0-9]{7}$' THEN '+' || substr(${compact},3)
  WHEN ${compact} ~ '^2507[2389][0-9]{7}$' THEN '+' || ${compact}
  WHEN ${compact} ~ '^07[2389][0-9]{7}$' THEN '+250' || substr(${compact},2)
  WHEN ${compact} ~ '^7[2389][0-9]{7}$' THEN '+250' || ${compact}
  ELSE NULL END ELSE NULL END`;
};
const route = value => `coalesce(${phone(value)},CASE WHEN ${value} ~ '^[0-9]{4,9}$' THEN ${value} ELSE NULL END)`;
// Normalize canonical Unicode forms, then fold both cases before lowercasing:
// PostgreSQL's C collation does not lowercase accented uppercase letters.
// This is a bounded Latin mapping, not a complete Unicode transliterator.
const fold = value => `lower(translate(replace(replace(normalize(${value},NFC),'ß','ss'),'ẞ','SS'),
 'ÀÁÂÃÄÅĀĂĄÇĆČĎÈÉÊËĒĖĘĚÌÍÎÏĪŁÑŃŇÒÓÔÕÖŌØŘŚŠẞŤÙÚÛÜŪÝŸŽŹŻàáâãäåāăąçćčďèéêëēėęěìíîïīłñńňòóôõöōøřśšßťùúûüūýÿžźż',
 'AAAAAAAAACCCDEEEEEEEEIIIIILNNNOOOOOOORSSSTUUUUUYYZZZaaaaaaaaacccdeeeeeeeeiiiiilnnnooooooorssstuuuuuyyzzz'))`;
const nameKey = value => `trim(regexp_replace(lower(normalize(${value},NFKC)),'[^[:alnum:]]+',' ','g'))`;
const suffix = value => `CASE WHEN length(${value})<=160 AND ${value} !~ '[[:cntrl:]]'
 AND ${value} ~ '[0-9]{3}[ ]*$' THEN right(regexp_replace(${value},'[^0-9]','','g'),3) ELSE NULL END`;

export const SMART_SUGGESTIONS_CTE=`WITH managed_admitted AS (
 SELECT t.id AS transaction_id,trim(t.payer_name) AS payer_name,
   ${phone('t.payer_identifier')} AS payer_phone,t.transaction_at
 FROM private.burimunsi_transaction_scopes x
 JOIN private.burimunsi_scopes s ON s.collection_id=x.collection_id AND s.receiving_account_id=x.receiving_account_id
 JOIN app.collections g ON g.id=x.collection_id
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 JOIN app.momo_receiving_accounts w ON w.id=x.receiving_account_id
 JOIN app.momo_transaction_sources ts ON ts.transaction_id=t.id AND ts.parse_attempt_id=t.parse_attempt_id AND ts.relation='accepted'
 JOIN app.sms_receipts r ON r.id=ts.raw_sms_id
 JOIN app.momo_parse_attempts a ON a.id=ts.parse_attempt_id AND a.raw_sms_id=r.id
 JOIN app.momo_gateway_captures c ON c.raw_sms_id=r.id
 JOIN app.momo_gateway_credentials k ON k.id=c.credential_id
 JOIN app.momo_gateway_bindings b ON b.id=k.binding_id
 JOIN app.momo_processing_jobs j ON j.raw_sms_id=r.id
 WHERE x.collection_id=$1 AND x.native_source_id IS NULL AND s.enabled=true
  AND x.source_binding_id=s.active_binding_id AND x.source_binding_id=b.id
  AND x.source_binding_version=s.binding_version AND x.source_binding_version=b.version
  AND j.binding_id=b.id AND j.binding_version=b.version AND j.receiving_account_id=w.id
  AND b.receiving_account_id=w.id AND b.owner_user_id=r.owner_user_id
  AND b.status='active' AND k.revoked_at IS NULL AND w.status='active' AND w.profile_status='approved'
  AND g.status='active' AND g.receiver_network=w.provider AND ${route('g.receiver_momo_number')}=${route('w.public_code')}
  AND r.originating_session_id IS NOT NULL AND r.receiver_hash=w.receiver_hash
  AND a.outcome='accepted' AND a.source_body_sha256=r.body_sha256
  AND a.profile_version=w.profile_version AND a.profile_json=w.profile_json
  AND c.completeness='complete' AND c.source_mode='live' AND j.mode='live'
  AND j.state='completed' AND j.last_error IS NULL
  AND t.event_kind='incoming_receipt' AND t.mode='live' AND t.has_conflict=0
  AND t.allocation_state='unallocated' AND t.currency='RWF'
  AND t.id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND t.payer_name IS NOT NULL AND length(trim(t.payer_name)) BETWEEN 2 AND 100
  AND t.payer_name !~ '[[:cntrl:]]'
  AND t.transaction_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?Z$'
  AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict')
  AND NOT EXISTS(SELECT 1 FROM app.momo_financial_links linked WHERE linked.transaction_id=t.id)
), native_projected AS (
 SELECT t.id AS transaction_id,t.transaction_at,native.value->'facts' AS facts
 FROM private.burimunsi_transaction_scopes x
 JOIN private.burimunsi_scopes s ON s.collection_id=x.collection_id AND s.receiving_account_id=x.receiving_account_id
 JOIN app.collections g ON g.id=x.collection_id AND g.status='active'
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 JOIN app.momo_receiving_accounts w ON w.id=x.receiving_account_id AND w.status='active'
 JOIN app.momo_transaction_sources ts ON ts.transaction_id=t.id AND ts.parse_attempt_id=t.parse_attempt_id
  AND ts.raw_sms_id=x.native_source_id AND ts.relation='accepted'
 JOIN app.sms_receipts r ON r.id=x.native_source_id
 JOIN app.momo_parse_attempts a ON a.id=ts.parse_attempt_id AND a.raw_sms_id=r.id AND a.source_body_sha256=r.body_sha256
 JOIN LATERAL (SELECT private.burimunsi_auto_projection(x.native_source_id) AS value) native ON true
 WHERE x.collection_id=$1 AND x.native_source_id IS NOT NULL AND (s.enabled OR s.active_binding_id IS NULL)
  AND x.source_binding_id IS NULL AND x.source_binding_version IS NULL
  AND native.value->>'sourceId'=x.native_source_id AND native.value->>'outcome'='successful'
  AND a.outcome='accepted'
  AND t.has_conflict=0 AND t.allocation_state IN ('unallocated','not_applicable')
  AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict')
  AND NOT EXISTS(SELECT 1 FROM app.momo_financial_links linked WHERE linked.transaction_id=t.id)
), native_admitted AS (
 SELECT transaction_id,trim(facts->>'counterparty_name') AS payer_name,
  ${phone("facts->>'counterparty_identifier'")} AS payer_phone,
  ${suffix("facts->>'counterparty_identifier'")} AS payer_last3,
  coalesce(facts->>'transaction_at',transaction_at) AS transaction_at
 FROM native_projected
 WHERE facts->>'event_kind'='incoming_receipt' AND facts->>'payment_outcome'='successful' AND facts->>'currency'='RWF'
  AND jsonb_typeof(facts->'counterparty_name')='string' AND jsonb_typeof(facts->'counterparty_identifier')='string'
), admitted AS (
 SELECT transaction_id,payer_name,payer_phone,right(payer_phone,3) AS last3,transaction_at,false AS native
 FROM managed_admitted WHERE payer_phone IS NOT NULL
 UNION ALL
 SELECT transaction_id,payer_name,payer_phone,payer_last3,transaction_at,true
 FROM native_admitted
 WHERE payer_last3 ~ '^[0-9]{3}$' AND length(payer_name) BETWEEN 2 AND 100 AND payer_name !~ '[[:cntrl:]]'
  AND ${nameKey('payer_name')}<>''
  AND transaction_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND transaction_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?Z$'
), identities AS (
 SELECT ${nameKey('payer_name')} AS name_key,last3,count(DISTINCT payer_phone) AS known_count,max(payer_phone) AS known_phone
 FROM admitted GROUP BY ${nameKey('payer_name')},last3
), unregistered AS (
 SELECT a.*,i.known_phone FROM admitted a
 JOIN identities i ON i.name_key=${nameKey('a.payer_name')} AND i.last3=a.last3
 WHERE (NOT a.native OR i.known_count<=1) AND NOT EXISTS (
  SELECT 1 FROM app.memberships m JOIN app.users u ON u.id=m.user_id
  WHERE m.collection_id=$1 AND (${phone('u.momo_number')}=a.payer_phone OR ${phone('u.phone')}=a.payer_phone
   OR (a.native AND ${nameKey('u.full_name')}=${nameKey('a.payer_name')}
    AND a.last3=right(coalesce(${phone('u.momo_number')},${phone('u.phone')}),3)))
 )
), grouped AS (
 SELECT max(payer_phone) AS payer_phone,max(known_phone) AS known_phone,min(last3) AS last3,
  (array_agg(transaction_id ORDER BY transaction_at DESC,transaction_id DESC))[1] AS candidate_id,
  (array_agg(payer_name ORDER BY transaction_at DESC,transaction_id DESC))[1] AS momo_name,
  max(transaction_at) AS latest_seen_at,count(*) AS source_count
 FROM unregistered GROUP BY CASE WHEN native THEN 'native:'||${nameKey('payer_name')}||':'||last3
  ELSE 'phone:'||payer_phone END
), filtered AS (
 SELECT candidate_id,momo_name,last3,latest_seen_at,source_count
 FROM grouped WHERE $2='' OR strpos(${fold('momo_name')},${fold('$2::text')})>0
  OR ($2 ~ '^[0-9]{3}$' AND last3=$2)
)`;

function queryOptions({groupId,q='',limit=40,after=null}) {
 requireId(groupId);
 requireThat(typeof q==='string'&&q.length<=80&&!/[\u0000-\u001f\u007f]/.test(q),'invalid_query');
 requireThat(Number.isSafeInteger(limit)&&limit>=1&&limit<=100,'invalid_query');
 requireThat(after===null||(after&&Object.keys(after).length===1&&Number.isSafeInteger(after.offset)&&after.offset>=0&&after.offset<=10000),'invalid_cursor');
 return {groupId,q:q.trim(),limit,offset:after?.offset??0};
}
function project(row){
 requireThat(row&&typeof row.candidate_id==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(row.candidate_id)&&
  typeof row.momo_name==='string'&&row.momo_name.length>=2&&row.momo_name.length<=100&&
  typeof row.last3==='string'&&/^[0-9]{3}$/.test(row.last3)&&
  typeof row.latest_seen_at==='string'&&Number.isFinite(Date.parse(row.latest_seen_at)),
  'invalid_suggestion',503);
 return {candidateId:row.candidate_id,momoName:row.momo_name,last3:row.last3,
  latestSeenAt:row.latest_seen_at,sourceCount:pgInteger(row.source_count,{minimum:1,code:'invalid_suggestion'})};
}

export async function listOnboardingSuggestions(sql,options){
 requirePort(sql,['unsafe']);const {groupId,q,limit,offset}=queryOptions(options);
 const rows=await sql.unsafe(`${SMART_SUGGESTIONS_CTE}
  SELECT *,count(*) OVER() AS total_count FROM filtered
  ORDER BY ${fold('momo_name')},candidate_id LIMIT $3 OFFSET $4`,[groupId,q,limit+1,offset]);
 requireThat(Array.isArray(rows)&&rows.length<=limit+1,'invalid_suggestion',503);
 const items=rows.slice(0,limit).map(project);
 const totalCount=rows.length?pgInteger(rows[0].total_count,{minimum:items.length,code:'invalid_suggestion'}):0;
 return {items,totalCount,after:rows.length>limit?{offset:offset+limit}:null};
}

export async function findOnboardingCandidate(sql,{groupId,candidateId,phone}){
 requirePort(sql,['unsafe']);requireId(groupId);requireId(candidateId);
 // Managed candidates retain exact full-phone matching. A masked native
 // candidate binds its selected name/suffix key to the full supplied number;
 // any already-known full number for that key must agree as well.
 const canonical=normalizePhone(phone);
 const rows=await sql.unsafe(`${SMART_SUGGESTIONS_CTE} SELECT * FROM filtered WHERE candidate_id=$3
  AND EXISTS(SELECT 1 FROM grouped WHERE candidate_id=$3 AND (payer_phone=$4 OR
   (payer_phone IS NULL AND last3=right($4::text,3) AND (known_phone IS NULL OR known_phone=$4)))) LIMIT 2`,[groupId,'',candidateId,canonical]);
 requireThat(Array.isArray(rows)&&rows.length<=1,'invalid_suggestion',503);
 return rows.length?{last3:project(rows[0]).last3}:null;
}
