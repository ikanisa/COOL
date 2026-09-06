// Supplemental executable migration test when the retained Docker fixture is
// unavailable. Dependency tables and the legacy five-argument RPC are fixtures.
import { PGlite } from 'npm:@electric-sql/pglite@0.3.14';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const db = new PGlite();
const owner='10000000-0000-0000-0000-000000000001';
const other='10000000-0000-0000-0000-000000000002';
await db.exec(`
create role anon; create role authenticated; create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.user',true),'')::uuid $$;
create table public.profiles(id uuid primary key,public_id text,whatsapp_phone text,country_code text,currency_code text,momo_provider text,momo_number text,momo_pay_code text,revolut_link text,revolut_account text);
create table public.audit_logs(actor_user_id uuid,action text,entity_type text,entity_id uuid,metadata jsonb);
insert into profiles(id,public_id,country_code,currency_code,momo_number) values('${owner}','123456','RW','RWF','0788123456'),('${other}','654321','RW','RWF','0788123457');
create function public.update_current_member_profile(p_country_code text,p_momo_provider text,p_momo_number text,p_revolut_link text,p_revolut_account text)
returns jsonb language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_country_code not in ('RW','DE') then raise exception 'Unsupported profile country'; end if;
 update public.profiles set country_code=p_country_code,momo_provider=p_momo_provider,momo_number=p_momo_number,revolut_account=p_revolut_account where id=auth.uid();
 if not found then raise exception 'Collect profile not found'; end if;
 return '{}'::jsonb;
end $$;
`);
await db.exec(await fs.readFile('supabase/migrations/20260906093000_member_profile_momo_code.sql','utf8'));
const q=(sql,args=[])=>db.query(sql,args);
const scalar=async(sql,args=[])=>Object.values((await q(sql,args)).rows[0])[0];
await q("select set_config('test.user',$1,false)",[owner]);
const update=(code,country='RW')=>scalar('select public.update_current_member_profile($1,$2,$3,null,null,$4)',[country,'mtn_momo','0788123456',code]);
const checks=[];
assert.equal((await update('008000')).momo_pay_code,'008000');
assert.equal(await scalar('select momo_pay_code from profiles where id=$1',[owner]),'008000');
checks.push('Leading zeros persist and private payload returns the code');
for(const code of ['12','12*45','1234567890']) await assert.rejects(()=>update(code),/4 to 9/);
assert.equal(await scalar('select momo_pay_code from profiles where id=$1',[owner]),'008000');
checks.push('Invalid codes leave stored values unchanged');
await assert.rejects(()=>update('41258','XX'),/Unsupported/);
assert.equal(await scalar('select momo_pay_code from profiles where id=$1',[owner]),'008000');
checks.push('Legacy RPC failure rolls back the new update');
assert.equal((await update('')).momo_pay_code,null);
await update('41258');
await q("select public.update_current_member_profile('RW','mtn_momo','0788123456',null,null)");
assert.equal(await scalar('select momo_pay_code from profiles where id=$1',[owner]),'41258');
checks.push('Optional clear and old five-argument call remain compatible');
assert.equal((await update(null,'DE')).momo_pay_code,null);
assert.equal(await scalar('select momo_pay_code from profiles where id=$1',[other]),null);
assert.equal(await scalar("select count(*)::int from audit_logs where metadata::text like '%008000%'"),0);
checks.push('Diaspora clears code; other account and audit privacy are preserved');
assert.equal(await scalar("select has_function_privilege('anon','public.update_current_member_profile(text,text,text,text,text,text)','execute')"),false);
assert.equal(await scalar("select has_function_privilege('authenticated','public.update_current_member_profile(text,text,text,text,text,text)','execute')"),true);
assert.equal(await scalar("select has_function_privilege('authenticated','public._member_profile_payload(public.profiles)','execute')"),false);
await q("select set_config('test.user','',false)");
await assert.rejects(()=>update('41258'),/Authentication required/);
checks.push('Authentication and grants remain restricted');
const report={passed:checks.length,checks,scope:'Actual MoMo-code migration; fixture dependency tables and legacy RPC. Supplements earlier full PostgreSQL rollback evidence; not live UAT.'};
await fs.writeFile('.cache/group-cover-integration/momo-prerequisite-checks.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));await db.close();
