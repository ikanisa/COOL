// Structural validation only; the original response is retained opaque.
import {assertUniqueJson} from '../managed-component-refresh/capture-json.mjs';
import {CaptureError,MAX_BODY} from './seal.mjs';
const need=(ok)=>{if(!ok)throw new CaptureError('UNSUPPORTED_PROVIDER_BODY');};
export function inspectMultipart(body,contentType){
 need(Buffer.isBuffer(body)&&body.length>0&&body.length<=MAX_BODY&&typeof contentType==='string'&&contentType.length<=256);
 const m=/^multipart\/form-data\s*;\s*boundary=(?:"([A-Za-z0-9'()+_,.\/:=?-]{1,70})"|([A-Za-z0-9'()+_,.\/:=?-]{1,70}))\s*$/i.exec(contentType);
 need(m);const boundary=m[1]??m[2],open=Buffer.from('--'+boundary+'\r\n'),marker=Buffer.from('\r\n--'+boundary),separator=Buffer.from('\r\n\r\n');
 need(body.subarray(0,open.length).equals(open));let pos=open.length,files=0,metadata=0,parts=0;
 while(true){
  need(++parts<=512);const hEnd=body.indexOf(separator,pos);need(hEnd>=pos&&hEnd-pos<=8192);
  const headerBytes=body.subarray(pos,hEnd);need(headerBytes.length>0&&!headerBytes.some(x=>x>127||x===0));
  const headers={};for(const line of headerBytes.toString('ascii').split('\r\n')){const colon=line.indexOf(':');need(colon>0);const k=line.slice(0,colon).trim().toLowerCase(),v=line.slice(colon+1).trim();need(/^[a-z0-9-]+$/.test(k)&&!Object.hasOwn(headers,k));headers[k]=v;}
  const disposition=/^form-data;\s*name="([^"\r\n]{1,256})"(?:;\s*filename="([^"\r\n]{1,1024})")?$/i.exec(headers['content-disposition']??'');need(disposition);
  const start=hEnd+separator.length;let next=body.indexOf(marker,start);
  while(next>=0){const suffix=next+marker.length;if((body[suffix]===45&&body[suffix+1]===45)||(body[suffix]===13&&body[suffix+1]===10))break;next=body.indexOf(marker,next+1);}
  need(next>=start);const length=next-start;
  if(disposition[2]!==undefined){need(length>0);files++;}
  else if(disposition[1]==='metadata'){
   need(++metadata===1&&length>0&&length<=65536);let parsed;
   try{const s=new TextDecoder('utf-8',{fatal:true}).decode(body.subarray(start,next));assertUniqueJson(s,65536);parsed=JSON.parse(s);}catch{throw new CaptureError('UNSUPPORTED_PROVIDER_BODY');}
   need(parsed&&typeof parsed==='object'&&!Array.isArray(parsed));
  }
  const end=next+marker.length;if(body[end]===45&&body[end+1]===45){const rest=body.subarray(end+2);need(rest.length===0||rest.equals(Buffer.from('\r\n')));break;}
  need(body[end]===13&&body[end+1]===10);pos=end+2;
 }
 need(metadata===1&&files>0);return {contentType:'multipart/form-data; boundary='+boundary,fileCount:files};
}
