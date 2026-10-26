import {lstat,mkdir,readdir,open} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {constants} from 'node:fs';
import {need,uuid,canonical,sha,sanitized,keys} from './contract.mjs';

export async function privateDirectory(path,{create=false}={}) {
  need(typeof path==='string'&&resolve(path)===path&&!/[\x00-\x1f\x7f]/.test(path),'absolute_private_directory_required');
  if(create)await mkdir(path,{mode:0o700});
  for(let current=path;current&&current!=='/';current=dirname(current))need(!(await lstat(current)).isSymbolicLink(),'aliased_private_state_refused');
  const stat=await lstat(path);
  need(stat.isDirectory()&&stat.uid===process.getuid()&&(stat.mode&0o077)===0,'private_owned_directory_required');
  return path;
}
export async function privateRead(path,{max=65536}={}) {
  const file=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
  try {
    const before=await file.stat();
    need(before.isFile()&&before.nlink===1&&before.uid===process.getuid()&&(before.mode&0o077)===0&&before.size<=max,'private_owned_regular_file_required');
    const raw=await file.readFile(),after=await file.stat(),named=await lstat(path);
    need(!named.isSymbolicLink()&&named.ino===before.ino&&named.dev===before.dev&&named.size===before.size&&named.mtimeMs===before.mtimeMs&&named.ctimeMs===before.ctimeMs&&after.ino===before.ino&&after.dev===before.dev&&after.size===before.size&&after.mtimeMs===before.mtimeMs&&after.ctimeMs===before.ctimeMs,'private_file_changed');
    return {raw,stat:after};
  } finally {await file.close();}
}
export async function privateWrite(path,value) {
  const raw=Buffer.from(canonical(value)+'\n');
  const file=await open(path,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);
  try{await file.writeFile(raw);await file.sync();}finally{await file.close();}
  const directory=await open(dirname(path),constants.O_RDONLY|constants.O_DIRECTORY);
  try{await directory.sync();}finally{await directory.close();}
  return sha(raw);
}
export class OperationJournal {
  constructor(root){this.root=root;}
  async ready(){await privateDirectory(this.root);return this;}
  async load(id) {
    uuid(id);const dir=join(this.root,id);
    try{await privateDirectory(dir);}catch(error){if(error.code==='ENOENT')return null;throw error;}
    const names=(await readdir(dir)).sort();need(names.length>0&&names.length<=100,'incomplete_operation_journal');
    let previous=null,intent=null,last=null;
    for(const [index,name]of names.entries()) {
      need(name===String(index+1).padStart(4,'0')+'.json','unexpected_operation_journal_entry');
      const {raw}=await privateRead(join(dir,name)),value=JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(raw));
      need(raw.equals(Buffer.from(canonical(value)+'\n'))&&value.request_id===id&&value.sequence===index+1&&value.previous_sha256===previous,'operation_journal_integrity_failed');
      need(canonical(value)===canonical(sanitized(value)),'persisted_permit_or_plaintext_refused');
      if(index===0){need(value.phase==='intent','original_intent_required');intent=value;}
      last=value;previous=sha(raw);
    }
    return {intent,last,sequence:names.length,last_sha256:previous};
  }
  async begin({action,args,session,authority}) {
    uuid(args.request_id);await this.ready();
    const id=args.request_id,dir=join(this.root,id);
    try{await mkdir(dir,{mode:0o700});}catch(error){if(error.code==='EEXIST')return {created:false,record:await this.load(id)};throw error;}
    const value={request_id:id,sequence:1,previous_sha256:null,phase:'intent',action,args:sanitized(args),args_sha256:sha(canonical(args)),operator_session:session,authority_sha256:sha(authority)};
    await privateWrite(join(dir,'0001.json'),value);
    return {created:true,record:await this.load(id)};
  }
  async append(id,status) {
    const record=await this.load(id);need(record,'original_intent_required');
    keys(status,['phase'],['receipt','error_code']);
    need(['unknown','rejected','resolved','not_observed'].includes(status.phase),'invalid_operation_phase');
    const value=sanitized({...status,request_id:id,sequence:record.sequence+1,previous_sha256:record.last_sha256});
    await privateWrite(join(this.root,id,String(value.sequence).padStart(4,'0')+'.json'),value);
    return this.load(id);
  }
}
