import {fstatSync} from 'node:fs';
export async function readPrivateInput(){
 const s=fstatSync(0);if(process.stdin.isTTY||!(s.isFIFO()||s.isSocket()))throw Error('input_refused');
 return new Promise((resolve,reject)=>{let chunks=[],size=0,done=false;
  const finish=bad=>{if(done)return;done=true;clearTimeout(timer);process.stdin.removeListener('data',data);process.stdin.removeListener('end',end);process.stdin.removeListener('error',error);process.stdin.removeListener('close',error);
   if(bad){for(const b of chunks)b.fill(0);chunks=[];process.stdin.destroy();reject(Error('input_refused'));return;}
   const b=Buffer.concat(chunks);for(const x of chunks)x.fill(0);chunks=[];
   try{const raw=new TextDecoder('utf-8',{fatal:true}).decode(b),v=JSON.parse(raw);if(JSON.stringify(v)!==raw)throw Error();resolve(v);}catch{reject(Error('input_refused'));}finally{b.fill(0);}
  };
  const data=b=>{size+=b.length;if(size>32768){b.fill(0);finish(true);}else chunks.push(b);},end=()=>finish(false),error=()=>finish(true);
  const timer=setTimeout(()=>finish(true),5000);process.stdin.on('data',data);process.stdin.on('end',end);process.stdin.on('error',error);process.stdin.on('close',error);
 });
}
