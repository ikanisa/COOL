import {assert,assertEquals} from 'jsr:@std/assert@1.0.14';

// Additive cases for the existing actual-Edge/PostgreSQL financial fixture.
// No auto-running entry point. Root must bind the existing genuine financial
// BFF/email fixture in a separately granted exclusive finite loopback runner.
// canonicalIncoming must use the existing receipt-facts producer fixture, not
// fabricated model/output acceptance. No hosted/network service is permitted.
export async function financialApprovalCollisionCases(h:any){
 const {sql,financialAdmin,financialCall,principal,ActualPostgresDatabase,newHandler,canonicalIncoming,step}=h;
 for(const fn of [financialAdmin,financialCall,newHandler,canonicalIncoming,step])assert(typeof fn==='function','All actual fixture bindings are mandatory; no skipped cases');
 assert(sql&&typeof principal==='string'&&ActualPostgresDatabase?.prototype?.prepare);
 const location=(await sql`SELECT current_database() AS db,host(inet_server_addr()) AS host`)[0];
 assert(['127.0.0.1','::1'].includes(location.host));
 assert(location.db==='collect_be02_green_3f624f3e7a6d_test','Use the already accepted isolated actual-Edge fixture only');
 const recorder1=await financialAdmin(10),recorder2=await financialAdmin(11),reviewer1=await financialAdmin(12),reviewer2=await financialAdmin(13);
 const stamp='2026-10-23T09:10:11.000Z';
 const decode=async(r:Response,status=200)=>{const value=await r.json();assertEquals(r.status,status,JSON.stringify(value));return value;};
 const group=async(provider='mtn_momo',receiver='250788123491')=>{
  const id=crypto.randomUUID(),at=new Date().toISOString();
  await sql`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at)
   VALUES(${id},${'collision-'+id},${principal},'Synthetic collision fixture','ikimina',${receiver},${provider},${at},${at})`;
  await sql`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)VALUES(${crypto.randomUUID()},${id},${principal},'owner',${at})`;return id;
 };
 const record=async(who:any,g:string,reference:string|null,amount=1000,observed=stamp)=>{
  const key=crypto.randomUUID(),body={group_id:g,amount_rwf:amount,provider_reference:reference,observed_at:observed,evidence:'SYNTHETIC exact receiving evidence; no provider confirmation',payer_name:'Synthetic payer',reason:'Synthetic independent evidence collision regression'};
  const v=await decode(await financialCall('/operations/transactions',body,who,key));
  const repeat=await decode(await financialCall('/operations/transactions',body,who,key));assertEquals(repeat.resource_id,v.resource_id);
  return {id:v.resource_id,key,body};
 };
 const propose=async(who:any,p:any)=>{
  const row=(await sql`SELECT p.collection_id,p.amount_minor,p.revision,u.revision AS member_version,m.revision AS membership_version,u.full_name,u.momo_provider,u.momo_number,u.momo_pay_code
   FROM app.payments p JOIN app.memberships m ON m.collection_id=p.collection_id AND m.user_id=${principal} JOIN app.users u ON u.id=m.user_id WHERE p.id=${p.id}`)[0];
  assert(row.full_name&&row.momo_number,'Existing actual financial fixture must provide a legitimate synthetic member identity');
  const body={member_user_id:principal,amount_rwf:Number(row.amount_minor),expected_transaction_version:Number(row.revision),expected_member_version:Number(row.member_version),expected_membership_version:Number(row.membership_version),
   expected_payment_identity:{display_name:row.full_name,momo_provider:row.momo_provider,momo_number:row.momo_number,momo_pay_code:row.momo_pay_code},reason:'Synthetic independent attribution preimage'};
  return {id:(await decode(await financialCall('/reconciliations/'+p.id+'/proposals',body,who,crypto.randomUUID()))).resource_id,payment:p.id};
 };
 const review=async(who:any,q:any,outcome='approved',key=crypto.randomUUID(),handler?:any)=>{
  const version=Number((await sql`SELECT revision FROM app.payments WHERE id=${q.payment}`)[0].revision);
  return financialCall('/reconciliations/proposals/'+q.id+'/reviews',{outcome,expected_proposal_version:1,expected_transaction_version:version,reason:'Synthetic independent event-reference review'},who,key,handler);
 };
 const ledger=async(ids:string[])=>{
  const result=await sql`SELECT count(*)::int AS entries,coalesce(sum(amount_minor),0)::bigint AS net,count(*) FILTER(WHERE kind='contribution')::int AS contributions FROM app.ledger_entries WHERE payment_id=ANY(${ids}::text[])`;
  return result[0];
 };
 const held=async(p:any,q:any)=>{
  assertEquals((await sql`SELECT status FROM app.payments WHERE id=${p.id}`)[0].status,'recorded');
  assertEquals((await sql`SELECT status FROM app.reconciliations WHERE id=${q.id}`)[0].status,'proposed');
  assertEquals(Number((await ledger([p.id])).entries),0);
  assertEquals(Number((await sql`SELECT count(*)::int AS n FROM app.contribution_posting_snapshots WHERE payment_id=${p.id}`)[0].n),0);
  assertEquals(Number((await sql`SELECT count(*)::int AS n FROM app.notification_events WHERE data_json::jsonb->>'payment_id'=${p.id}`)[0].n),0);
 };
 const pair=async({firstAmount=1000,secondAmount=1000,secondTime=stamp}:any={})=>{
  const g=await group(),reference='SYNTHETIC-'+crypto.randomUUID();
  const a=await record(recorder1,g,reference,firstAmount),b=await record(recorder2,g,reference,secondAmount,secondTime);
  assert(a.id!==b.id,'The test must traverse two actual recorder-created payment identities');
  return {a,b,qa:await propose(recorder1,a),qb:await propose(recorder2,b)};
 };
 await step('two recorders and two reviewers: second full credit held atomically',async()=>{
  const f=await pair();await decode(await review(reviewer1,f.qa));await decode(await review(reviewer2,f.qb),409);await held(f.b,f.qb);
  assertEquals(Number((await ledger([f.a.id,f.b.id])).net),1000);assertEquals(Number((await ledger([f.a.id,f.b.id])).contributions),1);
 });
 await step('same reference and receiver with amount mismatch does not make a new event',async()=>{
  const f=await pair({secondAmount:1700});await decode(await review(reviewer1,f.qa));await decode(await review(reviewer2,f.qb),409);await held(f.b,f.qb);
 });
 await step('same reference and receiver with observation-time mismatch does not make a new event',async()=>{
  const f=await pair({secondTime:'2026-11-23T09:10:11.000Z'});await decode(await review(reviewer1,f.qa));await decode(await review(reviewer2,f.qb),409);await held(f.b,f.qb);
 });
 await step('concurrent distinct approvals both pass original reads; exactly one commits',async()=>{
  const f=await pair(),ids=new Set([f.a.id,f.b.id]),original=ActualPostgresDatabase.prototype.prepare;
  let count=0,release!:()=>void;const barrier=new Promise<void>(resolve=>release=resolve);let expired=false;
  const timer=setTimeout(()=>{expired=true;release();},10000);
  ActualPostgresDatabase.prototype.prepare=function(query:string){const s=original.call(this,query);if(query!=='SELECT * FROM payments WHERE id=?')return s;
   const bind=s.bind.bind(s);s.bind=(...args:any[])=>{const bound=bind(...args);if(!ids.has(args[0]))return bound;const first=bound.first.bind(bound);bound.first=async(column?:any)=>{const row=await first(column);if(++count===2)release();await barrier;return row;};return bound;};return s;};
  let replies:Response[];
  try{replies=await Promise.all([review(reviewer1,f.qa,'approved',crypto.randomUUID(),newHandler()),review(reviewer2,f.qb,'approved',crypto.randomUUID(),newHandler())]);}
  finally{clearTimeout(timer);release();ActualPostgresDatabase.prototype.prepare=original;}
  assertEquals(expired,false);assertEquals(count,2,'Both distinct original payment reads must reach the controlled race');
  assertEquals(replies!.map(r=>r.status).sort(),[200,409]);for(const r of replies!)await r.arrayBuffer();
  const totals=await ledger([f.a.id,f.b.id]);assertEquals(Number(totals.net),1000);assertEquals(Number(totals.contributions),1);
  const loser=(await sql`SELECT id FROM app.payments WHERE id=ANY(${[f.a.id,f.b.id]}::text[]) AND status='recorded'`)[0].id;
  await held(loser===f.a.id?f.a:f.b,loser===f.a.id?f.qa:f.qb);
 });
 await step('normalized local/international receiving aliases collide across groups',async()=>{
  const ref='SYNTHETIC-'+crypto.randomUUID(),g1=await group('mtn_momo','0788123495'),g2=await group('mtn_momo','+250788123495');
  const a=await record(recorder1,g1,ref),b=await record(recorder2,g2,ref),qa=await propose(recorder1,a),qb=await propose(recorder2,b);
  await decode(await review(reviewer1,qa));await decode(await review(reviewer2,qb),409);await held(b,qb);
  assertEquals(Number((await ledger([a.id,b.id])).net),1000);
 });
 await step('same reference on distinct receiving accounts is permitted',async()=>{
  const ref='SYNTHETIC-'+crypto.randomUUID(),g1=await group('mtn_momo','250788123492'),g2=await group('mtn_momo','250788123493');
  const a=await record(recorder1,g1,ref),b=await record(recorder2,g2,ref);await decode(await review(reviewer1,await propose(recorder1,a)));await decode(await review(reviewer2,await propose(recorder2,b)));
  assertEquals(Number((await ledger([a.id,b.id])).net),2000);
 });
 await step('same reference and receiver text on distinct providers is permitted',async()=>{
  const ref='SYNTHETIC-'+crypto.randomUUID(),g1=await group('mtn_momo','250788123494'),g2=await group('airtel_money','250788123494');
  const a=await record(recorder1,g1,ref),b=await record(recorder2,g2,ref);await decode(await review(reviewer1,await propose(recorder1,a)));await decode(await review(reviewer2,await propose(recorder2,b)));
  assertEquals(Number((await ledger([a.id,b.id])).net),2000);
 });
 await step('missing reference: recording and rejection retained, approval unavailable',async()=>{
  const g=await group(),p=await record(recorder1,g,null),q=await propose(recorder1,p),response=await review(reviewer1,q);const failure=await decode(response,409);
  assertEquals(failure.error?.code??failure.code,'independent_evidence_identity_required');await held(p,q);await decode(await review(reviewer2,q,'rejected'));
  assertEquals(Number((await ledger([p.id])).entries),0);
 });
 await step('fully matched reversal allows separately reviewed replacement without erasure',async()=>{
  const f=await pair();await decode(await review(reviewer1,f.qa));const key=crypto.randomUUID();
  await decode(await financialCall('/operations/transactions/'+f.a.id+'/reverse',{expected_version:2,reason:'Synthetic full exact offset before replacement'},reviewer1,key));
  await decode(await financialCall('/operations/transactions/'+f.a.id+'/reverse',{expected_version:2,reason:'Synthetic full exact offset before replacement'},reviewer1,key));
  await decode(await review(reviewer2,f.qb));const totals=await ledger([f.a.id,f.b.id]);assertEquals(Number(totals.entries),3);assertEquals(Number(totals.net),1000);
  assertEquals(Number((await sql`SELECT count(*)::int AS n FROM app.payment_evidence WHERE id IN(SELECT evidence_id FROM app.payments WHERE id=ANY(${[f.a.id,f.b.id]}::text[]))`)[0].n),2);
 });
 await step('raw/qualified canonical SMS aliases collide only through retained canonical identity',async()=>{
  const g=await group(),txRef='SYNTHETIC-'+crypto.randomUUID();
  // The receiving account may exist before extraction. This callback creates
  // the actual canonical account through the existing receipt-facts fixture.
  const account=await canonicalIncoming({phase:'account',provider:'mtn_momo',receiver:'250788123491'});
  const a=await record(recorder1,g,txRef),b=await record(recorder2,g,account.id+':'+txRef);
  const canonical=await canonicalIncoming({phase:'extract',account,reference:txRef,amount:1000});
  assertEquals(canonical.provider_transaction_id,txRef);assertEquals(canonical.receiving_account_id,account.id);
  const qa=await propose(recorder1,a),qb=await propose(recorder2,b);await decode(await review(reviewer1,qa));await decode(await review(reviewer2,qb),409);await held(b,qb);
  assertEquals(Number((await ledger([a.id,b.id])).net),1000);
 });
 await step('same raw and qualified strings without canonical join are not silently reinterpreted',async()=>{
  const g=await group(),ref='SYNTHETIC-'+crypto.randomUUID(),unknown=crypto.randomUUID();
  const a=await record(recorder1,g,ref),b=await record(recorder2,g,unknown+':'+ref);
  // This is an explicit remaining identity-policy limit: strings alone do not
  // prove one event. Record the absence of a canonical account/transaction join.
  assertEquals(Number((await sql`SELECT count(*)::int AS n FROM app.momo_transactions WHERE provider_transaction_id=${ref}`)[0].n),0);
  // Do not approve ambiguous aliases or claim this candidate can authenticate
  // them. The required owner identity policy, not a guessed prefix, decides.
  assertEquals(Number((await ledger([a.id,b.id])).entries),0);
 });
}
