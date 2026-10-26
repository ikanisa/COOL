import {fixture} from './http_fixture.mjs';
import {AdminHttp} from '../src/http_client.mjs';
import {BrokerServer} from '../src/broker.mjs';
import {ORIGINS} from '../src/contract.mjs';

const stateDir=process.argv[2];process.chdir(stateDir);const server=await fixture();
const http=new AdminHttp({origin:ORIGINS[0],fetchImpl:server.fetch,clock:()=>server.now,timeoutMs:2000});
const login=()=>server.login(http);
await login();const broker=new BrokerServer({stateDir,http,clock:()=>server.now});
const descriptor=await broker.start();process.send({event:'ready',descriptor,jobs:[server.first.id,server.second.id]});
let release;
process.on('message',message=>{void(async()=>{
  try {
    if(message.command==='fault_after')server.fault={action:message.action,after:true};
    else if(message.command==='hold')server.fault={action:message.action,gate:new Promise(resolve=>release=resolve),entered:()=>process.send({event:'entered'})};
    else if(message.command==='release')release?.();
    else if(message.command==='login')await login();
    else if(message.command==='reverify'){server.now+=1000;await server.reverify(http);}
    else if(message.command==='unknown_verify_old_readback') {
      const original=http.snapshot().emailVerifiedAt;server.now+=1000;
      const challenge=await http.requestEmailVerification(await server.emailProof('sensitive'));
      server.authFault='/api/admin/auth/email/verify';let unknown=false;
      try{await http.verifyEmail(challenge.challenge_id,server.code);}catch(error){unknown=error.outcomeUnknown===true;}
      if(!unknown)throw new Error('synthetic_unknown_verification_required');
      server.authTransform=(path,value)=>path==='/api/admin/auth/email-verification'?{...value,emailVerifiedAt:original}:value;
    }
    else if(message.command==='reveal_current_proof')server.authTransform=null;
    else if(message.command==='advance')server.now+=message.milliseconds;
    else if(message.command==='stats'){}
    else if(message.command==='close'){await broker.close();await server.close();process.send({id:message.id,ok:true});process.disconnect();return;}
    else throw new Error('unsupported_fixture_control');
    process.send({id:message.id,ok:true,counts:server.counts,effects:server.effectCounts});
  }catch{process.send({id:message.id,ok:false});}
})();});
process.on('disconnect',()=>{void broker.close().finally(()=>server.close());});
