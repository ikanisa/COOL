import postgres from 'npm:postgres@3.4.7';
import {applicationWorkTuple,fenceFailure,reserveDatabaseConnection,FENCE_IO_TIMEOUT_MS} from './application-fence.js';

// Only Edge holds this database credential. SQL strings come from reviewed
// server modules; this adapter is never an HTTP/RPC accepting client SQL.
const pools = new Map();
export function connection(url) { return configuredConnection(url,false); }
export function fenceConnection(url) { return configuredConnection(url,true); }
function configuredConnection(url,control) {
  if (!url) throw new Error('COLLECT_DATABASE_URL is required.');
  const target=new URL(url);const local=['127.0.0.1','localhost','::1','[::1]'].includes(target.hostname);if(!['postgres:','postgresql:'].includes(target.protocol))throw new Error('Invalid database URL.');
  const poolKey=(control?'control:':'business:')+url;
  if (!pools.has(poolKey)) {const options={max: control ? 1 : 4, prepare: false,
    idle_timeout: 20, connect_timeout: 10, ssl: local ? false : {rejectUnauthorized: true},
    types: {numeric: {to:1700,from:[1700],serialize:String,parse:value=>{const n=Number(value);if(!/^-?\d+(?:\.0+)?$/.test(value)||!Number.isSafeInteger(n))throw new Error('integer_out_of_range');return n;}},bigint: {to: 20, from: [20], serialize: String, parse: value => {
      const n = Number(value); if (!Number.isSafeInteger(n)) throw new Error('integer_out_of_range'); return n;
    }}}, onnotice: () => {}};
    pools.set(poolKey,control?leaseOwnedControlPool(()=>postgres(url,options)):postgres(url,options));
  }
  return pools.get(poolKey);
}

// Eight local slots include connection setup, WORK, original cleanup and
// quarantined pools. A settled admission does not free this separate bound.
// Control sockets have one lease owner and no retained warm idle lifetime.
export function leaseOwnedControlPool(createPool) {
  const capacity=8,waiting=[],owned=new Set();let occupied=0,ending=false;
  const unavailable=()=>new Error('collect_fence_unavailable');
  function pump(){
    while(!ending&&occupied<capacity&&waiting.length){
      const waiter=waiting.shift();clearTimeout(waiter.timer);
      if(performance.now()>=waiter.deadline){waiter.reject(unavailable());continue;}
      occupied++;
      void acquire().then(waiter.resolve,waiter.reject);
    }
  }
  function retire(entry){
    if(!entry.retirement)entry.retirement=Promise.resolve().then(()=>entry.pool.end()).then(()=>{
      owned.delete(entry);occupied--;pump();
    });
    // Keep the original end promise/options. Lost or rejected ACK quarantines
    // the slot; neither normal release nor shutdown may dispatch another end.
    void entry.retirement.catch(()=>{});return entry.retirement;
  }
  async function acquire(){
    let entry;
    try{
      entry={pool:createPool(),returned:false,retirement:null};owned.add(entry);
      const tx=await entry.pool.reserve();
      return new Proxy(tx,{get(target,key){
        if(key==='release')return()=>{if(entry.returned)return;entry.returned=true;target.release();void retire(entry);};
        return Reflect.get(target,key,target);
      }});
    }catch(error){if(entry)void retire(entry);else{occupied--;pump();}throw error;}
  }
  return Object.freeze({capacity,queueCapacity:capacity,get pendingReservations(){return waiting.length;},
    reserve(){
      if(ending)return Promise.reject(unavailable());
      return new Promise((resolve,reject)=>{
        if(occupied<capacity){occupied++;void acquire().then(resolve,reject);return;}
        if(waiting.length>=capacity){reject(unavailable());return;}
        const waiter={resolve,reject,timer:null,deadline:performance.now()+FENCE_IO_TIMEOUT_MS};
        waiter.timer=setTimeout(()=>{const i=waiting.indexOf(waiter);if(i>=0){waiting.splice(i,1);reject(unavailable());}},FENCE_IO_TIMEOUT_MS);
        waiting.push(waiter);
      });
    },
    async end(options){
      ending=true;for(const waiter of waiting.splice(0)){clearTimeout(waiter.timer);waiter.reject(unavailable());}
      // Shutdown cannot initiate end for setup, WORK or an unacknowledged
      // rollback. Only original release/setup failure may start retirement.
      const entries=[...owned];if(entries.some(entry=>!entry.retirement))throw unavailable();
      const completion=Promise.all(entries.map(entry=>entry.retirement));let timer;
      try{await Promise.race([completion,new Promise((_,reject)=>{timer=setTimeout(()=>reject(unavailable()),FENCE_IO_TIMEOUT_MS);})]);}finally{clearTimeout(timer);}
      if(owned.size)throw unavailable();
    }
  });
}

