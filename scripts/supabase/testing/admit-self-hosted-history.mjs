// Rebase only physical artifact paths. Never rewrite receipt bytes or source pins.
import {readFile,readdir,realpath,lstat,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {HISTORY_PROFILE,validateSelfHostedHistoryPacket,verifySelfHostedHistorySources} from './self-hosted-member-history.mjs';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const need=(ok,code)=>{if(!ok)throw Error(code);};
export async function admitHistoryArtifact(folder,output){
 need(resolve(folder)===folder&&await realpath(folder)===folder,'PHYSICAL_HISTORY_ARTIFACT_REQUIRED');
 const expected=['ACTUAL-HISTORY-PACKET.json','ACTUAL-SQL-STATEMENTS.json','DEFINES.json','INPUTS.json','RESULT.json'];
 need(JSON.stringify((await readdir(folder)).sort())===JSON.stringify(expected),'EXACT_HISTORY_ARTIFACT_INVENTORY_REQUIRED');
 const values={},hashes={};
 for(const name of expected){const path=join(folder,name),info=await lstat(path);need(info.isFile()&&!info.isSymbolicLink()&&info.size<=32*1024*1024,'REGULAR_BOUNDED_HISTORY_ARTIFACT_REQUIRED');
  const bytes=await readFile(path);hashes[name]=sha(bytes);values[name]=JSON.parse(bytes);}
 const packet=validateSelfHostedHistoryPacket(values['ACTUAL-HISTORY-PACKET.json']),result=values['RESULT.json'],inputs=values['INPUTS.json'],defines=values['DEFINES.json'];
 need(result.format==='collect.selfhost.history.capture.v3'&&result.status==='PASS'&&result.profile===HISTORY_PROFILE&&result.historical_current14_or_current16_acceptance===false&&result.provider_calls===0&&result.hosted_acceptance===false&&result.production_acceptance===false,'EXACT_CURRENT_HISTORY_RESULT_REQUIRED');
 need(result.packet_sha256===hashes['ACTUAL-HISTORY-PACKET.json']&&result.inputs_sha256===hashes['INPUTS.json']&&result.sql_sha256===hashes['ACTUAL-SQL-STATEMENTS.json']&&packet.source_inputs_sha256===hashes['INPUTS.json']&&packet.source_sha256===inputs.source_sha256&&result.source_sha256===inputs.source_sha256,'HISTORY_ARTIFACT_DIGEST_CHANGED');
 need(packet.SQL_statement_count===values['ACTUAL-SQL-STATEMENTS.json'].length,'ACTUAL_HISTORY_SQL_INVENTORY_REQUIRED');
 await verifySelfHostedHistorySources(inputs);
 const paths={SELFHOST_HISTORY_PACKET:'ACTUAL-HISTORY-PACKET.json',SELFHOST_HISTORY_INPUTS:'INPUTS.json',SELFHOST_HISTORY_SQL:'ACTUAL-SQL-STATEMENTS.json'};
 need(JSON.stringify(Object.keys(defines).sort())===JSON.stringify([...Object.keys(paths),...Object.keys(paths).map(key=>key+'_SHA256'),'SELFHOST_HISTORY_SOURCE_SHA256'].sort()),'EXACT_HISTORY_DEFINES_REQUIRED');
 need(defines.SELFHOST_HISTORY_SOURCE_SHA256===inputs.source_sha256,'HISTORY_SOURCE_DEFINE_CHANGED');
 for(const [key,name]of Object.entries(paths)){
  need(defines[key]===name&&defines[key+'_SHA256']===hashes[name],'HISTORY_PATH_OR_DIGEST_DEFINE_CHANGED');defines[key]=join(folder,name);
 }
 need(resolve(output)===output&&await realpath(resolve(output,'..'))===resolve(output,'..'),'PHYSICAL_DEFINE_OUTPUT_REQUIRED');
 await writeFile(output,JSON.stringify(defines,null,2)+'\n',{flag:'wx',mode:0o600});
 return {status:'PASS',profile:HISTORY_PROFILE,source_sha256:inputs.source_sha256};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{need(process.argv.length===4,'ARTIFACT_AND_FRESH_DEFINES_REQUIRED');console.log(JSON.stringify(await admitHistoryArtifact(resolve(process.argv[2]),resolve(process.argv[3]))));}
 catch(error){console.error(JSON.stringify({status:'FAIL',code:/^[A-Z0-9_]+$/.test(error.message)?error.message:'HISTORY_ARTIFACT_UNCONFIRMED'}));process.exitCode=1;}
}
