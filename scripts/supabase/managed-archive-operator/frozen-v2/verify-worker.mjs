// No private input is read by this process.
import {verifyReviewedSourceManifest} from './source-manifest.mjs';
let out;
try{if(process.argv.length!==3)throw Error();out=await verifyReviewedSourceManifest(process.argv[2]);}
catch{out={status:'source_refused'};process.exitCode=1;}
try{await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify(out)+'\n',e=>e?reject(e):resolve()));}catch{process.exitCode=1;}
