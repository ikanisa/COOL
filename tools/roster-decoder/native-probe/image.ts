// Compare default decoding with explicit warning/APNG handling. Neither is an
// accepted production parser. Only the pinned public synthetic corpus is used.
import {initializeImageMagick,ImageMagick,MagickFormat,ResourceLimits,MagickImage,MagickReadSettings}from './vendor/parser.js';
await initializeImageMagick(await Deno.readFile(new URL('./vendor/parser.wasm',import.meta.url)));
ResourceLimits.width=16000n;ResourceLimits.height=16000n;ResourceLimits.area=16000000n;
ResourceLimits.listLength=20n;ResourceLimits.disk=0n;ResourceLimits.memory=256n*1024n*1024n;ResourceLimits.time=4n;
async function isolation(){
 const results={};
 for(const[name,call]of [['network',()=>fetch('http://127.0.0.1:9/')],
  ['environment',()=>Deno.env.get('QUAL_ISOLATION_SENTINEL')],
  ['file_read',()=>Deno.readTextFile('/etc/hostname')],
  ['file_write',()=>Deno.writeTextFile('/tmp/collect-roster-probe-forbidden','probe')],
  ['run',()=>new Deno.Command('/bin/true').output()]]){
  try{await call();results[name]='ALLOWED';}catch(error){results[name]=error.name;}
 }
 return results;
}
const check=(condition,code)=>{if(!condition)throw Error(code);};
Deno.serve(async request=>{
 const body=await request.json(),denied=await isolation();
 try{
  check(['Jpeg','Png','WebP','APng'].includes(body.format),'probe_format');
  check(typeof body.strict==='boolean','probe_mode');
  const data=Uint8Array.from(atob(body.base64),value=>value.charCodeAt(0));
  check(data.length>0&&data.length<=5*1024*1024,'input_limit');
  if(body.strict&&body.format==='Jpeg'){
   const image=MagickImage.create();let warning=false;
   try{image.onWarning=()=>{warning=true;};image.read(data,new MagickReadSettings({format:MagickFormat.Jpeg}));check(!warning,'jpeg_decode_warning');}
   finally{image.dispose();}
  }
  const summary=ImageMagick.readCollection(data,MagickFormat[body.format],images=>{
   check(images.length>=1&&images.length<=20,'frame_limit');let pixels=0;
   for(const image of images){
    check(image.width>0&&image.width<=16000&&image.height>0&&image.height<=16000,'dimensions');
    pixels+=image.width*image.height;check(pixels<=16000000,'pixel_limit');
    image.getPixels(values=>check(values.toByteArray(0,0,image.width,image.height,'RGBA')?.length===image.width*image.height*4,'pixel_materialization'));
   }
   return{frames:images.length,pixels};
  });
  return Response.json({ok:true,...summary,isolation:denied});
 }catch(error){return Response.json({ok:false,error:String(error).slice(0,200),isolation:denied},{status:422});}
});
