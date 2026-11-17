// Subprocess used exclusively by lifecycle regressions; all data is synthetic.
import {startOwnedPg17} from './owned-pg17.mjs';
const mode=process.argv[2];
const onPhase=(phase,detail)=>process.stdout.write(JSON.stringify({phase,...detail})+'\n');
try{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'collect_fixture',onPhase,
  afterInitdbSpawn:mode==='initdb-signal'?()=>new Promise(()=>{}):undefined,
  beforeReady:mode==='startup-signal'?()=>new Promise(()=>{}):mode==='startup-failure'?()=>{throw Error('synthetic readiness failure');}:undefined,
  forceUnconfirmedStop:mode==='stop-unconfirmed'});
 if(mode==='stop-unconfirmed'){
  const result=await f.close();process.stdout.write(JSON.stringify({phase:'closed',...result,pid:f.serverPid})+'\n');
 }else await new Promise(()=>{});
}catch(e){
 process.stdout.write(JSON.stringify({phase:'failed',code:e?.code,root:e?.root})+'\n');
}
