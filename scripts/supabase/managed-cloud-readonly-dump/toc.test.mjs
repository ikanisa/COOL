import test from 'node:test';
import assert from 'node:assert/strict';
import {createTocScanner,MAX_TOC_BYTES,MAX_TOC_LINE_BYTES,TocError} from './toc.mjs';
const code=x=>e=>e instanceof TocError&&e.code===x;
test('streams a realistic TOC larger than the old 512 KiB limit across arbitrary chunks',()=>{
 const lines=['12; 2615 2200 SCHEMA - app postgres\n','13; 2615 2201 SCHEMA - auth postgres\n'];
 for(let i=0;i<9000;i++)lines.push(`${100+i}; 1259 ${30000+i} TABLE app synthetic_collection_record_${String(i).padStart(6,'0')}_with_long_name postgres\n`);
 const data=Buffer.from(lines.join('')),scanner=createTocScanner();assert(data.length>512*1024&&data.length<MAX_TOC_BYTES);
 try{for(let p=0;p<data.length;p+=257)scanner.push(data.subarray(p,p+257));assert.deepEqual(scanner.finish(['app','auth']),{bytes:data.length});}
 finally{data.fill(0);scanner.clear();}
});
test('refuses missing schemas, oversized output and excessively long lines',()=>{
 const a=createTocScanner();a.push(Buffer.from('1; 2615 20 SCHEMA - app postgres\n'));assert.throws(()=>a.finish(['app','storage']),code('required_schemas_missing'));a.clear();
 const b=createTocScanner();assert.throws(()=>b.push(Buffer.alloc(MAX_TOC_LINE_BYTES+1,65)),code('toc_line_bound_exceeded'));b.clear();
 const c=createTocScanner();const chunk=Buffer.from(('x'.repeat(127)+'\n').repeat(512));try{for(let n=0;n<MAX_TOC_BYTES/chunk.length;n++)c.push(chunk);assert.throws(()=>c.push(Buffer.from('\n')),code('toc_bound_exceeded'));}finally{chunk.fill(0);c.clear();}
});
