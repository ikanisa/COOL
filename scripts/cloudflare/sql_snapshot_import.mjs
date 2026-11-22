// Complete offline snapshots only. Migration statements retain installSql's API.
import {constants} from 'node:sqlite';
import {createHash} from 'node:crypto';
import {readFileSync,lstatSync,realpathSync} from 'node:fs';
import {createRequire} from 'node:module';
import {join,isAbsolute} from 'node:path';
const need=(ok,message)=>{if(!ok)throw Error(message);};
const sha=raw=>createHash('sha256').update(raw).digest('hex');
const pins={
 'package.json':{sha256:'777a844512eb61977eafad63daa5dcebc0f47bfe18f761e1106c05384d31b3fa',bytes:6863},
 'wrangler-dist/cli.js':{sha256:'fdc72018f9cdd5cecff191ec00876825ac90620113996c9bf7d343914fbc842d',bytes:15030585},
};
export function loadLockedSnapshotParser(directory){
 need(typeof directory==='string'&&isAbsolute(directory),'An explicit locked Wrangler SQL parser directory is required');
 for(const name of Object.keys(pins)){
  const path=join(directory,name),raw=readFileSync(path),s=lstatSync(path),p=pins[name];
  need(s.isFile()&&!s.isSymbolicLink()&&realpathSync(path)===path&&raw.length===p.bytes&&sha(raw)===p.sha256,'Locked Wrangler SQL parser bytes differ');
 }
 need(JSON.parse(readFileSync(join(directory,'package.json'))).version==='4.151.0','Locked Wrangler 4.151.0 is required');
 const split=createRequire(import.meta.url)(join(directory,'wrangler-dist/cli.js')).unstable_splitSqlQuery;
 need(typeof split==='function','Locked Wrangler SQL splitter is unavailable');return split;
}
// Only leading trivia is inspected for statement classification. SQL boundaries,
// quoted semicolons and trigger bodies belong to the locked Wrangler parser.
function head(sql){
 let value=sql.trimStart();
 for(;;){
  if(value.startsWith('--')){const end=value.indexOf('\n');value=end<0?'':value.slice(end+1).trimStart();}
  else if(value.startsWith('/*')){const end=value.indexOf('*/',2);need(end>=0,'Unterminated leading SQL comment');value=value.slice(end+2).trimStart();}
  else return value;
 }
}
function authorizer(code,a,b){
 const name=typeof a==='string'?a.toLowerCase():a,other=typeof b==='string'?b.toLowerCase():b;
 if(code===constants.SQLITE_ATTACH||code===constants.SQLITE_DETACH||code===constants.SQLITE_FUNCTION&&(name==='load_extension'||other==='load_extension')||code===constants.SQLITE_PRAGMA&&name==='writable_schema')return constants.SQLITE_DENY;
 if(code===constants.SQLITE_PRAGMA&&['foreign_keys','defer_foreign_keys'].includes(name)&&other!==null&&other!==undefined&&!['on','1','true'].includes(other))return constants.SQLITE_DENY;
 return constants.SQLITE_OK;
}
export function installSnapshotSql(db,sql,splitSqlQuery){
 need(typeof sql==='string'&&Buffer.byteLength(sql)>0&&Buffer.byteLength(sql)<=64*1024*1024,'A bounded complete SQL snapshot is required');
 need(typeof splitSqlQuery==='function','The admitted locked SQL splitter is required');
 let statements=splitSqlQuery(sql);need(Array.isArray(statements)&&statements.length>0&&statements.length<=20000&&statements.every(s=>typeof s==='string'&&s.length),'Snapshot SQL statement bound exceeded');
 const begin=s=>/^BEGIN(?:\s+TRANSACTION)?\s*;?\s*$/i.test(head(s));
 const commit=s=>/^(?:COMMIT|END)(?:\s+TRANSACTION)?\s*;?\s*$/i.test(head(s));
 if(begin(statements[0])){need(commit(statements.at(-1)),'Snapshot transaction wrapper is incomplete');statements=statements.slice(1,-1);}
 need(statements.every(s=>! /^(?:BEGIN|COMMIT|END|ROLLBACK|SAVEPOINT|RELEASE)\b/i.test(head(s))),'Embedded snapshot transaction control is forbidden');
 const table=s=>/^CREATE\s+TABLE\b/i.test(head(s));
 const ordered=[...statements.filter(table),...statements.filter(s=>!table(s))];
 db.setAuthorizer(authorizer);db.exec('PRAGMA foreign_keys=ON');
 need(db.prepare('PRAGMA foreign_keys').get().foreign_keys===1,'Snapshot foreign keys must be enabled before import');
 let began=false;
 try{
  db.exec('BEGIN');began=true;db.exec('PRAGMA defer_foreign_keys=ON');
  for(const statement of ordered)db.exec(statement);
  need(db.prepare('PRAGMA foreign_key_check').all().length===0,'Snapshot contains foreign key violations');
  need(db.prepare('PRAGMA integrity_check').get().integrity_check==='ok','Snapshot integrity verification failed');
  db.exec('COMMIT');began=false;
 }catch(error){if(began)db.exec('ROLLBACK');if(error?.code==='ERR_SQLITE_ERROR'&&error.message==='incomplete input')throw new Error('Snapshot SQL syntax error',{cause:error});throw error;}
 need(db.prepare('PRAGMA foreign_keys').get().foreign_keys===1,'Snapshot foreign key enforcement changed');
 return {schema_first:true,foreign_keys:1,foreign_key_violations:0,transaction_committed:true,statement_count:statements.length};
}
