// Fixed read-only source reader. Sensitive records are returned only to the
// trusted caller in memory; never log, persist, or serialize this return value.
import {spawnSync} from 'node:child_process';
import {GRAPH, inspectSourceGraph} from './compile.mjs';

const name = table => {
  if (!/^(app|private)\.[a-z_][a-z0-9_]*$/.test(table) || !GRAPH.includes(table)) throw Error('source_relation_refused');
  return table;
};
const quote = value => "'" + value.replaceAll("'", "''") + "'";
const tables = GRAPH.map(name);
const literalArray = 'ARRAY[' + tables.map(quote).join(',') + ']::text[]';
const bounds = tables.map(t => `SELECT count(*)::bigint n,coalesce(sum(pg_column_size(r)),0)::bigint bytes,coalesce(max(pg_column_size(r)),0)::bigint largest FROM ONLY ${t} r`).join(' UNION ALL ');
const payload = tables.map(t => `${quote(t)},coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM ONLY ${t} r),'[]'::jsonb)`).join(',');
// Identical, independently queried catalogue on the fenced managed target.
export const TARGET_CATALOGUE_SQL = `WITH metadata AS (
 SELECT n,to_regclass(n) AS oid FROM unnest(${literalArray}) n
), cat AS (
 SELECT coalesce(jsonb_object_agg(n,jsonb_build_object(
  'columns',coalesce((SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
   'nullable',NOT a.attnotnull,'generated',a.attgenerated<>'','identity',a.attidentity,
   'defaultHash',CASE WHEN d.oid IS NULL THEN NULL ELSE encode(sha256(convert_to(pg_get_expr(d.adbin,d.adrelid),'UTF8')),'hex') END) ORDER BY a.attnum)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid=m.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
  'foreignKeys',coalesce((SELECT jsonb_agg(jsonb_build_object('target',pn.nspname||'.'||p.relname,'deferrable',k.condeferrable,
   'columns',(SELECT jsonb_agg(a.attname ORDER BY x.ord) FROM unnest(k.conkey) WITH ORDINALITY x(num,ord) JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=x.num),
   'targetColumns',(SELECT jsonb_agg(a.attname ORDER BY x.ord) FROM unnest(k.confkey) WITH ORDINALITY x(num,ord) JOIN pg_attribute a ON a.attrelid=k.confrelid AND a.attnum=x.num)) ORDER BY k.conname)
   FROM pg_constraint k JOIN pg_class p ON p.oid=k.confrelid JOIN pg_namespace pn ON pn.oid=p.relnamespace
   WHERE k.conrelid=m.oid AND k.contype='f'),'[]'::jsonb))), '{}'::jsonb) AS catalogue,
 count(*) FILTER(WHERE oid IS NULL) AS missing FROM metadata m
) SELECT catalogue,missing FROM cat`;
// All statements run in a single read-only, repeatable-read source snapshot.
const SQL = `BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='30s';
SET LOCAL TIME ZONE 'UTC';
WITH bounds AS (${bounds}), metadata AS (
 SELECT n, to_regclass(n) AS oid FROM unnest(${literalArray}) n
), cat AS (
 SELECT coalesce(jsonb_object_agg(n,jsonb_build_object(
  'columns',coalesce((SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
   'nullable',NOT a.attnotnull,'generated',a.attgenerated<>'','identity',a.attidentity,
   'defaultHash',CASE WHEN d.oid IS NULL THEN NULL ELSE encode(sha256(convert_to(pg_get_expr(d.adbin,d.adrelid),'UTF8')),'hex') END) ORDER BY a.attnum)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid=m.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
  'foreignKeys',coalesce((SELECT jsonb_agg(jsonb_build_object('target',pn.nspname||'.'||p.relname,'deferrable',k.condeferrable,
   'columns',(SELECT jsonb_agg(a.attname ORDER BY x.ord) FROM unnest(k.conkey) WITH ORDINALITY x(num,ord) JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=x.num),
   'targetColumns',(SELECT jsonb_agg(a.attname ORDER BY x.ord) FROM unnest(k.confkey) WITH ORDINALITY x(num,ord) JOIN pg_attribute a ON a.attrelid=k.confrelid AND a.attnum=x.num)) ORDER BY k.conname)
   FROM pg_constraint k JOIN pg_class p ON p.oid=k.confrelid JOIN pg_namespace pn ON pn.oid=p.relnamespace
   WHERE k.conrelid=m.oid AND k.contype='f'),'[]'::jsonb))), '{}'::jsonb) AS catalogue,
 count(*) FILTER(WHERE oid IS NULL) AS missing FROM metadata m
)
SELECT CASE WHEN (SELECT missing FROM cat)>0 OR EXISTS(SELECT 1 FROM bounds WHERE n>256 OR largest>1048576)
 OR (SELECT coalesce(sum(bytes),0) FROM bounds)>8388608
 THEN jsonb_build_object('error','source_graph_missing_or_oversized')
 ELSE jsonb_build_object('tables',jsonb_build_object(${payload}),
  'catalogue',(SELECT catalogue FROM cat),
  'ownerIds',(SELECT coalesce(jsonb_agg(l.user_id),'[]'::jsonb) FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE a.role='owner'),
  'fenceModes',(SELECT coalesce(jsonb_agg(mode),'[]'::jsonb) FROM private.collect_fence_control),
  'activeAdmissions',(SELECT count(*) FROM private.collect_fence_admissions WHERE state='active'),
  'effectiveActiveAdmissions',(SELECT count(*) FROM private.collect_fence_admissions a
    WHERE a.state IN('active','unresolved') AND private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind) IS NOT TRUE)) END::text;
ROLLBACK;`;

export function captureLocalSource() {
  const result = spawnSync('docker', ['--context','colima-supabase-local','exec','-i','supabase_db_local-app',
    'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],
    {input:SQL, maxBuffer:16*1024*1024, timeout:45000});
  if (result.error || result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length > 16*1024*1024) throw Error('source_read_unavailable');
  let value;
  try { value = JSON.parse(result.stdout.toString('utf8')); } catch { throw Error('source_response_invalid'); }
  if (value.error || !Array.isArray(value.ownerIds) || value.ownerIds.length !== 1 ||
      typeof value.ownerIds[0] !== 'string' || !Array.isArray(value.fenceModes) || value.fenceModes.length !== 1 ||
      !Number.isSafeInteger(value.activeAdmissions) || !Number.isSafeInteger(value.effectiveActiveAdmissions)) throw Error('source_state_unavailable');
  return {snapshot:{tables:value.tables},sourceCatalog:value.catalogue,sourceOwnerId:value.ownerIds[0],
    fenceMode:value.fenceModes[0],activeAdmissions:value.activeAdmissions,effectiveActiveAdmissions:value.effectiveActiveAdmissions};
}

if (process.argv[1] && import.meta.url === new URL('file://' + process.argv[1]).href) {
  try {
    const captured = captureLocalSource(), summary = inspectSourceGraph(captured.snapshot);
    console.log(JSON.stringify({...summary, fenceMode:captured.fenceMode, activeAdmissions:captured.activeAdmissions,
      effectiveActiveAdmissions:captured.effectiveActiveAdmissions,snapshotIsCutoverReady:false, targetChecked:false}));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
