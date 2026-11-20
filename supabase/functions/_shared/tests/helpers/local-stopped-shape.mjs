// Host fixture schema is derived from the candidate SQL, never an authority double.
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../../../migrations/20261110181002_collect_local_stopped_admission.sql',import.meta.url),'utf8');
const declaration=sql.match(/CREATE TABLE private\.collect_fence_local_stopped_admissions\(([\s\S]*?)\n\);/)[1];
export const localStoppedColumns=declaration.split('\n').flatMap(line=>{
 const column=line.trim().match(/^([a-z_][a-z_0-9]*) (uuid|text|bigint|jsonb|boolean|integer|timestamptz)\b/);
 return column?[`${column[1]}:${column[2]==='timestamptz'?'timestamp with time zone':column[2]}:${/NOT NULL|PRIMARY KEY/.test(line)}`]:[];
}).join(',');
