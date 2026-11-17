import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// Execute actual extracted migration functions and triggers with synthetic
// temp relations in an in-process PostgreSQL. This does not prove a race or
// the full production migration; the separate reviewed race harness does that.
const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
test('parsed-before-hold scope and final financial boundaries fail closed',{skip:!modulePath},async()=>{
 const generated=execFileSync(process.execPath,[fileURLToPath(new URL('./generate-held-recovery-temp-fixture.mjs',import.meta.url))],{encoding:'utf8'});
 const end=generated.indexOf('-- The fixture mirrors');assert(end>0);
 const {PGlite}=await import(modulePath);const db=new PGlite();
 try{await db.exec(generated.slice(0,end)+'\nROLLBACK;');}finally{await db.close();}
});
