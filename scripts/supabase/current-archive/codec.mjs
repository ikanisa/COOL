import {createHash} from 'node:crypto';
export const PROJECT='rrlduytparvsjfmegalh';
export const FORMAT='collect.current-target.sql-archive.v3';
export const CONTROL_PROBES=Object.freeze({inside_rr_on_response_sha256:'648172fe47f5e306c020d0bf6348c774ef27f31afb923b6826f51f00da400ff2',outside_after_rollback_response_sha256:'d1076eef3f123a3147815c8e79d96057f8c66d083b6975fcb962d5bdc246f13e'});
export const HARD_CAPS=Object.freeze({tables:256,columns:256,rowsPerTable:10000,totalRows:50000,cellBytes:16*1024*1024,textBytes:64*1024*1024,serializedBytes:128*1024*1024,catalogRows:20000,catalogBytes:8*1024*1024,sequences:256});
export class ArchiveError extends Error{constructor(code){super(code);this.name='ArchiveError';this.code=code;}}
export const fail=code=>{throw new ArchiveError(code);};
export const need=(condition,code)=>{if(!condition)fail(code);};
export const HASH=/^[a-f0-9]{64}$/;
export const sha=value=>createHash('sha256').update(value).digest('hex');
export const plain=x=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype;
export function exact(x,names){need(plain(x)&&Object.keys(x).sort().join('\n')===[...names].sort().join('\n'),'SHAPE_INVALID');}
export function canonical(x){
 if(x===null||typeof x==='boolean')return JSON.stringify(x);
 if(typeof x==='string'){need(x.isWellFormed(),'UNICODE_INVALID');return JSON.stringify(x);}
 if(typeof x==='number'){need(Number.isSafeInteger(x),'METADATA_NUMBER_INVALID');return JSON.stringify(x);}
 if(Array.isArray(x))return '['+x.map(canonical).join(',')+']';
 need(plain(x),'VALUE_KIND_INVALID');return '{'+Object.keys(x).sort().map(k=>canonical(k)+':'+canonical(x[k])).join(',')+'}';
}
export function identifier(x){need(typeof x==='string'&&/^[a-z][a-z0-9_]{0,62}$/.test(x),'IDENTIFIER_INVALID');return '"'+x+'"';}
export function caps(options={}){need(plain(options)&&Object.keys(options).every(k=>k in HARD_CAPS),'CAP_UNKNOWN');const out={...HARD_CAPS,...options};for(const[k,v]of Object.entries(out))need(Number.isSafeInteger(v)&&v>0&&v<=HARD_CAPS[k],'CAP_INVALID');return out;}
function int(x){need(typeof x==='string'&&/^-?(?:0|[1-9][0-9]*)$/.test(x),'INTEGER_METADATA_INVALID');const n=Number(x);need(Number.isSafeInteger(n),'INTEGER_METADATA_INVALID');return n;}
// Fixed PostgreSQL17 built-ins only. Native output functions preserve bpchar
// trailing spaces and JSON lexical text, unlike generic conversion through JS.
const TYPES=new Map([
 [16,['bool','boolout']],[17,['bytea','byteaout']],[20,['int8','int8out']],
 [21,['int2','int2out']],[23,['int4','int4out']],[25,['text','textout']],[26,['oid','oidout']],
 [700,['float4','float4out']],[701,['float8','float8out']],
 [1042,['bpchar','bpcharout']],[1043,['varchar','varcharout']],
 [1082,['date','date_out']],[1083,['time','time_out']],
 [1114,['timestamp','timestamp_out']],[1184,['timestamptz','timestamptz_out']],
 [1266,['timetz','timetz_out']],[1700,['numeric','numeric_out']],
 [2950,['uuid','uuid_out']],[114,['json','json_out']],[3802,['jsonb','jsonb_out']],
]);
export function columnType(c){
 const oid=int(c.type_oid),mod=int(c.typmod),t=TYPES.get(oid);
 need(t&&c.type_schema==='pg_catalog'&&c.type_name===t[0]&&c.type_kind==='b'&&c.base_oid==='0'&&c.element_oid==='0'&&c.output_schema==='pg_catalog'&&c.output_name===t[1],'TYPE_UNSUPPORTED');
 let suffix='';
 if([1042,1043].includes(oid)){need(mod===-1||mod>=5&&mod<=10485764,'TYPEMOD_UNSUPPORTED');if(mod!==-1)suffix='('+(mod-4)+')';}
 else if([1083,1114,1184,1266].includes(oid)){need(mod===-1||mod>=0&&mod<=6,'TYPEMOD_UNSUPPORTED');if(mod!==-1)suffix='('+mod+')';}
 else if(oid===1700){if(mod!==-1){need(mod>=4,'TYPEMOD_UNSUPPORTED');const bits=mod-4,precision=(bits>>>16)&65535,raw=bits&2047,scale=raw>=1024?raw-2048:raw;need(precision>=1&&precision<=1000&&scale>=-1000&&scale<=1000&&((precision*65536+(scale&2047))+4)===mod,'TYPEMOD_UNSUPPORTED');suffix='('+precision+','+scale+')';}}
 else need(mod===-1,'TYPEMOD_UNSUPPORTED');
 return {oid,sql:'pg_catalog.'+t[0]+suffix,output:'pg_catalog.'+t[1]};
}
export function validateColumns(columns,limit=HARD_CAPS.columns){
 need(Array.isArray(columns)&&columns.length>0&&columns.length<=limit,'COLUMNS_BOUND');const names=new Set();let last=0;
 for(const c of columns){exact(c,['name','position','type_oid','typmod','type_schema','type_name','type_kind','base_oid','element_oid','output_schema','output_name','not_null','identity','generated','acl','default_expression','collation']);identifier(c.name);need(!names.has(c.name),'COLUMN_DUPLICATE');names.add(c.name);const n=int(c.position);need(n>last&&n<=1600,'COLUMN_POSITION_INVALID');last=n;need(typeof c.not_null==='boolean'&&typeof c.identity==='string'&&typeof c.generated==='string'&&(c.acl===null||typeof c.acl==='string')&&(c.default_expression===null||typeof c.default_expression==='string')&&(c.collation===null||typeof c.collation==='string'),'COLUMN_METADATA_INVALID');need(c.default_expression!=='__ARCHIVE_DESCRIPTOR_TOO_LARGE__','COLUMN_DESCRIPTOR_BOUND');columnType(c);}
 return columns;
}
export function outputExpression(column,alias='t'){const t=columnType(column);return 'pg_catalog.textin('+t.output+'('+alias+'.'+identifier(column.name)+'))';}
export function validateCell(value,c,limit=HARD_CAPS.cellBytes){
 if(value===null){need(!c.not_null,'NULL_NOT_ALLOWED');return null;}
 need(typeof value==='string'&&value.isWellFormed()&&!value.includes('\0')&&Buffer.byteLength(value)<=limit,'CELL_INVALID');
 const oid=columnType(c).oid;
 if([20,21,23].includes(oid)){need(/^-?(?:0|[1-9][0-9]*)$/.test(value),'INTEGER_TEXT_INVALID');const n=BigInt(value),range=oid===20?[-9223372036854775808n,9223372036854775807n]:oid===21?[-32768n,32767n]:[-2147483648n,2147483647n];need(n>=range[0]&&n<=range[1],'INTEGER_RANGE_INVALID');}
 // OIDs are exact unsigned32 native identity values. Retain oidout's canonical
 // decimal text; never accept signed PostgreSQL input aliases or coerce to JS.
 if(oid===26){need(/^(?:0|[1-9][0-9]*)$/.test(value),'OID_TEXT_INVALID');need(value.length<=10&&BigInt(value)<=4294967295n,'OID_RANGE_INVALID');}
 if(oid===16)need(value==='t'||value==='f','BOOLEAN_TEXT_INVALID');
 if(oid===17)need(/^\\x(?:[a-f0-9]{2})*$/.test(value),'BYTEA_TEXT_INVALID');
 if(oid===2950)need(/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(value),'UUID_TEXT_INVALID');
 if([1700,700,701].includes(oid))need(/^(?:NaN|-?Infinity|-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)$/.test(value),'NUMBER_TEXT_INVALID');
 // JSON and time text are never parsed/re-serialized in JS: PG validates native
 // input on roundtrip, and its own output must match the original exact text.
 return value;
}
export function rowHash(columns,cells){need(Array.isArray(cells)&&cells.length===columns.length,'ROW_WIDTH_INVALID');return sha(canonical(columns.map((c,i)=>[c.name,c.type_oid,c.typmod,validateCell(cells[i],c)])));}
export function sealTable(table,limit=HARD_CAPS){
 need(['app','private'].includes(table.schema)&&['r','p'].includes(table.kind),'TABLE_SCOPE_INVALID');identifier(table.name);validateColumns(table.columns,limit.columns);need(Array.isArray(table.rows)&&table.rows.length<=limit.rowsPerTable,'ROWS_BOUND');
 const rows=table.rows.map(cells=>{need(Array.isArray(cells)&&cells.length===table.columns.length,'ROW_WIDTH_INVALID');cells.forEach((v,i)=>validateCell(v,table.columns[i],limit.cellBytes));return {cells,sha256:rowHash(table.columns,cells)};});
 rows.sort((a,b)=>a.sha256<b.sha256?-1:a.sha256>b.sha256?1:Buffer.compare(Buffer.from(canonical(a.cells)),Buffer.from(canonical(b.cells))));
 const body={schema:table.schema,name:table.name,kind:table.kind,columns:table.columns,rows,row_count:rows.length};return {...body,sha256:sha(canonical(body))};
}
export function validateSnapshot(x,limits={}){
 const l=caps(limits);exact(x,['format','project_ref','runtime_source_sha256','restore_authority','fixture','postgres','migrations','tables','catalog','catalog_sha256','sequences','sequences_every_value_stable','limits','proof_limits','management_provenance']);need(typeof x.fixture==='boolean'&&canonical(caps(x.limits))===canonical(x.limits)&&Array.isArray(x.proof_limits)&&x.proof_limits.every(v=>typeof v==='string'),'SNAPSHOT_METADATA_INVALID');need(plain(x)&&x.format===FORMAT&&x.project_ref===PROJECT&&HASH.test(x.runtime_source_sha256??'')&&x.restore_authority===false,'SNAPSHOT_INVALID');
 need(/^17[0-9]{4}$/.test(x.postgres?.server_version_num??'')&&x.postgres.server_encoding==='UTF8'&&!Object.hasOwn(x.postgres,'rolled_back')&&x.postgres.row_security==='off'&&x.postgres.read_only==='on'&&x.postgres.isolation==='repeatable read'&&x.postgres.timezone==='UTC'&&x.postgres.date_style==='ISO, YMD'&&x.postgres.bytea_output==='hex'&&x.postgres.extra_float_digits==='3'&&x.postgres.client_encoding==='UTF8'&&x.postgres.interval_style==='postgres','SNAPSHOT_CONTEXT_INVALID');
 exact(x.management_provenance,['endpoint','response_shape_simulated','request_read_only','request_sql_sha256','http_status','trailing_rollback_requested','native_rollback_command_complete_observed','control_probes']);need(x.management_provenance.endpoint===(x.fixture?'synthetic-local-node-pg':'https://api.supabase.com/v1/projects/'+PROJECT+'/database/query')&&x.management_provenance.response_shape_simulated===x.fixture&&x.management_provenance.request_read_only===true&&HASH.test(x.management_provenance.request_sql_sha256??'')&&x.management_provenance.http_status===201&&x.management_provenance.trailing_rollback_requested===true&&x.management_provenance.native_rollback_command_complete_observed===false&&canonical(x.management_provenance.control_probes)===canonical(CONTROL_PROBES),'MANAGEMENT_PROVENANCE_INVALID');
 need(x.fixture?/^collect_archive_source_[a-f0-9]{32}_test$/.test(x.postgres.database??'')&&['127.0.0.1','::1'].includes(x.postgres.server_address):x.postgres.database==='postgres','SOURCE_DATABASE_INVALID');
 need(Array.isArray(x.tables)&&x.tables.length>0&&x.tables.length<=l.tables,'TABLES_BOUND');const seen=new Set();let rows=0,textBytes=0;
 for(const table of x.tables){exact(table,['schema','name','kind','columns','rows','row_count','sha256']);const key=table.schema+'.'+table.name;need(!seen.has(key),'TABLE_DUPLICATE');seen.add(key);const re=sealTable({...table,rows:table.rows.map(r=>{exact(r,['cells','sha256']);need(rowHash(table.columns,r.cells)===r.sha256,'ROW_HASH_INVALID');return r.cells;})},l);need(canonical(re)===canonical(table),'TABLE_HASH_INVALID');rows+=table.rows.length;for(const r of table.rows)for(const cell of r.cells)if(cell!==null)textBytes+=Buffer.byteLength(cell);}
 need(rows<=l.totalRows&&textBytes<=l.textBytes,'TOTAL_DATA_BOUND');
 need(Array.isArray(x.catalog)&&x.catalog.length<=l.catalogRows&&Buffer.byteLength(canonical(x.catalog))<=l.catalogBytes&&sha(canonical(x.catalog))===x.catalog_sha256,'CATALOG_BOUND_OR_HASH');for(const r of x.catalog){exact(r,['category','identity','definition']);need(typeof r.category==='string'&&typeof r.identity==='string'&&typeof r.definition==='string','CATALOG_INVALID');}
 need(Array.isArray(x.sequences)&&x.sequences.length<=l.sequences&&x.sequences_every_value_stable===true,'SEQUENCE_INVALID');
 need(Array.isArray(x.migrations)&&x.migrations.length>=1&&x.migrations.length<=32,'MIGRATIONS_INVALID');let lastMigration='';for(const m of x.migrations){exact(m,['version','name','sha256','observed_record_sha256','observed_record']);need(/^[0-9]{14}$/.test(m.version)&&m.version>lastMigration&&/^[a-z0-9_]+$/.test(m.name)&&HASH.test(m.sha256??'')&&typeof m.observed_record==='string'&&HASH.test(m.observed_record_sha256??'')&&sha(m.observed_record)===m.observed_record_sha256,'MIGRATIONS_INVALID');lastMigration=m.version;}
 need(Buffer.byteLength(canonical(x))<=l.serializedBytes,'SNAPSHOT_BYTES_BOUND');return x;
}
