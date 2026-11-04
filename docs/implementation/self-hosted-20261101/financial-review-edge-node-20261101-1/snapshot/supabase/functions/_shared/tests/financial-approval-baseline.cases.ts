import {assert,assertEquals} from 'jsr:@std/assert@1.0.14';

// One controlled baseline counterexample through actual BFF+PostgreSQL.
// No candidate guard, fake SQL result, hosted provider, or original Auth suite.
export async function baselineFinancialDoubleCredit(h:any){
 const {sql,financialAdmin,financialCall,principal}=h;
 assert(sql&&typeof financialAdmin==='function'&&typeof financialCall==='function');
 const where=(await sql`SELECT current_database() AS db,host(inet_server_addr()) AS host`)[0];
 assert(where.db==='collect_be02_red_3f624f3e7a6d_test'&&['127.0.0.1','::1'].includes(where.host));
 const a=await financialAdmin(20),b=await financialAdmin(21),r=await financialAdmin(22),s=await financialAdmin(23),g=crypto.randomUUID(),at=new Date().toISOString(),reference='SYNTHETIC-BASELINE-'+crypto.randomUUID();
 await sql`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at)
  VALUES(${g},${'baseline-'+g},${principal},'Synthetic baseline duplicate','ikimina','250788123499','mtn_momo',${at},${at})`;
 await sql`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)VALUES(${crypto.randomUUID()},${g},${principal},'owner',${at})`;
 assertEquals(Number((await sql`SELECT count(*)::int AS n FROM app.ledger_entries WHERE collection_id=${g}`)[0].n),0);
 const read=async(resp:Response)=>{const value=await resp.json();assertEquals(resp.status,200,JSON.stringify(value));return value;};
 const record=async(who:any)=>{
  const body={group_id:g,amount_rwf:1000,provider_reference:reference,observed_at:'2026-10-23T09:10:11.000Z',
   evidence:'SYNTHETIC exact event; repeated by a second recorder',payer_name:'Synthetic payer',reason:'Synthetic baseline independent evidence'};
  return (await read(await financialCall('/operations/transactions',body,who,crypto.randomUUID()))).resource_id;
 };
 const pa=await record(a),pb=await record(b);assert(pa!==pb);
 const propose=async(who:any,payment:string)=>{
  const m=(await sql`SELECT u.revision AS uv,m.revision AS mv,u.full_name,u.momo_provider,u.momo_number,u.momo_pay_code FROM app.users u JOIN app.memberships m ON m.user_id=u.id WHERE u.id=${principal} AND m.collection_id=${g}`)[0];
  assert(m.full_name&&m.momo_number);
  return(await read(await financialCall('/reconciliations/'+payment+'/proposals',{
   member_user_id:principal,amount_rwf:1000,expected_transaction_version:1,expected_member_version:Number(m.uv),expected_membership_version:Number(m.mv),
   expected_payment_identity:{display_name:m.full_name,momo_provider:m.momo_provider,momo_number:m.momo_number,momo_pay_code:m.momo_pay_code},
   reason:'Synthetic baseline exact beneficiary preimage'},who,crypto.randomUUID()))).resource_id;
 };
 const qa=await propose(a,pa),qb=await propose(b,pb);
 const approve=async(who:any,q:string)=>read(await financialCall('/reconciliations/proposals/'+q+'/reviews',{
  outcome:'approved',expected_proposal_version:1,expected_transaction_version:1,reason:'Synthetic baseline independent event review'},who,crypto.randomUUID()));
 await approve(r,qa);await approve(s,qb);
 const rows=await sql`SELECT payment_id,collection_id,member_id,amount_minor,kind,evidence_id FROM app.ledger_entries WHERE collection_id=${g} ORDER BY payment_id,id`;
 assertEquals(rows.length,2);assertEquals(rows.every((x:any)=>x.kind==='contribution'),true);
 assertEquals(rows.reduce((n:number,x:any)=>n+Number(x.amount_minor),0),2000);
 const payments=await sql`SELECT id,status,member_id,evidence_id FROM app.payments WHERE id=ANY(${[pa,pb]}::text[]) ORDER BY id`;
 assertEquals(payments.length,2);assertEquals(payments.every((x:any)=>x.status==='reconciled'&&x.member_id===principal),true);
 const evidence=await sql`SELECT owner_user_id,external_reference,receiver_network,receiver_momo_number,amount_minor,currency,observed_at,object_sha256 FROM app.payment_evidence WHERE id=ANY(${payments.map((x:any)=>x.evidence_id)}::text[]) ORDER BY id`;
 assertEquals(evidence.length,2);assert(evidence[0].owner_user_id!==evidence[1].owner_user_id);
 for(const key of ['external_reference','receiver_network','receiver_momo_number','amount_minor','currency','observed_at','object_sha256'])assertEquals(evidence[0][key],evidence[1][key],key);
 console.log(JSON.stringify({state:'BASELINE_RED_COUNTEREXAMPLE_OBSERVED',synthetic:true,source_role:'unchanged payments.js 1e536470',recorders:2,independent_reviewers:2,payment_ids:[pa,pb],contribution_entries:2,one_event_principal_rwf:1000,ledger_net_rwf:2000,provider_confirmation:false}));
 throw new Error('KNOWN_DOUBLE_CREDIT_BASELINE_RED');
}
