// Explicitly invoked by lifecycle.test.mjs; not an ordinary CI test file.
import {test} from 'node:test';
import {startOwnedPg17} from './owned-pg17.mjs';
test('held synthetic PostgreSQL fixture',async()=>{
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'collect_fixture',
  beforeReady:process.env.COLLECT_FIXTURE_STARTUP_GATE==='1'?()=>new Promise(()=>{}):undefined,
  onPhase:(phase,detail)=>{if(['server_spawned','ready'].includes(phase))process.stdout.write('FIXTURE_EVENT '+JSON.stringify({phase,...detail})+'\n');}});
 try{await new Promise(()=>{});}finally{await fixture.close();}
});
