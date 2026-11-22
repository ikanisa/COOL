// Credentials and opaque bodies stay in this supervised child, never argv/env.
import {Socket} from 'node:net';
import {captureManaged,captureSynthetic} from './core.mjs';
import {captureStatus,verifyCapture} from './offline.mjs';
import {fixtureTransport} from './fixture.mjs';
const controller=new AbortController();let watchdog,finished=false,exitTimer,fixture;
function disconnected(){if(finished)return;controller.abort();exitTimer??=setTimeout(()=>process.exit(1),2000);}
process.on('SIGTERM',()=>controller.abort());process.on('SIGINT',()=>controller.abort());
try{watchdog=new Socket({fd:3,readable:true,writable:true});watchdog.on('end',disconnected);watchdog.on('close',disconnected);watchdog.on('error',disconnected);}catch{process.stdout.write(JSON.stringify({status:'worker_outcome_unconfirmed',retryAuthorized:false}));process.exit(1);}
let chunks=[],size=0;
process.stdin.on('data',b=>{size+=b.length;if(size>65536){b.fill(0);process.exit(1);}chunks.push(b);});
process.stdin.on('error',()=>controller.abort());
process.stdin.on('end',async()=>{
 let input;try{
  const b=Buffer.concat(chunks);for(const x of chunks)x.fill(0);chunks=[];try{input=JSON.parse(b.toString('utf8'));}finally{b.fill(0);}
  if(!input||Object.keys(input).sort().join(',')!=='action,expectedPlanSha256,plan'||!['capture','status','verify'].includes(input.action))throw Error();const plan=input.plan;
  let result;if(input.action==='status')result=await captureStatus({plan,expectedPlanSha256:input.expectedPlanSha256});
  else if(input.action==='verify')result=await verifyCapture({plan,expectedPlanSha256:input.expectedPlanSha256});
  else if(plan?.scope==='synthetic'){fixture=fixtureTransport(plan.fixture,controller.signal);result=await captureSynthetic({plan,expectedPlanSha256:input.expectedPlanSha256,transport:fixture.transport,signal:controller.signal});}
  else result=await captureManaged({plan,expectedPlanSha256:input.expectedPlanSha256,signal:controller.signal});
  process.stdout.write(JSON.stringify(input.action==='capture'?{status:'completed_point_in_time',...result,retryAuthorized:false}:result));
 }catch{process.stdout.write(JSON.stringify({status:'worker_outcome_unconfirmed',retryAuthorized:false}));process.exitCode=1;}
 finally{finished=true;if(exitTimer)clearTimeout(exitTimer);watchdog?.destroy();for(const x of chunks)x.fill(0);for(const b of fixture?.bodies??[])b.fill(0);input=null;}
});
