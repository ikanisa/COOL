import {execFile} from 'node:child_process';
import {lstat,mkdir,mkdtemp,readFile,realpath,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {gunzipSync} from 'node:zlib';
import {assertTrustedSourcePolicy,hash} from './momo_release_candidate.mjs';

const backend=new URL('../../deploy/platform-api/',import.meta.url);
const archiveDigest='cfa8a29f5f239f75275640d126b19154c851e6d7e202cc79ee61d017f48a40d8';
const run=promisify(execFile);

function requireSource(value,message) {
  if (!value) throw new Error(message);
}

async function readSource(name) {
  const file=fileURLToPath(new URL(name,backend));
  const info=await lstat(file);
  requireSource(info.isFile()&&await realpath(file)===file&&info.size<=1024*1024,'Invalid pinned MoMo15 source file');
  return readFile(file);
}

export async function readMomo15Source() {
  const archive=await readSource('history/momo15-source.json.gz');
  requireSource(hash(archive)===archiveDigest,'Exact MoMo15 source archive changed');
  const {format,files}=JSON.parse(gunzipSync(archive,{maxOutputLength:3*1024*1024}).toString('utf8'));
  requireSource(format==='collect.momo15.source-snapshot.v1'&&files&&typeof files==='object','Invalid MoMo15 source archive');
  const inventoryBytes=await readSource('operations-manifest-momo15.json');
  const inventory=JSON.parse(inventoryBytes);
  const config=await readSource('wrangler.momo15-source.jsonc');
  const contents=new Map([
    ['operations-manifest-momo15.json',inventoryBytes],
    ['wrangler.jsonc',config],
  ]);
  const expected=new Map([
    ['operations-manifest.json',inventory.predecessor_inventory.sha256],
    ['scripts/operation_inventory.mjs',inventory.producer.sha256],
    ...Object.entries(inventory.source_sha256).map(([name,digest])=>['src/'+name,digest]),
    ...Object.entries(inventory.migrations_sha256).map(([name,digest])=>['migrations/'+name,digest]),
  ]);
  requireSource(expected.size===67&&Object.keys(files).length===expected.size,'Incomplete MoMo15 source archive');
  for (const [name,digest] of expected) {
    requireSource(name.split('/').every(part=>/^[A-Za-z0-9_.-]+$/.test(part)&&part!=='.'&&part!=='..')
      &&Object.hasOwn(files,name)&&typeof files[name]==='string','Invalid MoMo15 source path');
    const bytes=Buffer.from(files[name],'base64');
    requireSource(hash(bytes)===digest,'Exact MoMo15 source input changed: '+name);
    contents.set(name,bytes);
  }
  requireSource(hash(config)===inventory.configuration_sha256,'Exact MoMo15 configuration changed');
  const roles=Object.fromEntries([...contents].map(([name,bytes])=>[name,{sha256:hash(bytes),bytes:bytes.length}]));
  assertTrustedSourcePolicy(roles);
  return {contents,roles};
}

export async function withMomo15Source(verify) {
  const {contents,roles}=await readMomo15Source();
  const root=await mkdtemp(join(await realpath(tmpdir()),'collect-momo15-source-'));
  try {
    await writeFile(join(root,'package.json'),'{"type":"module"}\n',{flag:'wx'});
    for (const [name,bytes] of contents) {
      const path=join(root,name);
      await mkdir(dirname(path),{recursive:true});
      await writeFile(path,bytes,{flag:'wx'});
    }
    return await verify(root,roles);
  } finally {
    await rm(root,{recursive:true,force:true});
  }
}

export async function checkMomo15Source() {
  return withMomo15Source(async(root,roles)=>{
    const {stdout}=await run(process.execPath,
      ['--permission','--allow-fs-read='+root,join(root,'scripts/operation_inventory.mjs'),'--check'],
      {cwd:root,env:{TZ:'UTC',NO_COLOR:'1'},timeout:15000,maxBuffer:1024*1024});
    const result=JSON.parse(stdout);
    requireSource(result.status==='pass'&&result.profile==='momo15_candidate','MoMo15 inventory regeneration failed');
    return {status:'pass',profile:result.profile,configuration_sha256:roles['wrangler.jsonc'].sha256,
      inventory_sha256:roles['operations-manifest-momo15.json'].sha256,source_roles:Object.keys(roles).length};
  });
}

if (process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.stdout.write(JSON.stringify(await checkMomo15Source())+'\n');
}
