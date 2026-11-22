// Local build only. Deployment and dependency installation are separate.
import {createRequire} from 'node:module';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {dirname,join,resolve} from 'node:path';
const require=createRequire(import.meta.url),esbuild=require('esbuild');
if(esbuild.version!=='0.28.2')throw Error('esbuild_version_mismatch');
async function packageRoot(name,version,override){
 let dir=override?resolve(override):dirname(require.resolve(name));
 while(true){try{const p=JSON.parse(await readFile(join(dir,'package.json'),'utf8'));if(p.name===name){if(p.version!==version)throw Error('dependency_version_mismatch');return dir;}}catch(error){if(error?.message==='dependency_version_mismatch')throw error;}
  const next=dirname(dir);if(next===dir)throw Error('dependency_not_found');dir=next;}
}
const hono=await packageRoot('hono','4.13.16',process.env.COLLECT_SMS_BUILD_HONO_ROOT),postgres=await packageRoot('postgres','3.4.7',process.env.COLLECT_SMS_BUILD_POSTGRES_ROOT);
const plugin={name:'pinned-deno-npm-imports',setup(build){
 build.onResolve({filter:/^npm:hono@4\.13\.16$/},()=>({path:join(hono,'dist/index.js')}));
 build.onResolve({filter:/^npm:postgres@3\.4\.7$/},()=>({path:join(postgres,'cf/src/index.js')}));
}};
const result=await esbuild.build({entryPoints:['src/worker.ts'],outfile:'dist/worker.js',bundle:true,write:false,metafile:true,
 format:'esm',platform:'neutral',target:'es2022',conditions:['workerd','worker','browser'],external:['node:*','cloudflare:*'],plugins:[plugin]});
const output=result.outputFiles.find(f=>f.path.endsWith('/dist/worker.js'));if(!output)throw Error('bundle_missing');
const external=Object.values(result.metafile.outputs).flatMap(o=>o.imports.filter(i=>i.external).map(i=>i.path));
if(external.some(path=>!path.startsWith('node:')&&!path.startsWith('cloudflare:')))throw Error('unexpected_external_import');
await mkdir('dist',{recursive:true});await writeFile('dist/worker.js',output.contents);
console.log(JSON.stringify({bundle:'dist/worker.js',external,production_deployed:false}));
