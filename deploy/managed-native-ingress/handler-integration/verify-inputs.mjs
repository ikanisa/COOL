import {createHash} from 'node:crypto';
import {readFile,realpath} from 'node:fs/promises';
import {dirname,isAbsolute,relative,resolve,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const here=dirname(fileURLToPath(import.meta.url)),root=resolve(here,'../../..');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const inside=(base,name)=>{const target=resolve(base,name),r=relative(base,target);if(isAbsolute(name)||r===''||r==='..'||r.startsWith('..'+sep))throw Error('invalid_manifest_path');return target;};
export async function verifyInputs({expectedRoot}={}){
 const manifest=JSON.parse(await readFile(resolve(here,'input-manifest.json'),'utf8'));
 const actual=await realpath(root);
 if(manifest.format!=='collect.managed-native-handler-integration.input-manifest.v1')throw Error('checkout_changed');
 if(expectedRoot===undefined){if(actual!==manifest.checkout_root)throw Error('checkout_changed');}
 else{
  if(typeof expectedRoot!=='string'||!isAbsolute(expectedRoot))throw Error('checkout_changed');
  let requested;try{requested=await realpath(expectedRoot);}catch{throw Error('checkout_changed');}
  if(resolve(expectedRoot)!==actual||requested!==actual)throw Error('checkout_changed');
 }
 for(const [base,entries] of [[root,manifest.source_inputs],[here,manifest.proposal_files]]){
  if(!entries||typeof entries!=='object'||Array.isArray(entries))throw Error('invalid_manifest');
  for(const [name,expected] of Object.entries(entries)){
   if(typeof expected!=='string'||!/^[a-f0-9]{64}$/.test(expected)||sha(await readFile(inside(base,name)))!==expected)throw Error('input_changed: '+name);
  }
 }
 return true;
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
 try{await verifyInputs();console.log('handler integration inputs match');}catch(error){console.error(error.message);process.exitCode=1;}
}
