import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
await import('./helpers/node-postgres-import.mjs');
const {compileSql}=await import('../postgres.js');
const {list}=await import('../domain/admin_records.js');

test('SQLite TEXT instr calls compile to the schema-qualified PostgreSQL builtin',()=>{
 assert.deepEqual(compileSql('SELECT instr(?,?), InStR /* call */ (?,?)',["a'b",'b','😀éB','B']),{
  text:'SELECT pg_catalog.strpos($1,$2), pg_catalog.strpos /* call */ ($3,$4)',values:["a'b",'b','😀éB','B']});
 assert.equal(compileSql('SELECT instr /* outer /* nested */ */ (value,needle)').text,
  'SELECT pg_catalog.strpos /* outer /* nested */ */ (value,needle)');
 assert.equal(compileSql("SELECT ARRAY[instr('abc','a')]").text,"SELECT ARRAY[pg_catalog.strpos('abc','a')]");
});

test('instr mapping preserves quoted text, identifiers, comments and qualified user functions',()=>{
 const sql=`SELECT 'instr(' AS literal,'it''s instr(' AS escaped,"instr"('a','b'),
  custom.instr('a','b'),"custom" . /* keep */ instr('a','b'),
  custom /* keep */ . -- instr('not','called')
  instr('a','b'), custom_instr('a','b'),instr_value,αinstr('a','b'),instrα('a','b'),instr$custom('a','b'),
  instr, "instr('a','b')", $$instr('a','b')$$, $body$instr('a','b')$body$
  /* instr('a','b') /* instr('c','d') */ */ FROM instr_table`;
 assert.equal(compileSql(sql).text,sql.replace("-- instr('not','called')",''));
 assert.equal(compileSql('SELECT instr -- call\n (a,b)').text,'SELECT pg_catalog.strpos \n (a,b)');
 assert.equal(compileSql('SELECT instr FROM records WHERE instr=?',['plain']).text,'SELECT instr FROM records WHERE instr=$1');
 assert.throws(()=>compileSql('SELECT instr /* unclosed'),/Unclosed SQL comment/);
 assert.throws(()=>compileSql("SELECT 'instr("),/Unclosed SQL literal/);
});

test('TEXT position cases retain SQLite character, null, empty and literal-match semantics',()=>{
 const db=new DatabaseSync(':memory:');
 try{
  const query=db.prepare('SELECT instr(?,?) AS position');
  for(const [haystack,needle,expected] of [
   ['BuriMunsi','Munsi',5],['A😀éB','B',4],['A😀éB','é',3],['e\u0301x','x',3],
   ['abc','missing',0],['abc','',1],['','',1],['','a',0],
   [null,'a',null],['a',null,null],[null,null,null],['x%_y','%_',2],
  ]){
   assert.equal(query.get(haystack,needle).position,expected);
   assert.deepEqual(compileSql('SELECT instr(?,?) AS position',[haystack,needle]),{
    text:'SELECT pg_catalog.strpos($1,$2) AS position',values:[haystack,needle]});
  }
 }finally{db.close();}
});

test('actual Admin groups list compiles both count and page searches with bound TEXT operands',async()=>{
 const db=new DatabaseSync(':memory:'),compiled=[];
 try{
  db.exec(`CREATE TABLE collections(id TEXT,title TEXT,slug TEXT,description TEXT,collection_type TEXT,status TEXT,
   visibility_status TEXT,is_platform_sponsored INTEGER,revision INTEGER,data_json TEXT,created_at TEXT,updated_at TEXT);
   CREATE TABLE memberships(collection_id TEXT,user_id TEXT,active INTEGER);CREATE TABLE users(id TEXT,access_status TEXT);`);
  const insert=db.prepare("INSERT INTO collections VALUES(?,?,?,?,?,'active','public_approved',1,1,'{}',?,?)"),date='2026-11-11T00:00:00.000Z';
  for(const [id,title,slug,description] of [
   ['1','BuriMunsi','buri','Collect-sponsored group'],['2','Unicode 😀é','unicode','A😀éB'],
   ['3','Literal %_','literal','No wildcard search'],['4','Unrelated','other',null],
  ])insert.run(id,title,slug,description,'other',date,date);
  const env={DB:{prepare(sql){return{sql,values:[],bind(...values){return{sql,values};}};},async batch(statements){
   return statements.map(statement=>{compiled.push(compileSql(statement.sql,statement.values));return{results:db.prepare(statement.sql).all(...statement.values)};});
  }}};
  for(const [search,ids] of [['BuriMunsi',['1']],['😀é',['2']],['%_',['3']],['missing',[]],['',['4','3','2','1']]]){
   compiled.length=0;
   const url=new URL('https://fixture.invalid/api/admin/core/groups');url.searchParams.set('search',search);url.searchParams.set('limit','100');url.searchParams.set('offset','0');
   const result=await list(env,'groups',url);
   assert.deepEqual(result.rows.map(row=>row.id),ids);assert.equal(result.total,ids.length);assert.equal(compiled.length,2);
   for(const query of compiled){
    assert.equal(/\binstr\s*\(/i.test(query.text),false);
    assert.equal((query.text.match(/pg_catalog\.strpos\(/g)??[]).length,search?3:0);
    if(search){
     assert.equal(query.text.includes("pg_catalog.strpos(lower(COALESCE(title,'')),lower($1))>0"),true);
     assert.equal(query.text.includes("pg_catalog.strpos(lower(COALESCE(slug,'')),lower($2))>0"),true);
     assert.equal(query.text.includes("pg_catalog.strpos(lower(COALESCE(description,'')),lower($3))>0"),true);
     assert.deepEqual(query.values.slice(0,3),[search,search,search]);assert.equal(query.text.includes(search),false);
    }
   }
   assert.match(compiled[1].text,search?/ORDER BY created_at DESC,id DESC LIMIT \$4 OFFSET \$5$/:/ORDER BY created_at DESC,id DESC LIMIT \$1 OFFSET \$2$/);
   assert.deepEqual(compiled[1].values.slice(-2),[100,0]);
  }
 }finally{db.close();}
});
