// Owned-fixture test only: finish a synthetic dump and suppress the response.
import {executeReadOnlyDump} from './execute.mjs';
let raw='';process.stdin.setEncoding('utf8');process.stdin.on('data',s=>{raw+=s;if(raw.length>65536)process.exit(2);});
process.stdin.on('end',async()=>{try{const {request,planSha256}=JSON.parse(raw);if(request.mode!=='synthetic')process.exit(2);await executeReadOnlyDump(request,planSha256);}catch{process.exitCode=1;}});