function quotedEnd(sql, i) {
  const quote = sql[i++];
  while (i < sql.length) { if (sql[i++] === quote) { if (sql[i] === quote) { i++; continue; } return i; } }
  throw new Error('Unclosed SQL literal.');
}
export function compileSql(input, values = []) {
  if (typeof input !== 'string' || !input.trim()) throw new Error('Invalid server SQL.');
  let out = '', index = 0;
  for (let i = 0; i < input.length;) {
    if (input[i] === "'" || input[i] === '"') { const end = quotedEnd(input, i); out += input.slice(i, end); i = end; continue; }
    if (input.slice(i,i+2) === '--') { const end = input.indexOf('\n',i); if (end < 0) break; out += '\n'; i=end+1; continue; }
    if (input[i] === '?') { out += '$' + (++index); i++; continue; }
    out += input[i++];
  }
  if (index !== values.length) throw new Error('Server SQL parameter count mismatch.');
  out=out.replace(/(\$\d+)\s+IS\s+(NOT\s+)?NULL/gi,'$1::text IS $2NULL');
  out = out.replace(/\bCOLLATE\s+BINARY\b/gi, 'COLLATE "C"')
    .replace(/\bIS\s+NOT\s+(\$\d+)/gi, 'IS DISTINCT FROM $1')
    .replace(/\bIS\s+(\$\d+|json_extract\s*\()/gi, 'IS NOT DISTINCT FROM $1')
    .replace(/\bmax\(([^(),]+),([^()]+|unixepoch\(\))\)/gi, 'greatest($1,$2)');
  out = out.replace(/\bGLOB\s+'((?:[^']|'')*)'/gi, (_, pattern) => {
    // Current source uses SQLite's ASCII glob, translated to anchored POSIX RE.
    let re = ''; for (const c of pattern) re += c === '*' ? '.*' : c === '?' ? '.' : /[.()+{}|^$\\]/.test(c) ? '\\'+c : c;
    return "~ '^" + re + "$'";
  });
  out = out.replace(/\bNOT\s+~/gi, '!~');
  const ignore = /\bINSERT\s+OR\s+IGNORE\s+INTO\b/i.test(out);
  out = out.replace(/\bINSERT\s+OR\s+IGNORE\s+INTO\b/gi, 'INSERT INTO');
  if (ignore && !/\bON\s+CONFLICT\b/i.test(out)) out = out.replace(/(\s+RETURNING\b|;?\s*$)/i, ' ON CONFLICT DO NOTHING$1');
  // SQLite preserves JSON scalar storage classes. Its JSON string "1" must
  // not satisfy a numeric flag =1. Select a typed numeric extractor only when
  // the comparison operand is numeric; balancing avoids nested-expression bugs.
  let cursor=0;
  while(cursor<out.length){
    if(out[cursor]==="'"||out[cursor]==='"'){cursor=quotedEnd(out,cursor);continue;}
    if(out.slice(cursor,cursor+13).toLowerCase()!=='json_extract('){cursor++;continue;}
    let end=cursor+13,depth=1;while(end<out.length&&depth){if(out[end]==="'"||out[end]==='"'){end=quotedEnd(out,end);continue;}if(out[end]==='(')depth++;if(out[end]===')')depth--;end++;}
    const compare=/^\s*(?:=|!=|<>|<=|>=|<|>)\s*(-?\d+(?:\.\d+)?|\$(\d+))\b/.exec(out.slice(end));
    if(compare&&(!compare[2]||typeof values[Number(compare[2])-1]==='number')){out=out.slice(0,cursor)+'json_numeric('+out.slice(cursor+13);cursor=end;}
    else cursor=end;
  }
  const catalog=`(SELECT 'table'::text AS type,c.relname::text AS name,c.relname::text AS tbl_name,(SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod),',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) AS sql FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relkind='r' UNION ALL SELECT 'index',c.relname,t.relname,pg_get_indexdef(c.oid) FROM pg_class c JOIN pg_index i ON i.indexrelid=c.oid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='app' UNION ALL SELECT 'trigger',g.tgname,c.relname,pg_get_triggerdef(g.oid) FROM pg_trigger g JOIN pg_class c ON c.oid=g.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND NOT g.tgisinternal UNION ALL SELECT 'view',c.relname,c.relname,pg_get_viewdef(c.oid) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relkind='v')`;
  out = out.replace(/\bsqlite_(master|schema)\b/g,catalog).replace(/\bsqlite_sequence\b/g,`(SELECT c.relname::text AS name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relkind='S')`);
  const pragma=/^\s*PRAGMA\s+table_info\("([a-z_]+)"\)\s*$/i.exec(out);
  if(pragma)out=`SELECT a.attnum-1 AS cid,a.attname::text AS name,format_type(a.atttypid,a.atttypmod) AS type FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relname='${pragma[1]}' AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum`;
  out=out.replace(/\bjson_object\(/g,'json_build_object(').replace(/printf\('RWF %d credited to %s\.'/g,"format('RWF %s credited to %s.'");
  return {text: out, values: values.map(v => v === undefined ? null : v)};
}

class Statement {
  constructor(db, sql, values = []) { this.db=db; this.sql=sql; this.values=values; }
  bind(...values) { return new Statement(this.db,this.sql,values); }
  async all() { return this.db.execute(this); }
  async first(column) { const row=(await this.all()).results[0] ?? null; return column && row ? row[column] : row; }
  async run() { return this.all(); }
  async raw() { return (await this.all()).results.map(Object.values); }
}
export class PostgresDatabase {
  constructor(sql, claims = {}, work = null) { this.sql=sql; this.claims=claims; this.applicationWork=work; }
  setApplicationWork(work) { applicationWorkTuple(work); this.applicationWork=work; }
  prepare(text) { return new Statement(this,text); }
  withSession() { return this; }
  setClaims(claims) { this.claims=claims; }
  async readContext(tx) {
    // This path cannot grant write authority: the server must already enforce a
    // genuine read-only repeatable-read transaction before role/claims setup.
    const work=this.applicationWork;if(!work)throw fenceFailure(null);await work.assert();
    const mode=await tx.unsafe('SHOW transaction_read_only'),isolation=await tx.unsafe('SHOW transaction_isolation');
    if(mode[0]?.transaction_read_only!=='on'||isolation[0]?.transaction_isolation!=='repeatable read')throw fenceFailure(null);
    await tx`set local role collect_runtime`;
    await tx`select set_config('search_path','app,public,pg_catalog',true),set_config('request.jwt.claims',${JSON.stringify(this.claims)},true),set_config('collect.edge_verified','true',true)`;
    await tx`set local statement_timeout='15s'`;
    await tx`set local lock_timeout='5s'`;
  }
  async context(tx) {
    const work=this.applicationWork;if(!work)throw fenceFailure(null);await work.assert();const tuple=applicationWorkTuple(work);
    await tx`set local role collect_runtime`;
    await tx`select set_config('search_path','app,public,pg_catalog',true), set_config('request.jwt.claims',${JSON.stringify(this.claims)},true), set_config('collect.edge_verified','true',true)`;
    await tx`select set_config('collect.fence_admission_id',${tuple[0]},true),set_config('collect.fence_epoch',${String(tuple[1])},true),set_config('collect.fence_source_sha256',${tuple[2]},true)`;
    try {const rows=await tx`select private.collect_fence_assert_write(${tuple[0]}::uuid,${tuple[1]}::bigint,${tuple[2]}::text) as result`;const result=rows[0]?.result;if(result?.contractVersion!==1||result.epoch!==tuple[1]||!['open','quiescing'].includes(result.mode))throw new Error('collect_fence_unavailable');}catch(error){throw fenceFailure(error);}
    await tx`set local statement_timeout='15s'`;
    await tx`set local lock_timeout='5s'`;
  }
  async statement(tx, statement) {
    const q=compileSql(statement.sql,statement.values);
    let result;try{result=await tx.unsafe(q.text,q.values);}catch(error){error.collectSql=q.text;throw error;}
    await tx`select set_config('collect.last_changes',${String(result.count ?? result.length)},true)`;
    return {success:true,results:Array.from(result),meta:{changes:result.count ?? result.length}};
  }
  transaction(fn) {
    const work=this.applicationWork;if(!work)throw fenceFailure(null);
    return work.waitUntil((async()=>{
      await work.assert();const tx=await reserveDatabaseConnection(this.sql);let idleConfirmed=false;
      try{await tx.unsafe('BEGIN ISOLATION LEVEL READ COMMITTED');const result=await fn(tx);await tx.unsafe('COMMIT');idleConfirmed=true;return result;}
      catch(error){try{await tx.unsafe('ROLLBACK');idleConfirmed=true;}catch{work.abandon('work_lost');}throw error;}
      // reserve().release() does not reset a transaction in postgres3.4.7.
      // Quarantine an unconfirmed connection; never let a later request commit it.
      finally{if(idleConfirmed)tx.release();}
    })());
  }
  async execute(statement) { return this.transaction(async tx=>{await this.context(tx);return this.statement(tx,statement);}); }
  async batch(statements) {
    return this.transaction(async tx=>{
      await this.context(tx);
      // D1 serialized all mutations. Serialize financial and authority batches
      // until reviewed per-group locking proves equivalent under concurrency.
      await tx`select pg_advisory_xact_lock(734636924058501::bigint)`;
      const result=[];for(const s of statements) result.push(await this.statement(tx,s));return result;
    });
  }
  async query(text, values=[]) { return this.execute(this.prepare(text).bind(...values)); }
}
