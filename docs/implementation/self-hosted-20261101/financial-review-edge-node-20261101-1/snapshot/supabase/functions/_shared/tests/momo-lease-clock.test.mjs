import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';

// The loader admits only import of the pinned driver. These tests open no
// network connections; SQLite is an in-memory portability fixture only.
await import('./helpers/node-postgres-import.mjs');
const {compileSql}=await import('../postgres.js');
const marked='unixepoch(/*collect_momo_lease_clock*/)';
const pgClock='floor(extract(epoch from pg_catalog.clock_timestamp()))::bigint';

test('only the explicitly marked lease clock uses the moving PostgreSQL clock',()=>{
 const sql=`SELECT ${marked},unixepoch(),${marked}+?, '${marked}' AS retained`;
 assert.deepEqual(compileSql(sql,[12]),{text:`SELECT ${pgClock},unixepoch(),${pgClock}+$1, '${marked}' AS retained`,values:[12]});
 assert.equal(compileSql(`SELECT 1 /* ${marked} */`,[]).text,`SELECT 1 /* ${marked} */`);
 assert.throws(()=>compileSql('SELECT 1 /* unclosed',[]),/Unclosed SQL comment/);
 const nested=`SELECT 1 /* outer /* ${marked} */ ? retained */ WHERE value=?`;
 assert.deepEqual(compileSql(nested,['bound']),{text:`SELECT 1 /* outer /* ${marked} */ ? retained */ WHERE value=$1`,values:['bound']});
 assert.throws(()=>compileSql('SELECT 1 /* outer /* inner */',[]),/Unclosed SQL comment/);
});

test('the same marked expression remains the standard SQLite unixepoch clock',()=>{
 const sqlite=new DatabaseSync(':memory:');
 try{
  const row=sqlite.prepare(`SELECT ${marked} AS lease_clock,unixepoch() AS ordinary_clock`).get();
  assert.equal(row.lease_clock,row.ordinary_clock);assert(Number.isInteger(row.lease_clock));
 }finally{sqlite.close();}
});
