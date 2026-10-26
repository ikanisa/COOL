import net from 'node:net';
import {randomUUID} from 'node:crypto';
import {chmod,lstat,mkdir} from 'node:fs/promises';
import {join,dirname} from 'node:path';
import {OperatorError,need,keys,uuid,hash,sha,ORIGINS,hasFreshEmailVerification} from './contract.mjs';
import {privateDirectory,privateRead,privateWrite,OperationJournal} from './private_state.mjs';
import {OperatorClient} from './operator_client.mjs';

const SOCKET='operator.sock',DESCRIPTOR='broker.json',MAX_LINE=65536;
const safeError=error=>({code:error instanceof OperatorError?error.code:'local_transport_failed',outcome_unknown:error instanceof OperatorError&&error.outcomeUnknown});
function frames(socket,onMessage,onFailure) {
  let pending=Buffer.alloc(0),ended=false;
  socket.on('data',chunk=>{
    if(ended)return;
    try {
      pending=Buffer.concat([pending,chunk]);need(pending.length<=MAX_LINE,'ipc_message_too_large');
      for(let i;(i=pending.indexOf(10))>=0;) {
        const line=pending.subarray(0,i);pending=pending.subarray(i+1);need(line.length>0,'invalid_ipc_frame');
        let value;try{value=JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(line));}catch{throw new OperatorError('invalid_ipc_json');}
        onMessage(value);
      }
    } catch(error){ended=true;onFailure(error);socket.destroy();}
  });
  socket.on('end',()=>{if(pending.length)onFailure(new OperatorError('incomplete_ipc_frame'));});
}
const send=(socket,value)=>{need(!socket.destroyed,'ipc_disconnected');socket.write(JSON.stringify(value)+'\n');};
async function socketStat(path) {
  const stat=await lstat(path);
  need(stat.isSocket()&&!stat.isSymbolicLink()&&stat.uid===process.getuid()&&(stat.mode&0o077)===0,'private_owned_socket_required');return stat;
}
const sameFile=(a,b)=>a.dev===b.dev&&a.ino===b.ino&&a.size===b.size&&a.mtimeMs===b.mtimeMs&&a.ctimeMs===b.ctimeMs&&a.mode===b.mode;

