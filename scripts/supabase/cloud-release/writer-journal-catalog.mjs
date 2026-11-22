// Read installed privileges and catalog metadata only. Verify either side of
// each pinned SQL step, including prefixes being reconciled after interruption.
import assert from 'node:assert/strict';
import {canonical,sha} from '../current-archive/codec.mjs';

const privileges=[
  ['burimunsi_accounts','INSERT',1,'id collection_id principal_user_id phone name role capabilities pin_hash created_at updated_at'],
  ['burimunsi_accounts','UPDATE',1,'name phone capabilities pin_hash active removed version credential_version updated_at'],
  ['burimunsi_sessions','INSERT',1,'id collection_id account_id grant_id installation_id credential_version grant_version token_hash created_at expires_at principal_user_id'],
  ['burimunsi_sessions','UPDATE',1,'revoked'],
  ['burimunsi_scopes','UPDATE',1,'active_binding_id binding_version version'],
  ['storage_payload_reservations','UPDATE',1,'sealed_body cleared_at'],
  ['storage_put_intents','UPDATE',1,'state attempts active_attempt last_outcome updated_at upload_unresolved delete_tombstone'],
  ['storage_upload_attempts','UPDATE',1,'outcome completed_at'],
  ['storage_delete_intents','UPDATE',1,'state last_outcome absence_proof committed_at'],
  ['storage_namespace','INSERT',3,'singleton origin bucket'],
  ['storage_payload_reservations','INSERT',3,'object_key source_fingerprint scope aad key_id plaintext_sha256 sealed_body'],
  ['storage_put_intents','INSERT',3,'operation_id object_key fingerprint sha256 size scope http_metadata custom_metadata'],
  ['storage_upload_attempts','INSERT',3,'id operation_id'],
  ['storage_objects','INSERT',3,'object_key operation_id fingerprint sha256 size scope http_metadata custom_metadata etag'],
  ['storage_delete_intents','INSERT',3,'operation_id object_key fingerprint expected_sha256 scope'],
];

const rowsFn='private._retention_manifest_rows_v2(text)';
const linksFn='private._burimunsi_retention_journal_links_v1(text,text)';
const initialRows='25597e57accb602949e65108db895113ee66e657b5c20e4cc1fbbdabf266973a';
const linkedRows='6a1435008e15ffe4f7ba1d7921a1b098b1adb3f0032745031d3e069b19962710';
const recipientLinks='3444eca5abdac7e8e54df3a96556a63077a87e48c4e4ba8cf120ebd08b8fde55';
const postingLinks='9b4f3d4ef80a5df6396c44952bbedd517b01e6566e0f7fb10fb83fecc531c741';
const manifestCatalog='9476c7ee0cd5bd1b3e0165553cbf1721c67f1dbd1188779aebab30d00bacee2d';
const relations=['private.burimunsi_observation_retry_commands','private.burimunsi_payment_sms_deliveries'];
const indexes=[
  ['burimunsi_observation_retry_subject_links','burimunsi_observation_retry_commands',['collection_id','account_id','request_id']],
  ['burimunsi_payment_sms_recipient_links','burimunsi_payment_sms_deliveries',['recipient_user_id','attempt_id']],
];

// Ordered grants change only at steps 1 and 3. The retention catalog changes
// only at steps 2 and 4. A newly added column also changes the role digest.
const broadRole='1051be2b3d4692d2084b0e4a4ea805f22ff4f3c9aea359b097c5a7c44be01e24';
const scopedRole='ee2428f5eee7009519a893bcfd0d404ab36cd96338b1a3dc7da1ba386f3c8c02';
const storageRole='6b7e23608b8b699fcaaf68d309fd18fd900eda6a8b0bf2783b7ca78fcecbb5a6';
const originalCatalog='fa56621725ce623a0b8cfbefe979ee8e51bd99fbb9af0e987279340b0d6edf49';
const recipientCatalog='8c038a47102c4e00b86d410adb2d7d54f4209abd5103dae18798e91fb49aa6d6';
const postingCatalog='8460a8a9e391d8e6e0b81b72ef2e9d96f6215630c427c04c68f906187c230c39';

