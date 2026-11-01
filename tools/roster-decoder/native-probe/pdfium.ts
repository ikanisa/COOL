import {PDFiumLibrary}from './vendor/parser.js';
const lib=await PDFiumLibrary.init({wasmBinary:await Deno.readFile(new URL('./vendor/parser.wasm',import.meta.url))});
async function isolation(){const results={};for(const [name,call]of [['network',()=>fetch('http://127.0.0.1:9/')],['environment',()=>Deno.env.get('QUAL_ISOLATION_SENTINEL')],['file_read',()=>Deno.readTextFile('/etc/hostname')],['file_write',()=>Deno.writeTextFile('/tmp/collect-roster-probe-forbidden','probe')],['run',()=>new Deno.Command('/bin/true').output()]]){try{await call();results[name]='ALLOWED';}catch(e){results[name]=e.name;}}return results;}
const bytes=body=>Uint8Array.from(atob(body.base64),v=>v.charCodeAt(0));
const check=(v,code)=>{if(!v)throw Error(code);};
Deno.serve(async request=>{const body=await request.json();const denied=await isolation();let doc;try{
 doc=await lib.loadDocument(bytes(body));check(doc.getPageCount()>=1&&doc.getPageCount()<=20,'page_limit');let pixels=0,pages=0;for(const page of doc.pages()){try{const image=await page.render({scale:4/3,render:async x=>x.data,renderFormFields:false});pixels+=image.width*image.height;check(pixels<=16000000,'pixel_limit');check(image.data.length===image.width*image.height*4,'raster_bytes');pages++;}finally{page.close();}}return Response.json({ok:true,pages,pixels,isolation:denied});
 }catch(e){return Response.json({ok:false,error:String(e).slice(0,200),isolation:denied},{status:422});}finally{doc?.destroy();}});
