// Bounded streaming inspection of pg_restore --list. It retains only selected
// schema flags and byte counts, never table names, SQL, or complete TOC output.
export const MAX_TOC_BYTES=8*1024*1024,MAX_TOC_LINE_BYTES=16*1024;
const SCHEMAS=new Set(['app','private','collect_sms','auth','storage','supabase_migrations']);
export class TocError extends Error{constructor(code){super(code);this.name='TocError';this.code=code;}}
const fail=c=>{throw new TocError(c);};
export function createTocScanner(){
 let pending=Buffer.alloc(0),total=0,ended=false;const schemas=new Set();
 function line(b){const m=/^[0-9]+;\s+[0-9]+\s+[0-9]+\s+SCHEMA\s+-\s+(app|private|collect_sms|auth|storage|supabase_migrations)\s+\S/.exec(b.toString('utf8'));if(m)schemas.add(m[1]);}
 function append(part){if(pending.length+part.length>MAX_TOC_LINE_BYTES)fail('toc_line_bound_exceeded');const old=pending;pending=Buffer.concat([old,part]);old.fill(0);}
 return {
  push(chunk){if(ended||!Buffer.isBuffer(chunk))fail('toc_input_refused');total+=chunk.length;if(!Number.isSafeInteger(total)||total>MAX_TOC_BYTES)fail('toc_bound_exceeded');
   let start=0;for(;;){const i=chunk.indexOf(10,start);if(i<0)break;append(chunk.subarray(start,i));line(pending);pending.fill(0);pending=Buffer.alloc(0);start=i+1;}
   if(start<chunk.length)append(chunk.subarray(start));
  },
  finish(required){if(ended||!Array.isArray(required)||required.some(x=>!SCHEMAS.has(x)))fail('toc_input_refused');ended=true;
   if(pending.length)line(pending);pending.fill(0);pending=Buffer.alloc(0);if(required.some(x=>!schemas.has(x)))fail('required_schemas_missing');return {bytes:total};
  },
  clear(){pending.fill(0);pending=Buffer.alloc(0);ended=true;}
 };
}
