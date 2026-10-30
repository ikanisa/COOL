#!/usr/bin/env node
import {createInterface} from 'node:readline/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {configuration,SafeError,invalid} from './config.mjs';
import {RetentionApi} from './retention_api.mjs';
import {RetentionJournal} from './retention_journal.mjs';
import {RetentionOperator} from './retention_operator.mjs';

export const HELP=`Collect approved-scope retention operator

Read and prepare:
  context
  inspect <request-uuid> <review-revision> <source-sha256>
  status <plan-uuid>
  preview-plan <request-uuid> <review-revision> <source-sha256> <approved-policy-sha256>
  preview-claim <plan-uuid> <task-uuid>
  preview-execute <original-claim-operation-uuid>
  preview-resume-claim <original-execute-operation-uuid>
  preview-reconcile <plan-uuid>
  list
  show <preview-sha256>
  cancel <never-dispatched-preview-sha256>

Human-confirmed writes (terminal required; no --yes, pipes or MCP write tools):
  apply <preview-sha256>
  recover <original-operation-uuid>
  retry <original-preview-sha256>

Use npm run login for an approved account, then npm run verify-email to renew
fresh EMAIL proof in that same session. Save every original operation reference.
Recover is read-only. An unseen operation remains unknown; no automatic retry or
replacement UUID is issued. Retry reuses the original exact request and requires
new confirmation. A failed reconciliation is observed through current status;
it has no immutable operation receipt and cannot be retried by this command.

This tool cannot create retention approvals, bypass holds, erase the financial
journal, operate external processor/backups/export copies, or certify all-copy
erasure. The server must already hold a current approved policy bound to the
source, schema, reviewed subject, deadlines and verified copy inventories.
`;
const number=value=>{if(!/^(0|[1-9][0-9]{0,9})$/.test(value??''))invalid();return Number(value);};
export async function runRetentionCommand(operator,args,{confirm,interactive=false}={}){
 const [command,...values]=args;
 const arities={context:0,inspect:3,status:1,'preview-plan':4,'preview-claim':2,'preview-execute':1,'preview-resume-claim':1,'preview-reconcile':1,list:0,show:1,cancel:1,apply:1,recover:1,retry:1};
 if(!Object.hasOwn(arities,command)||values.length!==arities[command])invalid();
 if(['apply','retry'].includes(command)&&(!interactive||typeof confirm!=='function'))throw new SafeError('interactive_confirmation_required','Run this command directly in a terminal and confirm the exact saved preview. Automated confirmation is unavailable.');
 switch(command){
 case 'context':return operator.context();
 case 'inspect':return operator.inspect(values[0],number(values[1]),values[2]);
 case 'status':return operator.status(values[0]);
 case 'preview-plan':return operator.previewPlan(values[0],number(values[1]),values[2],values[3]);
 case 'preview-claim':return operator.previewClaim(...values);
 case 'preview-resume-claim':return operator.previewResumeClaim(values[0]);
 case 'preview-execute':return operator.previewExecute(values[0]);
 case 'preview-reconcile':return operator.previewReconcile(values[0]);
 case 'list':return operator.list();
 case 'show':return operator.show(values[0]);
 case 'cancel':return operator.cancel(values[0]);
 case 'apply':return operator.apply(values[0],confirm);
 case 'retry':return operator.apply(values[0],confirm,{retry:true});
 case 'recover':return operator.recover(values[0]);
 }
}
async function main(){
 const args=process.argv.slice(2);if(args.length===0||args.length===1&&['help','--help','-h'].includes(args[0])){process.stdout.write(HELP);return;}
 const config=configuration();let journal;
 try{
  journal=new RetentionJournal(config);const operator=new RetentionOperator(new RetentionApi(config),journal);
  const result=await runRetentionCommand(operator,args,{interactive:process.stdin.isTTY&&process.stderr.isTTY,confirm:async(preview,phrase)=>{
   process.stderr.write(JSON.stringify(preview,null,2)+'\n');
   process.stderr.write('Review this exact approved-scope operation. This may quarantine access or permanently remove only the listed eligible data. External copies and financial records are not erased.\n');
   const prompt=createInterface({input:process.stdin,output:process.stderr});try{return await prompt.question('Type '+phrase+' to dispatch once: ');}finally{prompt.close();}
  }});
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
 }finally{journal?.close();}
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url)main().catch(error=>{
 process.stderr.write((error instanceof SafeError?error.message:'Retention operation could not be verified. Preserve the private journal and original operation references; no automatic retry occurred.')+'\n');process.exitCode=1;
});
