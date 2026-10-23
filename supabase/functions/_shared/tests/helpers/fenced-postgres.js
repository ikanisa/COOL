import postgres from 'npm:postgres@3.4.7';
import {connection as actualConnection,PostgresDatabase as ActualDatabase,compileSql} from '../../postgres.js';
import {deferredApplicationWork,sqlFenceBackend} from '../../application-fence.js';
import {SYNTHETIC_FENCE_SOURCE,ownFixtureWork,finishFixtureWork} from './fenced-unit.js';
export {compileSql};
const urls=new WeakMap(),works=new WeakMap(),controls=new Set(),workKeys=new Set(),initializations=new WeakMap();
export function connection(url){const target=new URL(url);if(!['127.0.0.1','localhost'].includes(target.hostname))throw Error('Synthetic fence fixture requires loopback');const sql=actualConnection(url);urls.set(sql,url);return sql;}
export function initializeSqlFixture(sql){if(initializations.has(sql))return initializations.get(sql);const current=initialize(sql).finally(()=>initializations.delete(sql));initializations.set(sql,current);return current;}
async function initialize(sql){
 const exists=await sql.unsafe("SELECT to_regprocedure('private.collect_fence_owner_status()') AS present");if(!exists[0]?.present)return false;
 try{const row=(await sql.unsafe('SELECT private.collect_fence_owner_status() AS result'))[0].result;if(row.sourceSha256!==SYNTHETIC_FENCE_SOURCE||row.mode!=='open')throw Error('Synthetic fence source/mode changed');return true;}
 catch(error){if(error.message!=='collect_fence_unavailable')throw error;await sql.unsafe('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text)',[crypto.randomUUID(),SYNTHETIC_FENCE_SOURCE,'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3']);return true;}
}
function workFor(sql){
 if(works.has(sql))return works.get(sql);const url=urls.get(sql);if(!url)throw Error('Use the genuine synthetic connection fixture');
 // Separate from the runtime control pool: a long test-domain context must not
 // consume the one runtime request slot used by actual createHandler probes.
 const control=postgres(url,{max:1,prepare:false,ssl:false,onnotice:()=>{}});controls.add(control);
 const backend=sqlFenceBackend(sql,control);const register=backend.register;
 const work=ownFixtureWork(deferredApplicationWork({backend:{...backend,async register(...args){if(!await initializeSqlFixture(sql))throw Error('Synthetic fence schema not installed');return register(...args);}},sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'}));works.set(sql,work);workKeys.add(sql);return work;
}
export class PostgresDatabase extends ActualDatabase{constructor(sql,claims={}){super(sql,claims,workFor(sql));}}
export async function finishSqlFixtureWork(){await finishFixtureWork();for(const control of controls)await control.end({timeout:1});controls.clear();for(const sql of workKeys)works.delete(sql);workKeys.clear();}
