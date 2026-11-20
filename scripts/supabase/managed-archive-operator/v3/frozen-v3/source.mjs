import {fileURLToPath} from 'node:url';
import {verifyManifestFile} from '../source-manifest.mjs';
const path=fileURLToPath(new URL('./SOURCE-PINS.json',import.meta.url));
export async function verifyV3(expected){
 const required=[process.execPath,...['source.mjs','journal.mjs','identity.mjs','worker.mjs','runner.mjs'].map(x=>fileURLToPath(new URL('./'+x,import.meta.url))),
  ...['archive-core.mjs','input.mjs','source-manifest.mjs'].map(x=>fileURLToPath(new URL('../'+x,import.meta.url))),
  fileURLToPath(new URL('../../../../supabase/migrations/20261101012309_collect_admission_archive.sql',import.meta.url))];
 return verifyManifestFile(path,expected,{required});
}