export async function readWriterJournalCatalog(db, completed) {
  const {rows:[role]}=await db.query(`SELECT rolname,rolsuper,rolbypassrls,pg_has_role(oid,'postgres','MEMBER') AS postgres_member
    FROM pg_roles WHERE rolname='collect_runtime'`);
  assert.ok(role && !role.rolsuper && !role.rolbypassrls && !role.postgres_member,'writer_journal_runtime_role_changed');
  const {rows:grants}=await db.query(`SELECT input.relation,input.privilege,c.relkind,pg_get_userbyid(c.relowner) AS owner,
    has_table_privilege('collect_runtime',c.oid,input.privilege) AS tablewide,
    array_agg(a.attname::text ORDER BY a.attname COLLATE "C") AS columns,
    array_agg(a.attname::text ORDER BY a.attname COLLATE "C") FILTER
      (WHERE has_column_privilege('collect_runtime',c.oid,a.attnum,input.privilege)) AS writable,
    bool_or(has_column_privilege('collect_runtime',c.oid,a.attnum,input.privilege||' WITH GRANT OPTION')) AS delegable
    FROM unnest($1::text[],$2::text[]) WITH ORDINALITY AS input(relation,privilege,ordinal)
    JOIN pg_class c ON c.relnamespace='private'::regnamespace AND c.relname=input.relation
    JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
    GROUP BY input.ordinal,input.relation,input.privilege,c.oid ORDER BY input.ordinal`,
  [privileges.map(r=>r[0]),privileges.map(r=>r[1])]);
  assert.equal(grants.length,privileges.length,'writer_journal_grant_target_missing');
  for (const [i,g] of grants.entries()) {
    const [relation,privilege,step,allowed]=privileges[i];
    assert.ok(g.relation===relation && g.privilege===privilege && g.owner==='postgres' && g.relkind==='r'
      && g.delegable===false && g.tablewide===(completed<step),'writer_journal_grant_changed_'+relation+'_'+privilege);
    assert.deepEqual(g.writable,completed<step?g.columns:allowed.split(' ').sort(),'writer_journal_columns_changed_'+relation+'_'+privilege);
  }
  const {rows:functions}=await db.query(`SELECT input.signature,pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.provolatile,
    p.proacl::text AS acl,p.proconfig,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS body_sha256,
    EXISTS(SELECT FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role','collect_runtime','collect_importer')
      AND has_function_privilege(r.oid,p.oid,'EXECUTE')) AS exposed
    FROM unnest($1::text[]) WITH ORDINALITY input(signature,ordinal) JOIN pg_proc p ON p.oid=to_regprocedure(input.signature)
    ORDER BY input.ordinal`,[[rowsFn,linksFn]]);
  assert.equal(functions.length,completed<2?1:2,'writer_journal_function_set_changed');
  for (const [i,f] of functions.entries()) {
    assert.ok(f.signature===(i===0?rowsFn:linksFn) && f.owner==='postgres' && f.prosecdef && f.provolatile==='s'
      && f.acl==='{postgres=X/postgres}' && f.exposed===false,'writer_journal_function_access_changed');
    assert.deepEqual(f.proconfig,[i===0?'search_path=app, pg_catalog, pg_temp':'search_path=pg_catalog, pg_temp']);
    assert.equal(f.body_sha256,i===0?(completed<2?initialRows:linkedRows):(completed<4?recipientLinks:postingLinks),'writer_journal_function_body_changed');
  }
  const {rows:[catalog]}=await db.query(`SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') AS body_sha256
    FROM pg_proc WHERE oid=to_regprocedure('private._retention_manifest_catalog_v2()')
      AND pg_get_userbyid(proowner)='postgres' AND NOT prosecdef AND provolatile='i'
      AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}'`);
  assert.equal(catalog?.body_sha256,manifestCatalog,'writer_journal_manifest_catalog_changed');
  const {rows:dispositions}=await db.query(`SELECT item->>'relation' AS relation,item->>'scope' AS scope,item->'blocked' AS blocked
    FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') item
    WHERE item->>'relation'=ANY($1) ORDER BY (item->>'relation') COLLATE "C"`,[relations]);
  assert.deepEqual(dispositions,relations.map(relation=>({relation,scope:'unmapped_private',blocked:true})),'writer_journal_retention_disposition_changed');
  const {rows:links}=await db.query(`SELECT x.relname AS name,t.relname AS relation,
    ARRAY(SELECT pg_get_indexdef(i.indexrelid,n,true) FROM generate_series(1,i.indnatts) n ORDER BY n) AS columns,
    i.indisvalid AND i.indisready AND i.indislive AND NOT i.indisunique AND i.indexprs IS NULL AND i.indpred IS NULL
      AND i.indnatts=i.indnkeyatts AND m.amname='btree' AND t.relnamespace='private'::regnamespace AS valid
    FROM pg_class x JOIN pg_index i ON i.indexrelid=x.oid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_am m ON m.oid=x.relam
    WHERE x.relnamespace='private'::regnamespace AND x.relname=ANY($1) ORDER BY x.relname COLLATE "C"`,[indexes.map(row=>row[0])]);
  assert.deepEqual(links,completed<2?[]:indexes.map(([name,relation,columns])=>({name,relation,columns,valid:true})),'writer_journal_link_index_changed');
  const {rows:[bucket]}=await db.query(`SELECT has_schema_privilege('postgres','storage','USAGE')
    AND has_column_privilege('postgres','storage.buckets','id','SELECT')
    AND has_column_privilege('postgres','storage.buckets','public','SELECT')
    AND EXISTS (SELECT FROM private.storage_namespace n JOIN storage.buckets b ON b.id=n.bucket
      WHERE n.singleton AND b.public IS FALSE) AS inventory_owner_can_read_bucket`);
  assert.equal(bucket.inventory_owner_can_read_bucket,true,'writer_journal_bucket_read_required');
  const role_sha256=sha(canonical({role,grants})),retention_sha256=sha(canonical({functions,dispositions,links,bucket}));
  assert.equal(role_sha256,[broadRole,scopedRole,scopedRole,storageRole,storageRole][completed],'writer_journal_role_fingerprint_changed');
  assert.equal(retention_sha256,[originalCatalog,originalCatalog,recipientCatalog,recipientCatalog,postingCatalog][completed],
    'writer_journal_retention_fingerprint_changed');
  return {role_sha256,retention_sha256,manifest_catalog_sha256:catalog.body_sha256};
}