export async function readConfig(path,expectedSha) {
  hash(expectedSha);await privateDirectory(dirname(path));
  const {raw}=await privateRead(path);need(sha(raw)===expectedSha,'reviewed_configuration_digest_required');
  const value=JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(raw));
  keys(value,['format','enabled','origin']);
  need(value.format==='collect.operator.client-config.v1'&&value.enabled===true&&ORIGINS.includes(value.origin),'independently_approved_configuration_required');
  return value;
}
export class BrokerServer {
  #server;#http;#client;#dir;#descriptor;#connections=new Set();#socketIdentity;#descriptorIdentity;
  constructor({stateDir,http,clock=Date.now}) {this.#dir=stateDir;this.#http=http;this.clock=clock;}
  #current(session,permission='assisted_sms.manage') {
    const current=this.#http.snapshot();
    need(current&&current.epoch===session?.epoch&&current.authority===session.authority&&current.emailVerifiedAt===session.emailVerifiedAt,'broker_authority_changed_during_call');
    need(hasFreshEmailVerification(session,this.clock())&&hasFreshEmailVerification(current,this.clock()),'fresh_verified_email_required');
    need(current.user.permissions.includes(permission),'permission_required');
  }
  async start() {
    await privateDirectory(this.#dir);need(process.cwd()===this.#dir,'private_socket_working_directory_required');
    const session=this.#http.snapshot();need(hasFreshEmailVerification(session,this.clock()),'fresh_verified_email_required');
    await this.#http.ensure(session.user.sessionId,'assisted_sms.manage');
    this.#current(session);
    const journalDir=join(this.#dir,'operations');await mkdir(journalDir,{mode:0o700});
    this.#client=new OperatorClient({http:this.#http,journal:await new OperationJournal(journalDir).ready(),clock:this.clock});
    this.#current(session);
    const instance=randomUUID();
    this.#descriptor={format:'collect.operator.session-broker.v1',origin:this.#http.origin,instance_id:instance,
      operator_session:session.user.sessionId,socket_relative_name:SOCKET,credentials_persisted:false,created_at:new Date(this.clock()).toISOString()};
    // No unlink/replacement of a pre-existing broker, stale session, socket or journal.
    try{await lstat(join(this.#dir,SOCKET));throw new OperatorError('existing_socket_refused');}catch(error){if(error.code!=='ENOENT')throw error;}
    this.#server=net.createServer(socket=>this.#accept(socket));
    await new Promise((resolve,reject)=>{this.#server.once('error',reject);this.#server.listen(SOCKET,resolve);});
    await chmod(join(this.#dir,SOCKET),0o600);this.#socketIdentity=await socketStat(join(this.#dir,SOCKET));
    const descriptorSha=await privateWrite(join(this.#dir,DESCRIPTOR),this.#descriptor);
    this.#descriptorIdentity=(await privateRead(join(this.#dir,DESCRIPTOR))).stat;
    this.#current(session);
    return {descriptor_path:join(this.#dir,DESCRIPTOR),descriptor_sha256:descriptorSha,...this.#descriptor};
  }
  async #unchanged() {
    const descriptor=await privateRead(join(this.#dir,DESCRIPTOR));
    need(sameFile(descriptor.stat,this.#descriptorIdentity),'broker_descriptor_replaced');
    need(sameFile(await socketStat(join(this.#dir,SOCKET)),this.#socketIdentity),'broker_socket_replaced');
    need(this.#http.snapshot()?.user.sessionId===this.#descriptor.operator_session,'broker_session_replaced');
  }
  #accept(socket) {
    this.#connections.add(socket);const active=new Map();let greeted=false;
    socket.on('error',()=>{});socket.on('close',()=>{this.#connections.delete(socket);for(const controller of active.values())controller.abort();});
    frames(socket,value=>{void (async()=>{
      let id;
      try {
        keys(value,['id','instance_id','operator_session','method'],['action','arguments','request_id']);
        id=uuid(value.id);need(!active.has(id),'duplicate_ipc_request');
        need(value.instance_id===this.#descriptor.instance_id&&value.operator_session===this.#descriptor.operator_session,'original_broker_session_required');
        await this.#unchanged();
        if(value.method==='hello') {
          need(!greeted&&!Object.hasOwn(value,'action')&&!Object.hasOwn(value,'arguments')&&!Object.hasOwn(value,'request_id'),'invalid_ipc_handshake');greeted=true;
          send(socket,{id,ok:true,result:{...this.#client.metadata(),instance_id:this.#descriptor.instance_id,operator_session:this.#descriptor.operator_session}});return;
        }
        need(greeted,'ipc_handshake_required');
        if(value.method==='cancel') {
          uuid(value.request_id);active.get(value.request_id)?.abort();send(socket,{id,ok:true,result:{cancel_requested:true}});return;
        }
        need(value.method==='call'&&typeof value.action==='string'&&!Object.hasOwn(value,'request_id'),'unsupported_ipc_method');
        need(value.arguments?.operator_session===this.#descriptor.operator_session,'original_broker_session_required');
        need(active.size<32,'ipc_concurrency_limit');
        const permission=value.action==='list_pending'?'assisted_sms.read':'assisted_sms.manage',controller=new AbortController();active.set(id,controller);
        let result,authority;
        try {
          // An explicit original-operation read may first settle unavailable
          // proof through GET readback. This never replays a verification or
          // mutation; the journal still requires the original authority hash.
          if(value.action==='get_operation'&&this.#http.snapshot()?.proofState!=='available') {
            await this.#http.ensure(value.arguments.operator_session,permission,{signal:controller.signal});
            await this.#unchanged();
          }
          authority=this.#http.snapshot();
          result=await this.#client.call(value.action,value.arguments,{signal:controller.signal});
        } finally {active.delete(id);}
        await this.#unchanged();need(!controller.signal.aborted,'request_cancelled');
        need(authority&&this.#http.snapshot()?.epoch===authority.epoch&&this.#http.snapshot()?.authority===authority.authority,'broker_authority_changed_during_call');
        this.#current(authority,permission);
        if(result?.may_send===true&&!(Date.parse(result.manual_handoff?.valid_until)>this.clock()))throw new OperatorError('handoff_expired',{unknown:true});
        // First-use permits exist only in this live response; there is no broker response cache.
        send(socket,{id,ok:true,result});
      } catch(error){if(id&&!socket.destroyed)send(socket,{id,ok:false,error:safeError(error)});else socket.destroy();}
    })();},()=>{});
  }
  async close(){for(const socket of this.#connections)socket.destroy();if(this.#server)await new Promise(resolve=>this.#server.close(resolve));this.#http.clear();}
}

export class BrokerConnector {
  #dir;#expected;#descriptor;#identity;#socketIdentity;#socket;#pending=new Map();#failed=false;#hello=null;
  constructor({stateDir,descriptorSha256}) {this.#dir=stateDir;this.#expected=hash(descriptorSha256);}
  async #unchanged() {
    await privateDirectory(this.#dir);
    const descriptor=await privateRead(join(this.#dir,DESCRIPTOR));need(sha(descriptor.raw)===this.#expected&&sameFile(descriptor.stat,this.#identity),'broker_descriptor_replaced');
    need(sameFile(await socketStat(join(this.#dir,SOCKET)),this.#socketIdentity),'broker_socket_replaced');
  }
  async connect() {
    need(!this.#socket&&!this.#failed,'broker_reconnection_refused');await privateDirectory(this.#dir);
    need(process.cwd()===this.#dir,'private_socket_working_directory_required');
    const {raw,stat}=await privateRead(join(this.#dir,DESCRIPTOR));need(sha(raw)===this.#expected,'reviewed_broker_descriptor_required');
    const descriptor=JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(raw));
    keys(descriptor,['format','origin','instance_id','operator_session','socket_relative_name','credentials_persisted','created_at']);
    need(descriptor.format==='collect.operator.session-broker.v1'&&ORIGINS.includes(descriptor.origin)&&descriptor.socket_relative_name===SOCKET&&descriptor.credentials_persisted===false,'invalid_broker_descriptor');uuid(descriptor.instance_id);uuid(descriptor.operator_session);
    this.#descriptor=descriptor;this.#identity=stat;this.#socketIdentity=await socketStat(join(this.#dir,SOCKET));
    this.#socket=net.createConnection(SOCKET);
    this.#socket.on('error',()=>this.#fail());this.#socket.on('close',()=>this.#fail());
    frames(this.#socket,value=>{
      try {
        keys(value,['id','ok'],value.ok===true?['result']:['error']);uuid(value.id);
        need(typeof value.ok==='boolean'&&(value.ok?Object.hasOwn(value,'result'):Object.hasOwn(value,'error')),'invalid_ipc_response');
        if(!value.ok){keys(value.error,['code','outcome_unknown']);need(/^[a-z_]{1,100}$/.test(value.error.code)&&typeof value.error.outcome_unknown==='boolean','invalid_ipc_error');}
        const pending=this.#pending.get(value.id);need(pending,'unexpected_ipc_response');this.#pending.delete(value.id);pending.finish();
        if(value.ok)pending.resolve(value.result);else pending.reject(new OperatorError(value.error.code,{unknown:value.error.outcome_unknown}));
      }catch{this.#fail();}
    },()=>this.#fail());
    await new Promise((resolve,reject)=>{this.#socket.once('connect',resolve);this.#socket.once('error',()=>reject(new OperatorError('broker_connection_failed')));});
    await this.#unchanged();this.#hello=await this.#request('hello');
    need(this.#hello.instance_id===descriptor.instance_id&&this.#hello.operator_session===descriptor.operator_session&&this.#hello.origin===descriptor.origin,'original_broker_session_required');
    return this.#hello;
  }
  metadata(){return this.#failed?{authentication_state:'broker_disconnected',operator_session:this.#descriptor?.operator_session??null,credentials_persisted:false,messages_automation:false}:this.#hello?structuredClone(this.#hello):{authentication_state:'unconfigured',operator_session:null,credentials_persisted:false,messages_automation:false};}
  #fail() {
    this.#failed=true;this.#socket?.destroy();
    for(const pending of this.#pending.values()){pending.finish();pending.reject(new OperatorError('broker_disconnected_outcome_unknown',{unknown:true}));}this.#pending.clear();
  }
  async #request(method,extra={},signal) {
    need(!this.#failed&&this.#socket&&!this.#socket.destroyed,'broker_reconnection_refused');await this.#unchanged();
    need(!signal?.aborted,'request_cancelled');const id=randomUUID();
    return new Promise((resolve,reject)=>{
      const cancel=()=>{
        // Keep the response slot until its acknowledgement arrives; never reconnect or replay.
        const cancelId=randomUUID();this.#pending.set(cancelId,{resolve:()=>{},reject:()=>{},finish:()=>{}});
        try{send(this.#socket,{id:cancelId,instance_id:this.#descriptor.instance_id,operator_session:this.#descriptor.operator_session,method:'cancel',request_id:id});}catch{this.#fail();}
      };
      const timer=setTimeout(()=>{this.#fail();},35000);
      this.#pending.set(id,{resolve,reject,finish:()=>{clearTimeout(timer);signal?.removeEventListener('abort',cancel);}});
      signal?.addEventListener('abort',cancel,{once:true});
      try{send(this.#socket,{id,instance_id:this.#descriptor.instance_id,operator_session:this.#descriptor.operator_session,method,...extra});}catch{this.#fail();}
    });
  }
  async call(action,args,{signal}={}) {
    need(this.#hello&&args?.operator_session===this.#descriptor.operator_session,'original_broker_session_required');
    const value=await this.#request('call',{action,arguments:args},signal);await this.#unchanged();
    need(!signal?.aborted,'request_cancelled');return value;
  }
  close(){this.#fail();}
}
