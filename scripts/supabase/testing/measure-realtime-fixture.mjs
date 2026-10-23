// ROOT ONLY. A review evidence producer, never an auto-admission mechanism.
// Supply a NEW unique local DB already containing immutable00+SQL1..9 only.
// No create/reset/drop/database initialization/SQL10/policy/provider operation.
import {open,realpath} from 'node:fs/promises';
import {dirname,resolve,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {fixtureIdentitySql,restrictedPostgresSql,loadOriginalNine} from './curated-platform-fixture.mjs';
import {readFile} from 'node:fs/promises';
const here=dirname(fileURLToPath(import.meta.url)),root=resolve(here,'../../..');
const fail=code=>{throw Error(code);},need=(v,c)=>{if(!v)fail(c);};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const raw=process.env.COLLECT_MEMBER_REALTIME_MEASUREMENT_DATABASE_URL;
const output=process.argv[2];let url;try{url=new URL(raw);}catch{fail('NEW_REALTIME_MEASUREMENT_URL_REQUIRED');}
need(process.argv.length===3&&isAbsolute(output??''),'NEW_PRIVATE_MEASUREMENT_OUTPUT_REQUIRED');
need(['postgres:','postgresql:'].includes(url.protocol)&&url.hostname==='127.0.0.1'&&/^\d{1,5}$/.test(url.port)&&Number(url.port)>0&&Number(url.port)<=65535&&url.username==='collect_test'&&!!url.password&&!url.search&&!url.hash&&/^\/collect_member_realtime_measure_[a-f0-9]{24}_test$/.test(url.pathname),'NEW_REALTIME_MEASUREMENT_URL_REQUIRED');
need(await realpath(root)===root,'PHYSICAL_REVIEWED_SOURCE_REQUIRED');
await loadOriginalNine(root,{requireTen:false}); // Exact immutable NINE files on disk and installed; no SQL10 yet.
const [interfaceBytes,metadataBytes]=await Promise.all(['member-realtime-interface.sql','member-realtime-metadata.sql'].map(f=>readFile(resolve(here,f))));
const {Client}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
const db=new Client({connectionString:url.href,connectionTimeoutMillis:5000,statement_timeout:15000,query_timeout:20000});
let stage='connect';let file;
try{
 await db.connect();await db.query(fixtureIdentitySql);await db.query(restrictedPostgresSql);stage='pristine_profile';
 await db.query("DO $$BEGIN IF to_regnamespace('realtime') IS NOT NULL OR to_regclass('private.member_realtime_control') IS NOT NULL OR(SELECT count(*) FROM pg_tables WHERE schemaname='app')<>97 OR(SELECT count(*) FROM pg_tables WHERE schemaname='private')<>17 OR(SELECT count(*) FROM app.users)<>0 OR EXISTS(SELECT 1 FROM private.collect_fence_control) OR EXISTS(SELECT 1 FROM private.collect_fence_admissions) THEN RAISE EXCEPTION 'PRISTINE_NINE_UNINITIALIZED_FIXTURE_REQUIRED';END IF;END$$;");
 stage='owned_synthetic_interface';await db.query(interfaceBytes.toString('utf8'));
 stage='bounded_metadata';const expression=metadataBytes.toString('utf8').trim().replace(/;$/,'');
 const rows=(await db.query("SELECT q.metadata::text AS metadata_text,encode(sha256(convert_to(q.metadata::text,'UTF8')),'hex') AS metadata_sha256 FROM ("+expression+") AS q(metadata)")).rows;
 need(rows.length===1&&typeof rows[0].metadata_text==='string'&&Buffer.byteLength(rows[0].metadata_text)<=131072&&/^[a-f0-9]{64}$/.test(rows[0].metadata_sha256)&&hash(rows[0].metadata_text)===rows[0].metadata_sha256,'BOUNDED_METADATA_IDENTITY_REQUIRED');
 const receipt={format:'collect.member.realtime.synthetic-metadata-observation.v1',status:'OBSERVED_NOT_ADMITTED',database:url.pathname.slice(1),server_major:17,owner:'collect_test',owner_super:true,owner_bypass:true,restricted_postgres_all_seven_flags_false:true,interface_sha256:hash(interfaceBytes),metadata_expression_sha256:hash(metadataBytes),metadata_sha256:rows[0].metadata_sha256,metadata:JSON.parse(rows[0].metadata_text),sql10_installed:false,source_initialized:false,review_required:true,provider_calls:0,hosted_acceptance:false};
 file=await open(output,'wx',0o600);await file.writeFile(JSON.stringify(receipt,null,2)+'\n');await file.sync();await file.close();file=null;
 console.log(JSON.stringify({status:'OBSERVED_NOT_ADMITTED',metadata_sha256:receipt.metadata_sha256,review_required:true,provider_calls:0,hosted_acceptance:false}));
}catch{console.error(JSON.stringify({status:'UNCONFIRMED',stage,preserve_database:true,provider_calls:0,hosted_acceptance:false}));process.exitCode=1;}
finally{if(file)await file.close().catch(()=>{});await db.end().catch(()=>{});}
