// Explicit, disposable Docker fixture; never connects to source or production.
import {spawnSync} from 'node:child_process';
import {readFileSync,statfsSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {FINANCIAL_CATALOG_SQL} from '../financial-import/import.mjs';
import {NATIVE_FIXTURE_TABLES,NATIVE_RECONCILE_TABLES} from './import.mjs';
const context=process.env.COLLECT_SYNTHETIC_DOCKER_CONTEXT;
if(!context||!/^[A-Za-z0-9._-]{1,80}$/.test(context))throw Error('explicit_fixture_context_required');
const cli=['--context',context],image='public.ecr.aws/supabase/postgres:17.11.0.006',token=randomUUID(),name='codex-native-catalog-'+token.slice(0,8);
const expected='45cf01453223af34873bb6d0a0e11d699197da47b9519a2baa35c91ac97ca228',imageId='sha256:c141fd17ac6a76c4323e90b3aee8ff1a23d2e89e547c2b963cfadc309c079cc2';
const reconcileExpected='da829d544c323238102d046c898e919f696c726c4fc9d690532a567236296b64';
let id,removed=false,error=null,observed=null,reconcileObserved=null;
function processDocker(args,input){return spawnSync('docker',[...cli,...args],{input,encoding:'utf8',timeout:30000,maxBuffer:2000000});}
function run(args,input){const p=processDocker(args,input);if(p.status!==0||p.error)throw Error('synthetic_container_failed');return p.stdout.trim();}
try{
 const disk=statfsSync(process.cwd());if(BigInt(disk.bavail)*BigInt(disk.bsize)<BigInt(3*2**30+48*2**20))throw Error('disk_reserve_reached');
 if(run(['image','inspect',image,'--format','{{.Id}}'])!==imageId)throw Error('image_changed');
 if(processDocker(['inspect',name]).status===0)throw Error('fixture_name_exists');
 id=run(['create','--pull','never','--name',name,'--label','io.collect.native-catalog='+token,'--network','none','--memory','768m','--cpus','1','--user','postgres','--tmpfs','/tmp:rw,size=256m,mode=1777','--env','PGDATA=/tmp/pgdata','--entrypoint','sh',image,'-c','initdb -D "$PGDATA" -U fixture_bootstrap -A trust --encoding=UTF8 --no-locale >/dev/null && exec postgres -D "$PGDATA" -c listen_addresses= -c unix_socket_directories=/tmp']);
 const inspect=JSON.parse(run(['inspect',id]))[0];if(inspect.Name!=='/'+name||inspect.Image!==imageId||inspect.Config.Labels['io.collect.native-catalog']!==token||inspect.HostConfig.NetworkMode!=='none'||inspect.Mounts.length||Object.keys(inspect.HostConfig.PortBindings??{}).length)throw Error('fixture_isolation_failed');
 run(['start',id]);let ready=false;
 for(let i=0;i<100;i++){if(processDocker(['exec',id,'pg_isready','-h','/tmp','-U','fixture_bootstrap']).status===0){ready=true;break;}await new Promise(r=>setTimeout(r,100));}
 if(!ready)throw Error('fixture_unavailable');
 const psql=(db,sql)=>run(['exec','-i',id,'psql','-h','/tmp','-U','fixture_bootstrap','-d',db,'-XAtq','-v','ON_ERROR_STOP=1'],sql);
 psql('postgres','CREATE ROLE fixture_operator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;');
 psql('postgres','CREATE DATABASE collect_financial_import_fixture OWNER fixture_bootstrap;');
 psql('collect_financial_import_fixture',readFileSync(new URL('../financial-import/fixture.sql',import.meta.url),'utf8'));
 psql('collect_financial_import_fixture',readFileSync(new URL('./fixture.sql',import.meta.url),'utf8'));
 const arr='ARRAY['+NATIVE_FIXTURE_TABLES.map(x=>"'"+x+"'").join(',')+']::text[]';
 observed=psql('collect_financial_import_fixture',FINANCIAL_CATALOG_SQL.replace('$1::text[]',arr));
 if(observed!==expected)throw Error('fixture_catalog_mismatch');
 const target='ARRAY['+NATIVE_RECONCILE_TABLES.map(x=>"'"+x+"'").join(',')+']::text[]';
 reconcileObserved=psql('collect_financial_import_fixture',FINANCIAL_CATALOG_SQL.replace('$1::text[]',target));
 if(reconcileObserved!==reconcileExpected)throw Error('reconciliation_catalog_mismatch');
}catch(e){error=e.message;}
finally{if(id){const result=processDocker(['inspect',id]);const value=result.status===0?JSON.parse(result.stdout)[0]:null;
 if(value?.Name==='/'+name&&value?.Config?.Labels?.['io.collect.native-catalog']===token)removed=processDocker(['rm','-f',id]).status===0;}}
process.stdout.write(JSON.stringify({status:!error&&removed?'pass':'failed',catalog_sha256:observed,reconciliation_catalog_sha256:reconcileObserved,error,removed,network:'none',synthetic_only:true})+'\n');
if(error||!removed)process.exitCode=1;
