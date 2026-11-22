// Exports exact parameterized production queries for the disposable PG fixture.
import {PostgresRecordsStore} from '../../functions/_shared/domain/burimunsi/postgres-records-store.js';
const g='buri-qualification-group',other='buri-qualification-group-2';
const A='f3000000-0000-4000-8000-000000000011',B='f3000000-0000-4000-8000-000000000012',C='f3000000-0000-4000-8000-000000000013';
const cases=[
 ['all',g,'','all',null],['payer',g,'Origin Alice','all',null],['payer_phone',g,'***111','all',null],
 ['reference',g,'QUALIFICATION-1','all',null],['amount',g,'11000','all',null],['date',g,'2026-11-11','all',null],
 ['member_name',g,'Alice Member','all',null],['member_local',g,'0780000011','all',null],['member_e164',g,'+250780000011','all',null],['other_member_name',g,'Charlie Other','all',null],
 ['literal_percent',g,'%','all',null],['literal_underscore',g,'_','all',null],['literal_slash',g,'\\','all',null],
 ['allocated',g,'','allocated',null],['unallocated',g,'','unallocated',null],['processing',g,'','processing',null],
 ['member_a',g,'','all',A],['member_b',g,'','all',B],['other',other,'','all',null],['other_member',other,'','all',C]
];
const result=[];
for(const [name,groupId,q,filter,memberId] of cases){
 const calls=[];
 const sql={unsafe:async(text,args=[])=>{calls.push({text,args});if(text.startsWith('SELECT id FROM app.memberships'))return[{id:'member'}];if(text.startsWith('SELECT count(*)'))return[{total:0}];return[];}};
 const store=new PostgresRecordsStore({authority:{groupId,read:fn=>fn(sql),session:async()=>null},sourceReader:{revision(){},page(){},detail(){}}});
 await store.withReadSnapshot(tx=>tx.readPage({groupId,kind:'payments',q,filter,memberId,limit:100,after:null}));
 result.push({name,groupId,count:calls.find(x=>x.text.startsWith('SELECT count(*)')),page:calls.find(x=>x.text.includes('ORDER BY t.transaction_at'))});
}
const revision=[];const sql={unsafe:async(text,args=[])=>{revision.push({text,args});return[];}};
const store=new PostgresRecordsStore({authority:{groupId:g,read:fn=>fn(sql),session:async()=>null},sourceReader:{revision(){},page(){},detail(){}}});
await store.withReadSnapshot(tx=>tx.listRevision(g,'payments',null));
const home=[];
const homeSql={unsafe:async(text,args=[])=>{home.push({text,args});
 if(text.startsWith('SELECT coalesce(sum(amount_minor)'))return[{balance:0}];
 if(text.startsWith('SELECT coalesce(sum(c.credited_amount)'))return[{today:0}];
 if(text.includes(' AS unallocated_amount'))return[{members:0,unallocated:0,unallocated_amount:0}];
 return[];}};
const homeStore=new PostgresRecordsStore({authority:{groupId:g,read:fn=>fn(homeSql),session:async()=>null},
 sourceReader:{revision(){},page(){},detail(){}},clock:()=>Date.parse('2026-11-11T10:30:00Z')});
await homeStore.withReadSnapshot(tx=>tx.canonicalHome(g));
process.stdout.write(JSON.stringify({cases:result,revision:revision[0],home}));
