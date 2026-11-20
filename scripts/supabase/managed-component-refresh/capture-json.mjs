// Structural duplicate-key and depth validation before parsing capture wire data.
// No response body or key is included in an error message.
export function assertUniqueJson(text,maximum=8*1024*1024){
 const fail=code=>{const e=new Error(code);e.code=code;throw e;};
 const need=(ok,code='CAPTURE_JSON_INVALID')=>{if(!ok)fail(code);};
 need(typeof text==='string'&&Number.isSafeInteger(maximum)&&maximum>0&&maximum<=8*1024*1024&&Buffer.byteLength(text)<=maximum);
 let at=0;const ws=()=>{while(at<text.length&&/[\x20\x09\x0a\x0d]/.test(text[at]))at++;};
 function str(){need(text[at]==='"');const start=at++;let escaped=false;
  while(at<text.length){const c=text[at++];if(escaped){escaped=false;continue;}if(c==='\\'){escaped=true;continue;}
   if(c==='"'){try{return JSON.parse(text.slice(start,at));}catch{fail('CAPTURE_JSON_INVALID');}}}fail('CAPTURE_JSON_INVALID');}
 function val(depth){need(depth<=64,'CAPTURE_JSON_DEPTH');ws();const c=text[at];
  if(c==='"'){str();return;}
  if(c==='{'){at++;ws();const keys=new Set();if(text[at]==='}'){at++;return;}
   for(;;){ws();const key=str();need(!keys.has(key),'CAPTURE_JSON_DUPLICATE_KEY');keys.add(key);ws();need(text[at++]===':');val(depth+1);ws();const end=text[at++];if(end==='}')return;need(end===',');}}
  if(c==='['){at++;ws();if(text[at]===']'){at++;return;}for(;;){val(depth+1);ws();const end=text[at++];if(end===']')return;need(end===',');}}
  const start=at;while(at<text.length&&!/[\x20\x09\x0a\x0d,\]}]/.test(text[at]))at++;
  need(at>start);try{JSON.parse(text.slice(start,at));}catch{fail('CAPTURE_JSON_INVALID');}}
 val(0);ws();need(at===text.length);
}
