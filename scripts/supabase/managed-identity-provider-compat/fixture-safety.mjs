// Narrow launch checks for this local-only synthetic fixture. Shared libraries,
// OS, loader and code running before these checks remain trusted inputs.
import {createHash} from 'node:crypto';
import {lstat,readFile,realpath} from 'node:fs/promises';
import {join} from 'node:path';
export const BIN='/Volumes/PRO-G40/Development/Supabase/Qwen-Validation/cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin';
const pins=Object.freeze({
 initdb:'1a53edc7a433f9cc789b968d97ef8bd99fd12377dca09022b578558844720d82',
 postgres:'9058a8740787c17c4736be5945369bd9ddeff189743a3ce1032383d23a1e356c',
 pg_ctl:'8a2bada4e252f1ff2ed4b0bea33246608b85b6711e29926e8b5c90a016a384a1',
 pg_isready:'b70711c575b302ebdc117ccf0e57751a2e250cfa8e763f18e88931479b575e25',
 '.initdb-wrapped':'bc065589e19531dfb7f0c2cef8030099d14c5616368a0612d89be62c88b430ba',
 '.postgres-wrapped':'acbf2c5c218837bc8f098d631091854569db5b791cb475f5f943e49f8d4cd053',
 '.pg_ctl-wrapped':'5829455d993811e30f19a1288da7a58de3d4ddcd834c0804cdcf69db6577cc7d',
 '.pg_isready-wrapped':'44e9d0de06eb85eeb141463b27cd54cf696965a240865f03e314053eb5b9a88e'
});
export function verifyEnvironment(env){
 if(!env||typeof env!=='object')throw new Error('SYNTHETIC_ENVIRONMENT_REQUIRED');
 for(const [key,value] of Object.entries(env))if(value&&/^(?:PG[A-Z_0-9]*|SUPABASE_.*|DATABASE_URL|POSTGRES_URL)$/i.test(key))
  throw new Error('MANAGED_OR_EXTERNAL_CONNECTION_REFUSED');
 if(env.COLLECT_SYNTHETIC_PG_BIN&&env.COLLECT_SYNTHETIC_PG_BIN!==BIN)throw new Error('SYNTHETIC_BINARY_REQUIRED');
}
export async function verifyBinaryPins(){
 if(await realpath(BIN)!==BIN)throw new Error('SYNTHETIC_BINARY_REQUIRED');
 for(const [name,pin] of Object.entries(pins)){
  const path=join(BIN,name),s=await lstat(path);
  if(!s.isFile()||s.isSymbolicLink()||await realpath(path)!==path||s.size>128*1024*1024)throw new Error('SYNTHETIC_BINARY_REQUIRED');
  if(createHash('sha256').update(await readFile(path)).digest('hex')!==pin)throw new Error('SYNTHETIC_BINARY_CHANGED');
 }
}
