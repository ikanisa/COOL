// Trusted server SQL. Authority, group revision, totals and one keyset page use
// one statement snapshot. No client SQL, mutation guard or global batch lock.
const orders={newest:'posted_at DESC,entry_id ASC',oldest:'posted_at ASC,entry_id ASC',
 highest:'amount_minor DESC,posted_at DESC,entry_id ASC',lowest:'amount_minor ASC,posted_at DESC,entry_id ASC'};
const timeAfter='(r.posted_at<a.posted_at OR (r.posted_at=a.posted_at AND r.entry_id>a.entry_id))';
const after={newest:timeAfter,oldest:'(r.posted_at>a.posted_at OR (r.posted_at=a.posted_at AND r.entry_id>a.entry_id))',
 highest:`(r.amount_minor<a.amount_minor OR (r.amount_minor=a.amount_minor AND ${timeAfter}))`,
 lowest:`(r.amount_minor>a.amount_minor OR (r.amount_minor=a.amount_minor AND ${timeAfter}))`};

export async function historySnapshot(env,actor,{selected,search,sort,from,before,literal,collectId,cursor,limit}){
 if(!Object.hasOwn(orders,sort))throw new TypeError('Unsupported history order');
 const row=await env.DB.prepare(`WITH authority AS MATERIALIZED (
   SELECT private.assert_actor() AS principal,api.current_session_id() AS session_id
  ), groups AS MATERIALIZED (
   SELECT m.collection_id,m.revision AS membership_revision,v.revision AS history_revision
   FROM app.memberships m LEFT JOIN private.member_history_versions v ON v.collection_id=m.collection_id
   CROSS JOIN authority a WHERE m.user_id=a.principal AND a.principal=? AND a.session_id=?
    AND m.active=1 AND (? IS NULL OR m.collection_id=?)
  ), matching AS NOT MATERIALIZED (
   SELECT l.id AS entry_id,l.payment_id,l.collection_id,g.title AS group_title,l.amount_minor,l.currency,p.rail,
    l.posted_at,COALESCE(u.public_id,'Member') AS supporter_label,l.member_id,
    l.kind AS entry_kind,l.reverses_entry_id,l.evidence_id,p.status AS payment_status
   FROM groups scope JOIN app.ledger_entries l ON l.collection_id=scope.collection_id
   JOIN app.payments p ON p.id=l.payment_id JOIN app.collections g ON g.id=l.collection_id
   JOIN app.payment_evidence e ON e.id=l.evidence_id LEFT JOIN app.users u ON u.id=l.member_id
   WHERE (? IS NULL OR l.posted_at>=?) AND (? IS NULL OR l.posted_at<?)
    AND (?='' OR g.title LIKE ? ESCAPE '\\' OR (? IS NOT NULL AND u.public_id=?)
     OR l.payment_id=? OR l.id=? OR e.external_reference=?)
  ), totals AS (
   SELECT count(*)::text AS total_count,
    coalesce(sum(amount_minor) FILTER(WHERE amount_minor>0),0)::text AS credit,
    coalesce(-sum(amount_minor) FILTER(WHERE amount_minor<0),0)::text AS debit,
    coalesce(sum(amount_minor) FILTER(WHERE amount_minor>0 AND member_id=?),0)::text AS own_credit,
    coalesce(-sum(amount_minor) FILTER(WHERE amount_minor<0 AND member_id=?),0)::text AS own_debit,
    coalesce(jsonb_agg(DISTINCT collection_id ORDER BY collection_id) FILTER(WHERE member_id=?),'[]'::jsonb) AS own_collection_ids,
    coalesce(bool_and(CASE WHEN posted_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$'
     THEN to_char(posted_at::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')=posted_at ELSE false END),true) AS valid_instants
   FROM matching
  ), anchor AS MATERIALIZED (SELECT entry_id,posted_at,amount_minor FROM matching WHERE entry_id=?),
  page AS (SELECT r.* FROM matching r WHERE (? IS NULL OR EXISTS(SELECT 1 FROM anchor a WHERE ${after[sort]}))
   ORDER BY ${orders[sort]} LIMIT ?)
  SELECT jsonb_build_object('principal',a.principal,'session_id',a.session_id,'totals',to_jsonb(t),
   'versions',coalesce((SELECT jsonb_agg(jsonb_build_array(collection_id,history_revision::text,membership_revision::text) ORDER BY collection_id) FROM groups),'[]'::jsonb),
   'versions_valid',coalesce((SELECT bool_and(history_revision IS NOT NULL) FROM groups),true),
   'anchor_found',EXISTS(SELECT 1 FROM anchor),
   'items',coalesce((SELECT jsonb_agg(to_jsonb(p)-'member_id'||jsonb_build_object('is_current_user_contribution',coalesce(p.member_id=?,false)) ORDER BY ${orders[sort]}) FROM page p),'[]'::jsonb)) AS snapshot
  FROM authority a CROSS JOIN totals t`).bind(actor.userId,actor.sessionId,selected,selected,
   from,from,before,before,search,literal,collectId,collectId,search,search,search,
   actor.userId,actor.userId,actor.userId,cursor?.after??null,cursor?.after??null,limit+1,actor.userId).first();
 return row?.snapshot;
}
