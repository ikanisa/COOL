// Invoked only by run-local-postgres.sh against its newly created Unix socket.
import assert from 'node:assert/strict';
import postgres from 'npm:postgres@3.4.7';
import {transact,type Pool} from '../src/transactions.ts';
import {managedSmsFence} from '../src/fence.ts';
import {ManagedGatewayDatabase} from '../src/database.ts';
import {receiptReadPrincipal} from '../src/receipt-read.ts';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
const socket=Deno.env.get('MANAGED_SMS_FIXTURE_SOCKET');
if(!socket||!/^\/(?:private\/)?tmp\/collect-managed-sms-[A-Za-z0-9]+\/socket$/.test(socket))throw Error('fixture_socket_required');
const port=Number(Deno.env.get('MANAGED_SMS_FIXTURE_PORT'));if(!Number.isInteger(port)||port<1024||port>65535)throw Error('fixture_port_required');
const sql=postgres({host:'127.0.0.1',port,database:'postgres',username:'collect_sms_edge',ssl:false,max:4,prepare:true,fetch_types:true,connect_timeout:2});
try{
 const value=await transact(sql as unknown as Pool,async tx=>(await tx.query("SELECT session_user::text AS login,current_user::text AS role,current_setting('collect.sms_verified',true) AS verified,pg_backend_pid() AS pid"))[0]);
 assert.equal(value.login,'collect_sms_edge');assert.equal(value.role,'collect_sms_runtime');assert.equal(value.verified,'true');
 const after=await sql`SELECT current_user::text AS role,current_setting('collect.sms_verified',true) AS verified`;
 assert.equal(after[0].role,'collect_sms_edge');assert.notEqual(after[0].verified,'true');
 const simultaneous=await Promise.all([0,1].map(()=>transact(sql as unknown as Pool,async tx=>{
  const rows=await tx.query("SELECT current_user::text AS role,current_setting('collect.sms_verified',true) AS verified,pg_backend_pid() AS pid,pg_sleep(0.05)");return rows[0];
 })));
 assert.ok(simultaneous.every(v=>v.role==='collect_sms_runtime'&&v.verified==='true'));assert.notEqual(simultaneous[0].pid,simultaneous[1].pid);
 const backend=managedSmsFence(sql as unknown as Pool,'b'.repeat(64));
 const work=await (openApplicationWork as any)({backend,sourceSha256:'a'.repeat(64),kind:'http_collect'});
 const db=new ManagedGatewayDatabase(sql as unknown as Pool).withApplicationWork(work,{tokenHash:'c'.repeat(64),scope:'messages:write'});
 await db.prepare('INSERT INTO messages(message_id,application_id,kind,text) VALUES(?,?,?,?)').bind('fixture-id','alpha','receipt','synthetic').run();
 assert.equal((await db.prepare('SELECT text FROM messages WHERE message_id=?').bind('fixture-id').first())?.text,'synthetic');
 const owner=postgres({host:'127.0.0.1',port,database:'postgres',username:'postgres',ssl:false,max:1,prepare:true,fetch_types:true});
 try{await assert.rejects(sql`SELECT * FROM private.fixture_admissions`);
  const locked=await owner`SELECT pg_try_advisory_xact_lock(7346371,1) AS available`;assert.equal(locked[0].available,false);
  const result=await work.finish();assert.equal(result.state,'settled');
  const free=await owner`SELECT pg_try_advisory_xact_lock(7346371,1) AS available`;assert.equal(free[0].available,true);
  const createWork=()=> (openApplicationWork as any)({backend,sourceSha256:'a'.repeat(64),kind:'http_collect'});
  // Revocation acquires the row first; INSERT must wait, then fail closed.
  const revokedWork=await createWork(),revokedDb=new ManagedGatewayDatabase(sql as unknown as Pool).withApplicationWork(revokedWork,{tokenHash:'c'.repeat(64),scope:'messages:write'});
  let rejected:Promise<any>|undefined,insertState='pending';
  await owner.begin(async tx=>{
   await tx`UPDATE collect_sms.applications SET revoked_at='revoked' WHERE application_id='alpha'`;
   rejected=revokedDb.prepare('INSERT INTO messages(message_id,application_id,kind,text) VALUES(?,?,?,?)').bind('revoked-first','alpha','receipt','synthetic').run();
   void rejected.then(()=>insertState='resolved',()=>insertState='rejected');await new Promise(r=>setTimeout(r,100));assert.equal(insertState,'pending');
  });
  await assert.rejects(rejected!);assert.equal((await revokedWork.finish({failed:true})).state,'settled');
  assert.equal((await owner`SELECT count(*)::int AS n FROM collect_sms.messages WHERE message_id='revoked-first'`)[0].n,0);
  await owner`UPDATE collect_sms.applications SET revoked_at=NULL WHERE application_id='alpha'`;
  // INSERT obtains the credential row first; concurrent revocation must wait.
  let releaseCommit!:()=>void,enteredCommit!:()=>void;const commitGate=new Promise<void>(r=>releaseCommit=r),commitEntered=new Promise<void>(r=>enteredCommit=r);
  const delayedBeforeCommit:Pool={async reserve(){const tx=await sql.reserve();let inserted=false;return {async unsafe(text:string,values:unknown[]=[],options:any={}){
   if(text.startsWith('INSERT INTO messages'))inserted=true;if(text==='COMMIT'&&inserted){enteredCommit();await commitGate;}return await tx.unsafe(text,values as any,options);},release(){tx.release();}};},end:async()=>{}};
  const insertedWork=await createWork(),insertedDb=new ManagedGatewayDatabase(delayedBeforeCommit).withApplicationWork(insertedWork,{tokenHash:'c'.repeat(64),scope:'messages:write'});
  const inserting=insertedDb.prepare('INSERT INTO messages(message_id,application_id,kind,text) VALUES(?,?,?,?)').bind('insert-first','alpha','receipt','synthetic').run();
  await commitEntered;let revokeState='pending';const revoking=owner`UPDATE collect_sms.applications SET revoked_at='revoked' WHERE application_id='alpha'`.then(()=>{revokeState='done';});
  await new Promise(r=>setTimeout(r,100));assert.equal(revokeState,'pending');releaseCommit();await inserting;await revoking;
  await assert.rejects(insertedDb.prepare('SELECT message_id FROM messages WHERE message_id=?').bind('insert-first').first());assert.equal((await insertedWork.finish()).state,'settled');
  const oldReadWork=await createWork(),oldReadDb=new ManagedGatewayDatabase(sql as unknown as Pool).withApplicationWork(oldReadWork,{tokenHash:'c'.repeat(64),scope:'messages:read'});
  await assert.rejects(receiptReadPrincipal(oldReadDb,'c'.repeat(64),'insert-first'));assert.equal((await oldReadWork.finish()).state,'settled');
  await owner`UPDATE collect_sms.applications SET token_hash=repeat('d',64),revoked_at=NULL WHERE application_id='alpha'`;
  const readerWork=await createWork(),readerDb=new ManagedGatewayDatabase(sql as unknown as Pool).withApplicationWork(readerWork,{tokenHash:'d'.repeat(64),scope:'messages:read'});
  const prior=await readerDb.prepare('SELECT message_id,application_id,kind FROM messages WHERE message_id=? AND application_id=?').bind('insert-first','alpha').first();
  const boundRead=await receiptReadPrincipal(readerDb,'d'.repeat(64),'insert-first');assert.equal(boundRead?.applicationId,'alpha');
  assert.equal(prior?.kind,'receipt');assert.equal((await readerWork.finish()).state,'settled');
  // More than eight deterministic conflicts must close cleanly, not exhaust
  // the fixture's eight-active/unresolved-admission limit.
  for(let i=0;i<12;i++){const conflictWork=await createWork(),conflictDb=new ManagedGatewayDatabase(sql as unknown as Pool).withApplicationWork(conflictWork,{tokenHash:'d'.repeat(64),scope:'messages:write'});
   await assert.rejects(conflictDb.prepare('INSERT INTO messages(message_id,application_id,kind,text) VALUES(?,?,?,?)').bind('insert-first','alpha','receipt','duplicate').run(),(e:any)=>e?.code==='23505');
   const original=await conflictDb.prepare('SELECT message_id,kind FROM messages WHERE message_id=? AND application_id=?').bind('insert-first','alpha').first();assert.equal(original?.kind,'receipt');
   assert.equal((await conflictWork.finish({failed:true})).state,'settled');}
  assert.equal((await owner`SELECT count(*)::int AS n FROM private.fixture_admissions WHERE state='unresolved'`)[0].n,0);
  // Actual COMMIT is applied, but its synthetic acknowledgement is held past
  // the caller timeout; the original work remains owned and is not retried.
  let releaseAck!:()=>void,commitApplied!:()=>void;const ackGate=new Promise<void>(r=>releaseAck=r),applied=new Promise<void>(r=>commitApplied=r);
  const delayedAfterCommit:Pool={async reserve(){const tx=await sql.reserve();let inserted=false;return {async unsafe(text:string,values:unknown[]=[],options:any={}){
   if(text.startsWith('INSERT INTO messages'))inserted=true;const result=await tx.unsafe(text,values as any,options);if(text==='COMMIT'&&inserted){commitApplied();await ackGate;}return result;},release(){tx.release();}};},end:async()=>{}};
  const lateWork=await createWork(),lateDb=new ManagedGatewayDatabase(delayedAfterCommit).withApplicationWork(lateWork,{tokenHash:'d'.repeat(64),scope:'messages:write'});
  const lateInsert=lateDb.prepare('INSERT INTO messages(message_id,application_id,kind,text) VALUES(?,?,?,?)').bind('late-ack','alpha','receipt','synthetic').run();
  await applied;await assert.rejects(lateInsert);let finished=false;const lateFinish=lateWork.finish({failed:true}).then((v:any)=>{finished=true;return v;});
  await new Promise(r=>setTimeout(r,50));assert.equal(finished,false);releaseAck();assert.equal((await lateFinish).state,'unresolved');
  assert.equal((await owner`SELECT count(*)::int AS n FROM collect_sms.messages WHERE message_id='late-ack'`)[0].n,1);
  await owner`ALTER ROLE collect_sms_edge INHERIT`;try{await assert.rejects(transact(sql as unknown as Pool,async()=>{throw Error('must_not_run');}));}
  finally{await owner`ALTER ROLE collect_sms_edge NOINHERIT`;}
 }finally{await owner.end({timeout:2});}
 console.log('isolated PostgreSQL role, fence, transaction and lock checks passed');
}finally{await sql.end({timeout:2});}
