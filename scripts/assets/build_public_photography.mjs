// Package existing Collect photos for web delivery. Originals and dimensions
// stay unchanged; this does not confer visual or release acceptance.
// Requires sharp 0.35.4 (NODE_PATH may point to a bundled installation).
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const sharp=createRequire(import.meta.url)('sharp');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const mode=process.argv[2]||'--check';
if(!['--check','--write'].includes(mode)||process.argv.length>3)throw new Error('Use --check or --write');
if(sharp.versions.sharp!=='0.35.4'||sharp.versions.webp!=='1.6.0')throw new Error('Expected sharp0.35.4 and libwebp1.6.0');
const bank='assets/marketing/rwanda';
const directory='web/public/photography';
const manifestPath=path.join(root,directory,'manifest.json');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const script=await fs.readFile(fileURLToPath(import.meta.url));
const manifest={schema_version:1,generator:'scripts/assets/build_public_photography.mjs',generator_sha256:hash(script),
  encoder:{sharp:sharp.versions.sharp,webp:sharp.versions.webp},
  operation:'Full-resolution WebP delivery encoding; opaque photos quality92, alpha photos quality95 with lossless alpha. No resize, crop, redraw or source replacement.',
  acceptance:'Packaging evidence only; visual review, measured performance and release acceptance remain separate.',records:[]};
if(mode==='--write')await fs.mkdir(path.join(root,directory),{recursive:true});
for(const filename of (await fs.readdir(path.join(root,bank))).filter(file=>file.endsWith('.png')).sort()){
  if(!/^[a-z0-9-]+\.png$/.test(filename))throw new Error('Unexpected photo filename');
  const source=bank+'/'+filename,input=await fs.readFile(path.join(root,source));
  const original=await sharp(input).metadata();
  if(original.orientation&&original.orientation!==1)throw new Error('Photo orientation needs explicit review: '+filename);
  const options={quality:original.hasAlpha?95:92,alphaQuality:100,smartSubsample:true,exact:true,effort:6};
  const bytes=await sharp(input).keepIccProfile().webp(options).toBuffer();
  const metadata=await sharp(bytes).metadata();
  const before=await sharp(input).ensureAlpha().raw().toBuffer();
  const after=await sharp(bytes).ensureAlpha().raw().toBuffer();
  if(original.width!==metadata.width||original.height!==metadata.height||before.length!==after.length)throw new Error('Photo dimensions changed');
  if(hash(original.icc||Buffer.alloc(0))!==hash(metadata.icc||Buffer.alloc(0)))throw new Error('Photo colour profile changed');
  let absolute=0,squared=0,maximum=0;
  for(let index=0;index<before.length;index++){
    const difference=Math.abs(before[index]-after[index]);
    if(index%4===3&&difference!==0)throw new Error('Photo alpha changed');
    absolute+=difference;squared+=difference*difference;maximum=Math.max(maximum,difference);
  }
  const digest=hash(bytes),name=filename.replace(/\.png$/,'')+'-'+digest.slice(0,12)+'.webp';
  const file=directory+'/'+name,output=path.join(root,file);
  if(mode==='--write'){
    try{await fs.writeFile(output,bytes,{flag:'wx'});}
    catch(error){if(error.code!=='EEXIST'||!bytes.equals(await fs.readFile(output)))throw error;}
  }else if(!bytes.equals(await fs.readFile(output)))throw new Error('Photo delivery artifact differs from deterministic encoding: '+file);
  if(hash(await fs.readFile(path.join(root,source)))!==hash(input))throw new Error('Original photo changed during packaging');
  manifest.records.push({source,source_sha256:hash(input),source_bytes:input.length,file,
    url:'/assets/marketing/rwanda/'+name,sha256:digest,bytes:bytes.length,width:original.width,height:original.height,
    has_alpha:original.hasAlpha,options,alpha_unchanged:true,colour_profile_unchanged:true,
    source_decoded_rgba_sha256:hash(before),encoded_decoded_rgba_sha256:hash(after),
    mean_absolute_channel_difference:absolute/before.length,root_mean_square_channel_difference:Math.sqrt(squared/before.length),maximum_channel_difference:maximum});
}
if(!manifest.records.length)throw new Error('No original photographs');
manifest.original_bytes=manifest.records.reduce((sum,item)=>sum+item.source_bytes,0);
manifest.delivery_bytes=manifest.records.reduce((sum,item)=>sum+item.bytes,0);
const content=JSON.stringify(manifest,null,2)+'\n';
if(mode==='--write'){
  const temporary=manifestPath+'.'+process.pid+'.tmp';
  try{await fs.writeFile(temporary,content,{flag:'wx'});await fs.rename(temporary,manifestPath);}
  finally{await fs.rm(temporary,{force:true});}
}else if(content!==await fs.readFile(manifestPath,'utf8'))throw new Error('Photo manifest is stale; review and run --write');
console.log(JSON.stringify({status:'pass',mode,photos:manifest.records.length,original_bytes:manifest.original_bytes,delivery_bytes:manifest.delivery_bytes,final_acceptance:false}));
