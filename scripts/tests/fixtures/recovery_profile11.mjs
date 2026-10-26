// Fixed generated synthetic historical11 data, never an observed hosted backup.
// The producer/actual Worker-D1 qualification and hashes are retained in metadata.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {quarantineSchemaProfiles} from '../../cloudflare/recovery_quarantine.mjs';
const sha=raw=>createHash('sha256').update(raw).digest('hex');
const sourceId='f'.repeat(64),database='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
export async function historical11Fixture(root){
 const metadata=JSON.parse(await readFile(new URL('recovery_profile11.metadata.json',import.meta.url),'utf8'));
 const sql=await readFile(new URL('recovery_profile11.sql',import.meta.url));
 assert.equal(metadata.never_primary_capture,true);assert.equal(metadata.actual_provider_source_database_id,null);
 assert.equal(sql.length,metadata.sql_bytes);assert.equal(sha(sql),metadata.sql_sha256);assert.equal(metadata.counts.privacy_retention_tasks,84);
 const values={'database.sql':sql,'wrangler.json':JSON.stringify({name:'collect-platform-api',d1_databases:[{binding:'DB',database_name:'collect-platform',database_id:database}],vars:{BUILD_SOURCE_ID:sourceId,DATA_KEY_ID:'auth-test-v1',TURNSTILE_SITE_KEY:'0xSYNTHETIC_ISOLATED_TEST_WIDGET_ONLY',AUTH_IDENTITY_KEY_ID:'recovery-current-v2'}}),
  'worker-secrets.json':JSON.stringify({AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),TURNSTILE_SECRET:'SYNTHETIC_TURNSTILE_SECRET_NEVER_A_REAL_PROVIDER_KEY',AUTH_IDENTITY_HASH_KEY:Buffer.alloc(32,151).toString('base64'),AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({'recovery-old-v1':Buffer.alloc(32,152).toString('base64')})})};
 for(const [name,pin]of Object.entries(quarantineSchemaProfiles.candidate11.digests)){const raw=await readFile(new URL(name,root));assert.equal(sha(raw),pin);values[name]=raw;}
 return {payload:{format:'collect.platform.backup.v1',database_id:database,source_id:sourceId,captured_at:metadata.captured_at,files:Object.fromEntries(Object.entries(values).map(([name,value])=>{const raw=Buffer.from(value);return [name,{sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')}];}))},
  recoveryAt:metadata.recovery_at,actor:metadata.actor,subject:metadata.subject,objectClaim:metadata.object_claim,counts:metadata.counts,observations:metadata.observations,historical_generated_fixture:true};
}
