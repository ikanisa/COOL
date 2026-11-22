import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,writeFile,copyFile,mkdir,rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
const root=fileURLToPath(new URL('..',import.meta.url));
const names=['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql','0004_operating_actions.sql','0005_member_cloudflare.sql'];
function split(sql){const result=spawnSync(process.execPath,['-e',"process.stdout.write(JSON.stringify(require('wrangler').unstable_splitSqlQuery(require('fs').readFileSync(0,'utf8'))));"],{cwd:root,input:sql,encoding:'utf8'});assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);}

test('member upgrade refuses a populated payee backend before changing referenced data or guards',async()=>{
 const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script:'export default{fetch(){return new Response("test")}}',compatibilityDate:'2026-10-04',d1Databases:['ADMIN_DB']}));
 try{const db=await mf.getD1Database('ADMIN_DB'),run=(sql,...p)=>db.prepare(sql).bind(...p).run();
  for(const name of names.slice(0,4))await db.batch(split(await readFile(path.join(root,'migrations',name),'utf8')).map(s=>db.prepare(s)));
  const actor=crypto.randomUUID(),group=crypto.randomUUID(),payee=crypto.randomUUID(),transaction=crypto.randomUUID(),at=Math.floor(Date.now()/1000);
  await run("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,?,'admin','invited',?,?)",actor,actor+'@example.com',at,at);
  await run("INSERT INTO collect_groups(id,slug,title,collection_type,created_by_admin_id,created_at,updated_at) VALUES(?,?,'Migration fixture','other',?,?,?)",group,'g-'+group,actor,at,at);
  await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'Receiver','mtn_momo','0781234567',?,'Synthetic local evidence',?)",payee,group,actor,at);
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at,recorded_by_admin_id) VALUES(?,?,?,'mtn_momo','migration-fixture',100,?,?,?)",transaction,group,payee,at,at,actor);
  await assert.rejects(db.batch(split(await readFile(path.join(root,'migrations',names[4]),'utf8')).map(s=>db.prepare(s))),/member_migration_requires_empty_payees/);
  assert.deepEqual((await db.prepare('PRAGMA foreign_key_check').all()).results,[]);
  const row=await db.prepare('SELECT t.payee_id,p.created_by_admin_id,p.version FROM collect_transactions t JOIN collect_payees p ON p.id=t.payee_id WHERE t.id=?').bind(transaction).first();
  assert.deepEqual(row,{payee_id:payee,created_by_admin_id:actor,version:1});
  assert.equal((await db.prepare("SELECT count(*) n FROM sqlite_master WHERE name='member_sessions'").first()).n,0);
  await assert.rejects(run('UPDATE collect_payees SET momo_number_or_code=? WHERE id=?','0789999999',payee),/immutable/);
  await assert.rejects(run('DELETE FROM collect_payees WHERE id=?',payee),/Deactivate/);
 }finally{await mf.dispose();}
});

test('Wrangler applies member migrations one through five locally and the repeated application is a no-op',async()=>{
 const directory=await mkdtemp(path.join(tmpdir(),'collect-member-migrations-'));
 try{const migrations=path.join(directory,'migrations');await mkdir(migrations);
  for(const name of names)await copyFile(path.join(root,'migrations',name),path.join(migrations,name));
  const config=path.join(directory,'wrangler.json');await writeFile(config,JSON.stringify({name:'member-migration-test',compatibility_date:'2026-10-04',d1_databases:[{binding:'ADMIN_DB',database_name:'member-test',database_id:crypto.randomUUID(),migrations_dir:migrations}]}));
  const cli=args=>{const r=spawnSync(process.execPath,[path.join(root,'node_modules/wrangler/bin/wrangler.js'),...args,'--local','--config',config],{cwd:directory,encoding:'utf8',timeout:30000,env:{...process.env,CI:'1',WRANGLER_SEND_METRICS:'false'}});assert.equal(r.status,0,r.stdout+r.stderr);return r.stdout;};
  cli(['d1','migrations','apply','ADMIN_DB']);assert.match(cli(['d1','migrations','apply','ADMIN_DB']),/No migrations to apply/);
  const rows=JSON.parse(cli(['d1','execute','ADMIN_DB','--command','SELECT name FROM d1_migrations ORDER BY id','--json']))[0].results;
  assert.deepEqual(rows,names.map(name=>({name})));
 }finally{await rm(directory,{recursive:true,force:true});}
});
