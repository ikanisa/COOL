import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir,lstat} from 'node:fs/promises';
import {resolve,relative,join} from 'node:path';
import {pathToFileURL} from 'node:url';

const hash=value=>createHash('sha256').update(value).digest('hex');
const identifier=value=>{if(!/^[a-z][a-z0-9_]*$/.test(value))throw new Error('Unexpected schema identifier');return '"'+value+'"';};
export async function schemaCatalog(root){
 const directory=join(root,'deploy/platform-api/migrations');
 const names=(await readdir(directory)).filter(n=>/^\d{4}_[a-z0-9_]+\.sql$/.test(n)).sort();
 if(!names.length||names.some((n,i)=>Number(n.slice(0,4))!==i+1))throw new Error('Non-contiguous source migration chain');
 const db=new DatabaseSync(':memory:');const migrations=[];
 try{
  db.exec('PRAGMA foreign_keys=ON');
  for(const name of names){const bytes=await readFile(join(directory,name));db.exec(bytes.toString('utf8'));migrations.push({name,sha256:hash(bytes)});}
  const objects=db.prepare("select type,name,tbl_name,sql from sqlite_schema where sql is not null and name not like 'sqlite_%' and name not like '_cf_%' order by type,name").all();
  const tables=objects.filter(x=>x.type==='table').map(t=>({name:t.name,sql_sha256:hash(t.sql),columns:db.prepare('PRAGMA table_info('+identifier(t.name)+')').all(),foreign_keys:db.prepare('PRAGMA foreign_key_list('+identifier(t.name)+')').all()}));
  return {migrations,tables,objects:objects.filter(x=>x.type!=='table').map(x=>({type:x.type,name:x.name,table:x.tbl_name,sha256:hash(x.sql)}))};
 }finally{db.close();}
}
async function filesUnder(root,folder){
 const result=[];
 async function walk(path){for(const name of (await readdir(path)).sort()){
  if(name.startsWith('._')||['node_modules','.git','.cache','build'].includes(name))continue;
  const full=join(path,name),stat=await lstat(full);
  if(stat.isSymbolicLink())throw new Error('Source inventory cannot follow symlinks');
  if(stat.isDirectory())await walk(full);
  else if(stat.isFile()&&/\.(?:js|mjs|sql|json|jsonc|toml)$/.test(name))result.push({path:relative(root,full),sha256:hash(await readFile(full)),bytes:stat.size});
 }}await walk(join(root,folder));return result;
}
export async function sourceInventory(root){
 root=resolve(root);const schema=await schemaCatalog(root);
 const {operationInventory}=await import(pathToFileURL(join(root,'deploy/platform-api/src/operations.js')));
 const files=await filesUnder(root,'deploy/platform-api');
 const directRouteReferences=[];
 for(const file of files.filter(f=>f.path.startsWith('deploy/platform-api/src/')&&f.path.endsWith('.js'))){
  const text=(await readFile(join(root,file.path),'utf8')).split('\n');
  text.forEach((line,index)=>{if(/(?:pathname|request\.method|url\.pathname|parts\[|\/api\/admin|\/v1\/|\/privacy\/account-deletion)/.test(line))directRouteReferences.push({source:file.path,line:index+1,sha256:hash(line)});});
 }
 return {format:'collect.supabase.source-inventory.v1',source_sha256:hash(JSON.stringify(files)),source_files:files,schema,registered_operations:operationInventory,direct_route_references:directRouteReferences,registry_is_total_endpoint_count:false,coverage_contract:'Registered operations plus every direct-route source reference require paired handler/consumer acceptance; references alone are not hosted parity.'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 sourceInventory(process.argv[2]??process.cwd()).then(value=>process.stdout.write(JSON.stringify(value,null,2)+'\n')).catch(()=>{console.error('Source inventory failed; no source data was changed');process.exitCode=1;});
}
