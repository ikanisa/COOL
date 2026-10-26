// TEST ONLY. No production runtime imports this module. Root-only execution pending.
import {readFile,readdir,realpath} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const here=dirname(fileURLToPath(import.meta.url));
export const AUTH_FIXTURE_SHA256='b935e17f44219f018cf1a864505d1895d71903885ca6c61c039d7ab6596117ea';
export const MIGRATION_TEN='20261022200028_collect_private_member_realtime.sql';
export const MIGRATION_TEN_SHA256='ebfd0389e6ba3aa5fe1595f854b25c69b9b31a0500f202b8e0643209ab0ef6e4';
export const MIGRATION_ELEVEN='20261023002500_collect_admin_recent_email_source_upgrade.sql';
export const MIGRATION_ELEVEN_ROLE='supabase/migrations/'+MIGRATION_ELEVEN;
export const ROOT_SQL11_SHA256='02c93209f546880032cf38382c61e78a3de0b0073dd2cb88699319afc6f0f185';
export const MIGRATION_TWELVE='20261023072038_collect_admin_initial_email_proof_ack.sql';
export const MIGRATION_TWELVE_ROLE='supabase/migrations/'+MIGRATION_TWELVE;
export const ROOT_SQL12_SHA256='2c31440ae10176e7e9e5f0befefce8e1ca44e06149d3cc4471119920b3abf6df';
export const MIGRATION_THIRTEEN='20261023102707_collect_retire_admin_mfa_enrollment.sql';
export const MIGRATION_THIRTEEN_ROLE='supabase/migrations/'+MIGRATION_THIRTEEN;
export const ROOT_SQL13_SHA256='e11ee7110cc2eb3a8a6cf571532966711b6a9b737537b5b893c61d2b48d8e834';
export const MIGRATION_FOURTEEN='20261023174000_collect_stopped_admission_lifecycle.sql';
export const MIGRATION_FOURTEEN_ROLE='supabase/migrations/'+MIGRATION_FOURTEEN;
export const ROOT_SQL14_SHA256='db6f2f23ae1ae5a7de01d8145e84b0429717e73628443ff58054f29aab451e25';
export const ORIGINAL_NINE=Object.freeze({
 '20261020134444_collect_curated_platform_baseline.sql':'0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0',
 '20261020135932_collect_runtime_role_and_function_paths.sql':'59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1',
 '20261020174856_collect_retention_retry_authority.sql':'d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c',
 '20261020184012_collect_admin_invitation_attempts.sql':'c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665',
 '20261020190301_collect_rls_helper_permissions.sql':'dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645',
 '20261020191847_collect_privacy_email_reauthentication.sql':'d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4',
 '20261020193752_collect_admin_invitation_access_notice_v2.sql':'b48a381169e777160a37396539248325e40b331a61db986622514724517f8467',
 '20261020195249_collect_admin_invitation_public_id_preservation.sql':'78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850',
 '20261022195747_collect_application_mutation_fence.sql':'714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497',
});
export const EXACT_TEN=Object.freeze([...Object.keys(ORIGINAL_NINE),MIGRATION_TEN]);
export const EXACT_CURRENT11=Object.freeze([...EXACT_TEN,MIGRATION_ELEVEN]);
export const EXACT_CURRENT12=Object.freeze([...EXACT_CURRENT11,MIGRATION_TWELVE]);
export const EXACT_CURRENT13=Object.freeze([...EXACT_CURRENT12,MIGRATION_THIRTEEN]);
export const EXACT_CURRENT14=Object.freeze([...EXACT_CURRENT13,MIGRATION_FOURTEEN]);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const need=(value,code)=>{if(!value)throw Error(code);};
const hex=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
// The descriptor is the independently reviewed static SQL10 binding. Runtime
// observations never populate or auto-admit it; only its two exact metadata
// literals may differ between hosted and synthetic SQL10 bytes.
export function validateBinding(value){
 need(value&&Object.keys(value).sort().join(',')==='format,hosted_metadata_sha256,hosted_sql_sha256,interface_sha256,metadata_expression_sha256,metadata_literal_occurrences,migration,project_ref,review_evidence_sha256,status,synthetic_metadata_sha256,synthetic_sql_sha256','REALTIME_BINDING_SHAPE_REQUIRED');
 need(value.format==='collect.member.realtime.fixture-binding.v1'&&value.status==='reviewed_static_binding'&&value.project_ref==='rrlduytparvsjfmegalh'&&value.migration===MIGRATION_TEN&&value.metadata_literal_occurrences===2,'REVIEWED_REALTIME_FIXTURE_BINDING_REQUIRED');
 for(const key of ['hosted_metadata_sha256','hosted_sql_sha256','interface_sha256','metadata_expression_sha256','review_evidence_sha256','synthetic_metadata_sha256','synthetic_sql_sha256'])need(hex(value[key]),'REVIEWED_REALTIME_FIXTURE_HASH_REQUIRED');
 need(value.hosted_metadata_sha256!==value.synthetic_metadata_sha256,'DISTINCT_LOCAL_AND_HOSTED_METADATA_REQUIRED');return value;
}
export function renderSyntheticSql(hosted,binding){
 const plan=validateBinding(binding);need(sha(hosted)===plan.hosted_sql_sha256,'HOSTED_REALTIME_SOURCE_CHANGED');
 const needle="'"+plan.hosted_metadata_sha256+"'";
 need(hosted.split(needle).length-1===plan.metadata_literal_occurrences,'REALTIME_METADATA_LITERAL_COUNT_CHANGED');
 const synthetic=hosted.split(needle).join("'"+plan.synthetic_metadata_sha256+"'");
 need(sha(synthetic)===plan.synthetic_sql_sha256,'SYNTHETIC_REALTIME_SOURCE_CHANGED');
 // Exact inverse proves every code byte outside the two reviewed literals.
 need(synthetic.split("'"+plan.synthetic_metadata_sha256+"'").join(needle)===hosted,'REALTIME_CODE_PARITY_REQUIRED');return synthetic;
}
export const fixtureIdentitySql=`DO $fixture_identity$
DECLARE u record;
BEGIN
 IF pg_catalog.current_database() !~ '^collect_[a-z0-9_]+_test$'
 OR coalesce(pg_catalog.host(pg_catalog.inet_server_addr()),'') NOT IN('127.0.0.1','::1')
 OR pg_catalog.current_setting('server_version_num')::integer/10000<>17
 OR current_user<>'collect_test' OR session_user<>'collect_test'
 OR pg_catalog.pg_get_userbyid((SELECT datdba FROM pg_catalog.pg_database WHERE datname=pg_catalog.current_database()))<>(CASE WHEN pg_catalog.current_database()='collect_sql_maintenance_test' THEN 'postgres' ELSE 'collect_test' END) THEN
 RAISE EXCEPTION 'REALTIME_OWNED_LOOPBACK_FIXTURE_REQUIRED';END IF;
 SELECT rolsuper,rolbypassrls INTO STRICT u FROM pg_catalog.pg_roles WHERE rolname=current_user;
 IF NOT u.rolsuper OR NOT u.rolbypassrls THEN RAISE EXCEPTION 'EXPLICIT_LOCAL_DEFINER_OWNER_PROFILE_REQUIRED';END IF;
END;$fixture_identity$;`;
export const restrictedPostgresSql="DO $$DECLARE p record;BEGIN SELECT rolcanlogin,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolbypassrls,rolreplication INTO STRICT p FROM pg_catalog.pg_roles WHERE rolname='postgres';IF p.rolcanlogin OR p.rolsuper OR p.rolinherit OR p.rolcreaterole OR p.rolcreatedb OR p.rolbypassrls OR p.rolreplication THEN RAISE EXCEPTION 'RESTRICTED_POSTGRES_FIXTURE_REQUIRED';END IF;END$$;";
async function bytesAt(root,role){const path=resolve(root,role);need(await realpath(path)===path,'FIXED_PHYSICAL_FIXTURE_SOURCE_REQUIRED');return readFile(path);}
export async function loadOriginalNine(root,{requireTen=true}={}){
 // Historical callers may still pass requireTen:false to consume the nine
 // returned prefixes. Disk admission validates the exact current fourteen-file
 // chain, while consumers may continue applying the reviewed SQL11 prefix.
 need(typeof requireTen==='boolean','BOOLEAN_LEGACY_LOADER_OPTION_REQUIRED');
 root=root instanceof URL?fileURLToPath(root):root;
 const names=(await readdir(resolve(root,'supabase/migrations'))).filter(name=>/^\d{14}_.*\.sql$/.test(name)).sort();
 need(JSON.stringify(names)===JSON.stringify(EXACT_CURRENT14),'EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED');
 need(hex(ROOT_SQL11_SHA256),'ROOT_SQL11_SHA256_REQUIRED');
 need(hex(ROOT_SQL12_SHA256),'ROOT_SQL12_SHA256_REQUIRED');
 need(hex(ROOT_SQL13_SHA256),'ROOT_SQL13_SHA256_REQUIRED');
 need(hex(ROOT_SQL14_SHA256),'ROOT_SQL14_SHA256_REQUIRED');
 const authBytes=await bytesAt(root,'supabase/tests/sql/00_local_auth_fixture.sql');need(sha(authBytes)===AUTH_FIXTURE_SHA256,'MANAGED_AUTH_FIXTURE_CHANGED');
 const originals=[];for(const[name,pin]of Object.entries(ORIGINAL_NINE)){const bytes=await bytesAt(root,'supabase/migrations/'+name);need(sha(bytes)===pin,'ORIGINAL_MIGRATION_CHANGED');originals.push({name,bytes,sql:bytes.toString('utf8'),sha256:pin});}
 const tenthBytes=await bytesAt(root,'supabase/migrations/'+MIGRATION_TEN),successorBytes=await bytesAt(root,MIGRATION_ELEVEN_ROLE),proofBytes=await bytesAt(root,MIGRATION_TWELVE_ROLE),retirementBytes=await bytesAt(root,MIGRATION_THIRTEEN_ROLE);
 need(sha(tenthBytes)===MIGRATION_TEN_SHA256,'REVIEWED_TENTH_MIGRATION_CHANGED');
 need(sha(successorBytes)===ROOT_SQL11_SHA256,'REVIEWED_SUCCESSOR_MIGRATION_CHANGED');
 need(sha(proofBytes)===ROOT_SQL12_SHA256,'REVIEWED_INITIAL_EMAIL_PROOF_MIGRATION_CHANGED');
 need(sha(retirementBytes)===ROOT_SQL13_SHA256,'REVIEWED_MFA_RETIREMENT_MIGRATION_CHANGED');
 const stoppedBytes=await bytesAt(root,MIGRATION_FOURTEEN_ROLE);
 need(sha(stoppedBytes)===ROOT_SQL14_SHA256,'REVIEWED_STOPPED_ADMISSION_MIGRATION_CHANGED');
 return{auth:authBytes.toString('utf8'),authBytes,originals,
  successor:{name:MIGRATION_ELEVEN,bytes:successorBytes,sql:successorBytes.toString('utf8'),sha256:ROOT_SQL11_SHA256},
  initialEmailProof:{name:MIGRATION_TWELVE,bytes:proofBytes,sql:proofBytes.toString('utf8'),sha256:ROOT_SQL12_SHA256},
  mfaRetirement:{name:MIGRATION_THIRTEEN,bytes:retirementBytes,sql:retirementBytes.toString('utf8'),sha256:ROOT_SQL13_SHA256},
  stoppedAdmissionLifecycle:{name:MIGRATION_FOURTEEN,bytes:stoppedBytes,sql:stoppedBytes.toString('utf8'),sha256:ROOT_SQL14_SHA256}};
}
export async function loadReviewedPlatformFixture(root,{includeInitialEmailProofMigration=false,includeMfaRetirementMigration=false,includeStoppedAdmissionLifecycleMigration=false}={}){
 need(typeof includeInitialEmailProofMigration==='boolean','BOOLEAN_INITIAL_EMAIL_PROOF_MIGRATION_OPTION_REQUIRED');
 need(typeof includeMfaRetirementMigration==='boolean','BOOLEAN_MFA_RETIREMENT_MIGRATION_OPTION_REQUIRED');
 need(typeof includeStoppedAdmissionLifecycleMigration==='boolean','BOOLEAN_STOPPED_ADMISSION_MIGRATION_OPTION_REQUIRED');
 root=root instanceof URL?fileURLToPath(root):root;
 const bindingBytes=await readFile(resolve(here,'member-realtime-fixture-plan.json'));
 const binding=validateBinding(JSON.parse(bindingBytes.toString('utf8'))),bindingSourceSha=sha(bindingBytes);
 const original=await loadOriginalNine(root);
 const [interfaceBytes,metadataBytes,hostedBytes]=await Promise.all([readFile(resolve(here,'member-realtime-interface.sql')),readFile(resolve(here,'member-realtime-metadata.sql')),bytesAt(root,'supabase/migrations/'+MIGRATION_TEN)]);
 need(sha(interfaceBytes)===binding.interface_sha256&&sha(metadataBytes)===binding.metadata_expression_sha256,'REVIEWED_REALTIME_FIXTURE_INPUT_CHANGED');
 const hosted=hostedBytes.toString('utf8'),synthetic=renderSyntheticSql(hosted,binding);
 need(binding.hosted_sql_sha256===MIGRATION_TEN_SHA256,'FIXED_HOSTED_TENTH_SOURCE_REQUIRED');
 const rawMigrations=[...original.originals,{name:MIGRATION_TEN,bytes:hostedBytes,sql:hosted,sha256:binding.hosted_sql_sha256},original.successor,
  ...(includeInitialEmailProofMigration||includeMfaRetirementMigration||includeStoppedAdmissionLifecycleMigration?[original.initialEmailProof]:[]),
  ...(includeMfaRetirementMigration||includeStoppedAdmissionLifecycleMigration?[original.mfaRetirement]:[]),
  ...(includeStoppedAdmissionLifecycleMigration?[original.stoppedAdmissionLifecycle]:[])];
 return{
  auth:original.auth,names:includeStoppedAdmissionLifecycleMigration?EXACT_CURRENT14:includeMfaRetirementMigration?EXACT_CURRENT13:includeInitialEmailProofMigration?EXACT_CURRENT12:EXACT_CURRENT11,rawMigrations,binding,successor:original.successor,
  initialEmailProof:original.initialEmailProof,includeInitialEmailProofMigration,mfaRetirement:original.mfaRetirement,includeMfaRetirementMigration,
  stoppedAdmissionLifecycle:original.stoppedAdmissionLifecycle,includeStoppedAdmissionLifecycleMigration,
  async parity(){need(sha(await readFile(resolve(here,'member-realtime-fixture-plan.json')))===bindingSourceSha,'REALTIME_FIXTURE_REVIEW_CHANGED');await loadReviewedPlatformFixture(root,{includeInitialEmailProofMigration,includeMfaRetirementMigration,includeStoppedAdmissionLifecycleMigration});},
  /** @param {(sql: string) => PromiseLike<unknown>} execute
   * @param {{includeAuth?: boolean,includeSuccessor?: boolean}} [options] */
  async apply(execute,{includeAuth=false,includeSuccessor=true}={}){
   need(typeof includeAuth==='boolean'&&typeof includeSuccessor==='boolean','BOOLEAN_FIXTURE_OPTIONS_REQUIRED');
   need(!includeInitialEmailProofMigration||includeSuccessor,'INITIAL_EMAIL_PROOF_REQUIRES_SQL11_SUCCESSOR');
   need(!includeMfaRetirementMigration||includeSuccessor,'MFA_RETIREMENT_REQUIRES_SQL11_SUCCESSOR');
   need(!includeStoppedAdmissionLifecycleMigration||includeSuccessor,'STOPPED_ADMISSION_REQUIRES_SQL11_SUCCESSOR');
   // All modes have already admitted all14 files. Prefix-only application is
   // explicit for genuine initialize/drain/source-upgrade qualification only.
   await execute(fixtureIdentitySql);
   if(includeAuth)await execute(original.auth);
   await execute(restrictedPostgresSql);
   for(const item of original.originals)await execute(item.sql);
   // Callers retain their existing owned reset; the loader never erases an
   // existing interface, archive, app row, admission or other fixture database.
   await execute("DO $$BEGIN IF pg_catalog.to_regnamespace('realtime') IS NOT NULL THEN RAISE EXCEPTION 'PRISTINE_REALTIME_FIXTURE_REQUIRED';END IF;END$$;");
   await execute(interfaceBytes.toString('utf8'));
   // Hosted binding must fail on this genuinely different local profile.
   // Do not assert merely that the two input hash strings differ.
   let refused=false;
   try{await execute(hosted);}catch(error){refused=error?.code==='55000'&&error?.message==='member_realtime_metadata_not_reviewed';}
   finally{await execute('ROLLBACK');}
   need(refused,'HOSTED_REALTIME_BINDING_MUST_REFUSE_LOCAL_PROFILE');
   await execute("DO $$BEGIN IF pg_catalog.to_regclass('private.member_realtime_control') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='realtime.messages'::regclass) THEN RAISE EXCEPTION 'HOSTED_REFUSAL_MUST_ROLL_BACK';END IF;END$$;");
   await execute(synthetic);
   await execute("DO $$BEGIN IF (SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname='private')<>18 OR(SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgname='collect_fence_statement_v1' AND tgenabled='A' AND tgtype=62)<>111 OR(SELECT enabled FROM private.member_realtime_control WHERE singleton) THEN RAISE EXCEPTION 'EXACT_TEN_INACTIVE_FIXTURE_REQUIRED';END IF;END$$;");
   await execute("DO $$BEGIN IF EXISTS(SELECT 1 FROM private.collect_fence_control) OR EXISTS(SELECT 1 FROM private.collect_fence_operations) OR EXISTS(SELECT 1 FROM private.collect_fence_admissions) OR EXISTS(SELECT 1 FROM private.collect_fence_scheduler_lifecycle) THEN RAISE EXCEPTION 'UNINITIALIZED_FENCE_FIXTURE_REQUIRED';END IF;END$$;");
   if(includeSuccessor){
    await execute(original.successor.sql);
    await execute("DO $$BEGIN IF (SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname='private')<>21 OR(SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgname='collect_fence_statement_v1' AND tgenabled='A' AND tgtype=62)<>113 OR EXISTS(SELECT 1 FROM private.collect_fence_control) OR EXISTS(SELECT 1 FROM private.collect_fence_operations) OR EXISTS(SELECT 1 FROM private.collect_fence_admissions) OR EXISTS(SELECT 1 FROM private.collect_fence_scheduler_lifecycle) OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades) OR (SELECT enabled FROM private.member_realtime_control WHERE singleton) THEN RAISE EXCEPTION 'EXACT_CURRENT11_UNINITIALIZED_FIXTURE_REQUIRED';END IF;END$$;");
    if(includeInitialEmailProofMigration||includeMfaRetirementMigration||includeStoppedAdmissionLifecycleMigration)await execute(original.initialEmailProof.sql);
    if(includeMfaRetirementMigration||includeStoppedAdmissionLifecycleMigration)await execute(original.mfaRetirement.sql);
    // The caller must supply a real postgres owner session for SQL14. This
    // loader never elevates identities, rewrites SQL or relaxes owner guards.
    if(includeStoppedAdmissionLifecycleMigration)await execute(original.stoppedAdmissionLifecycle.sql);
   }
  }
 };
}
