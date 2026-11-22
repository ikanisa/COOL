// Catalog metadata shared by managed graph verification and local fixtures.
import {GRAPH} from './compile.mjs';

const name = table => {
  if (!/^(app|private)\.[a-z_][a-z0-9_]*$/.test(table) || !GRAPH.includes(table)) throw Error('source_relation_refused');
  return table;
};
const quote = value => "'" + value.replaceAll("'", "''") + "'";
const tables = GRAPH.map(name);
const literalArray = 'ARRAY[' + tables.map(quote).join(',') + ']::text[]';

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
