import {fstatSync} from 'node:fs';
const MAX=32768;
export async function readPrivateInput(){
 const st=fstatSync(0);if(process.stdin.isTTY||!(st.isFIFO()||st.isSocket()))throw Error('input_refused');
 return new Promise((resolve,reject)=>{let chunks=[],bytes=0,finished=false;
  const finish=(error)=>{if(finished)return;finished=true;clearTimeout(timer);process.stdin.removeListener('data',onData);process.stdin.removeListener('end',onEnd);process.stdin.removeListener('error',onError);process.stdin.removeListener('close',onClose);
   if(error){for(const b of chunks)b.fill(0);chunks=[];process.stdin.destroy();reject(Error('input_refused'));return;}
   const b=Buffer.concat(chunks);for(const x of chunks)x.fill(0);chunks=[];
   try{const raw=new TextDecoder('utf-8',{fatal:true}).decode(b),data=JSON.parse(raw);if(JSON.stringify(data)!==raw)throw Error();resolve(data);}catch{reject(Error('input_refused'));}finally{b.fill(0);}
  };
  const onData=b=>{bytes+=b.length;if(bytes>MAX){b.fill(0);finish(true);}else chunks.push(b);},onEnd=()=>finish(false),onError=()=>finish(true),onClose=()=>finish(true);
  const timer=setTimeout(()=>finish(true),5000);process.stdin.on('data',onData);process.stdin.on('end',onEnd);process.stdin.on('error',onError);process.stdin.on('close',onClose);
 });
}
