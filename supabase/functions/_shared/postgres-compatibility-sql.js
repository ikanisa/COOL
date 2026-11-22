// Translate the SQL dialect used by the existing compatibility statements.
function quotedEnd(sql, i) {
  const quote = sql[i++];
  while (i < sql.length) { if (sql[i++] === quote) { if (sql[i] === quote) { i++; continue; } return i; } }
  throw new Error('Unclosed SQL literal.');
}
function sqlTriviaEnd(sql, i) {
  while(i<sql.length){
    if(/\s/.test(sql[i])){i++;continue;}
    if(sql.startsWith('--',i)){const end=sql.indexOf('\n',i);i=end<0?sql.length:end+1;continue;}
    if(!sql.startsWith('/*',i))break;
    i+=2;let depth=1;
    while(i<sql.length&&depth){if(sql.startsWith('/*',i)){depth++;i+=2;}else if(sql.startsWith('*/',i)){depth--;i+=2;}else i++;}
    if(depth)throw new Error('Unclosed SQL comment.');
  }
  return i;
}
function compileTextFunctions(sql) {
  // Current SQLite instr calls have TEXT operands. Rewrite only the unquoted,
  // unqualified builtin spelling, never text, comments or qualified functions.
  let i=0,previous='',copied=0,out='';
  while(i<sql.length){
    const next=sqlTriviaEnd(sql,i);if(next!==i){i=next;continue;}
    if(sql[i]==="'"||sql[i]==='"'||sql[i]==='`'){i=quotedEnd(sql,i);previous='quoted';continue;}
    if(sql[i]==='$'){
      const tag=/^\$(?:[A-Za-z_\u0080-\uffff][A-Za-z_0-9\u0080-\uffff]*)?\$/.exec(sql.slice(i))?.[0];
      if(tag){const end=sql.indexOf(tag,i+tag.length);if(end<0)throw new Error('Unclosed SQL literal.');i=end+tag.length;previous='quoted';continue;}
    }
    if(/[A-Za-z_\u0080-\uffff]/.test(sql[i])){
      const start=i++;while(i<sql.length&&/[A-Za-z_0-9$\u0080-\uffff]/.test(sql[i]))i++;
      const token=sql.slice(start,i);
      if(token.toLowerCase()==='instr'&&previous!=='.'&&sql[sqlTriviaEnd(sql,i)]==='('){out+=sql.slice(copied,start)+'pg_catalog.strpos';copied=i;}
      previous=token;continue;
    }
    previous=sql[i++];
  }
  return out+sql.slice(copied);
}
export function compileSql(input, values = []) {
  if (typeof input !== 'string' || !input.trim()) throw new Error('Invalid server SQL.');
  input=compileTextFunctions(input);
  let out = '', index = 0;
  // The explicitly marked MoMo lease clock remains ordinary unixepoch() on
  // SQLite. PostgreSQL's app.unixepoch() is transaction-stable, so just this
  // marker needs a moving clock after a row-lock wait. Do not alter other SQL.
  const momoLeaseClock='unixepoch(/*collect_momo_lease_clock*/)';
  for (let i = 0; i < input.length;) {
    if (input[i] === "'" || input[i] === '"') { const end = quotedEnd(input, i); out += input.slice(i, end); i = end; continue; }
    if (input.slice(i,i+2) === '--') { const end = input.indexOf('\n',i); if (end < 0) break; out += '\n'; i=end+1; continue; }
    if (input.slice(i,i+2) === '/*') {
      let end=i+2,depth=1;
      while(end<input.length&&depth){
        if(input.slice(end,end+2)==='/*'){depth++;end+=2;}
        else if(input.slice(end,end+2)==='*/'){depth--;end+=2;}
        else end++;
      }
      if(depth)throw new Error('Unclosed SQL comment.');out+=input.slice(i,end);i=end;continue;
    }
    if (input.startsWith(momoLeaseClock,i)) { out+='floor(extract(epoch from pg_catalog.clock_timestamp()))::bigint';i+=momoLeaseClock.length;continue; }
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
