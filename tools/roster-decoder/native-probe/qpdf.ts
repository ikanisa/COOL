import createQpdf from './vendor/parser.js';
const output=[];const errorOutput=[];
const wasmUrl=URL.createObjectURL(new Blob([await Deno.readFile(new URL('./vendor/parser.wasm',import.meta.url))],{type:'application/wasm'}));
const lib=await createQpdf({locateFile:()=>wasmUrl,noInitialRun:true,print:x=>output.push(String(x)),printErr:x=>errorOutput.push(String(x))});
async function isolation(){const results={};for(const [name,call]of [['network',()=>fetch('http://127.0.0.1:9/')],['environment',()=>Deno.env.get('QUAL_ISOLATION_SENTINEL')],['file_read',()=>Deno.readTextFile('/etc/hostname')],['file_write',()=>Deno.writeTextFile('/tmp/collect-roster-probe-forbidden','probe')],['run',()=>new Deno.Command('/bin/true').output()]]){try{await call();results[name]='ALLOWED';}catch(e){results[name]=e.name;}}return results;}
const bytes=body=>Uint8Array.from(atob(body.base64),v=>v.charCodeAt(0));
const check=(v,code)=>{if(!v)throw Error(code);};
Deno.serve(async request=>{const body=await request.json();const denied=await isolation();try{
 const data=bytes(body);check(data.length>0&&data.length<=5*1024*1024,'source_limit');lib.FS.writeFile('/input.pdf',data);
 if(body.version){const code=lib.callMain(['--version']);return Response.json({ok:code===0,code,output:lib.diagnostics.join('\n'),isolation:denied});}
 const code=lib.callMain(['--json-output=2','--json-key=qpdf','--json-key=pages','--json-key=encrypt','--json-stream-data=file','--json-stream-prefix=/stream','--decode-level=generalized','/input.pdf','/output.json']);
 check(code===0&&lib.diagnostics.length===0,'pdf_warning_or_error');
 const size=lib.FS.stat('/output.json').size;check(size<=16*1024*1024,'json_expansion_limit');const metadata=JSON.parse(new TextDecoder().decode(lib.FS.readFile('/output.json')));
 check(metadata.qpdf?.[0]?.jsonversion===2,'json_version');check(metadata.encrypt?.encrypted===false,'encrypted');
 check(Array.isArray(metadata.pages)&&metadata.pages.length>=1&&metadata.pages.length<=20,'page_limit');
 const objects=metadata.qpdf[1],names=Object.keys(objects);check(names.length-1<=5000,'object_limit');const visited=new Set();let events=0,streams=0,expanded=0;
 const inspect=(value,depth=0)=>{check(++events<=100000&&depth<=40,'object_limit');
  if(typeof value==='string'&&/^[0-9]+ [0-9]+ R$/.test(value)){if(visited.has(value))return;visited.add(value);const obj=objects['obj:'+value];if(obj)inspect(obj.value??obj.stream?.dict,depth+1);return;}
  if(!value||typeof value!=='object')return;if(Array.isArray(value)){for(const v of value)inspect(v,depth+1);return;}
  check(!['/JavaScript','/JS','/EmbeddedFiles','/Launch','/AA'].some(k=>Object.hasOwn(value,k))&&!['/JavaScript','/Launch','/SubmitForm','/ImportData'].includes(value['/S']),'active_content');
  for(const[k,v]of Object.entries(value))if(k!=='/Parent')inspect(v,depth+1);
 };
 for(const name of names){const entry=objects[name];inspect(entry.value??entry.stream?.dict);if(entry.stream){check(++streams<=2000,'stream_limit');const file=entry.stream.datafile;check(typeof file==='string'&&/^\/stream-[0-9]+$/.test(file),'stream_file_identity');const n=lib.FS.stat(file).size;
   if(!['/DCTDecode','/JPXDecode','/JBIG2Decode','/CCITTFaxDecode'].includes(entry.stream.dict['/Filter'])){expanded+=n;check(expanded<=32*1024*1024,'stream_expansion_limit');}
  }}
 return Response.json({ok:true,objects:names.length-1,pages:metadata.pages.length,streams,expanded_bytes:expanded,isolation:denied});
 }catch(e){return Response.json({ok:false,error:String(e).slice(0,200),diagnostic_count:lib.diagnostics.length,isolation:denied},{status:422});}});
