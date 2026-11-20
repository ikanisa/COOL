// In-process static-JPEG admission and byte-preserving OpenAI image packaging.
// This is not a pixel decoder, network service, or proof of image legibility.
import {classifyRosterImage} from './roster_image_policy.mjs';

export const NATIVE_JPEG_PROTOCOL='collect-native-jpeg-v1';
export const NATIVE_JPEG_IDENTITY='urn:collect:decoder:native-jpeg:v1';
const LOGICAL_URL='https://roster-decoder.internal/decode'; // Existing local Request envelope only; never fetched.
const SHA=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const LIMIT=5*1024*1024,REQUEST_LIMIT=8*1024*1024;
const branded=new WeakSet();
const fail=()=>{throw new Error('roster_native_jpeg_invalid');};
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).length===keys.length&&keys.every(key=>Object.hasOwn(value,key));
const hash=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',value)),
  byte=>byte.toString(16).padStart(2,'0')).join('');
async function bounded(request){
  const declared=request.headers.get('content-length');
  if(declared!==null&&(!/^[0-9]+$/.test(declared)||Number(declared)>REQUEST_LIMIT))fail();
  const reader=request.body?.getReader();if(!reader)fail();let length=0,done=false;const chunks=[];
  const abort=()=>{void reader.cancel(request.signal.reason).catch(()=>{});};
  request.signal.addEventListener('abort',abort,{once:true});
  try{
    while(true){
      request.signal.throwIfAborted();const part=await reader.read();request.signal.throwIfAborted();
      if(part.done){done=true;break;}
      if(!(part.value instanceof Uint8Array)||part.value.length>REQUEST_LIMIT-length)fail();
      length+=part.value.length;chunks.push(part.value);
    }
    if(declared!==null&&Number(declared)!==length)fail();
    const bytes=new Uint8Array(length);let offset=0;
    for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    try{return JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(bytes));}finally{bytes.fill(0);}
  }finally{
    request.signal.removeEventListener('abort',abort);
    if(!done)await reader.cancel().catch(()=>{});
    reader.releaseLock();for(const chunk of chunks)chunk.fill(0);
  }
}
export function isNativeRosterJpegDecoder(value){return branded.has(value);}
export function createNativeRosterJpegDecoder({protocol,identity,approvedBuildSha256,secret}={}){
  if(protocol!==NATIVE_JPEG_PROTOCOL||identity!==NATIVE_JPEG_IDENTITY||!SHA.test(approvedBuildSha256??'')||
    secret!==undefined&&secret!=='')fail();
  const port=Object.freeze({identity:NATIVE_JPEG_IDENTITY,protocol:NATIVE_JPEG_PROTOCOL,buildSha256:approvedBuildSha256,
    async fetch(request,context){
      if(!(request instanceof Request)||![NATIVE_JPEG_IDENTITY,LOGICAL_URL].includes(request.url)||request.method!=='POST'||
        request.headers.get('content-type')?.split(';',1)[0].trim()!=='application/json'||
        !exact(context,['requestId','reservationId'])||!UUID.test(context.requestId??'')||!UUID.test(context.reservationId??''))fail();
      const value=await bounded(request);
      if(!exact(value,['schema_version','source_sha256','decoder_build_sha256','mime_type','content_base64'])||
        value.schema_version!==1||!SHA.test(value.source_sha256??'')||value.decoder_build_sha256!==approvedBuildSha256||
        value.mime_type!=='image/jpeg'||typeof value.content_base64!=='string'||!value.content_base64.length||
        value.content_base64.length%4||value.content_base64.length>4*Math.ceil(LIMIT/3)||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(value.content_base64))fail();
      let binary;try{binary=atob(value.content_base64);}catch{fail();}
      if(binary.length<1||binary.length>LIMIT||btoa(binary)!==value.content_base64)fail();
      const bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
      try{
        request.signal.throwIfAborted();
        if(await hash(bytes)!==value.source_sha256||classifyRosterImage(bytes,'image/jpeg')!=='static')fail();
        request.signal.throwIfAborted();
        // Exactly the source bytes validated above, not a fabricated/re-encoded image.
        return Response.json({source_sha256:value.source_sha256,decoder_build_sha256:approvedBuildSha256,
          content:[{type:'input_image',image_url:'data:image/jpeg;base64,'+value.content_base64}]});
      }finally{bytes.fill(0);}
    }});
  branded.add(port);return port;
}
