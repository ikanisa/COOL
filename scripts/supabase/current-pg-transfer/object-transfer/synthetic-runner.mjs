// Test-only child process: all input, including the fixture key, uses stdin.
import {transferObject} from './transfer.mjs';
import {syntheticAdapters} from './synthetic-http.mjs';
const chunks=[];let size=0;
for await(const c of process.stdin){size+=c.length;if(size>65536)throw Error('input_too_large');chunks.push(c);}
const input=JSON.parse(Buffer.concat(chunks).toString('utf8'));
const key=Buffer.from(input.journalKey,'base64url');
try{
 const adapters=syntheticAdapters(input.plan);
 const result=await transferObject({...input,...adapters,journalKey:key});
 process.stdout.write(JSON.stringify(result)+'\n');
}finally{key.fill(0);}
